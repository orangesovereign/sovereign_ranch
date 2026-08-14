-- sovereign_ranch — idempotent schema (design §3). Every statement is
-- CREATE TABLE IF NOT EXISTS; re-running on every boot is safe. Column
-- additions to live tables go through Db.runMigrations, never here.

-- One row per ranch-class property that has ranch state. `ident` is a
-- FK-by-convention to sovereign_realestate's property ident; realestate is
-- the truth for ownership — owner_* here are mirrors refreshed by events
-- and the reconcile pass.
CREATE TABLE IF NOT EXISTS `sovereign_ranch_ranches` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `ident`           VARCHAR(64)  NOT NULL,
  `owner_charid`    INT NULL,
  `owner_userid`    VARCHAR(64) NULL,
  `biz_key`         VARCHAR(64) NULL,
  `stray_mult`      FLOAT NOT NULL DEFAULT 1.0,
  `webhook_url`     VARCHAR(255) NULL,
  `settings`        JSON NULL,
  `created_at`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ident` (`ident`),
  KEY `idx_owner_user` (`owner_userid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Crew + duty + wage accrual. The boss is a member row at grade 4 so
-- "everyone at ranch X" is one SELECT. uq_member enforces one ranch per
-- character in any role; the 1-ranch-per-ACCOUNT ownership rule is enforced
-- at purchase time inside sovereign_realestate.
CREATE TABLE IF NOT EXISTS `sovereign_ranch_members` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `ranch_id`        INT UNSIGNED NOT NULL,
  `charid`          INT NOT NULL,
  `grade`           TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `wage_override`   INT UNSIGNED NULL,
  `on_duty`         TINYINT(1) NOT NULL DEFAULT 0,
  `accrued_minutes` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `unpaid_cents`    INT UNSIGNED NOT NULL DEFAULT 0,
  `hired_by`        INT NULL,
  `hired_at`        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_member` (`charid`),
  KEY `idx_ranch` (`ranch_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- The herd. sim_minutes is the clock: animals age/grow/gestate only while
-- simulated (a member on duty + animal spawned) — pause-when-offline
-- expressed in data. state='penned' rows are never read by the tick.
CREATE TABLE IF NOT EXISTS `sovereign_ranch_animals` (
  `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `ranch_id`        INT UNSIGNED NOT NULL,
  `species`         VARCHAR(16) NOT NULL,
  `sex`             ENUM('m','f') NOT NULL,
  `name`            VARCHAR(48) NULL,
  `born_at`         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `sim_minutes`     INT UNSIGNED NOT NULL DEFAULT 0,
  `scale`           DECIMAL(4,3) NOT NULL DEFAULT 0.500,
  -- The animal's LOOK, fixed for life. A stable number the client mods by
  -- the model's real preset count, so the same beast wears the same coat
  -- every time it is spawned instead of rerolling its breed.
  `variation`       SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `health`          TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `hunger`          TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `thirst`          TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `groom`           TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `sick_state`      ENUM('healthy','sick','critical') NOT NULL DEFAULT 'healthy',
  `pregnant_until`  INT UNSIGNED NULL,
  `product_progress` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `product_ready`   TINYINT(1) NOT NULL DEFAULT 0,
  `state`           ENUM('penned','spawned','straying','wrangling','transit','dead') NOT NULL DEFAULT 'penned',
  `pos`             JSON NULL,
  `meta`            JSON NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ranch` (`ranch_id`),
  KEY `idx_state` (`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
