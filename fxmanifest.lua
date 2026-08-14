fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'Sovereign'
name 'sovereign_ranch'
description 'Sovereign Ranch — livestock, care, production, wrangling and crew for MLO ranch properties'
version '0.1.0'
lua54 'yes'

-- ============================================================================
-- Load order is deliberate (the realestate idiom): config + shared vocabulary
-- underpin everything, the logger and bridge come before any module that
-- could want to speak, the external adapters (estate, bank, notify) wrap the
-- other resources, then the domain modules, then the API surface, then
-- bootstrap. Money, property, tax, doors and fences are NOT here — they are
-- sovereign_banking's and sovereign_realestate's (design §1); we only adapt.
-- ============================================================================

shared_scripts {
  '@sovereign/init.lua',   -- the `sv` kernel (ownership, focus, interact, notify, progress)
  'config/config.lua',     -- global tunables; money authored in dollars, stored in cents
  'config/animals.lua',    -- per-species stats: models, prices, needs, growth
  'config/market.lua',     -- the Valentine dealer (survey-gated), delivery terms
  'config/ranches.lua',    -- per-ranch mapped points (barn, coop, pasture...)
  'locales/en.lua',        -- every player-facing string
  'shared/enums.lua',      -- species, sex, states, capabilities, error codes, T() accessor
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/logging.lua',    -- leveled console log + batched Discord mirror (suite house logger)
  'bridge/vorp.lua',       -- the ONLY file that talks to VORP directly
  'server/db.lua',         -- prepared oxmysql wrappers + schema install + migrations
  -- Adapters at the edges (design §1.11) — one file per external resource.
  'server/estate.lua',     -- sovereign_realestate: property truth, zones, access, lifecycle events
  'server/bank.lua',       -- sovereign_banking: the ranch business account
  'server/notify.lua',     -- server → client notification seam (sv.notify on the client)
  -- Domain modules.
  'server/ranches.lua',    -- ranch registry keyed by realestate ident; lifecycle + reconcile
  'server/members.lua',    -- crew membership, hire/fire/promote, grade + access sync
  'server/animals.lua',    -- the herd: cache, caps, buy, care, pen/release (Phase 1)
  'server/troughs.lua',    -- feed/water troughs + chicken scatter (Phase 1)
  'server/spawns.lua',     -- presence sweep, steward orders, netId ledger + Phase 0 probe
  'server/needs.lua',      -- the SIM tick: needs decay, sickness ladder, death (Phase 1)
  'server/requests.lua',   -- the validated inbound net-event surface (Phase 1)
  'server/api/events.lua', -- outbound sovereign_ranch:server:* emitters (emit-only)
  'server/api/exports.lua',-- the public export surface (suite contract)
  'server/admin.lua',      -- /ranchadmin + Config.Debug dev levers
  'server/main.lua',       -- bootstrap: schema, job registration, cache load, boot reconcile
}

client_scripts {
  'client/main.lua',       -- boot, notify receiver, probe dress assist
  'client/animals.lua',    -- steward spawner, registry, dress rule (Phase 1)
  'client/care.lua',       -- tend prompt + status text (Phase 1)
  'client/troughs.lua',    -- trough discovery, fill prompt, scatter (Phase 1)
  'client/menus.lua',      -- Herd Book + dealer (Phase 1)
}

dependencies {
  'sovereign',
  'vorp_core',
  'oxmysql',
  'sovereign_realestate',
  'sovereign_banking',
}
