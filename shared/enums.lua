--[[
  shared/enums.lua — the vocabulary of the ranch layer (design §2, §3).

  These strings ARE the DB enum values in sovereign_ranch_animals; change
  them here and you must migrate the table too, so don't. Error codes follow
  the suite contract: every mutating call returns (ok, resultOrErrorCode)
  and never throws — codes are ERR_* strings, matching sovereign_banking's
  style so callers handle both uniformly; bank and realestate codes pass
  through untouched.
]]

Enums = {}

-- Animal sexes — the DB enum ('m','f'). m: bull/boar/ram/buck/rooster.
Enums.Sex = { MALE = 'm', FEMALE = 'f' }

-- Animal lifecycle states (design §3.3). 'penned' = despawned/frozen: no
-- needs decay, no growth, no production, zero server cost.
Enums.State = {
  PENNED    = 'penned',
  SPAWNED   = 'spawned',
  STRAYING  = 'straying',
  WRANGLING = 'wrangling',
  TRANSIT   = 'transit',
  DEAD      = 'dead',
}

-- Sickness ladder (design §6.2): unmet needs → sick (production halts) →
-- critical (health drains) → dead.
Enums.Sick = { HEALTHY = 'healthy', SICK = 'sick', CRITICAL = 'critical' }

-- Life stages derived from sim_minutes against the per-species bands
-- (config/animals.lua growth.stages). Drive market pricing in Phase 3+.
Enums.Stage = { YOUNG = 'young', PRIME = 'prime', ADULT = 'adult', OLD = 'old' }

-- ============================================================================
-- Grades & capabilities (design §5.2 — the single source of truth).
-- Checks are always server-side, resolved from the MEMBERSHIP table, never
-- from the client and never from the VORP job alone.
-- ============================================================================

Enums.Grade = {
  HAND    = 0,
  SENIOR  = 1,
  FOREMAN = 2,
  MANAGER = 3,
  RANCHER = 4,   -- the boss; private grade, set on property purchase only
}

-- capability -> minimum grade.
Enums.Capability = {
  -- all grades
  care      = 0,   -- feed / water / brush
  wrangle   = 0,
  collect   = 0,
  -- Foreman+
  buy       = 2,   -- buy livestock (dealer / delivery)
  drive     = 2,   -- herd off-property, cattle drives, market sales
  treat     = 2,   -- treat sickness
  -- Manager+
  hire      = 3,   -- hire/fire below Manager, promote up to Foreman
  -- Rancher only
  manage    = 4,   -- promote/demote Manager, set wages, ledger withdraw, slaughter
}

-- ============================================================================
-- Ledger reason strings passed to the bank (opts.reason, ≤40 chars, stable —
-- they are how the bank's ledger is filtered).
-- ============================================================================
Enums.Reason = {
  LIVESTOCK_BUY  = 'ranch_livestock_buy',
  LIVESTOCK_SALE = 'ranch_livestock_sale',
  GOODS_SALE     = 'ranch_goods_sale',
  EXPORT         = 'ranch_export',
  WAGES          = 'ranch_wages',
  WITHDRAW       = 'ranch_withdraw',
}

-- ============================================================================
-- Error codes returned by our own flows. Bank codes (ERR_INSUFFICIENT_FUNDS,
-- ...) and realestate codes (ERR_NO_PROPERTY, ...) pass through untouched.
-- ============================================================================
Enums.Err = {
  BAD_ARG        = 'ERR_BAD_ARG',
  BAD_AMOUNT     = 'ERR_BAD_AMOUNT',
  BANKING        = 'ERR_BANKING',         -- bank missing / adapter call threw
  ESTATE         = 'ERR_ESTATE',          -- realestate missing / adapter call threw
  NO_RANCH       = 'ERR_NO_RANCH',        -- ident has no ranch record (or not ranch-class)
  NOT_MEMBER     = 'ERR_NOT_MEMBER',      -- charid is not on this ranch's crew
  ALREADY_MEMBER = 'ERR_ALREADY_MEMBER',  -- one ranch per character, any role
  NO_CAPABILITY  = 'ERR_NO_CAPABILITY',   -- grade below the capability floor
  GRADE_CEILING  = 'ERR_GRADE_CEILING',   -- actor may not set/touch that grade
  CREW_FULL      = 'ERR_CREW_FULL',       -- Config.MaxEmployees reached
  HERD_FULL      = 'ERR_HERD_FULL',       -- Config.MaxPerSpecies reached
  NO_ANIMAL      = 'ERR_NO_ANIMAL',       -- unknown animal id
  BAD_SPECIES    = 'ERR_BAD_SPECIES',     -- species not in config/animals.lua
  UNKNOWN_CHAR   = 'ERR_UNKNOWN_CHAR',    -- charid not in the characters table
  OFFLINE        = 'ERR_OFFLINE',         -- action needs the target online
  BUSY           = 'ERR_BUSY',            -- something already in progress there
  COOLDOWN       = 'ERR_COOLDOWN',
  INTERNAL       = 'ERR_INTERNAL',
}

-- ============================================================================
-- Locale accessor. Locales['en'] is loaded before this file (manifest order).
-- ============================================================================
function T(key, ...)
  local s = (Locales and Locales['en'] or {})[key]
  if not s then return key end
  if select('#', ...) > 0 then
    local ok, out = pcall(string.format, s, ...)
    return ok and out or s
  end
  return s
end
