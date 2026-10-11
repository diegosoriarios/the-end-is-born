local Grid = require("src.sim.grid")

local Camera = { x = 0, y = 0, zoom = 1, minZoom = 0.4, maxZoom = 2.5 }

function Camera.reset()
  Camera.x = Grid.pixelWidth() / 2
  Camera.y = Grid.pixelHeight() / 2
  Camera.zoom = 1
end

function Camera.toWorld(mx, my)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  return (mx - w / 2) / Camera.zoom + Camera.x, (my - h / 2) / Camera.zoom + Camera.y
end

function Camera.viewBounds()
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local x0, y0 = Camera.toWorld(0, 0)
  local x1, y1 = Camera.toWorld(w, h)
  return x0, y0, x1, y1
end

function Camera.zoomBy(dy)
  local factor = dy > 0 and 1.1 or 0.9
  Camera.zoom = math.max(Camera.minZoom, math.min(Camera.maxZoom, Camera.zoom * factor))
end

function Camera.clamp()
  local hw = love.graphics.getWidth() / 2 / Camera.zoom
  local hh = love.graphics.getHeight() / 2 / Camera.zoom
  local W, H = Grid.pixelWidth(), Grid.pixelHeight()
  if W <= hw * 2 then
    Camera.x = W / 2
  else
    Camera.x = math.max(hw, math.min(W - hw, Camera.x))
  end
  if H <= hh * 2 then
    Camera.y = H / 2
  else
    Camera.y = math.max(hh, math.min(H - hh, Camera.y))
  end
end

function Camera.updateKeyboard(dt)
  local speed = 500 / Camera.zoom
  if love.keyboard.isDown("w", "up") then Camera.y = Camera.y - speed * dt end
  if love.keyboard.isDown("s", "down") then Camera.y = Camera.y + speed * dt end
  if love.keyboard.isDown("a", "left") then Camera.x = Camera.x - speed * dt end
  if love.keyboard.isDown("d", "right") then Camera.x = Camera.x + speed * dt end
  Camera.clamp()
end

function Camera.apply()
  love.graphics.push()
  love.graphics.translate(love.graphics.getWidth() / 2, love.graphics.getHeight() / 2)
  love.graphics.scale(Camera.zoom)
  love.graphics.translate(-Camera.x, -Camera.y)
end

function Camera.unapply()
  love.graphics.pop()
end

return Camera
