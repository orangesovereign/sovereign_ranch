-- =====================================================================
-- SOVEREIGN RANCH · REMOVE THE ITEMS THIS RESOURCE USED TO CREATE
-- ---------------------------------------------------------------------
-- Run this ONLY if you imported an older sql/items.sql before the
-- 2026-08-14 ruling ("the ranch invents no items"). It removes the 14
-- `ranch_*` definitions and any instances players are holding.
--
-- If you never imported that file, running this is harmless: it will
-- simply match nothing.
--
-- ⚠ vorp_inventory-v2 spreads items over THREE tables, and they must go
--   in dependency order or you strand rows that point at nothing:
--     character_inventories  → who is holding which instance
--     items_crafted          → the instances themselves
--     items                  → the definitions
--   A bare `DELETE FROM items` leaves the first two behind, and those
--   orphans surface later as blank or erroring satchel slots.
--
-- ⚠ Nothing else in the county is touched: every statement is scoped to
--   the explicit `ranch_*` list below. The ranch now uses existing county
--   items (milk, eggs, wool, fertilizer, beef, pork, Mutton, bird, the
--   pelts and horns, Fat/porkfat, consumable_haycube,
--   consumable_medicine) and those must NOT be removed.
--
-- Back up first if you like — this is a delete, and it is not reversible.
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP 1 — PREVIEW. Run this alone first and read the result. If it
-- returns 0 rows, the old items were never imported and you are done.
-- ---------------------------------------------------------------------
SELECT i.id, i.item, i.label,
       (SELECT COUNT(*) FROM items_crafted ic WHERE ic.item_id = i.id) AS instances
FROM items i
WHERE i.item IN (
    'ranch_medicine', 'ranch_feed',
    'ranch_milk', 'ranch_goat_milk', 'ranch_egg', 'ranch_wool', 'ranch_manure',
    'ranch_beef', 'ranch_pork', 'ranch_mutton', 'ranch_poultry',
    'ranch_hide', 'ranch_tallow', 'ranch_feathers'
);

-- ---------------------------------------------------------------------
-- STEP 2 — DELETE, in dependency order. Run the three statements
-- together (or top to bottom); do not reorder them.
-- ---------------------------------------------------------------------

-- 2a. Unlink any instances players are carrying.
DELETE ci FROM character_inventories ci
JOIN items_crafted ic ON ic.id = ci.item_crafted_id
JOIN items i ON i.id = ic.item_id
WHERE i.item IN (
    'ranch_medicine', 'ranch_feed',
    'ranch_milk', 'ranch_goat_milk', 'ranch_egg', 'ranch_wool', 'ranch_manure',
    'ranch_beef', 'ranch_pork', 'ranch_mutton', 'ranch_poultry',
    'ranch_hide', 'ranch_tallow', 'ranch_feathers'
);

-- 2b. Remove the instances themselves. Matched on BOTH the foreign key
--     and the denormalised name, because items_crafted stores each and a
--     partial import can leave one of them dangling.
DELETE ic FROM items_crafted ic
LEFT JOIN items i ON i.id = ic.item_id
WHERE i.item IN (
    'ranch_medicine', 'ranch_feed',
    'ranch_milk', 'ranch_goat_milk', 'ranch_egg', 'ranch_wool', 'ranch_manure',
    'ranch_beef', 'ranch_pork', 'ranch_mutton', 'ranch_poultry',
    'ranch_hide', 'ranch_tallow', 'ranch_feathers'
)
   OR ic.item_name IN (
    'ranch_medicine', 'ranch_feed',
    'ranch_milk', 'ranch_goat_milk', 'ranch_egg', 'ranch_wool', 'ranch_manure',
    'ranch_beef', 'ranch_pork', 'ranch_mutton', 'ranch_poultry',
    'ranch_hide', 'ranch_tallow', 'ranch_feathers'
);

-- 2c. Finally the definitions.
DELETE FROM items
WHERE item IN (
    'ranch_medicine', 'ranch_feed',
    'ranch_milk', 'ranch_goat_milk', 'ranch_egg', 'ranch_wool', 'ranch_manure',
    'ranch_beef', 'ranch_pork', 'ranch_mutton', 'ranch_poultry',
    'ranch_hide', 'ranch_tallow', 'ranch_feathers'
);

-- ---------------------------------------------------------------------
-- STEP 3 — VERIFY. Should return 0 rows.
-- ---------------------------------------------------------------------
SELECT item FROM items WHERE item LIKE 'ranch\_%';

-- Restart the server afterwards: vorp_inventory reads item definitions
-- once at start, so a removed item lingers in memory until it does.
