local Grid = require("src.sim.grid")
local Enemies = require("src.sim.enemies")

local Projectiles = {
  n = 0,
  x = {}, y = {},
  vx = {}, vy = {},
  damage = {},
  life = {},
  hits = 0,
}

function Projectiles.resetCounters()
  Projectiles.hits = 0
end

local function spawn(x, y, tx, ty, speed, damage)
  local dx, dy = tx - x, ty - y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.001 then
    dx, dy, d = 1, 0, 1
  end
  Projectiles.n = Projectiles.n + 1
  local i = Projectiles.n
  Projectiles.x[i] = x
  Projectiles.y[i] = y
  Projectiles.vx[i] = dx / d * speed
  Projectiles.vy[i] = dy / d * speed
  Projectiles.damage[i] = damage
  Projectiles.life[i] = 2
end

local hitX, hitY, hitBest, hitBestD = 0, 0, 0, math.huge
local function hitCallback(j)
  local dx = hitX - Enemies.x[j]
  local dy = hitY - Enemies.y[j]
  local d2 = dx * dx + dy * dy
  local rr = Enemies.r[j] + 4
  if d2 <= rr * rr and d2 < hitBestD and Enemies.hp[j] > 0 then
    hitBestD = d2
    hitBest = j
  end
end

local function update(dt, hash)
  local P = Projectiles
  local i = 1
  while i <= P.n do
    P.x[i] = P.x[i] + P.vx[i] * dt
    P.y[i] = P.y[i] + P.vy[i] * dt
    P.life[i] = P.life[i] - dt
    local dead = P.life[i] <= 0
    if not dead then
      hitX = P.x[i]
      hitY = P.y[i]
      hitBest = 0
      hitBestD = math.huge
      hash:queryCircle(hitX, hitY, 12, hitCallback)
      if hitBest > 0 then
        Enemies.damage(hitBest, P.damage[i])
        P.hits = P.hits + 1
        dead = true
      end
    end
    if dead then
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

Projectiles.spawn = spawn
Projectiles.update = update

return Projectiles
