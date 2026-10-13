local Camera = require("src.core.camera")
local Grid = require("src.sim.grid")
local Buildings = require("src.sim.buildings")
local Villagers = require("src.sim.villagers")
local Nodes = require("src.sim.nodes")
local Enemies = require("src.sim.enemies")
local Checklist = require("src.sim.checklist")
local Ages = require("src.sim.ages")
local Research = require("src.sim.research")
local Particles = require("src.fx.particles")
local Audio = require("src.audio.audio")
local enemyData = require("src.data.enemies")
local buildingData = require("src.data.buildings")
local vData = require("src.data.villagers")

local UI = {}

-- Layout regions.
local TOP_H = 100
local BOTTOM_H = 138

local bigFont, medFont, smallFont, debugFont
local buttons = {}
local actionTitle = ""

local CATEGORY_LABEL = {
  defense = "Defense",
  economy = "Economy",
  ritual = "Ritual",
  research = "Research",
}

local JOB_LABEL = {
  idle = "Idle",
  wood = "Wood",
  food = "Food",
  stone = "Stone",
  build = "Build",
}

local function kindLabel(kind)
  local d = buildingData[kind]
  return (d and d.name) or kind
end

local function pointInRect(px, py, r)
  return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

local function costLabel(cost)
  if not cost then return "" end
  local parts = {}
  for _, res in ipairs({ "wood", "food", "stone", "bone" }) do
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

-- ---------------------------------------------------------------------------
-- Command bar buttons
-- ---------------------------------------------------------------------------

local function addPaletteButton(x, y, kind, hotkey, S)
  local d = buildingData[kind]
  local lockLabel = Ages.lockLabel(kind)
  local locked = lockLabel ~= nil
  local affordable = true
  if d.cost then
    for res, amt in pairs(d.cost) do
      if (S.stock[res] or 0) < amt then affordable = false end
    end
  end
  buttons[#buttons + 1] = {
    x = x, y = y, w = 136, h = 42,
    label = (d.name or kind) .. (hotkey and (" [" .. hotkey .. "]") or ""),
    sub = locked and ("Locked: " .. lockLabel) or costLabel(d.cost),
    buildType = kind,
    disabled = locked or not affordable,
  }
end

-- Unlocked buildable kinds within a category (age-gated ones are hidden).
local function unlockedIn(cat)
  local out = {}
  for _, kind in ipairs(Buildings.buildIn(cat)) do
    if Ages.unlocked(kind) then out[#out + 1] = kind end
  end
  return out
end

local function ensureCategory(S)
  if S.buildCategory and #unlockedIn(S.buildCategory) > 0 then return end
  for _, cat in ipairs(Buildings.categories()) do
    if #unlockedIn(cat) > 0 then
      S.buildCategory = cat
      return
    end
  end
  S.buildCategory = nil
end

local function buildTabs(S)
  ensureCategory(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local by = h - BOTTOM_H
  local x = 12
  for _, cat in ipairs(Buildings.categories()) do
    if #unlockedIn(cat) > 0 then
      buttons[#buttons + 1] = {
        x = x, y = by + 8, w = 108, h = 26,
        label = CATEGORY_LABEL[cat] or cat,
        tab = cat,
        active = S.buildCategory == cat,
      }
      x = x + 108 + 6
    end
  end
end

local function buildPalette(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local by = h - BOTTOM_H
  local splitX = math.floor(w * 0.54)
  local list = unlockedIn(S.buildCategory)
  local bw, bh, gap = 136, 42, 8
  local leftW = splitX - 12
  local cols = math.max(1, math.floor((leftW + gap) / (bw + gap)))
  for i, kind in ipairs(list) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    addPaletteButton(12 + col * (bw + gap), by + 44 + row * (bh + gap), kind, i <= 9 and i or nil, S)
  end
end

local function buildGlobals(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local by = h - BOTTOM_H
  local gw, gap = 106, 6
  buttons[#buttons + 1] = {
    x = w - 12 - gw, y = by + 8, w = gw, h = 26,
    label = "Debug [F3]", debugToggle = true, active = S.debug,
  }
  buttons[#buttons + 1] = {
    x = w - 12 - gw - gap - gw, y = by + 8, w = gw, h = 26,
    label = "Custom [C]", checklistToggle = true, active = S.checklistVisible ~= false,
  }
end

local function buildActions(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local by = h - BOTTOM_H
  local splitX = math.floor(w * 0.54)
  local ax = splitX + 12
  local aw = w - ax - 12
  local colW, gap, btnH = 168, 6, 26
  local cols = math.max(1, math.floor((aw + gap) / (colW + gap)))
  local y0 = by + 44
  local idx = 0
  local function act(label, fields, disabled, active)
    local col = idx % cols
    local row = math.floor(idx / cols)
    local b = {
      x = ax + col * (colW + gap), y = y0 + row * (btnH + 4),
      w = colW, h = btnH, label = label, disabled = disabled, active = active,
    }
    if fields then for k, v in pairs(fields) do b[k] = v end end
    buttons[#buttons + 1] = b
    idx = idx + 1
  end

  actionTitle = "Click a servant, a building, or the heart"
  local sel = S.selection
  if not sel then return end

  if sel.heart then
    local a = Ages.age()
    local nxt = Ages.next()
    actionTitle = nxt and ("The Heart — " .. a.name .. " -> " .. nxt.name) or ("The Heart — " .. a.name)
    if not Ages.isEnd() then
      act("Ascend to " .. ((nxt and nxt.name or ""):gsub("Age of ", "")), { ascend = true }, not Ages.canAscend(S))
    end
    if S.village.hp < S.village.maxHp then
      local heal = buildingData.village_center.sacrificeHeal or 40
      act(("Heal (+%d) — sacrifice"):format(heal), { heartHeal = true }, Villagers.pickHeartSacrifice() == nil)
    end
  elseif sel.villager then
    local v = sel.villager
    if v.age == "child" then
      actionTitle = ("Child — grows up in %d months"):format(math.max(0, v.growLeft))
    else
      actionTitle = ("Servant — %s"):format(Villagers.jobLabel(v))
      for _, job in ipairs({ "idle", "wood", "food", "stone", "build" }) do
        act(JOB_LABEL[job], { villagerJob = job, villager = v }, v.confined, v.job == job)
      end
    end
  elseif sel.building then
    local bi = sel.building
    if bi > Buildings.n then return end
    local kind = Buildings.kind[bi]
    local d = buildingData[kind]
    local built = Buildings.built[bi]
    if not built then
      actionTitle = ("%s — building %d%%"):format(kindLabel(kind), math.floor(100 * Buildings.progress[bi] / d.buildTime))
    elseif kind == "house" then
      local c = Villagers.coupleAt(bi)
      local vesselStage = Ages.reached("end")
      actionTitle = "House — " .. (c and "bound" or "empty") .. " · +2 pop"
      if c then
        if not c.pregnant and not c.conceived and not c.conceiving then
          local cost = vData.birthCost or 0
          local canChild = (S.stock.food or 0) >= cost and Villagers.population() < Buildings.popCap()
          act("Make a child (" .. cost .. "f)", { makeChild = bi }, not canChild)
        end
        if vesselStage and not (c.conceived or c.conceiving) then
          act(c.chosen and "Unchoose vessel" or "Choose as vessel", { chooseCouple = bi }, false, c.chosen)
        end
        act("Unbind", { unbindCouple = bi }, c.conceived or c.conceiving or (c.chosen and c.pregnant))
      else
        act("Bind a couple", { bindCouple = bi }, not (Villagers.freeAdult("m") and Villagers.freeAdult("f")))
      end
    elseif Buildings.role[bi] == "graveyard" then
      actionTitle = ("Graveyard — %d graves"):format(Buildings.graves[bi] or 0)
      local cost = (d.raiseCost and d.raiseCost.bone) or 0
      act("Raise undead (" .. cost .. "b)", { raiseUndead = bi }, (S.stock.bone or 0) < cost)
    elseif Buildings.role[bi] == "research" then
      local projId = Buildings.project[bi]
      local pname = projId and Research.def(projId)
      actionTitle = ("%s — %s"):format(kindLabel(kind), pname and pname.name or "idle")
      for _, e in ipairs(Research.available(kind)) do
        local afford = true
        if e.def.cost then
          for res, amt in pairs(e.def.cost) do
            if (S.stock[res] or 0) < amt then afford = false end
          end
        end
        act(e.def.name, { researchStart = e.id, researchIndex = bi }, (not afford) or projId ~= nil)
      end
      act("Assign researcher", { resAssign = bi },
        (Buildings.researchers[bi] or 0) >= (d.researchSlots or 0) or Villagers.idleAdults() == 0)
      act("Unassign researcher", { resUnassign = bi }, (Buildings.researchers[bi] or 0) == 0)
      if d.upgradeTo then
        local utd = buildingData[d.upgradeTo.kind]
        act("Upgrade: " .. (utd and utd.name or d.upgradeTo.kind), { upgradeBuilding = bi }, not S.canAfford(d.upgradeTo.cost))
      end
    elseif kind == "altar" then
      local rites = Checklist.ritualUnlocked()
      actionTitle = "Altar — " .. (rites and "rites awake" or "the rites sleep")
      act("Burn harvest (" .. Checklist.HARVEST_COST .. "f)", { ritualBurn = true }, not rites or (S.stock.food or 0) < Checklist.HARVEST_COST)
      act("Sacrifice a servant", { ritualSacrifice = bi }, not rites or Villagers.count() <= 1 or Villagers.pickSacrifice(bi) == nil)
      if Ages.reached("end") then
        act("Conceive the Antichrist", { ritualConceive = bi }, not Villagers.canConceive())
      end
    elseif Buildings.isTower[bi] then
      actionTitle = ("%s — crew %d/%d"):format(kindLabel(kind), Buildings.crewCount[bi], Buildings.maxCrew[bi])
      act("Assign", { crewAssign = bi }, Villagers.count() == 0)
      act("Unassign", { crewUnassign = bi }, Buildings.crewCount[bi] == 0)
    else
      actionTitle = kindLabel(kind)
    end
  end
end

function UI.buildButtons(S)
  buttons = {}
  if S.mode == "playing" then
    buildTabs(S)
    buildPalette(S)
    buildActions(S)
    buildGlobals(S)
  else
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    buttons[#buttons + 1] = { x = w / 2 - 95, y = h / 2 + 56, w = 190, h = 44, label = "Restart [R]", action = "restart" }
  end
  return buttons
end

function UI.handleClick(mx, my, S)
  for _, b in ipairs(UI.buildButtons(S)) do
    if pointInRect(mx, my, b) then
      if b.disabled then
        Audio.play("error")
        return true
      end
      Audio.play("click")
      if b.action == "restart" then
        S.reset()
      elseif b.tab then
        S.buildCategory = b.tab
      elseif b.checklistToggle then
        S.checklistVisible = not (S.checklistVisible ~= false)
      elseif b.debugToggle then
        S.debug = not S.debug
      elseif b.ascend then
        Ages.ascend(S)
      elseif b.heartHeal then
        local v = Villagers.pickHeartSacrifice()
        if v then Villagers.startHeartSacrifice(v, "heal") end
      elseif b.villagerJob then
        Villagers.setJob(b.villager, b.villagerJob)
      elseif b.crewAssign then
        Villagers.assignCrew(b.crewAssign)
      elseif b.crewUnassign then
        Villagers.unassignCrew(b.crewUnassign)
      elseif b.raiseUndead then
        local d = buildingData[Buildings.kind[b.raiseUndead]]
        local cost = (d.raiseCost and d.raiseCost.bone) or 0
        if (S.stock.bone or 0) >= cost then
          S.stock.bone = S.stock.bone - cost
          Villagers.spawnUndead(Buildings.x[b.raiseUndead], Buildings.y[b.raiseUndead])
          Audio.play("ritual")
        end
      elseif b.researchStart then
        Research.start(S, b.researchIndex, b.researchStart)
      elseif b.resAssign then
        Villagers.assignResearcher(b.resAssign)
      elseif b.resUnassign then
        Villagers.unassignResearcher(b.resUnassign)
      elseif b.upgradeBuilding then
        local i = b.upgradeBuilding
        local d = buildingData[Buildings.kind[i]]
        if d and d.upgradeTo and S.canAfford(d.upgradeTo.cost) then
          for res, amt in pairs(d.upgradeTo.cost) do S.stock[res] = (S.stock[res] or 0) - amt end
          Buildings.upgrade(i, d.upgradeTo.kind)
          Audio.play("build_done")
        end
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
        local c = Villagers.coupleAt(b.chooseCouple)
        if c and c.chosen then
          Villagers.unchoose(b.chooseCouple)
        else
          Villagers.choose(b.chooseCouple)
        end
      elseif b.makeChild then
        Villagers.makeChild(b.makeChild, S)
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

-- ---------------------------------------------------------------------------
-- Shared drawing helpers
-- ---------------------------------------------------------------------------

local function drawButton(b)
  local bg = b.active and { 0.45, 0.25, 0.55 } or { 0.16, 0.13, 0.22 }
  local fg = b.active and { 0.75, 0.5, 0.85 } or { 0.45, 0.42, 0.55 }
  if b.disabled then
    bg = { 0.10, 0.09, 0.13 }
    fg = { 0.28, 0.26, 0.33 }
  end
  love.graphics.setColor(bg[1], bg[2], bg[3])
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 4)
  love.graphics.setColor(fg[1], fg[2], fg[3])
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 4)
  love.graphics.setFont(debugFont)
  if b.label then
    if b.sub then
      love.graphics.print(b.label, b.x + 8, b.y + 5)
      love.graphics.print(b.sub, b.x + 8, b.y + 24)
    else
      local tw = debugFont:getWidth(b.label)
      love.graphics.print(b.label, b.x + (b.w - tw) / 2, b.y + (b.h - debugFont:getHeight()) / 2)
    end
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
    return ("Servant · %s%s · hp %d/%d"):format(Villagers.jobLabel(v), carry, math.ceil(v.hp), v.maxHp)
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
      return ("%s · building %d%%"):format(kindLabel(kind), math.floor(100 * Buildings.progress[b] / d.buildTime))
    elseif Buildings.isTower[b] then
      local status = Buildings.crewCount[b] >= Buildings.maxCrew[b]
        and ("crew %d/%d"):format(Buildings.crewCount[b], Buildings.maxCrew[b])
        or ("OFFLINE · crew %d/%d"):format(Buildings.crewCount[b], Buildings.maxCrew[b])
      return ("%s · %s"):format(kindLabel(kind), status)
    elseif kind == "house" then
      return "House · +2 population"
    elseif kind == "altar" then
      return Checklist.ritualUnlocked() and "Altar · dark rituals" or "Altar · the rites sleep"
    elseif Buildings.role[b] == "research" then
      local p = Buildings.project[b]
      local def = p and Research.def(p)
      return kindLabel(kind) .. (def and (" · researching " .. def.name) or " · idle")
    elseif Buildings.role[b] == "graveyard" then
      return kindLabel(kind) .. (" · %d graves"):format(Buildings.graves[b] or 0)
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

-- ---------------------------------------------------------------------------
-- Top status bar
-- ---------------------------------------------------------------------------

local function drawHordeTimer(S)
  local w = love.graphics.getWidth()
  local wl = S.waves
  local cx = w / 2
  if wl.phase == "wave" then
    love.graphics.setFont(medFont)
    love.graphics.setColor(0.95, 0.35, 0.35)
    local t = wl.calendar.apocalypse
      and ("THE END TIMES — enemies %d"):format(S.enemies.n)
      or ("UNDER ATTACK — enemies %d"):format(S.enemies.n)
    love.graphics.print(t, cx - medFont:getWidth(t) / 2, 44)
  else
    local pv = wl:preview()
    local secs = math.max(0, math.floor(pv.secs))
    local t = ("HORDE IN %d:%02d"):format(math.floor(secs / 60), secs % 60)
    love.graphics.setFont(bigFont)
    love.graphics.setColor(secs <= 30 and { 0.95, 0.4, 0.4 } or { 0.84, 0.55, 0.95 })
    love.graphics.print(t, cx - bigFont:getWidth(t) / 2, 24)
  end
  love.graphics.setColor(0.9, 0.86, 0.95)
end

local function drawTopBar(S)
  local w = love.graphics.getWidth()
  love.graphics.setColor(0.055, 0.045, 0.085, 1.0)
  love.graphics.rectangle("fill", 0, 0, w, TOP_H)
  love.graphics.setColor(0.30, 0.22, 0.40)
  love.graphics.setLineWidth(1)
  love.graphics.line(0, TOP_H, w, TOP_H)

  local wl = S.waves
  local cal = wl.calendar
  love.graphics.setFont(debugFont)
  love.graphics.setColor(0.9, 0.86, 0.95)
  love.graphics.print(("%s · Year %d · Month %d%s")
    :format(Ages.age().name, cal.year, cal.month, cal.apocalypse and "  ·  THE END TIMES" or ""), 16, 10)

  -- Heart hp bar (left)
  local v = S.village
  local hbW, hbH = 240, 16
  love.graphics.setColor(0.10, 0.10, 0.13)
  love.graphics.rectangle("fill", 16, 32, hbW, hbH, 3)
  love.graphics.setColor(0.62, 0.28, 0.72)
  love.graphics.rectangle("fill", 16, 32, hbW * (v.hp / v.maxHp), hbH, 3)
  love.graphics.setColor(0.9, 0.86, 0.95)
  love.graphics.print(("Heart  %d / %d"):format(v.hp, v.maxHp), 22, 33)

  -- Resources (right)
  local res = ("Wood %d   Food %d   Stone %d   Bones %d   Servants %d/%d")
    :format(S.stock.wood, S.stock.food, S.stock.stone, S.stock.bone or 0, S.villagers.count(), Buildings.popCap())
  love.graphics.print(res, w - 16 - debugFont:getWidth(res), 10)

  drawHordeTimer(S)

  -- Next-horde preview (centred, under the clock)
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
    local from = {}
    for _, e in ipairs({ "N", "E", "S", "W" }) do
      if pv.edges[e] then from[#from + 1] = e end
    end
    local line = "Next: " .. table.concat(parts, " · ")
    if #from > 0 and #from < 4 then line = line .. "  —  from " .. table.concat(from, ", ") end
    love.graphics.setFont(debugFont)
    love.graphics.setColor(0.95, 0.75, 0.55)
    love.graphics.print(line, w / 2 - debugFont:getWidth(line) / 2, 82)
    love.graphics.setColor(0.9, 0.86, 0.95)
  end

  -- Boss bar (just below the top bar)
  if wl.bossKind and wl.phase == "wave" then
    local E = S.enemies
    local ki = Enemies.kindIndex[wl.bossKind]
    local hp, mx = 0, 0
    for i = 1, E.n do
      if E.kind[i] == ki then hp = hp + E.hp[i]; mx = mx + E.maxHp[i] end
    end
    if mx > 0 then
      local bw, bh = 400, 12
      local bx, by = w / 2 - bw / 2, TOP_H + 6
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
end

-- ---------------------------------------------------------------------------
-- Bottom command bar
-- ---------------------------------------------------------------------------

local function drawCommandBarBg()
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local by = h - BOTTOM_H
  love.graphics.setColor(0.055, 0.045, 0.085, 1.0)
  love.graphics.rectangle("fill", 0, by, w, BOTTOM_H)
  local splitX = math.floor(w * 0.54)
  love.graphics.setColor(0.30, 0.22, 0.40)
  love.graphics.setLineWidth(1)
  love.graphics.line(splitX, by + 6, splitX, h - 6)
  love.graphics.setFont(debugFont)
  love.graphics.setColor(0.85, 0.78, 0.95)
  love.graphics.print(actionTitle, splitX + 12, by + 24)
end

-- ---------------------------------------------------------------------------
-- Objectives panel / toasts / debug
-- ---------------------------------------------------------------------------

local function drawChecklist(S)
  if S.checklistVisible == false then return 0 end
  local entries, stateOf = Checklist.list()
  local cur = Ages.age()
  local rows = {}
  for i = 1, #entries do
    local e = entries[i]
    local st = stateOf[e.id]
    if (st == "done" or st == "active") and (e.age == cur.id or e.age == nil) then
      rows[#rows + 1] = e
    end
  end
  local x = love.graphics.getWidth() - 244
  local y = TOP_H + 8
  local h = 30 + #rows * 32 + 22
  love.graphics.setColor(0.08, 0.06, 0.12, 0.9)
  love.graphics.rectangle("fill", x, y, 228, h, 4)
  love.graphics.setColor(0.55, 0.32, 0.68)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, 228, h, 4)
  love.graphics.setFont(debugFont)
  love.graphics.setColor(0.85, 0.7, 0.95)
  love.graphics.print(cur.name:upper(), x + 10, y + 6)
  local ry = y + 28
  for i = 1, #rows do
    local e = rows[i]
    local done = stateOf[e.id] == "done"
    love.graphics.setColor(done and 0.45 or 0.92, done and 0.7 or 0.86, done and 0.5 or 0.95)
    love.graphics.print((done and "✓ " or "· ") .. e.name, x + 10, ry)
    if not done then
      love.graphics.setColor(0.62, 0.55, 0.7)
      local line = e.desc
      if e.progress then
        local a, b = e.progress(S)
        line = line .. ("  %d/%d"):format(a, b)
      end
      love.graphics.print(line, x + 18, ry + 13)
    end
    ry = ry + 32
  end
  love.graphics.setColor(0.95, 0.75, 0.55)
  local foot
  if Ages.isEnd() then
    foot = "the end times await"
  elseif Ages.objectivesDone(cur.id) then
    foot = "Ascend at the Heart  ->  " .. Ages.next().name:gsub("Age of ", "")
  else
    foot = "Next: " .. Ages.next().name
  end
  love.graphics.print(foot, x + 10, y + h - 18)
  return h
end

local function drawToasts()
  local list = Checklist.toasts
  if #list == 0 then return end
  local w = love.graphics.getWidth()
  love.graphics.setFont(smallFont)
  local y = TOP_H + 12
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

-- ---------------------------------------------------------------------------

function UI.draw(S)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  if S.flash and S.flash > 0 then
    love.graphics.setColor(0.55, 0.05, 0.10, S.flash)
    love.graphics.rectangle("fill", 0, 0, w, h)
  end

  local bs = UI.buildButtons(S)
  if S.mode == "playing" then
    drawTopBar(S)
    drawCommandBarBg()
  end
  for _, b in ipairs(bs) do
    if b.buildType then b.active = S.buildMode and S.buildType == b.buildType end
    drawButton(b)
  end

  if S.mode == "playing" then
    local panelH = drawChecklist(S)
    drawToasts()
    if S.buildMode then
      love.graphics.setFont(debugFont)
      love.graphics.setColor(0.9, 0.86, 0.95)
      local hint = "Click to place " .. (buildingData[S.buildType] and buildingData[S.buildType].name or S.buildType) .. "  ·  right-click to cancel"
      love.graphics.print(hint, w / 2 - debugFont:getWidth(hint) / 2, h - BOTTOM_H - 22)
    end
    if S.debug then drawDebug(S, TOP_H + 8 + panelH + 8) end
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
