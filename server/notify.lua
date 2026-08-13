--[[
  server/notify.lua — the server → client notification seam (design §9).

  Server modules never build UI payloads inline; they call Notify.* and this
  file forwards to the client, where client/main.lua hands the payload to
  sv.notify (the lib's rate-limited, dual-renderer notification module).

  House style (design §9): NATIVE cards for game-flavored moments (item
  received, animal penned), styled NUI toasts for server-voiced ones
  (errors, payroll, market receipts). tone ∈ info|success|warn|alert|error.
]]

Notify = {}

local EVENT = 'sovereign_ranch:client:notify'

local function send(src, payload)
  src = tonumber(src)
  if not src or src <= 0 then return end
  TriggerClientEvent(EVENT, src, payload)
end

--- Styled toast (server voice): errors, receipts, payroll.
function Notify.toast(src, title, message, tone)
  send(src, { kind = 'show', title = title, message = message, tone = tone or 'info' })
end

--- Native RDR2 card (game voice): hired, item granted, animal penned.
function Notify.card(src, title, message, tone)
  send(src, { kind = 'show', title = title, message = message,
              tone = tone or 'success', renderer = 'native' })
end

--- Centred top notice (announcement-weight moments on one client).
function Notify.top(src, title, detail, tone)
  send(src, { kind = 'top', title = title, detail = detail, tone = tone or 'info' })
end

--- Toast a charid if they are online; silently nothing if not.
function Notify.charToast(charid, title, message, tone)
  local src = Bridge.GetSourceFromCharId(charid)
  if src then Notify.toast(src, title, message, tone) end
end

function Notify.charCard(charid, title, message, tone)
  local src = Bridge.GetSourceFromCharId(charid)
  if src then Notify.card(src, title, message, tone) end
end
