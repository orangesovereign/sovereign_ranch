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

--- Ground-truth a spawn coord before anything stands on it. A surveyed
--- point can sit under an eave, inside a prop, or on a building floor;
--- dropping a ped there gives it nowhere to route (live finding
--- 2026-08-13). Natives verified in RDR3:
---   GET_SAFE_COORD_FOR_PED    0xB61C8E878A4199CA (x,y,z,onGround,Vec3*,flags) → BOOL
---   GET_GROUND_Z_FOR_3D_COORD 0x24FA4267BB8D2431 (x,y,z,float*,BOOL) → BOOL
--- Both are guarded: an unavailable wrapper degrades to the raw coord
--- rather than killing the spawn.
local function safeSpawnCoord(x, y, z)
  local ok, pos = pcall(function()
    local found, out = GetSafeCoordForPed(x, y, z, true, 16)
    if found and out then return out end
    return nil
  end)
  -- SANITY GATE: a "safe coord" is only useful if it is still THIS place.
  -- The native can report a point far away — or a zeroed vector, and 0.0 is
  -- truthy in Lua, so an unchecked result cheerfully spawns the animal at
  -- the map origin where nobody will ever find it. Anything further than
  -- 10 m from what we asked for is not an answer to our question.
  if ok and pos and pos.x then
    local dx, dy = pos.x - x, pos.y - y
    if (dx * dx + dy * dy) <= 100.0 then return pos.x, pos.y, pos.z end
  end

  local okg, gz = pcall(function()
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 3.0, false)
    if found then return groundZ end
    return nil
  end)
  -- Same rule for the ground snap: a wild Z means the probe missed.
  if okg and gz and math.abs(gz - z) <= 15.0 then return x, y, gz + 0.05 end

  return x, y, z
end

--- Settle an animal into a wander around `home` (its mapped open-ground
--- anchor) rather than wherever it happens to be standing — wandering
--- from a bad spot just explores more bad spots.
local function wanderAt(ped, home)
  local c = GetEntityCoords(ped, true, true)
  local hx, hy, hz = c.x, c.y, c.z
  if home and home.x then hx, hy, hz = home.x, home.y, home.z end
  ClearPedTasks(ped, true, true)
  SetPedMoveRateOverride(ped, 1.0)   -- drop any keep-up boost
  TaskWanderInArea(ped, hx, hy, hz, Config.Wander.radius or 8.0, 1.0, 1.0, 0)
end

local function wanderHere(ped)
  wanderAt(ped, nil)
end

--- Put an animal back to its idle business after a care action or a meal.
--- Exposed because care.lua holds animals still while brushing them.
function RanchResumeIdle(animalId)
  local ped = RanchEntity(animalId)
  if not ped then return end
  local rec = RanchHerd[tonumber(animalId)]
  wanderAt(ped, rec and rec.home)
end

--- The species/sex scenario for an activity ('graze'|'eat'|'drink'), or nil
--- when the game ships none for that species (sheep — see config/animals).
function RanchScenario(species, sex, activity)
  local spec = Config.Animals[species]
  local set = spec and spec.scenarios
  if not set then return nil end
  local bySex = set[sex] or set.any
  return bySex and bySex[activity] or nil
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
      TriggerServerEvent('sovereign_ranch:server:spawnFailed', order.animalId,
        'model ' .. tostring(order.model) .. ' would not load')
      return
    end

    local x, y, z = safeSpawnCoord(order.x + 0.0, order.y + 0.0, (order.z or 0.0) + 0.0)
    -- Networked, script-host — the arity realestate's spawner proved live.
    local ped = CreatePed(model, x, y, z, 0.0, true, true, true, true)
    local tries = 0
    while not DoesEntityExist(ped) and tries < 40 do Wait(50) tries = tries + 1 end
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(ped) then
      print(('[sovereign_ranch] spawn order #%s: ped never materialised at %.2f %.2f %.2f')
        :format(tostring(order.animalId), x, y, z))
      TriggerServerEvent('sovereign_ranch:server:spawnFailed', order.animalId,
        'CreatePed produced nothing')
      return
    end
    print(('[sovereign_ranch] spawned #%s (%s) at %.2f %.2f %.2f')
      :format(tostring(order.animalId), tostring(order.species), x, y, z))

    SetEntityAsMissionEntity(ped, true, true)
    RanchDress(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)   -- no fleeing the brush

    -- Any client (prompts, lasso in P4) resolves the animal id off the ped.
    Entity(ped).state:set('sov_animal', order.animalId, true)

    -- Remember the mapped anchor: the wander centre AND where the stuck
    -- watchdog lifts it back to.
    local rec = RanchHerd[order.animalId]
    if not rec then rec = {}; RanchHerd[order.animalId] = rec end
    if order.homeX then
      rec.home = { x = order.homeX, y = order.homeY, z = order.homeZ }
    end

    if order.mode == 'transit' then
      RanchLead(order.animalId, ped)   -- pace-matching follow (see above)
    else
      wanderAt(ped, rec.home)
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
  -- A driven-home animal settles where it ARRIVED, not at the barn — it
  -- just walked here with you; teleporting it to the anchor would be worse.
  if ped and ped ~= 0 and DoesEntityExist(ped) then wanderHere(ped) end
end)

-- ============================================================================
-- The stuck watchdog. RDR3 peds route over the game's navmesh once tasked,
-- but a ped that starts (or wanders) into geometry will grind against it
-- indefinitely — it never reports failure. Nothing but observation catches
-- that, so: sample positions, and escalate.
--   3 strikes (~15s pinned) → clear tasks, wander afresh from the anchor.
--     Harmless if it was only grazing, which is why it's eager.
--   6 strikes (~30s, so the re-task didn't take) → lift it to safe ground
--     at its anchor. The conservative rung, because it's a teleport.
-- Led animals are exempt: they're supposed to stand still when you do.
-- ============================================================================

local stuckState = {}   -- animalId -> { x, y, strikes }

CreateThread(function()
  while true do
    Wait(Config.Wander.stuckCheckMs or 5000)
    local minMove = (Config.Wander.stuckDistance or 0.4) ^ 2
    local retask  = Config.Wander.strikesRetask or 3
    local warp    = Config.Wander.strikesWarp or 6

    for animalId, rec in pairs(RanchHerd) do
      if rec.netId and not leading[animalId] then
        local ped = RanchEntity(animalId)
        if not ped then
          stuckState[animalId] = nil
        else
          local c = GetEntityCoords(ped, true, true)
          local s = stuckState[animalId]
          if s then
            local dx, dy = c.x - s.x, c.y - s.y
            if (dx * dx + dy * dy) < minMove then
              s.strikes = s.strikes + 1
              if s.strikes >= warp then
                local h = rec.home
                if h then
                  local sx, sy, sz = safeSpawnCoord(h.x, h.y, h.z)
                  SetEntityCoordsNoOffset(ped, sx, sy, sz, false, false, false)
                  print(('[sovereign_ranch] animal #%d was pinned — lifted to its anchor')
                    :format(animalId))
                end
                wanderAt(ped, rec.home)
                s.strikes = 0
              elseif s.strikes == retask then
                wanderAt(ped, rec.home)
              end
            else
              s.strikes = 0
            end
            s.x, s.y = c.x, c.y
          else
            stuckState[animalId] = { x = c.x, y = c.y, strikes = 0 }
          end
        end
      end
    end
  end
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

-- ============================================================================
-- Feeding behaviour (server decides WHO is hungry and WHAT they can reach;
-- this walks them there and plays the right species scenario). This is also
-- most of the answer to "animals are stupid" — an animal with somewhere to
-- be stops looking like a wind-up toy.
--   TASK_GO_TO_COORD_ANY_MEANS 0x5BC448CB78FA3E88 (9 params)
--   TASK_START_SCENARIO_AT_POSITION 0x4D1F61FC34AF3CD1 (12 params)
-- ============================================================================

RegisterNetEvent('sovereign_ranch:client:feeding', function(list)
  if type(list) ~= 'table' then return end
  for _, row in ipairs(list) do
    local animalId = tonumber(row.id)
    local rec = RanchHerd[animalId]
    local ped = RanchEntity(animalId)
    if ped and rec and not leading[animalId] then
      local f = row.feeding
      if not f then
        -- Done eating (full, or the trough ran dry): back to idle.
        RanchResumeIdle(animalId)
      elseif f.eating then
        -- At the source: play the species' eat/drink scenario facing it.
        local v = rec.view or {}
        local activity = (f.kind == 'water') and 'drink' or 'eat'
        local scenario = RanchScenario(v.species, v.sex, activity)
        ClearPedTasks(ped, true, true)
        if scenario then
          Citizen.InvokeNative(0x4D1F61FC34AF3CD1, ped, GetHashKey(scenario),
            f.x, f.y, f.z, 0.0, -1, false, false, '', 0.0, false)
        else
          TaskTurnPedToFaceCoord(ped, f.x, f.y, f.z, 1000)
        end
      else
        -- Heading for it. Walk — livestock amble to a trough, they do not
        -- sprint — and let the navmesh route around the fences.
        TaskGoToCoordAnyMeans(ped, f.x, f.y, f.z, 1.0, 0, false, 786603, 0.0)
      end
    end
  end
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
