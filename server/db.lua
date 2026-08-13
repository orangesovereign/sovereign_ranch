--[[
  server/db.lua — thin oxmysql wrappers + the ranch queries (design §3).

  Mirrors the suite's db.lua: every wrapper is pcall-guarded, a SQL error
  logs and returns nil/false rather than throwing. The domain layer
  (server/ranches.lua, server/members.lua) owns the in-memory caches;
  everything here is the write-through path underneath them.
]]

Db = {}

local function safe(fn, query, params)
  local ok, res = pcall(fn, query, params)
  if not ok then
    Log.error('db error: %s | query: %s', tostring(res), tostring(query))
    return nil
  end
  return res
end

--- First row or nil.
function Db.single(query, params)
  return safe(MySQL.single.await, query, params)
end

--- All rows (possibly empty array) or nil on error.
function Db.query(query, params)
  return safe(MySQL.query.await, query, params)
end

--- INSERT; returns insert id or nil.
function Db.insert(query, params)
  return safe(MySQL.insert.await, query, params)
end

--- UPDATE/DELETE; returns affected row count or nil.
function Db.execute(query, params)
  return safe(MySQL.update.await, query, params)
end

-- ============================================================================
-- Schema bootstrap (Config.AutoRunSchema) — sql/install.sql is idempotent.
-- ============================================================================

-- Statement-by-statement (banking's pattern): comments are stripped from the
-- WHOLE file before splitting on ';' — the other way round, a semicolon
-- inside a `--` comment splits the comment and the tail poisons the next
-- statement. Every statement is CREATE TABLE IF NOT EXISTS, so re-running
-- on every boot is safe.
function Db.runSchema()
  local raw = LoadResourceFile(GetCurrentResourceName(), 'sql/install.sql')
  if not raw or raw == '' then
    Log.error('sql/install.sql missing — schema not verified')
    return false
  end
  local stripped = raw:gsub('%-%-[^\n]*', '')
  local count, failed = 0, 0
  for stmt in stripped:gmatch('[^;]+') do
    local cleaned = stmt:gsub('^%s+', ''):gsub('%s+$', '')
    if #cleaned > 0 then
      count = count + 1
      if Db.query(cleaned) == nil then
        failed = failed + 1
        Log.error('schema statement %d failed: %s', count, cleaned:sub(1, 120))
      end
    end
  end
  if failed == 0 then
    Log.info('schema verified (%d statements)', count)
  end
  Db.runMigrations()
  return failed == 0
end

--- Column additions to tables that already exist. `CREATE TABLE IF NOT
--- EXISTS` cannot add a column to a live table, and `ADD COLUMN IF NOT
--- EXISTS` is MariaDB-only — so each migration asks information_schema
--- first. Idempotent by construction: re-running finds the column and
--- skips. Append new entries here; never rewrite history.
function Db.runMigrations()
  local migrations = {
    -- none yet — Phase 0 ships the base schema
  }
  for _, m in ipairs(migrations) do
    local row = Db.single([[
      SELECT COUNT(*) AS n FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?
    ]], { m.table, m.column })
    if row and tonumber(row.n) == 0 then
      if Db.query(m.ddl) ~= nil then
        Log.info('migration: added %s.%s', m.table, m.column)
      else
        Log.error('migration FAILED: %s.%s', m.table, m.column)
      end
    end
  end
end

-- ============================================================================
-- Ranch rows. Nullable columns use SENTINELS at this boundary (the suite
-- rule): a Lua nil in an oxmysql param array punches a hole in the table and
-- truncates every value after it. Callers pass '' for absent strings/JSON
-- and 0 for absent numbers; NULLIF turns them back into real SQL NULLs.
-- ============================================================================

--- Every ranch row, boot-time cache load.
function Db.loadRanches()
  return Db.query([[
    SELECT id, ident, owner_charid, owner_userid, biz_key, stray_mult,
           webhook_url, settings,
           UNIX_TIMESTAMP(created_at) AS created_at
    FROM sovereign_ranch_ranches
  ]], {})
end

--- Insert a ranch record. Returns insert id or nil.
function Db.insertRanch(r)
  return Db.insert([[
    INSERT INTO sovereign_ranch_ranches
      (ident, owner_charid, owner_userid, biz_key, stray_mult, webhook_url, settings)
    VALUES (?, NULLIF(?, 0), NULLIF(?, ''), NULLIF(?, ''), ?, NULLIF(?, ''), NULLIF(?, ''))
  ]], {
    r.ident, r.owner_charid or 0, r.owner_userid or '', r.biz_key or '',
    r.stray_mult or 1.0, r.webhook_url or '', r.settings or '',
  })
end

--- Write the mutable fields of one ranch (write-through from the cache;
--- ident never changes post-create).
function Db.updateRanch(r)
  return Db.execute([[
    UPDATE sovereign_ranch_ranches SET
      owner_charid = NULLIF(?, 0),
      owner_userid = NULLIF(?, ''),
      biz_key      = NULLIF(?, ''),
      stray_mult   = ?,
      webhook_url  = NULLIF(?, ''),
      settings     = NULLIF(?, '')
    WHERE id = ?
  ]], {
    r.owner_charid or 0, r.owner_userid or '', r.biz_key or '',
    r.stray_mult or 1.0, r.webhook_url or '', r.settings or '', r.id,
  })
end

-- ============================================================================
-- Membership rows
-- ============================================================================

--- Every membership row, boot-time cache load.
function Db.loadMembers()
  return Db.query([[
    SELECT id, ranch_id, charid, grade, wage_override, on_duty,
           accrued_minutes, unpaid_cents, hired_by,
           UNIX_TIMESTAMP(hired_at) AS hired_at
    FROM sovereign_ranch_members
  ]], {})
end

--- Insert a membership row. Returns insert id or nil (nil also when the
--- uq_member unique key rejects a second ranch for the character).
function Db.insertMember(m)
  return Db.insert([[
    INSERT INTO sovereign_ranch_members (ranch_id, charid, grade, hired_by)
    VALUES (?, ?, ?, NULLIF(?, 0))
  ]], { m.ranch_id, m.charid, m.grade or 0, m.hired_by or 0 })
end

--- Write the mutable fields of one membership row.
function Db.updateMember(m)
  return Db.execute([[
    UPDATE sovereign_ranch_members SET
      grade = ?, wage_override = NULLIF(?, 0), on_duty = ?,
      accrued_minutes = ?, unpaid_cents = ?
    WHERE id = ?
  ]], {
    m.grade or 0, m.wage_override or 0, m.on_duty and 1 or 0,
    m.accrued_minutes or 0, m.unpaid_cents or 0, m.id,
  })
end

--- Remove a membership row (fire / teardown).
function Db.deleteMember(id)
  return Db.execute('DELETE FROM sovereign_ranch_members WHERE id = ?', { id })
end

-- ============================================================================
-- Animal rows (Phase 1). The herd cache in server/animals.lua owns these
-- rows in memory; the SIM writes behind through Db.flushAnimal(s).
-- ============================================================================

--- Every living animal row, boot-time cache load. Dead rows stay in the
--- table as the death record but never enter the cache.
function Db.loadAnimals()
  return Db.query([[
    SELECT id, ranch_id, species, sex, name,
           UNIX_TIMESTAMP(born_at) AS born_at,
           sim_minutes, scale, health, hunger, thirst, groom,
           sick_state, pregnant_until, product_progress, product_ready,
           state, pos, meta
    FROM sovereign_ranch_animals
    WHERE state <> 'dead'
  ]], {})
end

--- Insert one animal. Returns insert id or nil.
function Db.insertAnimal(a)
  return Db.insert([[
    INSERT INTO sovereign_ranch_animals
      (ranch_id, species, sex, name, sim_minutes, scale, health, hunger,
       thirst, groom, sick_state, state, pos)
    VALUES (?, ?, ?, NULLIF(?, ''), ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''))
  ]], {
    a.ranch_id, a.species, a.sex, a.name or '',
    a.sim_minutes or 0, a.scale or 0.5, a.health or 100,
    a.hunger or 100, a.thirst or 100, a.groom or 100,
    a.sick_state or 'healthy', a.state or 'penned', a.pos or '',
  })
end

--- Write-behind for one animal's mutable simulation fields.
function Db.flushAnimal(a)
  return Db.execute([[
    UPDATE sovereign_ranch_animals SET
      name = NULLIF(?, ''), sim_minutes = ?, scale = ?, health = ?,
      hunger = ?, thirst = ?, groom = ?, sick_state = ?,
      pregnant_until = NULLIF(?, 0), product_progress = ?, product_ready = ?,
      state = ?, pos = NULLIF(?, '')
    WHERE id = ?
  ]], {
    a.name or '', a.sim_minutes or 0, a.scale or 0.5, a.health or 100,
    a.hunger or 100, a.thirst or 100, a.groom or 100, a.sick_state or 'healthy',
    a.pregnant_until or 0, a.product_progress or 0, a.product_ready and 1 or 0,
    a.state or 'penned', a.pos or '', a.id,
  })
end

--- Mark one animal dead (row kept as the record; slot freed by the cache).
function Db.markAnimalDead(id)
  return Db.execute(
    "UPDATE sovereign_ranch_animals SET state = 'dead', health = 0 WHERE id = ?", { id })
end

--- Remove a row outright (market sale in Phase 4 archives via events; admin).
function Db.deleteAnimal(id)
  return Db.execute('DELETE FROM sovereign_ranch_animals WHERE id = ?', { id })
end

-- ============================================================================
-- Teardown freeze (Phase 0)
-- ============================================================================

--- Freeze every live animal of a ranch back to 'penned' (teardown, crash
--- recovery at boot). Position is kept. Returns affected count.
function Db.penAllAnimals(ranchId)
  return Db.execute([[
    UPDATE sovereign_ranch_animals
    SET state = 'penned'
    WHERE ranch_id = ? AND state IN ('spawned','straying','wrangling','transit')
  ]], { ranchId })
end

--- Herd wipe (Config.WipeHerdOnSellBack). Dead rows go too — the ledger of
--- record for deaths is the Discord/event log, not the table.
function Db.deleteAnimals(ranchId)
  return Db.execute('DELETE FROM sovereign_ranch_animals WHERE ranch_id = ?', { ranchId })
end
