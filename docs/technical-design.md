# Sovereign Ranch — Technical Design v1.0

**Resource name:** `sovereign_ranch` (county convention — events `sovereign_ranch:server:*`, tables `sovereign_ranch_*`, exports resolve by this name).
**Scope:** the full v1 script as designed in `design_brief.md` v0.3 — animals, care, production, wrangling, transport & market, crew & payroll, admin — delivered in 6 phases.
**Framework:** VORP Core (RedM) · **DB:** MySQL via oxmysql · **Property:** sovereign_realestate · **Money:** sovereign_banking · **Lib/UI:** sovereign (`sv`) + sovereign_ui · **Recipes:** sovereign_crafting (consumer of our items, not a dependency)
**Out of scope forever (owned elsewhere):** property sale/tax/doors/fences (realestate), accounts/payroll engine (banking), crafting recipes (crafting), horses (stables).

> All integration surfaces confirmed against installed source on 13 Aug 2026: realestate `server/api/exports.lua` + `events.lua` + `shared/enums.lua`, banking `server/api/exports.lua`, vorp_core `server/apicontroller.lua` (`RegisterJobs`), sovereign `modules/interact/client.lua` (prompts functional), sovereign_ui `docs/LUA_API.md`.

---

## 1. Design Principles

- **Server-authoritative.** Every animal stat, cooldown, yield, sale, wage-minute, and grade change is decided server-side. Clients request and render. Minigame results are interaction data, never entitlement.
- **The suite contract.** Mutating exports return `(ok, resultOrErrorCode)` and never throw; reads return plain values. Money in **integer minor units (cents)**, currency `0 = money`. `opts.reason` ledger categories, idempotency keys on money mutations. No inbound net events on authority paths — client → server goes through VORP server callbacks, each validated (membership, grade, distance, cooldown, caps).
- **Adapters at the edges.** One file per external resource (`server/bank.lua`, `server/estate.lua`, `server/notify.lua`, `bridge/vorp.lua`). Every call pcall-guarded, explicit-self proxies. Feature modules never touch an external export directly.
- **RedM, not FiveM.** sovereign_lib `CLAUDE.md` is binding: `rdr3_warning` in the manifest, `RegisterRawKeymap` never `RegisterKeyMapping`, control hashes not integers, natives verified against `natives_rdr3.json` before use, adaptive `Wait()`, artifacts owned via `sv.ownership`.
- **No FiveM assets or code as reference — ever [Wilbur ruling 2026-08-13].** Stricter than the lib's "verify before use" rule: FiveM/GTA V resources, snippets, and assets are not consulted at all when writing this script. Acceptable references are RedM-native sources only: the RDR3 native tables, rdr3_discoveries, VORP core/lib source, the installed Sovereign suite, and RedM-specific open-source resources. Where a pattern exists only in FiveM form, we derive it fresh from the RDR3 tables rather than porting.
- **Config-first.** Every species stat, price, timer, cooldown, yield, wage, and location lives in config. Adding a species is config only.
- **Pause when offline.** Nothing about a ranch costs the server anything while no member is on duty. Spawned-only simulation, batched writes.

---

## 2. Resource Structure

```
sovereign_ranch/
├── fxmanifest.lua                -- rdr3_warning, lua54, @sovereign/init.lua shared
├── config/
│   ├── config.lua                -- global tunables (ticks, caps, keys, webhooks, debug)
│   ├── animals.lua               -- per-species: models, prices, needs, growth, products, yields
│   ├── market.lua                -- Valentine dealer/buyer/export/chicken-ped locations, age pricing
│   └── wages.lua                 -- per-grade hourly defaults, payroll tick, suspension rules
├── shared/
│   └── enums.lua                 -- species, sex, life-stage, sickness, activity, err codes, reasons
├── server/
│   ├── main.lua                  -- bootstrap: schema install, job registration, cache load
│   ├── db.lua                    -- oxmysql prepared wrappers + dbupdater-style migration
│   ├── ranches.lua               -- ranch registry (keyed by realestate ident), lifecycle
│   ├── estate.lua                -- sovereign_realestate adapter + event subscriptions
│   ├── bank.lua                  -- sovereign_banking adapter (business account, RunPayroll)
│   ├── members.lua               -- membership table, hire/fire/promote, grade sync, access sync
│   ├── duty.lua                  -- clock-in/out, wage-minute accrual, hourly payroll tick
│   ├── animals.lua               -- animal CRUD, caps, buy (dealer/delivery), sell, slaughter
│   ├── needs.lua                 -- needs/sickness/growth/pregnancy tick service (the SIM)
│   ├── production.lua            -- readiness timers, collection validation, yields
│   ├── strays.lua                -- stray roller, fenceBroken multiplier, wrangle sessions
│   ├── transport.lua             -- herd-run sessions (drive-to-market, drive-home), market sales
│   ├── spawns.lua                -- spawn ledger: which animal is spawned where, by whom
│   ├── admin.lua                 -- admin commands + menu backend, dev levers
│   ├── logging.lua               -- Discord webhooks (per-ranch + staff), sv.log
│   └── api/
│       ├── exports.lua           -- integration surface (suite contract)
│       └── events.lua            -- outbound sovereign_ranch:server:* emitters (emit-only)
├── client/
│   ├── main.lua                  -- boot, ranch zone awareness, duty prompts
│   ├── animals.lua               -- ped spawn/despawn/appearance (scale, sick overlay), status text3d
│   ├── care.lua                  -- feed/water/brush/collect prompts (sv.interact), anims, minigames
│   ├── herd.lua                  -- follow/lead behaviours, lasso hooks, wrangle + drive client logic
│   ├── menus.lua                 -- sovereign_ui management surfaces (herd book, crew, ledger view)
│   └── admin.lua                 -- admin menu client
├── sql/
│   └── install.sql               -- idempotent CREATE TABLE IF NOT EXISTS
└── locales/
    └── en.lua                    -- all strings from day one
```

---

## 3. Data Model (MySQL)

Three tables. The ranch ledger is **not** a table — it is the bank business account realestate registers at purchase. Property identity, zones, doors, tax: realestate's table, referenced by `ident`.

### 3.1 `sovereign_ranch_ranches` — one row per ranch-class property that has ranch state

```sql
CREATE TABLE IF NOT EXISTS `sovereign_ranch_ranches` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `ident`           VARCHAR(64)  NOT NULL,          -- FK-by-convention → realestate property ident
  `owner_charid`    INT NULL,                       -- mirror of realestate owner (cache; realestate is truth)
  `owner_userid`    VARCHAR(64) NULL,               -- VORP user identifier — the 1-ranch-per-ACCOUNT key
  `biz_key`         VARCHAR(64) NULL,               -- bank business key (from realestate registration)
  `stray_mult`      FLOAT NOT NULL DEFAULT 1.0,     -- raised by fenceBroken, decays back to 1.0
  `webhook_url`     VARCHAR(255) NULL,              -- per-ranch Discord channel (boss-set)
  `settings`        JSON NULL,                      -- boss-tunable: wages per grade, toggles
  `created_at`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ident` (`ident`),
  KEY `idx_owner_user` (`owner_userid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### 3.2 `sovereign_ranch_members` — crew + duty + wage accrual

```sql
CREATE TABLE IF NOT EXISTS `sovereign_ranch_members` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `ranch_id`        INT UNSIGNED NOT NULL,
  `charid`          INT NOT NULL,
  `grade`           TINYINT UNSIGNED NOT NULL DEFAULT 0,   -- 0..4, mirrors VORP job grade
  `wage_override`   INT UNSIGNED NULL,                     -- cents/hour; NULL = per-grade default
  `on_duty`         TINYINT(1) NOT NULL DEFAULT 0,
  `accrued_minutes` SMALLINT UNSIGNED NOT NULL DEFAULT 0,  -- reset on each payroll payout
  `unpaid_cents`    INT UNSIGNED NOT NULL DEFAULT 0,       -- carried when the account was short
  `hired_by`        INT NULL,
  `hired_at`        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_member` (`charid`),                       -- one ranch per character, any role
  KEY `idx_ranch` (`ranch_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Notes: the boss is a member row at grade 4 (uniform queries: "everyone at ranch X" is one SELECT). `uq_member` enforces one-ranch-per-character for employment; the stricter **1-ranch-per-account ownership** rule is enforced at purchase time inside realestate (§5.3 patch).

### 3.3 `sovereign_ranch_animals` — the herd

```sql
CREATE TABLE IF NOT EXISTS `sovereign_ranch_animals` (
  `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `ranch_id`        INT UNSIGNED NOT NULL,
  `species`         VARCHAR(16) NOT NULL,           -- 'cow','pig','sheep','goat','chicken' (enum by config)
  `sex`             ENUM('m','f') NOT NULL,         -- m: bull/boar/ram/buck/rooster
  `name`            VARCHAR(48) NULL,
  `born_at`         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `sim_minutes`     INT UNSIGNED NOT NULL DEFAULT 0,   -- simulated (on-duty) minutes lived — drives growth & age tiers
  `scale`           DECIMAL(4,3) NOT NULL DEFAULT 0.500, -- ped scale 0.500 → 1.000
  `health`          TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `hunger`          TINYINT UNSIGNED NOT NULL DEFAULT 100,  -- decays; feed restores
  `thirst`          TINYINT UNSIGNED NOT NULL DEFAULT 100,  -- decays; water restores
  `groom`           TINYINT UNSIGNED NOT NULL DEFAULT 100,  -- cows/bulls only; brush restores
  `sick_state`      ENUM('healthy','sick','critical') NOT NULL DEFAULT 'healthy',
  `pregnant_until`  INT UNSIGNED NULL,              -- sim_minutes threshold when birth fires
  `product_progress` SMALLINT UNSIGNED NOT NULL DEFAULT 0,  -- minutes toward next product-ready
  `product_ready`   TINYINT(1) NOT NULL DEFAULT 0,
  `state`           ENUM('penned','spawned','straying','wrangling','transit','dead') NOT NULL DEFAULT 'penned',
  `pos`             JSON NULL,                      -- last world position when spawned/straying
  `meta`            JSON NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ranch` (`ranch_id`),
  KEY `idx_state` (`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Notes:
- **`sim_minutes` is the clock.** Animals age/grow/gestate only while being simulated (a member on duty + animal spawned) — this is the "pause when offline" rule expressed in data. Wall-clock (`born_at`) is display flavor only.
- `state = 'penned'` = despawned/frozen: no needs decay, no growth, no production, zero server cost.
- Caps enforced in `animals.lua`: ≤ **20 per species per ranch**, from config.

---

## 4. Ranch Lifecycle — driven entirely by realestate events

```
realestate: propertySold (class=='ranch')
        │
        ▼
[ ranches.ensure(ident) ] → create/claim row, mirror owner_charid + owner_userid,
        │                    resolve biz_key, upsert member row grade 4,
        │                    set VORP job rancher:4, GrantAccess mirror
        ▼
   [ ACTIVE ] ←────────── daily reconcile (boot + cron): realestate owner vs our mirror
        │
realestate: propertySoldBack | propertyConfiscated | propertyRepossessed
        │
        ▼
[ ranches.teardown(ident) ] → despawn all animals → state 'penned', clear duty flags,
                              fire all members (job → unemployed for chars whose job == rancher),
                              RevokeAccess mirrors, zero accrued wages (log them), archive note.
                              Animal rows are KEPT (herd survives an ownership transfer intact;
                              wiped only on propertySoldBack per Config.WipeHerdOnSellBack).
```

- Payload fields treated as optional (suite rule). Each handler re-reads truth from realestate exports rather than trusting the payload beyond `ident`.
- **Boot reconcile:** on start, `ListProperties({ class='ranch' })` → ensure a ranch row per owned property, verify owner mirrors, verify every member's VORP grade matches the membership table (fix toward the table), re-freeze any `spawned` animals left over from a crash (→ `penned`, position kept).

---

## 5. Jobs, Crew, Duty & Payroll

### 5.1 Job registration (server start, before anything touches jobs)

```lua
Core.RegisterJobs({
    rancher = {
        privateJob = false,
        grades = {
            [0] = { label = 'Ranch Hand' },
            [1] = { label = 'Senior Hand' },
            [2] = { label = 'Foreman' },
            [3] = { label = 'Ranch Manager' },
            [4] = { label = 'Rancher', privateGrade = true },
        },
    },
}, GetCurrentResourceName())
```

### 5.2 Permission map (single source of truth: `shared/enums.lua`)

| Capability | 0 Hand | 1 Senior | 2 Foreman | 3 Manager | 4 Rancher |
|---|---|---|---|---|---|
| feed / water / brush / wrangle / collect | ✔ | ✔ | ✔ | ✔ | ✔ |
| buy livestock, drives, market sales, treat sickness | | | ✔ | ✔ | ✔ |
| hire/fire (below Manager), promote ≤ Foreman | | | | ✔ | ✔ |
| promote/demote Manager, set wages, ledger withdraw, slaughter | | | | | ✔ |

Checks are always **server-side**: `Members.can(charid, 'capability')` resolves ranch + grade from the membership table (never from the client, never from the VORP job alone).

### 5.3 The 1-ranch-per-account patch (lives in realestate, tracked here)

Realestate enforces one business-class property per **character**. Before completing a **ranch-class** sale, its purchase flow must additionally check every character on the buyer's VORP user identifier for an existing ranch-class holding. Small guarded query + one new error code (`ERR_ACCOUNT_HAS_RANCH`). Deliverable of our Phase 0 (it must exist before the first ranch is sold).

**Landed 2026-08-13, widened by the dual-use ruling:** a ranch counts as home AND business, filling both ownership slots (`Properties.blockingHolding` in realestate's state machine + all three purchase gates). The account-wide check runs pre-charge and again post-charge (yield race). Realestate's `GetProperty`/`ListProperties` views now also expose `bizKey` for business classes — how our `Ranches.activate` resolves the bank account.

### 5.4 Duty clock & wage accrual

- Clock-in/out: `sv.interact` prompt at the ranch (config point per ranch, boss-placeable later). Auto clock-out on disconnect, on fire/demote-below-member, on ranch teardown.
- **Accrual rule (locked):** each server-side minute tick, a clocked-in member accrues 1 wage-minute iff **(a)** inside ranch land/interior (`IsInsideProperty`) **or (b)** flagged in an active tracked activity: wrangle session or herd-run session (transport module owns those flags). Otherwise the minute silently doesn't count.
- **Payroll tick (hourly):** for each ranch with accrual, build `payrollTable = { {charid, amount = minutes/60 * wage, memo}, ... }` → `Bank.RunPayroll(bizKey, table, { reason = 'ranch_wages', idem = 'wages:<ranchid>:<hourstamp>' })`. On `ERR_INSUFFICIENT_FUNDS`: nothing pays (atomic); minutes convert to `unpaid_cents`, hands get a sovereign_ui notify, and duties suspend (care prompts disabled) until the boss funds the account and back-pay clears. Mirrors realestate's guard-wage pattern.

---

## 6. Animal Simulation — the SIM (server/needs.lua)

### 6.1 Simulation gate

A ranch is **hot** when ≥1 member is on duty. Only hot ranches tick. Within a hot ranch, only `spawned|straying|wrangling|transit` animals tick. `penned` rows are never read by the tick.

### 6.2 The tick (default cadence 60s, config)

Per hot ranch, one pass over its live animals (in-memory cache, write-behind):

1. **Needs decay:** hunger/thirst (and groom for cows/bulls) decay by per-species config points. Feed/water/brush actions restore (server-validated prompt completions with per-animal cooldowns).
2. **Sickness ladder:** any need below `SickThreshold` for `SickAfterMinutes` → `sick` (production halts, visual cue). Still neglected past `CriticalAfterMinutes` → `critical` (health drains). Health 0 → `dead` (row kept for the log, ped despawned, slot freed). Treatment: Foreman+ uses `ranch_medicine` item → back to `healthy`, needs reset to modest values.
3. **Growth:** needs above `GrowThreshold` → `sim_minutes += tick`, `scale` interpolates 0.5 → 1.0 across `GrowMinutes` (per species). Life stage derives from `sim_minutes`: young → prime → adult → old (per-species bands; drives market pricing §8.3).
4. **Pregnancy:** breeding action (Foreman+, requires healthy m+f pair of species, cooldowns both sides) sets `pregnant_until = sim_minutes + GestationMinutes` with `BreedChance`. Tick past threshold → new row (baby, random sex, scale 0.5) if species cap allows; else birth holds until a slot frees.
5. **Production progress:** §7.
6. **Stray roll:** §8.1.
7. **Batched write-behind:** one multi-row UPDATE per ranch per tick; full flush on ranch going cold, resource stop, and every `Config.FlushMinutes`.

### 6.3 Spawn model (server/spawns.lua + client/animals.lua)

- Server owns the **spawn ledger**: which animal ids are spawned, at which coords, and which client is **steward** (spawner). Clients never decide.
- **Phase 0 probe (build ruling required):** attempt server-side `CreatePed` under OneSync for RedM. If server-created networked peds prove reliable (persist, migrate, animate), the steward concept shrinks to "server spawns, nearest client drives behaviours." If not: the first on-duty member at the ranch becomes steward, spawns peds **networked**, registers netIds with the server; on steward disconnect the server re-assigns and the new steward re-resolves entities by netId (respawn fallback). The design works either way; only `spawns.lua`/`client/animals.lua` internals differ.
- Entity → animal binding via state bags (`Entity(ped).state.sov_animal = id`) so any client (lasso, prompts) can resolve the animal id locally and ask the server.
- Peds: per-species model + sex variant from `config/animals.lua` (drafted from known RDR2 models — `a_c_cow`, `a_c_bull_01`, `a_c_pig_01`, `a_c_sheep_01`, `a_c_goat_01`, `a_c_chicken_01`, `a_c_rooster_01` — **each verified against rdr3_discoveries before use**, per lib rules). Scale applied via ped scale native (verify exact native in Phase 1; devchacha/BTC prove the technique in RedM).
- All spawned peds are owned artifacts (`sv.ownership`, destructor deletes ped) — a restart mid-shift strands nothing.

---

## 7. Production & Collection

- **Readiness (passive):** while needs ≥ `ProduceThreshold` and `healthy`, `product_progress` accrues per tick; at `ProduceMinutes` (per species) → `product_ready = 1` (visual cue: text3d tag / slight glow via config).
- **Collection (active):** `sv.interact` hold-prompt on the animal (milk cow/goat, gather eggs, shear sheep) → server validates (member, grade 0+, ready, distance, per-animal cooldown) → animation + **sovereign_ui minigame** (config per action: `SkillCheck` milking, `HoldSteady` shearing, none for eggs) → server grants items via vorp_inventory and resets progress. Minigame result modulates yield within config bounds only.
- **Products (items, consumed by sovereign_crafting):** `ranch_milk`, `ranch_goat_milk`, `ranch_egg`, `ranch_wool`, `ranch_manure` (shovel prompt at manure piles), plus butcher outputs.
- **Butchering (Rancher-only decision):** butcher station prompt → carcass yield table per species/life-stage (`ranch_pork`, `ranch_beef`, hides, feathers...). Pig slaughter is the pork pipeline feeding player-market trade and the export ped.

---

## 8. Strays & Wrangling · Transport & Market

### 8.1 Stray roller (server/strays.lua)

- Per tick, each spawned animal rolls `StrayChancePerHour × ranch.stray_mult` (converted to per-tick). On success: `state = 'straying'`, server picks a drift point beyond the land polygon (config distance band), steward client walks the ped there; it then loiters.
- **`fenceBroken` (realestate event):** `stray_mult += Config.FenceStrayBump` (cap `Config.FenceStrayMax`), decays back toward 1.0 per hour — fixed fences quickly calm the herd. We never touch fence state itself.
- Strays are announced (sovereign_ui TopNotice to on-duty members) and marked with a config-gated blip.

### 8.2 Wrangling loop (client/herd.lua + server session)

- Lasso the straying animal (lasso detection on a ped carrying our state-bag id) → server opens a **wrangle session** (this flags wage accrual §5.4) → ped calms, `TaskFollowToOffsetOfEntity` behind the player (walk-only per config).
- Range leash: if player-to-animal distance exceeds `WrangleLeash` for `WrangleGraceSeconds` → breaks loose (`straying` again, session stays open). Re-lasso resumes.
- Crossing back inside the land polygon (`IsInsideProperty`) → `state = 'spawned'`, session closes, condition nudge reward + Discord log.

### 8.3 Herd runs & the Valentine market (server/transport.lua)

- **Sell run (cows/bulls/goats/sheep/pigs):** Foreman+ starts a herd run at the ranch, selecting up to `MaxDriveHead` animals → those enter `transit` and follow (same follow tech as wrangling, multi-animal). Wage accrual flags on for all participating on-duty members. At the Valentine stockyard zone, the buyer ped prompt sells each delivered animal: price = per-species base × **life-stage multiplier** (young/prime/adult/old — fixed, from config; no demand simulation in v1) × sickness penalty. Proceeds → ranch business account (`reason='ranch_livestock_sale'`). Rows → removed (archived in log).
- **Buy run:** dealer ped at Valentine lists stock (sovereign_ui ItemPicker/Transaction); pay from ranch account (Foreman+). Bought animals either (a) spawn at the stockyard in `transit` — drive them home; crossing the home polygon pens them; or (b) **delivery**: price × `DeliveryPremium`, rows created directly as `penned` after `DeliveryDelayMinutes`.
- **On-property sales:** chicken buyer ped/menu at the ranch buys chickens + eggs/products outright (`reason='ranch_goods_sale'`). **Export ped** (Valentine, config) buys pork/meat at export rates (`reason='ranch_export'`). Player-market trade needs nothing from us — products are ordinary inventory items.
- Drive hazards (predator/stray events mid-run) are **Phase 6** (contract drives) — the plain sell run ships without them first.

---

## 9. Client Architecture

- **Interaction:** everything in-world is `sv.interact` — prompts (`press` for status, `hold` for feed/water/brush/collect, groups per animal so one animal shows one prompt cluster), `text3d` for the [G]-style status readout (name, needs bars as text, ready flag), `marker` for drive waypoints and the stray drift point (config-gated). Zero raw `UiPrompt*` calls in this resource.
- **Management surfaces (sovereign_ui):** Herd Book (`OpenMenu` → per-animal `OpenContext`: rename via `OpenInput`, breed, send to barn/pasture), Crew panel (hire nearby via `OpenSelect`, promote/demote/fire via `OpenContext`, wages via `OpenQuantity` — gated per §5.2), Ledger view (read-only `GetTransactions` render + withdraw via `OpenTransaction`, Rancher only), Buy/Sell flows (`OpenItemPicker` + `OpenTransaction` + `OpenReceipt`), drives (`ShowObjectives`, `ShowTimer`). Focus/controls entirely via the `sv` kernel.
- **Notifications: `sv.notify` (lib module, functional as of Aug 13).** `sv.notify.show{ title, message, tone, renderer = 'nui'|'native' }` plus `.top`, `.location`, `.announce`, and `notify.native.left/tip/top` — all behind the kernel's shared rate limiter, so a bug can't flood the screen. House style for this script: **native cards** for game-flavored moments (item received, animal penned), **styled toasts** for server-voiced ones (errors, payroll, market receipts). Server-side sends go through `server/notify.lua`, a thin event that invokes `sv.notify` on the target client.
- **Progress bars: `sv.progress` (lib module, functional as of Aug 13).** Promise-shaped and queued: `if sv.progress.start({ label='Milking...', duration=5000, canCancel=true, disable={'attack','aim'} }) then request server grant end`. Never takes focus. Used for every timed care/collect/butcher action; pairs with `sv.interact` hold-prompts (short holds = prompt progress, long actions = progress bar).
- **Perf rules:** adaptive `Wait()` everywhere; prompt distance tests are engine-side (`sv.interact` context points); one status-text render loop active only when aiming at/near an animal; ped scale + sick overlay applied on spawn and on state change, not per frame.

## 10. Outbound Events & Exports

`server/api/events.lua` (emit-only, flat primitive payloads, fields only ever added):

```
sovereign_ranch:server:ranchActivated      { ident, ownerCharid }
sovereign_ranch:server:ranchTorndown       { ident, reason }
sovereign_ranch:server:handHired           { ident, charid, grade, by }
sovereign_ranch:server:handFired           { ident, charid, by }
sovereign_ranch:server:handPromoted        { ident, charid, grade, by }
sovereign_ranch:server:animalBought        { ident, animalId, species, delivery }
sovereign_ranch:server:animalSold          { ident, animalId, species, cents }
sovereign_ranch:server:animalDied          { ident, animalId, species, cause }
sovereign_ranch:server:animalBorn          { ident, animalId, species }
sovereign_ranch:server:productCollected    { ident, animalId, item, count }
sovereign_ranch:server:strayEscaped        { ident, animalId }
sovereign_ranch:server:strayRecovered      { ident, animalId, charid }
sovereign_ranch:server:driveStarted        { ident, head, by }
sovereign_ranch:server:driveCompleted      { ident, delivered, cents }
sovereign_ranch:server:payrollRun          { ident, hands, cents, ok }
```

`server/api/exports.lua` (suite contract — mutators `(ok, err)`, reads plain):

```lua
-- reads
GetRanch(ident)                 -- public view | nil
GetRanchByOwner(charid)         -- public view | nil
IsRanchMember(charid, ident?)   -- bool (any ranch if ident nil)
GetMemberGrade(charid)          -- { ident, grade } | nil
GetHerdCount(ident, species?)   -- number
IsOnDuty(charid)                -- bool
-- mutators
AddAnimal(ident, species, sex, opts)     -- admin/event tooling
RemoveAnimal(animalId, reason)
SetStrayMultiplier(ident, mult)          -- events/weather scripts can spook herds
```

## 11. Admin, Webhooks & Dev Levers

- `/ranchadmin` (group-gated `admin`,`superadmin`) → sovereign_ui menu: list ranches (owner, herd counts, account balance read, duty roster) · open any Herd Book · add/remove animals · set needs/sickness · force teardown/reconcile · toggle per-ranch webhook.
- Webhooks (`server/logging.lua`): staff channel (all ranches) + per-ranch boss-set channel — hire/fire, sales, payroll, deaths, strays, admin actions. Same envelope style as realestate's `Log.discord`.
- Dev levers (`Config.Debug` only, realestate's `/sre_backdate` idiom):
  `/sr_tick <ident>` force one sim tick · `/sr_age <animalId> <simMinutes>` · `/sr_ready <animalId>` · `/sr_stray <animalId>` · `/sr_payroll <ident>` force payroll tick · `/sr_probe_spawn` (Phase 0 server-spawn probe).

## 12. Performance Budget

- Cold ranch: **0** queries, 0 threads, 0 entities.
- Hot ranch: 1 tick/60s over ≤100 cached rows (20×5 species), 1 batched UPDATE; ≤ `Config.MaxSpawnedPerRanch` (default 40) peds concurrently spawned, remainder penned. Idle client threads at `Wait(500)`+.
- Server-wide: tick loop iterates hot ranches only; with every ranch hot and full this is trivially within budget on the suite's evidence (devchacha holds 250–300 live animals at 50–60 players with the same shape).
- Diagnostics: `sv.interact.ticks()` sampling client-side; `/sr_stats` prints cache sizes, hot ranches, last tick cost server-side.

---

## 13. Phased Build Plan

Each phase lands runnable + testable with its own ledger (realestate's `docs/testing/` idiom); two-player items go to the county Master Duo Ledger (section **RN**).

**Phase 0 — Foundation & seams** *(no gameplay)*
Manifest (rdr3_warning, lua54, `@sovereign/init.lua`) · schema install + dbupdater · enums · adapters (estate/bank/vorp/notify) · job auto-registration · realestate event subscriptions + boot reconcile · ranch row lifecycle · membership table + grade sync + GrantAccess mirror · **realestate 1-per-account patch** · **server-spawn probe → build ruling** · logging skeleton.
*Accept:* buy a ranch on a test server → row appears, buyer is Rancher g4 with access; repossess → clean teardown; probe ruling written down.

**Phase 1 — Animals exist & are cared for**
Buy at dealer (drive-home in walking-follow form) + delivery · spawn ledger + steward (per ruling) · pen/release · needs decay + feed/water/brush prompts + cooldowns · sickness ladder + medicine · death · Herd Book v1 (list, rename, pen/release) · caps.
*Accept:* full care loop on one cow and one chicken batch; neglect → sick → treat; crash mid-shift leaves no orphan peds.

**Phase 2 — Production**
Readiness timers · collect prompts + anims + minigames · items granted · manure piles · butcher station + yields · chicken/product ped at ranch · export ped · crafting handshake (items exist, sovereign_crafting recipes confirmed consuming them).
*Accept:* milk/eggs/wool/manure/pork all reach inventory and sell at the right peds for the right cents into the business account.

**Phase 3 — Growth & breeding**
sim_minutes growth + ped scaling · life stages · breeding + gestation + birth (cap-aware) · age-tier market pricing wired.
*Accept:* calf born, visibly grows across a session, sells at young vs prime prices correctly.

**Phase 4 — Strays, wrangling & the market run**
Stray roller + fenceBroken multiplier · wrangle sessions (lasso → follow → leash-break → home detect) · herd sell-runs to Valentine · buy-run drive-home upgraded to full herd tech · stockyard buyer pricing.
*Accept:* fence broken → stray rate visibly rises; full drive of 6 head sells at Valentine; leash-break and re-lasso works.

**Phase 5 — Crew & payroll**
Duty clock + prompts · wage-minute accrual (property OR active session) · hourly RunPayroll + shortfall suspension + back-pay · crew panel · admin suite + webhooks complete.
*Accept:* two-player ledger: hire, promote to Manager, Manager hires a third, hourly payroll pays only accrued minutes, shortfall suspends and back-pays.

**Phase 6 — Contract drives** *(the mission layer)*
Drive contracts (config templates: route, head, payout) · hazards (predator ambush, storm spook → mass stray event via `SetStrayMultiplier`) · `ShowObjectives`/`ShowTimer` presentation · scaled payouts to the business account.
*Accept:* a two-player contract drive with one ambush completes and pays.

---

## 14. Open Build Rulings (to be written during build, realestate-style)

1. **Server-side CreatePed on RedM/OneSync** — Phase 0 probe decides steward model (§6.3).
2. **Ped scale native** — verify exact RDR3 native + arity before Phase 3 scaling.
3. **Lasso detection** — event/native for "this ped is lassoed by this player" needs a Phase 4 spike; fallback is a prompt-based catch on a straying animal.
4. **Model hashes** — verify every species/sex model against rdr3_discoveries in Phase 1.
5. **`RunPayroll` society vs business key** — ~~confirm the bank accepts a business key where it takes `society`~~ **RESOLVED 2026-08-13 (Phase 0, from banking source): it does NOT.** `Society.payroll` resolves `Config.Societies` only; business accounts (`owner_type='business'`) are invisible to it. Phase 5 decision: add a `RunBusinessPayroll(bizKey, entries, opts)` export to sovereign_banking (mirror of `Society.payroll` over `Business.account` — preferred, needs Wilbur's sign-off as a banking change) or fall back to per-hand `Transfer`s (loses batch atomicity). `server/bank.lua`'s `Bank.runPayroll` already calls the business-aware name so the banking patch needs no ranch-side change.

## 15. Reference

`design_brief.md` v0.3 (decisions) · `ranch_script_research.md` (landscape) · realestate `integration-reference.md` + `api/` (verified surfaces) · sovereign_lib `CLAUDE.md` (RedM rules) · sovereign_ui `LUA_API.md` (surfaces & minigames).
