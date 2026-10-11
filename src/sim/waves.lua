local waveData = require("src.data.waves")
local Grid = require("src.sim.grid")

local Waves = {}
Waves.__index = Waves

function Waves.new()
  return setmetatable({
    phase = "village",
    timer = waveData.startDelay,
    number = 0,
    toSpawn = 0,
    spawnTimer = 0,
  }, Waves)
end

function Waves:skip()
  if self.phase == "village" then self.timer = 0 end
end

function Waves.spawnAtEdge(enemies, kind, hpMul)
  local W, H = Grid.pixelWidth(), Grid.pixelHeight()
  local m = 24
  local edge = love.math.random(0, 3)
  local x, y
  if edge == 0 then
    x, y = love.math.random(m, W - m), m
  elseif edge == 1 then
    x, y = love.math.random(m, W - m), H - m
  elseif edge == 2 then
    x, y = m, love.math.random(m, H - m)
  else
    x, y = W - m, love.math.random(m, H - m)
  end
  enemies.spawn(x, y, kind, hpMul)
end

function Waves:update(dt, ctx)
  if self.phase == "village" then
    self.timer = self.timer - dt
    if self.timer <= 0 then
      self.number = self.number + 1
      self.toSpawn = waveData.spawnPerWave(self.number)
      self.spawnTimer = 0.5
      self.phase = "wave"
    end
    return
  end
  if self.toSpawn > 0 then
    self.spawnTimer = self.spawnTimer - dt
    if self.spawnTimer <= 0 then
      self.spawnTimer = waveData.spawnInterval
      self.toSpawn = self.toSpawn - 1
      local hpMul = 1 + waveData.hpGrowth * (self.number - 1)
      Waves.spawnAtEdge(ctx.enemies, waveData.enemyType, hpMul)
    end
  elseif ctx.enemies.n == 0 then
    if self.number >= waveData.totalWaves then
      ctx.mode = "victory"
    else
      self.phase = "village"
      self.timer = waveData.countdown
    end
  end
end

return Waves
