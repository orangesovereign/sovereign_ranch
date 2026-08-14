--[[
  client/production.lua — the world side of Phase 2: manure piles, the
  butcher station, and the two buyer counters.

  Prompt discipline as established this phase: ONE prompt at a time,
  created on approach and DELETED on leave, because a registered prompt
  contests its control against every other prompt on the same key.
  Everything here shares INPUT_ENTER with the tend and trough prompts, so
  this loop picks a single winner by distance and shows only that.
]]

RanchManure = {}

local prompt   = nil
local target   = nil    -- 'manure' | 'manager' | 'store:<key>' | 'export'
local busy     = false

RegisterNetEvent('sovereign_ranch:client:manure', function(piles)
  RanchManure = type(piles) == 'table' and piles or {}
end)

-- ============================================================================
-- Candidates
-- ============================================================================

local function nearestManure(pc)
  local best, bestD2, bestIdx = nil, nil, nil
  for i, p in ipairs(RanchManure) do
    local dx, dy = pc.x - p.x, pc.y - p.y
    local d2 = dx * dx + dy * dy
    if (not bestD2 or d2 < bestD2) then best, bestD2, bestIdx = p, d2, i end
  end
  return best, bestD2, bestIdx
end

--- The butcher station and the on-ranch buyer both hang off mapped points,
--- which the server sends with the herd snapshot.
RanchPoints = {}
RegisterNetEvent('sovereign_ranch:client:points', function(points)
  RanchPoints = type(points) == 'table' and points or {}
end)

local function pointNear(pc, name)
  local p = RanchPoints[name]
  if not p then return nil end
  local dx, dy = pc.x - p.x, pc.y - p.y
  return p, dx * dx + dy * dy
end

-- ============================================================================
-- Actions
-- ============================================================================

local function doShovel(idx)
  if busy then return end
  busy = true
  CreateThread(function()
    local done = RanchScenarioAction({
      scenario = Config.CareAnims.fallback,
      duration = (Config.Production.manure.shovelSeconds or 6) * 1000,
      label = 'Shovelling...',
    })
    if done then TriggerServerEvent('sovereign_ranch:server:shovel', idx) end
    busy = false
  end)
end

local function openBuyer(kind)
  TriggerServerEvent('sovereign_ranch:server:requestPrices', kind)
end

-- ============================================================================
-- One prompt, nearest candidate wins
-- ============================================================================

local function dropPrompt()
  if prompt then prompt:delete(); prompt = nil end
  target = nil
end

local function ensurePrompt(label, onComplete)
  if prompt then
    prompt:setLabel(label)
    return
  end
  prompt = sv.interact.prompt({
    key = 'INPUT_ENTER',
    label = label,
    mode = 'hold', holdTime = 700,
    group = 'ranch_work', groupLabel = 'Ranch',
    onComplete = onComplete,
  })
end

CreateThread(function()
  while true do
    local wait = 1000
    local pc = GetEntityCoords(PlayerPedId(), true, true)

    -- Gather candidates with their squared distances, nearest wins.
    local best, bestD2, label, action = nil, nil, nil, nil

    local pile, pd2, pidx = nearestManure(pc)
    if pile and pd2 and pd2 <= 9.0 then
      best, bestD2 = 'manure', pd2
      label = 'Shovel Manure'
      action = function() doShovel(pidx) end
    end

    -- The ranch manager: one NPC, most of the business.
    if Config.Manager.enabled then
      local mgr, md2 = pointNear(pc, Config.Manager.point or 'manager')
      if mgr and md2 and md2 <= 9.0 and (not bestD2 or md2 < bestD2) then
        best, bestD2 = 'manager', md2
        label = Config.Manager.prompt or 'Speak with the Ranch Manager'
        action = function()
          TriggerServerEvent('sovereign_ranch:server:requestManager')
        end
      end
    end

    -- Every configured store: the coop basket, the larder, whatever else
    -- a property maps. Each uses its own point, or its fallback.
    for key, cfg in pairs(Config.Stores) do
      local at, sd2 = pointNear(pc, cfg.point)
      if not at and cfg.fallback then at, sd2 = pointNear(pc, cfg.fallback) end
      if at and sd2 and sd2 <= 9.0 and (not bestD2 or sd2 < bestD2) then
        best, bestD2 = 'store:' .. key, sd2
        label = cfg.prompt or cfg.label or 'Store'
        local storeKey = key
        action = function()
          TriggerServerEvent('sovereign_ranch:server:openStore', storeKey)
        end
      end
    end

    local exp = Config.Market.export
    if exp and exp.enabled and exp.surveyed then
      local dx, dy = pc.x - exp.coords.x, pc.y - exp.coords.y
      local ed2 = dx * dx + dy * dy
      if ed2 <= 9.0 and (not bestD2 or ed2 < bestD2) then
        best, bestD2 = 'export', ed2
        label = exp.promptLabel or 'Sell to the Exporter'
        action = function() openBuyer('export') end
      end
    end

    if best then
      target = best
      ensurePrompt(label, action)
      wait = 500
    else
      dropPrompt()
    end

    Wait(wait)
  end
end)

-- Manure piles are marked so they can be found; cheap, and only while some
-- exist and you are near them.
CreateThread(function()
  while true do
    local wait = 1000
    if #RanchManure > 0 then
      local pc = GetEntityCoords(PlayerPedId(), true, true)
      local drew = false
      for _, p in ipairs(RanchManure) do
        local dx, dy = pc.x - p.x, pc.y - p.y
        if (dx * dx + dy * dy) < 900.0 then
          sv.interact.marker({ x = p.x, y = p.y, z = p.z - 0.9 },
            { type = 'cylinder', scale = 0.5, height = 0.15,
              r = 120, g = 90, b = 50, a = 120 })
          drew = true
        end
      end
      if drew then wait = 0 end
    end
    Wait(wait)
  end
end)

-- ============================================================================
-- The ranch manager's ped. Local scenery at the mapped `manager` point
-- (same lineage as the dealer: dressed, frozen, untargetable). One NPC per
-- ranch by design — no point mapped, no manager.
-- ============================================================================

local buyerPed = nil

CreateThread(function()
  while true do
    local wait = 3000
    local cfg = Config.Manager
    local p = cfg and cfg.enabled and RanchPoints[cfg.point or 'manager']
    if p then
      local pc = GetEntityCoords(PlayerPedId(), true, true)
      local dx, dy = pc.x - p.x, pc.y - p.y
      local near = (dx * dx + dy * dy) < 14400.0    -- 120m
      if near and not buyerPed then
        local model = GetHashKey(cfg.model)
        if IsModelValid(model) then
          RequestModel(model, false)
          local tries = 0
          while not HasModelLoaded(model) and tries < 100 do Wait(50); tries = tries + 1 end
          if HasModelLoaded(model) then
            local ped = CreatePed(model, p.x, p.y, p.z, p.h or 0.0, false, true, true, true)
            local waits = 0
            while not DoesEntityExist(ped) and waits < 40 do Wait(50); waits = waits + 1 end
            SetModelAsNoLongerNeeded(model)
            if DoesEntityExist(ped) then
              SetEntityCoordsNoOffset(ped, p.x, p.y, p.z, false, false, false)
              SetEntityHeading(ped, p.h or 0.0)
              RanchDress(ped)                      -- the standing rule
              SetEntityInvincible(ped, true)
              SetBlockingOfNonTemporaryEvents(ped, true)
              FreezeEntityPosition(ped, true)
              SetPedCanBeTargetted(ped, false)
              buyerPed = ped
            end
          end
        end
      elseif not near and buyerPed then
        if DoesEntityExist(buyerPed) then DeleteEntity(buyerPed) end
        buyerPed = nil
      end
    end
    Wait(wait)
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  dropPrompt()
  if buyerPed and DoesEntityExist(buyerPed) then DeleteEntity(buyerPed) end
end)
