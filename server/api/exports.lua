--[[
  server/api/exports.lua — the integration surface other Sovereign scripts
  call (design §10).

  CONTRACT (the suite's, followed exactly): every MUTATING export returns
  `(ok: boolean, resultOrErrorCode)` and never throws. Read-only queries
  return the plain value (or nil), because a caller asking "whose ranch is
  this?" wants an answer, not a tuple. Error codes are Enums.Err strings.
]]

API = {}

local Err = Enums.Err

--- Public view of a ranch row: everything a consumer may know, nothing
--- internal (no webhook URL, no settings bag).
local function view(r)
  if not r then return nil end
  return {
    id = r.id, ident = r.ident,
    owner = r.owner_charid,
    strayMult = tonumber(r.stray_mult) or 1.0,
  }
end

-- ============================================================================
-- Reads
-- ============================================================================

--- Public view of the ranch at `ident`, or nil.
function API.GetRanch(ident)
  return view(Ranches.getByIdent(ident))
end

--- The ranch a charid OWNS (holds the deed of), or nil.
function API.GetRanchByOwner(charid)
  return view(Ranches.getByOwner(charid))
end

--- Is this character on a ranch crew? ident nil = any ranch.
function API.IsRanchMember(charid, ident)
  local m = Members.get(charid)
  if not m then return false end
  if ident == nil then return true end
  local r = Ranches.getByIdent(ident)
  return r ~= nil and m.ranch_id == r.id
end

--- { ident, grade } for a crewed character, or nil.
function API.GetMemberGrade(charid)
  local m = Members.get(charid)
  if not m then return nil end
  local r = Ranches.get(m.ranch_id)
  return { ident = r and r.ident or nil, grade = m.grade }
end

--- Herd size at a ranch (species nil = all, dead excluded).
function API.GetHerdCount(ident, species)
  local r = Ranches.getByIdent(ident)
  if not r then return 0 end
  local row
  if species then
    row = Db.single([[
      SELECT COUNT(*) AS n FROM sovereign_ranch_animals
      WHERE ranch_id = ? AND species = ? AND state <> 'dead'
    ]], { r.id, tostring(species) })
  else
    row = Db.single([[
      SELECT COUNT(*) AS n FROM sovereign_ranch_animals
      WHERE ranch_id = ? AND state <> 'dead'
    ]], { r.id })
  end
  return row and tonumber(row.n) or 0
end

--- Is this character clocked in? (Duty arrives Phase 5; the column exists
--- from day one so the answer is honest — false — until then.)
function API.IsOnDuty(charid)
  local m = Members.get(charid)
  return m ~= nil and m.on_duty == true
end

-- ============================================================================
-- Mutators (admin / event tooling; gameplay callers arrive with their phases)
-- ============================================================================

--- Events/weather scripts can spook or calm a herd. mult clamps to [0.1, 10].
function API.SetStrayMultiplier(ident, mult)
  local r = Ranches.getByIdent(ident)
  if not r then return false, Err.NO_RANCH end
  mult = tonumber(mult)
  if not mult then return false, Err.BAD_ARG end
  r.stray_mult = math.min(10.0, math.max(0.1, mult))
  Ranches.save(r)
  return true, { ident = r.ident, strayMult = r.stray_mult }
end

-- AddAnimal / RemoveAnimal export with Phase 1 (animal CRUD does not exist
-- yet; registering a surface that returns ERR_INTERNAL would be worse than
-- its absence — fields/exports are only ever ADDED, so landing them later
-- breaks nobody).

-- ============================================================================
-- Registration
-- ============================================================================

exports('GetRanch', API.GetRanch)
exports('GetRanchByOwner', API.GetRanchByOwner)
exports('IsRanchMember', API.IsRanchMember)
exports('GetMemberGrade', API.GetMemberGrade)
exports('GetHerdCount', API.GetHerdCount)
exports('IsOnDuty', API.IsOnDuty)
exports('SetStrayMultiplier', API.SetStrayMultiplier)
