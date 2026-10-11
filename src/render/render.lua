local Grid = require("src.sim.grid")
local Camera = require("src.core.camera")
local Walls = require("src.sim.walls")
local Buildings = require("src.sim.buildings")
local Villagers = require("src.sim.villagers")
local Nodes = require("src.sim.nodes")
local buildingData = require("src.data.buildings")

local Render = {}

local C = {
  bg = { 0.07, 0.05, 0.09 },
  tileA = { 0.10, 0.08, 0.12 },
  tileB = { 0.085, 0.065, 0.105 },
  border = { 0.30, 0.25, 0.40 },
  villageFill = { 0.26, 0.11, 0.33 },
  villageLine = { 0.62, 0.28, 0.72 },
  tower = { 0.62, 0.62, 0.70 },
  towerLine = { 0.16, 0.16, 0.22 },
  ballista = { 0.72, 0.62, 0.45 },
  house = { 0.52, 0.38, 0.26 },
  houseRoof = { 0.30, 0.20, 0.14 },
  construct = { 0.55, 0.50, 0.38 },
  wall = { 0.45, 0.42, 0.52 },
  wallLine = { 0.20, 0.18, 0.26 },
  wallFlash = { 1, 0.9, 0.7 },
  flash = { 1, 0.96, 0.90 },
  hpBar = { 0.35, 0.9, 0.4 },
  hpBarBack = { 0.12, 0.12, 0.14 },
  ghostOk = { 0.35, 0.9, 0.45, 0.35 },
  ghostBad = { 1, 0.28, 0.28, 0.35 },
  treeCanopy = { 0.16, 0.34, 0.18 },
  treeTrunk = { 0.38, 0.27, 0.16 },
  bush = { 0.18, 0.38, 0.20 },
  berry = { 0.85, 0.22, 0.30 },
  rock = { 0.55, 0.55, 0.62 },
  rockLine = { 0.32, 0.32, 0.38 },
  villagerM = { 0.45, 0.42, 0.82 },
  villagerF = { 0.82, 0.46, 0.70 },
  villagerLine = { 0.12, 0.10, 0.18 },
  crewGood = { 0.40, 0.90, 0.40 },
  crewBad = { 0.90, 0.30, 0.30 },
  offline = { 0.95, 0.25, 0.25 },
  select = { 0.95, 0.92, 1.0 },
}

local RES_COLOR = {
  wood = { 0.55, 0.38, 0.20 },
  food = { 0.90, 0.30, 0.35 },
  stone = { 0.65, 0.65, 0.72 },
}

local enemyBatch, enemyQuad
local projBatch, projQuad
local ENEMY_SPRITE_R = 13

local function makeCircleSprite(size, radius, base, rim, shine)
  local canvas = love.graphics.newCanvas(size, size)
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  local cx, cy = size / 2, size / 2
  love.graphics.setColor(rim)
  love.graphics.circle("fill", cx, cy, radius)
  love.graphics.setColor(base)
  love.graphics.circle("fill", cx, cy, radius - size / 16)
  love.graphics.setColor(shine)
  love.graphics.circle("fill", cx - radius * 0.3, cy - radius * 0.35, radius * 0.25)
  love.graphics.setCanvas()
  return canvas
end

function Render.initSprites()
  if enemyBatch then return end
  local enemyImg = makeCircleSprite(28, ENEMY_SPRITE_R,
    { 0.82, 0.20, 0.24 }, { 0.45, 0.08, 0.12 }, { 1, 0.55, 0.55 })
  enemyQuad = love.graphics.newQuad(0, 0, 28, 28, enemyImg:getDimensions())
  enemyBatch = love.graphics.newSpriteBatch(enemyImg, 16384, "dynamic")

  local projImg = makeCircleSprite(8, 4, { 1, 0.85, 0.30 }, { 0.6, 0.4, 0.1 }, { 1, 1, 0.8 })
  projQuad = love.graphics.newQuad(0, 0, 8, 8, projImg:getDimensions())
  projBatch = love.graphics.newSpriteBatch(projImg, 8192, "dynamic")
end

function Render.draw(S)
  Render.initSprites()
  love.graphics.clear(C.bg)
  Render.terrain()
  Render.nodes(S)
  Render.village(S.village)
  Render.walls(S)
  Render.villagers(S)
  Render.buildings(S)
  Render.enemies(S.enemies)
  Render.projectiles(S.projectiles)
  Render.ghost(S)
end

function Render.terrain()
  local x0, y0, x1, y1 = Camera.viewBounds()
  local T = Grid.TILE
  local gx0 = math.max(0, math.floor(x0 / T))
  local gy0 = math.max(0, math.floor(y0 / T))
  local gx1 = math.min(Grid.WIDTH - 1, math.floor(x1 / T))
  local gy1 = math.min(Grid.HEIGHT - 1, math.floor(y1 / T))
  for gy = gy0, gy1 do
    for gx = gx0, gx1 do
      love.graphics.setColor((gx + gy) % 2 == 0 and C.tileA or C.tileB)
      love.graphics.rectangle("fill", gx * T, gy * T, T, T)
    end
  end
  love.graphics.setColor(C.border)
  love.graphics.setLineWidth(4)
  love.graphics.rectangle("line", 0, 0, Grid.pixelWidth(), Grid.pixelHeight())
end

function Render.nodes(S)
  local x0, y0, x1, y1 = Camera.viewBounds()
  love.graphics.setLineWidth(1)
  for i = 1, #Nodes.list do
    local nd = Nodes.list[i]
    if nd.x >= x0 - 20 and nd.x <= x1 + 20 and nd.y >= y0 - 20 and nd.y <= y1 + 20 then
      if nd.kind == "tree" then
        love.graphics.setColor(C.treeTrunk)
        love.graphics.line(nd.x, nd.y + 4, nd.x, nd.y - 2)
        love.graphics.setColor(C.treeCanopy)
        love.graphics.circle("fill", nd.x, nd.y - 4, 8)
      elseif nd.kind == "berry" then
        love.graphics.setColor(C.bush)
        love.graphics.circle("fill", nd.x, nd.y, 7)
        local dots = math.ceil(nd.amount / 5)
        love.graphics.setColor(C.berry)
        for k = 1, dots do
          local a = k * 2.2
          love.graphics.circle("fill", nd.x + math.cos(a) * 4, nd.y + math.sin(a) * 4, 1.6)
        end
      else
        love.graphics.setColor(C.rock)
        love.graphics.circle("fill", nd.x, nd.y, 7, 6)
        love.graphics.setColor(C.rockLine)
        love.graphics.circle("line", nd.x, nd.y, 7, 6)
      end
    end
  end
end

function Render.village(v)
  love.graphics.setColor(C.villageFill)
  love.graphics.circle("fill", v.x, v.y, v.r)
  love.graphics.setColor(C.villageLine)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", v.x, v.y, v.r)
  local pts = {}
  for i = 0, 4 do
    local a = -math.pi / 2 + i * 2 * math.pi / 5
    pts[#pts + 1] = { v.x + math.cos(a) * v.r * 0.85, v.y + math.sin(a) * v.r * 0.85 }
  end
  local order = { 1, 3, 5, 2, 4, 1 }
  local line = {}
  for _, idx in ipairs(order) do
    line[#line + 1] = pts[idx][1]
    line[#line + 1] = pts[idx][2]
  end
  love.graphics.line(line)
end

function Render.walls()
  local W = Walls
  for i = 1, W.n do
    local x, y = W.gx[i] * Grid.TILE, W.gy[i] * Grid.TILE
    local hpFrac = W.hp[i] / W.maxHp[i]
    love.graphics.setColor(C.wall[1] * (0.6 + 0.4 * hpFrac), C.wall[2] * (0.6 + 0.4 * hpFrac), C.wall[3] * (0.6 + 0.4 * hpFrac))
    love.graphics.rectangle("fill", x + 1, y + 1, Grid.TILE - 2, Grid.TILE - 2, 2)
    love.graphics.setColor(C.wallLine)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 1, y + 1, Grid.TILE - 2, Grid.TILE - 2, 2)
    if W.flash[i] > 0 then
      love.graphics.setColor(C.wallFlash[1], C.wallFlash[2], C.wallFlash[3], math.min(1, W.flash[i] * 8))
      love.graphics.rectangle("fill", x + 1, y + 1, Grid.TILE - 2, Grid.TILE - 2, 2)
    end
  end
end

function Render.villagers(S)
  local list = Villagers.list
  local sel = S.selection and S.selection.villager or nil
  love.graphics.setLineWidth(1)
  for i = 1, #list do
    local v = list[i]
    if not v.dead then
      love.graphics.setColor(v.sex == "f" and C.villagerF or C.villagerM)
      love.graphics.circle("fill", v.x, v.y, v.r)
      love.graphics.setColor(C.villagerLine)
      love.graphics.circle("line", v.x, v.y, v.r)
      if v.carry > 0 and RES_COLOR[v.carryRes] then
        local rc = RES_COLOR[v.carryRes]
        love.graphics.setColor(rc[1], rc[2], rc[3])
        love.graphics.circle("fill", v.x, v.y - v.r - 3, 2.2)
      end
      if v.flash > 0 then
        love.graphics.setColor(C.flash[1], C.flash[2], C.flash[3], math.min(1, v.flash * 9))
        love.graphics.circle("fill", v.x, v.y, v.r)
      end
      if v == sel then
        love.graphics.setColor(C.select)
        love.graphics.circle("line", v.x, v.y, v.r + 3)
      end
    end
  end
end

local function crewPips(x, y, crewCount, maxCrew)
  love.graphics.setLineWidth(1)
  local total = maxCrew
  local w = total * 8 - 3
  local px = x - w / 2 + 2
  for k = 1, total do
    if k <= crewCount then
      love.graphics.setColor(C.crewGood)
      love.graphics.circle("fill", px, y, 2.4)
    else
      love.graphics.setColor(C.crewBad)
      love.graphics.circle("line", px, y, 2.4)
    end
    px = px + 8
  end
end

function Render.buildings(S)
  local B = Buildings
  local sel = S.selection and S.selection.building or nil
  for i = 1, B.n do
    local x, y = B.x[i], B.y[i]
    local kind = B.kind[i]
    if not B.built[i] then
      local d = buildingData[kind]
      local frac = B.progress[i] / d.buildTime
      love.graphics.setColor(C.construct[1], C.construct[2], C.construct[3], 0.35 + 0.4 * frac)
      love.graphics.rectangle("fill", x - 12, y - 12, 24, 24, 3)
      love.graphics.setColor(C.construct)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", x - 12, y - 12, 24, 24, 3)
      love.graphics.setColor(C.hpBarBack)
      love.graphics.rectangle("fill", x - 12, y + 14, 24, 3)
      love.graphics.setColor(C.hpBar)
      love.graphics.rectangle("fill", x - 12, y + 14, 24 * frac, 3)
    elseif kind == "house" then
      love.graphics.setColor(C.house)
      love.graphics.rectangle("fill", x - 11, y - 6, 22, 17, 2)
      love.graphics.setColor(C.houseRoof)
      love.graphics.polygon("fill", x - 13, y - 6, x, y - 16, x + 13, y - 6)
      love.graphics.setColor(C.wallLine)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", x - 11, y - 6, 22, 17, 2)
      if B.flash[i] > 0 then
        love.graphics.setColor(C.wallFlash[1], C.wallFlash[2], C.wallFlash[3], math.min(1, B.flash[i] * 8))
        love.graphics.rectangle("fill", x - 12, y - 16, 24, 28, 2)
      end
    else
      local isBallista = kind == "ballista"
      local half = isBallista and 14 or 12
      love.graphics.setColor(isBallista and C.ballista or C.tower)
      love.graphics.rectangle("fill", x - half, y - half, half * 2, half * 2, 3)
      love.graphics.setColor(C.towerLine)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", x - half, y - half, half * 2, half * 2, 3)
      if isBallista then
        love.graphics.setLineWidth(2)
        love.graphics.line(x, y - 6, x, y + 8)
        love.graphics.line(x - 6, y + 2, x + 6, y + 2)
      end
      if B.crewCount[i] < B.maxCrew[i] then
        love.graphics.setColor(C.offline)
        love.graphics.setLineWidth(2)
        love.graphics.line(x - 8, y - 8, x + 8, y + 8)
      end
      crewPips(x, y + half + 6, B.crewCount[i], B.maxCrew[i])
      if B.flash[i] > 0 then
        love.graphics.setColor(C.wallFlash[1], C.wallFlash[2], C.wallFlash[3], math.min(1, B.flash[i] * 8))
        love.graphics.rectangle("fill", x - half, y - half, half * 2, half * 2, 3)
      end
    end
    if i == sel then
      love.graphics.setColor(C.select)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", x - 17, y - 17, 34, 34, 3)
    end
  end
  love.graphics.setLineWidth(1)
  for i = 1, B.n do
    if B.built[i] and B.hp[i] < B.maxHp[i] then
      local x, y = B.x[i], B.y[i]
      love.graphics.setColor(C.hpBarBack)
      love.graphics.rectangle("fill", x - 12, y - 22, 24, 3)
      love.graphics.setColor(C.hpBar)
      love.graphics.rectangle("fill", x - 12, y - 22, 24 * (B.hp[i] / B.maxHp[i]), 3)
    end
  end
end

function Render.enemies(E)
  enemyBatch:clear()
  local n = E.n
  for i = 1, n do
    local s = E.r[i] / ENEMY_SPRITE_R
    enemyBatch:add(enemyQuad, E.x[i] - 14 * s, E.y[i] - 14 * s, 0, s, s)
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(enemyBatch)

  local flashed = 0
  for i = 1, n do
    if E.hitFlash[i] > 0 then
      love.graphics.setColor(C.flash[1], C.flash[2], C.flash[3], math.min(1, E.hitFlash[i] * 9))
      love.graphics.circle("fill", E.x[i], E.y[i], E.r[i])
      flashed = flashed + 1
      if flashed > 300 then break end
    end
  end

  local bars = 0
  love.graphics.setLineWidth(1)
  for i = 1, n do
    if E.hp[i] < E.maxHp[i] then
      local w = 14
      love.graphics.setColor(C.hpBarBack)
      love.graphics.rectangle("fill", E.x[i] - w / 2, E.y[i] - E.r[i] - 6, w, 2)
      love.graphics.setColor(C.hpBar)
      love.graphics.rectangle("fill", E.x[i] - w / 2, E.y[i] - E.r[i] - 6, w * (E.hp[i] / E.maxHp[i]), 2)
      bars = bars + 1
      if bars > 400 then break end
    end
  end
end

function Render.projectiles(P)
  projBatch:clear()
  for i = 1, P.n do
    projBatch:add(projQuad, P.x[i] - 4, P.y[i] - 4)
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(projBatch)
end

function Render.ghost(S)
  if not S.buildMode or S.mode ~= "playing" then return end
  local mx, my = love.mouse.getPosition()
  local wx, wy = Camera.toWorld(mx, my)
  local gx, gy = Grid.worldToTile(wx, wy)
  local t = S.buildType
  local ok
  if t == "wall" then
    ok = Walls.canPlace(gx, gy) and S.canAfford(buildingData.wall.cost)
  else
    ok = Buildings.canPlace(gx, gy, S.village) and S.canAfford(buildingData[t].cost)
  end
  love.graphics.setColor(ok and C.ghostOk or C.ghostBad)
  love.graphics.rectangle("fill", gx * Grid.TILE, gy * Grid.TILE, Grid.TILE, Grid.TILE)
  local d = buildingData[t]
  if d and d.range then
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", (gx + 0.5) * Grid.TILE, (gy + 0.5) * Grid.TILE, d.range)
  end
end

return Render
