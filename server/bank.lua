--[[
  server/bank.lua — sovereign_banking, the money backend (design §1.3).

  The ONLY module that calls exports.sovereign_banking. The "ranch ledger"
  IS the ranch's bank business account — realestate calls RegisterBusiness
  at purchase (ranch is a business class), so every owned ranch has one. No
  script-side balance column, no double bookkeeping, no tax engine here.

  Contract: amounts are integer minor units (cents); every mutating call
  returns (ok, resultOrErrorCode) and never throws. Mutations pass opts.idem
  so a retry can't double-charge — the bank no-ops replays by key.

  ⚠️ Build ruling (Phase 0, resolves design §14.5): RunPayroll accepts a
  SOCIETY id only — Society.get reads Config.Societies, and business
  accounts (owner_type='business') are not societies. Ranch payroll in
  Phase 5 therefore needs either a small banking export
  (RunBusinessPayroll) or per-hand account transfers. Bank.runPayroll below
  is written against the business-aware export and reports BANKING until it
  exists — the Phase 5 decision point is documented in the changelog.
]]

Bank = {}

local BANK = 'sovereign_banking'
local Err = Enums.Err

local function bankStarted()
  return GetResourceState(BANK) == 'started'
end

Bank.available = bankStarted

--- Uniform pcall wrapper around a bank export. Returns whatever the export
--- returns on success, or nil on a missing bank / thrown error.
local function call(fn, ...)
  if not bankStarted() then
    Log.warn('bank: %s skipped — %s is not started', fn, BANK)
    return nil
  end
  -- Explicit-self proxy call (the suite rule — index-form calls shift every
  -- argument left by one).
  local proxy = exports[BANK]
  local packed = { pcall(function(...) return proxy[fn](proxy, ...) end, ...) }
  if not packed[1] then
    Log.error('bank: %s errored: %s', fn, tostring(packed[2]))
    return nil
  end
  table.remove(packed, 1)
  return table.unpack(packed)
end

-- Every ranch-tied movement carries a MEMO naming the ranch (the realestate
-- ledger idiom): `reason` stays the stable category the bank filters by;
-- `memo` is the human statement line, e.g. 'ranch_livestock_sale — bla_ranch_01'.
local function memoTag(reason, ident)
  return ('%s — %s'):format(reason, ident)
end
Bank.memoTag = memoTag

-- ============================================================================
-- The ranch business account
-- ============================================================================

--- The ranch's business account row { id, ... } or nil. bizKey comes from
--- the property (bank_business_key or ident — realestate registers with
--- exactly that fallback).
function Bank.businessAccount(bizKey)
  return call('GetBusinessAccount', bizKey)
end

--- Account balance in cents, or nil when the account is missing. Column
--- name per banking Constants.CurrencyColumn: currency 0 → balance_money.
function Bank.businessBalance(bizKey)
  local acct = Bank.businessAccount(bizKey)
  if not acct then return nil end
  return tonumber(acct.balance_money) or 0
end

--- Is this charid the registered owner (or granted admin) of the account?
function Bank.isBusinessOwner(charid, bizKey)
  return call('IsBusinessOwner', tostring(charid), bizKey) == true
end

--- Credit the ranch account (livestock/goods sale proceeds). Returns (ok, err).
function Bank.credit(bizKey, cents, reason, idem, ident)
  cents = math.floor(tonumber(cents) or 0)
  if cents <= 0 then return false, Err.BAD_AMOUNT end
  local acct = Bank.businessAccount(bizKey)
  if not acct then return false, Err.BANKING end
  -- AddMoney with opts.target = accountId routes to the business account;
  -- the charid argument is unused on the account path but must be present.
  local ok, res = call('AddMoney', '0', Config.Currency, cents,
    { target = acct.id, reason = reason, idem = idem,
      memo = ident and memoTag(reason, ident) or nil })
  if ok == nil then return false, Err.BANKING end
  return ok, res
end

--- Debit the ranch account (livestock purchases, withdrawals). Fails clean
--- on ERR_INSUFFICIENT_FUNDS. Returns (ok, err).
function Bank.debit(bizKey, cents, reason, idem, ident)
  cents = math.floor(tonumber(cents) or 0)
  if cents <= 0 then return false, Err.BAD_AMOUNT end
  local acct = Bank.businessAccount(bizKey)
  if not acct then return false, Err.BANKING end
  local ok, res = call('RemoveMoney', '0', Config.Currency, cents,
    { target = acct.id, reason = reason, idem = idem,
      memo = ident and memoTag(reason, ident) or nil })
  if ok == nil then return false, Err.BANKING end
  return ok, res
end

--- Pay a character's wallet from thin air is FORBIDDEN — every payout is a
--- transfer out of the ranch account (Bank.debit) paired with an AddMoney,
--- or the Phase 5 payroll below. Wallet-side helper for market flows where
--- the counterparty is a player selling TO the ranch (none in v1).

-- ============================================================================
-- Payroll (Phase 5 — seam declared now, see the header ruling)
-- ============================================================================

--- Atomic batch payroll from the ranch account into hands' bank accounts.
--- payrollTable = { { charid, amount, memo? }, ... }. Returns (ok, err).
function Bank.runPayroll(bizKey, payrollTable, opts)
  -- The business-aware export does not exist yet (build ruling above). Try
  -- it — if banking gains RunBusinessPayroll this line starts working with
  -- no ranch-side change — and report cleanly meanwhile.
  local ok, res = call('RunBusinessPayroll', bizKey, payrollTable, opts)
  if ok == nil then return false, Err.BANKING end
  return ok, res
end

--- Ledger read for the boss's ledger view (Phase 5).
function Bank.transactions(bizKey, filterOpts)
  local acct = Bank.businessAccount(bizKey)
  if not acct then return nil end
  return call('GetTransactions', acct.id, filterOpts)
end
