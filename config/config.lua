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

-- Care verbs that are still HANDS-ON, per animal (brush, treat). Feeding
-- and watering are NOT here — you fill a trough and the animals come
-- (Wilbur ruling 2026-08-13, see Config.Troughs).
Config.CareCooldownMinutes = { brush = 45 }
Config.CareRestore         = { brush = 50 }
Config.CareRange           = 4.0

-- ============================================================================
-- TROUGHS — how livestock actually eat and drink [Wilbur ruling 2026-08-13].
-- You do not hand-feed a cow. You fill the trough; every animal that wants
-- it walks over and helps itself until the trough runs dry. Chickens are
-- the exception: their feed is SCATTERED on the ground (Config.Scatter).
--
-- Troughs are the MAP's own props, not something we place — every model
-- Rockstar ships is listed so whichever one a property happens to have
-- just works. All seven verified in rdr3_discoveries/objects.
-- ============================================================================
Config.Troughs = {
  feed = {                              -- p_farm.rpf
    'p_feedtrough01x', 'p_feedtroughsml01x',
  },
  water = {                             -- p_roadside.rpf
    'p_watertrough01x', 'p_watertrough01x_new', 'p_watertrough02x',
    'p_watertrough03x', 'p_watertroughsml01x',
  },
  scanRadius     = 40.0,   -- how far around a member we look for trough props
  scanEveryMs    = 3000,   -- discovery cadence while on the property
  promptRange    = 2.5,    -- how close to fill one
  fillSeconds    = 4,      -- the fill action's duration
  capacity       = 24,     -- animal-servings a full trough holds
  drawRadius     = 20.0,   -- a hungry animal this close will walk to it
  eatRange       = 3.0,    -- close enough to actually be feeding
  restorePerTick = 20,     -- need points restored per SIM tick while feeding
  hungerSeekAt   = 70,     -- an animal below this need goes looking
}

-- Chicken feed is thrown on the ground, and the birds converge on the spot
-- until it is picked clean.
Config.Scatter = {
  minutes        = 6,      -- how long a scatter lasts before it is gone
  capacity       = 12,     -- pecks before the ground is clean
  drawRadius     = 20.0,
  eatRange       = 2.5,
  restorePerTick = 25,
}

-- Care animations. ⚠ THESE ARE AUDITION RESULTS, not guesses — gate VIII
-- was run live on 2026-08-13 and most of the obvious-sounding scenarios
-- FAILED. The rule it taught us (recorded in docs/animations-reference.md):
--
--   Scenarios in the WORLD_PLAYER_CHORES_* family, and the *_PICKUP /
--   *_PUTDOWN transitions, are SCENARIO-POINT scenarios. They expect a
--   real map point with an associated prop and DO NOT work played in
--   place — they either do nothing or conjure a prop and weld it to you.
--   Plain ambient WORLD_HUMAN_* scenarios do work in place.
--
-- Only names confirmed working in-game appear below. Swap freely, but
-- re-audition with /sr_anim before trusting anything new.
Config.CareAnims = {
  fallback = 'WORLD_HUMAN_CROUCH_INSPECT',        -- proven: herbs, realestate, gate VIII
  feed  = { duration = 5000,
            default = 'WORLD_HUMAN_FEED_PIGS',    -- proven; a slop-toss reads right at a trough
            chicken = 'WORLD_HUMAN_FEED_CHICKEN' },  -- proven; the exact scatter motion
  -- ⚠ every bucket scenario failed the audition, so watering has no
  -- purpose-built animation. Kneeling at the trough is the honest stand-in
  -- until a hand-rolled anim-dict + our own bucket prop is built.
  water = { duration = 5000, default = 'WORLD_HUMAN_CROUCH_INSPECT' },
  -- ⚠ HORSE_TEND_BRUSH_LINK failed (it is a paired scenario and wants a
  -- horse partner). Falling back until the raw dict is prototyped.
  brush = { duration = 6000, default = 'WORLD_HUMAN_CROUCH_INSPECT' },
  treat = { duration = 4000, default = 'WORLD_HUMAN_CROUCH_INSPECT' },
}
-- Male-only scenarios silently do nothing on a female ped, so anything not
-- listed here falls back. FEED_PIGS is male-listed in the dumps.
Config.FemaleSafeAnims = {
  WORLD_HUMAN_FEED_CHICKEN   = true,
  WORLD_HUMAN_CROUCH_INSPECT = true,
}

-- Filling a FEED trough (and scattering for chickens) can cost a feed item
-- once sovereign_crafting/shops supply one. Off by default so the care loop
-- doesn't dead-end on an unobtainable item; water is always free (your own
-- well). Both names below are existing county items.
-- Existing county items (ruling 2026-08-14 — the ranch invents nothing).
Config.RequireFeedItem = false
Config.FeedItem        = 'consumable_haycube'   -- Haycube
Config.MedicineItem    = 'consumable_medicine'  -- Medicine (no vet-specific item exists)

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
-- Following & pace (drive-home now; Phase 4 wrangling and cattle drives use
-- the same machinery). Led animals MATCH THE LEADER'S GAIT [Wilbur ruling
-- 2026-08-13] — a trotting horse must not simply leave the herd behind.
--
-- The leader's speed (the MOUNT's when mounted, else the player's) is
-- sampled and mapped to a band; the follow task is re-issued only when the
-- band changes, so there is no per-frame re-tasking stutter.
--   move     1.0 walk · 2.0 run · 3.0 sprint (task movementSpeed)
--   rate     SetPedMoveRateOverride — how hard the animal may push past its
--            natural pace to keep up. Modest by design: high values make
--            the legs skate. Set every rate to 1.0 to disable the boost.
--   distance how far behind the leader it aims to sit, in metres
-- Physical truth: a full gallop still outruns cattle even boosted. They
-- string out and close the gap when you ease off — which is what a real
-- drive looks like.
-- ============================================================================
Config.FollowPace = {
  sampleMs = 400,
  bands = {
    { id = 'walk',   upTo = 2.0,   move = 1.0, walkOnly = true,  rate = 1.00, distance = 2.5, stopRange = 2.0 },
    { id = 'trot',   upTo = 4.5,   move = 2.0, walkOnly = false, rate = 1.05, distance = 3.0, stopRange = 2.5 },
    { id = 'run',    upTo = 7.5,   move = 3.0, walkOnly = false, rate = 1.15, distance = 3.5, stopRange = 3.0 },
    { id = 'gallop', upTo = 999.0, move = 3.0, walkOnly = false, rate = 1.30, distance = 4.0, stopRange = 3.5 },
  },
}

-- ============================================================================
-- PRODUCTION (Phase 2). Readiness is passive and earned: an animal only
-- accrues toward its next product while it is fed, watered and healthy —
-- neglect does not just risk the animal, it stops the income. Collection
-- itself is an active interaction the server validates.
-- ============================================================================
Config.Production = {
  needThreshold  = 50,    -- both hunger and thirst must be at least this to accrue
  requireHealthy = true,  -- sick or critical animals produce nothing
  collectRange   = 4.0,   -- metres, server-checked against the animal's ped
  collectSeconds = 5,     -- the collection action's duration

  -- (Stores live in Config.Stores, below.)
  -- Life stage scales BUTCHER yields (Phase 3 sets real stages; until then
  -- everything reads as 'prime'). Product yields are unaffected.
  stageYield = { young = 0.5, prime = 1.0, adult = 1.0, old = 0.7 },
  -- Manure: piles accumulate where livestock stand. Shovelled for fertiliser.
  manure = {
    enabled        = true,
    item           = 'fertilizer',   -- the county's existing Farming item
    perAnimalHours = 6,     -- one pile per animal per this many simulated hours
    maxPerRanch    = 12,    -- piles stop accruing past this
    yield          = { 1, 2 },
    shovelSeconds  = 6,
    sell           = Config.dollars(0.25),
  },
  -- Butchering (Rancher only — design §5.2 'manage'). Arranged through the
  -- ranch manager rather than a station of its own.
  butcher = {
    seconds   = 12,
    point     = 'manager',
  },
}

-- ============================================================================
-- THE RANCH MANAGER — one NPC, most of the business [Wilbur ruling
-- 2026-08-14]. Rather than scattering a butcher, a buyer and a clerk
-- around the yard, every ranch has a single manager standing at a mapped
-- point who handles the lot. New ranch business gets added to HIS menu,
-- not to another ped.
--
-- He deals in DELIVERY only when selling you livestock: driving stock home
-- yourself is the Valentine dealer's trade and the cattle-drive gameplay.
-- Convenience through the manager costs the species delivery multiplier
-- (config/animals.lua `price.delivery`), and `deliveryMarkup` on top if you
-- want him dearer still.
-- ============================================================================
Config.Manager = {
  enabled        = true,
  point          = 'manager',        -- mapped point in config/ranches.lua
  model          = 'a_m_m_rancher_01',  -- verified: 0x54D8BE8E, 20 variations
  label          = 'Ranch Manager',
  prompt         = 'Speak with the Ranch Manager',
  deliveryMarkup = 1.0,              -- 1.0 = the species premium is enough
}

-- ============================================================================
-- STORES — the ranch's WORKING containers.
--
-- ⚠ THE BOUNDARY [Wilbur ruling 2026-08-14]: general property storage is
-- sovereign_realestate's — it already gives every owned property a stash
-- at the deed, and we do not duplicate or replace it. What lives here is
-- only the husbandry-specific kit: containers tied to an ANIMAL FUNCTION,
-- which realestate has no business knowing about. If a container would
-- make sense on a house, it belongs to realestate, not us.
--
-- The coop is the case in point: hens lay whether anyone is watching or
-- not, so their eggs land in the basket by themselves and a hand collects
-- them from there. It only ever holds eggs — `only` is a whitelist, so a
-- coop cannot quietly become a second saddlebag.
--
-- Adding one (a milk house, a tack room) is a config entry plus a
-- surveyed point. `point` names a key in config/ranches.lua; `fallback`
-- is used when that point has not been surveyed yet.
-- ============================================================================
Config.Stores = {
  coop = {
    point    = 'coop',            -- the coop structure, already surveyed
    label    = 'Coop',
    prompt   = 'Egg Basket',
    slots    = 20,
    only     = { eggs = 500 },    -- item -> max units. Eggs and nothing else.
  },
}

-- ============================================================================
-- Wander & the stuck watchdog. RDR3 peds route themselves over the game's
-- navmesh once tasked — our job is to put them on ground the navmesh
-- actually covers, and to notice when one is grinding into a surface
-- anyway (live finding 2026-08-13: animals spawned indoors walked into
-- walls forever). Re-tasking a false positive is harmless (a grazing
-- animal just picks a new spot), so the retask threshold is deliberately
-- eager and only the WARP is conservative.
-- ============================================================================
Config.Wander = {
  radius          = 8.0,    -- how far a settled animal drifts from its anchor
  scatter         = 2.5,    -- release spread around the anchor, metres
  stuckCheckMs    = 5000,   -- watchdog sample cadence
  stuckDistance   = 0.4,    -- moved less than this between samples = one strike
  strikesRetask   = 3,      -- ≈15s pinned → clear tasks and wander afresh
  strikesWarp     = 6,      -- ≈30s pinned (retask failed) → lift to the anchor
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
