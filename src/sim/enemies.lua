local enemyData = require("src.data.enemies")
local Grid = require("src.sim.grid")
local Flow = require("src.sim.flowfield")
local Walls = require("src.sim.walls")
local Buildings = require("src.sim.buildings")
local Villagers = require("src.sim.villagers")

local floor = math.floor
local sqrt = math.sqrt

local W, H = Grid.WIDTH, Grid.HEIGHT
local INV_TILE = 1 / Grid.TILE
local OCC_WALL = Grid.OCC_WALL
local OCC_BUILD = Grid.OCC_BUILD

local Enemies = {
  n = 0,
  x = {}, y = {},
  hx = {}, hy = {},
  hp = {}, maxHp = {},
  speed = {}, r = {},
  dmg = {}, attackTimer = {},
  hitFlash = {},
  kind = {},
  blk = {},
  kills = 0,
}

local KINDS = {}
local kindIndex = {}
for name in pairs(enemyData) do
  KINDS[#KINDS + 1] = name
end
table.sort(KINDS)
for i, name in ipairs(KINDS) do kindIndex[name] = i end

local attackInterval = {}
for i, name in ipairs(KINDS) do
  attackInterval[i] = enemyData[name].attackInterval
end

local flowX, flowY = Flow.flowX, Flow.flowY

local function spawn(x, y, kind, hpMul)
  local d = enemyData[kind]
  Enemies.n = Enemies.n + 1
  local i = Enemies.n
  Enemies.x[i] = x
  Enemies.y[i] = y
  local a = love.math.random() * math.pi * 2
  Enemies.hx[i] = math.cos(a)
  Enemies.hy[i] = math.sin(a)
  Enemies.hp[i] = d.hp * (hpMul or 1)
  Enemies.maxHp[i] = Enemies.hp[i]
  Enemies.speed[i] = d.speed
  Enemies.r[i] = d.r
  Enemies.dmg[i] = d.damage
  Enemies.attackTimer[i] = d.attackInterval
  Enemies.hitFlash[i] = 0
  Enemies.kind[i] = kindIndex[kind]
  Enemies.blk[i] = 0
  return i
end

local function damage(i, amount)
  if Enemies.hp[i] <= 0 then return end
  Enemies.hp[i] = Enemies.hp[i] - amount
  Enemies.hitFlash[i] = 0.08
end

local function compact()
  local E = Enemies
  local i = 1
  while i <= E.n do
    if E.hp[i] <= 0 then
      local last = E.n
      E.x[i] = E.x[last]
      E.y[i] = E.y[last]
      E.hx[i] = E.hx[last]
      E.hy[i] = E.hy[last]
      E.hp[i] = E.hp[last]
      E.maxHp[i] = E.maxHp[last]
      E.speed[i] = E.speed[last]
      E.r[i] = E.r[last]
      E.dmg[i] = E.dmg[last]
      E.attackTimer[i] = E.attackTimer[last]
      E.hitFlash[i] = E.hitFlash[last]
      E.kind[i] = E.kind[last]
      E.blk[i] = E.blk[last]
      E.n = E.n - 1
      E.kills = E.kills + 1
    else
      i = i + 1
    end
  end
end

local function wallAdjacent(i)
  local E = Enemies
  local T = Grid.TILE
  local px = E.x[i] + E.hx[i] * (E.r[i] + 12)
  local py = E.y[i] + E.hy[i] * (E.r[i] + 12)
  local w = Walls.at(floor(px / T), floor(py / T))
  if w > 0 then return w end
  local gx = floor((E.x[i] + E.hx[i] * 2) / T)
  local gy = floor((E.y[i] + E.hy[i] * 2) / T)
  local best, bd = 0, math.huge
  for k = 0, 3 do
    local ox = (k == 0 and 1) or (k == 1 and -1) or 0
    local oy = (k == 2 and 1) or (k == 3 and -1) or 0
    local wi = Walls.at(gx + ox, gy + oy)
    if wi > 0 then
      local wx, wy = Grid.tileToWorld(Walls.gx[wi], Walls.gy[wi])
      local dx, dy = wx - E.x[i], wy - E.y[i]
      local d = dx * dx + dy * dy
      if d < bd then
        bd = d
        best = wi
      end
    end
  end
  return best
end

local function buildingAdjacent(i)
  local E = Enemies
  local T = Grid.TILE
  local gx = floor((E.x[i] + E.hx[i] * 2) / T)
  local gy = floor((E.y[i] + E.hy[i] * 2) / T)
  local b = Buildings.at(gx, gy)
  if b > 0 then return b end
  for k = 0, 3 do
    local ox = (k == 0 and 1) or (k == 1 and -1) or 0
    local oy = (k == 2 and 1) or (k == 3 and -1) or 0
    b = Buildings.at(gx + ox, gy + oy)
    if b > 0 then return b end
  end
  return 0
end

local pvX, pvY, pvRange = 0, 0, 0
local function villagerNear(ctx)
  local list = ctx.villagers.list
  local best, bd = nil, pvRange * pvRange
  for k = 1, #list do
    local v = list[k]
    if not v.dead then
      local dx = v.x - pvX
      local dy = v.y - pvY
      local d2 = dx * dx + dy * dy
      if d2 < bd then
        bd = d2
        best = v
      end
    end
  end
  return best
end

local function update(dt, ctx)
  local E = Enemies
  local v = ctx.village
  local sepHash = ctx.sepHash or ctx.hash
  local buckets = sepHash.buckets
  local cols = sepHash.cols
  local cell = sepHash.cell
  local occ = Grid.occupancy
  local n = E.n
  for i = 1, n do
    if E.hitFlash[i] > 0 then E.hitFlash[i] = E.hitFlash[i] - dt end
    local xi = E.x[i]
    local yi = E.y[i]
    local dxv = v.x - xi
    local dyv = v.y - yi
    local stop = v.r + E.r[i]
    if dxv * dxv + dyv * dyv < stop * stop then
      E.blk[i] = 0
      E.attackTimer[i] = E.attackTimer[i] - dt
      if E.attackTimer[i] <= 0 then
        E.attackTimer[i] = attackInterval[E.kind[i]]
        pvX, pvY = xi, yi
        pvRange = E.r[i] + 12
        local pv = villagerNear(ctx)
        if pv then
          Villagers.damage(pv, E.dmg[i])
        else
          v.hp = math.max(0, v.hp - E.dmg[i])
        end
      end
    else
      local sx, sy = 0, 0
      if E.blk[i] == 0 then
        local reach = E.r[i] * 2
        local reach2 = reach * reach
        local gx0 = floor((xi - reach) / cell)
        local gx1 = floor((xi + reach) / cell)
        local gy0 = floor((yi - reach) / cell)
        local gy1 = floor((yi + reach) / cell)
        if gx0 < 0 then gx0 = 0 end
        if gy0 < 0 then gy0 = 0 end
        if gx1 >= cols then gx1 = cols - 1 end
        if gy1 >= cols then gy1 = cols - 1 end
        local seen, count = 0, 0
        for gy = gy0, gy1 do
          local row = gy * cols
          for gx = gx0, gx1 do
            local b = buckets[row + gx + 1]
            for k = 1, b.n do
              seen = seen + 1
              if seen > 24 then break end
              local j = b[k]
              if j ~= i then
                local dx = xi - E.x[j]
                local dy = yi - E.y[j]
                local d2 = dx * dx + dy * dy
                if d2 > 0.0001 and d2 < reach2 then
                  local d = sqrt(d2)
                  local push = (reach - d) / reach
                  sx = sx + dx / d * push
                  sy = sy + dy / d * push
                  count = count + 1
                end
              end
            end
            if seen > 24 or count >= 6 then break end
          end
          if seen > 24 or count >= 6 then break end
        end
        sx = sx * 60
        sy = sy * 60
      end
      local tx, ty = 0, 0
      local fgx = floor(xi * INV_TILE)
      local fgy = floor(yi * INV_TILE)
      if fgx >= 0 and fgy >= 0 and fgx < W and fgy < H then
        local c = fgy * W + fgx + 1
        tx = flowX[c]
        ty = flowY[c]
      end
      tx = tx + sx
      ty = ty + sy
      local k = math.min(1, 6 * dt)
      local nhx = E.hx[i] + (tx - E.hx[i]) * k
      local nhy = E.hy[i] + (ty - E.hy[i]) * k
      local len = sqrt(nhx * nhx + nhy * nhy)
      if len > 0.0001 then
        nhx = nhx / len
        nhy = nhy / len
      end
      E.hx[i] = nhx
      E.hy[i] = nhy
      local sp = E.speed[i] * dt
      local blocked = false
      local nx = xi + nhx * sp
      local ngx = floor(nx * INV_TILE)
      local ngy = floor(yi * INV_TILE)
      local oc = ngx < 0 or ngy < 0 or ngx >= W or ngy >= H
      if not oc then oc = occ[ngy * W + ngx + 1] == OCC_WALL or occ[ngy * W + ngx + 1] == OCC_BUILD end
      if oc then
        nx = xi
        blocked = true
      end
      E.x[i] = nx
      local ny = E.y[i] + nhy * sp
      ngx = floor(E.x[i] * INV_TILE)
      ngy = floor(ny * INV_TILE)
      oc = ngx < 0 or ngy < 0 or ngx >= W or ngy >= H
      if not oc then oc = occ[ngy * W + ngx + 1] == OCC_WALL or occ[ngy * W + ngx + 1] == OCC_BUILD end
      if oc then
        ny = E.y[i]
        blocked = true
      end
      E.y[i] = ny
      E.blk[i] = blocked and 1 or 0
      if blocked then
        E.attackTimer[i] = E.attackTimer[i] - dt
        if E.attackTimer[i] <= 0 then
          pvX, pvY = xi, yi
          pvRange = E.r[i] + 12
          local pv = villagerNear(ctx)
          if pv then
            E.attackTimer[i] = attackInterval[E.kind[i]]
            Villagers.damage(pv, E.dmg[i])
          else
            local w = wallAdjacent(i)
            if w > 0 then
              E.attackTimer[i] = attackInterval[E.kind[i]]
              Walls.damage(w, E.dmg[i])
            else
              local b = buildingAdjacent(i)
              if b > 0 then
                E.attackTimer[i] = attackInterval[E.kind[i]]
                Buildings.damage(b, E.dmg[i])
              end
            end
          end
        end
      end
    end
  end
end

Enemies.spawn = spawn
Enemies.damage = damage
Enemies.compact = compact
Enemies.update = update

return Enemies
