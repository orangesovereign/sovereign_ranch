--[[
  client/menus.lua — management surfaces (design §9, Phase 1): the Herd
  Book and the livestock dealer. All sovereign_ui exports; zero NUI of our
  own; every choice is a request the server re-validates.

  The dealer ped is LOCAL scenery (the realestate clerk lineage): each
  client streams its own, dressed per the standing rule, frozen, and
  removed on resource stop via sv.ownership? No — peds aren't a kernel
  kind; an onResourceStop delete keeps it clean.
]]

-- ============================================================================
-- Herd Book (/herdbook) — list, then per-animal context.
-- ============================================================================

local function openHerdBook(data)
  local items = {}
  for _, v in ipairs(data.animals or {}) do
    local state = v.state == 'penned' and 'Barn' or (v.state:gsub('^%l', string.upper))
    local badge = v.sick ~= 'healthy' and (' · %s'):format(v.sick:upper()) or ''
    items[#items + 1] = {
      id = tostring(v.id),
      label = ('%s — %s'):format(v.name or 'Unnamed', v.label),
      description = ('%s · Hunger %d · Thirst %d%s'):format(
        state, v.hunger or 0, v.thirst or 0, badge),
    }
  end
  if #items == 0 then
    exports.sovereign_ui:Notify({ tone = 'info', title = 'Herd Book',
      message = 'No animals on the books. See the dealer in Valentine.' })
    return
  end

  exports.sovereign_ui:OpenMenu({
    title = 'Herd Book',
    eyebrow = data.ident or 'Ranch',
    items = items,
  }, function(value, kind)
    if kind ~= 'menu' or not value then return end
    local animalId = tonumber(value)
    local view
    for _, v in ipairs(data.animals) do
      if v.id == animalId then view = v break end
    end
    if not view then return end

    local actions = {}
    if view.state == 'penned' then
      actions[#actions + 1] = { id = 'release', label = 'Lead to Pasture',
        description = 'Spawns beside you — stand on your land' }
    elseif view.state == 'spawned' or view.state == 'transit' then
      actions[#actions + 1] = { id = 'pen', label = 'Send to Barn',
        description = 'Stows the animal safely' }
    end
    actions[#actions + 1] = { id = 'rename', label = 'Name',
      description = view.name or 'Unnamed' }

    exports.sovereign_ui:OpenContext({
      title = view.name or view.label, actions = actions,
    }, function(actionId, ckind)
      if ckind ~= 'context' or not actionId then return end
      if actionId == 'release' then
        TriggerServerEvent('sovereign_ranch:server:release', animalId)
      elseif actionId == 'pen' then
        TriggerServerEvent('sovereign_ranch:server:pen', animalId)
      elseif actionId == 'rename' then
        exports.sovereign_ui:OpenInput({
          title = 'Name the Animal', label = 'Name',
          value = view.name or '', maxLength = 48,
        }, function(value2, ikind)
          if ikind == 'input' and value2 and value2 ~= '' then
            TriggerServerEvent('sovereign_ranch:server:rename', animalId, value2)
          end
        end)
      end
    end)
  end)
end

RegisterNetEvent('sovereign_ranch:client:herd', function(data)
  if type(data) ~= 'table' then return end
  openHerdBook(data)
end)

RegisterCommand('herdbook', function()
  TriggerServerEvent('sovereign_ranch:server:requestHerd')
end, false)

-- ============================================================================
--- The dealer (Phase 1: buying only)
-- ============================================================================

local dealerPed = nil
local dealerPrompt = nil

local function fmtDollars(cents)
  return ('$%.2f'):format((tonumber(cents) or 0) / 100)
end

local function openDealer(data)
  local items = {}
  for _, s in ipairs(data.stock or {}) do
    items[#items + 1] = {
      id = s.species,
      label = s.label,
      description = ('%s a head · delivery ×%.2f'):format(fmtDollars(s.price), s.deliveryMult),
    }
  end

  exports.sovereign_ui:OpenMenu({
    title = 'Livestock Dealer', eyebrow = 'Valentine Stockyard', items = items,
  }, function(species, kind)
    if kind ~= 'menu' or not species then return end
    local stock
    for _, s in ipairs(data.stock) do if s.species == species then stock = s end end
    if not stock then return end

    exports.sovereign_ui:OpenContext({
      title = stock.label,
      actions = {
        { id = 'f', label = stock.sexLabels.f, description = 'Female' },
        { id = 'm', label = stock.sexLabels.m, description = 'Male' },
      },
    }, function(sex, ckind)
      if ckind ~= 'context' or not sex then return end
      exports.sovereign_ui:OpenQuantity({
        label = 'How many head?', value = 1, min = 1,
        max = data.maxPerPurchase or 5, unit = 'head',
      }, function(count, qkind)
        if qkind ~= 'quantity' then return end
        count = tonumber(count)
        if not count or count < 1 then return end

        exports.sovereign_ui:OpenContext({
          title = ('%d × %s'):format(count, stock.label),
          actions = {
            { id = 'drive', label = 'Drive Them Home',
              description = ('%s — they follow you at a walk'):format(
                fmtDollars(stock.price * count)) },
            { id = 'delivery', label = 'Have Them Delivered',
              description = ('%s — in the barn in ~%d min'):format(
                fmtDollars(math.floor(stock.price * stock.deliveryMult) * count),
                data.deliveryDelay or 10) },
          },
        }, function(how, hkind)
          if hkind ~= 'context' or not how then return end
          local delivery = how == 'delivery'
          local unit = delivery and math.floor(stock.price * stock.deliveryMult) or stock.price
          exports.sovereign_ui:OpenConfirm({
            title = 'Sign for the stock?',
            description = ('%d × %s, %s. Paid from the ranch account.'):format(
              count, stock.label, fmtDollars(unit * count)),
            tone = 'warning', confirmLabel = 'Sign',
          }, function(confirmed)
            if confirmed then
              TriggerServerEvent('sovereign_ranch:server:buy', species, sex, count, delivery)
            end
          end)
        end)
      end)
    end)
  end)
end

RegisterNetEvent('sovereign_ranch:client:dealer', function(data)
  if type(data) ~= 'table' then return end
  openDealer(data)
end)

-- Dealer ped streamer + prompt (only when surveyed).
CreateThread(function()
  local d = Config.Market.dealer
  if not (d and d.enabled and d.surveyed) then return end

  local at = vector3(d.coords.x, d.coords.y, d.coords.z)

  -- GROUPED, deliberately: the library's INTERACT ledger verified grouped
  -- prompts live (shared header + range-gated group activation), while the
  -- ungrouped-with-context-point path is documented but unproven — and an
  -- ungrouped dealer prompt did not draw at all on this server (live
  -- finding 2026-08-13). The group activation is what actually shows a
  -- context-culled prompt; the library range-gates it for us.
  dealerPrompt = sv.interact.prompt({
    key = 'INPUT_ENTER',
    label = d.promptLabel or 'Speak with the Dealer',
    mode = 'hold', holdTime = 600,
    coords = at, radius = 3.0,
    group = 'ranch_dealer', groupLabel = 'Livestock Dealer',
    onComplete = function()
      TriggerServerEvent('sovereign_ranch:server:requestDealer')
    end,
  })

  while true do
    local dist = #(GetEntityCoords(PlayerPedId(), true, true) - at)
    if dist < 120.0 and not dealerPed then
      local model = GetHashKey(d.model)
      if IsModelValid(model) then
        RequestModel(model, false)
        local tries = 0
        while not HasModelLoaded(model) and tries < 100 do Wait(50) tries = tries + 1 end
        if HasModelLoaded(model) then
          local ped = CreatePed(model, at.x, at.y, at.z, d.coords.h or 0.0, false, true, true, true)
          local waits = 0
          while not DoesEntityExist(ped) and waits < 40 do Wait(50) waits = waits + 1 end
          SetModelAsNoLongerNeeded(model)
          if DoesEntityExist(ped) then
            SetEntityCoordsNoOffset(ped, at.x, at.y, at.z, false, false, false)
            SetEntityHeading(ped, d.coords.h or 0.0)
            RanchDress(ped)
            SetEntityVisible(ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            FreezeEntityPosition(ped, true)
            SetPedCanBeTargetted(ped, false)
            dealerPed = ped
          end
        end
      end
    elseif dist >= 150.0 and dealerPed then
      if DoesEntityExist(dealerPed) then DeleteEntity(dealerPed) end
      dealerPed = nil
    end
    Wait(2000)
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  if dealerPed and DoesEntityExist(dealerPed) then DeleteEntity(dealerPed) end
end)

-- ============================================================================
-- /sr_prompts — client diagnostic (read-only, prints to F8). Answers the
-- questions guessing cannot: is the prompt registered at all, is the ped
-- there, and how far away am I from the point the engine culls against?
-- ============================================================================

RegisterCommand('sr_prompts', function()
  local d = Config.Market and Config.Market.dealer
  print('--- sovereign_ranch prompt diagnostic ---')
  if not d then
    print('  Config.Market.dealer is NIL — config/market.lua not loaded client-side')
    return
  end
  print(('  dealer: enabled=%s surveyed=%s model=%s')
    :format(tostring(d.enabled), tostring(d.surveyed), tostring(d.model)))
  print(('  dealer point: %.2f %.2f %.2f'):format(d.coords.x, d.coords.y, d.coords.z))

  local c = GetEntityCoords(PlayerPedId(), true, true)
  local dx, dy, dz = c.x - d.coords.x, c.y - d.coords.y, c.z - d.coords.z
  print(('  you: %.2f %.2f %.2f  → distance %.2fm (prompt radius 3.0)')
    :format(c.x, c.y, c.z, math.sqrt(dx * dx + dy * dy + dz * dz)))

  print(('  dealer prompt object: %s | valid: %s')
    :format(dealerPrompt and 'created' or 'NIL — the spawn thread never reached it',
            dealerPrompt and tostring(dealerPrompt:isValid()) or 'n/a'))
  print(('  dealer ped: %s'):format(
    dealerPed and DoesEntityExist(dealerPed) and 'spawned' or 'not spawned'))
  print(('  prompts owned by this resource: %d'):format(sv.interact.count()))

  local n = 0
  for _ in pairs(RanchHerd or {}) do n = n + 1 end
  print(('  animals known to this client: %d'):format(n))
  print('----------------------------------------')
end, false)
