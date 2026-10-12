local Camera = require("src.core.camera")
local Grid = require("src.sim.grid")
local Buildings = require("src.sim.buildings")
local Villagers = require("src.sim.villagers")
local Nodes = require("src.sim.nodes")
local Enemies = require("src.sim.enemies")
local Checklist = require("src.sim.checklist")
local Particles = require("src.fx.particles")
local Audio = require("src.audio.audio")
local enemyData = require("src.data.enemies")
local buildingData = require("src.data.buildings")
local resData = require("src.data.resources")

local UI = {}

local bigFont, medFont, smallFont, debugFont
local buttons = {}
local selPanel = { x = 0, y = 0, w = 220, h = 110 }

local KIND_LABEL = {
  arrow_tower = "Arrow Tower",
  ballista = "Ballista",
  house = "House",
  wall = "Wall",
  altar = "Altar",
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
  local locked = d.unlock and not Checklist.isDone(d.unlock)
  local affordable = true
  if d.cost then
    for res, amt in pairs(d.cost) do
      if (S.stock[res] or 0) < amt then affordable = false end
    end
  end
  buttons[#buttons + 1] = {
    x = x, y = y, w = 130, h = 44,
    label = label .. " [" .. key .. "]",
    sub = locked and ("Locked: " .. Checklist.entryName(d.unlock)) or costLabel(d.cost),
    buildType = buildType,
    disabled = locked or not affordable,
    locked = locked,
  }
end

local function addSelectionPanel(S, w, h)
  local sel = S.selection
  if not sel then return end
  local px = w - 236
  if sel.villager then
    local v = sel.villager
    local py = h - 200
    selPanel = { x = px, y = py, w = 220, h = 150 }
    buttons[#buttons + 1] = { x = px, y = py, w = 220, h = 150, panel = true }
    if v.age ~= "child" then
      local jobs = { "idle", "wood", "food", "stone", "build" }
      for i, job in ipairs(jobs) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        buttons[#buttons + 1] = {
          x = px + 10 + col * 103, y = py + 52 + row * 32, w = 98, h = 27,
          label = JOB_LABEL[job],
          villagerJob = job,
          villager = v,
          active = v.job == job,
        }
      end
    end
  elseif sel.building then
    local i = sel.building
    if i > Buildings.n then return end
    local kind = Buildings.kind[i]
    local built = Buildings.built[i]
    if kind == "house" and built then
      local ph = 150
      local py = h - 250
      selPanel = { x = px, y = py, w = 220, h = ph }
      buttons[#buttons + 1] = { x = px, y = py, w = 220, h = ph, panel = true }
      local c = Villagers.coupleAt(i)
      if c then
        buttons[#buttons + 1] = {
          x = px + 10, y = py + 44, w = 200, h = 27,
          label = c.chosen and "The vessel" or "Choose as vessel",
          chooseCouple = i,
          active = c.chosen,
          disabled = c.conceived or c.conceiving,
        }
        buttons[#buttons + 1] = {
          x = px + 10, y = py + 78, w = 200, h = 27,
          label = "Unbind",
          unbindCouple = i,
          disabled = c.conceived or c.conceiving or (c.chosen and c.pregnant),
        }
      else
        buttons[#buttons + 1] = {
          x = px + 10, y = py + 44, w = 200, h = 27,
          label = "Bind a couple",
          bindCouple = i,
          disabled = not (Villagers.freeAdult("m") and Villagers.freeAdult("f")),
        }
      end
    elseif kind == "altar" and built then
      local showConceive = Checklist.isDone("stars_right")
      local rows = showConceive and 3 or 2
      local ph = 34 + rows * 36
      local py = h - ph - 60
      selPanel = { x = px, y = py, w = 220, h = ph }
      buttons[#buttons + 1] = { x = px, y = py, w = 220, h = ph, panel = true }
      local rites = Checklist.ritualUnlocked()
      local by = py + 34
      buttons[#buttons + 1] = {
        x = px + 10, y = by, w = 200, h = 28,
        label = "Burn harvest (" .. Checklist.HARVEST_COST .. "f)",
        ritualBurn = true,
        disabled = not rites or (S.stock.food or 0) < Checklist.HARVEST_COST,
      }
      by = by + 36
      buttons[#buttons + 1] = {
        x = px + 10, y = by, w = 200, h = 28,
        label = "Sacrifice a servant",
        ritualSacrifice = i,
        disabled = not rites or Villagers.count() <= 1 or Villagers.pickSacrifice(i) == nil,
      }
      if showConceive then
        by = by + 36
        buttons[#buttons + 1] = {
          x = px + 10, y = by, w = 200, h = 28,
          label = "Conceive the Antichrist",
          ritualConceive = i,
          disabled = not Villagers.canConceive(),
        }
      end
    else
      local py = h - 200
      selPanel = { x = px, y = py, w = 220, h = 110 }
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
end

function UI.buildButtons(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  buttons = {}
  if S.mode == "playing" then
    addBuildButton(16, h - 60, "1", "Wall", "wall", S)
    addBuildButton(154, h - 60, "2", "Arrow Tower", "arrow_tower", S)
    addBuildButton(292, h - 60, "3", "Ballista", "ballista", S)
    addBuildButton(430, h - 60, "4", "House", "house", S)
    addBuildButton(568, h - 60, "5", "Altar", "altar", S)
    addSelectionPanel(S, w, h)
    if Villagers.request then
      local bw, bh = 150, 34
      local by = h / 2 + 30
      buttons[#buttons + 1] = { x = w / 2 - bw - 10, y = by, w = bw, h = bh, label = "Allow", birthAllow = true }
      buttons[#buttons + 1] = { x = w / 2 + 10, y = by, w = bw, h = bh, label = "Deny", birthDeny = true }
    end
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
      if b.disabled then
        Audio.play("error")
        return true
      end
      Audio.play("click")
      if b.action == "restart" then
        S.reset()
      elseif b.villagerJob then
        Villagers.setJob(b.villager, b.villagerJob)
      elseif b.crewAssign then
        Villagers.assignCrew(b.crewAssign)
      elseif b.crewUnassign then
        Villagers.unassignCrew(b.crewUnassign)
      elseif b.ritualBurn then
        Checklist.burnHarvest(S)
      elseif b.ritualSacrifice then
        local v = Villagers.pickSacrifice(b.ritualSacrifice)
        if v then Villagers.startSacrifice(v, b.ritualSacrifice) end
      elseif b.ritualConceive then
        Villagers.startConception(b.ritualConceive)
      elseif b.bindCouple then
        Villagers.bindCouple(b.bindCouple)
      elseif b.unbindCouple then
        Villagers.unbind(b.unbindCouple)
      elseif b.chooseCouple then
        Villagers.choose(b.chooseCouple)
      elseif b.birthAllow then
        Villagers.allowBirth()
      elseif b.birthDeny then
        Villagers.denyBirth()
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
    if v.age == "child" then
      return ("Child · grows up in %d months"):format(math.max(0, v.growLeft))
    end
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
    elseif kind == "altar" then
      return Checklist.ritualUnlocked() and "Altar · dark rituals" or "Altar · the rites sleep"
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

local function coupleLabel(c)
  local m = c.man and (c.man.dead and "†" or "") or "†"
  local f = c.woman and (c.woman.dead and "†" or "") or "†"
  return ("Man%s · Woman%s"):format(m, f)
end

local function drawSelectionPanel(S)
  local sel = S.selection
  if not sel then return end
  local px, py = selPanel.x, selPanel.y
  love.graphics.setFont(debugFont)
  love.graphics.setColor(0.88, 0.85, 0.95)
  if sel.villager then
    local v = sel.villager
    love.graphics.print(("Servant (%s) · %s"):format(v.sex == "f" and "woman" or "man", Villagers.jobLabel(v)), px + 10, py + 8)
    if v.age == "child" then
      love.graphics.setColor(0.75, 0.7, 0.85)
      love.graphics.print(("Child · grows up in %d months"):format(math.max(0, v.growLeft)), px + 10, py + 30)
    end
    local barY = v.age == "child" and py + 120 or py + 126
    love.graphics.setColor(0.12, 0.10, 0.15)
    love.graphics.rectangle("fill", px + 10, barY, 200, 14, 2)
    love.graphics.setColor(0.85, 0.65, 0.25)
    love.graphics.rectangle("fill", px + 10, barY, 200 * math.min(1, v.hunger / 100), 14, 2)
    love.graphics.setColor(0.88, 0.85, 0.95)
    love.graphics.print(("hunger %d%%  ·  hp %d"):format(v.hunger, math.ceil(v.hp)), px + 16, barY + 1)
  elseif sel.building then
    local i = sel.building
    if i > Buildings.n then return end
    local kind = Buildings.kind[i]
    local d = buildingData[kind]
    if not Buildings.built[i] then
      love.graphics.print(("%s · building %d%%"):format(KIND_LABEL[kind], math.floor(100 * Buildings.progress[i] / d.buildTime)), px + 10, py + 8)
    elseif kind == "altar" then
      love.graphics.print("Altar", px + 10, py + 8)
      love.graphics.setColor(0.6, 0.58, 0.68)
      local status
      if S.villagers.conceived then
        status = "the vessel quickens"
      elseif not Checklist.ritualUnlocked() then
        status = "the rites sleep"
      elseif Checklist.isDone("stars_right") then
        status = "name the vessel, then conceive"
      else
        status = "the ground thirsts"
      end
      love.graphics.print(status, px + 10, py + 22)
    elseif kind == "house" then
      love.graphics.print("House · +2 population cap", px + 10, py + 8)
      local c = Villagers.coupleAt(i)
      love.graphics.setColor(0.6, 0.58, 0.68)
      if c then
        local status
        if c.conceived then
          status = ("carrying the Antichrist · %d months"):format(math.max(0, c.monthsLeft))
        elseif c.pregnant then
          status = ("expecting · %d months"):format(math.max(0, c.monthsLeft))
        elseif c.conceiving then
          status = "walking to the altar"
        elseif c.pending then
          status = "asking for a child"
        elseif c.chosen then
          status = "THE VESSEL · awaits the ritual"
        else
          status = "bound"
        end
        love.graphics.print(status, px + 10, py + 24)
      else
        love.graphics.print("no couple bound", px + 10, py + 24)
      end
    elseif Buildings.isTower[i] then
      local staffed = Buildings.crewCount[i] >= Buildings.maxCrew[i]
      love.graphics.print(("%s · crew %d/%d%s"):format(KIND_LABEL[kind], Buildings.crewCount[i], Buildings.maxCrew[i], staffed and "" or " · OFFLINE"), px + 10, py + 8)
      love.graphics.setColor(0.6, 0.58, 0.68)
      love.graphics.print(staffed and "firing" or "needs a servant to fire", px + 10, py + 24)
    end
  end
end

local function drawChecklist(S)
  if S.checklistVisible == false then return 0 end
  local entries, stateOf = Checklist.list()
  local rows = {}
  for i = 1, #entries do
    local e = entries[i]
    local st = stateOf[e.id]
    if st == "done" or st == "active" then
      rows[#rows + 1] = e
    end
  end
  local x = love.graphics.getWidth() - 244
  local y = 8
  local h = 28 + #rows * 32
  love.graphics.setColor(0.08, 0.06, 0.12, 0.88)
  love.graphics.rectangle("fill", x, y, 228, h, 4)
  love.graphics.setColor(0.55, 0.32, 0.68)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, 228, h, 4)
  love.graphics.setFont(debugFont)
  love.graphics.setColor(0.85, 0.7, 0.95)
  love.graphics.print("THE CUSTOM", x + 10, y + 6)
  local ry = y + 24
  for i = 1, #rows do
    local e = rows[i]
    local done = stateOf[e.id] == "done"
    love.graphics.setColor(done and 0.45 or 0.92, done and 0.7 or 0.86, done and 0.5 or 0.95)
    local mark = done and "✓ " or "· "
    love.graphics.print(mark .. e.name, x + 10, ry)
    if not done then
      love.graphics.setColor(0.62, 0.55, 0.7)
      local line = e.desc
      if e.progress then
        local cur, mx = e.progress(S)
        line = line .. ("  %d/%d"):format(cur, mx)
      end
      love.graphics.print(line, x + 18, ry + 13)
    end
    ry = ry + 32
  end
  return h
end

local function drawToasts()
  local list = Checklist.toasts
  if #list == 0 then return end
  local w = love.graphics.getWidth()
  love.graphics.setFont(smallFont)
  local y = 64
  for i = 1, #list do
    local t = list[i]
    local a = math.min(1, t.t)
    love.graphics.setColor(0.72, 0.4, 0.85, a)
    love.graphics.print(t.text, w / 2 - smallFont:getWidth(t.text) / 2, y)
    if t.sub then
      love.graphics.setFont(debugFont)
      love.graphics.setColor(0.9, 0.82, 0.95, a)
      love.graphics.print(t.sub, w / 2 - debugFont:getWidth(t.sub) / 2, y + 20)
      love.graphics.setFont(smallFont)
      y = y + 40
    else
      y = y + 22
    end
  end
end

local function drawDebug(S, y0)
  love.graphics.setFont(debugFont)
  local x = love.graphics.getWidth() - 230
  local lines = {
    ("fps: %d"):format(love.timer.getFPS()),
    ("date: year %d, month %d%s"):format(S.waves.calendar.year, S.waves.calendar.month,
      S.waves.calendar.apocalypse and " (end times)" or ""),
    ("wave phase: %s"):format(S.waves.phase),
    ("enemies: %d"):format(S.enemies.n),
    ("servants: %d / %d"):format(S.villagers.count(), Buildings.popCap()),
    ("buildings: %d"):format(S.buildings.n),
    ("walls: %d"):format(S.walls.n),
    ("projectiles: %d"):format(S.projectiles.n),
    ("particles: %d"):format(Particles.n),
    ("shots: %d"):format(S.towers.shots),
    ("step: %.2f ms"):format(S.stats.stepMs),
    ("sim: %.2f ms"):format(S.stats.simMs),
    ("draw: %.2f ms"):format(S.stats.drawMs),
    ("flow rebakes: %d"):format(S.flow.rebakes),
  }
  local top = y0 or 8
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", x - 8, top, 226, #lines * 16 + 12)
  love.graphics.setColor(0.7, 0.95, 0.7)
  for i, l in ipairs(lines) do
    love.graphics.print(l, x, top + 6 + (i - 1) * 16)
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.print("K +1k  shift+K +10k  F3 close", x, top + 6 + #lines * 16)
end

local function drawBirthModal()
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local bw, bh = 440, 130
  local bx, by = w / 2 - bw / 2, h / 2 - bh / 2
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(0.10, 0.07, 0.14, 0.96)
  love.graphics.rectangle("fill", bx, by, bw, bh, 6)
  love.graphics.setColor(0.62, 0.28, 0.72)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", bx, by, bw, bh, 6)
  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.9, 0.86, 0.95)
  local t = "A bound couple asks to bear a child"
  love.graphics.print(t, w / 2 - smallFont:getWidth(t) / 2, by + 20)
  love.graphics.setFont(debugFont)
  love.graphics.setColor(0.7, 0.64, 0.78)
  local t2 = "Approved births feed both the flock and the custom."
  love.graphics.print(t2, w / 2 - debugFont:getWidth(t2) / 2, by + 48)
end

function UI.draw(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  if S.flash and S.flash > 0 then
    love.graphics.setColor(0.55, 0.05, 0.10, S.flash)
    love.graphics.rectangle("fill", 0, 0, w, h)
  end
  if S.mode == "playing" and Villagers.request then drawBirthModal() end
  local bs = UI.buildButtons(S)
  for _, b in ipairs(bs) do
    if b.buildType then b.active = S.buildMode and S.buildType == b.buildType end
    drawButton(b)
  end
  drawSelectionPanel(S)

  if S.mode == "playing" then
    local wl = S.waves
    local cal = wl.calendar
    love.graphics.setColor(0.9, 0.86, 0.95)
    love.graphics.setFont(medFont)
    local info
    if wl.phase == "wave" then
      info = cal.apocalypse
        and ("END TIMES HORDE %d  —  enemies: %d"):format(wl.number, S.enemies.n)
        or ("HORDE — YEAR %d  —  enemies: %d"):format(wl.number, S.enemies.n)
    else
      local pv = wl:preview()
      info = ("%s in %ds  [Space to summon]"):format(pv.label, math.ceil(pv.secs))
    end
    love.graphics.print(info, 16, 12)

    love.graphics.setFont(debugFont)
    love.graphics.print(("Year %d · Month %d%s   Wood %d   Food %d   Stone %d   Servants %d/%d")
      :format(cal.year, cal.month, cal.apocalypse and "  ·  THE END TIMES" or "",
        S.stock.wood, S.stock.food, S.stock.stone, S.villagers.count(), Buildings.popCap()), 16, 40)

    if wl.phase == "village" then
      local pv = wl:preview()
      local parts = {}
      for _, kind in ipairs(pv.order) do
        local d = enemyData[kind]
        parts[#parts + 1] = pv.counts[kind] .. "× " .. (d and d.name or kind)
      end
      if pv.boss then
        local d = enemyData[pv.boss]
        parts[#parts + 1] = (d and d.name or pv.boss):upper()
      end
      local edgeOrder = { "N", "E", "S", "W" }
      local from = {}
      for _, e in ipairs(edgeOrder) do
        if pv.edges[e] then from[#from + 1] = e end
      end
      local line = "Next: " .. table.concat(parts, " · ")
      if #from > 0 and #from < 4 then line = line .. "  —  from " .. table.concat(from, ", ") end
      love.graphics.setColor(0.95, 0.75, 0.55)
      love.graphics.print(line, 16, 58)
      love.graphics.setColor(0.9, 0.86, 0.95)
    end

    if wl.bossKind and wl.phase == "wave" then
      local E = S.enemies
      local ki = Enemies.kindIndex[wl.bossKind]
      local hp, mx = 0, 0
      for i = 1, E.n do
        if E.kind[i] == ki then
          hp = hp + E.hp[i]
          mx = mx + E.maxHp[i]
        end
      end
      if mx > 0 then
        local bw, bh = 400, 12
        local bx, by = w / 2 - bw / 2, 40
        love.graphics.setColor(0.10, 0.10, 0.13)
        love.graphics.rectangle("fill", bx, by, bw, bh, 3)
        love.graphics.setColor(0.85, 0.15, 0.2)
        love.graphics.rectangle("fill", bx, by, bw * (hp / mx), bh, 3)
        love.graphics.setColor(0.95, 0.85, 0.9)
        love.graphics.setFont(smallFont)
        local d = enemyData[wl.bossKind]
        local bl = (d and d.name or wl.bossKind):upper()
        love.graphics.print(bl, w / 2 - smallFont:getWidth(bl) / 2, by + bh + 2)
      end
    end

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
    love.graphics.print("1 wall · 2 tower · 3 ballista · 4 house · 5 altar · C custom · click altar: rites · F3 debug · R restart", 16, h - 74)

    if S.buildMode then
      local hint = "Click to place " .. S.buildType .. "  ·  right-click to cancel"
      love.graphics.print(hint, w / 2 - debugFont:getWidth(hint) / 2, h - 28)
    end

    local panelH = drawChecklist(S)
    drawToasts()
    if S.debug then drawDebug(S, 8 + panelH + 8) end
  elseif S.mode == "gameover" or S.mode == "victory" then
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setFont(bigFont)
    if S.mode == "gameover" then
      love.graphics.setColor(0.9, 0.2, 0.22)
      local titles = {
        fallen = "THE VILLAGE HAS FALLEN",
        extinct = "THE BLOODLINE ENDS",
        vessel = "THE VESSEL IS LOST",
        no_vessel = "NO VESSEL REMAINS",
      }
      local subs = {
        extinct = "No servant draws breath. The cult dies with them.",
        vessel = "The chosen one perished. The Antichrist will not come.",
        no_vessel = "The custom demands a couple, but none remain.",
      }
      local t = titles[S.ending] or titles.fallen
      love.graphics.print(t, w / 2 - bigFont:getWidth(t) / 2, h / 2 - 70)
      local sub = subs[S.ending]
      if sub then
        love.graphics.setFont(smallFont)
        love.graphics.setColor(0.85, 0.78, 0.9)
        love.graphics.print(sub, w / 2 - smallFont:getWidth(sub) / 2, h / 2 - 10)
      end
    else
      love.graphics.setColor(0.72, 0.4, 0.85)
      local born = S.ending == "birth"
      local t = born and "THE ANTICHRIST IS BORN" or "THE HORDE IS SATED... FOR NOW"
      love.graphics.print(t, w / 2 - bigFont:getWidth(t) / 2, h / 2 - 70)
      love.graphics.setFont(smallFont)
      love.graphics.setColor(0.8, 0.75, 0.9)
      local sub = born and "Nine months of fire. The prophecy is fulfilled." or "The horde years are survived... the prophecy stirs"
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
