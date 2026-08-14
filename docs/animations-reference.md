# Animations Reference — feeding · planting · shoveling · brushing

*Written 2026-08-13. Sources: `_reference/rdr3_discoveries` dumps
(`animations/scenarios/scenario_types_with_conditional_anims.lua`,
`megadictanims`, `scenario_attached_props`), the mosquito pack's readable
data layer (game identifiers only — its code is escrowed), and the suite's
proven usage (sovereign_herbs, sovereign_realestate, sovereign_medical's
08-ANIMATIONS discipline).*

**The rule (medical's, adopted):** a name below is either **VERIFIED IN
DUMPS** (found as a real scenario TYPE in the discoveries) or additionally
**GAME-PROVEN** (played live by a suite script). Nothing ships in a live
code path until game-proven — candidates wait behind a `/sr_anim` dev
lever and get promoted with a dated note.

**How to play them (game-proven pattern, sovereign_herbs
`client/main.lua:138`):**

```lua
-- TaskStartScenarioInPlaceHash — proven live with WORLD_HUMAN_CROUCH_INSPECT
Citizen.InvokeNative(0x524B54361229154F, ped, GetHashKey(scenario), durationMs, true, false, false, false)
```

realestate's rummage lesson applies: these must be scenario **TYPES** (the
table keys), not conditional-anim names (the values) — passing a
conditional anim silently plays nothing. Everything listed below is a type.

---

## Feeding

| Scenario type | Sexes in dump | Reads as |
|---|---|---|
| `WORLD_HUMAN_FEED_CHICKEN` | M + F | scatter grain from the hand — the chicken feed |
| `WORLD_PLAYER_CHORES_FEED_CHICKENS` | M | player-chore variant of the same (Pronghorn epilogue chores) |
| `WORLD_HUMAN_FEED_PIGS` | M only | slop toss for the pig pen |
| `WORLD_HUMAN_FEEDBAG_PICKUP` / `_PUTDOWN` (+`_NO_FEEDBAG`) | M + F | hoisting/setting a feed bag — generic livestock feed |
| `WORLD_PLAYER_CHORES_FEEDBAG_PICKUP` / `_PUTDOWN` | M | chore variants |
| `WORLD_PLAYER_CHORES_BALE_PICKUP_` / `_PUT_DOWN_` | M | hay bale carry — cattle feed flavor |

**Watering (bonus — the bucket family):**
`WORLD_PLAYER_CHORES_BUCKET_FILL` · `_BUCKET_POUR_LOW` / `_POUR_HIGH` ·
`_BUCKET_PICKUP_FULL` / `_EMPTY` · `_BUCKET_PUT_DOWN_FULL`, plus the
`WORLD_CAMP_JACK_ES_BUCKET_*` camp set (fill/pour/pickup/putdown). Pour-low
over a trough IS the watering animation.

**Hand props** (from `scenario_attached_props`): `p_feedBag01bx`,
`p_bucket03x`, `p_cs_bucket01x`, `p_hayBale03x`.

## Planting

**No true sow/plant player scenario exists in the dumps.** Working set:

| Scenario type | Sexes | Notes |
|---|---|---|
| `WORLD_HUMAN_FARMER_WEEDING` | M only | kneeling, working the soil — the closest "planting" read |
| `WORLD_HUMAN_FARMER_RAKE` | M only | standing rake work (prop in dict) — bed preparation |
| `WORLD_HUMAN_FEED_CHICKEN` | M + F | the scatter motion doubles as **seed sowing** — mosquito's own pack maps its "Fertilize" emote to exactly this scenario |
| `WORLD_HUMAN_CROUCH_INSPECT` | — | **GAME-PROVEN** (herbs + realestate) generic kneel-and-touch-ground; the safe fallback |
| `RE_MOONSHINE_ADD_PLANT` | — | CANDIDATE, prop-scenario from a random encounter; likely position-dependent — prototype before trusting |

A believable planting loop composes: FARMER_RAKE (prepare) →
FEED_CHICKEN-scatter or CROUCH_INSPECT (sow) → bucket POUR_LOW (water in).

## Shoveling

| Scenario type | Sexes | Reads as |
|---|---|---|
| `WORLD_HUMAN_GRAVEDIG` | M only (`MALE_B`) | the full digging loop — THE shovel animation |
| `WORLD_HUMAN_SHOVEL_PICKUP` / `_PUTDOWN` (+`_NO_SHOVEL`) | M | picking up / setting down the tool |
| `WORLD_HUMAN_SHOVEL_COAL_PICKUP` · `WORLD_VEHICLE_MINECART_COAL_SHOVEL` | M | coal-specific variants (coal_stables territory) |
| `WORLD_PLAYER_CHORES_PITCH_FORK_PICKUP` / `_PUT_DOWN` | M | pitchfork — mucking pens; the natural **manure collection** anim (Phase 2) |

**Hand props:** `p_shovel03x`, `p_pitchfork01x`.

## Brushing

The thinnest category — RDR2's horse brush is a game *mechanic*, not a
free-standing scenario:

| Name | Status | Notes |
|---|---|---|
| `WORLD_HUMAN_HORSE_TEND_BRUSH_LINK` | VERIFIED IN DUMPS, ⚠ CANDIDATE | dict is `amb_work@world_human_horse_tend_brush_link@paired@male_a@…` — a **paired/linked** scenario built to sync against a horse. Standalone behaviour aimed at a cow is unknown: it may play the human half fine, T-pose, or refuse. Prototype FIRST, before any design leans on it. |
| `amb_work@world_human_horse_tend_brush_link@paired@male_a@base` via `TaskPlayAnim` | CANDIDATE | fallback: play just the human clip from the dict if the scenario insists on a partner |
| `WORLD_HUMAN_CROUCH_INSPECT` | GAME-PROVEN | last-resort stand-in ("checking the animal over") if both brush candidates fail |

## Caveats that will bite

- **Female variants are thin.** Only FEED_CHICKEN and FEEDBAG carry
  `FEMALE_A` conditional anims in the dump; FEED_PIGS, GRAVEDIG, the
  chores family and both farmer scenarios are male-listed only. Medical's
  precedent (female peds silently skip male-only walk styles) says: test
  every pick on a female character before promoting, and keep
  CROUCH_INSPECT as the universal fallback.
- **Props are not automatic.** Scenario types that expect a tool usually
  conjure it, but the `_NO_SHOVEL`/`_NO_FEEDBAG`/`_NO_PITCHFORK` variants
  exist precisely because prop-less versions were needed — if a scenario
  plays empty-handed, try its base name; if it refuses, try the `_NO_*`.
- **Type vs conditional anim** (realestate's paid-for lesson): the
  distinction decides whether anything plays at all. Only ever pass the
  table KEYS above.

## ⚠ AUDITION RESULTS — live, 2026-08-13 (ledger gate VIII)

**The rule this run taught us, and it is the important part:**

> **Scenario-point scenarios do not work played in place.** The
> `WORLD_PLAYER_CHORES_*` family and every `*_PICKUP` / `*_PUTDOWN`
> transition expect a real map scenario point with an *associated prop*.
> Started with `TaskStartScenarioInPlace` they either do nothing at all,
> or spawn a prop, fail to animate, and leave the prop welded to the
> player. Plain ambient `WORLD_HUMAN_*` scenarios work fine in place.

Being present in the dumps says a name EXISTS. It says nothing about
whether it plays standalone. Only the table below is trustworthy.

| Scenario | Verdict |
|---|---|
| `WORLD_HUMAN_FEED_CHICKEN` | ✅ **WORKS** — the grain scatter. In use for chicken feed. |
| `WORLD_HUMAN_FEED_PIGS` | ✅ **WORKS** — slop toss. In use for filling feed troughs. |
| `WORLD_HUMAN_FARMER_RAKE` | ✅ **WORKS** (conjures a rake prop — sweep it after). |
| `WORLD_HUMAN_FARMER_WEEDING` | ✅ **WORKS** — kneeling; also conjures a rake. |
| `WORLD_HUMAN_CROUCH_INSPECT` | ✅ **WORKS**, no prop. The universal fallback. Visually ≈ WEEDING. |
| `WORLD_HUMAN_FEEDBAG_PICKUP` / `_PUTDOWN` | ❌ nothing plays |
| `WORLD_PLAYER_CHORES_FEED_CHICKENS` | ❌ attaches a stray bucket, no animation |
| `WORLD_PLAYER_CHORES_BUCKET_*` (all) | ❌ nothing plays; `_PICKUP_FULL` drops a bucket on the ground and froze the player |
| `WORLD_HUMAN_GRAVEDIG` | ❌ nothing plays |
| `WORLD_HUMAN_SHOVEL_PICKUP` | ❌ nothing plays |
| `WORLD_PLAYER_CHORES_PITCH_FORK_PICKUP` | ❌ nothing plays |
| `WORLD_HUMAN_HORSE_TEND_BRUSH_LINK` | ❌ paired scenario — wants a horse partner; does not play solo |

**Consequences now in the code:** watering and brushing have no
purpose-built animation and use the kneeling fallback; every scenario is
followed by an unconditional attached-prop sweep
(`RanchClearAttachedProps`, `client/anim.lua`) because the outro cannot be
trusted for scenarios that never started.

**The way forward for real prop work** (unbuilt, when fidelity matters):
skip scenarios entirely for these chores and hand-roll — `REQUEST_ANIM_DICT`
+ `TASK_PLAY_ANIM` on the dictionaries listed above, with the prop created,
attached and deleted by us (`CREATE_OBJECT` → `ATTACH_ENTITY_TO_ENTITY` on
`PH_R_HAND` → `DELETE_ENTITY`). All natives verified. That buys full
control of both the motion and the prop's lifetime, at the cost of
per-animation tuning.

## ⚠ AUDITION RESULTS — run live 2026-08-13/14 (gate VIII)

**The rule this taught us, and it governs every future pick:**

> Scenarios in the **`WORLD_PLAYER_CHORES_*`** family, and every
> **`*_PICKUP` / `*_PUTDOWN`** transition, are **scenario-POINT** scenarios.
> They expect a real map point with an associated prop, and they do **not**
> work played in place — they either do nothing at all, or conjure a prop
> and weld it to the player. Plain ambient `WORLD_HUMAN_*` scenarios work
> in place.

| Scenario | Verdict |
|---|---|
| `WORLD_HUMAN_FEED_CHICKEN` | ✅ **WORKS** — the scatter motion; now the chicken-feed and seed-sowing anim |
| `WORLD_HUMAN_FEED_PIGS` | ✅ **WORKS** — slop toss; now the feed-trough fill (male-only in dumps) |
| `WORLD_HUMAN_FARMER_RAKE` | ✅ **WORKS** — conjures a rake |
| `WORLD_HUMAN_FARMER_WEEDING` | ✅ **WORKS** — reads the same as CROUCH_INSPECT; also produced a rake once |
| `WORLD_HUMAN_CROUCH_INSPECT` | ✅ **WORKS** — the universal fallback |
| `WORLD_HUMAN_FEEDBAG_PICKUP` / `_PUTDOWN` | ❌ nothing plays |
| every `*_BUCKET_*` (POUR_LOW/HIGH, FILL, PICKUP_FULL) | ❌ nothing plays; `PICKUP_FULL` dropped a bucket on the floor and froze the player |
| `WORLD_PLAYER_CHORES_FEED_CHICKENS` | ❌ attaches a stray bucket that never leaves |
| `WORLD_HUMAN_GRAVEDIG` · `SHOVEL_PICKUP` · `PITCH_FORK_PICKUP` | ❌ nothing plays |
| `WORLD_HUMAN_HORSE_TEND_BRUSH_LINK` | ❌ **the brush candidate is dead** — a paired scenario with no partner |

**Props stick, and that is not the scenario's fault to fix.** Several of the
above leave an object welded to the player permanently. `client/anim.lua`
therefore never trusts the outro alone: after every scenario it sweeps
`GetGamePool('CObject')` and deletes anything attached to the ped.
`/sr_unstick` runs the same sweep on demand and is deliberately ungated.

**Open work — hand-rolled prop animations.** Watering and brushing have no
working scenario, so they currently kneel (`CROUCH_INSPECT`). The real fix
is to stop using scenarios for those: play the clip straight out of its
anim dict with `TASK_PLAY_ANIM` and spawn/attach/delete our OWN prop, which
gives complete control of its lifecycle. Dicts are in `megadictanims`
(e.g. `amb_work@world_human_feedbag_putdown@male_a@base`,
`amb_work@world_human_farmer_rake@male_a@base`) and the props are named in
`scenario_attached_props` (`p_feedBag01bx`, `p_bucket03x`, `p_shovel03x`,
`p_pitchfork01x`). Natives for it are already verified: `REQUEST_ANIM_DICT`
0xA862A2AD321F94B4, `TASK_PLAY_ANIM` 0xEA47FE3719165B94,
`ATTACH_ENTITY_TO_ENTITY` 0x6B9BBD38AB0796DF, `GET_PED_BONE_INDEX`
0x3F428D08BE5AAE31.

## Phase 1/2 mapping — WIRED 2026-08-13 via `Config.CareAnims`

The first picks below are live in the care verbs (scenario + `sv.progress`
bar, request fired at completion, cancel sends nothing). Female peds fall
back to CROUCH_INSPECT for anything outside `Config.FemaleSafeAnims`.
Ledger gate VIII + care gate V audition them; losers are swapped in
config, not code.

| Ranch verb | First pick | Fallback |
|---|---|---|
| Feed (chicken) | `WORLD_HUMAN_FEED_CHICKEN` | FEEDBAG_PUTDOWN |
| Feed (pig) | `WORLD_HUMAN_FEED_PIGS` | FEEDBAG_PUTDOWN |
| Feed (cow/sheep/goat) | `WORLD_HUMAN_FEEDBAG_PUTDOWN` | BALE_PUT_DOWN |
| Water | `WORLD_PLAYER_CHORES_BUCKET_POUR_LOW` | BUCKET_POUR_HIGH |
| Brush | `WORLD_HUMAN_HORSE_TEND_BRUSH_LINK` (prototype!) | CROUCH_INSPECT |
| Manure (P2) | `WORLD_PLAYER_CHORES_PITCH_FORK_PICKUP` | SHOVEL_PICKUP |
| Digging/planting (future crops) | `WORLD_HUMAN_GRAVEDIG` / FARMER_WEEDING | CROUCH_INSPECT |
