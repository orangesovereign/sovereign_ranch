--[[
  config/ranches.lua — per-ranch mapped points (owner decision 2026-08-13:
  the map belongs to the PROPERTY, not the owner — coords live in config so
  they survive every sale, keyed by the realestate ident).

  Survey with /sr_here (Config.Debug) standing at each spot; paste the
  printed line. EVERY point is OPTIONAL — an unmapped ranch keeps the
  fallback behaviour (release beside the releasing member, wander where
  spawned), so mapping is incremental and nothing breaks while it's empty.

  Points and who reads them:
    barn        release/pen anchor for cattle, pigs, sheep, goats (Phase 1);
                the Phase 2 butcher/product stations hang off it
    chickenPen  release anchor for chickens/roosters (ground-level pen —
                preferred over the coop structure for spawning)
    coop        Phase 2 egg-collection point; chicken release FALLBACK when
                no chickenPen is mapped
    pasture     reserved: settle/wander centre for Phase 4 herding + strays
  Phase 2 will add (same table, same survey lever): butcher, manure,
  buyerPed. Phase 5 adds: duty (the clock-in point).

  Anchors are ANCHORS, not requirements — care verbs are never gated on
  standing at a mapped point.
]]

Config.Ranches = {
  -- Beecher's Hope (surveyed by Wilbur 2026-08-13).
  -- ⚠ KEY = the realestate IDENT for this property — if /ranchadmin points
  -- says "no mapped points" against the real ident, rename this key to
  -- match what /ranchadmin list prints.
  ['beechers_hope'] = {
    barn       = { x = -1600.758, y = -1412.767, z = 81.93 },   -- inside the barn
    pasture    = { x = -1500.936, y = -1422.768, z = 81.449 },  -- pen centre
    chickenPen = { x = -1584.877, y = -1398.599, z = 81.263 },
    coop       = { x = -1582.946, y = -1393.685, z = 82.001 },
  },
}
