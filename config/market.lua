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
}
