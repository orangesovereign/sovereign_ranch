--[[
  server/admin.lua — staff tooling + Config.Debug dev levers (design §11).

  Phase 0 ships the console/chat command set that Phase 0's ledger needs:
  inspect state, force lifecycle transitions, run the spawn probe. The
  sovereign_ui admin menu arrives with the phases whose data it manages.

  Every command is gated: chat commands by Bridge.IsAdmin, console always
  allowed (src 0). Dev levers additionally require Config.Debug.
]]

local function isStaff(src)
  return src == 0 or Bridge.IsAdmin(src)
end

local function reply(src, msg)
  if src == 0 then print('[sovereign_ranch] ' .. msg)
  else Notify.toast(src, 'Ranch Admin', msg, 'info') end
end

--- Resolve a ranch from whatever an admin typed: the property ident, OUR
--- ranch #id (as /ranchadmin list prints), or the realestate property id
--- (as /assignhouse and the realtor tooling print). Testers reach for
--- whichever number is on their screen — accept all three (ledger L2).
local function findRanch(arg)
  if not arg then return nil end
  local r = Ranches.getByIdent(arg)
  if r then return r end
  local n = tonumber(arg)
  if n then
    r = Ranches.get(n)
    if r then return r end
    for _, p in ipairs(Estate.listRanchProperties()) do
      if tonumber(p.id) == n then return Ranches.getByIdent(p.ident) end
    end
  end
  return nil
end

--- Same resolution, but for commands that may target a property with NO
--- ranch record yet (activate): fall through to the realestate ident.
local function resolveIdent(arg)
  local r = findRanch(arg)
  if r then return r.ident end
  local n = tonumber(arg)
  if n then
    for _, p in ipairs(Estate.listRanchProperties()) do
      if tonumber(p.id) == n then return p.ident end
    end
  end
  return arg
end

-- ============================================================================
-- /ranchadmin <sub> — inspection & lifecycle
-- ============================================================================

RegisterCommand('ranchadmin', function(src, args)
  if not isStaff(src) then return end
  local sub = (args[1] or 'list'):lower()

  if sub == 'list' then
    local n = 0
    for _, r in pairs(Ranches.all()) do
      n = n + 1
      local crew = Members.crewOf(r.id)
      local bal = r.biz_key and Bank.businessBalance(r.biz_key)
      reply(src, ('#%d %s — owner %s · crew %d · account %s'):format(
        r.id, r.ident,
        r.owner_charid and Bridge.GetCharName(r.owner_charid) or 'none',
        #crew, bal and ('$%.2f'):format(bal / 100) or 'n/a'))
    end
    if n == 0 then reply(src, 'no ranch records') end

  elseif sub == 'crew' and args[2] then
    local r = findRanch(args[2])
    if not r then return reply(src, 'no ranch record for ' .. tostring(args[2])) end
    local crew = Members.crewOf(r.id)
    if #crew == 0 then return reply(src, r.ident .. ': no crew') end
    for _, m in ipairs(crew) do
      reply(src, ('  %s — grade %d (%s)%s'):format(
        Bridge.GetCharName(m.charid), m.grade,
        (Config.JobGrades[m.grade] or {}).label or '?',
        m.on_duty and ' · ON DUTY' or ''))
    end

  elseif sub == 'reconcile' then
    Ranches.reconcile()
    reply(src, 'reconcile pass complete — see console')

  elseif sub == 'activate' and args[2] then
    -- Repair lever: force-activate from realestate truth (e.g. after an
    -- admin /assignhouse, which emits no propertySold).
    local ident = resolveIdent(args[2])
    local ok, res = Ranches.activate(ident, nil)
    reply(src, ok and ('activated ' .. ident) or ('failed: ' .. tostring(res)))

  elseif sub == 'teardown' and args[2] then
    local r = findRanch(args[2])
    if not r then return reply(src, 'no ranch record for ' .. tostring(args[2])) end
    local ok, res = Ranches.teardown(r.ident, 'admin')
    reply(src, ok and ('torn down ' .. r.ident) or ('failed: ' .. tostring(res)))

  elseif sub == 'hire' and args[2] and args[3] then
    -- Admin repair hire: /ranchadmin hire <ident|id> <charid> [grade 0-3]
    local r = findRanch(args[2])
    if not r then return reply(src, 'no ranch record for ' .. tostring(args[2])) end
    local ok, res = Members.hire(nil, r, tonumber(args[3]), 0)
    if ok and args[4] then
      Members.setGrade(nil, tonumber(args[3]), tonumber(args[4]))
    end
    reply(src, ok and 'hired' or ('failed: ' .. tostring(res)))

  elseif sub == 'fire' and args[2] then
    local ok, res = Members.fire(nil, tonumber(args[2]), 'admin')
    reply(src, ok and 'fired' or ('failed: ' .. tostring(res)))

  else
    reply(src, 'usage: /ranchadmin list | crew <ident|id> | reconcile | activate <ident|id> | teardown <ident|id> | hire <ident|id> <charid> [grade] | fire <charid>')
  end
end, false)

-- ============================================================================
-- Dev levers (Config.Debug only — design §11)
-- ============================================================================

local function isDev(src)
  return Config.Debug and isStaff(src)
end

--- The Phase 0 build-ruling probe (server/spawns.lua). Needs a live player
--- to stand at (server entities materialise near clients).
RegisterCommand('sr_probe_spawn', function(src)
  if not isDev(src) then return end
  if src == 0 then return print('[sovereign_ranch] run in-game — the probe spawns at your feet') end
  local ok, msg = Spawns.probe(src)
  reply(src, msg)
end, false)

RegisterCommand('sr_probe_clear', function(src)
  if not isDev(src) then return end
  local _, msg = Spawns.clearProbe()
  reply(src, msg)
end, false)

--- Cache/state introspection (perf budget §12 grows this in later phases).
--- STAFF-gated, not Debug-gated: stats are diagnostics, not a dev lever —
--- Debug-gating made it silently dead on a stock config (ledger B3).
RegisterCommand('sr_stats', function(src)
  if not isStaff(src) then return end
  local ranches, members = 0, 0
  for _, r in pairs(Ranches.all()) do
    ranches = ranches + 1
    members = members + #Members.crewOf(r.id)
  end
  reply(src, ('ranches %d · members %d · estate %s · bank %s'):format(
    ranches, members,
    Estate.available() and 'up' or 'DOWN',
    Bank.available() and 'up' or 'DOWN'))
end, false)
