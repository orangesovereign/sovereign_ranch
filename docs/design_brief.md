# sovereign_ranch — Design Brief v0.3
**Project:** Private in-house ranch script for Sovereign County RP
**Stack:** Lua · VORP Core · oxmysql · sovereign lib (`sv`) + sovereign_ui · sovereign_realestate · sovereign_banking · sovereign_crafting
**Status:** Design phase — all round-2 questions resolved; job spec finalized
**Last updated:** August 13, 2026

---

## 1. Locked Design Decisions

### 1.1 Ownership & Property Lifecycle (contracts now VERIFIED)
- Ranches are **MLO ranch properties** owned by **sovereign_realestate**, which already has first-class support: `Enums.Class.RANCH`, land + interior polygon zones (`/zonepoint`), realtor-brokered sales, confiscation/repossession pipeline, per-property access rights.
- sovereign_ranch **subscribes** to realestate's outbound events (server-side `AddEventHandler`, payload fields treated as optional):
  - `sovereign_realestate:server:propertySold` → if property class == `ranch`: initialize ranch record, assign owner the Rancher boss grade, register membership.
  - `propertySoldBack` / `propertyConfiscated` / `propertyRepossessed` → teardown: strip job/membership, despawn & archive animals, freeze ledger activity.
- Ranch discovery: `ListProperties({ class = 'ranch' })`; geography via `resolvePropertyAt(coords)` / `IsInsideProperty(coords, ident)` — **the ranch script never draws its own zones**; the property's land polygon IS the ranch boundary.
- Owner checks: `IsPropertyOwner(charid, ident)` / `GetPropertyOwner(ident)`.
- When hiring a hand, also call `GrantAccess(ident, charid, { storage=..., ... })` so realestate's door/storage rights stay in sync with ranch employment; `RevokeAccess` on fire.
- ⚠️ **Overlap to resolve:** realestate Phase 5 already implements **fence wear + repair on Ranch/Farm class properties** (wears while owner online, repaired at the piece). Ranch chores must complement, not duplicate this — see Open Question #1.

### 1.2 Jobs & Employees — "Shared job + ranch ID" (FINALIZED)
- One shared VORP `rancher` job (updated per Wilbur mid-review: Ranch Manager tier at grade 3 with hire/fire → boss moves to grade 4):
  | Grade | Label | Assignment |
  |---|---|---|
  | 0 | Ranch Hand | script (hire) or admin repair |
  | 1 | Senior Hand | script (promote) or admin repair |
  | 2 | Foreman | script (promote) or admin repair |
  | 3 | Ranch Manager | script (promote) or admin repair |
  | 4 | Rancher | **PRIVATE_GRADE** — script-only, set on property purchase |
- Registered **automatically at resource start** via `Core.RegisterJobs` (verified API in installed vorp_core `server/apicontroller.lua:226`); a manual `config/jobs.lua` block is also documented as backup. Server registration overrides the config file.
- **Permission split (standard, updated):**
  - All grades: feed, water, brush, wrangle strays, collect products.
  - Foreman (2)+: buy livestock, herd off-property / cattle drives, sell at market, treat sickness.
  - Ranch Manager (3)+: **hire/fire** (grades below Manager), promote up to Foreman.
  - Rancher (4) only: promote to/demote from Manager, set wages, ledger withdraw, slaughter decisions.
- Script-side membership table (charid → property ident, grade, hired_at) scopes which ranch; hire/fire/promote syncs VORP grade + membership row + realestate `GrantAccess`/`RevokeAccess` together.
- Max **10 employees per ranch**.
- **Wages — hourly, per-grade, automated (FINALIZED):** wages accrue only while a hand is **on duty AND either (a) physically on ranch property** (realestate land/interior zone test) **or (b) engaged in a tracked off-property ranch activity — a herd run/cattle drive or an active wrangling loop.** Off duty, or idling off-property with no active task, accrues nothing.
  - Implies an explicit **clock-in/clock-out duty state** (prompt at the ranch; auto clock-out on disconnect and on fire/demote-to-nonmember).
  - Accrual tick server-side (per-minute counters → hourly payout); paid via `sovereign_banking:RunPayroll` from the ranch business account. Per-grade defaults in config, boss-adjustable.
  - If the account can't cover payroll: hands notified, unpaid hands' duties suspend until paid (mirrors realestate's guard-wage pattern).

### 1.3 Money — rides sovereign_banking's business account (VERIFIED)
- Suite convention: **all amounts in integer cents**; every mutating call returns `(ok, resultOrErrorCode)`, never throws; idempotency keys on mutations; `opts.reason` ledger categories (stable strings, ≤40 chars).
- Ranch is a **non-residential class** → realestate already calls `RegisterBusiness` at purchase, so **every owned ranch has a bank business account with a tax basis, and the bank assesses its licence fee on its own schedule.** The ranch script builds **no tax engine at all.**
- **The "ranch ledger" = the ranch's business account** (`GetBusinessAccount(bizKey)`). Livestock/goods sale proceeds credit it; wages and purchases debit it. No script-side balance column, no double bookkeeping.
- The ranch script never touches VORP currency directly — banking exports only (`AddMoney`/`RemoveMoney` for wallet-side, `Transfer`, `RunPayroll`).

### 1.4 Animal Simulation
- **Species (v1), gendered:** Cow/Bull, Pig (sow/boar), Sheep (ewe/ram), Goat (doe/buck), Chicken/Rooster. Adding species = pure config.
- **Caps (FINALIZED):** 1 ranch per **account** (see §1.12 — needs a small realestate patch, realestate currently enforces per *character*), max **20 of each animal species** per ranch, max **10 employees** per ranch.
- **Care verbs:** feed, water, **brush** (cows & bulls — a recurring care need on those species), breed, herd to pasture, herd back to ranch, **wrangle strays**, butcher.
- **Wrangling (FINALIZED):** a chore loop — animals periodically stray off the property. **Lasso the stray → it calms and follows you. Stray too far from it in transit → it breaks loose, stops following, and must be lasso'd again.** Home test = realestate's land polygon via `IsInsideProperty`. **Broken fences (realestate's `fenceBroken` event) raise the stray rate** — fences themselves stay 100% realestate's system (§1.12).
- **Persistence — pause when offline:** needs decay/growth tick only while a ranch member is online and the animal is spawned; barn/penned-despawned animals are frozen. Zero cost for inactive ranches.
- **Neglect — sickness ladder:** needs unmet → production stops → visibly sick (treatable, medicine/vet item) → death if ignored.
- **Breeding:** gender-required, chance-based pregnancy → offspring; babies grow with visual ped scaling over real hours.

### 1.5 Production — Hybrid (passive readiness + active collection)
- Timers gated on needs-met determine readiness; collection is an active interaction with animation and/or **sovereign_ui minigame** (7 already shipped: SkillCheck, PrecisionBar, ButtonSequence, MemorySequence, Lockpicking, HoldSteady, TimingSequence — no third-party minigame dependency needed).
- Products: milk (cows/goats), eggs (chickens), wool (sheep), manure; butchering yields per-species carcass tables.
- Minigame results are **client interaction data, never entitlement** — server validates cooldowns, distance, permissions, yields (suite rule, stated in sovereign_ui docs).

### 1.6 Selling & Markets (FINALIZED)
- **Herding animals — cows, bulls, goats, sheep, pigs: physically transported** (driven/led) to the livestock market to sell live. This is the cattle-drive gameplay.
- **Pigs' value chain:** sold live at market, **or slaughtered for meat**; pork sells on the player market (as tradeable items) or **for export via a ped/menu**.
- **Chickens (and eggs/products): sold from a menu/ped on the ranch property.**
- **Market location (v1): Valentine only.** Fixed prices **dependent on animal age** (age tiers, per-species config). Architecture keeps market locations as a config array so more towns are drop-in later.
- **Livestock acquisition:** dealer NPC(s) in market towns — buy and **drive them home** — or **delivery to the ranch for a premium** (config markup).
- Sale proceeds → ranch business account (cents), with `opts.reason` categories for the bank ledger (e.g. `ranch_livestock_sale`, `ranch_goods_sale`, `ranch_export`).

### 1.7 In-Scope Extra Systems
- **Crafting/processing lives in sovereign_crafting** (FINALIZED). sovereign_ranch produces the raw ingredients (milk, eggs, wool, pork, manure...) as inventory items; recipes (cheese, butter, jerky, feed) are sovereign_crafting's domain. Ranch may register stations/placements via the existing hooks.
- **Cattle drives / herding missions:** contract drives cross-map with hazards and scaled payouts. sovereign_ui's `ShowObjectives` / `ShowTimer` overlays fit this directly.

### 1.8 Out of Scope (for now)
- PvP rustling/theft; on-ranch farming/crops (future).
- Anything realestate owns: property sale/transfer, tax, doors/keys, break-ins, guards, rentals, **and fences** (see §1.12).
- **Horses — entirely sovereign_stables' domain** (FINALIZED). Drives/wrangling assume players ride their own stabled horses; the ranch script never spawns, stores, or sells horses.

### 1.9 UI Layer (revised to suite reality)
- **In-world: `sv.interact` (sovereign lib — now functional, verified in source Aug 13).** `sv.interact.prompt{ key='INPUT_*', label, mode='press|hold|mash', coords, radius, group, onComplete }` gives native RDR2 prompts with engine-side distance culling, hold-progress for free, gamepad support, and kernel-owned cleanup on resource stop. Plus `sv.interact.text3d` and `sv.interact.marker` for herd-status text and drive checkpoints. **sovereign_ranch writes no raw UiPrompt code.** sovereign_interact's ALT wheel remains an option where a wheel fits better.
- **Management surfaces:** **sovereign_ui exports** (OpenMenu, OpenSelect, OpenTransaction, OpenConfirm, OpenQuantity, OpenDocument, Progress, Notify/TopNotice) rather than a bespoke NUI bundle — consistent with the suite, gamepad-supported, and the focus stack/control suppression is already solved by the `sv` kernel. A dedicated React surface (e.g. a herd ledger book) only if a real need outgrows these components.

### 1.10 Admin Tooling — Full Suite (v1)
- Admin commands + menu: inspect/edit any ranch, set stats, manage animals, wipe/reset; dev/test levers following the suite's pattern (`/sre_backdate`-style backdating for growth/production ticks, gated by `Config.Debug`).
- Discord webhooks: per-ranch + staff channel (realestate's `Config.Discord.webhooks` pattern).
- Lifecycle handled by realestate events (no separate repossession logic here).

### 1.11 Technical Direction (aligned to suite conventions, from installed source)
- `shared_scripts { '@sovereign/init.lua' }` → `sv` global; use `sv.ownership` (artifact registry — every prompt/blip/ped/cam owned and swept on stop), `sv.focus` (never `SetNuiFocus`), `sv.controls`, `sv.log`. `ensure sovereign` before consumers.
- **Adapters at the edges** — one file per external resource (`bridge/vorp.lua`, `server/bank.lua`, `server/realestate.lua`, `server/notify.lua`), every call pcall-guarded, explicit-self proxies. VORP never called from feature modules.
- **RedM-not-FiveM rules** (sovereign_lib CLAUDE.md is authoritative): `rdr3_warning` line mandatory, `RegisterRawKeymap` not `RegisterKeyMapping`, control hashes not integers, verified natives only, adaptive `Wait()`, engine-side prompt distance tests.
- **Server-authoritative:** growth/needs/production tick server-side, spawned-animals-only processing, batched SQL; server-side cooldowns and validation on every action. **No inbound net events on authority paths** (suite rule: `AddEventHandler` server-side only; clients go through validated callbacks).
- **Own event surface:** emit `sovereign_ranch:server:<verb>` (animalSold, animalDied, driveCompleted, handHired...) — flat primitive payloads, fields only ever added.
- **Own exports** following the suite contract: mutators `(ok, err)`; reads return plain values. E.g. `IsRanchHand(charid, ident)`, `GetRanch(ident)`, `GetHerd(ident)`.
- DB: idempotent auto-installing schema (`sql/install.sql`), oxmysql prepared statements. Tables (draft): `sovereign_ranch_ranches` (keyed by realestate ident), `sovereign_ranch_members`, `sovereign_ranch_animals`.
- Locale file structure from day one.

---

## 2. Resolved Integration Contracts (verified from installed source, Aug 13 2026)

| Need | Answer |
|---|---|
| Know a ranch was bought | `sovereign_realestate:server:propertySold` event; filter `class == 'ranch'` |
| Know a ranch was lost | `propertySoldBack` / `propertyConfiscated` / `propertyRepossessed` events |
| Ranch boundary / "is animal home?" | realestate land zone: `IsInsideProperty(coords, ident)`, `resolvePropertyAt(coords)` |
| Owner / access checks | `IsPropertyOwner`, `GetPropertyOwner`, `HasPropertyAccess`, `GrantAccess`/`RevokeAccess` |
| Ranch ledger | Bank **business account** (auto-created at purchase via `RegisterBusiness`); `GetBusinessAccount`, credits/debits via banking exports |
| Taxes | Already handled — bank assesses business licence fee; **build nothing** |
| Wages | `RunPayroll` (atomic batch, pays into hands' bank accounts) |
| Notifications | **`sv.notify`** (functional Aug 13) — NUI toast or native RDR2 card behind one rate-limited interface; `.top`/`.location`/`.announce` |
| Progress bars | **`sv.progress`** (functional Aug 13) — promise-shaped, queued, focus-free |
| Menus/inputs/confirms/minigames | sovereign_ui exports (see §1.9) |
| Focus/keybinds/artifact cleanup | `sv` kernel (focus stack, controls arbiter, ownership registry, raw keymaps) |
| In-world prompts / 3D text / markers | **`sv.interact`** — functional as of Aug 13 (press/hold/mash prompts, engine distance culling, groups, onComplete, owned cleanup; `text3d`; `marker`) |
| Storage | **Split by ownership [ruling 2026-08-14]:** general property storage is realestate's stash at the deed — not ours, never duplicated. The ranch registers only **husbandry-specific** containers (the egg-only coop basket; a milk house or tack room later) via vorp_inventory `registerInventory` — `limit` is **slots**, not weight; `whitelistItems` + `limitedItems` enforce what a container may hold. Rule of thumb: if it would make sense on a house, it is realestate's. |
| sovereign lib status | Kernel verified live 13 Aug 2026 (loader, ownership, focus, controls, logger, UI seam) **+ `sv.interact` prompts/text3d/markers now functional**. Not yet built: NUI bus, point/zone scheduler — don't depend on those |

---

## 3. Round-2 Decisions Log (Aug 13, 2026)

1. **Fences** → realestate's system; `fenceBroken` raises the stray/wrangling rate. ✔
2. **Pigs** → driven to market live, or slaughtered; pork → player market or export ped. ✔
3. **Crafting** → sovereign_crafting owns recipes; ranch supplies ingredients. ✔
4. **Wages** → automated **hourly** per-grade payroll from ranch account; accrual requires on-duty + (on property OR active herd run/wrangle). Clock-in/out duty state. ✔
5. **Job** → `rancher`, 5 grades (0 Hand, 1 Senior Hand, 2 Foreman, 3 Ranch Manager, 4 Rancher/boss-private); Managers have hire/fire (Wilbur mid-review addition). Auto-registered by the script. ✔
6. **Wrangling** → lasso → calm-follow → breaks loose if you range too far → re-lasso. ✔
7. **Acquisition** → dealer NPCs in market towns (drive home) or ranch delivery at premium. ✔
8. **Market** → Valentine only for v1; fixed age-dependent prices. ✔
9. **Horses** → sovereign_stables only. ✔
10. **Caps** → 1 ranch/account · 20 per species · 10 employees. ✔

## 3b. §1.12 Known Follow-ups Outside This Script

- **realestate patch needed:** enforce **per-account** (not per-character) ranch-class ownership in the realtor-brokered sale flow, before money moves. Small check against all characters on the buyer's VORP user identifier. **✔ Landed 2026-08-13 (ranch Phase 0).**
- **fenceBroken subscription:** already emitted by realestate — ranch just listens.

## 3c. Round-3 Decisions Log (Aug 13, 2026 — Phase 0 kickoff)

11. **Ranch = dual-use property (Wilbur ruling):** owning a ranch means owning both a home AND a business — it fills **both** realestate ownership slots. A ranch owner may hold no other property; owning any house or business blocks buying a ranch. Enforced in realestate's state machine + purchase flow (patched 2026-08-13). ✔
12. **1-ranch-per-account confirmed** on top of the dual-use rule. ✔
13. **Payroll ruling (design §14.5) resolved against `RunPayroll`:** banking's payroll export is society-only. Phase 5 will need a `RunBusinessPayroll` banking export (preferred, Wilbur decision pending) or per-hand transfers; the ranch's bank adapter already targets the business-aware name. ✔

---

## 4. Reference
- Landscape research: `docs/ranch_script_research.md` (14 scripts, master feature pick-list)
- Verified contracts: `sovereign_realestate/docs/integration-reference.md`, `server/api/exports.lua` + `events.lua`; `sovereign_banking/server/api/exports.lua`; `sovereign_lib/CLAUDE.md`, `sovereign/README.md`, `sovereign-ui/docs/LUA_API.md`
