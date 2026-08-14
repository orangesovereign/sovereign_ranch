--[[
  client/animals.lua — the steward's hands (design §6.3 under the Phase 0
  ruling). The SERVER decides what exists; this file materialises it when
  ordered: CreatePed (networked), the two-native dress (standing rule),
  state bag binding, wander/settle behaviours, and the local registry that
  care prompts and the Herd Book read.

  Natives verified against natives_rdr3.json 2026-08-13:
    REQUEST_MODEL                     0xFA28FE3A6246FC30 (Hash, BOOL)
    NETWORK_GET_NETWORK_ID_FROM_ENTITY 0xA11700682F3AD45C (Entity) → int
    NETWORK_GET_ENTITY_FROM_NETWORK_ID 0xCE4E5D9B0A4FF560 (int) → Entity
    TASK_WANDER_IN_AREA               0xE054346CA3A0F315 (Ped, x,y,z, radius, f, f, int)
    SET_ENTITY_AS_MISSION_ENTITY      0xDC19C288082E586E (Entity, BOOL, BOOL)
    CLEAR_PED_TASKS                   0xE1EF3C1216AFF2CD (Ped, BOOL, BOOL)
    _SET_RANDOM_OUTFIT_VARIATION      0x283978A15512B2FE / _UPDATE_PED_VARIATION 0xCC8CA3E88256E58F
]]

-- animalId -> { netId, view } — every spawned animal of MY ranch the server
-- has told me about. care.lua and menus.lua read this; only server events
-- write it.
RanchHerd = {}

--- The standing dressing rule: every ped this resource spawns gets the
--- two-native dress, a settle beat, and a second dress. Global — main.lua's
--- probe assist and menus.lua's dealer ped use the same hands.
function RanchDress(ped)
  local function once()
    pcall(function() Citizen.InvokeNative(0x283978A15512B2FE, ped, true) end)
    pcall(function() Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false) end)
  end
  once()
  Wait(100)
  once()
end

local function loadModel(name)
  local model = GetHashKey(name)
  if not IsModelValid(model) then return nil end
  RequestModel(model, false)
  for _ = 1, 100 do
    if HasModelLoaded(model) then return model end
    Wait(50)
  end
  return nil
end

local function wanderHere(ped)
  local c = GetEntityCoords(ped)
  ClearPedTasks(ped, true, true)
  SetPedMoveRateOverride(ped, 1.0)   -- drop any keep-up boost
  TaskWanderInArea(ped, c.x, c.y, c.z, 12.0, 1.0, 1.0, 0)
end

-- ============================================================================
-- Following & pace-matching (Wilbur ruling 2026-08-13: a led animal makes
-- every effort to match its leader's gait). Natives verified in RDR3:
--   GET_ENTITY_SPEED            0xFB6BA510A533DF81 (Entity) → float
--   IS_PED_ON_MOUNT             0x460BC76A0E10655E (Ped) → BOOL
--   GET_MOUNT                   0xE7E11B8DCBED1058 (Ped) → Ped
--   SET_PED_MOVE_RATE_OVERRIDE  0x085BF80FA50A39D1 (Ped, float)
-- The follow task is re-issued only when the band or the follow TARGET
-- changes (mounting swaps the target from the player to the horse), so
-- there is no per-frame re-tasking and no stutter.
-- ============================================================================

local leading = {}   -- animalId -> true while THIS client is leading it

local function bandFor(speed)
  local bands = Config.FollowPace.bands
  for _, b in ipairs(bands) do
    if speed <= b.upTo then return b end
  end
  return bands[#bands]
end

local function applyFollow(ped, target, band)
  -- 14 params in RDR3: (ped, entity, offX, offY, offZ, movementSpeed,
  -- timeout, stoppingRange, persistFollowing, p9, walkOnly, p11, p12, p13)
  TaskFollowToOffsetOfEntity(ped, target, 0.0, -band.distance, 0.0,
    band.move, -1, band.stopRange, true, false, band.walkOnly, false, false, false)
  SetPedMoveRateOverride(ped, band.rate or 1.0)
end

--- Start leading an animal (drive-home purchase; Phase 4 wrangling reuses
--- this). The pace thread takes it from here.
function RanchLead(animalId, ped)
  leading[animalId] = true
  local me = PlayerPedId()
  local target = IsPedOnMount(me) and GetMount(me) or me
  applyFollow(ped, (target ~= 0) and target or me, Config.FollowPace.bands[1])
end

--- Stop leading (settled home, penned, broke loose).
function RanchStopLeading(animalId)
  leading[animalId] = nil
end

CreateThread(function()
  local lastBand, lastTarget
  while true do
    local any = next(leading) ~= nil
    if not any then
      lastBand, lastTarget = nil, nil
      Wait(1000)
    else
      local me = PlayerPedId()
      local mounted = IsPedOnMount(me)
      local target = mounted and GetMount(me) or me
      if not target or target == 0 then target = me end

      -- Pace off the thing actually moving: the horse when mounted.
      local band = bandFor(GetEntitySpeed(target))

      if band.id ~= lastBand or target ~= lastTarget then
        lastBand, lastTarget = band.id, target
        for animalId in pairs(leading) do
          local ped = RanchEntity(animalId)
          if ped then applyFollow(ped, target, band) end
        end
      end
      Wait(Config.FollowPace.sampleMs or 400)
    end
  end
end)

-- ============================================================================
-- Spawn orders (server → this steward)
-- ============================================================================

RegisterNetEvent('sovereign_ranch:client:spawn', function(order)
  if type(order) ~= 'table' or not order.animalId then return end
  CreateThread(function()
    local model = loadModel(order.model)
    if not model then
      print(('[sovereign_ranch] spawn order #%s: model %s invalid/unloaded')
        :format(tostring(order.animalId), tostring(order.model)))
      return
    end

    local x, y, z = order.x + 0.0, order.y + 0.0, (order.z or 0.0) + 0.0
    -- Networked, script-host — the arity realestate's spawner proved live.
    local ped = CreatePed(model, x, y, z, 0.0, true, true, true, true)
    local tries = 0
    while not DoesEntityExist(ped) and tries < 40 do Wait(50) tries = tries + 1 end
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(ped) then
      print(('[sovereign_ranch] spawn order #%s: ped never materialised'):format(tostring(order.animalId)))
      return
    end

    SetEntityAsMissionEntity(ped, true, true)
    RanchDress(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)   -- no fleeing the brush

    -- Any client (prompts, lasso in P4) resolves the animal id off the ped.
    Entity(ped).state:set('sov_animal', order.animalId, true)

    if order.mode == 'transit' then
      RanchLead(order.animalId, ped)   -- pace-matching follow (see above)
    else
      wanderHere(ped)
    end

    local netId = NetworkGetNetworkIdFromEntity(ped)
    TriggerServerEvent('sovereign_ranch:server:spawned', order.animalId, netId)
  end)
end)

--- Transit animal crossed the home boundary: follow → wander.
RegisterNetEvent('sovereign_ranch:client:settle', function(animalId)
  animalId = tonumber(animalId)
  RanchStopLeading(animalId)
  local rec = RanchHerd[animalId]
  if not rec or not rec.netId then return end
  if not NetworkDoesEntityExistWithNetworkId(rec.netId) then return end
  local ped = NetworkGetEntityFromNetworkId(rec.netId)
  if ped and ped ~= 0 and DoesEntityExist(ped) then wanderHere(ped) end
end)

-- ============================================================================
-- Registry upkeep (server pushes; present members only)
-- ============================================================================

local function absorb(view)
  if type(view) ~= 'table' or not view.id then return end
  local rec = RanchHerd[view.id]
  if not rec then rec = {}; RanchHerd[view.id] = rec end
  rec.view = view
  rec.netId = view.netId or rec.netId
  if view.state ~= 'spawned' and view.state ~= 'transit' then
    rec.netId = nil
  end
end

RegisterNetEvent('sovereign_ranch:client:animal', function(view) absorb(view) end)

RegisterNetEvent('sovereign_ranch:client:animals', function(views)
  if type(views) ~= 'table' then return end
  for _, v in ipairs(views) do absorb(v) end
end)

RegisterNetEvent('sovereign_ranch:client:despawn', function(animalId)
  animalId = tonumber(animalId)
  RanchStopLeading(animalId)   -- penned/removed mid-drive: stop pacing it
  local rec = RanchHerd[animalId]
  if rec then rec.netId = nil end
end)

--- Resolve a registry entry to a live entity, or nil.
function RanchEntity(animalId)
  local rec = RanchHerd[tonumber(animalId)]
  if not rec or not rec.netId then return nil end
  if not NetworkDoesEntityExistWithNetworkId(rec.netId) then return nil end
  local ped = NetworkGetEntityFromNetworkId(rec.netId)
  if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
  return ped
end
