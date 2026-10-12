-- Cosmetic particle system. Data-oriented SoA pool with a hard cap so mass
-- deaths (10k enemies) can never flood the frame. One color-atlas SpriteBatch
-- (one draw call). Particles are pure eye-candy: no gameplay effect.
local Particles = {
  n = 0,
  cap = 2600,
  x = {}, y = {},
  vx = {}, vy = {},
  life = {}, maxLife = {},
  size = {}, drag = {}, grav = {},
  ci = {},
}

local SPR = 16
local SPRITE_R = 6

local COLOR_LIST = {
  "blood", "bloodDark", "dust", "debris",
  "fire", "spark", "dark", "purple", "green", "white",
}
local COLORS = {
  { 0.60, 0.07, 0.10 }, -- blood
  { 0.34, 0.03, 0.06 }, -- bloodDark
  { 0.42, 0.40, 0.44 }, -- dust
  { 0.50, 0.42, 0.32 }, -- debris
  { 1.00, 0.58, 0.20 }, -- fire
  { 1.00, 0.84, 0.42 }, -- spark
  { 0.30, 0.10, 0.38 }, -- dark
  { 0.70, 0.35, 0.85 }, -- purple
  { 0.40, 0.80, 0.30 }, -- green
  { 1.00, 0.96, 0.90 }, -- white
}
local CI = {}
for i = 1, #COLOR_LIST do CI[COLOR_LIST[i]] = i end

local batch, quads

local function init()
  if batch then return end
  local atlas = love.graphics.newCanvas(SPR * #COLORS, SPR)
  love.graphics.setCanvas(atlas)
  for c = 1, #COLORS do
    local col = COLORS[c]
    local cx, cy = (c - 1) * SPR + SPR / 2, SPR / 2
    for k = 1, 4 do
      local r = SPRITE_R * (0.35 + 0.17 * k)
      love.graphics.setColor(col[1], col[2], col[3], 0.32)
      love.graphics.circle("fill", cx, cy, r)
    end
  end
  love.graphics.setCanvas()
  quads = {}
  for c = 1, #COLORS do
    quads[c] = love.graphics.newQuad((c - 1) * SPR, 0, SPR, SPR, atlas:getDimensions())
  end
  batch = love.graphics.newSpriteBatch(atlas, Particles.cap, "dynamic")
end

local function emit(x, y, color, count, spdMin, spdMax, lifeMin, lifeMax, size, drag, grav)
  local P = Particles
  if P.n >= P.cap then return end
  local c = CI[color] or CI.white
  for _ = 1, count do
    if P.n >= P.cap then return end
    P.n = P.n + 1
    local i = P.n
    local a = love.math.random() * math.pi * 2
    local s = spdMin + love.math.random() * (spdMax - spdMin)
    P.x[i] = x + (love.math.random() - 0.5) * 6
    P.y[i] = y + (love.math.random() - 0.5) * 6
    P.vx[i] = math.cos(a) * s
    P.vy[i] = math.sin(a) * s
    local lf = lifeMin + love.math.random() * (lifeMax - lifeMin)
    P.life[i] = lf
    P.maxLife[i] = lf
    P.size[i] = size * (0.7 + love.math.random() * 0.6)
    P.drag[i] = drag
    P.grav[i] = grav
    P.ci[i] = c
  end
end

function Particles.blood(x, y, n)
  emit(x, y, "blood", n or 4, 20, 95, 0.25, 0.6, 3, 4, 30)
end

function Particles.dust(x, y, n)
  emit(x, y, "dust", n or 8, 12, 46, 0.5, 1.1, 3.5, 2, -4)
  emit(x, y, "debris", math.max(2, (n or 8) - 4), 20, 70, 0.4, 0.8, 2.6, 3, 60)
end

function Particles.trail(x, y, color)
  if Particles.n >= Particles.cap then return end
  emit(x, y, color or "spark", 1, 0, 8, 0.18, 0.32, 2.2, 6, 0)
end

function Particles.muzzle(x, y, dx, dy, color)
  local P = Particles
  if P.n >= P.cap then return end
  local c = CI[color or "spark"] or CI.spark
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.001 then dx, dy, len = 1, 0, 1 end
  dx, dy = dx / len, dy / len
  for _ = 1, 5 do
    if P.n >= P.cap then return end
    P.n = P.n + 1
    local i = P.n
    local rot = (love.math.random() - 0.5) * 0.7
    local cs, sn = math.cos(rot), math.sin(rot)
    local s = 60 + love.math.random() * 90
    P.x[i] = x
    P.y[i] = y
    P.vx[i] = (dx * cs - dy * sn) * s
    P.vy[i] = (dx * sn + dy * cs) * s
    P.life[i] = 0.12 + love.math.random() * 0.12
    P.maxLife[i] = P.life[i]
    P.size[i] = 2.4
    P.drag[i] = 5
    P.grav[i] = 0
    P.ci[i] = c
  end
end

function Particles.flame(x, y, n)
  emit(x, y, "fire", n or 2, 4, 22, 0.4, 0.9, 3.2, 2, -34)
  emit(x, y, "spark", 1, 8, 40, 0.2, 0.45, 1.8, 3, -20)
end

function Particles.ritual(x, y)
  emit(x, y, "dark", 16, 20, 70, 0.7, 1.6, 4, 2, -30)
  emit(x, y, "purple", 14, 30, 110, 0.6, 1.4, 3, 2.5, -20)
  emit(x, y, "fire", 6, 10, 40, 0.3, 0.7, 3, 2, -40)
end

function Particles.decal(x, y, color)
  local P = Particles
  if P.n >= P.cap then return end
  P.n = P.n + 1
  local i = P.n
  P.x[i] = x
  P.y[i] = y
  P.vx[i] = 0
  P.vy[i] = 0
  P.life[i] = 6
  P.maxLife[i] = 6
  P.size[i] = 5
  P.drag[i] = 20
  P.grav[i] = 0
  P.ci[i] = CI[color or "bloodDark"] or CI.bloodDark
end

local function swapRemove(i)
  local P = Particles
  local last = P.n
  P.x[i] = P.x[last]
  P.y[i] = P.y[last]
  P.vx[i] = P.vx[last]
  P.vy[i] = P.vy[last]
  P.life[i] = P.life[last]
  P.maxLife[i] = P.maxLife[last]
  P.size[i] = P.size[last]
  P.drag[i] = P.drag[last]
  P.grav[i] = P.grav[last]
  P.ci[i] = P.ci[last]
  P.n = last - 1
end

function Particles.update(dt)
  local P = Particles
  local i = 1
  while i <= P.n do
    local f = 1 - P.drag[i] * dt
    if f < 0 then f = 0 end
    P.vx[i] = P.vx[i] * f
    P.vy[i] = P.vy[i] * f + P.grav[i] * dt
    P.x[i] = P.x[i] + P.vx[i] * dt
    P.y[i] = P.y[i] + P.vy[i] * dt
    P.life[i] = P.life[i] - dt
    if P.life[i] <= 0 then
      swapRemove(i)
    else
      i = i + 1
    end
  end
end

function Particles.draw()
  if Particles.n == 0 then return end
  init()
  local P = Particles
  batch:clear()
  for i = 1, P.n do
    local frac = P.life[i] / P.maxLife[i]
    local s = (P.size[i] / SPRITE_R) * (0.35 + 0.65 * frac)
    batch:add(quads[P.ci[i]], P.x[i] - SPR / 2 * s, P.y[i] - SPR / 2 * s, 0, s, s)
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(batch)
end

function Particles.clear()
  Particles.n = 0
end

return Particles
