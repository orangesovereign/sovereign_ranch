--[[
  server/members.lua — the crew (design §5). One membership table scopes
  which ranch a character works at and at what grade; the VORP job is a
  MIRROR of this table, never the truth. Hire/fire/promote move three things
  together: the membership row, the VORP job grade, and the realestate
  access mirror (GrantAccess/RevokeAccess).

  Grade meanings live in Enums.Capability; checks are always server-side via
  Members.can. The boss is an ordinary row at grade 4 seated by
  Ranches.activate — never by hire.
]]

Members = {}

local Err = Enums.Err
local Grade = Enums.Grade

local byChar  = {}   -- charid -> member row (uq_member: one ranch per character)
local byRanch = {}   -- ranch_id -> { member row, ... }

-- ============================================================================
-- Cache
-- ============================================================================

local function index(m)
  byChar[m.charid] = m
  local list = byRanch[m.ranch_id]
  if not list then list = {}; byRanch[m.ranch_id] = list end
  list[#list + 1] = m
end

local function unindex(m)
  byChar[m.charid] = nil
  local list = byRanch[m.ranch_id]
  if not list then return end
  for i, e in ipairs(list) do
    if e.id == m.id then table.remove(list, i) break end
  end
end

function Members.load()
  byChar, byRanch = {}, {}
  local rows = Db.loadMembers() or {}
  for _, m in ipairs(rows) do
    m.id = tonumber(m.id); m.ranch_id = tonumber(m.ranch_id)
    m.charid = tonumber(m.charid); m.grade = tonumber(m.grade) or 0
    m.on_duty = tonumber(m.on_duty) == 1
    index(m)
  end
  Log.info('loaded %d crew member(s)', #rows)
end

--- Membership row for a charid (any ranch), or nil.
function Members.get(charid) return byChar[tonumber(charid)] end

--- Crew of one ranch (array, possibly empty). Includes the grade-4 boss.
function Members.crewOf(ranchId) return byRanch[tonumber(ranchId)] or {} end

--- Count of EMPLOYEES (grades 0-3; the boss seat doesn't consume a slot —
--- Config.MaxEmployees is the bunkhouse, not the deed).
function Members.employeeCount(ranchId)
  local n = 0
  for _, m in ipairs(Members.crewOf(ranchId)) do
    if m.grade < Grade.RANCHER then n = n + 1 end
  end
  return n
end

--- Capability check (design §5.2): resolves ranch + grade from the
--- MEMBERSHIP table. Returns (true, member) or (false, err).
function Members.can(charid, capability, ranchId)
  local m = Members.get(charid)
  if not m then return false, Err.NOT_MEMBER end
  if ranchId and m.ranch_id ~= tonumber(ranchId) then return false, Err.NOT_MEMBER end
  local floor = Enums.Capability[capability]
  if not floor then return false, Err.BAD_ARG end
  if m.grade < floor then return false, Err.NO_CAPABILITY end
  return true, m
end

-- ============================================================================
-- The VORP job mirror. Online → live setter; offline → direct characters
-- write (safe: an unloaded character has no in-memory copy to save over it).
-- ============================================================================

local function gradeLabel(grade)
  local g = Config.JobGrades[grade]
  return g and g.label or Config.JobName
end

--- Point a character's VORP job at (rancher, grade) — or at unemployed when
--- grade is nil. Never fails the caller; drift self-heals on login and at
--- the daily reconcile.
function Members.syncGrade(charid, grade)
  local job   = grade and Config.JobName or 'unemployed'
  local glvl  = grade or 0
  local label = grade and gradeLabel(grade) or 'Unemployed'
  local src = Bridge.GetSourceFromCharId(charid)
  if src then
    if not Bridge.SetJob(src, job, glvl) then
      Log.warn('syncGrade: live SetJob failed for %s — will heal on reconcile', tostring(charid))
    end
  else
    Bridge.SetJobOffline(charid, job, glvl, label)
  end
end

--- Fix every member's VORP job toward the membership table (boot + daily).
--- Only touches characters whose stored job disagrees; a member holding a
--- DIFFERENT job entirely is corrected too — membership is the truth.
function Members.reconcileGrades()
  local fixed = 0
  for charid, m in pairs(byChar) do
    local row = Db.single(
      'SELECT job, jobgrade FROM characters WHERE charidentifier = ? LIMIT 1',
      { tostring(charid) })
    if row and (row.job ~= Config.JobName or tonumber(row.jobgrade) ~= m.grade) then
      Members.syncGrade(charid, m.grade)
      fixed = fixed + 1
    end
  end
  if fixed > 0 then Log.info('reconcile: corrected %d member job(s)', fixed) end
end

-- A character logging in gets their job re-asserted from the table — the
-- cheap end of reconcile, catching anything that drifted while offline.
Bridge.OnCharacterSelected(function(src)
  local charid = Bridge.GetCharId(src)
  if not charid then return end
  local m = Members.get(charid)
  if m then
    local job, grade = Bridge.GetJob(src)
    if job ~= Config.JobName or grade ~= m.grade then
      Members.syncGrade(charid, m.grade)
    end
  elseif (Bridge.GetJob(src)) == Config.JobName then
    -- Carries the rancher job but isn't on any crew — strip it.
    Members.syncGrade(charid, nil)
  end
end)

-- ============================================================================
-- Seats & releases (called by Ranches lifecycle)
-- ============================================================================

--- Seat the OWNER at grade 4 (Ranches.activate). Idempotent. A buyer who
--- was crewed as a HAND elsewhere leaves that job first — employment yields
--- to ownership (the dual-use rule governs owning, not working).
function Members.seatOwner(ranch, charid)
  charid = tonumber(charid)
  if not charid then return false, Err.BAD_ARG end

  local existing = Members.get(charid)
  if existing then
    if existing.ranch_id == ranch.id then
      -- Repeat activation (reconcile): just assert grade 4.
      if existing.grade ~= Grade.RANCHER then
        existing.grade = Grade.RANCHER
        Db.updateMember(existing)
      end
      Members.syncGrade(charid, Grade.RANCHER)
      return true, existing
    end
    -- Owner is crewed at ANOTHER ranch: leave that job first (realestate
    -- allowed the purchase, so employment is the thing that yields).
    Members.fire(nil, charid, 'bought_own_ranch')
  end

  local id = Db.insertMember({ ranch_id = ranch.id, charid = charid, grade = Grade.RANCHER })
  if not id then return false, Err.INTERNAL end
  local m = { id = tonumber(id), ranch_id = ranch.id, charid = charid,
              grade = Grade.RANCHER, on_duty = false,
              accrued_minutes = 0, unpaid_cents = 0 }
  index(m)

  Members.syncGrade(charid, Grade.RANCHER)
  -- No GrantAccess for the boss: realestate's owner passes every access
  -- check already; a redundant grant row would just outlive a resale.
  return true, m
end

--- Release the entire crew (Ranches.teardown). Accrued-but-unpaid wage
--- minutes are zeroed with a log line (design §4) — the account that owed
--- them no longer answers to anyone.
function Members.releaseAll(ranch, reason)
  local crew = Members.crewOf(ranch.id)
  for i = #crew, 1, -1 do
    local m = crew[i]
    if (m.accrued_minutes or 0) > 0 or (m.unpaid_cents or 0) > 0 then
      Log.info('teardown %s: member %d forfeits %d accrued min + %d unpaid cents',
        ranch.ident, m.charid, m.accrued_minutes or 0, m.unpaid_cents or 0)
    end
    Db.deleteMember(m.id)
    unindex(m)
    Members.syncGrade(m.charid, nil)
    Estate.revokeAccess(ranch.ident, m.charid)
    Notify.charToast(m.charid, T('ranch_torndown_title'), T('ranch_torndown', ranch.ident), 'warn')
  end
end

-- ============================================================================
-- Hire / fire / promote (design §5.2). `actor` is a charid, or nil for
-- system/admin paths (nil skips the capability gate; admin.lua guards).
-- ============================================================================

--- Hire `charid` onto `ranch` at grade 0. Actor needs 'hire' (Manager+).
--- Returns (ok, memberOrErr).
function Members.hire(actor, ranch, charid, hiredBy)
  charid = tonumber(charid)
  if not charid or not ranch then return false, Err.BAD_ARG end
  if actor then
    local ok, err = Members.can(actor, 'hire', ranch.id)
    if not ok then return false, err end
  end
  if not Bridge.CharacterExists(charid) then return false, Err.UNKNOWN_CHAR end
  if Members.get(charid) then return false, Err.ALREADY_MEMBER end
  if Members.employeeCount(ranch.id) >= Config.MaxEmployees then
    return false, Err.CREW_FULL
  end

  local id = Db.insertMember({ ranch_id = ranch.id, charid = charid,
                               grade = Grade.HAND, hired_by = tonumber(hiredBy) or tonumber(actor) or 0 })
  if not id then return false, Err.INTERNAL end
  local m = { id = tonumber(id), ranch_id = ranch.id, charid = charid,
              grade = Grade.HAND, on_duty = false,
              accrued_minutes = 0, unpaid_cents = 0 }
  index(m)

  Members.syncGrade(charid, Grade.HAND)
  Estate.grantAccess(ranch.ident, charid, { storage = true })

  Events.handHired({ ident = ranch.ident, charid = charid, grade = Grade.HAND,
                     by = tonumber(actor) or 0 })
  Log.discord('crew', 'Hand hired', ('**%s** — %s (by %s)'):format(
    ranch.ident, Bridge.GetCharName(charid), actor and Bridge.GetCharName(actor) or 'system'))
  Log.ranchDiscord(ranch, 'crew', 'Hand hired', Bridge.GetCharName(charid))
  Notify.charCard(charid, T('hired_title'), T('hired', ranch.ident, gradeLabel(Grade.HAND)))
  return true, m
end

--- Fire a member. Actor needs 'hire' and may only fire BELOW their own
--- grade and below Manager unless they are the Rancher (design §5.2: the
--- boss alone touches Managers). The boss seat itself cannot be fired.
--- Returns (ok, err).
function Members.fire(actor, charid, reason)
  charid = tonumber(charid)
  local m = Members.get(charid)
  if not m then return false, Err.NOT_MEMBER end
  local ranch = Ranches.get(m.ranch_id)
  if not ranch then return false, Err.NO_RANCH end
  if m.grade == Grade.RANCHER then return false, Err.GRADE_CEILING end

  if actor then
    local ok, actorRow = Members.can(actor, 'hire', m.ranch_id)
    if not ok then return false, actorRow end
    -- Managers touch grades below Manager; the Rancher touches everyone.
    if actorRow.grade < Grade.RANCHER and m.grade >= Grade.MANAGER then
      return false, Err.GRADE_CEILING
    end
  end

  if (m.accrued_minutes or 0) > 0 or (m.unpaid_cents or 0) > 0 then
    Log.info('fire %s from %s: forfeits %d accrued min + %d unpaid cents',
      tostring(charid), ranch.ident, m.accrued_minutes or 0, m.unpaid_cents or 0)
  end
  Db.deleteMember(m.id)
  unindex(m)
  Members.syncGrade(charid, nil)
  Estate.revokeAccess(ranch.ident, charid)

  Events.handFired({ ident = ranch.ident, charid = charid, by = tonumber(actor) or 0 })
  Log.discord('crew', 'Hand fired', ('**%s** — %s (%s)'):format(
    ranch.ident, Bridge.GetCharName(charid), tostring(reason or 'fired')))
  Log.ranchDiscord(ranch, 'crew', 'Hand fired', Bridge.GetCharName(charid))
  Notify.charToast(charid, T('fired_title'), T('fired', ranch.ident), 'warn')
  return true, nil
end

--- Promote/demote to `grade` (0-3; the grade-4 seat moves only with the
--- deed). Managers promote up to Foreman; only the Rancher touches the
--- Manager grade in either direction (design §5.2). Returns (ok, err).
function Members.setGrade(actor, charid, grade)
  charid, grade = tonumber(charid), tonumber(grade)
  if not grade or grade < Grade.HAND or grade > Grade.MANAGER then
    return false, Err.BAD_ARG
  end
  local m = Members.get(charid)
  if not m then return false, Err.NOT_MEMBER end
  if m.grade == Grade.RANCHER then return false, Err.GRADE_CEILING end

  if actor then
    local ok, actorRow = Members.can(actor, 'hire', m.ranch_id)
    if not ok then return false, actorRow end
    local ceiling = actorRow.grade >= Grade.RANCHER and Grade.MANAGER or Grade.FOREMAN
    if grade > ceiling or m.grade > ceiling then
      return false, Err.GRADE_CEILING
    end
  end
  if m.grade == grade then return true, m end

  m.grade = grade
  Db.updateMember(m)
  Members.syncGrade(charid, grade)

  local ranch = Ranches.get(m.ranch_id)
  Events.handPromoted({ ident = ranch and ranch.ident, charid = charid,
                        grade = grade, by = tonumber(actor) or 0 })
  Log.discord('crew', 'Standing changed', ('**%s** — %s → %s'):format(
    ranch and ranch.ident or '?', Bridge.GetCharName(charid), gradeLabel(grade)))
  Notify.charCard(charid, T('promoted_title'),
    T('promoted', gradeLabel(grade), ranch and ranch.ident or ''))
  return true, m
end
