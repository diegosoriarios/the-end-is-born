local Camera = require("src.core.camera")
local Grid = require("src.sim.grid")
local Buildings = require("src.sim.buildings")
local Villagers = require("src.sim.villagers")
local Nodes = require("src.sim.nodes")
local buildingData = require("src.data.buildings")
local resData = require("src.data.resources")

local UI = {}

local bigFont, medFont, smallFont, debugFont
local buttons = {}

local KIND_LABEL = {
  arrow_tower = "Arrow Tower",
  ballista = "Ballista",
  house = "House",
  wall = "Wall",
}

local JOB_LABEL = {
  idle = "Idle",
  wood = "Wood",
  food = "Food",
  stone = "Stone",
  build = "Build",
}

local function pointInRect(px, py, r)
  return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

local function costLabel(cost)
  if not cost then return "" end
  local parts = {}
  for _, res in ipairs({ "wood", "food", "stone" }) do
    if cost[res] then parts[#parts + 1] = cost[res] .. res:sub(1, 1) end
  end
  return table.concat(parts, " ")
end

function UI.load()
  bigFont = love.graphics.newFont(44)
  medFont = love.graphics.newFont(22)
  smallFont = love.graphics.newFont(15)
  debugFont = love.graphics.newFont(13)
end

local function addBuildButton(x, y, key, label, buildType, S)
  local d = buildingData[buildType]
  local affordable = true
  if d.cost then
    for res, amt in pairs(d.cost) do
      if (S.stock[res] or 0) < amt then affordable = false end
    end
  end
  buttons[#buttons + 1] = {
    x = x, y = y, w = 130, h = 44,
    label = label .. " [" .. key .. "]",
    sub = costLabel(d.cost),
    buildType = buildType,
    disabled = not affordable,
  }
end

local function addSelectionPanel(S, w, h)
  local sel = S.selection
  if not sel then return end
  local px, py = w - 236, h - 200
  if sel.villager then
    local v = sel.villager
    buttons[#buttons + 1] = { x = px, y = py, w = 220, h = 150, panel = true }
    local jobs = { "idle", "wood", "food", "stone", "build" }
    for i, job in ipairs(jobs) do
      local col = (i - 1) % 2
      local row = math.floor((i - 1) / 2)
      buttons[#buttons + 1] = {
        x = px + 10 + col * 103, y = py + 30 + row * 32, w = 98, h = 27,
        label = JOB_LABEL[job],
        villagerJob = job,
        villager = v,
        active = v.job == job,
      }
    end
  elseif sel.building then
    local i = sel.building
    if i > Buildings.n then return end
    local kind = Buildings.kind[i]
    buttons[#buttons + 1] = { x = px, y = py, w = 220, h = 110, panel = true }
    if Buildings.isTower[i] then
      buttons[#buttons + 1] = {
        x = px + 10, y = py + 40, w = 97, h = 30,
        label = "Assign",
        crewAssign = i,
        disabled = Buildings.n == 0 or Villagers.count() == 0,
      }
      buttons[#buttons + 1] = {
        x = px + 113, y = py + 40, w = 97, h = 30,
        label = "Unassign",
        crewUnassign = i,
        disabled = Buildings.crewCount[i] == 0,
      }
    end
  end
end

function UI.buildButtons(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  buttons = {}
  if S.mode == "playing" then
    addBuildButton(16, h - 60, "1", "Wall", "wall", S)
    addBuildButton(154, h - 60, "2", "Arrow Tower", "arrow_tower", S)
    addBuildButton(292, h - 60, "3", "Ballista", "ballista", S)
    addBuildButton(430, h - 60, "4", "House", "house", S)
    addSelectionPanel(S, w, h)
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
    if not b.panel and pointInRect(mx, my, b) then
      if b.action == "restart" then
        S.reset()
      elseif b.villagerJob then
        Villagers.setJob(b.villager, b.villagerJob)
      elseif b.crewAssign then
        Villagers.assignCrew(b.crewAssign)
      elseif b.crewUnassign then
        Villagers.unassignCrew(b.crewUnassign)
      elseif b.buildType then
        if b.disabled then return true end
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
  local bg = b.active and { 0.45, 0.25, 0.55 } or { 0.16, 0.13, 0.22 }
  local fg = b.active and { 0.75, 0.5, 0.85 } or { 0.45, 0.42, 0.55 }
  if b.disabled then
    bg = { 0.10, 0.09, 0.13 }
    fg = { 0.28, 0.26, 0.33 }
  end
  love.graphics.setColor(bg[1], bg[2], bg[3], b.panel and 0.92 or 1)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 4)
  love.graphics.setColor(fg[1], fg[2], fg[3])
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 4)
  love.graphics.setFont(debugFont)
  if b.sub then
    love.graphics.print(b.label, b.x + 8, b.y + 5)
    love.graphics.print(b.sub, b.x + 8, b.y + 24)
  else
    local tw = debugFont:getWidth(b.label)
    love.graphics.print(b.label, b.x + (b.w - tw) / 2, b.y + (b.h - debugFont:getHeight()) / 2)
  end
end

local function villagerHit(S, wx, wy)
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead then
      local dx, dy = v.x - wx, v.y - wy
      if dx * dx + dy * dy < 144 then return v end
    end
  end
  return nil
end

local function worldTooltip(S, mx, my)
  local wx, wy = Camera.toWorld(mx, my)
  local v = villagerHit(S, wx, wy)
  if v then
    local carry = v.carry > 0 and (" · carrying " .. v.carry .. " " .. v.carryRes) or ""
    return ("Servant · %s%s · hunger %d%%"):format(Villagers.jobLabel(v), carry, v.hunger)
  end
  local gx, gy = Grid.worldToTile(wx, wy)
  local b = Buildings.at(gx, gy)
  if b == 0 then
    for i = 1, Buildings.n do
      local dx, dy = Buildings.x[i] - wx, Buildings.y[i] - wy
      if dx * dx + dy * dy < 324 then b = i; break end
    end
  end
  if b > 0 then
    local kind = Buildings.kind[b]
    if not Buildings.built[b] then
      local d = buildingData[kind]
      return ("%s · building %d%%"):format(KIND_LABEL[kind], math.floor(100 * Buildings.progress[b] / d.buildTime))
    elseif Buildings.isTower[b] then
      local status = Buildings.crewCount[b] >= Buildings.maxCrew[b]
        and ("crew %d/%d"):format(Buildings.crewCount[b], Buildings.maxCrew[b])
        or ("OFFLINE · crew %d/%d"):format(Buildings.crewCount[b], Buildings.maxCrew[b])
      return ("%s · %s"):format(KIND_LABEL[kind], status)
    elseif kind == "house" then
      return "House · +2 population"
    end
  end
  local list = Nodes.list
  for i = 1, #list do
    local nd = list[i]
    local dx, dy = nd.x - wx, nd.y - wy
    if dx * dx + dy * dy < (nd.r + 6) * (nd.r + 6) then
      local names = { tree = "Tree", berry = "Berry bush", rock = "Rock" }
      return ("%s · %d %s"):format(names[nd.kind], math.floor(nd.amount), nd.res)
    end
  end
  return nil
end

local function drawTooltip(text, mx, my)
  love.graphics.setFont(debugFont)
  local tw = debugFont:getWidth(text)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local tx, ty = math.min(mx + 14, w - tw - 16), math.min(my + 18, h - 28)
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", tx - 6, ty - 3, tw + 12, 20, 3)
  love.graphics.setColor(0.9, 0.87, 0.95)
  love.graphics.print(text, tx, ty)
end

local function drawSelectionPanel(S)
  local sel = S.selection
  if not sel then return end
  local px, py = love.graphics.getWidth() - 236, love.graphics.getHeight() - 200
  love.graphics.setFont(debugFont)
  love.graphics.setColor(0.88, 0.85, 0.95)
  if sel.villager then
    local v = sel.villager
    love.graphics.print(("Servant (%s) · %s"):format(v.sex == "f" and "woman" or "man", Villagers.jobLabel(v)), px + 10, py + 8)
    love.graphics.setColor(0.12, 0.10, 0.15)
    love.graphics.rectangle("fill", px + 10, py + 126, 200, 14, 2)
    love.graphics.setColor(0.85, 0.65, 0.25)
    love.graphics.rectangle("fill", px + 10, py + 126, 200 * math.min(1, v.hunger / 100), 14, 2)
    love.graphics.setColor(0.88, 0.85, 0.95)
    love.graphics.print(("hunger %d%%  ·  hp %d"):format(v.hunger, math.ceil(v.hp)), px + 16, py + 127)
  elseif sel.building then
    local i = sel.building
    if i > Buildings.n then return end
    local kind = Buildings.kind[i]
    local d = buildingData[kind]
    if not Buildings.built[i] then
      love.graphics.print(("%s · building %d%%"):format(KIND_LABEL[kind], math.floor(100 * Buildings.progress[i] / d.buildTime)), px + 10, py + 8)
    elseif Buildings.isTower[i] then
      local staffed = Buildings.crewCount[i] >= Buildings.maxCrew[i]
      love.graphics.print(("%s · crew %d/%d%s"):format(KIND_LABEL[kind], Buildings.crewCount[i], Buildings.maxCrew[i], staffed and "" or " · OFFLINE"), px + 10, py + 8)
      love.graphics.setColor(0.6, 0.58, 0.68)
      love.graphics.print(staffed and "firing" or "needs a servant to fire", px + 10, py + 24)
    elseif kind == "house" then
      love.graphics.print("House · +2 population cap", px + 10, py + 8)
    end
  end
end

local function drawDebug(S)
  love.graphics.setFont(debugFont)
  local x = love.graphics.getWidth() - 230
  local lines = {
    ("fps: %d"):format(love.timer.getFPS()),
    ("enemies: %d"):format(S.enemies.n),
    ("servants: %d / %d"):format(S.villagers.count(), Buildings.popCap()),
    ("buildings: %d"):format(S.buildings.n),
    ("walls: %d"):format(S.walls.n),
    ("projectiles: %d"):format(S.projectiles.n),
    ("shots: %d"):format(S.towers.shots),
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
  drawSelectionPanel(S)

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

    love.graphics.setFont(debugFont)
    love.graphics.print(("Wood %d   Food %d   Stone %d   Servants %d/%d")
      :format(S.stock.wood, S.stock.food, S.stock.stone, S.villagers.count(), Buildings.popCap()), 16, 40)

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

    love.graphics.setFont(debugFont)
    love.graphics.print("1 wall · 2 tower · 3 ballista · 4 house · click servant: jobs · click defense: crew · F3 debug · R restart", 16, h - 74)

    if S.buildMode then
      local hint = "Click to place " .. S.buildType .. "  ·  right-click to cancel"
      love.graphics.print(hint, w / 2 - debugFont:getWidth(hint) / 2, h - 28)
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
      local sub = "M3 slice complete"
      love.graphics.print(sub, w / 2 - smallFont:getWidth(sub) / 2, h / 2 - 10)
    end
  end

  if S.mode == "playing" then
    local mx, my = love.mouse.getPosition()
    local text = worldTooltip(S, mx, my)
    if text then drawTooltip(text, mx, my) end
  end
end

return UI
