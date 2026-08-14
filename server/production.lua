--[[
  server/production.lua — what the herd is FOR (design §7).

  Readiness is passive and earned: an animal accrues toward its next
  product only while fed, watered and healthy, so neglect does not merely
  risk the beast — it stops the income. Collection is an active,
  server-validated interaction that grants real inventory items.

  Also here: manure (accrues where livestock stand, shovelled for
  fertiliser) and butchering (a Rancher-only decision that ends an animal
  and yields a carcass table).

  Every yield is rolled SERVER-side. The client asked; it never says how
  much it got.
]]

Production = {}

local Err = Enums.Err
local State = Enums.State

-- ranch_id -> { {x, y, z, units}, ... }  piles waiting to be shovelled
local manure = {}

-- ============================================================================
-- Readiness — called from the SIM tick, once per live animal
-- ============================================================================

--- Accrue progress toward this animal's next product. Returns true when
--- the animal newly became ready (so the tick can push/announce it).
function Production.tick(a, spec, dt)
  local p = spec.produce
  if not p then return false end
  if p.femaleOnly and a.sex ~= 'f' then return false end
  if a.product_ready then return false end

  local cfg = Config.Production
  if cfg.requireHealthy and a.sick_state ~= 'healthy' then return false end
  local floor = cfg.needThreshold or 50
  if a.hunger < floor or a.thirst < floor then return false end

  a.product_progress = (a.product_progress or 0) + (dt / 60)
  if a.product_progress >= (p.minutes or 60) then
    a.product_progress = 0
    a.product_ready = true
    return true
  end
  return false
end

--- Is there something to take off this animal right now?
function Production.readyOn(a)
  local spec = Config.Animals[a.species]
  return spec and spec.produce and a.product_ready == true
end

-- ============================================================================
-- Collection
-- ============================================================================

--- Take the product off an animal. Server validates membership, capability,
--- state, readiness and distance, then rolls the yield itself.
--- Returns (ok, { item, count }) or (false, err).
function Production.collect(src, animalId)
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local a = Animals.get(animalId)
  if not a then return false, Err.NO_ANIMAL end
  local ok, err = Members.can(charid, 'collect', a.ranch_id)
  if not ok then return false, err end

  local spec = Config.Animals[a.species]
  local p = spec and spec.produce
  if not p then return false, Err.BAD_ARG end
  if not a.product_ready then return false, Err.COOLDOWN end
  if a.state ~= State.SPAWNED and a.state ~= State.TRANSIT then
    return false, Err.NO_ANIMAL
  end
  if not Animals.withinReach(src, a, Config.Production.collectRange) then
    return false, Err.BAD_ARG
  end

  local lo, hi = (p.yield or { 1, 1 })[1], (p.yield or { 1, 1 })[2]
  local count = math.random(lo, hi)
  if not Bridge.AddItem(src, p.item, count) then return false, Err.INTERNAL end

  a.product_ready = false
  a.product_progress = 0
  Animals.touch(a)
  Spawns.pushAnimal(a)

  local ranch = Ranches.get(a.ranch_id)
  Events.productCollected({ ident = ranch and ranch.ident, animalId = a.id,
                            item = p.item, count = count })
  return true, { item = p.item, count = count }
end

-- ============================================================================
-- Manure — accrues where livestock stand, shovelled for fertiliser
-- ============================================================================

--- Called from the SIM tick per live animal; occasionally drops a pile at
--- the animal's feet. Chickens are exempt (their droppings are not a crop).
function Production.manureTick(a, dt)
  local cfg = Config.Production.manure
  if not (cfg and cfg.enabled) then return end
  if Config.Animals[a.species].scattered then return end

  local piles = manure[a.ranch_id]
  if not piles then piles = {}; manure[a.ranch_id] = piles end
  if #piles >= (cfg.maxPerRanch or 12) then return end

  -- Probability per tick that this animal has left one behind.
  local perHour = 1 / math.max(1, cfg.perAnimalHours or 6)
  if math.random() > (perHour * (dt / 3600)) then return end

  local pos = Spawns.positionOf(a)
  if not pos then return end
  piles[#piles + 1] = { x = pos.x, y = pos.y, z = pos.z,
                        units = math.random(cfg.yield[1], cfg.yield[2]) }
  Spawns.pushManure(a.ranch_id)
end

function Production.manureFor(ranchId)
  return manure[tonumber(ranchId)] or {}
end

--- Shovel a pile. Returns (ok, { item, count }) or (false, err).
function Production.shovel(src, index)
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local m = Members.get(charid)
  if not m then return false, Err.NOT_MEMBER end
  local ok, err = Members.can(charid, 'care', m.ranch_id)
  if not ok then return false, err end

  local piles = manure[m.ranch_id]
  local pile = piles and piles[tonumber(index)]
  if not pile then return false, Err.BAD_ARG end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false, Err.INTERNAL end
  local c = GetEntityCoords(ped)
  local dx, dy = c.x - pile.x, c.y - pile.y
  if (dx * dx + dy * dy) > 16.0 then return false, Err.BAD_ARG end

  local cfg = Config.Production.manure
  if not Bridge.AddItem(src, cfg.item, pile.units) then return false, Err.INTERNAL end
  table.remove(piles, tonumber(index))
  Spawns.pushManure(m.ranch_id)
  return true, { item = cfg.item, count = pile.units }
end

function Production.clearManure(ranchId)
  manure[tonumber(ranchId)] = nil
end

-- ============================================================================
-- Butchering — a Rancher's decision, and it is final
-- ============================================================================

--- Butcher an animal at the station. Returns (ok, { {item, count}, ... }).
function Production.butcher(src, animalId)
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local a = Animals.get(animalId)
  if not a then return false, Err.NO_ANIMAL end
  -- 'manage' = Rancher only (design §5.2: slaughter is the boss's call).
  local ok, err = Members.can(charid, 'manage', a.ranch_id)
  if not ok then return false, err end

  local ranch = Ranches.get(a.ranch_id)
  local station = ranch and Ranches.pointsOf(ranch.ident)[Config.Production.butcher.point]
  if not station then return false, Err.BAD_ARG end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false, Err.INTERNAL end
  local c = GetEntityCoords(ped)
  local dx, dy = c.x - station.x, c.y - station.y
  local reach = (Config.Production.butcher.promptRange or 2.0) + 3.0
  if (dx * dx + dy * dy) > reach * reach then return false, Err.BAD_ARG end

  local spec = Config.Animals[a.species]
  local table_ = spec and spec.butcher
  if not table_ then return false, Err.BAD_ARG end

  -- Life stage scales the carcass (a calf is not a steer).
  local stage = Animals.stageOf(a)
  local scale = (Config.Production.stageYield or {})[stage] or 1.0

  local granted = {}
  for _, row in ipairs(table_) do
    local count = math.floor(math.random(row.min, row.max) * scale + 0.5)
    if count > 0 and Bridge.AddItem(src, row.item, count) then
      granted[#granted + 1] = { item = row.item, count = count }
    end
  end

  local name = a.name or Animals.labelOf(a)
  Animals.slaughter(a, charid)
  Log.discord('animals', 'Animal butchered', ('**%s** — %s (%s) by %s'):format(
    ranch.ident, name, a.species, Bridge.GetCharName(charid)))
  return true, granted
end
