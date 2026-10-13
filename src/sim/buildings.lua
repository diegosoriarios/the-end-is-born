local Grid = require("src.sim.grid")
local buildingData = require("src.data.buildings")
local Particles = require("src.fx.particles")
local Camera = require("src.core.camera")

local Buildings = {
  n = 0,
  kind = {}, gx = {}, gy = {}, x = {}, y = {},
  hp = {}, maxHp = {}, progress = {}, built = {}, flash = {},
  crewCount = {}, maxCrew = {}, cd = {},
  isTower = {}, role = {},
  project = {}, rprogress = {}, researchers = {},
  graves = {},
}

-- Ordered list of buildable kinds (build bar + number keys), from data.
local buildOrder = nil
function Buildings.buildOrder()
  if buildOrder then return buildOrder end
  buildOrder = {}
  for kind, d in pairs(buildingData) do
    if d.role ~= "heart" and d.cost and d.buildable ~= false then
      buildOrder[#buildOrder + 1] = { kind = kind, order = d.order or 999 }
    end
  end
  table.sort(buildOrder, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.kind < b.kind
  end)
  return buildOrder
end

-- Ordered unique build categories (build-palette tabs), from data.
local categoriesCache = nil
function Buildings.categories()
  if categoriesCache then return categoriesCache end
  categoriesCache = {}
  local seen = {}
  for _, e in ipairs(Buildings.buildOrder()) do
    local c = buildingData[e.kind].category or "other"
    if not seen[c] then
      seen[c] = true
      categoriesCache[#categoriesCache + 1] = c
    end
  end
  return categoriesCache
end

-- Ordered buildable kinds within a category.
function Buildings.buildIn(category)
  local out = {}
  for _, e in ipairs(Buildings.buildOrder()) do
    if buildingData[e.kind].category == category then out[#out + 1] = e.kind end
  end
  return out
end

local index = {}
local onRebuild, onRemove, onBuilt = nil, nil, nil

function Buildings.setRebuildHook(fn) onRebuild = fn end

function Buildings.setRemoveHook(fn) onRemove = fn end

function Buildings.setBuiltHook(fn) onBuilt = fn end

-- Called when construction finishes (lets content add role effects).
function Buildings.emitBuilt(i)
  if onBuilt then onBuilt(i) end
end

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
  Buildings.role[i] = d.role
  Buildings.isTower[i] = d.role == "tower"
  Buildings.project[i] = nil
  Buildings.rprogress[i] = 0
  Buildings.researchers[i] = 0
  Buildings.graves[i] = 0
  local c = Grid.cellIndex(gx, gy)
  index[c] = i
  Grid.occupancy[c] = Grid.OCC_BUILD
  Particles.dust(wx, wy, 6)
  changed()
  return i
end

function Buildings.remove(i)
  local n = Buildings.n
  local destroyed, movedFrom, movedTo = i, nil, nil
  local wx, wy, kind = Buildings.x[i], Buildings.y[i], Buildings.kind[i]
  local c = Grid.cellIndex(Buildings.gx[i], Buildings.gy[i])
  index[c] = nil
  Grid.occupancy[c] = Grid.OCC_NONE
  Particles.dust(Buildings.x[i], Buildings.y[i], 12)
  Camera.shake(4, 0.3)
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
    Buildings.role[i] = Buildings.role[n]
    Buildings.project[i] = Buildings.project[n]
    Buildings.rprogress[i] = Buildings.rprogress[n]
    Buildings.researchers[i] = Buildings.researchers[n]
    Buildings.graves[i] = Buildings.graves[n]
    index[Grid.cellIndex(Buildings.gx[i], Buildings.gy[i])] = i
    movedFrom, movedTo = n, i
  end
  Buildings.n = n - 1
  if onRemove then onRemove(destroyed, movedFrom, movedTo, wx, wy, kind) end
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

-- Rebuild the registry from saved primitives (bypasses place() cost/hooks).
function Buildings.load(list)
  Buildings.clear()
  for i = 1, #list do
    local b = list[i]
    Buildings.kind[i] = b.kind
    Buildings.gx[i] = b.gx
    Buildings.gy[i] = b.gy
    Buildings.x[i], Buildings.y[i] = Grid.tileToWorld(b.gx, b.gy)
    Buildings.hp[i] = b.hp
    Buildings.maxHp[i] = b.maxHp
    Buildings.progress[i] = b.progress
    Buildings.built[i] = b.built
    Buildings.flash[i] = 0
    Buildings.crewCount[i] = b.crewCount or 0
    Buildings.maxCrew[i] = b.maxCrew or 0
    Buildings.cd[i] = b.cd or 0
    Buildings.role[i] = buildingData[b.kind].role
    Buildings.isTower[i] = Buildings.role[i] == "tower"
    Buildings.project[i] = b.project
    Buildings.rprogress[i] = b.rprogress or 0
    Buildings.researchers[i] = 0
    Buildings.graves[i] = 0
    local c = Grid.cellIndex(b.gx, b.gy)
    index[c] = i
    Grid.occupancy[c] = Grid.OCC_BUILD
  end
  Buildings.n = #list
  changed()
end

-- In-place upgrade (e.g. School -> University): swaps the kind, resets to an
-- unbuilt state so a builder finishes it, keeps position/crew.
function Buildings.upgrade(i, newKind)
  local d = buildingData[newKind]
  if not d then return false end
  Buildings.kind[i] = newKind
  Buildings.hp[i] = d.hp
  Buildings.maxHp[i] = d.hp
  Buildings.progress[i] = 0
  Buildings.built[i] = false
  Buildings.role[i] = d.role
  Buildings.isTower[i] = d.role == "tower"
  Buildings.maxCrew[i] = d.crew or 0
  if Buildings.crewCount[i] > Buildings.maxCrew[i] then Buildings.crewCount[i] = Buildings.maxCrew[i] end
  Buildings.project[i] = nil
  Buildings.rprogress[i] = 0
  Particles.dust(Buildings.x[i], Buildings.y[i], 10)
  changed()
  return true
end

function Buildings.hasBuilt(kind)
  for i = 1, Buildings.n do
    if Buildings.kind[i] == kind and Buildings.built[i] then return true end
  end
  return false
end

function Buildings.hasRole(role)
  for i = 1, Buildings.n do
    if Buildings.role[i] == role and Buildings.built[i] then return true end
  end
  return false
end

function Buildings.popCap()
  local cap = buildingData.village_center.popCap
  for i = 1, Buildings.n do
    local d = buildingData[Buildings.kind[i]]
    if d.popCap and Buildings.built[i] then cap = cap + d.popCap end
  end
  return cap
end

return Buildings
