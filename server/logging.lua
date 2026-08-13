--[[
  server/logging.lua — leveled console logging + batched Discord audit
  mirroring. Mirrors the sovereign_realestate / sovereign_banking logger so
  the suite reads and operates the same way.

  Discord posts are BATCHED per category and flushed on a timer as one embed
  list, so a busy market day can't trip Discord's rate limiter. A failed
  webhook never affects the operation that produced it — logging is strictly
  downstream of the state change.

  Two destinations: the staff webhooks in Config.Discord.webhooks (by
  category), and an optional per-ranch channel (boss-set webhook_url on the
  ranch row) via Log.ranchDiscord.
]]

Log = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local COLORS = { debug = '^6', info = '^2', warn = '^3', error = '^1' }

local function write(level, fmt, ...)
  local threshold = LEVELS[Config.LogLevel or 'info'] or 2
  if LEVELS[level] < threshold then return end
  local ok, msg = pcall(string.format, fmt, ...)
  print(('%s[sovereign_ranch:%s]^7 %s'):format(
    COLORS[level], level, ok and msg or tostring(fmt)))
end

function Log.debug(fmt, ...) write('debug', fmt, ...) end
function Log.info(fmt, ...)  write('info', fmt, ...) end
function Log.warn(fmt, ...)  write('warn', fmt, ...) end
function Log.error(fmt, ...) write('error', fmt, ...) end

-- ============================================================================
-- Discord — staff channels (Config.Discord.webhooks by category)
-- ============================================================================

local queues = {}   -- webhook URL -> { embed, ... } (keyed by URL so the
                    -- per-ranch channels share the same flush machinery)

-- Category → embed accent (suite leather/brass palette; purely cosmetic).
local COLOR = {
  lifecycle = 8421504, crew = 15844367, market = 10038562,
  animals = 5763719, payroll = 15105570, admin = 8421504,
}

local function enqueue(hook, embed)
  if not hook or hook == '' then return end
  local q = queues[hook]
  if not q then q = {}; queues[hook] = q end
  if #q >= 50 then return end -- backpressure: drop rather than balloon
  q[#q + 1] = embed
end

local function embed(category, title, description, fields)
  return {
    title = tostring(title),
    description = description and tostring(description) or nil,
    color = COLOR[category] or 8421504,
    fields = fields,
    footer = { text = ('Sovereign County · %s'):format(os.date('%Y-%m-%d %H:%M:%S')) },
  }
end

--- Queue an audit entry for the staff channel of `category`.
--- fields = { {name=, value=, inline=}, ... }. Never throws, never blocks.
function Log.discord(category, title, description, fields)
  if not (Config.Discord and Config.Discord.enabled) then return end
  enqueue((Config.Discord.webhooks or {})[category], embed(category, title, description, fields))
end

--- Queue the same entry for a RANCH's own channel (boss-set webhook_url).
--- Callers usually pair this with Log.discord so staff see everything.
function Log.ranchDiscord(ranch, category, title, description, fields)
  if not (Config.Discord and Config.Discord.enabled) then return end
  if not ranch or not ranch.webhook_url or ranch.webhook_url == '' then return end
  enqueue(ranch.webhook_url, embed(category, title, description, fields))
end

local function flush(hook)
  local q = queues[hook]
  if not q or #q == 0 then queues[hook] = nil; return end

  local batch = {}
  for _ = 1, math.min(10, #q) do -- Discord accepts at most 10 embeds/message
    batch[#batch + 1] = table.remove(q, 1)
  end

  pcall(function()
    PerformHttpRequest(hook, function(status)
      if status ~= 200 and status ~= 204 then
        Log.warn('discord webhook returned %s', tostring(status))
      end
    end, 'POST', json.encode({ username = 'Sovereign Ranch', embeds = batch }),
      { ['Content-Type'] = 'application/json' })
  end)
end

CreateThread(function()
  while true do
    Wait(math.max(2, tonumber(Config.Discord and Config.Discord.flushSeconds) or 10) * 1000)
    if Config.Discord and Config.Discord.enabled then
      for hook in pairs(queues) do pcall(flush, hook) end
    end
  end
end)
