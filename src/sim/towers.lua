local buildingData = require("src.data.buildings")
local Buildings = require("src.sim.buildings")
local Enemies = require("src.sim.enemies")
local Particles = require("src.fx.particles")
local Audio = require("src.audio.audio")

local Towers = { shots = 0 }

function Towers.clear()
  Towers.shots = 0
end

function Towers.canPlace(gx, gy, village)
  return Buildings.canPlace(gx, gy, village)
end

-- Instant-build helper for test harnesses (skips cost + construction).
function Towers.place(gx, gy, kind)
  return Buildings.place(gx, gy, kind or "arrow_tower", true)
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

function Towers.update(dt, hash, projectiles)
  local B = Buildings
  local E = Enemies
  for i = 1, B.n do
    if B.isTower[i] and B.built[i] and B.crewCount[i] >= B.maxCrew[i] then
      B.cd[i] = B.cd[i] - dt
      if B.cd[i] <= 0 then
        local d = buildingData[B.kind[i]]
        probeBest = 0
        probeBestD = d.range * d.range
        probeX = B.x[i]
        probeY = B.y[i]
        hash:queryCircle(B.x[i], B.y[i], d.range, probeCallback)
        local j = probeBest
        if j > 0 then
          B.cd[i] = d.fireInterval
          Towers.shots = Towers.shots + 1
          Particles.muzzle(B.x[i], B.y[i], E.x[j] - B.x[i], E.y[j] - B.y[i], "spark")
          Audio.play(B.kind[i] == "ballista" and "ballista" or "shoot")
          local flight = math.sqrt(probeBestD) / d.projectileSpeed
          projectiles.spawn(B.x[i], B.y[i],
            E.x[j] + E.hx[j] * E.speed[j] * flight,
            E.y[j] + E.hy[j] * E.speed[j] * flight,
            d.projectileSpeed, d.damage)
        end
      end
    end
  end
end

return Towers
