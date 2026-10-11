local UI = {}

local bigFont, medFont, smallFont, debugFont
local buttons = {}

local function pointInRect(px, py, r)
  return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

function UI.load()
  bigFont = love.graphics.newFont(44)
  medFont = love.graphics.newFont(22)
  smallFont = love.graphics.newFont(15)
  debugFont = love.graphics.newFont(13)
end

function UI.buildButtons(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  buttons = {}
  if S.mode == "playing" then
    buttons[#buttons + 1] = {
      x = 16, y = h - 60, w = 130, h = 44,
      label = "Wall [1]",
      buildType = "wall",
    }
    buttons[#buttons + 1] = {
      x = 154, y = h - 60, w = 160, h = 44,
      label = "Arrow Tower [2]",
      buildType = "arrow_tower",
    }
  else
    buttons[#buttons + 1] = {
      x = w / 2 - 95, y = h / 2 + 56, w = 190, h = 44,
      label = "Restart [R]",
      action = "restart",
    }
  end
  return buttons
end

function UI.handleClick(mx, my, S)
  for _, b in ipairs(UI.buildButtons(S)) do
    if pointInRect(mx, my, b) then
      if b.action == "restart" then
        S.reset()
      elseif b.buildType then
        if S.buildMode and S.buildType == b.buildType then
          S.buildMode = false
        else
          S.setBuildType(b.buildType)
        end
      end
      return true
    end
  end
  return false
end

local function drawButton(b)
  love.graphics.setColor(b.active and { 0.45, 0.25, 0.55 } or { 0.16, 0.13, 0.22 })
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 4)
  love.graphics.setColor(b.active and { 0.75, 0.5, 0.85 } or { 0.45, 0.42, 0.55 })
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 4)
  love.graphics.setFont(smallFont)
  local tw = smallFont:getWidth(b.label)
  love.graphics.print(b.label, b.x + (b.w - tw) / 2, b.y + 14)
end

local function drawDebug(S)
  love.graphics.setFont(debugFont)
  local x = love.graphics.getWidth() - 230
  local lines = {
    ("fps: %d"):format(love.timer.getFPS()),
    ("enemies: %d"):format(S.enemies.n),
    ("walls: %d"):format(S.walls.n),
    ("projectiles: %d"):format(S.projectiles.n),
    ("towers: %d (%d shots)"):format(#S.towers.list, S.towers.shots),
    ("step: %.2f ms"):format(S.stats.stepMs),
    ("sim: %.2f ms"):format(S.stats.simMs),
    ("draw: %.2f ms"):format(S.stats.drawMs),
    ("flow rebakes: %d"):format(S.flow.rebakes),
  }
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", x - 8, 8, 226, #lines * 16 + 12)
  love.graphics.setColor(0.7, 0.95, 0.7)
  for i, l in ipairs(lines) do
    love.graphics.print(l, x, 14 + (i - 1) * 16)
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.print("K +1k  shift+K +10k  F3 close", x, 14 + #lines * 16)
end

function UI.draw(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local bs = UI.buildButtons(S)
  for _, b in ipairs(bs) do
    if b.buildType then b.active = S.buildMode and S.buildType == b.buildType end
    drawButton(b)
  end

  if S.mode == "playing" then
    local wl = S.waves
    local info
    if wl.phase == "village" then
      info = ("WAVE %d INCOMING IN %ds  [Space to skip]"):format(wl.number + 1, math.ceil(wl.timer))
    else
      info = ("WAVE %d  —  enemies: %d"):format(wl.number, S.enemies.n)
    end
    love.graphics.setColor(0.9, 0.86, 0.95)
    love.graphics.setFont(medFont)
    love.graphics.print(info, 16, 12)

    local v = S.village
    local barW, barH = 300, 16
    local bx, by = w / 2 - barW / 2, 14
    love.graphics.setColor(0.10, 0.10, 0.13)
    love.graphics.rectangle("fill", bx, by, barW, barH, 3)
    love.graphics.setColor(0.62, 0.28, 0.72)
    love.graphics.rectangle("fill", bx, by, barW * (v.hp / v.maxHp), barH, 3)
    love.graphics.setColor(0.9, 0.86, 0.95)
    love.graphics.setFont(smallFont)
    local label = ("Village  %d / %d"):format(v.hp, v.maxHp)
    love.graphics.print(label, w / 2 - smallFont:getWidth(label) / 2, by + 1)

    love.graphics.print("1 wall · 2 tower · WASD pan · wheel zoom · F3 debug · R restart", 16, h - 74)

    if S.buildMode then
      local hint = "Click to place " .. S.buildType .. "  ·  right-click to cancel"
      love.graphics.print(hint, w / 2 - smallFont:getWidth(hint) / 2, h - 28)
    end

    if S.debug then drawDebug(S) end
  elseif S.mode == "gameover" or S.mode == "victory" then
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setFont(bigFont)
    if S.mode == "gameover" then
      love.graphics.setColor(0.9, 0.2, 0.22)
      local t = "THE VILLAGE HAS FALLEN"
      love.graphics.print(t, w / 2 - bigFont:getWidth(t) / 2, h / 2 - 70)
    else
      love.graphics.setColor(0.72, 0.4, 0.85)
      local t = "THE HORDE IS SATED... FOR NOW"
      love.graphics.print(t, w / 2 - bigFont:getWidth(t) / 2, h / 2 - 70)
      love.graphics.setFont(smallFont)
      love.graphics.setColor(0.8, 0.75, 0.9)
      local sub = "M2 slice complete"
      love.graphics.print(sub, w / 2 - smallFont:getWidth(sub) / 2, h / 2 - 10)
    end
  end
end

return UI
