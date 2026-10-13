local State = require("src.core.state")
local Camera = require("src.core.camera")
local Grid = require("src.sim.grid")
local Enemies = require("src.sim.enemies")
local Villagers = require("src.sim.villagers")
local Buildings = require("src.sim.buildings")
local Ages = require("src.sim.ages")
local Audio = require("src.audio.audio")
local Settings = require("src.core.settings")
local Menu = require("src.ui.menu")

local FIXED_DT = 1 / 60

function love.load()
  Audio.load()
  Settings.load()
  Settings.apply()
  Menu.load()
  State.reset()
  if State.menu or not State.harness then
    State.mode = "menu"
  end
  Audio.startMusic()
end

function love.update(dt)
  if State.menu then
    State.menu = State.menu - 1
    if State.menu == 220 then State.settingsOpen = true end
    if State.menu == 200 then love.graphics.captureScreenshot("menu_settings.png") end
    if State.menu == 150 then State.settingsOpen = false end
    if State.menu == 60 then love.graphics.captureScreenshot("menu_title.png") end
    if State.menu <= 0 then
      print(("[menu] done: mode=%s settings=%s paused=%s"):format(State.mode, tostring(State.settingsOpen), tostring(State.paused)))
      love.event.quit()
    end
  end
  if State.mode == "menu" then return end
  if State.paused then
    State.accumulator = 0
    return
  end
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
  if State.mode == "menu" then
    Menu.drawTitle(State)
    if State.settingsOpen then Menu.drawSettings(State) end
    return
  end
  local drawT0 = love.timer.getTime()
  State.draw()
  if State.mode == "playing" and State.paused then
    if State.settingsOpen then
      Menu.drawSettings(State)
    else
      Menu.drawPause(State)
    end
  end
  local now = love.timer.getTime()
  State.stats.drawMs = State.stats.drawMs * 0.95 + (now - drawT0) * 1000 * 0.05
  State.stats.frameMs = State.stats.frameMs * 0.95 + (now - (State.frameT0 or now)) * 1000 * 0.05
end

function love.keypressed(key)
  if key == "escape" then
    if State.settingsOpen then
      State.settingsOpen = false
    elseif State.paused then
      State.paused = false
    elseif State.mode == "menu" then
      love.event.quit()
    elseif State.selection then
      State.selection = nil
      State.follow = false
    elseif State.buildMode then
      State.buildMode = false
    else
      State.paused = true
    end
    return
  end
  if State.mode ~= "playing" or State.paused or State.settingsOpen then return end
  if key == "r" then
    State.reset()
  elseif key:match("^[1-9]$") then
    local idx = tonumber(key)
    local n = 0
    for _, kind in ipairs(Buildings.buildIn(State.buildCategory or "defense")) do
      if Ages.unlocked(kind) then
        n = n + 1
        if n == idx then State.setBuildType(kind) break end
      end
    end
  elseif key == "c" then
    State.checklistVisible = not State.checklistVisible
  elseif key == "b" then
    State.buildMode = not State.buildMode
  elseif key == "space" then
    State.waves:skip()
  elseif key == "f3" then
    State.debug = not State.debug
  elseif key == "k" then
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
  elseif key == "p" then
    local cal = State.waves.calendar
    cal.apocalypse = not cal.apocalypse
    print("[debug] end times " .. (cal.apocalypse and "begun — hordes come every month" or "averted"))
  end
end

function love.mousepressed(x, y, button)
  if State.mode == "menu" or State.paused or State.settingsOpen then
    if button == 1 then Menu.handleClick(x, y, State) end
    return
  end
  if button == 1 then
    if State.handleClick(x, y) then return end
    if State.buildMode then
      State.tryPlace(x, y)
      return
    end
    if State.mode ~= "playing" then return end
    local wx, wy = Camera.toWorld(x, y)
    local gx, gy = Grid.worldToTile(wx, wy)
    local sel
    for _, v in ipairs(Villagers.list) do
      if not v.dead then
        local dx, dy = v.x - wx, v.y - wy
        if dx * dx + dy * dy < 144 then sel = { villager = v }; break end
      end
    end
    if not sel then
      local dx, dy = wx - State.village.x, wy - State.village.y
      if dx * dx + dy * dy <= State.village.r * State.village.r then sel = { heart = true } end
    end
    if not sel then
      local b = Buildings.at(gx, gy)
      if b > 0 then sel = { building = b } end
    end
    State.selection = sel
    State.follow = sel ~= nil and sel.villager ~= nil
  elseif button == 2 then
    local wx, wy = Camera.toWorld(x, y)
    if State.buildMode then
      State.buildMode = false
    elseif State.selection and State.selection.villager then
      -- assign the selected villager to the clicked resource/building
      if not State.assignTo(State.selection.villager, wx, wy) then
        State.selection = nil
        State.follow = false
      end
    else
      State.selection = nil
      State.follow = false
    end
  end
end

function love.wheelmoved(_, dy)
  if State.mode == "menu" or State.paused or State.settingsOpen then return end
  Camera.zoomBy(dy)
end
