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

## Suggested Phase 1/2 mapping (once game-proven)

| Ranch verb | First pick | Fallback |
|---|---|---|
| Feed (chicken) | `WORLD_HUMAN_FEED_CHICKEN` | FEEDBAG_PUTDOWN |
| Feed (pig) | `WORLD_HUMAN_FEED_PIGS` | FEEDBAG_PUTDOWN |
| Feed (cow/sheep/goat) | `WORLD_HUMAN_FEEDBAG_PUTDOWN` | BALE_PUT_DOWN |
| Water | `WORLD_PLAYER_CHORES_BUCKET_POUR_LOW` | BUCKET_POUR_HIGH |
| Brush | `WORLD_HUMAN_HORSE_TEND_BRUSH_LINK` (prototype!) | CROUCH_INSPECT |
| Manure (P2) | `WORLD_PLAYER_CHORES_PITCH_FORK_PICKUP` | SHOVEL_PICKUP |
| Digging/planting (future crops) | `WORLD_HUMAN_GRAVEDIG` / FARMER_WEEDING | CROUCH_INSPECT |
