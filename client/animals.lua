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
  TaskWanderInArea(ped, c.x, c.y, c.z, 12.0, 1.0, 1.0, 0)
end

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
      -- Walk-only follow behind the buyer (drive-home). 14 params in RDR3.
      TaskFollowToOffsetOfEntity(ped, PlayerPedId(), 0.0, -2.0, 0.0,
        1.0, -1, 2.5, true, false, true, false, false, false)
    else
      wanderHere(ped)
    end

    local netId = NetworkGetNetworkIdFromEntity(ped)
    TriggerServerEvent('sovereign_ranch:server:spawned', order.animalId, netId)
  end)
end)

--- Transit animal crossed the home boundary: follow → wander.
RegisterNetEvent('sovereign_ranch:client:settle', function(animalId)
  local rec = RanchHerd[tonumber(animalId)]
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
  local rec = RanchHerd[tonumber(animalId)]
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
