--[[
  server/estate.lua — sovereign_realestate, the property backend (design §4).

  The ONLY module that calls exports.sovereign_realestate. Realestate is the
  TRUTH for property identity, ownership, zones, doors, tax and fences; this
  file exposes exactly the reads and access mutations the ranch needs, plus
  the lifecycle event subscriptions that drive ranch activation/teardown.

  Suite rules honoured here: payload fields are treated as optional — every
  handler re-reads truth from realestate exports rather than trusting the
  payload beyond `ident`; server-side AddEventHandler only (these events are
  emitted server-side by realestate and cannot be fired by a client).
]]

Estate = {}

local ESTATE = 'sovereign_realestate'
local Err = Enums.Err

local RANCH_CLASS = 'ranch'   -- realestate Enums.Class.RANCH

local function estateStarted()
  return GetResourceState(ESTATE) == 'started'
end

Estate.available = estateStarted

--- Uniform pcall wrapper around a realestate export. Returns whatever the
--- export returns on success, or nil on a missing resource / thrown error.
local function call(fn, ...)
  if not estateStarted() then
    Log.warn('estate: %s skipped — %s is not started', fn, ESTATE)
    return nil
  end
  -- CFX's export wrapper is `function(self, ...)`: pass the proxy explicitly
  -- as self so the real args land (the suite's explicit-self rule).
  local proxy = exports[ESTATE]
  local packed = { pcall(function(...) return proxy[fn](proxy, ...) end, ...) }
  if not packed[1] then
    Log.error('estate: %s errored: %s', fn, tostring(packed[2]))
    return nil
  end
  table.remove(packed, 1)
  return table.unpack(packed)
end

-- ============================================================================
-- Reads
-- ============================================================================

--- Public view of one property, or nil. { id, ident, label, class, status,
--- price, owner, nickname, hasLand, hasInterior, bizKey* }
--- (*bizKey added by the Phase 0 realestate patch for business classes.)
function Estate.getProperty(ident)
  return call('GetProperty', ident)
end

--- Every ranch-class property (any status). Array, possibly empty.
function Estate.listRanchProperties()
  return call('ListProperties', { class = RANCH_CLASS }) or {}
end

--- Is this property ranch-class? nil-safe.
function Estate.isRanchClass(ident)
  local p = Estate.getProperty(ident)
  return p ~= nil and p.class == RANCH_CLASS
end

--- Charid of the deed holder, or nil when unowned/unknown.
function Estate.getOwner(ident)
  return call('GetPropertyOwner', ident)
end

--- Does this character hold the deed?
function Estate.isOwner(charid, ident)
  return call('IsPropertyOwner', charid, ident) == true
end

--- Is this point inside the property (land or interior)? The property's
--- land polygon IS the ranch boundary — the ranch never draws its own zones.
function Estate.isInside(coords, ident)
  return call('IsInsideProperty', coords, ident) == true
end

--- Which property contains this point? Premises ref or nil.
function Estate.resolveAt(coords)
  return call('resolvePropertyAt', coords)
end

-- ============================================================================
-- Access mirror (design §1.1): hiring grants realestate door/storage rights,
-- firing revokes them, so property access stays in sync with employment.
-- ============================================================================

--- Grant a hand access to the ranch property. Returns (ok, err).
function Estate.grantAccess(ident, charid, opts)
  local ok, res = call('GrantAccess', ident, charid, opts or { storage = true })
  if ok == nil then return false, Err.ESTATE end
  return ok, res
end

--- Revoke a fired hand's access. Missing grants are fine (ERR_NO_ACCESS is
--- swallowed — the end state is what we wanted).
function Estate.revokeAccess(ident, charid)
  local ok, res = call('RevokeAccess', ident, charid)
  if ok == nil then return false, Err.ESTATE end
  if not ok and res == 'ERR_NO_ACCESS' then return true, nil end
  return ok, res
end

-- ============================================================================
-- Lifecycle subscriptions (design §4) — the ONLY way ranches come and go.
-- Handlers land in Ranches (loaded after this file; resolved at call time).
-- ============================================================================

--- propertySold { propertyId, ident, charid, price, class } — class is
--- present on this payload today, but we re-check via export anyway.
AddEventHandler('sovereign_realestate:server:propertySold', function(payload)
  if type(payload) ~= 'table' or not payload.ident then return end
  local ident = tostring(payload.ident)
  if not Estate.isRanchClass(ident) then return end
  Ranches.activate(ident, tonumber(payload.charid))
end)

--- Teardown family. Confiscated/repossessed payloads carry no class — the
--- guard is simply "do we have a ranch record for this ident".
local function onLoss(reason)
  return function(payload)
    if type(payload) ~= 'table' or not payload.ident then return end
    Ranches.teardown(tostring(payload.ident), reason)
  end
end

AddEventHandler('sovereign_realestate:server:propertySoldBack',    onLoss('soldback'))
AddEventHandler('sovereign_realestate:server:propertyConfiscated', onLoss('confiscated'))
AddEventHandler('sovereign_realestate:server:propertyRepossessed', onLoss('repossessed'))

--- fenceBroken — Phase 4 raises the stray multiplier from this. Subscribed
--- now so the seam is proven in Phase 0's ledger; the handler is a log line
--- until strays exist.
AddEventHandler('sovereign_realestate:server:fenceBroken', function(payload)
  if type(payload) ~= 'table' then return end
  Log.debug('fenceBroken heard: %s', json.encode(payload))
  -- Phase 4: Strays.onFenceBroken(payload)
end)
