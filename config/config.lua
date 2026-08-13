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
