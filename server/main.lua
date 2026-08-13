--[[
  server/main.lua — bootstrap (design §4, §13 Phase 0).

  Order matters: schema → job registry → caches → reconcile. Everything
  after the schema is safe to re-run; the reconcile pass is the same code
  the daily timer runs.
]]

CreateThread(function()
  -- 1. Schema (idempotent) + migrations.
  if Config.AutoRunSchema then
    Db.runSchema()
  end

  -- 2. The rancher job — registered before anything can touch jobs
  --    (design §5.1). Server registration overrides vorp config files.
  Bridge.RegisterJobs()

  -- 3. Caches.
  Ranches.load()
  Members.load()

  -- 4. Boot reconcile — realestate is truth. Realestate may still be
  --    starting (ensure order isn't guaranteed across restarts), so wait
  --    for it briefly rather than skipping the pass.
  local waited = 0
  while not Estate.available() and waited < 30000 do
    Wait(1000); waited = waited + 1000
  end
  Ranches.reconcile()

  Log.info('sovereign_ranch up — Phase 0 (foundation & seams)')
end)

-- Daily reconcile (design §4). Boot ran one; this keeps long-lived servers
-- honest against drift (admin assigns, missed events).
CreateThread(function()
  local minutes = math.max(60, tonumber(Config.ReconcileMinutes) or 1440)
  while true do
    Wait(minutes * 60 * 1000)
    Ranches.reconcile()
  end
end)
