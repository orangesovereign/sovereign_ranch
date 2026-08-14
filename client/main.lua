--[[
  client/main.lua — Phase 0 client boot. Gameplay arrives in Phase 1; this
  file is the notification receiver and nothing else.

  Everything UI-shaped goes through the `sv` kernel (design §1.9) — no raw
  UiPrompt code, no SetNuiFocus, no bespoke draw loops in this resource.
]]

-- Server → client notification seam (server/notify.lua). sv.notify maps
-- tones and rate-limits centrally; renderer 'native' selects the game's
-- own card (house style: native for game voice, NUI for server voice).
RegisterNetEvent('sovereign_ranch:client:notify', function(payload)
  if type(payload) ~= 'table' then return end
  if payload.kind == 'top' then
    sv.notify.top({ title = payload.title, detail = payload.detail, tone = payload.tone })
  else
    sv.notify.show({ title = payload.title, message = payload.message,
                     tone = payload.tone, renderer = payload.renderer })
  end
end)

-- ============================================================================
-- Dev animation preview (/sr_anim — Debug-gated server-side). Plays a
-- scenario TYPE via the herbs-proven native; 'stop' clears. Candidates are
-- judged here before any care verb ships one (docs/animations-reference.md).
-- ============================================================================

RegisterNetEvent('sovereign_ranch:client:devAnim', function(name, durationMs)
  CreateThread(function()
    if name == 'stop' then
      RanchEndScenario(PlayerPedId())   -- proper outro: puts the prop away
      return
    end
    local ms = tonumber(durationMs) or 6000
    RanchPlayScenario(PlayerPedId(), name, ms)
    print(('[sovereign_ranch] /sr_anim playing %s for %dms — nothing visible = the type did not resolve')
      :format(name, ms))
    -- Auditions clean up after themselves, so a prop scenario cannot leave
    -- the tester holding a shovel for the rest of the session.
    Wait(ms)
    RanchEndScenario(PlayerPedId())
  end)
end)

-- ============================================================================
-- Probe assist (server/spawns.lua). A freshly created RDR3 ped is UNDRESSED
-- and can render INVISIBLE until a variation is applied — every ped this
-- resource ever spawns must be dressed (Wilbur ruling 2026-08-13; the
-- banking-teller → realestate-receptionist lineage proved the pattern).
-- Outfit natives are client-side, so the server asks this client to dress
-- the probe ped by netId. Two-native dress, 100ms settle beat, dress again.
-- Natives verified against natives_rdr3.json 2026-08-13:
--   _SET_RANDOM_OUTFIT_VARIATION       0x283978A15512B2FE (Ped, BOOL)
--   _UPDATE_PED_VARIATION              0xCC8CA3E88256E58F (Ped, 5×BOOL)
--   NETWORK_GET_ENTITY_FROM_NETWORK_ID 0xCE4E5D9B0A4FF560 (netId) → Entity
-- ============================================================================

-- (The dress function itself is RanchDress in client/animals.lua — one
-- implementation of the standing rule for every ped this resource touches.)

RegisterNetEvent('sovereign_ranch:client:probeDress', function(netId)
  netId = tonumber(netId)
  if not netId or netId == 0 then return end
  CreateThread(function()
    -- Server-created entities stream in asynchronously; poll briefly.
    local entity, waited = 0, 0
    while waited < 5000 do
      if NetworkDoesEntityExistWithNetworkId(netId) then
        entity = NetworkGetEntityFromNetworkId(netId)
        if entity ~= 0 and DoesEntityExist(entity) then break end
      end
      entity = 0
      Wait(250); waited = waited + 250
    end
    if entity == 0 then
      print(('[sovereign_ranch] probe dress: netId %d never streamed in on this client'):format(netId))
      return
    end
    RanchDress(entity)
    print(('[sovereign_ranch] probe dress: netId %d dressed (entity %d)'):format(netId, entity))
  end)
end)
