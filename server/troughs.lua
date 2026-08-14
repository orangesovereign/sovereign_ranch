--[[
  server/troughs.lua — feeding infrastructure (Wilbur ruling 2026-08-13).

  Livestock are NOT hand-fed. A member fills a trough; every animal that
  wants it walks over and helps itself until the trough runs dry. Chickens
  are the exception — their feed is scattered on the ground and the birds
  converge on the spot until it is picked clean.

  Authority: the SERVER owns whether a trough is full and how much is left.
  Clients discover the map's trough PROPS (they are ordinary world objects,
  not ours) and report "I filled the one at these coords"; the server
  validates member, capability, property and proximity before believing a
  word of it, then keys the trough by its rounded world position — stable
  across clients because it is the same map prop for everyone.
]]

Troughs = {}

local Err = Enums.Err

-- key -> { ranchId, kind = 'feed'|'water', x, y, z, units, filledAt, by }
local troughs = {}
-- key -> { ranchId, x, y, z, units, expiresAt, by }   (chicken feed)
local scatters = {}

local function keyOf(ranchId, x, y, z)
  return ('%d:%.1f:%.1f:%.1f'):format(ranchId, x, y, z)
end

-- ============================================================================
-- Filling
-- ============================================================================

--- A member filled a trough at (x,y,z). kind ∈ 'feed'|'water'.
--- Returns (ok, err). Everything about the claim is re-checked here.
function Troughs.fill(src, kind, x, y, z)
  if kind ~= 'feed' and kind ~= 'water' then return false, Err.BAD_ARG end
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  if not (x and y and z) then return false, Err.BAD_ARG end

  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local m = Members.get(charid)
  if not m then return false, Err.NOT_MEMBER end
  local ok, err = Members.can(charid, 'care', m.ranch_id)
  if not ok then return false, err end
  local ranch = Ranches.get(m.ranch_id)
  if not ranch then return false, Err.NO_RANCH end

  -- The trough must be ON the ranch, and the filler must be AT it. The
  -- client only ever named a position; both facts are established here.
  if not Estate.isInside({ x = x, y = y, z = z }, ranch.ident) then
    return false, Err.BAD_ARG
  end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false, Err.INTERNAL end
  local c = GetEntityCoords(ped)
  local dx, dy, dz = c.x - x, c.y - y, c.z - z
  local reach = (Config.Troughs.promptRange or 2.5) + 2.0
  if (dx * dx + dy * dy + dz * dz) > reach * reach then return false, Err.BAD_ARG end

  local key = keyOf(ranch.id, x, y, z)
  local t = troughs[key]
  if t and t.units >= (Config.Troughs.capacity or 24) then
    return false, Err.BUSY   -- already brim-full; nothing to do
  end

  -- Feed costs feed, once a supply chain exists to buy it from. Water is
  -- free — you are drawing it from the ranch's own well.
  if kind == 'feed' and Config.RequireFeedItem then
    if not Bridge.SubItem(src, Config.FeedItem, 1) then return false, Err.BAD_ARG end
  end

  troughs[key] = {
    ranchId = ranch.id, kind = kind, x = x, y = y, z = z,
    units = Config.Troughs.capacity or 24,
    filledAt = os.time(), by = charid,
  }
  Log.debug('trough %s filled (%s) at %s', key, kind, ranch.ident)
  Spawns.pushTroughs(ranch.id)
  return true, nil
end

--- Scatter chicken feed at the member's feet. Returns (ok, err).
function Troughs.scatter(src)
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local m = Members.get(charid)
  if not m then return false, Err.NOT_MEMBER end
  local ok, err = Members.can(charid, 'care', m.ranch_id)
  if not ok then return false, err end
  local ranch = Ranches.get(m.ranch_id)
  if not ranch then return false, Err.NO_RANCH end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false, Err.INTERNAL end
  local c = GetEntityCoords(ped)
  if not Estate.isInside({ x = c.x, y = c.y, z = c.z }, ranch.ident) then
    return false, Err.BAD_ARG
  end

  if Config.RequireFeedItem then
    if not Bridge.SubItem(src, Config.FeedItem, 1) then return false, Err.BAD_ARG end
  end

  local key = keyOf(ranch.id, c.x, c.y, c.z)
  scatters[key] = {
    ranchId = ranch.id, x = c.x, y = c.y, z = c.z,
    units = Config.Scatter.capacity or 12,
    expiresAt = os.time() + (Config.Scatter.minutes or 6) * 60,
    by = charid,
  }
  Log.debug('feed scattered at %s (%s)', key, ranch.ident)
  Spawns.pushTroughs(ranch.id)
  return true, nil
end

-- ============================================================================
-- Reads (the SIM and the client push both use these)
-- ============================================================================

--- Every live trough of a ranch, as a plain array.
function Troughs.activeFor(ranchId)
  local out = {}
  for key, t in pairs(troughs) do
    if t.ranchId == ranchId and t.units > 0 then
      out[#out + 1] = { key = key, kind = t.kind, x = t.x, y = t.y, z = t.z, units = t.units }
    end
  end
  return out
end

--- Every live scatter of a ranch (expired ones are swept as we go).
function Troughs.scattersFor(ranchId)
  local now, out = os.time(), {}
  for key, s in pairs(scatters) do
    if s.units <= 0 or s.expiresAt <= now then
      scatters[key] = nil
    elseif s.ranchId == ranchId then
      out[#out + 1] = { key = key, x = s.x, y = s.y, z = s.z, units = s.units }
    end
  end
  return out
end

--- The nearest live source this animal would walk to for `kind`, or nil.
--- FEED comes from a scatter for birds and a trough for everything else;
--- WATER always comes from a trough — chickens drink from the waterer like
--- anything else, and denying them one would just starve them of thirst.
--- Returns (source, distanceSquared, isScatter).
function Troughs.sourceFor(a, kind, pos)
  if not pos then return nil end
  local scattered = Config.Animals[a.species].scattered
  local useScatter = scattered and kind == 'feed'

  local draw = (useScatter and Config.Scatter.drawRadius
    or Config.Troughs.drawRadius) or 20.0
  local maxD2 = draw * draw
  local best, bestD2 = nil, nil

  if useScatter then
    for _, s in ipairs(Troughs.scattersFor(a.ranch_id)) do
      local dx, dy = pos.x - s.x, pos.y - s.y
      local d2 = dx * dx + dy * dy
      if d2 <= maxD2 and (not bestD2 or d2 < bestD2) then best, bestD2 = s, d2 end
    end
    return best, bestD2, true
  end

  for _, t in ipairs(Troughs.activeFor(a.ranch_id)) do
    if t.kind == kind then
      local dx, dy = pos.x - t.x, pos.y - t.y
      local d2 = dx * dx + dy * dy
      if d2 <= maxD2 and (not bestD2 or d2 < bestD2) then best, bestD2 = t, d2 end
    end
  end
  return best, bestD2, false
end

--- Consume one serving. Returns true if there was anything to take.
function Troughs.consume(key, isScatter)
  local pool = isScatter and scatters or troughs
  local row = pool[key]
  if not row or row.units <= 0 then return false end
  row.units = row.units - 1
  if row.units <= 0 then pool[key] = nil end
  return true
end

--- Drop everything belonging to a ranch (teardown).
function Troughs.clearRanch(ranchId)
  for key, t in pairs(troughs) do
    if t.ranchId == ranchId then troughs[key] = nil end
  end
  for key, s in pairs(scatters) do
    if s.ranchId == ranchId then scatters[key] = nil end
  end
end
