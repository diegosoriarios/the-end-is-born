local buildingData = require("src.data.buildings")
local Grid = require("src.sim.grid")
local Enemies = require("src.sim.enemies")

local Towers = { list = {}, shots = 0 }

function Towers.clear()
  Towers.list = {}
  Towers.shots = 0
end

function Towers.canPlace(gx, gy, village)
  if not Grid.inBounds(gx, gy) then return false end
  if Grid.occAtTile(gx, gy) ~= Grid.OCC_NONE then return false end
  local wx, wy = Grid.tileToWorld(gx, gy)
  local dx, dy = wx - village.x, wy - village.y
  local minDist = village.r + Grid.TILE * 0.75
  return dx * dx + dy * dy > minDist * minDist
end

function Towers.place(gx, gy)
  local wx, wy = Grid.tileToWorld(gx, gy)
  local tower = { gx = gx, gy = gy, x = wx, y = wy, kind = "arrow_tower", cooldown = 0 }
  Towers.list[#Towers.list + 1] = tower
  return tower
end

local probeBest, probeBestD = 0, math.huge
local probeX, probeY = 0, 0
local function probeCallback(j)
  if Enemies.hp[j] > 0 then
    local dx = probeX - Enemies.x[j]
    local dy = probeY - Enemies.y[j]
    local d2 = dx * dx + dy * dy
    if d2 < probeBestD then
      probeBestD = d2
      probeBest = j
    end
  end
end

local function update(dt, hash, projectiles)
  local d = buildingData.arrow_tower
  local E = Enemies
  for i = 1, #Towers.list do
    local t = Towers.list[i]
    t.cooldown = t.cooldown - dt
    if t.cooldown <= 0 then
      probeBest = 0
      probeBestD = d.range * d.range
      probeX = t.x
      probeY = t.y
      hash:queryCircle(t.x, t.y, d.range, probeCallback)
      local j = probeBest
      if j > 0 then
        t.cooldown = d.fireInterval
        Towers.shots = Towers.shots + 1
        local flight = math.sqrt(probeBestD) / d.projectileSpeed
        local aimX = E.x[j] + E.hx[j] * E.speed[j] * flight
        local aimY = E.y[j] + E.hy[j] * E.speed[j] * flight
        projectiles.spawn(t.x, t.y, aimX, aimY, d.projectileSpeed, d.damage)
      end
    end
  end
end

Towers.update = update

return Towers
