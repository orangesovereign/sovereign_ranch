--[[
  server/requests.lua — the ONLY inbound net-event surface (Phase 1).

  Every handler: rate-limit by src → resolve charid → hand to the domain
  module, which re-validates everything (membership, capability, state,
  range, cooldown, funds). Handlers translate (ok, err) into player-facing
  notifications; they never mutate anything themselves.

  The suite rule stands: nothing here trusts a client beyond "this src
  asked for this thing".
]]

local Err = Enums.Err

-- Simple per-src, per-kind rate limiter: one action per `gap` ms.
local stamps = {}
local function limited(src, kind, gap)
  local key = src .. ':' .. kind
  local now = GetGameTimer()
  if stamps[key] and (now - stamps[key]) < (gap or 400) then return true end
  stamps[key] = now
  return false
end

AddEventHandler('playerDropped', function()
  local src = source
  for key in pairs(stamps) do
    if key:match('^' .. src .. ':') then stamps[key] = nil end
  end
end)

-- Uniform error voice.
local ERRTEXT = {
  [Err.NOT_MEMBER]    = 'not_a_member',
  [Err.NO_CAPABILITY] = 'no_permission',
  [Err.COOLDOWN]      = 'care_cooldown',
  [Err.HERD_FULL]     = 'herd_full',
  ERR_INSUFFICIENT_FUNDS = 'cannot_afford',
}

local function fail(src, err, ...)
  local key = ERRTEXT[err]
  Notify.toast(src, 'Ranch', key and T(key, ...) or T('no_permission'), 'warn')
end

-- ============================================================================
-- Care
-- ============================================================================

local CARE_OK = { feed = 'animal_fed', water = 'animal_watered', brush = 'animal_brushed' }

RegisterNetEvent('sovereign_ranch:server:care', function(animalId, verb)
  local src = source
  if limited(src, 'care', 1500) then return end
  verb = tostring(verb)
  if not CARE_OK[verb] then return end
  local ok, err = Animals.care(src, animalId, verb)
  if ok then
    Notify.card(src, 'Ranch', T(CARE_OK[verb]))
  elseif err == Err.COOLDOWN then
    Notify.toast(src, 'Ranch', T('care_cooldown'), 'info')
  elseif err == Err.BAD_ARG then
    Notify.toast(src, 'Ranch', T('care_too_far'), 'warn')
  else
    fail(src, err)
  end
end)

RegisterNetEvent('sovereign_ranch:server:treat', function(animalId)
  local src = source
  if limited(src, 'treat', 2000) then return end
  local ok, err = Animals.treat(src, animalId)
  if ok then
    Notify.card(src, 'Ranch', T('animal_treated'))
  elseif err == Err.BAD_ARG then
    local a = Animals.get(animalId)
    if a and a.sick_state == 'healthy' then
      Notify.toast(src, 'Ranch', T('not_sick'), 'info')
    else
      Notify.toast(src, 'Ranch', T('need_medicine', Config.MedicineItem), 'warn')
    end
  else
    fail(src, err)
  end
end)

-- ============================================================================
-- Troughs & scatter (the real feeding path — Wilbur ruling 2026-08-13)
-- ============================================================================

RegisterNetEvent('sovereign_ranch:server:fillTrough', function(kind, x, y, z)
  local src = source
  if limited(src, 'fill', 2000) then return end
  local ok, err = Troughs.fill(src, tostring(kind), x, y, z)
  if ok then
    Notify.card(src, 'Ranch', kind == 'water' and T('trough_watered') or T('trough_filled'))
  elseif err == Err.BUSY then
    Notify.toast(src, 'Ranch', T('trough_full'), 'info')
  elseif err == Err.BAD_ARG then
    Notify.toast(src, 'Ranch', T('care_too_far'), 'warn')
  else
    fail(src, err)
  end
end)

RegisterNetEvent('sovereign_ranch:server:scatterFeed', function()
  local src = source
  if limited(src, 'scatter', 2000) then return end
  local ok, err = Troughs.scatter(src)
  if ok then
    Notify.card(src, 'Ranch', T('feed_scattered'))
  else
    fail(src, err)
  end
end)

--- Trough state on demand (a client arriving at a ranch mid-session).
RegisterNetEvent('sovereign_ranch:server:requestTroughs', function()
  local src = source
  if limited(src, 'troughs', 1000) then return end
  local charid = Bridge.GetCharId(src)
  local m = charid and Members.get(charid)
  if not m then return end
  TriggerClientEvent('sovereign_ranch:client:troughs', src, {
    troughs = Troughs.activeFor(m.ranch_id),
    scatters = Troughs.scattersFor(m.ranch_id),
  })
end)

-- ============================================================================
-- Herd Book actions
-- ============================================================================

RegisterNetEvent('sovereign_ranch:server:rename', function(animalId, name)
  local src = source
  if limited(src, 'rename', 1000) then return end
  local ok, newName = Animals.rename(src, animalId, name)
  if ok and newName then
    Notify.card(src, 'Ranch', T('animal_renamed', newName))
  elseif not ok then
    fail(src, newName)
  end
end)

RegisterNetEvent('sovereign_ranch:server:release', function(animalId)
  local src = source
  if limited(src, 'penrelease', 1000) then return end
  local ok, err = Animals.release(src, animalId)
  if ok then
    Notify.card(src, 'Ranch', T('animal_released'))
  elseif err == Err.INTERNAL then
    Notify.toast(src, 'Ranch', T('release_failed'), 'warn')
  elseif err == Err.BAD_ARG then
    Notify.toast(src, 'Ranch', T('release_offsite'), 'warn')
  else
    fail(src, err)
  end
end)

RegisterNetEvent('sovereign_ranch:server:pen', function(animalId)
  local src = source
  if limited(src, 'penrelease', 1000) then return end
  local ok, err = Animals.pen(src, animalId)
  if ok then Notify.card(src, 'Ranch', T('animal_penned'))
  else fail(src, err) end
end)

--- Herd snapshot for the Herd Book: replies only to crew of that ranch.
RegisterNetEvent('sovereign_ranch:server:requestHerd', function()
  local src = source
  if limited(src, 'herd', 1000) then return end
  local charid = Bridge.GetCharId(src)
  local m = charid and Members.get(charid)
  if not m then return fail(src, Err.NOT_MEMBER) end
  local ranch = Ranches.get(m.ranch_id)
  TriggerClientEvent('sovereign_ranch:client:herd', src, {
    ident = ranch and ranch.ident,
    animals = Animals.herdView(m.ranch_id),
    grade = m.grade,
  })
end)

-- ============================================================================
-- Dealer
-- ============================================================================

RegisterNetEvent('sovereign_ranch:server:buy', function(species, sex, count, delivery)
  local src = source
  if limited(src, 'buy', 2000) then return end

  -- Proximity to the dealer is a server-side gate, same as the realestate
  -- land office: the buy menu only means something at the stockyard.
  local d = Config.Market.dealer
  if not (d.enabled and d.surveyed) then return end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return end
  local c = GetEntityCoords(ped)
  local dx, dy, dz = c.x - d.coords.x, c.y - d.coords.y, c.z - d.coords.z
  if (dx * dx + dy * dy + dz * dz) > (6.0 * 6.0) then return end

  local ok, res = Animals.buy(src, tostring(species), tostring(sex),
    tonumber(count), delivery == true)
  if not ok then
    if res == Err.NOT_MEMBER or res == Err.NO_CAPABILITY or res == Err.NO_RANCH then
      Notify.toast(src, 'Ranch', T('dealer_no_ranch'), 'warn')
    else
      fail(src, res)
    end
    return
  end
  if res.delivery then
    Notify.card(src, T('bought_title'),
      T('bought_delivery', res.count, Config.Market.DeliveryDelayMinutes or 10))
  else
    Notify.card(src, T('bought_title'), T('bought_drive', res.count))
  end
end)

--- Dealer stock list (species, labels, prices) for the menu — config only,
--- but served from the server so prices are never client-authored.
RegisterNetEvent('sovereign_ranch:server:requestDealer', function()
  local src = source
  if limited(src, 'dealer', 1000) then return end
  local stock = {}
  for species, spec in pairs(Config.Animals) do
    stock[#stock + 1] = {
      species = species, label = spec.label,
      sexLabels = spec.sexLabels,
      price = spec.price.buy,
      deliveryMult = spec.price.delivery or 1.25,
    }
  end
  table.sort(stock, function(x, y) return x.species < y.species end)
  TriggerClientEvent('sovereign_ranch:client:dealer', src, {
    stock = stock,
    maxPerPurchase = Config.Market.MaxPerPurchase or 5,
    deliveryDelay = Config.Market.DeliveryDelayMinutes or 10,
  })
end)
