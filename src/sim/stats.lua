-- Global stat modifier channels. Research, age bonuses, and any future
-- content feed additive bonuses here; sim code reads Stats.value(channel) so
-- adding a new upgrade on an existing channel is pure data.
local Stats = {}

local add = {} -- channel -> accumulated additive bonus (0.15 = +15%)

function Stats.reset()
  add = {}
end

function Stats.apply(effect)
  if not effect then return end
  for channel, amount in pairs(effect) do
    add[channel] = (add[channel] or 0) + amount
  end
end

function Stats.bonus(channel)
  return add[channel] or 0
end

-- Multiplier for a channel (1.0 = unchanged).
function Stats.value(channel)
  return 1 + (add[channel] or 0)
end

return Stats
