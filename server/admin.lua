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

  elseif sub == 'points' and args[2] then
    -- Which anchors does config/ranches.lua map, and how far apart are
    -- they? A pasture on the far side of the property is a legitimate
    -- survey but makes released stock look missing — show the numbers.
    local r = findRanch(args[2])
    local ident = r and r.ident or tostring(args[2]):lower()
    local points = Ranches.pointsOf(ident)
    local names = {}
    for name in pairs(points) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then
      return reply(src, ident .. ': no mapped points — release falls back beside the releaser')
    end
    local me = src ~= 0 and GetPlayerPed(src) or nil
    local c = me and me ~= 0 and GetEntityCoords(me) or nil
    for _, name in ipairs(names) do
      local p = points[name]
      local line = ('  %-11s %.1f %.1f %.1f'):format(name, p.x, p.y, p.z)
      if p.radius then line = line .. (' · zone %.0fm'):format(p.radius) end
      if c then
        local dx, dy = p.x - c.x, p.y - c.y
        line = line .. (' · %.0fm from you'):format(math.sqrt(dx * dx + dy * dy))
      end
      reply(src, line)
    end

  elseif sub == 'bizinit' and args[2] then
    -- Repair lever: open the bank business account for an ADMIN-ASSIGNED
    -- ranch (a real sale registers it in realestate's paid flow; assigns
    -- don't, leaving buys/payroll with no account to draw on).
    local r = findRanch(args[2])
    if not r then return reply(src, 'no ranch record for ' .. tostring(args[2])) end
    if not r.owner_charid then return reply(src, r.ident .. ' has no owner') end
    local ok, res = Bank.registerBusiness(r.biz_key or r.ident, r.owner_charid, 0, r.ident)
    reply(src, ok and ('business account open for ' .. r.ident)
      or ('failed: ' .. tostring(res)))

  else
    reply(src, 'usage: /ranchadmin list | crew <ident|id> | reconcile | activate <ident|id> | teardown <ident|id> | hire <ident|id> <charid> [grade] | fire <charid> | bizinit <ident|id> | points <ident|id>')
  end
end, false)

-- ============================================================================
-- Dev levers (Config.Debug only — design §11)
-- ============================================================================

local function isDev(src)
  if not isStaff(src) then return false end
  if not Config.Debug then
    -- The B3 lesson, applied to the levers: a staff member gets an honest
    -- refusal, never silence (silence reads as a broken command).
    reply(src, 'dev levers are off — set Config.Debug = true in config/config.lua and restart')
    return false
  end
  return true
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

--- Fund a ranch business account for testing (Debug only): the account
--- must exist first (real purchase or /ranchadmin bizinit).
--- /sr_fund <ident|id> <dollars>
RegisterCommand('sr_fund', function(src, args)
  if not isDev(src) then return end
  local r = args[1] and Ranches.getByIdent(args[1]) or nil
  if not r then
    local n = tonumber(args[1])
    if n then r = Ranches.get(n) end
  end
  if not r then return reply(src, 'no ranch record for ' .. tostring(args[1])) end
  local cents = math.floor((tonumber(args[2]) or 0) * 100)
  if cents <= 0 then return reply(src, 'usage: /sr_fund <ident|id> <dollars>') end
  local idem = ('ranch:devfund:%d:%d'):format(r.id, os.time())
  local ok, res = Bank.credit(r.biz_key or r.ident, cents, 'ranch_admin_fund', idem, r.ident)
  reply(src, ok and ('funded %s with $%.2f'):format(r.ident, cents / 100)
    or ('failed: ' .. tostring(res) .. ' (account missing? /ranchadmin bizinit first)'))
end, false)

--- Animation candidate preview (docs/animations-reference.md): plays a
--- scenario TYPE on your ped so candidates can be judged in-game before
--- any care verb leans on one. /sr_anim <SCENARIO_NAME> [ms] · /sr_anim stop
RegisterCommand('sr_anim', function(src, args)
  if not isDev(src) then return end
  if src == 0 then return print('[sovereign_ranch] run in-game') end
  local name = tostring(args[1] or '')
  if name == '' then
    return reply(src, 'usage: /sr_anim <SCENARIO_TYPE> [durationMs] | /sr_anim stop')
  end
  TriggerClientEvent('sovereign_ranch:client:devAnim', src, name,
    tonumber(args[2]) or 6000)
end, false)

--- Where is every spawned animal, relative to me? The answer to "my stock
--- has vanished" — which is usually "it is at the pasture anchor, which is
--- further away than you think".
RegisterCommand('sr_where', function(src)
  if not isDev(src) then return end
  local charid = src ~= 0 and Bridge.GetCharId(src) or nil
  local m = charid and Members.get(charid)
  if not m then return reply(src, 'you are not on a ranch crew') end
  local ped = GetPlayerPed(src)
  local c = ped and ped ~= 0 and GetEntityCoords(ped) or nil

  local n = 0
  for _, a in ipairs(Animals.herdOf(m.ranch_id)) do
    local pos = Spawns.positionOf(a)
    local live = Spawns.entityOf(a.id) ~= nil
    local where = 'penned'
    if pos and c then
      local dx, dy = pos.x - c.x, pos.y - c.y
      where = ('%.0fm away at %.1f %.1f %.1f'):format(
        math.sqrt(dx * dx + dy * dy), pos.x, pos.y, pos.z)
    end
    reply(src, ('  #%d %s (%s) — %s%s'):format(
      a.id, a.name or a.species, a.state, where, live and ' · PED LIVE' or ''))
    n = n + 1
  end
  if n == 0 then reply(src, 'no animals on the books') end
end, false)

--- Survey helper: prints where you stand, ready to paste into a config
--- coords table (the dealer spot, future pen points).
RegisterCommand('sr_here', function(src)
  if not isDev(src) then return end
  if src == 0 then return print('[sovereign_ranch] run in-game') end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return end
  local c = GetEntityCoords(ped)
  local h = GetEntityHeading(ped)
  reply(src, ('{ x = %.2f, y = %.2f, z = %.2f, h = %.2f }'):format(c.x, c.y, c.z, h))
  print(('[sovereign_ranch] /sr_here: { x = %.2f, y = %.2f, z = %.2f, h = %.2f }')
    :format(c.x, c.y, c.z, h))
end, false)

--- Resolve the animal a dev lever should act on. Pass an id, or pass
--- `near` (or nothing at all) to mean "the one I am standing beside" —
--- hunting for an id to run a test is friction nobody needs. Returns
--- (animal, remainingArgs) so callers read their values uniformly.
local function targetAnimal(src, args)
  local first = tostring(args[1] or ''):lower()
  if first ~= '' and first ~= 'near' and first ~= 'n' then
    local a = Animals.get(tonumber(first))
    if a then
      return a, { args[2], args[3], args[4] }
    end
  end
  -- No id, or an unrecognised one: use the nearest animal and shift the
  -- arguments along only if the first was a keyword.
  local shift = (first == 'near' or first == 'n')
  local rest = shift and { args[2], args[3], args[4] } or { args[1], args[2], args[3] }
  return Animals.nearestTo(src, 12.0), rest
end

--- Force an animal's needs (ledger: neglect → sick → treat without waiting
--- an hour). /sr_needs [id|near] <hunger> <thirst> [groom]
--- Standing next to the cow, `/sr_needs 5 5` is enough.
RegisterCommand('sr_needs', function(src, args)
  if not isDev(src) then return end
  local a, v = targetAnimal(src, args)
  if not a then return reply(src, 'no animal here — stand next to one, or give an id (/sr_where lists them)') end
  a.hunger = math.max(0, math.min(100, tonumber(v[1]) or a.hunger))
  a.thirst = math.max(0, math.min(100, tonumber(v[2]) or a.thirst))
  if v[3] then a.groom = math.max(0, math.min(100, tonumber(v[3]) or a.groom)) end
  Animals.touch(a)
  Spawns.pushAnimal(a)
  reply(src, ('#%d %s — hunger %d, thirst %d, groom %d'):format(
    a.id, a.name or a.species, a.hunger, a.thirst, a.groom))
end, false)

--- Force the sickness state.
--- /sr_sick [id|near] <healthy|sick|critical>
RegisterCommand('sr_sick', function(src, args)
  if not isDev(src) then return end
  local a, v = targetAnimal(src, args)
  if not a then return reply(src, 'no animal here — stand next to one, or give an id (/sr_where lists them)') end
  local state = tostring(v[1] or '')
  if state ~= 'healthy' and state ~= 'sick' and state ~= 'critical' then
    return reply(src, 'state must be healthy | sick | critical')
  end
  a.sick_state = state
  if state == 'healthy' then Needs.clearSickTimer(a.id) end
  Animals.touch(a)
  Spawns.pushAnimal(a)
  reply(src, ('animal #%d is now %s'):format(a.id, state))
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
