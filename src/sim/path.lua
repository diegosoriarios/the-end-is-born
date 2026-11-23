-- A* pathfinding for servants over the occupancy grid. Enemies keep their
-- baked flow-field; villagers need arbitrary goals (nodes, buildings, altars)
-- and must respect player-built walls.
local Grid = require("src.sim.grid")

local W, H = Grid.WIDTH, Grid.HEIGHT
local N = W * H
local SQRT2 = math.sqrt(2)

-- Reused per-search buffers. `seen`/`closed` hold a generation stamp so the
-- arrays never need clearing; only one search runs at a time.
local gScore, fScore, came = {}, {}, {}
local seen, closed = {}, {}
local stamp = 0

local heapIdx, heapF = {}, {}
local heapN = 0

local DIRS = {
  { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
  { 1, 1, SQRT2 }, { 1, -1, SQRT2 }, { -1, 1, SQRT2 }, { -1, -1, SQRT2 },
}

local function hpush(idx, f)
  local n = heapN + 1
  heapN = n
  while n > 1 do
    local p = math.floor(n / 2)
    if heapF[p] <= f then break end
    heapIdx[n], heapF[n] = heapIdx[p], heapF[p]
    n = p
  end
  heapIdx[n], heapF[n] = idx, f
end

local function hpop()
  if heapN == 0 then return nil, nil end
  local topIdx, topF = heapIdx[1], heapF[1]
  local lastIdx, lastF = heapIdx[heapN], heapF[heapN]
  heapN = heapN - 1
  if heapN > 0 then
    heapIdx[1], heapF[1] = lastIdx, lastF
    local i = 1
    while true do
      local l, r = i * 2, i * 2 + 1
      local m = i
      if l <= heapN and heapF[l] < heapF[m] then m = l end
      if r <= heapN and heapF[r] < heapF[m] then m = r end
      if m == i then break end
      heapIdx[i], heapIdx[m] = heapIdx[m], heapIdx[i]
      heapF[i], heapF[m] = heapF[m], heapF[i]
      i = m
    end
  end
  return topIdx, topF
end

local function heuristic(gx, gy, tgx, tgy)
  local dx = math.abs(tgx - gx)
  local dy = math.abs(tgy - gy)
  return (dx + dy) + (SQRT2 - 2) * math.min(dx, dy)
end

local function reconstruct(start, goal)
  local out = {}
  local idx = goal
  while idx ~= 0 and idx ~= start do
    out[#out + 1] = idx
    idx = came[idx]
  end
  local n = #out
  for i = 1, math.floor(n / 2) do
    out[i], out[n - i + 1] = out[n - i + 1], out[i]
  end
  return out
end

local Path = {}

-- Returns a list of cell indices from start (exclusive) to goal (inclusive),
-- or nil when no route exists. A solid start cell is allowed so a servant can
-- escape if a building was placed on top of them.
function Path.find(sgx, sgy, ggx, ggy)
  if not Grid.inBounds(sgx, sgy) or not Grid.inBounds(ggx, ggy) then return nil end
  if Grid.isSolidTile(ggx, ggy) then return nil end
  local start = Grid.cellIndex(sgx, sgy)
  local goal = Grid.cellIndex(ggx, ggy)
  if start == goal then return {} end

  stamp = stamp + 1
  heapN = 0
  seen[start] = stamp
  gScore[start] = 0
  fScore[start] = heuristic(sgx, sgy, ggx, ggy)
  came[start] = 0
  hpush(start, fScore[start])

  local expansions = 0
  while heapN > 0 do
    local idx, f = hpop()
    if f ~= nil and closed[idx] ~= stamp and f <= (fScore[idx] or math.huge) + 1e-9 then
      closed[idx] = stamp
      if idx == goal then return reconstruct(start, goal) end
      expansions = expansions + 1
      if expansions > N then return nil end

      local gx = (idx - 1) % W
      local gy = math.floor((idx - 1) / W)
      local g = gScore[idx]
      for d = 1, 8 do
        local dir = DIRS[d]
        local nx, ny = gx + dir[1], gy + dir[2]
        if Grid.inBounds(nx, ny) and not Grid.isSolidTile(nx, ny) then
          local diagonal = dir[1] ~= 0 and dir[2] ~= 0
          if not diagonal
            or (not Grid.isSolidTile(gx + dir[1], gy) and not Grid.isSolidTile(gx, gy + dir[2])) then
            local ni = Grid.cellIndex(nx, ny)
            local ng = g + dir[3]
            if seen[ni] ~= stamp or ng < (gScore[ni] or math.huge) then
              seen[ni] = stamp
              gScore[ni] = ng
              came[ni] = idx
              fScore[ni] = ng + heuristic(nx, ny, ggx, ggy)
              hpush(ni, fScore[ni])
            end
          end
        end
      end
    end
  end
  return nil
end

return Path
