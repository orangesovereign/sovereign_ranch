--[[
  client/troughs.lua — the feeding infrastructure, player side.

  Troughs are the MAP's own props, not ours: whichever of Rockstar's seven
  models a property happens to have, we find it and offer to fill it. All
  the server ever hears is "I filled the one at these coords" — it decides
  whether that was true (member, on the property, within reach).

  Prompt discipline, learned the hard way this phase: ONE prompt exists at
  a time, created on approach and DELETED on leave. A registered prompt
  contests its control against every other prompt on the same key even when
  disabled or hidden.

  Natives verified in RDR3 2026-08-13:
    GET_CLOSEST_OBJECT_OF_TYPE 0xE143FA2249364369 (x,y,z,radius,Hash,BOOL,BOOL,BOOL) → Object
    GET_ENTITY_MODEL           0xDA76A9F39210D365 (Entity) → Hash
]]

-- Live server state, so a filled trough can say so on the prompt.
RanchTroughs  = { troughs = {}, scatters = {} }

local nearTrough = nil    -- { object, kind, x, y, z }
local fillPrompt = nil
local filling    = false

RegisterNetEvent('sovereign_ranch:client:troughs', function(payload)
  if type(payload) ~= 'table' then return end
  RanchTroughs.troughs  = payload.troughs or {}
  RanchTroughs.scatters = payload.scatters or {}
end)

-- ============================================================================
-- Discovery
-- ============================================================================

local feedHashes, waterHashes = {}, {}
CreateThread(function()
  for _, name in ipairs(Config.Troughs.feed or {})  do feedHashes[#feedHashes + 1]  = GetHashKey(name) end
  for _, name in ipairs(Config.Troughs.water or {}) do waterHashes[#waterHashes + 1] = GetHashKey(name) end
end)

--- Nearest trough prop of either kind within scanRadius, or nil.
local function findNearestTrough()
  local c = GetEntityCoords(PlayerPedId(), true, true)
  local radius = Config.Troughs.scanRadius or 40.0
  local best, bestD2, bestKind = nil, nil, nil

  local function scan(hashes, kind)
    for _, hash in ipairs(hashes) do
      local obj = GetClosestObjectOfType(c.x, c.y, c.z, radius, hash, false, false, false)
      if obj and obj ~= 0 and DoesEntityExist(obj) then
        local oc = GetEntityCoords(obj)
        local dx, dy, dz = c.x - oc.x, c.y - oc.y, c.z - oc.z
        local d2 = dx * dx + dy * dy + dz * dz
        if not bestD2 or d2 < bestD2 then
          best, bestD2, bestKind = obj, d2, kind
        end
      end
    end
  end

  scan(feedHashes, 'feed')
  scan(waterHashes, 'water')
  if not best then return nil end
  local oc = GetEntityCoords(best)
  return { object = best, kind = bestKind, x = oc.x, y = oc.y, z = oc.z }, bestD2
end

--- Is the server holding this trough as filled? (Position-matched, same
--- rounding tolerance the server keys on.)
local function isFilled(t)
  for _, row in ipairs(RanchTroughs.troughs) do
    if row.kind == t.kind
      and math.abs(row.x - t.x) < 0.3
      and math.abs(row.y - t.y) < 0.3 then
      return true, row.units
    end
  end
  return false, 0
end

-- ============================================================================
-- Fill action
-- ============================================================================

local function fillLabel(t)
  local full, units = isFilled(t)
  if t.kind == 'water' then
    return full and ('Water Trough (%d left)'):format(units) or 'Fill Water Trough'
  end
  return full and ('Feed Trough (%d left)'):format(units) or 'Fill Feed Trough'
end

local function doFill(t)
  if filling then return end
  filling = true
  CreateThread(function()
    -- Water pours from a bucket; feed comes out of a sack. Both scenarios
    -- are first picks from docs/animations-reference.md, and both carry
    -- PROPS — client/anim.lua owns getting them out of your hands again.
    local verb = (t.kind == 'water') and 'water' or 'feed'
    local name = RanchAnimFor(verb, nil)
    local duration = (Config.Troughs.fillSeconds or 4) * 1000

    local done = RanchScenarioAction({
      scenario = name, duration = duration, faceCoords = t,
      label = (t.kind == 'water') and 'Filling the water trough...'
        or 'Filling the feed trough...',
    })
    if done then
      TriggerServerEvent('sovereign_ranch:server:fillTrough', t.kind, t.x, t.y, t.z)
    end
    filling = false
  end)
end

-- ============================================================================
-- The proximity loop — one prompt, created on approach, deleted on leave.
-- ============================================================================

local function dropPrompt()
  if fillPrompt then
    fillPrompt:delete()
    fillPrompt = nil
  end
end

CreateThread(function()
  while true do
    local wait = Config.Troughs.scanEveryMs or 3000

    -- Only look while we are actually somewhere with animals to feed.
    local t, d2 = findNearestTrough()
    local range = Config.Troughs.promptRange or 2.5
    if t and d2 and d2 <= (range * range) then
      nearTrough = t
      if not fillPrompt then
        fillPrompt = sv.interact.prompt({
          key = 'INPUT_ENTER',
          label = fillLabel(t),
          mode = 'hold', holdTime = 700,
          group = 'ranch_trough', groupLabel = 'Trough',
          onComplete = function()
            if nearTrough then doFill(nearTrough) end
          end,
        })
      else
        fillPrompt:setLabel(fillLabel(t))
      end
      wait = 500   -- close in: refresh the label briskly
    else
      nearTrough = nil
      dropPrompt()
    end

    Wait(wait)
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  dropPrompt()
end)
