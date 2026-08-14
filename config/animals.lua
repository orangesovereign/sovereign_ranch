--[[
  config/animals.lua — the species catalogue. Adding a species is config
  only (design §1.11): a new entry here plus items in the inventory table is
  the whole job.

  Phase 0 ships the five locked species (design brief §1.4) with their
  gendered model names DRAFTED. ⚠️ Every model string is verified against
  rdr3_discoveries in Phase 1 before the first spawn — the lib rule. Needs,
  growth, products and yields are Phase 1–3 numbers; they live here from day
  one so the shape is settled, but nothing reads them until those phases.
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
    produce = { item = 'ranch_milk', minutes = 90, femaleOnly = true },
  },
  pig = {
    label   = 'Pigs',
    models  = { f = 'a_c_pig_01', m = 'a_c_pig_01' },      -- sex variant check Phase 1
    sexLabels = { f = 'Sow', m = 'Boar' },
    scenarios = {   -- no pig DRINK scenario exists in the dumps; grazing reads fine
      any = { graze = 'WORLD_ANIMAL_PIG_GRAZING',
              eat   = 'WORLD_ANIMAL_PIG_GRAZING',
              drink = 'WORLD_ANIMAL_PIG_GRAZING' },
    },
    price   = { buy = Config.dollars(25.00), delivery = 1.25 },
    needs   = { hungerPerHour = 12, thirstPerHour = 10 },
    growth  = { growMinutes = 1200, stages = { young = 0, prime = 400, adult = 800, old = 1000 } },
    breeding = { gestationMinutes = 480, chance = 0.7, cooldownMinutes = 240 },
    produce = nil,                                         -- pigs are the pork value chain, not a product timer
  },
  sheep = {
    label   = 'Sheep',
    models  = { f = 'a_c_sheep_01', m = 'a_c_sheep_01' },  -- ram variant check Phase 1
    sexLabels = { f = 'Ewe', m = 'Ram' },
    -- ⚠ NO WORLD_ANIMAL_SHEEP_* scenario exists in the dumps (searched
    -- 2026-08-13). Sheep walk to the trough and stand rather than graze.
    -- Auditioning the goat scenarios on a sheep ped is a /sr_anim job —
    -- species scenarios usually validate the model, so expect refusal.
    scenarios = nil,
    price   = { buy = Config.dollars(30.00), delivery = 1.25 },
    needs   = { hungerPerHour = 8, thirstPerHour = 8 },
    growth  = { growMinutes = 1500, stages = { young = 0, prime = 500, adult = 1000, old = 1250 } },
    breeding = { gestationMinutes = 600, chance = 0.65, cooldownMinutes = 300 },
    produce = { item = 'ranch_wool', minutes = 240, femaleOnly = false },
  },
  goat = {
    label   = 'Goats',
    models  = { f = 'a_c_goat_01', m = 'a_c_goat_01' },    -- buck variant check Phase 1
    sexLabels = { f = 'Doe', m = 'Buck' },
    scenarios = {   -- the DOMESTIC variants exist precisely for farm goats
      any = { graze = 'WORLD_ANIMAL_GOAT_GRAZING_DOMESTIC',
              eat   = 'WORLD_ANIMAL_GOAT_GRAZING_DOMESTIC',
              drink = 'WORLD_ANIMAL_GOAT_DRINK_GROUND_DOMESTIC' },
    },
    price   = { buy = Config.dollars(20.00), delivery = 1.25 },
    needs   = { hungerPerHour = 9, thirstPerHour = 9 },
    growth  = { growMinutes = 1200, stages = { young = 0, prime = 400, adult = 800, old = 1000 } },
    breeding = { gestationMinutes = 480, chance = 0.65, cooldownMinutes = 300 },
    produce = { item = 'ranch_goat_milk', minutes = 120, femaleOnly = true },
  },
  chicken = {
    label   = 'Chickens',
    models  = { f = 'a_c_chicken_01', m = 'a_c_rooster_01' }, -- verify Phase 1
    sexLabels = { f = 'Chicken', m = 'Rooster' },
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
    produce = { item = 'ranch_egg', minutes = 60, femaleOnly = true },
  },
}
