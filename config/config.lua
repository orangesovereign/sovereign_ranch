--[[
  config/config.lua — every global tunable in one place (design §1.11).
  Config-first is a hard rule: no price, timer, cap, or coordinate lives in
  code. Per-species stats live in config/animals.lua; market locations and
  pricing arrive in config/market.lua (Phase 2/4); wages in config/wages.lua
  (Phase 5).

  Owner notes: only change the values after the '=' sign; keep quotes and
  commas as they are. Money is authored in DOLLARS here — the dollars()
  helper converts once to the integer cents the bank speaks.
]]

Config = Config or {}

-- Dollars → cents, applied once at config load. Everything downstream of
-- this file is integer minor units (sovereign_banking convention).
local function dollars(d) return math.floor(d * 100 + 0.5) end
Config.dollars = dollars   -- other config files reuse the same conversion

-- ============================================================================
-- Money
-- ============================================================================
Config.Currency = 0        -- sovereign_banking currency id: 0 = MONEY. Ranch is money-only.

-- ============================================================================
-- Caps (design brief §1.4, locked)
-- ============================================================================
Config.MaxPerSpecies  = 20   -- animals of each species per ranch
Config.MaxEmployees   = 10   -- crew members per ranch, boss included? No — hands; boss is grade 4 on top
Config.MaxSpawnedPerRanch = 40 -- peds concurrently spawned per ranch (perf budget §12)

-- ============================================================================
-- The rancher job (design §5.1). Registered automatically at resource start
-- via Core.RegisterJobs — server registration overrides vorp config files.
-- Grade meanings are fixed by shared/enums.lua Capabilities; relabel freely.
-- ============================================================================
Config.JobName = 'rancher'
Config.JobGrades = {
  [0] = { label = 'Ranch Hand' },
  [1] = { label = 'Senior Hand' },
  [2] = { label = 'Foreman' },
  [3] = { label = 'Ranch Manager' },
  [4] = { label = 'Rancher', privateGrade = true },  -- boss; script-only, set on purchase
}

-- ============================================================================
-- Lifecycle & reconcile (design §4)
-- ============================================================================
Config.ReconcileMinutes    = 1440   -- full owner/grade reconcile cadence (daily); boot always runs one
Config.WipeHerdOnSellBack  = false  -- voluntary sell-back: keep (false) or wipe (true) the herd rows
Config.AutoRunSchema       = true   -- run sql/install.sql + migrations on boot

-- ============================================================================
-- Simulation & care (Phase 1). Per-species numbers live in config/animals.lua;
-- these are the global mechanics.
-- ============================================================================
Config.TickSeconds      = 60   -- SIM cadence for hot ranches (design §6.2)
Config.PresenceSeconds  = 10   -- member-position sweep (server-side; drives hot/cold + steward)
Config.FlushMinutes     = 5    -- write-behind full flush cadence

-- Care verbs: server-validated cooldowns (per animal, minutes) and restore
-- amounts (points). Range is metres from player to animal, server-checked.
Config.CareCooldownMinutes = { feed = 30, water = 20, brush = 45 }
Config.CareRestore         = { feed = 40, water = 40, brush = 50 }
Config.CareRange           = 4.0

-- Feed can require an item once sovereign_crafting/shops supply one; Phase 1
-- default is free-with-cooldown so the care loop doesn't dead-end on an
-- unobtainable item. Medicine IS an item from day one (sql/items.sql).
Config.RequireFeedItem = false
Config.FeedItem        = 'ranch_feed'
Config.MedicineItem    = 'ranch_medicine'

-- Sickness ladder (design §6.2): any need below `threshold` for
-- `sickAfterMinutes` → sick (production halts). Still neglected past
-- `criticalAfterMinutes` → critical, health drains per tick. Health 0 → dead.
Config.Sickness = {
  threshold             = 25,
  sickAfterMinutes      = 60,
  criticalAfterMinutes  = 120,
  healthDrainPerTick    = 5,
  treatRestoreNeeds     = 50,   -- needs floor after successful treatment
}

-- ============================================================================
-- Admin & debug
-- ============================================================================
Config.AdminGroups = { admin = true, superadmin = true }  -- users.group / characters.group
Config.Debug       = false   -- gates the /sr_* dev levers (backdating, probes, forced ticks)
Config.LogLevel    = 'info'  -- debug | info | warn | error

-- ============================================================================
-- Discord (the realestate webhook pattern: per-category staff hooks here,
-- plus an optional per-ranch channel stored on the ranch row, boss-set)
-- ============================================================================
Config.Discord = {
  enabled = false,
  flushSeconds = 10,
  webhooks = {
    -- category -> webhook URL ('' = off). Categories: lifecycle (ranch
    -- activated/torn down), crew (hire/fire/promote), market (buys/sales),
    -- animals (deaths, strays), payroll, admin.
    lifecycle = '',
    crew      = '',
    market    = '',
    animals   = '',
    payroll   = '',
    admin     = '',
  },
}
