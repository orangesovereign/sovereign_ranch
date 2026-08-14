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

--- Begin a scenario on a ped. Duration is generous: we end it ourselves.
function RanchPlayScenario(ped, name, durationMs)
  if not name then return false end
  Citizen.InvokeNative(0x524B54361229154F, ped, GetHashKey(name),
    (durationMs or 5000) + 1000, true, false, false, false)
  return true
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
    while waited < 2000 and inScenario() do Wait(50); waited = waited + 50 end

    -- 2. Still in it: demand an immediate exit.
    if inScenario() then
      pcall(function() Citizen.InvokeNative(0xF1C03A5352243A30, ped) end)
      local w2 = 0
      while w2 < 800 and inScenario() do Wait(50); w2 = w2 + 50 end
    end

    -- 3. Last resort: hard clear. Ugly, but never leave a player stuck.
    if inScenario() then
      pcall(function() Citizen.InvokeNative(0xAAA34F8A7CB32098, ped, false, false) end)
    end
  end

  ClearPedTasks(ped, true, true)
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

  RanchPlayScenario(ped, opts.scenario, opts.duration)

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
    print('[sovereign_ranch] /sr_unstick: scenario cleared')
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
