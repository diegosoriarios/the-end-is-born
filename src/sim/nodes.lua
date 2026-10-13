local nodeData = require("src.data.nodes")
local Grid = require("src.sim.grid")

local Nodes = { list = {} }

function Nodes.clear()
  Nodes.list = {}
end

function Nodes.generate(village)
  Nodes.clear()
  for kind, d in pairs(nodeData) do
    for _ = 1, d.count do
      local x, y
      for _ = 1, 20 do
        x = love.math.random(60, Grid.pixelWidth() - 60)
        y = love.math.random(60, Grid.pixelHeight() - 60)
        local dx, dy = x - village.x, y - village.y
        if dx * dx + dy * dy > 300 * 300 then break end
      end
      Nodes.list[#Nodes.list + 1] = {
        kind = kind,
        res = d.res,
        x = x,
        y = y,
        amount = d.amount,
        max = d.amount,
        regen = d.regen,
        r = d.r,
      }
    end
  end
end

-- Runtime-added node (e.g. a built Farm). Returns the new node.
function Nodes.add(spec, x, y)
  local nd = {
    kind = spec.kind or "farm",
    res = spec.res,
    x = x, y = y,
    amount = spec.amount,
    max = spec.amount,
    regen = spec.regen or 0,
    r = spec.r or 8,
  }
  Nodes.list[#Nodes.list + 1] = nd
  return nd
end

function Nodes.atWorld(x, y)
  local list = Nodes.list
  for i = 1, #list do
    local nd = list[i]
    if nd.x == x and nd.y == y then return nd end
  end
  return nil
end

function Nodes.removeAt(x, y)
  local list = Nodes.list
  for i = #list, 1, -1 do
    local nd = list[i]
    if nd.x == x and nd.y == y then
      table.remove(list, i)
      return true
    end
  end
  return false
end

function Nodes.nearest(x, y, res)
  local best, bd = nil, math.huge
  local list = Nodes.list
  for i = 1, #list do
    local nd = list[i]
    if nd.res == res and nd.amount > 0 then
      local dx, dy = nd.x - x, nd.y - y
      local d2 = dx * dx + dy * dy
      if d2 < bd then
        bd = d2
        best = nd
      end
    end
  end
  return best
end

function Nodes.update(dt)
  local list = Nodes.list
  for i = 1, #list do
    local nd = list[i]
    if nd.regen > 0 and nd.amount < nd.max then
      nd.amount = math.min(nd.max, nd.amount + nd.regen * dt)
    end
  end
end

return Nodes
