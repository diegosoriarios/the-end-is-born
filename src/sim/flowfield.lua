local Grid = require("src.sim.grid")

local W, H = Grid.WIDTH, Grid.HEIGHT
local N = W * H
local INF = math.huge
local WALL_COST = 60

local nbDx = { 1, -1, 0, 0, 1, 1, -1, -1 }
local nbDy = { 0, 0, 1, -1, 1, -1, 1, -1 }
local nbDiag = { false, false, false, false, true, true, true, true }

local Flow = { dist = {}, flowX = {}, flowY = {}, rebakes = 0 }

local heap = {}
local heapD = {}
local heapN = 0

local function push(c, d)
  heapN = heapN + 1
  heap[heapN] = c
  heapD[heapN] = d
  local i = heapN
  while i > 1 do
    local p = math.floor(i / 2)
    if heapD[p] <= heapD[i] then break end
    heap[p], heap[i] = heap[i], heap[p]
    heapD[p], heapD[i] = heapD[i], heapD[p]
    i = p
  end
end

local function pop()
  local top = heap[1]
  heap[1] = heap[heapN]
  heapD[1] = heapD[heapN]
  heapN = heapN - 1
  local i = 1
  while true do
    local l, r = i * 2, i * 2 + 1
    local m = i
    if l <= heapN and heapD[l] < heapD[m] then m = l end
    if r <= heapN and heapD[r] < heapD[m] then m = r end
    if m == i then break end
    heap[m], heap[i] = heap[i], heap[m]
    heapD[m], heapD[i] = heapD[i], heapD[m]
    i = m
  end
  return top
end

local OCC_WALL, OCC_BUILD = Grid.OCC_WALL, Grid.OCC_BUILD

local function solid(v)
  return v == OCC_WALL or v == OCC_BUILD
end

local function cornerBlocked(gx, gy, k)
  local ox = nbDx[k]
  local oy = nbDy[k]
  if solid(Grid.occAtTile(gx + ox, gy)) then return true end
  if solid(Grid.occAtTile(gx, gy + oy)) then return true end
  return false
end

function Flow.rebake(sources)
  heapN = 0
  local dist = Flow.dist
  for i = 1, N do dist[i] = INF end
  for s = 1, #sources do
    local c = sources[s]
    if dist[c] ~= 0 then
      dist[c] = 0
      push(c, 0)
    end
  end
  local occ = Grid.occupancy
  while heapN > 0 do
    local c = pop()
    local dc = dist[c]
    local cgx = (c - 1) % W
    local cgy = math.floor((c - 1) / W)
    for k = 1, 8 do
      local nx = cgx + nbDx[k]
      local ny = cgy + nbDy[k]
      if nx >= 0 and ny >= 0 and nx < W and ny < H then
        if not (nbDiag[k] and cornerBlocked(cgx, cgy, k)) then
          local nc = ny * W + nx + 1
          local cost = nbDiag[k] and 1.42 or 1
          if solid(occ[nc]) then cost = cost + WALL_COST end
          local nd = dc + cost
          if nd < dist[nc] then
            dist[nc] = nd
            push(nc, nd)
          end
        end
      end
    end
  end
  Flow.computeDirections()
  Flow.rebakes = Flow.rebakes + 1
end

function Flow.computeDirections()
  local dist = Flow.dist
  local fx, fy = Flow.flowX, Flow.flowY
  local occ = Grid.occupancy
  for c = 1, N do
    if solid(occ[c]) or dist[c] == INF then
      fx[c] = 0
      fy[c] = 0
    else
      local cgx = (c - 1) % W
      local cgy = math.floor((c - 1) / W)
      local best = dist[c]
      local bx, by = 0, 0
      for k = 1, 8 do
        local nx = cgx + nbDx[k]
        local ny = cgy + nbDy[k]
        if nx >= 0 and ny >= 0 and nx < W and ny < H then
          if not (nbDiag[k] and cornerBlocked(cgx, cgy, k)) then
            local nd = dist[ny * W + nx + 1]
            if nd < best then
              best = nd
              bx, by = nbDx[k], nbDy[k]
            end
          end
        end
      end
      if bx ~= 0 or by ~= 0 then
        local len = math.sqrt(bx * bx + by * by)
        fx[c] = bx / len
        fy[c] = by / len
      else
        fx[c] = 0
        fy[c] = 0
      end
    end
  end
end

function Flow.dirAt(x, y)
  local gx = math.floor(x / Grid.TILE)
  local gy = math.floor(y / Grid.TILE)
  if gx < 0 or gy < 0 or gx >= W or gy >= H then return 0, 0 end
  local c = gy * W + gx + 1
  return Flow.flowX[c], Flow.flowY[c]
end

return Flow
