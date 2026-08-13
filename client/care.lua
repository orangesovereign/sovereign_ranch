--[[
  client/care.lua — tending prompts (design §9, Phase 1).

  One hold-prompt ("Tend"), proximity-gated by an adaptive loop over the
  local registry: near a spawned animal it enables and follows that animal;
  completing it opens a sovereign_ui context menu (Feed/Water/Brush/Treat/
  Rename/Pen filtered by species and what the server said about the
  animal). Every selection is only ever a REQUEST — the server re-validates
  membership, range, cooldowns and items.

  The multi-key context trap (lib CLAUDE.md: inputs outside the current
  control context silently never fire) is dodged by using exactly one
  verified OnFoot control (INPUT_ENTER) and putting the verbs in a menu.

  Perf: loop idles at 500ms with nothing near; text3d renders only while an
  animal is within 6m (design §9 perf rules).
]]

local prompt          -- the single reusable Tend prompt
local nearId = nil    -- animalId currently in tending range

local function nearestAnimal(maxDist)
  local pc = GetEntityCoords(PlayerPedId(), true, true)
  local best, bestId, bestPed = maxDist * maxDist, nil, nil
  for id, rec in pairs(RanchHerd) do
    if rec.netId then
      local ped = RanchEntity(id)
      if ped then
        local c = GetEntityCoords(ped, true, true)
        local dx, dy, dz = pc.x - c.x, pc.y - c.y, pc.z - c.z
        local d2 = dx * dx + dy * dy + dz * dz
        if d2 < best then best, bestId, bestPed = d2, id, ped end
      end
    end
  end
  return bestId, bestPed
end

local function tendLabel(rec)
  local v = rec.view or {}
  return ('Tend %s'):format(v.name or v.label or 'Animal')
end

-- ============================================================================
-- The tend menu — built from the last server-pushed view; the server is
-- the judge of every option picked.
-- ============================================================================

-- ============================================================================
-- Care animation + progress (design §9: sv.progress for every timed care
-- action; the scenario is flavor, the SERVER request at the end is the
-- deal). Scenario per verb/species from Config.CareAnims; female peds get
-- the game-proven fallback for anything outside Config.FemaleSafeAnims
-- (male-only conditional anims silently skip — the medical precedent).
-- IS_PED_MALE 0x6D9F5FAA7488BA46, TaskStartScenarioInPlaceHash
-- 0x524B54361229154F — both suite-proven call shapes.
-- ============================================================================

local performing = false

local function animFor(verb, species)
  local set = Config.CareAnims[verb]
  if not set then return nil, 0 end
  local name = set[species] or set.default
  local male = Citizen.InvokeNative(0x6D9F5FAA7488BA46, PlayerPedId())
  if not male and name and not Config.FemaleSafeAnims[name] then
    name = Config.CareAnims.fallback
  end
  return name, set.duration or 5000
end

--- Play the verb's scenario with a progress bar, then fire the server
--- request. Cancelling the bar cancels the deed — nothing is sent.
local function performCare(animalId, verb, serverEvent)
  if performing then return end
  performing = true
  CreateThread(function()
    local name, duration = animFor(verb, (RanchHerd[animalId] or {}).view
      and RanchHerd[animalId].view.species or nil)
    local ped = PlayerPedId()
    if name then
      Citizen.InvokeNative(0x524B54361229154F, ped, GetHashKey(name),
        duration + 500, true, false, false, false)
    end
    local done = sv.progress.start({
      label = ({ feed = 'Feeding...', water = 'Watering...',
                 brush = 'Brushing...', treat = 'Treating...' })[verb] or 'Working...',
      duration = duration, canCancel = true,
      disable = { 'attack', 'aim' },
    })
    ClearPedTasks(ped, true, true)
    if done then
      TriggerServerEvent(serverEvent, animalId, verb ~= 'treat' and verb or nil)
    end
    performing = false
  end)
end

local function openTend(animalId)
  local rec = RanchHerd[animalId]
  if not rec or not rec.view then return end
  local v = rec.view

  local actions = {
    { id = 'feed',  label = 'Feed',  description = ('Hunger %d/100'):format(v.hunger or 0) },
    { id = 'water', label = 'Water', description = ('Thirst %d/100'):format(v.thirst or 0) },
  }
  if v.groom ~= nil then
    actions[#actions + 1] = { id = 'brush', label = 'Brush', description = ('Coat %d/100'):format(v.groom) }
  end
  if v.sick ~= 'healthy' then
    actions[#actions + 1] = { id = 'treat', label = 'Treat',
      description = ('The animal is %s — medicine required'):format(v.sick) }
  end
  actions[#actions + 1] = { id = 'rename', label = 'Name', description = v.name or 'Unnamed' }
  actions[#actions + 1] = { id = 'pen', label = 'Send to Barn', description = 'Despawn to safety' }

  exports.sovereign_ui:OpenContext({
    title = v.name or v.label or 'Animal',
    actions = actions,
  }, function(actionId, kind)
    if kind ~= 'context' or not actionId then return end
    if actionId == 'feed' or actionId == 'water' or actionId == 'brush' then
      performCare(animalId, actionId, 'sovereign_ranch:server:care')
    elseif actionId == 'treat' then
      performCare(animalId, 'treat', 'sovereign_ranch:server:treat')
    elseif actionId == 'pen' then
      TriggerServerEvent('sovereign_ranch:server:pen', animalId)
    elseif actionId == 'rename' then
      exports.sovereign_ui:OpenInput({
        title = 'Name the Animal', label = 'Name',
        value = v.name or '', maxLength = 48,
      }, function(value, ikind)
        if ikind == 'input' and value and value ~= '' then
          TriggerServerEvent('sovereign_ranch:server:rename', animalId, value)
        end
      end)
    end
  end)
end

-- ============================================================================
-- The proximity loop
-- ============================================================================

CreateThread(function()
  prompt = sv.interact.prompt({
    key = 'INPUT_ENTER',
    label = 'Tend',
    mode = 'hold', holdTime = 800,
    enabled = false,
    onComplete = function()
      if nearId then openTend(nearId) end
    end,
  })

  while true do
    local id, ped = nearestAnimal(3.0)
    if id then
      if id ~= nearId then
        nearId = id
        prompt:setLabel(tendLabel(RanchHerd[id]))
      end
      prompt:enable(true)

      -- Status text over the animal while close — one loop, only when near.
      local shown = 0
      while shown < 10 do   -- re-check the nearest every ~10 frames batch
        local e = RanchEntity(id)
        if not e then break end
        local c = GetEntityCoords(e, true, true)
        local rec = RanchHerd[id]
        local v = rec and rec.view
        if v then
          local tag = v.name or v.label or ''
          if v.sick and v.sick ~= 'healthy' then
            tag = tag .. (' [%s]'):format(v.sick:upper())
          end
          sv.interact.text3d({ x = c.x, y = c.y, z = c.z + 1.2 }, tag, { maxDistance = 6.0 })
        end
        shown = shown + 1
        Wait(0)
      end
    else
      if nearId then
        nearId = nil
        prompt:enable(false)
      end
      Wait(500)
    end
  end
end)
