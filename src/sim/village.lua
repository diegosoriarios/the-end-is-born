local buildingData = require("src.data.buildings")

local Village = {}

function Village.new(x, y)
  local d = buildingData.village_center
  return { x = x, y = y, r = d.r, hp = d.hp, maxHp = d.hp }
end

function Village.damage(v, amount)
  v.hp = math.max(0, v.hp - amount)
end

return Village
