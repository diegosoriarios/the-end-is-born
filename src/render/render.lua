local Grid = require("src.sim.grid")
local Camera = require("src.core.camera")
local Walls = require("src.sim.walls")
local Buildings = require("src.sim.buildings")
local Villagers = require("src.sim.villagers")
local Nodes = require("src.sim.nodes")
local Enemies = require("src.sim.enemies")
local enemyData = require("src.data.enemies")
local buildingData = require("src.data.buildings")
local Checklist = require("src.sim.checklist")
local Ages = require("src.sim.ages")
local Particles = require("src.fx.particles")

local Render = {}

local floor = math.floor

local C = {
  bg = { 0.07, 0.05, 0.09 },
  tileA = { 0.105, 0.085, 0.125 },
  tileB = { 0.088, 0.068, 0.108 },
  grass = { 0.15, 0.30, 0.17 },
  border = { 0.30, 0.25, 0.40 },
  shadow = { 0, 0, 0, 0.22 },
  villageFill = { 0.24, 0.10, 0.31 },
  villageLine = { 0.62, 0.28, 0.72 },
  villageGlow = { 0.72, 0.34, 0.85 },
  stone = { 0.45, 0.42, 0.52 },
  stoneDark = { 0.20, 0.18, 0.26 },
  stoneHi = { 0.60, 0.57, 0.68 },
  tower = { 0.58, 0.58, 0.66 },
  towerRoof = { 0.42, 0.16, 0.22 },
  ballista = { 0.72, 0.60, 0.42 },
  ballistaWood = { 0.45, 0.30, 0.16 },
  house = { 0.52, 0.38, 0.26 },
  houseRoof = { 0.34, 0.16, 0.20 },
  houseRoofHi = { 0.44, 0.22, 0.26 },
  door = { 0.26, 0.16, 0.11 },
  window = { 1.0, 0.80, 0.35 },
  construct = { 0.55, 0.50, 0.38 },
  construction = { 0.50, 0.44, 0.32 },
  altarStone = { 0.22, 0.18, 0.28 },
  altarStoneHi = { 0.32, 0.27, 0.40 },
  candle = { 1, 0.55, 0.2 },
  candleHi = { 1, 0.85, 0.45 },
  wall = { 0.44, 0.41, 0.51 },
  wallLine = { 0.17, 0.15, 0.22 },
  wallFlash = { 1, 0.9, 0.7 },
  flash = { 1, 0.96, 0.90 },
  hpBar = { 0.35, 0.9, 0.4 },
  hpBarBack = { 0.12, 0.12, 0.14 },
  ghostOk = { 0.35, 0.9, 0.45, 0.35 },
  ghostBad = { 1, 0.28, 0.28, 0.35 },
  treeCanopy = { 0.17, 0.36, 0.19 },
  treeCanopyDark = { 0.10, 0.24, 0.12 },
  treeCanopyHi = { 0.26, 0.48, 0.26 },
  treeTrunk = { 0.36, 0.25, 0.15 },
  bush = { 0.18, 0.38, 0.20 },
  berry = { 0.85, 0.22, 0.30 },
  rock = { 0.53, 0.53, 0.60 },
  rockDark = { 0.32, 0.32, 0.40 },
  rockHi = { 0.68, 0.68, 0.75 },
  villagerM = { 0.45, 0.42, 0.82 },
  villagerF = { 0.82, 0.46, 0.70 },
  villagerChildM = { 0.66, 0.63, 0.92 },
  villagerChildF = { 0.92, 0.63, 0.85 },
  undead = { 0.56, 0.70, 0.56 },
  villagerHood = { 0.28, 0.24, 0.52 },
  villagerHoodF = { 0.52, 0.26, 0.44 },
  villagerFace = { 0.07, 0.06, 0.11 },
  villagerEye = { 1.0, 0.86, 0.55 },
  villagerLine = { 0.11, 0.09, 0.16 },
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

local enemyBatch, kindQuads
local projBatch, projQuad
local ENEMY_SPRITE_R = 13
local ENEMY_SPRITE_S = 28
local now = 0

local function shadow(x, y, rx, ry)
  love.graphics.setColor(C.shadow)
  love.graphics.ellipse("fill", x, y, rx, ry)
end

-- Placeholder: one solid opaque disc per kind (color + size distinguish them).
local function paintEnemy(x0, col)
  local cx, cy, R = x0 + ENEMY_SPRITE_S / 2, ENEMY_SPRITE_S / 2, 11
  love.graphics.setColor(col[2])
  love.graphics.circle("fill", cx, cy, R + 1.5)
  love.graphics.setColor(col[1])
  love.graphics.circle("fill", cx, cy, R)
  love.graphics.setColor(col[3])
  love.graphics.circle("fill", cx - R * 0.32, cy - R * 0.36, R * 0.26)
end

function Render.initSprites()
  if enemyBatch then return end
  local kinds = Enemies.KINDS
  local K = #kinds
  local atlas = love.graphics.newCanvas(ENEMY_SPRITE_S * K, ENEMY_SPRITE_S)
  love.graphics.setCanvas(atlas)
  local fallback = { { 0.82, 0.20, 0.24 }, { 0.45, 0.08, 0.12 }, { 1, 0.55, 0.55 } }
  for k = 1, K do
    paintEnemy((k - 1) * ENEMY_SPRITE_S, enemyData[kinds[k]].color or fallback)
  end
  love.graphics.setCanvas()
  kindQuads = {}
  for k = 1, K do
    kindQuads[k] = love.graphics.newQuad((k - 1) * ENEMY_SPRITE_S, 0, ENEMY_SPRITE_S, ENEMY_SPRITE_S, atlas:getDimensions())
  end
  enemyBatch = love.graphics.newSpriteBatch(atlas, 16384, "dynamic")

  local projImg = love.graphics.newCanvas(8, 8)
  love.graphics.setCanvas(projImg)
  love.graphics.setColor(0.6, 0.4, 0.1)
  love.graphics.circle("fill", 4, 4, 4)
  love.graphics.setColor(1, 0.85, 0.30)
  love.graphics.circle("fill", 4, 4, 3)
  love.graphics.setColor(1, 1, 0.8)
  love.graphics.circle("fill", 3, 3, 1.2)
  love.graphics.setCanvas()
  projQuad = love.graphics.newQuad(0, 0, 8, 8, projImg:getDimensions())
  projBatch = love.graphics.newSpriteBatch(projImg, 8192, "dynamic")
end

function Render.draw(S)
  Render.initSprites()
  now = love.timer.getTime()
  love.graphics.clear(C.bg)
  Render.terrain()
  Render.nodes(S)
  Render.village(S.village)
  Render.walls(S)
  Render.villagers(S)
  Render.buildings(S)
  Render.enemies(S.enemies)
  Render.projectiles(S.projectiles)
  Render.enemyShots(S.enemyShots)
  Particles.draw()
  Render.ghost(S)
end

function Render.terrain()
  local x0, y0, x1, y1 = Camera.viewBounds()
  local T = Grid.TILE
  local gx0 = math.max(0, floor(x0 / T))
  local gy0 = math.max(0, floor(y0 / T))
  local gx1 = math.min(Grid.WIDTH - 1, floor(x1 / T))
  local gy1 = math.min(Grid.HEIGHT - 1, floor(y1 / T))
  love.graphics.setLineWidth(1)
  for gy = gy0, gy1 do
    for gx = gx0, gx1 do
      love.graphics.setColor((gx + gy) % 2 == 0 and C.tileA or C.tileB)
      love.graphics.rectangle("fill", gx * T, gy * T, T, T)
    end
  end
  -- scattered grass tufts (deterministic per tile, drawn after the base grid)
  love.graphics.setColor(C.grass)
  for gy = gy0, gy1 do
    for gx = gx0, gx1 do
      local h = (gx * 92837111 + gy * 689287499) % 1000
      if h < 260 then
        local px = gx * T + (h % 24) + 4
        local py = gy * T + (floor(h / 24) % 24) + 6
        love.graphics.line(px, py, px - 2, py - 4)
        love.graphics.line(px, py, px + 1, py - 5)
        love.graphics.line(px, py, px + 3, py - 3)
      end
    end
  end
  love.graphics.setColor(C.border)
  love.graphics.setLineWidth(4)
  love.graphics.rectangle("line", 0, 0, Grid.pixelWidth(), Grid.pixelHeight())
  love.graphics.setLineWidth(1)
end

function Render.nodes()
  local x0, y0, x1, y1 = Camera.viewBounds()
  love.graphics.setLineWidth(1)
  local list = Nodes.list
  for i = 1, #list do
    local nd = list[i]
    if nd.x >= x0 - 24 and nd.x <= x1 + 24 and nd.y >= y0 - 24 and nd.y <= y1 + 24 then
      if nd.kind == "tree" then
        shadow(nd.x, nd.y + 5, 9, 3.5)
        love.graphics.setColor(C.treeTrunk)
        love.graphics.rectangle("fill", nd.x - 1.5, nd.y - 3, 3, 8, 1)
        love.graphics.setColor(C.treeCanopyDark)
        love.graphics.circle("fill", nd.x, nd.y - 6, 9)
        love.graphics.setColor(C.treeCanopy)
        love.graphics.circle("fill", nd.x - 2, nd.y - 7, 7.5)
        love.graphics.circle("fill", nd.x + 3, nd.y - 5, 6)
        love.graphics.setColor(C.treeCanopyHi)
        love.graphics.circle("fill", nd.x - 3, nd.y - 9, 3)
      elseif nd.kind == "berry" then
        shadow(nd.x, nd.y + 4, 7, 3)
        love.graphics.setColor(C.bush)
        love.graphics.circle("fill", nd.x, nd.y, 7)
        love.graphics.setColor(0.12, 0.28, 0.14)
        love.graphics.circle("line", nd.x, nd.y, 7)
        local dots = math.ceil(nd.amount / 5)
        love.graphics.setColor(C.berry)
        for k = 1, dots do
          local a = k * 2.2
          love.graphics.circle("fill", nd.x + math.cos(a) * 4, nd.y + math.sin(a) * 4, 1.7)
        end
      elseif nd.kind == "rock" then
        shadow(nd.x, nd.y + 4, 7, 3)
        love.graphics.setColor(C.rockDark)
        love.graphics.polygon("fill", nd.x - 8, nd.y + 5, nd.x - 6, nd.y - 5, nd.x, nd.y - 8, nd.x + 7, nd.y - 3, nd.x + 8, nd.y + 5)
        love.graphics.setColor(C.rock)
        love.graphics.polygon("fill", nd.x - 6, nd.y + 4, nd.x - 4, nd.y - 3, nd.x, nd.y - 6, nd.x + 5, nd.y - 1, nd.x + 5, nd.y + 4)
        love.graphics.setColor(C.rockHi)
        love.graphics.polygon("fill", nd.x - 3, nd.y - 2, nd.x, nd.y - 5, nd.x + 2, nd.y - 1)
      end
    end
  end
end

function Render.village(v)
  love.graphics.setColor(C.villageFill)
  love.graphics.circle("fill", v.x, v.y, v.r)
  local pulse = 0.5 + 0.5 * math.sin(now * 2)
  love.graphics.setColor(C.villageGlow[1], C.villageGlow[2], C.villageGlow[3], 0.18 + 0.16 * pulse)
  love.graphics.setLineWidth(5)
  love.graphics.circle("line", v.x, v.y, v.r)
  love.graphics.setColor(C.villageLine)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", v.x, v.y, v.r)
  local pts = {}
  for i = 0, 4 do
    local a = -math.pi / 2 + i * 2 * math.pi / 5
    pts[#pts + 1] = { v.x + math.cos(a) * v.r * 0.82, v.y + math.sin(a) * v.r * 0.82 }
  end
  local order = { 1, 3, 5, 2, 4, 1 }
  local line = {}
  for _, idx in ipairs(order) do
    line[#line + 1] = pts[idx][1]
    line[#line + 1] = pts[idx][2]
  end
  love.graphics.setLineWidth(2)
  love.graphics.line(line)
end

function Render.walls()
  local W = Walls
  local T = Grid.TILE
  love.graphics.setLineWidth(1)
  for i = 1, W.n do
    local x, y = W.gx[i] * T, W.gy[i] * T
    local hpFrac = W.hp[i] / W.maxHp[i]
    local b = 0.6 + 0.4 * hpFrac
    shadow(x + T / 2, y + T - 3, T / 2 - 2, 3)
    love.graphics.setColor(C.wall[1] * b, C.wall[2] * b, C.wall[3] * b)
    love.graphics.rectangle("fill", x + 1, y + 1, T - 2, T - 2, 2)
    love.graphics.setColor(C.wallLine)
    love.graphics.line(x + 1, y + T / 2, x + T - 1, y + T / 2)
    love.graphics.line(x + T / 2, y + 1, x + T / 2, y + T / 2)
    love.graphics.line(x + T / 4, y + T / 2, x + T / 4, y + T - 1)
    love.graphics.line(x + T * 3 / 4, y + T / 2, x + T * 3 / 4, y + T - 1)
    love.graphics.setColor(C.stoneHi[1] * b, C.stoneHi[2] * b, C.stoneHi[3] * b)
    love.graphics.line(x + 2, y + 2, x + T - 2, y + 2)
    love.graphics.setColor(C.wallLine)
    love.graphics.rectangle("line", x + 1, y + 1, T - 2, T - 2, 2)
    if W.flash[i] > 0 then
      love.graphics.setColor(C.wallFlash[1], C.wallFlash[2], C.wallFlash[3], math.min(1, W.flash[i] * 8))
      love.graphics.rectangle("fill", x + 1, y + 1, T - 2, T - 2, 2)
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
      local bob = math.sin(now * 6 + v.id) * 0.8
      local x, y = v.x, v.y + bob
      shadow(v.x, v.y + v.r, v.r + 1.5, v.r * 0.6)
      if v.undead then
        love.graphics.setColor(C.undead)
      elseif v.age == "child" then
        love.graphics.setColor(v.sex == "f" and C.villagerChildF or C.villagerChildM)
      else
        love.graphics.setColor(v.sex == "f" and C.villagerF or C.villagerM)
      end
      love.graphics.circle("fill", x, y, v.r)
      love.graphics.setColor(v.sex == "f" and C.villagerHoodF or C.villagerHood)
      love.graphics.arc("fill", x, y, v.r + 0.6, math.pi, 2 * math.pi)
      love.graphics.setColor(C.villagerFace)
      love.graphics.circle("fill", x, y - v.r * 0.12, v.r * 0.56)
      love.graphics.setColor(C.villagerEye)
      local es = math.max(0.8, v.r * 0.2)
      love.graphics.circle("fill", x - v.r * 0.22, y - v.r * 0.18, es)
      love.graphics.circle("fill", x + v.r * 0.22, y - v.r * 0.18, es)
      love.graphics.setColor(C.villagerLine)
      love.graphics.circle("line", x, y, v.r)
      if v.carry > 0 and RES_COLOR[v.carryRes] then
        local rc = RES_COLOR[v.carryRes]
        love.graphics.setColor(rc[1], rc[2], rc[3])
        love.graphics.circle("fill", x, y - v.r - 3, 2.2)
      end
      if v.flash > 0 then
        love.graphics.setColor(C.flash[1], C.flash[2], C.flash[3], math.min(1, v.flash * 9))
        love.graphics.circle("fill", x, y, v.r)
      end
      if v == sel then
        love.graphics.setColor(C.select)
        love.graphics.circle("line", x, y, v.r + 3)
      end
    end
  end
end

local function crewPips(x, y, crewCount, maxCrew)
  love.graphics.setLineWidth(1)
  for k = 1, maxCrew do
    local px = x - (maxCrew * 8 - 3) / 2 + 2 + (k - 1) * 8
    if k <= crewCount then
      love.graphics.setColor(C.crewGood)
      love.graphics.circle("fill", px, y, 2.4)
    else
      love.graphics.setColor(C.crewBad)
      love.graphics.circle("line", px, y, 2.4)
    end
  end
end

local function drawHouse(x, y)
  shadow(x, y + 9, 14, 5)
  love.graphics.setColor(0.30, 0.20, 0.13)
  love.graphics.rectangle("fill", x - 12, y - 5, 24, 18, 2)
  love.graphics.setColor(C.house)
  love.graphics.rectangle("fill", x - 11, y - 4, 22, 16, 2)
  love.graphics.setColor(C.door)
  love.graphics.rectangle("fill", x - 3.5, y + 3, 7, 9, 1)
  love.graphics.setColor(0.9, 0.75, 0.4)
  local lit = 0.5 + 0.5 * math.sin(now * 3 + x * 0.1)
  love.graphics.setColor(C.window[1], C.window[2], C.window[3], 0.55 + 0.45 * lit)
  love.graphics.rectangle("fill", x + 4, y - 1, 4.5, 4.5, 1)
  love.graphics.setColor(C.houseRoof)
  love.graphics.polygon("fill", x - 14, y - 4, x, y - 17, x + 14, y - 4)
  love.graphics.setColor(C.houseRoofHi)
  love.graphics.polygon("fill", x - 14, y - 4, x, y - 17, x - 1, y - 4)
  love.graphics.setColor(C.wallLine)
  love.graphics.setLineWidth(1)
  love.graphics.polygon("line", x - 14, y - 4, x, y - 17, x + 14, y - 4)
  love.graphics.rectangle("line", x - 11, y - 4, 22, 16, 2)
end

local function drawTower(x, y, isBallista)
  if isBallista then
    shadow(x, y + 11, 15, 5)
    love.graphics.setColor(C.ballistaWood)
    love.graphics.rectangle("fill", x - 13, y - 2, 26, 13, 2)
    love.graphics.setColor(C.ballista)
    love.graphics.rectangle("fill", x - 11, y - 4, 22, 10, 2)
    love.graphics.setColor(C.ballistaWood)
    love.graphics.setLineWidth(3)
    love.graphics.line(x - 12, y - 8, x + 12, y - 8)
    love.graphics.setLineWidth(2)
    love.graphics.line(x, y - 12, x, y + 2)
    love.graphics.polygon("fill", x - 3, y - 14, x + 3, y - 14, x, y - 9)
    love.graphics.setColor(C.wallLine)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x - 11, y - 4, 22, 15, 2)
  else
    shadow(x, y + 11, 13, 5)
    love.graphics.setColor(C.stoneDark)
    love.graphics.rectangle("fill", x - 12, y - 12, 24, 24, 2)
    love.graphics.setColor(C.tower)
    love.graphics.rectangle("fill", x - 11, y - 11, 22, 22, 2)
    -- crenellations
    love.graphics.setColor(C.stoneHi)
    for c = -1, 1 do
      love.graphics.rectangle("fill", x + c * 8 - 3, y - 15, 6, 5, 1)
    end
    love.graphics.setColor(C.stoneDark)
    love.graphics.setLineWidth(1)
    love.graphics.line(x - 11, y - 1, x + 11, y - 1)
    love.graphics.line(x, y - 11, x, y - 1)
    love.graphics.line(x - 11, y + 6, x + 11, y + 6)
    love.graphics.setColor(C.window[1], C.window[2], C.window[3], 0.7)
    love.graphics.rectangle("fill", x - 2, y - 8, 4, 5, 1)
    love.graphics.setColor(C.wallLine)
    love.graphics.rectangle("line", x - 11, y - 11, 22, 22, 2)
  end
end

local function drawAltar(x, y)
  shadow(x, y + 8, 15, 5)
  love.graphics.setColor(C.altarStoneHi)
  love.graphics.rectangle("fill", x - 14, y - 9, 28, 19, 3)
  love.graphics.setColor(C.altarStone)
  love.graphics.rectangle("fill", x - 13, y - 8, 26, 17, 3)
  love.graphics.setColor(C.villageGlow)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", x, y, 7, 5)
  local f1 = 1.6 + 0.6 * math.sin(now * 9.0)
  local f2 = 1.6 + 0.6 * math.sin(now * 11.0 + 1.7)
  love.graphics.setColor(C.candle)
  love.graphics.rectangle("fill", x - 11, y - 12, 2.5, 5)
  love.graphics.rectangle("fill", x + 8.5, y - 12, 2.5, 5)
  love.graphics.setColor(C.candle)
  love.graphics.circle("fill", x - 9.75, y - 13, f1)
  love.graphics.circle("fill", x + 9.75, y - 13, f2)
  love.graphics.setColor(C.candleHi)
  love.graphics.circle("fill", x - 9.75, y - 13.5, f1 * 0.5)
  love.graphics.circle("fill", x + 9.75, y - 13.5, f2 * 0.5)
  love.graphics.setColor(C.wallLine)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x - 14, y - 9, 28, 19, 3)
end

local function drawConstruction(x, y, frac)
  shadow(x, y + 11, 13, 4)
  love.graphics.setColor(C.construction[1], C.construction[2], C.construction[3], 0.3 + 0.35 * frac)
  love.graphics.rectangle("fill", x - 12, y - 12, 24, 24, 3)
  love.graphics.setColor(C.construct)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x - 12, y - 12, 24, 24, 3)
  love.graphics.line(x - 12, y - 12, x + 12, y + 12)
  love.graphics.line(x + 12, y - 12, x - 12, y + 12)
  love.graphics.setColor(C.hpBarBack)
  love.graphics.rectangle("fill", x - 12, y + 14, 24, 3)
  love.graphics.setColor(C.hpBar)
  love.graphics.rectangle("fill", x - 12, y + 14, 24 * frac, 3)
end

-- Generic fallback so a brand-new building is visible before custom art.
local function drawGeneric(x, y, d)
  local col = d and d.color or { 0.55, 0.5, 0.62 }
  shadow(x, y + 10, 12, 4)
  love.graphics.setColor(col[1] * 0.55, col[2] * 0.55, col[3] * 0.55)
  love.graphics.rectangle("fill", x - 12, y - 12, 24, 24, 3)
  love.graphics.setColor(col)
  love.graphics.rectangle("fill", x - 10, y - 10, 20, 20, 3)
  love.graphics.setColor(0.1, 0.1, 0.12)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x - 12, y - 12, 24, 24, 3)
end

local function drawFarm(x, y)
  shadow(x, y + 10, 13, 4)
  love.graphics.setColor(0.34, 0.24, 0.14)
  love.graphics.rectangle("fill", x - 13, y - 9, 26, 20, 3)
  love.graphics.setColor(0.30, 0.45, 0.20)
  for r = 0, 2 do
    love.graphics.rectangle("fill", x - 11, y - 7 + r * 6, 22, 3, 1)
  end
  love.graphics.setColor(0.60, 0.78, 0.38)
  for r = 0, 2 do
    for c = -2, 2 do
      love.graphics.circle("fill", x + c * 5, y - 5.5 + r * 6, 1.4)
    end
  end
  love.graphics.setColor(0.12, 0.09, 0.06)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x - 13, y - 9, 26, 20, 3)
end

local function drawGraveyard(x, y)
  shadow(x, y + 10, 14, 4)
  love.graphics.setColor(0.20, 0.20, 0.24)
  love.graphics.rectangle("fill", x - 14, y - 10, 28, 22, 3)
  love.graphics.setColor(0.32, 0.32, 0.38)
  local graves = { { -8, -4 }, { -2, -6 }, { 4, -3 }, { 9, -6 } }
  for i = 1, #graves do
    love.graphics.rectangle("fill", x + graves[i][1] - 2, y + graves[i][2] - 3, 4, 8, 1)
  end
  love.graphics.setColor(0.45, 0.5, 0.45)
  love.graphics.circle("fill", x - 8, y - 8, 1)
  love.graphics.setColor(0.12, 0.09, 0.06)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x - 14, y - 10, 28, 22, 3)
end

-- render key (from data) -> drawer; anything missing uses drawGeneric.
local RENDERERS = {
  house = drawHouse,
  altar = drawAltar,
  farm = drawFarm,
  graveyard = drawGraveyard,
  arrow_tower = function(x, y) drawTower(x, y, false) end,
  ballista = function(x, y) drawTower(x, y, true) end,
}

function Render.buildings(S)
  local B = Buildings
  local sel = S.selection and S.selection.building or nil
  love.graphics.setLineWidth(1)
  for i = 1, B.n do
    local x, y, kind = B.x[i], B.y[i], B.kind[i]
    local d = buildingData[kind]
    if not B.built[i] then
      drawConstruction(x, y, math.min(1, B.progress[i] / (d.buildTime or 1)))
    else
      local draw = RENDERERS[d.render or kind] or drawGeneric
      draw(x, y, d)
      if d.role == "tower" then
        local half = (d.render == "ballista") and 13 or 12
        if B.crewCount[i] < B.maxCrew[i] then
          love.graphics.setColor(C.offline)
          love.graphics.setLineWidth(2)
          love.graphics.line(x - 8, y - 8, x + 8, y + 8)
        end
        crewPips(x, y + half + 7, B.crewCount[i], B.maxCrew[i])
      elseif d.role == "research" then
        crewPips(x, y + 18, B.researchers[i] or 0, d.researchSlots or 0)
      end
      if B.flash[i] > 0 then
        local half = d.role == "tower" and ((d.render == "ballista") and 13 or 12) or 14
        love.graphics.setColor(C.wallFlash[1], C.wallFlash[2], C.wallFlash[3], math.min(1, B.flash[i] * 8))
        love.graphics.rectangle("fill", x - half, y - half, half * 2, half * 2, 3)
      end
    end
    if i == sel then
      love.graphics.setColor(C.select)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", x - 17, y - 18, 34, 34, 3)
    end
  end
  love.graphics.setLineWidth(1)
  for i = 1, B.n do
    if B.built[i] and B.hp[i] < B.maxHp[i] then
      local x, y = B.x[i], B.y[i]
      love.graphics.setColor(C.hpBarBack)
      love.graphics.rectangle("fill", x - 12, y - 24, 24, 3)
      love.graphics.setColor(C.hpBar)
      love.graphics.rectangle("fill", x - 12, y - 24, 24 * (B.hp[i] / B.maxHp[i]), 3)
    end
  end
end

function Render.enemies(E)
  enemyBatch:clear()
  local n = E.n
  for i = 1, n do
    local s = E.r[i] / ENEMY_SPRITE_R
    enemyBatch:add(kindQuads[E.kind[i]], E.x[i] - 14 * s, E.y[i] - 14 * s, 0, s, s)
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

function Render.enemyShots(P)
  if not P or P.n == 0 then return end
  love.graphics.setColor(0.55, 0.9, 0.35)
  for i = 1, P.n do
    love.graphics.circle("fill", P.x[i], P.y[i], 3)
  end
  love.graphics.setColor(0.2, 0.45, 0.12)
  for i = 1, P.n do
    love.graphics.circle("line", P.x[i], P.y[i], 3)
  end
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
    ok = Ages.unlocked(t) and Buildings.canPlace(gx, gy, S.village) and S.canAfford(buildingData[t].cost)
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
