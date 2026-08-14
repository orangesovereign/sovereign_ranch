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

--- Walk the hand to the animal's FLANK and settle both of them before any
--- hands-on work (Wilbur note 2026-08-13: the brush has to actually reach
--- the animal). The animal is held still for the duration, so it cannot
--- amble off mid-stroke. Natives verified in RDR3:
---   GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS 0x1899F328B0E12848
---   TASK_GO_STRAIGHT_TO_COORD              0xD76B57B44F1E6F8B (9 params)
---   TASK_TURN_PED_TO_FACE_ENTITY           0x5AD23D40115353AC (6 params, not 3)
---   TASK_STAND_STILL                       0x919BE13EED931959
local function approachAnimal(animalId, animalPed, holdMs)
  local ped = PlayerPedId()

  -- Hold the animal where it stands, then take up position at its left
  -- flank — brushing a moving cow from two metres away looks like mime.
  -- RanchHold also parks the ROAM LOOP for this animal: without that it
  -- re-tasks every 2 s and walks the beast out from under you, which is
  -- what "the cow runs off when I try to brush it" actually was.
  RanchHold(animalId, holdMs)

  local side = GetOffsetFromEntityInWorldCoords(animalPed, -1.1, 0.0, 0.0)
  TaskGoStraightToCoord(ped, side.x, side.y, side.z, 1.0, 3000,
    GetEntityHeading(animalPed) + 90.0, 0.2, 0)

  local waited = 0
  while waited < 3000 do
    local c = GetEntityCoords(ped, true, true)
    local dx, dy = c.x - side.x, c.y - side.y
    if (dx * dx + dy * dy) < 0.6 then break end
    Wait(100); waited = waited + 100
  end

  ClearPedTasks(ped, true, true)
  TaskTurnPedToFaceEntity(ped, animalPed, 700, 0.0, 0.0, 0.0)
  Wait(500)
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

    -- Hands-on verbs need to be within arm's reach of the animal.
    local animalPed = RanchEntity(animalId)
    if animalPed then approachAnimal(animalId, animalPed, duration + 6000) end

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
    -- Let the animal get back to its business either way.
    RanchResumeIdle(animalId)
    performing = false
  end)
end

--- Scatter chicken feed at your feet: the grain-throwing scenario, then the
--- server decides whether it counted. The birds converge on the spot.
function performScatter()
  if performing then return end
  performing = true
  CreateThread(function()
    local ped = PlayerPedId()
    local set = Config.CareAnims.feed
    local name = (set and set.chicken) or Config.CareAnims.fallback
    local duration = (set and set.duration) or 5000
    Citizen.InvokeNative(0x524B54361229154F, ped, GetHashKey(name),
      duration + 500, true, false, false, false)
    local done = sv.progress.start({
      label = 'Scattering feed...', duration = duration,
      canCancel = true, disable = { 'attack', 'aim' },
    })
    ClearPedTasks(ped, true, true)
    if done then TriggerServerEvent('sovereign_ranch:server:scatterFeed') end
    performing = false
  end)
end

local function openTend(animalId)
  local rec = RanchHerd[animalId]
  if not rec or not rec.view then return end
  local v = rec.view

  -- Feeding and watering are NOT here: livestock help themselves from a
  -- filled trough, and chickens eat feed scattered on the ground (Wilbur
  -- ruling 2026-08-13). What is left is genuinely hands-on work.
  local actions = {}
  local scattered = Config.Animals[v.species] and Config.Animals[v.species].scattered
  if scattered then
    actions[#actions + 1] = { id = 'scatter', label = 'Scatter Feed',
      description = 'Throw feed on the ground here — the birds will come' }
  end
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
    title = ('%s — Hunger %d · Thirst %d'):format(
      v.name or v.label or 'Animal', v.hunger or 0, v.thirst or 0),
    actions = actions,
  }, function(actionId, kind)
    if kind ~= 'context' or not actionId then return end
    if actionId == 'brush' then
      performCare(animalId, actionId, 'sovereign_ranch:server:care')
    elseif actionId == 'scatter' then
      performScatter()
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

--- Both the Tend prompt and the dealer prompt ride INPUT_ENTER; a
--- drive-home cow stands 4m from the dealer at purchase, so without this
--- guard one held E would complete BOTH prompts at once.
local function nearDealer()
  local d = Config.Market and Config.Market.dealer
  if not (d and d.enabled and d.surveyed) then return false end
  local c = GetEntityCoords(PlayerPedId(), true, true)
  local dx, dy, dz = c.x - d.coords.x, c.y - d.coords.y, c.z - d.coords.z
  return (dx * dx + dy * dy + dz * dz) <= (4.0 * 4.0)
end

--- The Tend prompt EXISTS only while an animal is in range. Keeping an
--- idle prompt registered — even disabled, even invisible — contests its
--- control against every other INPUT_ENTER prompt on screen and can
--- suppress them outright (live findings 2026-08-13: first it ghosted
--- greyed on the dealer, then, hidden, it still swallowed the dealer's
--- prompt). Create on approach, delete on leave: sv.interact's delete()
--- is a real native unregister, so nothing is left to contend.

local function ensurePrompt(label)
  if prompt then
    prompt:setLabel(label)
    return
  end
  prompt = sv.interact.prompt({
    key = 'INPUT_ENTER',
    label = label,
    mode = 'hold', holdTime = 800,
    -- GROUPED is the library's live-verified path (INTERACT-LEDGER rows
    -- 239/247-8: group header + range-gated activation). Ungrouped is
    -- documented but was never proven in-game — see the dealer prompt.
    group = 'ranch_animal', groupLabel = 'Livestock',
    onComplete = function()
      if nearId then openTend(nearId) end
    end,
  })
end

local function dropPrompt()
  if prompt then
    prompt:delete()
    prompt = nil
  end
end

CreateThread(function()
  while true do
    local id, ped = nearestAnimal(3.0)
    if id and not nearDealer() then
      if id ~= nearId then
        nearId = id
      end
      ensurePrompt(tendLabel(RanchHerd[id]))

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
      nearId = nil
      dropPrompt()
      Wait(500)
    end
  end
end)
