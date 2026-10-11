local Grid = { TILE = 32, WIDTH = 64, HEIGHT = 64, EDGE_MARGIN = 2 }

Grid.OCC_NONE = 0
Grid.OCC_WALL = 1
Grid.OCC_VILLAGE = 2

function Grid.resetOccupancy()
  local occ = Grid.occupancy
  if not occ then
    occ = {}
    Grid.occupancy = occ
  end
  for i = 1, Grid.WIDTH * Grid.HEIGHT do occ[i] = Grid.OCC_NONE end
end

function Grid.cellIndex(gx, gy) return gy * Grid.WIDTH + gx + 1 end

function Grid.pixelWidth() return Grid.WIDTH * Grid.TILE end

function Grid.pixelHeight() return Grid.HEIGHT * Grid.TILE end

function Grid.worldToTile(x, y)
  return math.floor(x / Grid.TILE), math.floor(y / Grid.TILE)
end

function Grid.tileToWorld(gx, gy)
  return (gx + 0.5) * Grid.TILE, (gy + 0.5) * Grid.TILE
end

function Grid.inBounds(gx, gy)
  return gx >= 0 and gy >= 0 and gx < Grid.WIDTH and gy < Grid.HEIGHT
end

function Grid.occAtWorld(x, y)
  local gx = math.floor(x / Grid.TILE)
  local gy = math.floor(y / Grid.TILE)
  if not Grid.inBounds(gx, gy) then return Grid.OCC_WALL end
  return Grid.occupancy[Grid.cellIndex(gx, gy)]
end

function Grid.occAtTile(gx, gy)
  if not Grid.inBounds(gx, gy) then return Grid.OCC_WALL end
  return Grid.occupancy[Grid.cellIndex(gx, gy)]
end

function Grid.cellsInCircle(cx, cy, r)
  local T = Grid.TILE
  local cells = {}
  local gx0, gy0 = Grid.worldToTile(cx - r, cy - r)
  local gx1, gy1 = Grid.worldToTile(cx + r, cy + r)
  for gy = gy0, gy1 do
    for gx = gx0, gx1 do
      local nx = math.max(gx * T, math.min(cx, (gx + 1) * T))
      local ny = math.max(gy * T, math.min(cy, (gy + 1) * T))
      local dx, dy = nx - cx, ny - cy
      if dx * dx + dy * dy <= r * r then
        cells[#cells + 1] = Grid.cellIndex(gx, gy)
      end
    end
  end
  return cells
end

return Grid
