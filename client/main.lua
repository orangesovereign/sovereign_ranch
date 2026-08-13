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
