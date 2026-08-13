--[[
  config/ranches.lua — per-ranch mapped points (owner decision 2026-08-13:
  the map belongs to the PROPERTY, not the owner — coords live in config so
  they survive every sale, keyed by the realestate ident).

  Survey with /sr_here (Config.Debug) standing at each spot; paste the
  printed line. EVERY point is OPTIONAL — an unmapped ranch keeps the
  fallback behaviour (release beside the releasing member, wander where
  spawned), so mapping is incremental and nothing breaks while it's empty.

  Points and who reads them:
    barn     release/pen anchor for cattle, pigs, sheep, goats (Phase 1);
             the Phase 2 butcher/product stations hang off it
    coop     release anchor for chickens/roosters (Phase 1); Phase 2 egg
             collection point
    pasture  reserved: settle/wander centre for Phase 4 herding + strays
  Phase 2 will add (same table, same survey lever): butcher, manure,
  buyerPed. Phase 5 adds: duty (the clock-in point).

  Anchors are ANCHORS, not requirements — care verbs are never gated on
  standing at a mapped point.
]]

Config.Ranches = {
  -- ['bla_ranch_01'] = {
  --   barn    = { x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
  --   coop    = { x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
  --   pasture = { x = 0.0, y = 0.0, z = 0.0 },
  -- },
}
