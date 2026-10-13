local Grid = require("src.sim.grid")
local buildingData = require("src.data.buildings")
local Particles = require("src.fx.particles")
local Camera = require("src.core.camera")
local Stats = require("src.sim.stats")

local Walls = { n = 0, gx = {}, gy = {}, hp = {}, maxHp = {}, flash = {} }

local index = {}
local onRebuild = nil

function Walls.setRebuildHook(fn) onRebuild = fn end

local function changed()
  if onRebuild then onRebuild() end
end

function Walls.clear()
  for i = 1, Walls.n do
    local c = Grid.cellIndex(Walls.gx[i], Walls.gy[i])
    index[c] = nil
    Grid.occupancy[c] = Grid.OCC_NONE
  end
  Walls.n = 0
end

function Walls.at(gx, gy)
  return index[Grid.cellIndex(gx, gy)] or 0
end

function Walls.canPlace(gx, gy)
  if gx < Grid.EDGE_MARGIN or gy < Grid.EDGE_MARGIN then return false end
  if gx >= Grid.WIDTH - Grid.EDGE_MARGIN or gy >= Grid.HEIGHT - Grid.EDGE_MARGIN then return false end
  return Grid.occAtTile(gx, gy) == Grid.OCC_NONE
end

function Walls.place(gx, gy)
  local d = buildingData.wall
  Walls.n = Walls.n + 1
  local i = Walls.n
  Walls.gx[i] = gx
  Walls.gy[i] = gy
  local hp = d.hp * Stats.value("wallHp")
  Walls.hp[i] = hp
  Walls.maxHp[i] = hp
  Walls.flash[i] = 0
  local c = Grid.cellIndex(gx, gy)
  index[c] = i
  Grid.occupancy[c] = Grid.OCC_WALL
  changed()
  return i
end

function Walls.remove(i)
  local n = Walls.n
  local cRemoved = Grid.cellIndex(Walls.gx[i], Walls.gy[i])
  local wx, wy = Grid.tileToWorld(Walls.gx[i], Walls.gy[i])
  Particles.dust(wx, wy, 8)
  Camera.shake(2, 0.2)
  index[cRemoved] = nil
  Grid.occupancy[cRemoved] = Grid.OCC_NONE
  if i ~= n then
    Walls.gx[i] = Walls.gx[n]
    Walls.gy[i] = Walls.gy[n]
    Walls.hp[i] = Walls.hp[n]
    Walls.maxHp[i] = Walls.maxHp[n]
    Walls.flash[i] = Walls.flash[n]
    index[Grid.cellIndex(Walls.gx[i], Walls.gy[i])] = i
  end
  Walls.n = n - 1
  changed()
end

function Walls.damage(i, amount)
  Walls.hp[i] = Walls.hp[i] - amount
  Walls.flash[i] = 0.1
  if Walls.hp[i] <= 0 then Walls.remove(i) end
end

function Walls.load(list)
  Walls.clear()
  for i = 1, #list do
    local w = list[i]
    Walls.gx[i] = w.gx
    Walls.gy[i] = w.gy
    Walls.hp[i] = w.hp
    Walls.maxHp[i] = w.maxHp
    Walls.flash[i] = 0
    local c = Grid.cellIndex(w.gx, w.gy)
    index[c] = i
    Grid.occupancy[c] = Grid.OCC_WALL
  end
  Walls.n = #list
  changed()
end

function Walls.update(dt)
  for i = 1, Walls.n do
    if Walls.flash[i] > 0 then Walls.flash[i] = Walls.flash[i] - dt end
  end
end

return Walls
