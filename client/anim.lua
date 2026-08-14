--[[
  client/anim.lua — the animation seam. Every scenario this resource plays
  goes through here, because ENDING one correctly is harder than starting
  one and getting it wrong strands the player.

  The trap (live finding 2026-08-13): a scenario is not an animation you
  can just stop. Hard-clearing tasks mid-scenario leaves the PROP in the
  ped's hands and can leave the player unable to act. RDR3 ships an
  explicit outro for exactly this — the ped puts the tool down, stows the
  bucket, and returns to a normal state — and it must be asked for and
  WAITED ON before anything else touches the ped.

  Natives verified against natives_rdr3.json 2026-08-13:
    TASK_START_SCENARIO_IN_PLACE_HASH        0x524B54361229154F
    SET_PED_SHOULD_PLAY_NORMAL_SCENARIO_EXIT 0xA3A9299C4F2ADB98 (Ped)
    SET_PED_SHOULD_PLAY_IMMEDIATE_SCENARIO_EXIT 0xF1C03A5352243A30 (Ped)
    IS_PED_USING_ANY_SCENARIO                0x57AB4A3080F85143 (Ped) → BOOL
    CLEAR_PED_TASKS_IMMEDIATELY              0xAAA34F8A7CB32098 (Ped, BOOL, BOOL)
    IS_PED_MALE                              0x6D9F5FAA7488BA46 (Ped) → BOOL
]]

--- The scenario name + duration for a care verb, with the female-safety
--- rule applied (male-only scenarios silently do nothing on a female ped,
--- so those fall back to the proven one). Shared by care and troughs.
function RanchAnimFor(verb, species)
  local set = Config.CareAnims[verb]
  if not set then return nil, 5000 end
  local name = set[species] or set.default
  local male = Citizen.InvokeNative(0x6D9F5FAA7488BA46, PlayerPedId())
  if not male and name and not Config.FemaleSafeAnims[name] then
    name = Config.CareAnims.fallback
  end
  return name, set.duration or 5000
end

--- Begin a scenario on a ped.
---
--- ⚠ THE SIGNATURE IS NOT WHAT THE SUITE HAS BEEN PASSING (found
--- 2026-08-14, natives_rdr3.json):
---   TASK_START_SCENARIO_IN_PLACE_HASH(ped, scenarioHash, duration,
---       playEnterAnim BOOL, conditionalHash Hash, heading FLOAT, p6 BOOL)
--- The last three are a HASH, a FLOAT and a BOOL — not the three booleans
--- everyone (this resource, and sovereign_herbs) was passing. Handing a
--- boolean to the float heading slot left the task in a state that never
--- completed: the animation looked finished, the prop looked gone, and the
--- player stayed pinned until a weapon draw force-aborted the task. That
--- is the "stuck after feeding" bug.
---
--- Duration is -1 by default: we own the ending (RanchEndScenario), and
--- letting the engine time it out as well meant two things racing to
--- finish one task.
function RanchPlayScenario(ped, name, durationMs)
  if not name then return false end
  Citizen.InvokeNative(0x524B54361229154F,
    ped,
    GetHashKey(name),
    durationMs or -1,          -- int  duration (-1 = until we say stop)
    true,                      -- BOOL playEnterAnim
    0,                         -- Hash conditionalHash (0 = none)
    GetEntityHeading(ped) + 0.0, -- float heading — keep them facing as they are
    false)                     -- BOOL p6
  return true
end

--- Delete every object attached to the player, full stop.
---
--- Scenario props are game-owned objects parented to the ped. The polite
--- outro is supposed to stow them, but a scenario that never properly
--- STARTED has no outro to play — and the audition (2026-08-13) found
--- several that conjure a prop and leave it welded to the player for the
--- rest of the session. So we do not rely on the outro alone: after every
--- scenario we sweep the object pool and delete anything hanging off the
--- ped. GET_GAME_POOL is a shared CFX native (verified available in RedM).
--- Natives: GET_ENTITY_ATTACHED_TO 0x56D713888A566481,
--- SET_ENTITY_AS_MISSION_ENTITY 0xDC19C288082E586E (claim it before
--- deleting a game-owned object), DELETE_ENTITY 0x4CD38C78BD19A497.
function RanchClearAttachedProps()
  local ped = PlayerPedId()
  if not ped or ped == 0 then return 0 end
  local ok, pool = pcall(function() return GetGamePool('CObject') end)
  if not ok or type(pool) ~= 'table' then return 0 end

  local removed = 0
  for _, obj in ipairs(pool) do
    if DoesEntityExist(obj) and GetEntityAttachedTo(obj) == ped then
      pcall(function()
        DetachEntity(obj, true, true)
        SetEntityAsMissionEntity(obj, true, true)
        local handle = obj
        DeleteEntity(handle)
      end)
      removed = removed + 1
    end
  end
  return removed
end

--- End a scenario CLEANLY: ask for the outro, wait for the ped to actually
--- leave it (that is when the prop is put away), and only escalate if it
--- refuses. Escalating without waiting is the bug this function exists to
--- prevent, so the waits are not optional.
function RanchEndScenario(ped)
  ped = ped or PlayerPedId()
  if not ped or ped == 0 then return end

  local function inScenario()
    local ok, using = pcall(function()
      return Citizen.InvokeNative(0x57AB4A3080F85143, ped)
    end)
    return ok and using == true
  end

  if inScenario() then
    -- 1. The polite exit: plays the outro and stows the prop.
    pcall(function() Citizen.InvokeNative(0xA3A9299C4F2ADB98, ped) end)
    local waited = 0
    while waited < 1500 and inScenario() do Wait(50); waited = waited + 50 end

    -- 2. Still in it: demand an immediate exit.
    if inScenario() then
      pcall(function() Citizen.InvokeNative(0xF1C03A5352243A30, ped) end)
      local w2 = 0
      while w2 < 600 and inScenario() do Wait(50); w2 = w2 + 50 end
    end
  end

  -- 3. Then clear UNCONDITIONALLY.
  --
  -- Gating this on IS_PED_USING_ANY_SCENARIO was the second half of the
  -- stuck bug: a scenario that never properly started reports false, so
  -- the cleanup was skipped entirely and the player kept whatever broken
  -- task they were left holding. The chore is stationary, so a hard clear
  -- costs nothing visually and guarantees the player gets their body back.
  ClearPedTasks(ped, true, true)
  pcall(function() Citizen.InvokeNative(0x176CECF6F920D707, ped) end)          -- CLEAR_PED_SECONDARY_TASK
  pcall(function() Citizen.InvokeNative(0xAAA34F8A7CB32098, ped, false, false) end) -- CLEAR_PED_TASKS_IMMEDIATELY

  -- The outro is best-effort; this is the guarantee. Nothing this resource
  -- plays leaves anything in the player's hands.
  local dropped = RanchClearAttachedProps()
  if dropped > 0 then
    print(('[sovereign_ranch] cleared %d stranded prop(s)'):format(dropped))
  end
end

--- The whole shape of a timed, animated chore: play the scenario, run a
--- progress bar over it, then always exit cleanly — even when the player
--- cancels. Returns true only if the bar completed.
---
--- opts = { scenario, duration, label, cancellable, faceCoords }
function RanchScenarioAction(opts)
  local ped = PlayerPedId()
  if opts.faceCoords then
    TaskTurnPedToFaceCoord(ped, opts.faceCoords.x, opts.faceCoords.y,
      opts.faceCoords.z, 800)
    Wait(300)
  end

  -- -1, not opts.duration: the progress bar times the chore and
  -- RanchEndScenario ends the scenario. Giving the engine a duration too
  -- meant two things racing to finish one task.
  RanchPlayScenario(ped, opts.scenario, -1)

  local done = sv.progress.start({
    label = opts.label or 'Working...',
    duration = opts.duration or 5000,
    canCancel = opts.cancellable ~= false,
    disable = { 'attack', 'aim' },
  })

  -- Whatever happened — finished, cancelled, or the bar was dropped — the
  -- ped leaves its scenario properly and keeps nothing in its hands.
  RanchEndScenario(ped)
  return done
end

--- /sr_unstick — the escape hatch. If a scenario ever does strand a player
--- (holding a prop, unable to act), this drops it without a relog. Cheap,
--- harmless when nothing is wrong, and available to everyone by design:
--- the suite's rule is that the fix for being stuck must not itself
--- require permission.
RegisterCommand('sr_unstick', function()
  CreateThread(function()
    local ped = PlayerPedId()
    RanchEndScenario(ped)
    pcall(function() Citizen.InvokeNative(0xAAA34F8A7CB32098, ped, false, false) end)
    local dropped = RanchClearAttachedProps()
    print(('[sovereign_ranch] /sr_unstick: scenario cleared, %d prop(s) removed')
      :format(dropped))
  end)
end, false)

-- Belt and braces: if this resource stops while a chore is mid-animation,
-- the player would otherwise be left holding a feed sack forever.
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  local ped = PlayerPedId()
  if ped and ped ~= 0 then
    pcall(function() Citizen.InvokeNative(0xF1C03A5352243A30, ped) end)
    pcall(function() Citizen.InvokeNative(0xAAA34F8A7CB32098, ped, false, false) end)
  end
end)
