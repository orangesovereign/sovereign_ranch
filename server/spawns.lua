--[[
  server/spawns.lua — the spawn ledger (design §6.3). Phase 0 ships ONLY the
  server-spawn probe that decides the build ruling (§14.1): can the server
  itself create networked animal peds under OneSync on RedM, or does the
  steward-client model own spawning?

  Server-side CREATE_PED is real and game-agnostic — verified against
  natives_cfx.json 13 Aug 2026: CREATE_PED apiset=server, no game field,
  signature (pedType, modelHash, x, y, z, heading, isNetwork,
  bScriptHostPed). What the table cannot answer is BEHAVIOUR on RedM:
  does the ped stream in for nearby clients, persist, migrate owners, and
  accept tasks? That is what the live probe observes.

  The probe is Config.Debug-gated, admin-only, and self-cleaning.
]]

Spawns = {}

local probe = nil   -- { entity, netId, model, startedAt } while one is live

--- /sr_probe_spawn — create one server-side cow ped at the caller's feet
--- and report what the server can see about it. The CALLER walks around it,
--- watches for streaming/animation, and has a second player approach —
--- their observations complete the ledger row. /sr_probe_clear removes it.
function Spawns.probe(src)
  if probe and DoesEntityExist(probe.entity) then
    Log.warn('probe: previous probe ped still exists (net %s) — clear it first',
      tostring(probe.netId))
    return false, 'probe already live — /sr_probe_clear first'
  end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false, 'no player ped' end
  local c = GetEntityCoords(ped)
  local model = GetHashKey('a_c_cow')   -- draft model; behaviour is what's probed

  -- pedType is a GTA-shaped slot ignored by RDR3 spawning paths; 4 (civmale)
  -- is the conventional filler. isNetwork + bScriptHostPed true: we want a
  -- fully networked, script-owned entity.
  local entity = CreatePed(4, model, c.x + 2.0, c.y, c.z, 0.0, true, true)

  -- Server-created entities materialise asynchronously (a client must
  -- accept ownership). Poll briefly rather than trusting the return alone.
  CreateThread(function()
    local waited = 0
    while waited < 5000 and not DoesEntityExist(entity) do
      Wait(250); waited = waited + 250
    end
    if not DoesEntityExist(entity) then
      Log.error('PROBE RESULT: CreatePed returned %s but no entity exists after 5s — server spawning NOT viable as-is', tostring(entity))
      probe = nil
      return
    end
    local netId = 0
    pcall(function() netId = NetworkGetNetworkIdFromEntity(entity) end)
    probe = { entity = entity, netId = netId, model = 'a_c_cow', startedAt = os.time() }
    local pc = GetEntityCoords(entity)
    Log.info('PROBE RESULT: server ped EXISTS — entity %s, netId %s, at %.2f %.2f %.2f. Now observe in-game: does it render, animate, survive the spawner leaving, and stream to a second client?',
      tostring(entity), tostring(netId), pc.x, pc.y, pc.z)
  end)
  return true, 'probe ped requested — watch the server console, then the world'
end

--- Remove the probe ped.
function Spawns.clearProbe()
  if probe and DoesEntityExist(probe.entity) then
    DeleteEntity(probe.entity)
  end
  probe = nil
  return true, 'probe cleared'
end

-- Never strand a probe ped across a restart.
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  if probe and DoesEntityExist(probe.entity) then DeleteEntity(probe.entity) end
end)
