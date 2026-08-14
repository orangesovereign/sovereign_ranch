--[[
  config/market.lua — the livestock dealer (Phase 1: buy only; sell runs and
  the stockyard buyer arrive Phase 4, export/chicken peds Phase 2).

  ⚠ SURVEY REQUIRED: the dealer coords below are a DRAFT near the Valentine
  auction yard. Stand at the real spot in-game and run /sr_here (Debug
  lever) to print exact coords, paste them here, then set surveyed = true.
  The dealer ped does not spawn while surveyed = false — a ped floating in
  a fence line would be worse than no ped.
]]

Config.Market = {
  dealer = {
    enabled  = true,
    surveyed = true,                     -- ⚠ flip true after /sr_here survey
    coords   = { x = -279.78, y = 689.40, z = 113.40, h = 294.80 },  -- DRAFT
    -- Valentine auction foreman — verified in rdr3_discoveries peds_list
    -- (0x075398B9, 7 outfit variations; dressed via the standing two-native
    -- rule like every ped we spawn).
    model    = 'u_m_m_valauctionforman_01',
    promptLabel = 'Speak with the Livestock Dealer',
  },

  -- Where bought animals materialise for the drive home: offset from the
  -- dealer, so the pen gate area stays clear. Surveyed alongside the dealer.
  spawnOffset = { x = 4.0, y = 0.0, z = 0.0 },

  MaxPerPurchase       = 5,     -- head per transaction (drive-home practicality)
  DeliveryDelayMinutes = 10,    -- delivered animals appear penned after this
  -- Delivery price premium is per-species: config/animals.lua price.delivery.

  -- ==========================================================================
  -- Phase 2 buyers. Same survey discipline as the dealer: nothing spawns
  -- while `surveyed = false`, so a ped is never left floating in scenery.
  -- Stand at the spot, /sr_here, paste, flip the flag, restart.
  -- ==========================================================================

  -- The produce buyer STANDS ON THE RANCH — this one is per-property, so
  -- its position comes from config/ranches.lua (`buyer` point), not here.
  -- Buys eggs, milk, wool, manure and live chickens at the per-species
  -- `sell` prices. Proceeds go to the ranch business account.
  produce = {
    enabled     = true,
    model       = 'u_m_m_valauctionforman_01',   -- placeholder; a farmhand suits better
    promptLabel = 'Sell Produce',
    point       = 'buyer',        -- mapped point name in config/ranches.lua
  },

  -- The EXPORT buyer takes meat in bulk at export rates — one fixed
  -- location for the county, hence coords here rather than per ranch.
  export = {
    enabled  = true,
    surveyed = false,             -- ⚠ survey before this ped appears
    coords   = { x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
    model    = 'u_m_m_valauctionforman_01',      -- placeholder
    promptLabel = 'Sell to the Exporter',
    -- Export pays a premium over the on-ranch buyer for meat only.
    rate     = 1.35,
    items    = { 'ranch_pork', 'ranch_beef', 'ranch_mutton', 'ranch_poultry' },
  },
}

-- Base prices the EXPORT buyer works from (per unit, before `rate`). The
-- on-ranch buyer pays the per-species `sell` values in config/animals.lua;
-- these cover butcher outputs, which no species "produces".
Config.MeatPrices = {
  ranch_pork     = Config.dollars(1.10),
  ranch_beef     = Config.dollars(1.30),
  ranch_mutton   = Config.dollars(1.00),
  ranch_poultry  = Config.dollars(0.70),
  ranch_hide     = Config.dollars(0.80),
  ranch_tallow   = Config.dollars(0.40),
  ranch_feathers = Config.dollars(0.20),
}
