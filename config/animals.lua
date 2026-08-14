--[[
  config/animals.lua — the species catalogue. Adding a species is config
  only (design §1.11): a new entry here plus items in the inventory table is
  the whole job.

  Phase 0 ships the five locked species (design brief §1.4) with their
  gendered model names DRAFTED. ⚠️ Every model string is verified against
  rdr3_discoveries in Phase 1 before the first spawn — the lib rule. Needs,
  growth, products and yields are Phase 1–3 numbers; they live here from day
  one so the shape is settled, but nothing reads them until those phases.

  ⚠️ EVERY `item` NAME HERE IS AN EXISTING COUNTY ITEM [Wilbur ruling
  2026-08-14: use what the database already has before inventing anything].
  Verified against the county catalogue (1,014 items) — the ranch invents
  NO items at all, which is what lets sovereign_crafting recipes that
  already consume `beef`, `milk`, `eggs` and `wool` work with ranch output
  the day it ships. Names are case-sensitive as stored: `Mutton`, `Fat`.
  A `bySex` entry picks the right variant where the county stocks one per
  sex (cow/bull pelt and horn, chicken/rooster feather).
]]

Config.Animals = {
  -- `scenarios` — what the animal DOES rather than just standing there
  -- (graze while idle, eat at a filled feed trough, drink at a water
  -- trough). Every name verified as a scenario TYPE in
  -- rdr3_discoveries/animations/scenarios; per sex where the game ships a
  -- separate one (a bull is not a cow). nil = no scenario for that species
  -- yet, and the animal simply stands at the trough.
  cow = {
    label   = 'Cattle',
    models  = { f = 'a_c_cow', m = 'a_c_bull_01' },        -- verify Phase 1
    sexLabels = { f = 'Cow', m = 'Bull' },
    pen     = 'pasture',   -- which mapped point in config/ranches.lua
    scenarios = {
      f = { graze = 'WORLD_ANIMAL_COW_GRAZING',
            eat   = 'WORLD_ANIMAL_COW_EATING_GROUND',
            drink = 'WORLD_ANIMAL_COW_DRINK_TROUGH' },   -- purpose-built by R*
      m = { graze = 'WORLD_ANIMAL_BULL_GRAZING',
            eat   = 'WORLD_ANIMAL_BULL_GRAZING',
            drink = 'WORLD_ANIMAL_BULL_DRINK_GROUND' },
    },
    needsGroom = true,                                     -- cows & bulls brush (design §1.4)
    price   = { buy = Config.dollars(60.00), delivery = 1.25 },  -- delivery = premium multiplier
    needs   = { hungerPerHour = 8, thirstPerHour = 10, groomPerHour = 4 },
    growth  = { growMinutes = 1800, stages = { young = 0, prime = 600, adult = 1200, old = 1500 } },
    breeding = { gestationMinutes = 720, chance = 0.6, cooldownMinutes = 360 },
    -- Phase 2. `produce`: what accrues passively while the animal is fed,
    -- watered and healthy, and what an active collection hands over.
    -- `verb` is the player-facing word; `sell` is the per-unit price the
    -- on-ranch buyer pays. `butcher`: what a carcass yields, scaled by
    -- life stage (Config.Production.stageYield).
    produce = { item = 'milk', minutes = 90, femaleOnly = true,
                yield = { 1, 2 }, verb = 'Milk', sell = Config.dollars(1.20) },
    butcher = {
      { item = 'beef', min = 3, max = 6 },
      -- The county stocks a pelt and a horn per sex; use the right one.
      { bySex = { f = 'cows', m = 'bulls' }, min = 1, max = 2 },
      { bySex = { f = 'cowh', m = 'bullhorn' }, min = 1, max = 2 },
      { item = 'Fat', min = 1, max = 2 },
    },
  },
  pig = {
    label   = 'Pigs',
    models  = { f = 'a_c_pig_01', m = 'a_c_pig_01' },      -- sex variant check Phase 1
    sexLabels = { f = 'Sow', m = 'Boar' },
    pen     = 'stockPen',
    scenarios = {   -- no pig DRINK scenario exists in the dumps; grazing reads fine
      any = { graze = 'WORLD_ANIMAL_PIG_GRAZING',
              eat   = 'WORLD_ANIMAL_PIG_GRAZING',
              drink = 'WORLD_ANIMAL_PIG_GRAZING' },
    },
    price   = { buy = Config.dollars(25.00), delivery = 1.25 },
    needs   = { hungerPerHour = 12, thirstPerHour = 10 },
    growth  = { growMinutes = 1200, stages = { young = 0, prime = 400, adult = 800, old = 1000 } },
    breeding = { gestationMinutes = 480, chance = 0.7, cooldownMinutes = 240 },
    produce = nil,   -- pigs ARE the value chain: no timer, all carcass
    butcher = {
      { item = 'pork',    min = 4, max = 8 },
      { item = 'boars',   min = 1, max = 1 },
      { item = 'porkfat', min = 1, max = 3 },
    },
  },
  sheep = {
    label   = 'Sheep',
    models  = { f = 'a_c_sheep_01', m = 'a_c_sheep_01' },  -- ram variant check Phase 1
    sexLabels = { f = 'Ewe', m = 'Ram' },
    pen     = 'pasture',
    -- ⚠ NO WORLD_ANIMAL_SHEEP_* scenario exists in the dumps (searched
    -- 2026-08-13). Sheep walk to the trough and stand rather than graze.
    -- Auditioning the goat scenarios on a sheep ped is a /sr_anim job —
    -- species scenarios usually validate the model, so expect refusal.
    scenarios = nil,
    price   = { buy = Config.dollars(30.00), delivery = 1.25 },
    needs   = { hungerPerHour = 8, thirstPerHour = 8 },
    growth  = { growMinutes = 1500, stages = { young = 0, prime = 500, adult = 1000, old = 1250 } },
    breeding = { gestationMinutes = 600, chance = 0.65, cooldownMinutes = 300 },
    produce = { item = 'wool', minutes = 240, femaleOnly = false,
                yield = { 2, 4 }, verb = 'Shear', sell = Config.dollars(0.90) },
    butcher = {
      { item = 'Mutton',  min = 2, max = 5 },   -- capital M in the county catalogue
      { item = 'wool',    min = 1, max = 3 },
      { item = 'rams',    min = 1, max = 1 },   -- Ram Pelt is the only sheep pelt stocked
      { item = 'ramhorn', min = 1, max = 2 },
    },
  },
  goat = {
    label   = 'Goats',
    models  = { f = 'a_c_goat_01', m = 'a_c_goat_01' },    -- buck variant check Phase 1
    sexLabels = { f = 'Doe', m = 'Buck' },
    pen     = 'stockPen',
    scenarios = {   -- the DOMESTIC variants exist precisely for farm goats
      any = { graze = 'WORLD_ANIMAL_GOAT_GRAZING_DOMESTIC',
              eat   = 'WORLD_ANIMAL_GOAT_GRAZING_DOMESTIC',
              drink = 'WORLD_ANIMAL_GOAT_DRINK_GROUND_DOMESTIC' },
    },
    price   = { buy = Config.dollars(20.00), delivery = 1.25 },
    needs   = { hungerPerHour = 9, thirstPerHour = 9 },
    growth  = { growMinutes = 1200, stages = { young = 0, prime = 400, adult = 800, old = 1000 } },
    breeding = { gestationMinutes = 480, chance = 0.65, cooldownMinutes = 300 },
    -- The county stocks one `milk`, so goats fill the same pail. A separate
    -- goat's milk item would be a new item for no gameplay gain.
    produce = { item = 'milk', minutes = 120, femaleOnly = true,
                yield = { 1, 2 }, verb = 'Milk', sell = Config.dollars(1.40) },
    butcher = {
      { item = 'Mutton', min = 2, max = 4 },
      { item = 'goats',  min = 1, max = 1 },
      { item = 'Fat',    min = 1, max = 1 },
    },
  },
  chicken = {
    label   = 'Chickens',
    models  = { f = 'a_c_chicken_01', m = 'a_c_rooster_01' }, -- verify Phase 1
    sexLabels = { f = 'Chicken', m = 'Rooster' },
    pen     = 'chickenPen',
    penAlt  = 'coop',   -- unmapped chickenPen: the coop will do
    scattered = true,   -- fed by scattering on the ground, never a trough
    scenarios = {
      f = { graze = 'WORLD_ANIMAL_CHICKEN_EATING',
            eat   = 'WORLD_ANIMAL_CHICKEN_EATING',
            drink = 'WORLD_ANIMAL_CHICKEN_EATING' },
      m = { graze = 'WORLD_ANIMAL_ROOSTER_EATING',
            eat   = 'WORLD_ANIMAL_ROOSTER_EATING',
            drink = 'WORLD_ANIMAL_ROOSTER_EATING' },
    },
    price   = { buy = Config.dollars(3.00), delivery = 1.25 },
    needs   = { hungerPerHour = 6, thirstPerHour = 6 },
    growth  = { growMinutes = 600, stages = { young = 0, prime = 200, adult = 400, old = 500 } },
    breeding = { gestationMinutes = 240, chance = 0.8, cooldownMinutes = 120 },
    -- `autoStore`: hens lay whether anyone is there or not, so eggs go
    -- STRAIGHT into the coop basket (Config.Stores.coop, egg-only) and a
    -- hand collects them from there [Wilbur ruling 2026-08-14]. No tend
    -- menu entry — you do not squeeze a chicken. Everything else still
    -- needs a pair of hands.
    produce = { item = 'eggs', minutes = 60, femaleOnly = true,
                autoStore = 'coop',
                yield = { 1, 3 }, verb = 'Gather Eggs', sell = Config.dollars(0.35) },
    butcher = {
      { item = 'bird', min = 1, max = 2 },      -- Bird Meat
      { bySex = { f = 'chickenf', m = 'cockf' }, min = 1, max = 3 },
    },
    -- Birds are also sold live at the ranch, not driven to market.
    sellLive = Config.dollars(4.50),
  },
}
