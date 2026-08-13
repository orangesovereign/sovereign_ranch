--[[
  bridge/vorp.lua — the ONLY file that talks to VORP directly (design §1.11).
  Everything else calls Bridge.*; a VORP surface change is fixed in this one
  file. Loaded on both sides; each side defines only what it needs.

  This bridge moves NO money — that is sovereign_banking's alone (server/
  bank.lua). VORP is identity, job, admin group and the job registry here,
  nothing more.
]]

Bridge = {}

-- Lazy, cache-on-success-only core acquisition (the suite pattern): an early
-- call — before vorp_core is queryable — must not poison the cache with a
-- permanent nil.
local Core
local function core()
  if Core then return Core end
  local ok, c = pcall(function() return exports.vorp_core:GetCore() end)
  if ok and c then Core = c end
  return Core
end

-- ============================================================================
-- CLIENT side
-- ============================================================================
if not IsDuplicityVersion() then
  return   -- Phase 0 has no client-side VORP needs; sv.notify covers feedback
end

-- ============================================================================
-- SERVER side
-- ============================================================================

--- Live character table for a source, or nil. getUsedCharacter is a FIELD,
--- not a call.
local function getCharacter(src)
  local c = core()
  if not c or not src then return nil end
  local user = c.getUser(tonumber(src))
  if not user then return nil end
  return user.getUsedCharacter
end

Bridge.GetCharacter = getCharacter

--- Register the rancher job with VORP's job registry (design §5.1). Server
--- registration overrides the core's config file. Must run before anything
--- touches jobs — called from server/main.lua bootstrap.
function Bridge.RegisterJobs()
  local c = core()
  if not c or not c.RegisterJobs then
    Log.error('vorp_core RegisterJobs unavailable — rancher job NOT registered')
    return false
  end
  local ok = pcall(function()
    c.RegisterJobs({
      [Config.JobName] = {
        privateJob = false,
        grades = Config.JobGrades,
      },
    }, GetCurrentResourceName())
  end)
  if ok then
    Log.info('registered VORP job %s (%d grades)', Config.JobName, 5)
  else
    Log.error('RegisterJobs threw — rancher job NOT registered')
  end
  return ok
end

--- Character id for a connected player as a NUMBER (our charid columns are
--- INT). The bank wants strings — server/bank.lua does that conversion.
function Bridge.GetCharId(src)
  local char = getCharacter(src)
  if not char or char.charIdentifier == nil then return nil end
  return tonumber(char.charIdentifier)
end

--- Resolve a charid back to a live source, or nil if offline.
function Bridge.GetSourceFromCharId(charid)
  charid = tostring(charid)
  for _, sid in ipairs(GetPlayers()) do
    local src = tonumber(sid)
    local char = getCharacter(src)
    if char and tostring(char.charIdentifier) == charid then
      return src
    end
  end
  return nil
end

--- Job (name, grade) for a source. Grade 0 when unknown.
function Bridge.GetJob(src)
  local char = getCharacter(src)
  if not char then return nil, 0 end
  return char.job, tonumber(char.jobGrade or char.jobgrade) or 0
end

--- Assign a VORP job + grade to a LIVE source (hire / promote / fire path
--- for online members). Setter names vary between VORP versions, so try the
--- character-object methods first (the lawandorder-proven pattern).
function Bridge.SetJob(src, job, grade)
  local char = getCharacter(src)
  if not char then return false end
  grade = tonumber(grade) or 0
  local ok = pcall(function()
    if char.setJob then char.setJob(job) else char.updateCharJob(job) end
    if char.setJobGrade then char.setJobGrade(grade) else char.updateCharJobGrade(grade) end
  end)
  if not ok then
    Log.error('SetJob failed for src %s (%s/%s)', tostring(src), tostring(job), tostring(grade))
  end
  return ok
end

--- Set the job of an OFFLINE character by direct characters-table write —
--- safe precisely because the character is not loaded, so no in-memory copy
--- will save over it. Callers must check offline first (Members.syncGrade
--- does). joblabel kept in step so the next login reads consistently.
function Bridge.SetJobOffline(charid, job, grade, label)
  local n = Db.execute([[
    UPDATE characters SET job = ?, jobgrade = ?, joblabel = ?
    WHERE charidentifier = ?
  ]], { job, tonumber(grade) or 0, label or job, tostring(charid) })
  return (n or 0) > 0
end

--- The VORP USER identifier (account key) behind a character — the
--- 1-ranch-per-account key. DB read so it works for offline characters.
function Bridge.GetUserId(charid)
  local row = Db.single(
    'SELECT identifier FROM characters WHERE charidentifier = ? LIMIT 1',
    { tostring(charid) })
  return row and row.identifier or nil
end

--- Display name for a charid (Discord logs, crew panel), or the charid
--- itself when unknown. VORP characters-table coupling lives here.
function Bridge.GetCharName(charid)
  local row = Db.single(
    'SELECT firstname, lastname FROM characters WHERE charidentifier = ? LIMIT 1',
    { tostring(charid) })
  if not row then return tostring(charid) end
  -- Parenthesised so gsub's second return (the count) is dropped.
  return (('%s %s'):format(row.firstname or '', row.lastname or '')
    :gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Does this charid exist at all (online or not)? Guards hire/admin flows
--- against typos that would strand a membership row on a ghost.
function Bridge.CharacterExists(charid)
  local row = Db.single(
    'SELECT charidentifier FROM characters WHERE charidentifier = ? LIMIT 1',
    { tostring(charid) })
  return row ~= nil
end

--- Is this source staff? Checks BOTH group sources — users.group (identifier
--- level, user.getGroup) and characters.group — against Config.AdminGroups,
--- matching sovereign_admin's model.
function Bridge.IsAdmin(src)
  local c = core()
  if not c then return false end
  local user = c.getUser(tonumber(src))
  if not user then return false end
  local userGroup = user.getGroup
  if userGroup and Config.AdminGroups[userGroup] then return true end
  local char = user.getUsedCharacter
  local charGroup = char and char.group
  return charGroup ~= nil and Config.AdminGroups[charGroup] == true
end

-- ============================================================================
-- vorp_inventory (Phase 1: medicine + optional feed item). Guarded — a
-- differing inventory version degrades to a clean refusal, never a throw.
-- ============================================================================

--- Remove `amount` of an item from a player. Count-check first, then take;
--- returns true only when the inventory confirmed the removal. (subItem's
--- return shape varies between inventory versions — anything but an
--- explicit false after a positive count check is treated as taken.)
function Bridge.SubItem(src, itemName, amount)
  amount = amount or 1
  if Bridge.GetItemCount(src, itemName) < amount then return false end
  local ok, res = pcall(function()
    return exports.vorp_inventory:subItem(src, itemName, amount, {})
  end)
  if not ok then
    Log.warn('SubItem(%s) threw — check vorp_inventory', tostring(itemName))
    return false
  end
  return res ~= false
end

--- Count of an item a player carries (0 when unknown).
function Bridge.GetItemCount(src, itemName)
  local ok, res = pcall(function()
    return exports.vorp_inventory:getItemCount(src, nil, itemName)
  end)
  if not ok then return 0 end
  return tonumber(res) or 0
end

--- Grant items (production collection in Phase 2; admin repair now).
function Bridge.AddItem(src, itemName, amount)
  local ok = pcall(function()
    exports.vorp_inventory:addItem(src, itemName, amount or 1, {})
  end)
  if not ok then Log.warn('AddItem(%s) threw — check vorp_inventory', tostring(itemName)) end
  return ok
end

--- fn(src) fires once a player has picked a character (job/wallet are live).
function Bridge.OnCharacterSelected(fn)
  AddEventHandler('vorp:SelectedCharacter', function(source, ...)
    fn(tonumber(source))
  end)
end

--- fn(src, newJob, newGrade) fires when vorp_core changes a character's job
--- (any resource). Members uses it to notice outside interference with the
--- rancher job and re-assert the membership table.
function Bridge.OnJobChange(fn)
  AddEventHandler('vorp:playerJobChange', function(source, job, grade)
    fn(tonumber(source), job, tonumber(grade) or 0)
  end)
end
