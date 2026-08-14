--[[
  server/animals.lua — the herd (design §6, Phase 1 slice). Owns the
  in-memory animal cache, caps, buying (dealer drive-home + delivery),
  pen/release, rename, the care verbs and treatment. The needs SIM that
  decays these numbers lives in server/needs.lua; who is steward and which
  peds exist lives in server/spawns.lua.

  Authority rules: every mutation validates membership + capability +
  server-read positions. Clients only ever ask.
]]

Animals = {}

local Err = Enums.Err
local State = Enums.State

local byId    = {}   -- animalId -> animal row (live, write-behind)
local byRanch = {}   -- ranch_id -> { animalId -> row }
local dirty   = {}   -- animalId -> true (needs flush)

local careStamp = {} -- animalId -> { feed = epoch, water = epoch, brush = epoch }

-- ============================================================================
-- Cache
-- ============================================================================

local function index(a)
  byId[a.id] = a
  local herd = byRanch[a.ranch_id]
  if not herd then herd = {}; byRanch[a.ranch_id] = herd end
  herd[a.id] = a
end

local function unindex(a)
  byId[a.id] = nil
  careStamp[a.id] = nil
  dirty[a.id] = nil
  local herd = byRanch[a.ranch_id]
  if herd then herd[a.id] = nil end
end

function Animals.load()
  byId, byRanch, dirty = {}, {}, {}
  local rows = Db.loadAnimals() or {}
  local backfilled = 0
  for _, a in ipairs(rows) do
    a.id = tonumber(a.id); a.ranch_id = tonumber(a.ranch_id)
    a.sim_minutes = tonumber(a.sim_minutes) or 0
    a.scale = tonumber(a.scale) or 0.5
    a.variation = tonumber(a.variation) or 0
    a.health = tonumber(a.health) or 100
    a.hunger = tonumber(a.hunger) or 100
    a.thirst = tonumber(a.thirst) or 100
    a.groom  = tonumber(a.groom) or 100
    a.product_ready = tonumber(a.product_ready) == 1
    a.pos = type(a.pos) == 'string' and a.pos ~= '' and json.decode(a.pos) or nil
    -- 0 means "predates the variation column": give it a coat once, now,
    -- so an existing herd isn't a row of identical clones. New animals are
    -- always 1..999, so 0 is unambiguous.
    if a.variation == 0 then
      a.variation = math.random(1, 999)
      Db.setVariation(a.id, a.variation)
      backfilled = backfilled + 1
    end
    index(a)
  end
  Log.info('loaded %d animal(s)%s', #rows,
    backfilled > 0 and (' (%d given a coat)'):format(backfilled) or '')
end

function Animals.get(id) return byId[tonumber(id)] end

--- The living herd of one ranch as an array (stable order by id).
function Animals.herdOf(ranchId)
  local out = {}
  for _, a in pairs(byRanch[tonumber(ranchId)] or {}) do out[#out + 1] = a end
  table.sort(out, function(x, y) return x.id < y.id end)
  return out
end

function Animals.countOf(ranchId, species)
  local n = 0
  for _, a in pairs(byRanch[tonumber(ranchId)] or {}) do
    if not species or a.species == species then n = n + 1 end
  end
  return n
end

--- Mark changed; the flush thread and ranch-cold flush write it behind.
function Animals.touch(a) dirty[a.id] = true end

function Animals.flush()
  local n = 0
  for id in pairs(dirty) do
    local a = byId[id]
    if a then
      Db.flushAnimal({
        id = a.id, name = a.name, sim_minutes = a.sim_minutes, scale = a.scale,
        health = a.health, hunger = a.hunger, thirst = a.thirst, groom = a.groom,
        sick_state = a.sick_state, pregnant_until = a.pregnant_until,
        product_progress = a.product_progress, product_ready = a.product_ready,
        state = a.state, pos = a.pos and json.encode(a.pos) or '',
      })
      n = n + 1
    end
    dirty[id] = nil
  end
  if n > 0 then Log.debug('flushed %d animal row(s)', n) end
  return n
end

CreateThread(function()
  local minutes = math.max(1, tonumber(Config.FlushMinutes) or 5)
  while true do
    Wait(minutes * 60 * 1000)
    Animals.flush()
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  Animals.flush()
end)

-- ============================================================================
-- Creation & removal
-- ============================================================================

--- Create an animal on a ranch (buy, delivery, admin, later births).
--- Returns (ok, rowOrErr). Enforces the per-species cap.
function Animals.add(ranch, species, sex, opts)
  opts = opts or {}
  local spec = Config.Animals[species]
  if not spec then return false, Err.BAD_SPECIES end
  if sex ~= 'm' and sex ~= 'f' then return false, Err.BAD_ARG end
  if Animals.countOf(ranch.id, species) >= Config.MaxPerSpecies then
    return false, Err.HERD_FULL
  end

  local row = {
    ranch_id = ranch.id, species = species, sex = sex,
    name = opts.name, sim_minutes = opts.sim_minutes or 0,
    scale = opts.scale or 0.5, health = 100, hunger = 100, thirst = 100,
    groom = 100, sick_state = 'healthy',
    -- The animal's LOOK, decided once and never again: this beast wears
    -- the same coat from the day it is bought until it dies or is sold
    -- (Wilbur ruling 2026-08-13). The client mods it by the model's real
    -- preset count, so any number here is valid for any species. Never
    -- written by flushAnimal — immutable by construction.
    variation = opts.variation or math.random(1, 999),   -- 0 is reserved for "unset"
    state = opts.state or State.PENNED,
    pos = opts.pos and json.encode(opts.pos) or nil,
  }
  local id = Db.insertAnimal(row)
  if not id then return false, Err.INTERNAL end
  row.id = tonumber(id)
  row.pos = opts.pos
  row.product_ready = false
  row.variation = row.variation or 0
  index(row)
  return true, row
end

--- Remove an animal (admin / future market sale). reason for the event log.
function Animals.remove(animalId, reason)
  local a = byId[tonumber(animalId)]
  if not a then return false, Err.NO_ANIMAL end
  Spawns.despawn(a)            -- no-op if not spawned
  Db.deleteAnimal(a.id)
  unindex(a)
  Log.info('animal #%d (%s) removed: %s', a.id, a.species, tostring(reason))
  return true, nil
end

--- Death (called by the SIM). Row kept as the record, ped despawned, cache
--- slot freed so the species cap opens up.
function Animals.die(a, cause)
  Spawns.despawn(a)
  Db.markAnimalDead(a.id)
  unindex(a)
  local ranch = Ranches.get(a.ranch_id)
  Events.animalDied({ ident = ranch and ranch.ident, animalId = a.id,
                      species = a.species, cause = tostring(cause) })
  Log.discord('animals', 'Animal died', ('**%s** — %s (%s), cause: %s'):format(
    ranch and ranch.ident or '?', a.name or a.species, a.species, tostring(cause)))
  if ranch then Log.ranchDiscord(ranch, 'animals', 'Animal died',
    ('%s (%s) — %s'):format(a.name or a.species, a.species, tostring(cause))) end
  -- Tell everyone present so the loss is felt, not discovered.
  for _, m in ipairs(Members.crewOf(a.ranch_id)) do
    Notify.charToast(m.charid, T('animal_died_title'),
      T('animal_died', a.name or Animals.labelOf(a)), 'alert')
  end
end

--- Slaughter: like death, but deliberate and with no "it died" alarm to
--- the crew — the boss chose this. Row kept as the record, slot freed.
function Animals.slaughter(a, byCharid)
  Spawns.despawn(a)
  Db.markAnimalDead(a.id)
  unindex(a)
  local ranch = Ranches.get(a.ranch_id)
  Events.animalDied({ ident = ranch and ranch.ident, animalId = a.id,
                      species = a.species, cause = 'butchered' })
end

--- Life stage from simulated minutes (Phase 3 grows these for real; until
--- then everything reads 'prime', which is the neutral yield multiplier).
function Animals.stageOf(a)
  local bands = (Config.Animals[a.species].growth or {}).stages
  if not bands then return 'prime' end
  local mins = a.sim_minutes or 0
  local best = 'young'
  for _, name in ipairs({ 'young', 'prime', 'adult', 'old' }) do
    if bands[name] and mins >= bands[name] then best = name end
  end
  return best
end

--- Is this player close enough to the animal's ped to work on it? Server
--- reads the entity itself — the client never states its own distance.
function Animals.withinReach(src, a, range)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false end
  local entity = Spawns.entityOf(a.id)
  if not entity then return false end
  local pc, ac = GetEntityCoords(ped), GetEntityCoords(entity)
  local dx, dy, dz = pc.x - ac.x, pc.y - ac.y, pc.z - ac.z
  local reach = (range or 4.0) + 2.0
  return (dx * dx + dy * dy + dz * dz) <= reach * reach
end

--- 'Cow' / 'Bull' / species label fallback, for player-facing lines.
function Animals.labelOf(a)
  local spec = Config.Animals[a.species]
  return spec and (spec.sexLabels[a.sex] or spec.label) or a.species
end

-- ============================================================================
-- Public views (pushed to clients; nothing internal)
-- ============================================================================

function Animals.view(a)
  return {
    id = a.id, species = a.species, sex = a.sex, name = a.name,
    label = Animals.labelOf(a),
    state = a.state, sick = a.sick_state,
    ready = a.product_ready == true,
    produce = (Config.Animals[a.species].produce or {}).verb,
    hunger = math.floor(a.hunger), thirst = math.floor(a.thirst),
    groom = Config.Animals[a.species].needsGroom and math.floor(a.groom) or nil,
    health = math.floor(a.health),
  }
end

function Animals.herdView(ranchId)
  local out = {}
  for _, a in ipairs(Animals.herdOf(ranchId)) do out[#out + 1] = Animals.view(a) end
  return out
end

-- ============================================================================
-- Care verbs (feed / water / brush) + treatment. Server-validated: member,
-- animal on their ranch, spawned, in range (server-read entity coords),
-- per-animal cooldown, item where required.
-- ============================================================================

-- Only hands-on verbs live here now: feeding and watering happen at a
-- trough the animals visit themselves (server/troughs.lua).
local RESTORE_FIELD = { brush = 'groom' }

-- Plain-language bearing, so "where did my cow go" is answered in the
-- message rather than by walking the property. +y is north, +x is east.
local DIRS = { 'east', 'north-east', 'north', 'north-west',
               'west', 'south-west', 'south', 'south-east' }
local function compass(dx, dy)
  local ang = math.atan(dy, dx)
  return DIRS[math.floor((ang / math.pi) * 4 + 8.5) % 8 + 1]
end

local function inRange(src, a)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false end
  local entity = Spawns.entityOf(a.id)
  if not entity then return false end
  local pc = GetEntityCoords(ped)
  local ac = GetEntityCoords(entity)
  local dx, dy, dz = pc.x - ac.x, pc.y - ac.y, pc.z - ac.z
  return (dx * dx + dy * dy + dz * dz) <= (Config.CareRange + 2.0) ^ 2
end

--- One care action. verb ∈ feed|water|brush. Returns (ok, err) and pushes
--- the updated animal view to present members on success.
function Animals.care(src, animalId, verb)
  local field = RESTORE_FIELD[verb]
  if not field then return false, Err.BAD_ARG end
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local a = byId[tonumber(animalId)]
  if not a then return false, Err.NO_ANIMAL end
  local ok, err = Members.can(charid, 'care', a.ranch_id)
  if not ok then return false, err end
  if a.state ~= State.SPAWNED and a.state ~= State.TRANSIT then
    return false, Err.NO_ANIMAL
  end
  if verb == 'brush' and not Config.Animals[a.species].needsGroom then
    return false, Err.BAD_ARG
  end
  if not inRange(src, a) then return false, Err.BAD_ARG end

  local stamps = careStamp[a.id]
  if not stamps then stamps = {}; careStamp[a.id] = stamps end
  local cd = (Config.CareCooldownMinutes[verb] or 30) * 60
  if stamps[verb] and (os.time() - stamps[verb]) < cd then
    return false, Err.COOLDOWN
  end

  stamps[verb] = os.time()
  a[field] = math.min(100, (a[field] or 0) + (Config.CareRestore[verb] or 40))
  Animals.touch(a)
  Spawns.pushAnimal(a)
  return true, nil
end

--- Treat a sick animal (Foreman+, consumes Config.MedicineItem).
function Animals.treat(src, animalId)
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local a = byId[tonumber(animalId)]
  if not a then return false, Err.NO_ANIMAL end
  local ok, err = Members.can(charid, 'treat', a.ranch_id)
  if not ok then return false, err end
  if a.sick_state == 'healthy' then return false, Err.BAD_ARG end
  if not inRange(src, a) then return false, Err.BAD_ARG end

  if not Bridge.SubItem(src, Config.MedicineItem, 1) then
    return false, Err.BAD_ARG
  end

  a.sick_state = 'healthy'
  local floorv = Config.Sickness.treatRestoreNeeds or 50
  a.hunger = math.max(a.hunger, floorv)
  a.thirst = math.max(a.thirst, floorv)
  if Config.Animals[a.species].needsGroom then a.groom = math.max(a.groom, floorv) end
  Needs.clearSickTimer(a.id)
  Animals.touch(a)
  Spawns.pushAnimal(a)
  return true, nil
end

--- Rename (any member of the ranch).
function Animals.rename(src, animalId, name)
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local a = byId[tonumber(animalId)]
  if not a then return false, Err.NO_ANIMAL end
  local ok, err = Members.can(charid, 'care', a.ranch_id)
  if not ok then return false, err end
  name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 48)
  if name == '' then name = nil end
  a.name = name
  Animals.touch(a)
  Spawns.pushAnimal(a)
  return true, name
end

-- ============================================================================
-- Buying (design §8.3 buy-run, Phase 1 form). Foreman+ ('buy'), paid from
-- the ranch business account. Drive-home: rows created in TRANSIT and
-- spawned at the dealer following the buyer. Delivery: rows appear PENNED
-- after the delay, at a premium.
-- ============================================================================

function Animals.buy(src, species, sex, count, delivery)
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local m = Members.get(charid)
  if not m then return false, Err.NOT_MEMBER end
  local ok, err = Members.can(charid, 'buy', m.ranch_id)
  if not ok then return false, err end
  local ranch = Ranches.get(m.ranch_id)
  if not ranch or not ranch.biz_key then return false, Err.NO_RANCH end

  local spec = Config.Animals[tostring(species)]
  if not spec then return false, Err.BAD_SPECIES end
  if sex ~= 'm' and sex ~= 'f' then return false, Err.BAD_ARG end
  count = math.floor(tonumber(count) or 0)
  if count < 1 or count > (Config.Market.MaxPerPurchase or 5) then
    return false, Err.BAD_ARG
  end
  if Animals.countOf(ranch.id, species) + count > Config.MaxPerSpecies then
    return false, Err.HERD_FULL
  end

  local unit = spec.price.buy
  if delivery then unit = math.floor(unit * (spec.price.delivery or 1.25)) end
  local total = unit * count

  local idem = ('ranch:buy:%d:%d:%d'):format(ranch.id, charid, os.time())
  local paid, perr = Bank.debit(ranch.biz_key, total, Enums.Reason.LIVESTOCK_BUY,
    idem, ranch.ident)
  if not paid then return false, perr end

  local made = {}
  for _ = 1, count do
    local aok, row = Animals.add(ranch, species, sex, {
      state = delivery and State.PENNED or State.TRANSIT,
    })
    if aok then
      made[#made + 1] = row
      Events.animalBought({ ident = ranch.ident, animalId = row.id,
                            species = species, delivery = delivery == true })
    end
  end

  if delivery then
    -- Rows exist but stay invisible to the Herd Book until "arrival":
    -- simplest honest model is a notify on a timer; the rows are already
    -- penned and safe whatever happens to the timer.
    local delayMs = math.max(1, Config.Market.DeliveryDelayMinutes or 10) * 60 * 1000
    local ident, cid = ranch.ident, charid
    SetTimeout(delayMs, function()
      Notify.charCard(cid, T('delivery_title'), T('delivery_arrived'))
    end)
  else
    -- Drive home: hand the transit animals to the buyer's client to spawn
    -- at the dealer and walk-follow them (client/herd.lua).
    Spawns.beginTransit(src, ranch, made)
  end

  Log.discord('market', 'Livestock bought', ('**%s** — %d × %s %s (%s)'):format(
    ranch.ident, count, species, sex, delivery and 'delivery' or 'drive-home'))
  return true, { count = #made, total = total, delivery = delivery == true }
end

-- ============================================================================
-- Pen / release
-- ============================================================================

--- Release a penned animal to pasture. If the ranch is MAPPED
--- (config/ranches.lua), the animal materialises at its anchor — coop for
--- chickens, barn for everything else — with a small scatter so a batch
--- release doesn't stack peds. Unmapped ranches keep the fallback: beside
--- the releasing member. Either way the releaser must be physically inside
--- the property (server-verified).
function Animals.release(src, animalId)
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local a = byId[tonumber(animalId)]
  if not a then return false, Err.NO_ANIMAL end
  local ok, err = Members.can(charid, 'care', a.ranch_id)
  if not ok then return false, err end
  if a.state ~= State.PENNED then return false, Err.BUSY end
  local ranch = Ranches.get(a.ranch_id)

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false, Err.INTERNAL end
  local c = GetEntityCoords(ped)
  if not Estate.isInside({ x = c.x, y = c.y, z = c.z }, ranch.ident) then
    return false, Err.BAD_ARG
  end
  if Spawns.spawnedCount(a.ranch_id) >= (Config.MaxSpawnedPerRanch or 40) then
    return false, Err.BUSY
  end

  -- Open-ground anchor for the species (never a building interior — the
  -- client still ground-snaps and safe-coords whatever we send).
  local anchor = Ranches.releaseAnchor(ranch.ident, a.species)
  if anchor then
    local spread = Config.Wander and Config.Wander.scatter or 2.5
    local ang = math.random() * 2 * math.pi
    local dist = 1.0 + math.random() * spread
    a.pos = { x = anchor.x + math.cos(ang) * dist,
              y = anchor.y + math.sin(ang) * dist, z = anchor.z }
  else
    a.pos = { x = c.x + 1.5, y = c.y, z = c.z }
  end
  a.state = State.SPAWNED
  Animals.touch(a)
  -- Honour the result: telling a player their animal is out when nothing
  -- was spawned is worse than refusing (live finding 2026-08-13). The
  -- releaser is the spawn target — they are standing right here.
  if not Spawns.materialise(a, src) then
    return false, Err.INTERNAL
  end

  -- Report WHERE it went. An anchor can be the far side of the property
  -- (Beecher's Hope pasture is ~96 m from its barn), and an animal you
  -- cannot see reads exactly like an animal that never spawned.
  local pdx, pdy = a.pos.x - c.x, a.pos.y - c.y
  return true, {
    dist = math.floor(math.sqrt(pdx * pdx + pdy * pdy) + 0.5),
    dir  = compass(pdx, pdy),
    anchored = anchor ~= nil,
  }
end

--- Pen a spawned animal: current position saved, ped despawned, frozen.
function Animals.pen(src, animalId)
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local a = byId[tonumber(animalId)]
  if not a then return false, Err.NO_ANIMAL end
  local ok, err = Members.can(charid, 'care', a.ranch_id)
  if not ok then return false, err end
  if a.state ~= State.SPAWNED and a.state ~= State.TRANSIT then
    return false, Err.BUSY
  end

  Spawns.persistPosition(a)
  a.state = State.PENNED
  Animals.touch(a)
  Spawns.despawn(a)
  return true, nil
end

-- ============================================================================
-- Teardown support (Ranches.teardown): purge a ranch's rows from the cache
-- after the herd wipe — the DB delete alone would leave ghosts in memory.
-- ============================================================================

function Animals.dropRanch(ranchId)
  for id, a in pairs(byRanch[tonumber(ranchId)] or {}) do
    unindex(a)
  end
  byRanch[tonumber(ranchId)] = nil
end
