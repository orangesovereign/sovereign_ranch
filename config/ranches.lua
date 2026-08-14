--[[
  config/ranches.lua — per-ranch mapped points (owner decision 2026-08-13:
  the map belongs to the PROPERTY, not the owner — coords live in config so
  they survive every sale, keyed by the realestate ident).

  Survey with /sr_here (Config.Debug) standing at each spot; paste the
  printed line. EVERY point is OPTIONAL — an unmapped ranch keeps the
  fallback behaviour (release beside the releasing member, wander where
  spawned), so mapping is incremental and nothing breaks while it's empty.

  ⚠ TWO KINDS OF POINT — do not mix them up (live finding 2026-08-13:
  animals released at an INTERIOR barn point walked into walls forever,
  because a building has no route out and the game's navmesh cannot help
  them). "Where an animal is KEPT" and "where an animal is LET OUT" are
  different places: a penned animal is despawned and has no location at
  all, so the barn interior is useless as a spawn point.

    OPEN-GROUND points — animals SPAWN and ROAM here. Survey these in
    the open, on walkable ground, clear of eaves, fences and props:
      pasture     release + roam anchor for cattle, pigs, sheep, goats
      chickenPen  release + roam anchor for chickens/roosters

    ⚠ GIVE EVERY OPEN-GROUND POINT A `radius` — this is the PEN ZONE, and
    it is what stops animals walking into fences (live finding
    2026-08-13: chickens ground themselves against the coop fence
    forever). Animals only ever pick roam destinations INSIDE this
    circle, and one that strays outside is walked back. Survey it by
    standing at the anchor and pacing to the nearest fence: use a hair
    LESS than that distance, so the far side of the animal clears the
    rail. A small coop yard is 4–6 m; an open pasture 20–40 m.
    Omitted → Config.Wander.radius (8 m), which is a guess and will be
    wrong for a small pen.

    STRUCTURE points — interaction anchors only, never spawn points
    (Phase 2 hangs the butcher/product/egg stations off these):
      barn        the barn building
      coop        the coop building

  Release falls back structure-ward only if no open-ground point is
  mapped (pasture → barn, chickenPen → coop → pasture), and the client
  still ground-snaps and safe-coords whatever it is given.
    pasture     reserved: the ON-PROPERTY settle/wander centre — where
                animals idle when all is well, and the HOME anchor a
                wrangled stray is led back to. NOT where strays drift:
                straying (Phase 4) computes its drift points OUTSIDE the
                realestate land polygon at runtime (config distance band) —
                loose animals leave the property lines by design.
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
    barn       = { x = -1596.40, y = -1415.10, z = 81.90, h = 252.28 },   -- structure: Phase 2 stations
    coop       = { x = -1584.94, y = -1392.92, z = 82.00, h = 62.36 },    -- structure: Phase 2 egg point
    -- Open ground. ⚠ radius values are ESTIMATES — pace the real fences
    -- and correct them; too large is what puts a bird in the rails.
    pasture    = { x = -1500.936, y = -1422.768, z = 81.449, radius = 25.0 },
    chickenPen = { x = -1583.32, y = -1397.58, z = 81.80, h = 164.40, radius = 5.0 },
  },
}
