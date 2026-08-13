--[[
  server/spawns.lua — the spawn ledger + steward machinery (design §6.3,
  under the Phase 0 ruling: server-side CreatePed is NOT viable on RedM, so
  a member's CLIENT materialises peds; the server stays authoritative over
  what exists, where, and when it disappears).

  Division of labour:
    SERVER (this file)  — presence sweep (server-read member coords vs the
      realestate polygon), hot/cold ranches, steward choice, spawn ORDERS,
      the netId ledger, position persistence, DESPAWN (server-side
      DeleteEntity works on any networked entity — verified natives_cfx:
      DELETE_ENTITY / NETWORK_GET_ENTITY_FROM_NETWORK_ID apiset=server),
      transit home-detection, and the no-orphans guarantees.
    CLIENT (client/animals.lua, client/herd.lua) — CreatePed (networked),
      the two-native dress (standing rule), state bags, wander/follow tasks.

  A ranch with nobody present auto-pens its herd: positions persisted, peds
  deleted server-side. Pause-when-offline, expressed in entities.
]]

Spawns = {}

local State = Enums.State

local present  = {}   -- ranch_id -> { charid -> src }  (members on the property)
local steward  = {}   -- ranch_id -> src                (spawn-order target)
local registry = {}   -- animalId -> netId              (the spawn ledger)
local orders   = {}   -- animalId -> src                (order sent, reply pending)
local probe    = nil  -- Phase 0 probe record (see the bottom of this file)

-- ============================================================================
-- Entity resolution (server-side)
-- ============================================================================

--- Live entity handle for an animal, or nil.
function Spawns.entityOf(animalId)
  local netId = registry[tonumber(animalId)]
  if not netId then return nil end
  local entity = NetworkGetEntityFromNetworkId(netId)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
  return entity
end

function Spawns.spawnedCount(ranchId)
  local n = 0
  for _, a in ipairs(Animals.herdOf(ranchId)) do
    if registry[a.id] then n = n + 1 end
  end
  return n
end

--- Save the entity's current world position onto the row (pen, sweeps).
function Spawns.persistPosition(a)
  local entity = Spawns.entityOf(a.id)
  if not entity then return end
  local c = GetEntityCoords(entity)
  a.pos = { x = c.x, y = c.y, z = c.z }
  Animals.touch(a)
end

-- ============================================================================
-- Presence & steward (the hot/cold gate)
-- ============================================================================

--- ranch_id -> { charid -> src } for every ranch with ≥1 member present.
function Spawns.hotRanches()
  return present
end

function Spawns.presentAt(ranchId)
  return present[tonumber(ranchId)]
end

local function membersPresentSrcs(ranchId)
  local out = {}
  for _, src in pairs(present[tonumber(ranchId)] or {}) do out[#out + 1] = src end
  return out
end

--- Push one animal's public view (+netId when spawned) to present members.
function Spawns.pushAnimal(a)
  local view = Animals.view(a)
  view.netId = registry[a.id]
  for _, src in ipairs(membersPresentSrcs(a.ranch_id)) do
    TriggerClientEvent('sovereign_ranch:client:animal', src, view)
  end
end

--- Batch push after a SIM tick.
function Spawns.pushAnimals(ranchId, list)
  local views = {}
  for _, a in ipairs(list) do
    local v = Animals.view(a)
    v.netId = registry[a.id]
    views[#views + 1] = v
  end
  for _, src in ipairs(membersPresentSrcs(ranchId)) do
    TriggerClientEvent('sovereign_ranch:client:animals', src, views)
  end
end

--- Auto-pen every live animal of a ranch (nobody left to mind them, or
--- teardown). Positions persisted, peds deleted server-side, rows frozen.
local function penAll(ranchId, why)
  local n = 0
  for _, a in ipairs(Animals.herdOf(ranchId)) do
    if a.state == State.SPAWNED or a.state == State.TRANSIT
      or a.state == State.STRAYING or a.state == State.WRANGLING then
      Spawns.persistPosition(a)
      a.state = State.PENNED
      Animals.touch(a)
      Spawns.despawn(a)
      n = n + 1
    end
  end
  if n > 0 then
    Log.info('ranch %s: auto-penned %d animal(s) (%s)', tostring(ranchId), n, why)
    Animals.flush()
  end
end
Spawns.penAllLive = penAll

-- The presence sweep. Server-read positions only — no client pings, no
-- client trust. Cost: (#online members) × isInside every PresenceSeconds.
CreateThread(function()
  while true do
    Wait(math.max(5, tonumber(Config.PresenceSeconds) or 10) * 1000)

    local nowPresent = {}
    for _, sid in ipairs(GetPlayers()) do
      local src = tonumber(sid)
      local charid = Bridge.GetCharId(src)
      local m = charid and Members.get(charid)
      if m then
        local ranch = Ranches.get(m.ranch_id)
        local ped = GetPlayerPed(src)
        if ranch and ped and ped ~= 0 then
          local c = GetEntityCoords(ped)
          if Estate.isInside({ x = c.x, y = c.y, z = c.z }, ranch.ident) then
            local set = nowPresent[m.ranch_id]
            if not set then set = {}; nowPresent[m.ranch_id] = set end
            set[charid] = src
          end
        end
      end
    end

    -- Transitions.
    for ranchId, set in pairs(nowPresent) do
      -- Steward must be present; (re)elect when missing or departed.
      local s = steward[ranchId]
      local stillHere = false
      for _, src in pairs(set) do
        if src == s then stillHere = true break end
      end
      if not stillHere then
        local _, first = next(set)
        steward[ranchId] = first
        if s then Log.debug('ranch %d steward %s → %s', ranchId, tostring(s), tostring(first)) end
      end
    end
    for ranchId in pairs(present) do
      if not nowPresent[ranchId] then
        -- Last member left the property (or logged off): freeze the herd.
        steward[ranchId] = nil
        penAll(ranchId, 'nobody present')
      end
    end

    present = nowPresent
  end
end)

-- ============================================================================
-- Spawn orders (server → steward client) and replies
-- ============================================================================

local function orderSpawn(src, a, mode)
  local spec = Config.Animals[a.species]
  orders[a.id] = src
  TriggerClientEvent('sovereign_ranch:client:spawn', src, {
    animalId = a.id,
    model = spec.models[a.sex] or spec.models.f,
    x = a.pos and a.pos.x, y = a.pos and a.pos.y, z = a.pos and a.pos.z,
    name = a.name, species = a.species, sick = a.sick_state,
    mode = mode or 'pasture',   -- 'pasture' wanders; 'transit' follows the buyer
  })
end

--- Materialise a spawned-state animal through the ranch steward (release,
--- future re-spawn sweeps). No steward present → freeze back to penned.
function Spawns.materialise(a)
  local s = steward[a.ranch_id]
  if not s then
    a.state = State.PENNED
    Animals.touch(a)
    return false
  end
  orderSpawn(s, a, 'pasture')
  return true
end

--- Drive-home purchase (server/animals.lua): the BUYER is the order target
--- wherever they stand — the animals spawn at the dealer and follow them.
function Spawns.beginTransit(buyerSrc, ranch, rows)
  local d = Config.Market.dealer.coords
  local off = Config.Market.spawnOffset or { x = 4.0, y = 0.0, z = 0.0 }
  for i, a in ipairs(rows) do
    a.pos = { x = d.x + off.x + (i - 1) * 1.2, y = d.y + off.y, z = d.z + off.z }
    Animals.touch(a)
    orderSpawn(buyerSrc, a, 'transit')
  end
end

--- Steward's reply: the ped exists. Validated — the reply must come from
--- the src the order went to, and the netId must resolve to a real entity
--- server-side. Anything else is dropped with a log line.
RegisterNetEvent('sovereign_ranch:server:spawned', function(animalId, netId)
  local src = source
  animalId, netId = tonumber(animalId), tonumber(netId)
  if not animalId or not netId then return end
  if orders[animalId] ~= src then
    Log.warn('spawn reply for #%s from wrong src %s — dropped', tostring(animalId), tostring(src))
    return
  end
  orders[animalId] = nil
  local entity = NetworkGetEntityFromNetworkId(netId)
  if not entity or entity == 0 or not DoesEntityExist(entity) then
    Log.warn('spawn reply for #%d: netId %d resolves to nothing — dropped', animalId, netId)
    return
  end
  registry[animalId] = netId
  local a = Animals.get(animalId)
  if a then Spawns.pushAnimal(a) end
end)

--- Delete an animal's ped. Server-side DeleteEntity — no client required,
--- which is what makes the no-orphans guarantee unconditional.
function Spawns.despawn(a)
  local id = tonumber(a.id or a)
  local entity = Spawns.entityOf(id)
  if entity then DeleteEntity(entity) end
  registry[id] = nil
  orders[id] = nil
  -- Present members drop it from their local registries (prompt targeting).
  local row = Animals.get(id)
  local ranchId = row and row.ranch_id or (type(a) == 'table' and a.ranch_id)
  if ranchId then
    for _, src in ipairs(membersPresentSrcs(ranchId)) do
      TriggerClientEvent('sovereign_ranch:client:despawn', src, id)
    end
  end
end

-- ============================================================================
-- Transit home-detection: a transit animal crossing the home polygon
-- becomes a settled, spawned animal (design §8.3 buy-run).
-- ============================================================================

CreateThread(function()
  while true do
    Wait(5000)
    for animalId, netId in pairs(registry) do
      local a = Animals.get(animalId)
      if a and a.state == State.TRANSIT then
        local entity = Spawns.entityOf(animalId)
        if entity then
          local ranch = Ranches.get(a.ranch_id)
          local c = GetEntityCoords(entity)
          if ranch and Estate.isInside({ x = c.x, y = c.y, z = c.z }, ranch.ident) then
            a.state = State.SPAWNED
            a.pos = { x = c.x, y = c.y, z = c.z }
            Animals.touch(a)
            Spawns.pushAnimal(a)
            -- Every present member's client swaps follow → wander and hears
            -- about it; the buyer is among them by definition (they just
            -- walked the herd through the gate).
            for _, src in ipairs(membersPresentSrcs(a.ranch_id)) do
              TriggerClientEvent('sovereign_ranch:client:settle', src, animalId)
              Notify.card(src, T('bought_title'), T('transit_home'))
            end
          end
        end
      end
    end
  end
end)

-- ============================================================================
-- No-orphans guarantees
-- ============================================================================

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  for animalId in pairs(registry) do
    local entity = Spawns.entityOf(animalId)
    if entity then DeleteEntity(entity) end
  end
  registry = {}
  if probe and DoesEntityExist(probe.entity) then DeleteEntity(probe.entity) end
end)

-- ============================================================================
-- Phase 0: the server-spawn probe (kept for the record; the ruling it
-- produced — steward-client model — is what everything above implements).
-- ============================================================================

function Spawns.probe(src)
  if probe and DoesEntityExist(probe.entity) then
    return false, 'probe already live — /sr_probe_clear first'
  end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false, 'no player ped' end
  local c = GetEntityCoords(ped)
  local model = GetHashKey('a_c_cow')
  local entity = CreatePed(4, model, c.x + 2.0, c.y, c.z, 0.0, true, true)
  CreateThread(function()
    local waited = 0
    while waited < 5000 and not DoesEntityExist(entity) do
      Wait(250); waited = waited + 250
    end
    if not DoesEntityExist(entity) then
      Log.error('PROBE RESULT: CreatePed returned %s but no entity exists after 5s — server spawning NOT viable as-is (onesync=%s)',
        tostring(entity), GetConvar('onesync', 'off'))
      probe = nil
      return
    end
    local netId = 0
    pcall(function() netId = NetworkGetNetworkIdFromEntity(entity) end)
    probe = { entity = entity, netId = netId, model = 'a_c_cow', startedAt = os.time() }
    local pc = GetEntityCoords(entity)
    Log.info('PROBE RESULT: server ped EXISTS — entity %s, netId %s, at %.2f %.2f %.2f (onesync=%s).',
      tostring(entity), tostring(netId), pc.x, pc.y, pc.z, GetConvar('onesync', 'off'))
    if netId ~= 0 then
      TriggerClientEvent('sovereign_ranch:client:probeDress', src, netId)
    end
  end)
  return true, 'probe ped requested — watch the server console, then the world'
end

function Spawns.clearProbe()
  if probe and DoesEntityExist(probe.entity) then
    DeleteEntity(probe.entity)
  end
  probe = nil
  return true, 'probe cleared'
end
