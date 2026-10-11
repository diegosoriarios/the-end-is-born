local Grid = require("src.sim.grid")
local buildingData = require("src.data.buildings")

local Buildings = {
  n = 0,
  kind = {}, gx = {}, gy = {}, x = {}, y = {},
  hp = {}, maxHp = {}, progress = {}, built = {}, flash = {},
  crewCount = {}, maxCrew = {}, cd = {},
  isTower = {},
}

local index = {}
local onRebuild, onRemove = nil, nil

function Buildings.setRebuildHook(fn) onRebuild = fn end

function Buildings.setRemoveHook(fn) onRemove = fn end

local function changed()
  if onRebuild then onRebuild() end
end

function Buildings.clear()
  for i = 1, Buildings.n do
    local c = Grid.cellIndex(Buildings.gx[i], Buildings.gy[i])
    index[c] = nil
    Grid.occupancy[c] = Grid.OCC_NONE
  end
  Buildings.n = 0
end

function Buildings.at(gx, gy)
  return index[Grid.cellIndex(gx, gy)] or 0
end

function Buildings.canPlace(gx, gy, village)
  if gx < Grid.EDGE_MARGIN or gy < Grid.EDGE_MARGIN then return false end
  if gx >= Grid.WIDTH - Grid.EDGE_MARGIN or gy >= Grid.HEIGHT - Grid.EDGE_MARGIN then return false end
  if Grid.occAtTile(gx, gy) ~= Grid.OCC_NONE then return false end
  local wx, wy = Grid.tileToWorld(gx, gy)
  local dx, dy = wx - village.x, wy - village.y
  local minDist = village.r + Grid.TILE * 0.75
  return dx * dx + dy * dy > minDist * minDist
end

function Buildings.place(gx, gy, kind, instant)
  local d = buildingData[kind]
  Buildings.n = Buildings.n + 1
  local i = Buildings.n
  local wx, wy = Grid.tileToWorld(gx, gy)
  Buildings.kind[i] = kind
  Buildings.gx[i] = gx
  Buildings.gy[i] = gy
  Buildings.x[i] = wx
  Buildings.y[i] = wy
  Buildings.hp[i] = d.hp
  Buildings.maxHp[i] = d.hp
  Buildings.progress[i] = instant and d.buildTime or 0
  Buildings.built[i] = instant and true or false
  Buildings.flash[i] = 0
  Buildings.crewCount[i] = 0
  Buildings.maxCrew[i] = d.crew or 0
  Buildings.cd[i] = 0
  Buildings.isTower[i] = kind == "arrow_tower" or kind == "ballista"
  local c = Grid.cellIndex(gx, gy)
  index[c] = i
  Grid.occupancy[c] = Grid.OCC_BUILD
  changed()
  return i
end

function Buildings.remove(i)
  local n = Buildings.n
  local destroyed, movedFrom, movedTo = i, nil, nil
  local c = Grid.cellIndex(Buildings.gx[i], Buildings.gy[i])
  index[c] = nil
  Grid.occupancy[c] = Grid.OCC_NONE
  if i ~= n then
    Buildings.kind[i] = Buildings.kind[n]
    Buildings.gx[i] = Buildings.gx[n]
    Buildings.gy[i] = Buildings.gy[n]
    Buildings.x[i] = Buildings.x[n]
    Buildings.y[i] = Buildings.y[n]
    Buildings.hp[i] = Buildings.hp[n]
    Buildings.maxHp[i] = Buildings.maxHp[n]
    Buildings.progress[i] = Buildings.progress[n]
    Buildings.built[i] = Buildings.built[n]
    Buildings.flash[i] = Buildings.flash[n]
    Buildings.crewCount[i] = Buildings.crewCount[n]
    Buildings.maxCrew[i] = Buildings.maxCrew[n]
    Buildings.cd[i] = Buildings.cd[n]
    Buildings.isTower[i] = Buildings.isTower[n]
    index[Grid.cellIndex(Buildings.gx[i], Buildings.gy[i])] = i
    movedFrom, movedTo = n, i
  end
  Buildings.n = n - 1
  if onRemove then onRemove(destroyed, movedFrom, movedTo) end
  changed()
end

function Buildings.damage(i, amount)
  Buildings.hp[i] = Buildings.hp[i] - amount
  Buildings.flash[i] = 0.1
  if Buildings.hp[i] <= 0 then Buildings.remove(i) end
end

function Buildings.update(dt)
  for i = 1, Buildings.n do
    if Buildings.flash[i] > 0 then Buildings.flash[i] = Buildings.flash[i] - dt end
  end
end

function Buildings.popCap()
  local cap = buildingData.village_center.popCap
  for i = 1, Buildings.n do
    if Buildings.kind[i] == "house" and Buildings.built[i] then
      cap = cap + buildingData.house.popCap
    end
  end
  return cap
end

return Buildings
