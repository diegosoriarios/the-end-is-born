-- Main menu, pause overlay, and settings screen. Layout is shared between
-- drawing and click hit-testing so the two never drift.
local Settings = require("src.core.settings")
local Persistence = require("src.core.persistence")
local Checklist = require("src.sim.checklist")

local Menu = {}

local fonts = {}
local BTN_BG = { 0.16, 0.13, 0.22 }
local BTN_BG_HOVER = { 0.30, 0.18, 0.40 }
local BTN_FG = { 0.80, 0.72, 0.92 }

function Menu.load()
  fonts.title = love.graphics.newFont(72)
  fonts.big = love.graphics.newFont(26)
  fonts.med = love.graphics.newFont(19)
  fonts.small = love.graphics.newFont(14)
end

local function pointInRect(px, py, r)
  return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

local function vmenu(items)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local bw, bh, gap = 300, 56, 16
  local total = #items * bh + (#items - 1) * gap
  local y = h / 2 - total / 2 + 40
  local btns = {}
  for i = 1, #items do
    btns[#btns + 1] = { x = w / 2 - bw / 2, y = y, w = bw, h = bh, label = items[i][1], action = items[i][2] }
    y = y + bh + gap
  end
  return btns
end

function Menu.mainButtons()
  local items = {}
  if Persistence.exists() then
    items[#items + 1] = { "Continue", "continue" }
  end
  items[#items + 1] = { "New Cult", "start" }
  items[#items + 1] = { "Settings", "settings" }
  items[#items + 1] = { "Quit", "quit" }
  return vmenu(items)
end

function Menu.pauseButtons()
  return vmenu({
    { "Resume", "resume" },
    { "Save", "save" },
    { "Settings", "settings" },
    { "Restart", "restart" },
    { "Main Menu", "mainmenu" },
  })
end

function Menu.settingsButtons()
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local pw = 480
  local px = w / 2 - pw / 2
  local rowH = 46
  local y0 = h / 2 - 150
  local btns = {}
  local function stepper(i, key)
    local y = y0 + i * rowH
    btns[#btns + 1] = { x = px + pw - 92, y = y - 17, w = 34, h = 34, label = "-", action = "vol_" .. key .. "_down", small = true }
    btns[#btns + 1] = { x = px + pw - 52, y = y - 17, w = 34, h = 34, label = "+", action = "vol_" .. key .. "_up", small = true }
  end
  stepper(0, "master")
  stepper(1, "sfx")
  stepper(2, "music")
  btns[#btns + 1] = { x = px + pw - 130, y = y0 + 3 * rowH - 17, w = 120, h = 34, label = Settings.shake and "ON" or "OFF", action = "toggle_shake", small = true }
  btns[#btns + 1] = { x = px + pw - 130, y = y0 + 4 * rowH - 17, w = 120, h = 34, label = Settings.fullscreen and "ON" or "OFF", action = "toggle_fullscreen", small = true }
  btns[#btns + 1] = { x = w / 2 - 90, y = y0 + 5 * rowH + 14, w = 180, h = 46, label = "Back", action = "back" }
  Menu._rows = { px = px, pw = pw, y0 = y0, rowH = rowH }
  return btns
end

function Menu.layout(S)
  if S.settingsOpen then return Menu.settingsButtons() end
  if S.mode == "menu" then return Menu.mainButtons() end
  return Menu.pauseButtons()
end

function Menu.handleClick(mx, my, S)
  for _, b in ipairs(Menu.layout(S)) do
    if pointInRect(mx, my, b) then
      local a = b.action
      if a == "start" then
        S.reset()
      elseif a == "continue" then
        if Persistence.load(S) then
          S.paused = false
          S.settingsOpen = false
          S.mode = "playing"
        end
      elseif a == "save" then
        if Persistence.save(S) then
          Checklist.notice("THE CULT ENDURES", "progress carved into the dark")
        else
          Checklist.notice("THE RITE FAILS", "progress can only be saved between hordes")
        end
      elseif a == "quit" then
        love.event.quit()
      elseif a == "settings" then
        S.settingsOpen = true
      elseif a == "back" then
        S.settingsOpen = false
      elseif a == "resume" then
        S.paused = false
        S.settingsOpen = false
      elseif a == "restart" then
        S.paused = false
        S.settingsOpen = false
        S.reset()
      elseif a == "mainmenu" then
        S.paused = false
        S.settingsOpen = false
        S.mode = "menu"
      elseif a == "vol_master_down" then Settings.adjust("master", -0.1)
      elseif a == "vol_master_up" then Settings.adjust("master", 0.1)
      elseif a == "vol_sfx_down" then Settings.adjust("sfx", -0.1)
      elseif a == "vol_sfx_up" then Settings.adjust("sfx", 0.1)
      elseif a == "vol_music_down" then Settings.adjust("music", -0.1)
      elseif a == "vol_music_up" then Settings.adjust("music", 0.1)
      elseif a == "toggle_shake" then Settings.toggle("shake")
      elseif a == "toggle_fullscreen" then Settings.toggle("fullscreen")
      end
      return true
    end
  end
  return false
end

local function drawButtons(btns)
  local mx, my = love.mouse.getPosition()
  for i = 1, #btns do
    local b = btns[i]
    local hover = pointInRect(mx, my, b)
    love.graphics.setColor(hover and BTN_BG_HOVER or BTN_BG)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6)
    love.graphics.setColor(hover and { 0.85, 0.6, 0.95 } or { 0.5, 0.4, 0.6 })
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 6)
    love.graphics.setColor(BTN_FG)
    local f = b.small and fonts.med or fonts.big
    love.graphics.setFont(f)
    love.graphics.print(b.label, b.x + (b.w - f:getWidth(b.label)) / 2, b.y + (b.h - f:getHeight()) / 2)
  end
end

function Menu.drawTitle(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  love.graphics.clear(0.05, 0.03, 0.07)
  love.graphics.setFont(fonts.title)
  love.graphics.setColor(0.62, 0.28, 0.72)
  local t = "antic"
  love.graphics.print(t, w / 2 - fonts.title:getWidth(t) / 2, h / 2 - 210)
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(0.7, 0.6, 0.8)
  local sub = "grow the flock  ·  feed the dark  ·  birth the end"
  love.graphics.print(sub, w / 2 - fonts.small:getWidth(sub) / 2, h / 2 - 110)
  if not S.settingsOpen then
    drawButtons(Menu.mainButtons())
  end
end

function Menu.drawPause(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  love.graphics.setColor(0, 0, 0, 0.62)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setFont(fonts.big)
  love.graphics.setColor(0.72, 0.4, 0.85)
  local t = "PAUSED"
  love.graphics.print(t, w / 2 - fonts.big:getWidth(t) / 2, h / 2 - 150)
  if not S.settingsOpen then
    drawButtons(Menu.pauseButtons())
  end
end

function Menu.drawSettings(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  love.graphics.setColor(0, 0, 0, 0.72)
  love.graphics.rectangle("fill", 0, 0, w, h)
  local btns = Menu.settingsButtons()
  local r = Menu._rows
  love.graphics.setColor(0.10, 0.08, 0.14, 0.98)
  love.graphics.rectangle("fill", r.px, r.y0 - 56, r.pw, 5 * r.rowH + 176, 8)
  love.graphics.setColor(0.5, 0.3, 0.6)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", r.px, r.y0 - 56, r.pw, 5 * r.rowH + 176, 8)
  love.graphics.setFont(fonts.big)
  love.graphics.setColor(0.85, 0.6, 0.95)
  local t = "SETTINGS"
  love.graphics.print(t, w / 2 - fonts.big:getWidth(t) / 2, r.y0 - 48)
  love.graphics.setFont(fonts.med)
  local labels = { "Master volume", "Sound volume", "Music volume", "Screen shake", "Fullscreen" }
  for i = 1, #labels do
    love.graphics.setColor(0.85, 0.82, 0.92)
    love.graphics.print(labels[i], r.px + 24, r.y0 + (i - 1) * r.rowH - 8)
  end
  local vals = { Settings.master, Settings.sfx, Settings.music }
  for i = 1, #vals do
    local s = ("%d%%"):format(math.floor(vals[i] * 100 + 0.5))
    love.graphics.setColor(0.9, 0.75, 0.95)
    love.graphics.print(s, r.px + r.pw - 100 - fonts.med:getWidth(s), r.y0 + (i - 1) * r.rowH - 8)
  end
  drawButtons(btns)
end

return Menu
