local Grid = require("src.sim.grid")

local Camera = {
  x = 0, y = 0, zoom = 1, minZoom = 0.4, maxZoom = 2.5,
  shakeAmt = 0, shakeT = 0, shakeDur = 0, shakeX = 0, shakeY = 0,
  shakeEnabled = true,
}

function Camera.setShakeEnabled(v)
  Camera.shakeEnabled = v and true or false
  if not Camera.shakeEnabled then
    Camera.shakeAmt = 0
    Camera.shakeT = 0
    Camera.shakeX, Camera.shakeY = 0, 0
  end
end

function Camera.reset()
  Camera.x = Grid.pixelWidth() / 2
  Camera.y = Grid.pixelHeight() / 2
  Camera.zoom = 1
  Camera.shakeAmt = 0
  Camera.shakeT = 0
  Camera.shakeX = 0
  Camera.shakeY = 0
end

-- Request a screen shake; keeps the strongest active impulse.
function Camera.shake(amount, duration)
  if not Camera.shakeEnabled then return end
  if amount > Camera.shakeAmt then Camera.shakeAmt = amount end
  Camera.shakeDur = math.max(Camera.shakeDur, duration or 0.35)
  Camera.shakeT = Camera.shakeDur
end

function Camera.updateShake(dt)
  if Camera.shakeT <= 0 then
    Camera.shakeX, Camera.shakeY = 0, 0
    return
  end
  Camera.shakeT = Camera.shakeT - dt
  local k = math.max(0, Camera.shakeT / Camera.shakeDur)
  local a = Camera.shakeAmt * k * k
  Camera.shakeX = (love.math.random() * 2 - 1) * a
  Camera.shakeY = (love.math.random() * 2 - 1) * a
  if Camera.shakeT <= 0 then
    Camera.shakeAmt = 0
    Camera.shakeX, Camera.shakeY = 0, 0
  end
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
  local panned = false
  if love.keyboard.isDown("w", "up") then Camera.y = Camera.y - speed * dt; panned = true end
  if love.keyboard.isDown("s", "down") then Camera.y = Camera.y + speed * dt; panned = true end
  if love.keyboard.isDown("a", "left") then Camera.x = Camera.x - speed * dt; panned = true end
  if love.keyboard.isDown("d", "right") then Camera.x = Camera.x + speed * dt; panned = true end
  Camera.clamp()
  return panned
end

function Camera.apply()
  love.graphics.push()
  love.graphics.translate(love.graphics.getWidth() / 2, love.graphics.getHeight() / 2)
  love.graphics.scale(Camera.zoom)
  love.graphics.translate(-Camera.x + Camera.shakeX, -Camera.y + Camera.shakeY)
end

function Camera.unapply()
  love.graphics.pop()
end

return Camera
