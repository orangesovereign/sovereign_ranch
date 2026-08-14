--[[
  server/ranches.lua — the ranch registry (design §4), keyed by realestate
  ident. Owns the in-memory cache of ranch rows and the lifecycle:

    propertySold(ranch-class)  → Ranches.activate: create/claim the row,
                                 mirror owner, resolve biz key, seat the
                                 owner as the grade-4 member.
    soldback/confiscated/
    repossessed                → Ranches.teardown: freeze animals, release
                                 the crew, revoke access mirrors.
    boot + daily               → Ranches.reconcile: realestate is truth;
                                 fix our mirrors toward it.

  Realestate remains the single truth for who owns the property; owner_*
  here are mirrors for offline queries (the per-account key) and fast paths.
]]

Ranches = {}

local cache   = {}   -- id -> ranch row (live, write-through)
local byIdent = {}   -- ident -> ranch row
local missingStrikes = {}  -- ident -> consecutive reconciles missing from realestate

local Err = Enums.Err

-- ============================================================================
-- Cache
-- ============================================================================

function Ranches.load()
  cache, byIdent = {}, {}
  local rows = Db.loadRanches() or {}
  for _, r in ipairs(rows) do
    r.id = tonumber(r.id)
    r.owner_charid = tonumber(r.owner_charid)
    cache[r.id] = r
    byIdent[r.ident] = r
  end
  Log.info('loaded %d ranch record(s)', #rows)
end

function Ranches.get(id) return cache[tonumber(id)] end
function Ranches.getByIdent(ident) return byIdent[tostring(ident or ''):lower()] end
function Ranches.all() return cache end

--- Mapped points for a ranch (config/ranches.lua, keyed by ident — the map
--- belongs to the property, not the owner). Always a table, possibly empty.
function Ranches.pointsOf(ident)
  return (Config.Ranches or {})[tostring(ident or ''):lower()] or {}
end

--- Where this species is LET OUT and wanders. Open-ground points first;
--- structures only as a last resort, because an interior point strands the
--- animal inside a building (live finding 2026-08-13 — see the header of
--- config/ranches.lua). nil = no map, caller falls back to the releaser.
function Ranches.releaseAnchor(ident, species)
  local p = Ranches.pointsOf(ident)
  if species == 'chicken' then
    return p.chickenPen or p.coop or p.pasture
  end
  return p.pasture or p.barn
end

--- The ranch a charid OWNS (grade-4 seat), or nil. Membership answers "works
--- at"; this answers "holds the deed of".
function Ranches.getByOwner(charid)
  charid = tonumber(charid)
  if not charid then return nil end
  for _, r in pairs(cache) do
    if r.owner_charid == charid then return r end
  end
  return nil
end

local function save(r)
  Db.updateRanch(r)
end
Ranches.save = save

-- ============================================================================
-- Activation (design §4) — idempotent: activating an already-active ranch
-- re-asserts the mirrors instead of duplicating anything.
-- ============================================================================

--- Bring a ranch record live for `ident`, owned by `charid`. charid may be
--- nil (payload was thin) — truth is re-read from realestate either way.
--- Returns (ok, ranchOrErr).
function Ranches.activate(ident, charid)
  ident = tostring(ident or ''):lower()
  if ident == '' then return false, Err.BAD_ARG end

  local p = Estate.getProperty(ident)
  if not p or p.class ~= 'ranch' then return false, Err.NO_RANCH end

  local owner = tonumber(p.owner) or tonumber(charid)
  if not owner then return false, Err.BAD_ARG end

  local r = Ranches.getByIdent(ident)
  if not r then
    local id = Db.insertRanch({ ident = ident })
    if not id then return false, Err.INTERNAL end
    r = { id = tonumber(id), ident = ident, stray_mult = 1.0 }
    cache[r.id] = r
    byIdent[ident] = r
  end

  r.owner_charid = owner
  r.owner_userid = Bridge.GetUserId(owner)
  -- The bank account key realestate registered the business under
  -- (bank_business_key or ident — the patched GetProperty exposes it).
  r.biz_key = p.bizKey or ident
  save(r)

  -- Seat the owner as the grade-4 member (also syncs the VORP job and the
  -- realestate access mirror; idempotent for an existing seat).
  local ok, err = Members.seatOwner(r, owner)
  if not ok then
    Log.error('activate %s: owner seat failed: %s', ident, tostring(err))
  end

  Events.ranchActivated({ ident = ident, ownerCharid = owner })
  Log.info('ranch ACTIVATED: %s (owner %d, account %s)', ident, owner, tostring(r.biz_key))
  Log.discord('lifecycle', 'Ranch activated',
    ('**%s** — owner %s'):format(ident, Bridge.GetCharName(owner)))

  Notify.charCard(owner, T('ranch_activated_title'), T('ranch_activated', p.label or ident))
  return true, r
end

-- ============================================================================
-- Teardown (design §4) — the property was lost. Animals freeze (rows KEPT so
-- a herd survives an ownership transfer intact; wiped only on voluntary
-- sell-back when Config.WipeHerdOnSellBack), crew is released, mirrors clear.
-- ============================================================================

--- Returns (ok, err). Idempotent: tearing down an unknown ident is a no-op
--- success (the end state — no active ranch — already holds).
function Ranches.teardown(ident, reason)
  ident = tostring(ident or ''):lower()
  local r = Ranches.getByIdent(ident)
  if not r then return true, nil end

  -- 1. Freeze the herd: live peds despawned server-side with positions
  --    persisted (Spawns), then the DB-level pen as belt and braces for
  --    rows the cache never saw (crash leftovers).
  Spawns.penAllLive(r.id, 'teardown')
  Troughs.clearRanch(r.id)   -- a lost ranch's feed does not follow the deed
  local penned = Db.penAllAnimals(r.id) or 0
  if reason == 'soldback' and Config.WipeHerdOnSellBack then
    Db.deleteAnimals(r.id)
    Animals.dropRanch(r.id)
    Log.info('teardown %s: herd wiped (%s)', ident, reason)
  end

  -- 2. Release the crew: fire every member (job → unemployed where they
  --    carry the rancher job, access mirror revoked, duty cleared, wages
  --    zeroed with a log line — design §4).
  Members.releaseAll(r, reason)

  -- 3. Clear the ownership mirrors; the row itself stays (herd + settings
  --    survive for the next owner).
  r.owner_charid = nil
  r.owner_userid = nil
  save(r)

  Events.ranchTorndown({ ident = ident, reason = tostring(reason or 'unknown') })
  Log.info('ranch TORN DOWN: %s (%s, %d animals penned)', ident, tostring(reason), penned)
  Log.discord('lifecycle', 'Ranch torn down',
    ('**%s** — %s'):format(ident, tostring(reason)))
  return true, nil
end

-- ============================================================================
-- Reconcile (design §4) — boot + every Config.ReconcileMinutes. Realestate
-- is truth: every owned ranch-class property has a live record with correct
-- mirrors; every record whose property is no longer owned is torn down;
-- every member's VORP grade matches the membership table.
-- ============================================================================

function Ranches.reconcile()
  if not Estate.available() then
    Log.warn('reconcile skipped — realestate not started')
    return
  end

  local props = Estate.listRanchProperties()
  local seen = {}

  for _, p in ipairs(props) do
    seen[p.ident] = true
    local r = Ranches.getByIdent(p.ident)
    if p.owner then
      if not r or r.owner_charid ~= tonumber(p.owner) then
        -- Sold (or transferred) while we weren't looking — activate mirrors.
        Log.info('reconcile: %s owner drift (have %s, truth %s) — activating',
          p.ident, r and tostring(r.owner_charid) or 'none', tostring(p.owner))
        Ranches.activate(p.ident, tonumber(p.owner))
      end
    elseif r and r.owner_charid then
      Log.info('reconcile: %s no longer owned — tearing down', p.ident)
      Ranches.teardown(p.ident, 'reconcile')
    end
  end

  -- Records whose property vanished from realestate entirely (deleted MLO
  -- listing): tear down — but NEVER on first sighting. Realestate loads its
  -- property cache asynchronously after 'started', so a reconcile that runs
  -- against the not-yet-loaded cache sees every property as missing; acting
  -- on that once tore down a healthy test ranch (live finding 2026-08-13).
  -- Rule: a direct GetProperty recheck, then TWO consecutive reconciles
  -- agreeing the property is gone before anything destructive happens.
  for _, r in pairs(cache) do
    if r.owner_charid and not seen[r.ident] then
      if Estate.getProperty(r.ident) ~= nil then
        missingStrikes[r.ident] = nil   -- cache was mid-load; property is real
      else
        missingStrikes[r.ident] = (missingStrikes[r.ident] or 0) + 1
        if missingStrikes[r.ident] >= 2 then
          Log.warn('reconcile: %s missing from realestate twice running — tearing down', r.ident)
          missingStrikes[r.ident] = nil
          Ranches.teardown(r.ident, 'reconcile')
        else
          Log.warn('reconcile: %s has a record but no realestate property — will confirm next pass before acting', r.ident)
        end
      end
    else
      missingStrikes[r.ident] = nil
    end
  end

  -- Crash recovery: any animal left 'spawned' by a mid-shift restart is
  -- frozen (position kept). Spawned-state truth restarts empty by design.
  for _, r in pairs(cache) do
    local n = Db.penAllAnimals(r.id)
    if n and n > 0 then
      Log.info('reconcile: %s — re-penned %d stranded animal(s)', r.ident, n)
    end
  end

  Members.reconcileGrades()
end
