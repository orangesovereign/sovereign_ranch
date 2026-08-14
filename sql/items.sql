-- =====================================================================
-- SOVEREIGN RANCH · ITEMS SEED (Phase 1)
-- ---------------------------------------------------------------------
-- Creates the items this resource introduces, in vorp_inventory's `items`
-- table. Import into the SAME database vorp_inventory uses — NOT run by
-- the resource's schema loader (the crafting/medical precedent: a ranch
-- script has no business writing the inventory catalogue on every boot).
--
-- Idempotent: re-running updates label/description in place, keyed on the
-- item name's unique index.
--
-- Neither item is `usable` — both are consumed THROUGH ranch prompts
-- (server-side subItem on treat/feed), not by clicking them in the bag.
--
-- ⚠ vorp_inventory reads item definitions once, at start: new items appear
--   after the next server restart.
-- IMAGES: drop matching PNGs into vorp_inventory/html/img/items or the
-- slot renders blank: ranch_medicine.png, ranch_feed.png.
-- =====================================================================

INSERT INTO `items`
    (`item`, `label`, `limit`, `type`, `usable`, `can_remove`, `desc`, `weight`, `groupId`, `rarityId`, `metadata`)
VALUES
    ('ranch_medicine', 'Livestock Medicine', 10, 'item_standard', 0, 1,
     'A stoppered bottle of veterinary tonic. Administered to a sick animal at the ranch, it clears most ailments before they turn.',
     0.30, 1, 1, '{}'),

    ('ranch_feed', 'Feed Bag', 20, 'item_standard', 0, 1,
     'A coarse sack of mixed grain and hay. Keeps a working animal fed when the pasture is thin.',
     0.50, 1, 1, '{}'),

    -- Phase 2 produce. Ingredients for sovereign_crafting as much as goods
    -- for the buyer, so all are freely tradeable between players.
    ('ranch_milk', 'Milk', 20, 'item_standard', 0, 1,
     'A pail of fresh milk, still warm from the cow.', 0.60, 1, 1, '{}'),
    ('ranch_goat_milk', 'Goat''s Milk', 20, 'item_standard', 0, 1,
     'Richer and sharper than cow''s milk. The cheesemakers pay well for it.', 0.55, 1, 1, '{}'),
    ('ranch_egg', 'Eggs', 40, 'item_standard', 0, 1,
     'Gathered this morning, straw still stuck to the shells.', 0.10, 1, 1, '{}'),
    ('ranch_wool', 'Wool', 30, 'item_standard', 0, 1,
     'A greasy bundle of fleece, fresh off the shears.', 0.40, 1, 1, '{}'),
    ('ranch_manure', 'Manure', 30, 'item_standard', 0, 1,
     'Well-rotted muck. Unpleasant company, but there is no better fertiliser.', 0.70, 1, 1, '{}'),

    -- Butcher outputs.
    ('ranch_beef', 'Beef', 30, 'item_standard', 0, 1,
     'Heavy cuts of beef, trimmed and ready for the smokehouse.', 0.80, 1, 1, '{}'),
    ('ranch_pork', 'Pork', 30, 'item_standard', 0, 1,
     'Fresh pork. Salt it, smoke it, or sell it before it turns.', 0.75, 1, 1, '{}'),
    ('ranch_mutton', 'Mutton', 30, 'item_standard', 0, 1,
     'Strong-flavoured meat off a sheep or goat.', 0.70, 1, 1, '{}'),
    ('ranch_poultry', 'Poultry', 30, 'item_standard', 0, 1,
     'A plucked and dressed bird.', 0.35, 1, 1, '{}'),
    ('ranch_hide', 'Hide', 20, 'item_standard', 0, 1,
     'A raw hide, salted against the rot. The tanners will want it.', 1.20, 1, 1, '{}'),
    ('ranch_tallow', 'Tallow', 20, 'item_standard', 0, 1,
     'Rendered fat, set hard in a crock. Candles, soap and grease.', 0.50, 1, 1, '{}'),
    ('ranch_feathers', 'Feathers', 40, 'item_standard', 0, 1,
     'A bundle of feathers, good for bedding and fletching.', 0.05, 1, 1, '{}')

ON DUPLICATE KEY UPDATE
    `label`      = VALUES(`label`),
    `limit`      = VALUES(`limit`),
    `type`       = VALUES(`type`),
    `usable`     = VALUES(`usable`),
    `can_remove` = VALUES(`can_remove`),
    `desc`       = VALUES(`desc`),
    `weight`     = VALUES(`weight`),
    `groupId`    = VALUES(`groupId`),
    `rarityId`   = VALUES(`rarityId`);
