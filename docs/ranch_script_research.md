# RedM Ranch Script Landscape Research
**Prepared for:** Sovereign County RP — `sovereign_ranch` (private in-house script, Lua, VORP Core)
**Date:** August 13, 2026
**Purpose:** Survey of existing RedM ranch scripts + one master pick-list of features (Gameplay / Administrative / Technical) to select from during design.

---

## Part 1 — The Landscape (Scripts Surveyed)

| # | Script | Author/Store | Framework(s) | Price | Source Access |
|---|--------|-------------|--------------|-------|---------------|
| 1 | **bcc-ranch** v2.7.2 | BCC Team (Bryce Canyon County) | VORP | Free | Open source (GPL-3.0) |
| 2 | **devchacha-ranch** ("VORP Ranch") | devchacha | VORP | Free | Open source (GPL-2.0) |
| 3 | **rsg-ranch** (BETA) | devchacha | RSG | Free | Open source |
| 4 | **BTC RANCHMAN** ("Advanced Ranch System") | BeTiuCia | VORP / RSG / TPZ | $55 | Escrow (config + locale open) |
| 5 | **MX-Ranch** | Mexicano Scripts | VORP / RSG | €49.99 | Escrow (config open) |
| 6 | **The Ranch System** (Progressive Code) | Progressive Code | VORP / RSG / QB / RedEM / RPX | €54.99 | Escrow (configs only) |
| 7 | **Dodiban Animal Ranch** | Dodiban Scripts | RSG (+ VORP) | €200.70 (OS tier) | Open-source tier sold |
| 8 | **Mack-Scripts Ranch System** (2026) | Mack Back | RSG | £50 | Closed source |
| 9 | **Erko Ranch Job** (XP/Tasks/Stash) | Erko00 | QBR / RSG | €40 escrow / €120 OS | Store currently offline |
| 10 | **TheLostRiders Free Ranch Script** | TheLostRidersMMORPG | VORP | Free (premium tier exists) | Free download |
| 11 | **RicX Farm Animals** (+ Milk Man) | RicX | RedEM / VORP / QBR / RSG | €21.70 / €28 | Partial escrow |
| 12 | **Cattle Herding by Erebus** ("Cattle Drive") | Erebus/Mosquito Scripts | VORP | $30 | Escrow |
| — | **RanchWork Camp System** | RanchWork | VORP / RSG | $15 | Escrow or OS |
| — | **bcc-farming** v3.0 | BCC Team | VORP | Free | Open source |

*Notes: RanchWork is a persistent camp/base-building script despite the name — included for its placement/roles/storage patterns. bcc-farming is a crop script — included because two ranch scripts bundle planting. "Advanced Ranch System" forum threads (5340018, 5358067) are both BTC RANCHMAN. Erebus is a single-mechanic cattle-drive script, not a full ranch.*

### Two dominant architecture philosophies

Nearly every script falls into one of two ownership models — this is the first big design fork for sovereign_ranch:

- **A. Admin/board-created ranches anywhere on the map** (bcc-ranch, MX-Ranch, Progressive Code): an admin (or command) creates a ranch at any coordinates with a radius; owner is assigned. Flexible, RP-driven placement.
- **B. Fixed, predefined purchasable ranch locations** (devchacha-ranch, rsg-ranch): 9 famous map ranches (MacFarlane, Emerald, Pronghorn, Downes, etc.) hard-configured, each tied to a VORP job with grades; players buy at a management board.
- **C. Player-placeable "ranch kit" item** (Mack-Scripts, TheLostRiders, RanchWork pattern): ranch is a placeable/packable object — deploy anywhere, even relocate.

---

## Part 2 — MASTER FEATURE LIST (Pick & Choose)

Every feature found across all scripts, deduplicated, with attribution `[script names]` so you can see who does it and how common it is.

## A. GAMEPLAY FEATURES

### A1. Ranch Ownership & Property
- **One ranch per character limit** (enforced) `[bcc-ranch, devchacha, RanchWork, TheLostRiders]`
- **Multiple ranches per player allowed** (configurable cap) `[MX-Ranch]`
- **Purchase ranch with cash at a management board / NPC** `[devchacha ($100k), Progressive Code, rsg-ranch]`
- **Admin-created ranch assigned to a player** `[bcc-ranch, MX-Ranch, Progressive Code /giveranch]`
- **Placeable/packable ranch via inventory item** (deploy anywhere, relocate) `[Mack-Scripts, TheLostRiders "ranchtoken", RanchWork "camp_kit"]`
- **Sell/transfer ranch to another player** (negotiated or fixed price, cash to seller, fresh-start reset) `[devchacha, Progressive Code]`
- **Sell ranch back to government** for 50% refund; ranch relisted as public `[devchacha]`
- **Ranch naming / renaming** `[bcc-ranch, MX-Ranch, RanchWork]`
- **Map blips** — ownership-status icons, per-ranch toggle; member-only blips `[bcc-ranch, Progressive Code, RanchWork]`
- **Ranch radius / zone** with configurable size `[bcc-ranch, MX-Ranch]`
- **Building/prop placement system**: fences, gates, coops, hen houses, troughs, barns, hitching posts — snap mode, undo, persistence `[Dodiban (deepest), Mack-Scripts, RanchWork (tents/campfires/wardrobe)]`
- **Decorative ranch NPC** with in-world placement mode `[bcc-ranch]`
- **Chicken coop as purchasable prop/prerequisite** `[bcc-ranch ($200), MX-Ranch (required for chickens)]`

### A2. Ranch Condition / Upkeep Loop
- **Ranch condition stat (0–100) that decays over time** and gates progression (animal aging halted until condition maxed) `[bcc-ranch]`
- **Environment % that decays with time and usage**; chores restore +10% w/ 1h cooldown `[TheLostRiders]`
- **Chores restore condition** — Shovel Hay, Water Animals, Repair Feed Trough, Scoop Poop; per-chore animations + skill-check minigames; chore rewards items (fertilizer) `[bcc-ranch]`
- **4 animated chore tasks affecting animal well-being** `[BTC RANCHMAN]`
- **Maintenance chores: cleaning fences, repairing troughs, raking** `[Dodiban, Mack-Scripts]`
- **Manure appears on ground, must be raked/shoveled**; collected as crafting ingredient `[MX-Ranch (rake), devchacha/rsg-ranch (shovel → manure item)]`
- **Ranch stat/earnings tiers + leaderboard** (earnings scale $10 → $2,500 with accumulated stats) `[Mack-Scripts]`

### A3. Animals — Species & Lifecycle
- **Species pools seen:** cows, bulls, pigs, sheep, goats, chickens, roosters, turkeys, rabbits, horses. Typical set = 5 species; richest = 9 `[RicX]`; gendered pairs (cow/bull, chicken/rooster) `[devchacha, BTC]`
- **Per-animal persistent identity**: unique ID, custom name, stored world position `[devchacha, BTC, Dodiban, MX-Ranch]`
- **Individual stats:** health, hunger, thirst, age, growth %, weight, XP/quality, gender, production timers `[MX-Ranch (fullest set), Progressive Code, devchacha, BTC, Dodiban]`
- **Visual growth**: babies spawn at 0.5 ped scale, grow to 1.0 over real hours (2–3h); growth halts if hungry `[devchacha, rsg-ranch, BTC]`
- **Age tiers affecting sale price** (Young 0.5× / Prime 1.5× / Adult 1.0× / Old 0.7×); too-young/too-old animals unsellable `[devchacha, bcc-ranch, Progressive Code]`
- **Hunger decay → starvation drains health → death** `[devchacha, BTC, MX-Ranch]`
- **Animal sickness + vaccination (vet mechanic)** `[MX-Ranch]`
- **Animal death: permadeath** `[RicX]` **vs 5-min recovery lockout then respawnable** `[devchacha]`
- **Reviving downed animals** `[Dodiban]`
- **Animals can get lost / wander off** `[BTC, RicX, Erebus]`
- **Barn storage**: despawned animals don't age/hunger/grow (zero overhead) `[devchacha]`
- **Spawn cap per player** (e.g. max 5 spawned animals) `[devchacha]`; capacity limits global/per-player `[BTC]`

### A4. Feeding, Watering & Care
- **Direct feeding with feed item** (+condition/hunger, cooldown per animal) `[bcc-ranch, devchacha, Mack-Scripts, Dodiban (pitchfork+haybale)]`
- **Trough infrastructure**: food/water troughs that animals consume from automatically; require periodic refilling `[MX-Ranch, Progressive Code]`
- **Customizable per-species diets** `[BTC]`
- **Watering animals as a chore** `[bcc-ranch]`
- **Production gated on care thresholds** (e.g. requires health ≥60, hunger ≥40, thirst ≥40) `[devchacha, MX-Ranch]`

### A5. Production & Harvesting
- **Passive timed production per species**: cows/goats → milk, sheep → wool, chickens → eggs, pigs/bulls/roosters → manure/fertilizer `[devchacha, MX-Ranch, Progressive Code, BTC, Mack-Scripts, Erko]`
- **Active harvesting with minigame/animation**: milking (timed squeeze minigame), shearing, egg collecting — each with own cooldown + yields `[bcc-ranch, TheLostRiders (syn_minigame), Dodiban]`
- **Product bar must be full + min growth before collection** `[MX-Ranch]`
- **Proportional yields — 2 chickens = 2 eggs per cycle** `[Erko]`
- **Butchering/skinning own animals** for meat/hide/feathers — RDO skinning animation; butcher table prop; per-species carcass yield tables `[BTC (RDO anim), devchacha (butcher table), bcc-ranch (butcher menu)]`
- **Fertile eggs — only hatch if a rooster is present** `[BTC]`
- **Ranch XP that gates production cycles** (products generate only at 100% XP) `[Erko]`

### A6. Breeding
- **Chance-based breeding attempt → pregnancy flag → offspring** (50% in devchacha; configurable chances in BTC/Progressive Code) `[devchacha, BTC, Progressive Code]`
- **Gender-required realistic reproduction** (male+female of species) `[BTC, Progressive Code (gender selection at purchase)]`
- **Cattle breeding requiring 1 cow + 1 bull + branding iron item (consumed), 60s progress** `[Mack-Scripts]`

### A7. Herding & Droving
- **Herd-to-location mechanic** raising animal condition, cooldown-limited `[bcc-ranch]`
- **/herd command**: all ranch animals within 50m follow as a group up to 15 min `[devchacha]`
- **Per-animal follow/stay toggle; send-to-barn key; status panel key** `[devchacha]`
- **Lasso + key to make cattle follow; wander-off chance; distance leash** `[Erebus]`
- **Lead cattle with rope; carry chickens** `[Dodiban]`
- **RTS-style overhead camera for field herd command** `[Dodiban]`
- **Checkpoint-trail herding runs** (5 checkpoints, ≥25m, stay close to herd) with hazards: stray animals (max 1), wolf attack (max 1 per herd) `[TheLostRiders]`
- **Herding missions**: take contract, drive configured animals cross-map, return or slaughter `[Progressive Code]`
- **Cattle drive to market required for sale** (animal must physically arrive at sale zone) `[bcc-ranch (10 auction yards), MX-Ranch, RicX, Erebus]`

### A8. Economy & Markets
- **Livestock dealers/markets at fixed map locations** for buying and selling `[devchacha (3), bcc-ranch (10 sale yards), MX-Ranch, Mack-Scripts (NPC traders), RicX (shop + butchery)]`
- **Condition/quality-scaled sale prices** (low/base/max-condition pay; quality 20+ enables re-branding; "well-managed animals worth more") `[bcc-ranch, Mack-Scripts, Dodiban, Progressive Code (XP=value)]`
- **Sale bonus items** on mature animal sales (meat/leather/wool bundles) `[devchacha, rsg-ranch]`
- **Baby animals sell at 60% of buy price; grown at 2×** `[devchacha, rsg-ranch]`
- **Cut of sales auto-deposited to ranch ledger** (20%) `[devchacha, rsg-ranch]`; sales pay to ranch wallet, not pocket `[MX-Ranch]`
- **Ranch ledger/wallet**: deposit, withdraw, pays taxes, receives sale income `[bcc-ranch, devchacha, MX-Ranch, Progressive Code, TheLostRiders]`
- **Recurring tax**: monthly on set day `[bcc-ranch (day 23)]`, weekly `[devchacha ($1,500)]`, configurable interval `[BTC]`, manual monthly `[TheLostRiders]`, optional maintenance credits `[Mack-Scripts]`
- **Repossession on unpaid tax**: owner stripped, employees fired, animals wiped; ranch relisted (e.g. at $50k) `[bcc-ranch, devchacha, TheLostRiders]`
- **Auto-Seller NPC buying goods at reduced price** (passive income alternative) `[Progressive Code]`
- **Animal market between players**: buy/sell/transfer animals player↔player and player↔NPC `[BTC]`
- **Currency type config (money vs gold)** `[Erebus]`

### A9. Employees & Roles
- **Hire/fire other players via menu; nearby-player hire** `[bcc-ranch, devchacha, BTC, MX-Ranch, Dodiban]`
- **Role tiers**: owner/manager/employee `[MX-Ranch]`; owner/co-owner/member `[RanchWork]`; VORP job grades 0–4 (Trainee→Boss), promote/demote, caps (20 employees, 4 managers) `[devchacha]`
- **Granular per-permission flags** (manage, buy, build, upgrade, herd, care, economy, sell / panel, members, props, chest, wardrobe...) `[Dodiban, RanchWork, Progressive Code (per-keyholder perms)]`
- **Owner-only menu entries hidden from employees** `[bcc-ranch]`
- **Offline fire/promote (instant DB update)** `[devchacha]`
- **Employee wage tracking (webhook-logged)** `[TheLostRiders]`
- **Job restriction**: only configured jobs may participate `[bcc-ranch RanchAllowedJobs, MX-Ranch job field]`

### A10. Storage & Crafting
- **Shared ranch inventory/stash** (vorp_inventory registerInventory; per-ranch stash; weight/slot config) `[bcc-ranch (200 slots), devchacha (grade 3+ only), MX-Ranch, Erko, Mack-Scripts, RanchWork (multi-chest)]`
- **Paid storage upgrades** (20 stages, $1k–$20k, +100→+1,950 slots) `[bcc-ranch]`
- **Grade-restricted storage access** `[devchacha]`
- **Crafting station (placeable table)**: 16 recipes — cheese, butter, fertilizer, animal feed, cloth, bread, sausage, jerky, jams... with ingredients/timers/animations `[devchacha, rsg-ranch]`
- **Products withdrawable "for sale or crafting"** `[Progressive Code]`

### A11. Farming Tie-in (on-ranch crops)
- **Plant seeds in per-ranch plantable areas**; animal fertilizers give per-species crop boosts `[Progressive Code 1.2]`
- **Full crop loop** (plant/water/fertilize/harvest, 32 crops, 3 fertilizer grades with growtime/yield multipliers, rain auto-watering, job/zone locks, smell detection for illicit crops) `[bcc-farming — reference architecture]`

### A12. PvP, Events & Extras
- **Animal theft / cattle rustling from other players' ranches** `[BTC, Mack-Scripts]`; explicit no-PvP-kill protection `[TheLostRiders]`
- **Branding & re-branding system** (brand cattle; steal + re-brand once quality ≥20) `[Mack-Scripts, Dodiban]`
- **Dynamic events**: snake ambushes, rope-spook mechanics; corral safety (animals protected in closed corrals) `[Dodiban]`
- **Wolf attacks during herding** `[TheLostRiders]`
- **Wild horse taming integration** `[Mack-Scripts]`
- **Hot air balloon ranch-kit delivery** `[Mack-Scripts]`
- **Milk delivery job** (wagon, load cans, deliver; XP unlocks dairies, yield, speed) `[RicX Milk Man]`
- **Grazing outings** (take animals out to graze as an activity; recapture wanderers) `[RicX]`

---

## B. ADMINISTRATIVE FEATURES

### B1. Admin Commands & Menus
- **Full admin menu** (`/manageRanches`, group-locked): create ranch (owner, name, radius, tax), list all, delete (with DB cleanup), change radius, rename, set condition, open any ranch inventory `[bcc-ranch — gold standard]`
- **`/createranch` + edit price/job/owner/position, delete, teleport-to-ranch** `[MX-Ranch]`
- **`/ranches` oversight UI + `/giveranch` assignment UI** `[Progressive Code]`
- **`/deleteranch [radius]`** — delete nearest ranch `[TheLostRiders]`
- **Production test command** (`/ranchtestprod`) `[MX-Ranch]`
- **Dev mode flag + dev commands** (`startRanch`, `/farmreload`) `[bcc-ranch, bcc-farming]`

### B2. Permissions & Access Control
- **Admin group gating** (admin/superadmin configurable) `[bcc-ranch]`
- **Donator/role-exclusive ranches** (admin-assign-only as perks) `[Progressive Code]`
- **Job allow-lists** for participation `[bcc-ranch]`
- **Per-ranch job binding** with standard `/setjob` override `[devchacha]`

### B3. Logging & Monitoring
- **Discord webhook logging** — global configurable `[bcc-ranch]`; per-ranch channel + separate staff channel `[MX-Ranch]`; owner-set webhook incl. employee wages `[TheLostRiders]`; activity/delivery logs `[RicX Milk Man]`
- **Camp/ranch action logs** (DB-recorded important actions) `[RanchWork]`
- **Leaderboard / stats oversight** `[Mack-Scripts]`

### B4. Lifecycle Management
- **Repossession automation** (tax failure → strip owner, fire employees, wipe animals, relist) `[bcc-ranch, devchacha, TheLostRiders]`
- **Ranch reset via owner=NULL → auto-relist for sale** `[devchacha]`
- **Toggle ranch selling entirely; toggle purchase NPC per ranch** `[Progressive Code]`

---

## C. TECHNICAL FEATURES

### C1. Framework & Dependencies
- **VORP integration**: vorp_core, vorp_character, vorp_inventory, vorp_inputs, charidentifier-keyed data `[bcc-ranch, devchacha, TheLostRiders, Erebus]`
- **Multi-framework bridge layer** (VORP/RSG/QB/RedEM/RPX behind one API; `Config.Framework` switch or fw_func.lua adapter file) `[Progressive Code (5 fw), MX-Ranch, BTC, RicX, RanchWork]`
- **Dependency philosophies**: minimal native-prompts-only, no ox_lib/ox_target `[devchacha, RanchWork, RicX]` — vs — ox_lib + ox_target stack `[MX-Ranch, Mack-Scripts, rsg-ranch]` — vs — BCC ecosystem (bcc-utils, bcc-minigames, feather-menu) `[bcc-ranch]` — vs — vendor's own core (btc-core) `[BTC]`
- **Minigame dependency for harvest actions** (bcc-minigames, syn_minigame; toggleable) `[bcc-ranch, TheLostRiders]`

### C2. Database & Persistence
- **oxmysql/MySQL persistence** — universal among persistent scripts
- **Schema pattern (bcc)**: `bcc_ranch`, `bcc_ranch_employees`, + `ranchid` column on characters; auto-migration helper (dbUpdater.lua)
- **Schema pattern (devchacha)**: `ranch_funds` (ledger/owner/tax date), `ranch_employees` (grade, hired_date), `ranch_animals` (model, name, pos xyzw, age, health, hunger, thirst, scale, production timers, pregnant, spawned) — memory-optimized column types; startup auto-migration; SQL ships item INSERTs
- **Persistent placed structures/props** `[Dodiban, RanchWork, Mack-Scripts (animal positions)]`
- **Plants/crops persisted across restarts** `[bcc-farming]`
- **Camps/ranches persist until deleted** `[RanchWork]`

### C3. Sync & Performance Architecture
- **Server-side authoritative loops**: growth/production tick fully server-side, only spawned animals processed, batched SQL per tick group (~250–300 animals @ 50–60 players) `[devchacha]`
- **Local entities + stat sync instead of full entity sync** (Progressive Code switched to this for perf) `[Progressive Code]`
- **Server-side cooldown service** (herding, feeding, milking, shearing, eggs — anti-cheat) `[bcc-ranch, Mack-Scripts]`
- **Server-side validation**: item, distance, permission, ownership, proximity, inventory `[RanchWork, bcc-farming]`
- **Anti-spam protection** `[MX-Ranch]`
- **RPC/callback layer instead of raw events** (BccUtils RPC) `[bcc-ranch]`
- **Barned/despawned animals = zero runtime overhead** `[devchacha]`
- **Claimed scale: 10,000 active animals stress-test** `[BTC — marketing claim]`

### C4. Configuration Surface
- **Split config files** (main / ranch / animals / inventory; settings + salelocation; config + shared defaults) `[bcc-ranch, TheLostRiders, MX-Ranch]`
- **Everything-exposed configs**: per-species costs, health, herd sizes, ages, roam radius, pay tiers, cooldowns, animations, minigame params, keybinds, blips, notification system selection `[bcc-ranch]`
- **Economy tuning tables**: growth rates, age pricing, base sell prices, products, sell rewards, carcass items, recipes, locations `[devchacha]`
- **Per-ranch config**: plantable area, blip, NPC toggle, purchase rules `[Progressive Code]`

### C5. API / Extensibility
- **Server exports**: `CheckIfRanchIsOwned(charid)`, `IncreaseRanchCondition`, `DecreaseRanchCondition`, `DoesPlayerWorkAtRanch(charid)` `[bcc-ranch — only script with a documented export API]`
- **Housing/property integration export** (`GetPlayerHouses`) `[bcc-farming ↔ bcc-housing]`
- **Item-based action gating** ("Ranch Book" item — optional or mandatory to open ranch actions) `[Progressive Code]`

### C6. UI Approaches
- **feather-menu menu system** `[bcc-ranch]`
- **Custom western-parchment NUI** (fonts, per-animal icons, status bars) `[devchacha, RanchWork]`
- **Native UiPrompt proximity prompts** (no target resource) `[devchacha, RicX, RanchWork, Erebus]`
- **Target-based interaction** (ox_target/rsg-target) `[Mack-Scripts, Progressive Code 1.2]`
- **Overhead RTS camera mode** `[Dodiban]`
- **Progressbars + cinematic placement camera** `[RanchWork, Mack-Scripts]`

### C7. Localization & Ops
- **Multi-language locale files** (7 langs: en/de/fr/pl/pt-BR/pt-PT/ro) `[bcc-ranch]`; en/tr `[RanchWork]`; en/pt JSON `[MX-Ranch]`; multi-lang `[TheLostRiders]`; none (hardcoded EN) `[devchacha]`
- **Version checker + update notifications** `[bcc-ranch]`
- **lua54 enabled** `[bcc-ranch]`

---

## Part 3 — Observations for a Ground-Up VORP Build

1. **No single script does everything.** The union of BTC (breeding/genders/theft), MX-Ranch (thirst/sickness/troughs/wallet), bcc-ranch (admin tooling/exports/chores), devchacha (growth scaling/crafting/job grades), Dodiban (building system/RTS herding), and TheLostRiders (herd trails/hazards) does not exist in one product. That's the opportunity.
2. **The best admin tooling is in bcc-ranch** (full admin menu + webhooks + exports); the best animal simulation is MX-Ranch/BTC; the best economy loop discipline is devchacha (ledger cut, age pricing, repossession); the best building system is Dodiban.
3. **Recurring design decisions you'll need to make** (every script answers these differently): ownership model (admin-created vs fixed locations vs placeable), animal persistence model (always-simulated vs only-when-spawned), needs depth (hunger only → hunger+thirst+health+sickness), production style (passive timers vs active minigames vs both), economy sinks (tax cadence + repossession), employee model (DB table vs VORP jobs w/ grades), interaction layer (native prompts vs menus vs target).
4. **Server-authoritative + spawned-only simulation** (devchacha pattern) is the proven perf model for VORP; batched SQL and zero-cost barned animals matter at 250+ animals.
5. **Since sovereign library is coming**, the bcc-ranch pattern of a thin RPC/util layer is worth copying — keep utility calls behind one adapter so the sovereign lib can slot in when ready.

---

## Sources

- [bcc-ranch (GitHub)](https://github.com/BryceCanyonCounty/bcc-ranch) · [BCC resources](https://bcc-scripts.com/resources/)
- [devchacha-ranch (GitHub)](https://github.com/Devchacha01/devchacha-ranch) · [rsg-ranch (GitHub)](https://github.com/Devchacha01/rsg-ranch) · [rsg-ranch forum](https://forum.cfx.re/t/free-ranch-script/5376565)
- [bcc-farming (GitHub)](https://github.com/BryceCanyonCounty/bcc-farming)
- [BTC RANCHMAN — forum (older)](https://forum.cfx.re/t/paid-vorp-rsg-advanced-ranch-system/5340018) · [forum (newer)](https://forum.cfx.re/t/advanced-ranch-system/5358067) · [Tebex](https://betiucia-scripts-shop.tebex.io/package/6938107)
- [MX-Ranch — forum](https://forum.cfx.re/t/vorp-rsg-mx-ranch/5405437)
- [Progressive Code Ranch System — Update 1.2 forum](https://forum.cfx.re/t/redm-ranch-system-update-1-2-vorp-core-rsg-core-qb-core-redem-rpx-core/5333498) · [Update 1.1 forum](https://forum.cfx.re/t/redm-ranch-system-update-1-1-vorp-core-rsg-core-qb-core-redem-rpx-core/5319821) · [Tebex](https://progressive-code.tebex.io/package/6761653) · [redmscript.com writeup](https://redmscript.com/redm-ranch-script)
- [Dodiban Animal Ranch — Tebex](https://dodiban-redm.tebex.io/package/7415463)
- [Mack-Scripts Ranch System — forum](https://forum.cfx.re/t/redm-ranching-script-updated/5339213) · [Tebex](https://mack-scripts.tebex.io/package/6688314)
- [Erko Ranch Job — forum](https://forum.cfx.re/t/qbr-rsg-ranch-job-xp-animals-products-tasks-stash/5042860)
- [TheLostRiders Free Ranch Script — forum](https://forum.cfx.re/t/free-redm-ranch-script/5411524)
- [RicX Farm Animals — Tebex](https://ricx-scripts.tebex.io/package/4515254) · [RicX Milk Man — Tebex](https://ricx-scripts.tebex.io/package/6716618)
- [Cattle Herding by Erebus — forum](https://forum.cfx.re/t/cattle-herding-by-erebus/5245906)
- [RanchWork Camp System — forum](https://forum.cfx.re/t/paid-ranchwork-camp-system-advanced-persistent-camp-system-vorp-rsg/5410686)
