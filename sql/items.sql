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
     0.50, 1, 1, '{}')

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
