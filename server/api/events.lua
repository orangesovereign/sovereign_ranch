--[[
  server/api/events.lua — the outbound event surface (design §10).

  Other resources learn what the ranch did by listening to
  `sovereign_ranch:server:<verb>`. Emitters only: this file never mutates
  anything, and there are deliberately NO inbound net events here — the
  suite-wide rule: authority paths use AddEventHandler server-side only, so
  a client can never fire one.

  Payloads are flat tables of primitives. Listeners must treat every field
  as optional: a payload gains fields over time, never loses them.
]]

Events = {}

local function emit(name, payload)
  TriggerEvent('sovereign_ranch:server:' .. name, payload)
end

-- Lifecycle (Phase 0)
function Events.ranchActivated(payload)   emit('ranchActivated', payload) end
function Events.ranchTorndown(payload)    emit('ranchTorndown', payload) end

-- Crew (Phase 0 seats/releases; full flows Phase 5)
function Events.handHired(payload)        emit('handHired', payload) end
function Events.handFired(payload)        emit('handFired', payload) end
function Events.handPromoted(payload)     emit('handPromoted', payload) end

-- Herd (Phase 1+)
function Events.animalBought(payload)     emit('animalBought', payload) end
function Events.animalSold(payload)       emit('animalSold', payload) end
function Events.animalDied(payload)       emit('animalDied', payload) end
function Events.animalBorn(payload)       emit('animalBorn', payload) end
function Events.productCollected(payload) emit('productCollected', payload) end

-- Strays & drives (Phase 4)
function Events.strayEscaped(payload)     emit('strayEscaped', payload) end
function Events.strayRecovered(payload)   emit('strayRecovered', payload) end
function Events.driveStarted(payload)     emit('driveStarted', payload) end
function Events.driveCompleted(payload)   emit('driveCompleted', payload) end

-- Payroll (Phase 5)
function Events.payrollRun(payload)       emit('payrollRun', payload) end
