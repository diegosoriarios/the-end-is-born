local Grid = require("src.sim.grid")

local SpatialHash = {}
SpatialHash.__index = SpatialHash

function SpatialHash.new(cellSize)
  local self = setmetatable({ cell = cellSize, buckets = {} }, SpatialHash)
  local cols = math.ceil(Grid.WIDTH * Grid.TILE / cellSize)
  local rows = math.ceil(Grid.HEIGHT * Grid.TILE / cellSize)
  self.cols = cols
  self.rows = rows
  for i = 1, cols * rows do
    self.buckets[i] = { n = 0 }
  end
  return self
end

function SpatialHash:rebuild(enemies)
  local buckets = self.buckets
  for i = 1, #buckets do buckets[i].n = 0 end
  local c = self.cell
  local n = enemies.n
  local ex, ey = enemies.x, enemies.y
  for i = 1, n do
    local gx = math.floor(ex[i] / c)
    local gy = math.floor(ey[i] / c)
    if gx < 0 then gx = 0 elseif gx >= self.cols then gx = self.cols - 1 end
    if gy < 0 then gy = 0 elseif gy >= self.rows then gy = self.rows - 1 end
    local b = buckets[gy * self.cols + gx + 1]
    local k = b.n + 1
    b.n = k
    b[k] = i
  end
end

function SpatialHash:queryCircle(x, y, r, fn, maxVisits)
  local c = self.cell
  local x0 = math.floor((x - r) / c)
  local x1 = math.floor((x + r) / c)
  local y0 = math.floor((y - r) / c)
  local y1 = math.floor((y + r) / c)
  if x0 < 0 then x0 = 0 end
  if y0 < 0 then y0 = 0 end
  if x1 >= self.cols then x1 = self.cols - 1 end
  if y1 >= self.rows then y1 = self.rows - 1 end
  local buckets = self.buckets
  local cols = self.cols
  local visits = 0
  for gy = y0, y1 do
    local row = gy * cols
    for gx = x0, x1 do
      local b = buckets[row + gx + 1]
      local n = b.n
      for i = 1, n do
        visits = visits + 1
        if maxVisits and visits > maxVisits then return end
        fn(b[i])
      end
    end
  end
end

return SpatialHash
