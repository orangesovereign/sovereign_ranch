--[[
  server/selling.lua — turning goods into money (design §8.3, Phase 2 slice).

  Two counters:
    PRODUCE, on the ranch itself — eggs, milk, wool, manure and live
      chickens, at the per-species `sell` prices.
    EXPORT, in town — butchered meat in bulk at a premium rate.

  Both credit the RANCH BUSINESS ACCOUNT, never a wallet: the ranch earns,
  and the boss draws wages and withdrawals from the ledger (design §1.3).
  Prices are read from config server-side; a client never names a price,
  only what it wants to sell.
]]

Selling = {}

local Err = Enums.Err

--- What the on-ranch produce buyer will take, and for how much each.
--- Built from the species catalogue so a new species needs no code.
local function producePrices()
  local prices = {}
  for _, spec in pairs(Config.Animals) do
    local p = spec.produce
    if p and p.item and p.sell then prices[p.item] = p.sell end
  end
  local m = Config.Production.manure
  if m and m.enabled and m.sell then prices[m.item] = m.sell end
  return prices
end

--- What the exporter will take, at its premium.
local function exportPrices()
  local cfg = Config.Market.export or {}
  local rate = cfg.rate or 1.0
  local prices = {}
  for _, item in ipairs(cfg.items or {}) do
    local base = Config.MeatPrices[item]
    if base then prices[item] = math.floor(base * rate + 0.5) end
  end
  return prices
end

Selling.producePrices = producePrices
Selling.exportPrices  = exportPrices

--- Sell everything the player carries that this counter buys.
--- kind is 'produce' or 'export'. Returns (ok, { lines, total }) or (false, err).
function Selling.sellAll(src, kind)
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local m = Members.get(charid)
  if not m then return false, Err.NOT_MEMBER end
  -- Selling the ranch's goods is ordinary hand's work; the money lands in
  -- the ranch account either way, so grade 0 may run produce to market.
  local ok, err = Members.can(charid, 'care', m.ranch_id)
  if not ok then return false, err end
  local ranch = Ranches.get(m.ranch_id)
  if not ranch or not ranch.biz_key then return false, Err.NO_RANCH end

  local prices = (kind == 'export') and exportPrices() or producePrices()
  local lines, total = {}, 0

  for item, unit in pairs(prices) do
    local held = Bridge.GetItemCount(src, item)
    if held and held > 0 then
      if Bridge.SubItem(src, item, held) then
        local cents = unit * held
        total = total + cents
        lines[#lines + 1] = { item = item, count = held, cents = cents }
      end
    end
  end

  if total <= 0 then return false, Err.BAD_ARG end

  local reason = (kind == 'export') and Enums.Reason.EXPORT or Enums.Reason.GOODS_SALE
  local idem = ('ranch:sell:%s:%d:%d:%d'):format(kind, ranch.id, charid, os.time())
  local paid, perr = Bank.credit(ranch.biz_key, total, reason, idem, ranch.ident)
  if not paid then
    -- The goods are already gone from the satchel; hand them back rather
    -- than eat a player's stock over a bank hiccup.
    for _, line in ipairs(lines) do
      Bridge.AddItem(src, line.item, line.count)
    end
    Log.error('sell %s at %s failed to credit (%s) - goods returned',
      kind, ranch.ident, tostring(perr))
    return false, perr
  end

  Log.discord('market', kind == 'export' and 'Export sale' or 'Produce sale',
    ('**%s** - %s by %s'):format(ranch.ident, FmtMoney(total),
      Bridge.GetCharName(charid)))
  return true, { lines = lines, total = total }
end

--- Sell live birds off the ranch (the chicken counter). count is capped by
--- what the ranch actually holds. Returns (ok, { count, total }).
function Selling.sellLiveBirds(src, count)
  local charid = Bridge.GetCharId(src)
  if not charid then return false, Err.NOT_MEMBER end
  local m = Members.get(charid)
  if not m then return false, Err.NOT_MEMBER end
  local ok, err = Members.can(charid, 'care', m.ranch_id)
  if not ok then return false, err end
  local ranch = Ranches.get(m.ranch_id)
  if not ranch or not ranch.biz_key then return false, Err.NO_RANCH end

  local unit = (Config.Animals.chicken or {}).sellLive
  if not unit then return false, Err.BAD_ARG end
  count = math.max(1, math.floor(tonumber(count) or 1))

  -- Take the oldest birds first; a ranch sells its spent layers.
  local birds = {}
  for _, a in ipairs(Animals.herdOf(m.ranch_id)) do
    if a.species == 'chicken' then birds[#birds + 1] = a end
  end
  if #birds == 0 then return false, Err.NO_ANIMAL end
  if count > #birds then count = #birds end

  local total = unit * count
  local idem = ('ranch:birds:%d:%d:%d'):format(ranch.id, charid, os.time())
  local paid, perr = Bank.credit(ranch.biz_key, total,
    Enums.Reason.LIVESTOCK_SALE, idem, ranch.ident)
  if not paid then return false, perr end

  for i = 1, count do
    local a = birds[i]
    Events.animalSold({ ident = ranch.ident, animalId = a.id,
                        species = a.species, cents = unit })
    Animals.slaughter(a, charid)   -- off the books, off the property
  end

  Log.discord('market', 'Birds sold', ('**%s** - %d head, %s'):format(
    ranch.ident, count, FmtMoney(total)))
  return true, { count = count, total = total }
end
