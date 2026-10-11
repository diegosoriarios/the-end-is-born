local State = require("src.core.state")
local Camera = require("src.core.camera")
local Grid = require("src.sim.grid")
local Enemies = require("src.sim.enemies")

local FIXED_DT = 1 / 60

function love.load()
  State.reset()
end

function love.update(dt)
  local frameT0 = love.timer.getTime()
  State.frameT0 = frameT0
  State.accumulator = (State.accumulator or 0) + math.min(dt, 0.1)
  while State.accumulator >= FIXED_DT do
    State.update(FIXED_DT)
    State.accumulator = State.accumulator - FIXED_DT
  end
  local simMs = (love.timer.getTime() - frameT0) * 1000
  State.stats.simMs = State.stats.simMs * 0.95 + simMs * 0.05
end

function love.draw()
  local drawT0 = love.timer.getTime()
  State.draw()
  local now = love.timer.getTime()
  State.stats.drawMs = State.stats.drawMs * 0.95 + (now - drawT0) * 1000 * 0.05
  State.stats.frameMs = State.stats.frameMs * 0.95 + (now - (State.frameT0 or now)) * 1000 * 0.05
end

function love.keypressed(key)
  if key == "escape" then
    if State.buildMode then
      State.buildMode = false
    else
      love.event.quit()
    end
  elseif key == "r" then
    State.reset()
  elseif key == "1" and State.mode == "playing" then
    State.setBuildType("wall")
  elseif key == "2" and State.mode == "playing" then
    State.setBuildType("arrow_tower")
  elseif key == "b" and State.mode == "playing" then
    State.buildMode = not State.buildMode
  elseif key == "space" then
    State.waves:skip()
  elseif key == "f3" then
    State.debug = not State.debug
  elseif key == "k" and State.mode == "playing" then
    local count = love.keyboard.isDown("lshift", "rshift") and 10000 or 1000
    local W, H = Grid.pixelWidth(), Grid.pixelHeight()
    local m = 24
    for _ = 1, count do
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
      Enemies.spawn(x, y, "grunt", 1)
    end
    print("[debug] spawned " .. count .. " enemies (total " .. Enemies.n .. ")")
  end
end

function love.mousepressed(x, y, button)
  if button == 1 then
    if State.handleClick(x, y) then return end
    if State.buildMode then State.tryPlace(x, y) end
  elseif button == 2 then
    State.buildMode = false
  end
end

function love.wheelmoved(_, dy)
  Camera.zoomBy(dy)
end
