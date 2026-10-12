-- Hostile ranged attacks (spitters). Straight shots that resolve damage
-- positionally on impact: villager > building > wall > village heart.
local Grid = require("src.sim.grid")
local Walls = require("src.sim.walls")
local Buildings = require("src.sim.buildings")
local Villagers = require("src.sim.villagers")
local Particles = require("src.fx.particles")

local EnemyShots = {
  n = 0,
  x = {}, y = {},
  vx = {}, vy = {},
  damage = {},
  life = {},
  hits = 0,
}

local function spawn(x, y, tx, ty, speed, damage)
  local dx, dy = tx - x, ty - y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.001 then
    dx, dy, d = 1, 0, 1
  end
  EnemyShots.n = EnemyShots.n + 1
  local i = EnemyShots.n
  EnemyShots.x[i] = x
  EnemyShots.y[i] = y
  EnemyShots.vx[i] = dx / d * speed
  EnemyShots.vy[i] = dy / d * speed
  EnemyShots.damage[i] = damage
  EnemyShots.life[i] = d / speed
  Particles.trail(x, y, "green")
end

local function resolveImpact(x, y, dmg, ctx)
  local list = ctx.villagers.list
  local best, bd = nil, 196
  for k = 1, #list do
    local v = list[k]
    if not v.dead then
      local dx, dy = v.x - x, v.y - y
      local d2 = dx * dx + dy * dy
      if d2 < bd then
        bd = d2
        best = v
      end
    end
  end
  if best then
    Villagers.damage(best, dmg)
    Particles.blood(x, y, 2)
    return
  end
  local gx, gy = Grid.worldToTile(x, y)
  local b = Buildings.at(gx, gy)
  if b > 0 then
    Buildings.damage(b, dmg)
    Particles.dust(x, y, 4)
    return
  end
  local w = Walls.at(gx, gy)
  if w > 0 then
    Walls.damage(w, dmg)
    Particles.dust(x, y, 4)
    return
  end
  local v = ctx.village
  local dx, dy = v.x - x, v.y - y
  if dx * dx + dy * dy < v.r * v.r then
    v.hp = math.max(0, v.hp - dmg)
    Particles.blood(x, y, 2)
  end
end

local function update(dt, ctx)
  local P = EnemyShots
  local i = 1
  while i <= P.n do
    P.x[i] = P.x[i] + P.vx[i] * dt
    P.y[i] = P.y[i] + P.vy[i] * dt
    P.life[i] = P.life[i] - dt
    if P.life[i] <= 0 then
      P.hits = P.hits + 1
      resolveImpact(P.x[i], P.y[i], P.damage[i], ctx)
      local last = P.n
      P.x[i] = P.x[last]
      P.y[i] = P.y[last]
      P.vx[i] = P.vx[last]
      P.vy[i] = P.vy[last]
      P.damage[i] = P.damage[last]
      P.life[i] = P.life[last]
      P.n = P.n - 1
    else
      i = i + 1
    end
  end
end

EnemyShots.spawn = spawn
EnemyShots.update = update

return EnemyShots
