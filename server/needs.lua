--[[
  server/needs.lua — the SIM, Phase 1 slice (design §6.1-6.2 steps 1-2).

  Gate: a ranch is HOT when ≥1 member is physically present on the property
  (Spawns.presentAt — Phase 5 tightens this to on-duty). Only hot ranches
  tick; within one, only spawned|transit animals decay. `penned` rows are
  never read — pause-when-offline costs nothing.

  This tick: needs decay → sickness ladder → death. Growth/pregnancy are
  Phase 3 rungs of the SAME loop; production is Phase 2. Batched
  write-behind via Animals.touch + the flush thread.
]]

Needs = {}

local State = Enums.State

-- animalId -> epoch when a need first crossed the sick threshold / when the
-- animal turned sick. In-memory only: a restart forgives partial progress
-- toward sickness, which errs kind — never punishes a crash.
local lowSince  = {}
local sickSince = {}

function Needs.clearSickTimer(id)
  lowSince[id] = nil
  sickSince[id] = nil
end

local function needsLow(a, spec)
  local t = Config.Sickness.threshold or 25
  if a.hunger < t or a.thirst < t then return true end
  if spec.needsGroom and a.groom < t then return true end
  return false
end

--- Feed and water an animal from whatever it can reach (Wilbur ruling
--- 2026-08-13: animals help themselves). Returns the source it is using
--- so the client can walk it there and play the right scenario, or nil.
local function graze(a)
  local pos = Spawns.positionOf(a)
  if not pos then return nil end
  local seekAt = Config.Troughs.hungerSeekAt or 70

  -- Hunger first, then thirst — a beast eats before it drinks.
  for _, kind in ipairs({ 'feed', 'water' }) do
    local need = (kind == 'feed') and 'hunger' or 'thirst'
    if a[need] < seekAt then
      local src, d2, isScatter = Troughs.sourceFor(a, kind, pos)
      if src then
        local eatRange = (isScatter and Config.Scatter.eatRange
          or Config.Troughs.eatRange) or 3.0
        if d2 <= eatRange * eatRange then
          -- At the trough: eat.
          if Troughs.consume(src.key, isScatter) then
            local gain = (isScatter and Config.Scatter.restorePerTick
              or Config.Troughs.restorePerTick) or 20
            a[need] = math.min(100, a[need] + gain)
            return { kind = kind, x = src.x, y = src.y, z = src.z, eating = true }
          end
        else
          -- Within draw range but not there yet: head for it.
          return { kind = kind, x = src.x, y = src.y, z = src.z, eating = false }
        end
      end
    end
  end
  return nil
end

local function tickAnimal(a, spec, dt)
  -- 0. Eat/drink from anything in reach FIRST — a fed animal does not decay
  --    that need this tick.
  local feeding = graze(a)

  -- 1. Needs decay (per-hour config → per-tick), skipping what was just
  --    topped up at a trough.
  local perTick = dt / 3600
  if not (feeding and feeding.eating and feeding.kind == 'feed') then
    a.hunger = math.max(0, a.hunger - (spec.needs.hungerPerHour or 8) * perTick)
  end
  if not (feeding and feeding.eating and feeding.kind == 'water') then
    a.thirst = math.max(0, a.thirst - (spec.needs.thirstPerHour or 8) * perTick)
  end
  if spec.needsGroom then
    a.groom = math.max(0, a.groom - (spec.needs.groomPerHour or 4) * perTick)
  end
  a.feeding = feeding

  -- 3. Production: readiness accrues only on a well-kept animal, and the
  --    muck accrues regardless (Phase 2).
  Production.tick(a, spec, dt)
  Production.manureTick(a, dt)

  -- 2. Sickness ladder.
  local now = os.time()
  if a.sick_state == 'healthy' then
    if needsLow(a, spec) then
      lowSince[a.id] = lowSince[a.id] or now
      if (now - lowSince[a.id]) >= (Config.Sickness.sickAfterMinutes or 60) * 60 then
        a.sick_state = 'sick'
        sickSince[a.id] = now
        Log.debug('animal #%d is SICK', a.id)
      end
    else
      lowSince[a.id] = nil
    end
  elseif a.sick_state == 'sick' then
    if (now - (sickSince[a.id] or now)) >= (Config.Sickness.criticalAfterMinutes or 120) * 60 then
      a.sick_state = 'critical'
      Log.debug('animal #%d is CRITICAL', a.id)
    end
  elseif a.sick_state == 'critical' then
    a.health = math.max(0, a.health - (Config.Sickness.healthDrainPerTick or 5))
    if a.health <= 0 then
      Needs.clearSickTimer(a.id)
      Animals.die(a, 'neglect')
      return false   -- removed from cache; skip the touch
    end
  end

  return true
end

CreateThread(function()
  while true do
    local dt = math.max(15, tonumber(Config.TickSeconds) or 60)
    Wait(dt * 1000)

    for ranchId in pairs(Spawns.hotRanches()) do
      local changed = {}
      for _, a in ipairs(Animals.herdOf(ranchId)) do
        if a.state == State.SPAWNED or a.state == State.TRANSIT then
          if tickAnimal(a, Config.Animals[a.species], dt) then
            Animals.touch(a)
            changed[#changed + 1] = a
          end
        end
      end
      if #changed > 0 then
        Spawns.pushAnimals(ranchId, changed)
        Spawns.pushFeeding(ranchId, changed)   -- walk them to their trough
      end
    end
  end
end)
