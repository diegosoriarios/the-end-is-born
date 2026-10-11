local vData = require("src.data.villagers")
local resData = require("src.data.resources")
local buildingData = require("src.data.buildings")
local Grid = require("src.sim.grid")
local Nodes = require("src.sim.nodes")
local Buildings = require("src.sim.buildings")

local Villagers = { list = {} }
local nextId = 1

local JOB_LABEL = {
  idle = "Idle",
  wood = "Gathering wood",
  food = "Gathering food",
  stone = "Gathering stone",
  build = "Building",
  crew = "Crewing defense",
}

local slotOff = { { 20, 0 }, { -20, 0 }, { 0, 20 }, { 0, -20 } }

function Villagers.clear()
  Villagers.list = {}
  nextId = 1
end

function Villagers.spawn(x, y, sex, family)
  local v = {
    id = nextId,
    x = x, y = y,
    sex = sex, family = family,
    hp = vData.hp, maxHp = vData.hp,
    r = vData.r,
    hunger = 0,
    job = "idle",
    state = "idle",
    carry = 0, carryRes = nil,
    node = nil,
    buildTarget = 0,
    building = nil,
    timer = love.math.random() * vData.wanderInterval,
    wx = x, wy = y,
    flash = 0,
    dead = false,
  }
  nextId = nextId + 1
  Villagers.list[#Villagers.list + 1] = v
  return v
end

function Villagers.count()
  local c = 0
  local list = Villagers.list
  for i = 1, #list do
    if not list[i].dead then c = c + 1 end
  end
  return c
end

function Villagers.jobLabel(v)
  return JOB_LABEL[v.job] or v.job
end

function Villagers.damage(v, amount)
  if v.dead then return end
  v.hp = v.hp - amount
  v.flash = 0.08
end

local function move(v, tx, ty, dt, arriveDist)
  local dx, dy = tx - v.x, ty - v.y
  local d2 = dx * dx + dy * dy
  if d2 <= arriveDist * arriveDist then return true end
  local d = math.sqrt(d2)
  local step = vData.speed * dt
  if d <= step then
    v.x, v.y = tx, ty
    return true
  end
  v.x = v.x + dx / d * step
  v.y = v.y + dy / d * step
  return false
end

local function idleWander(v, dt, ctx)
  v.timer = v.timer - dt
  if v.timer <= 0 then
    v.timer = vData.wanderInterval * (0.6 + love.math.random() * 0.8)
    local a = love.math.random() * math.pi * 2
    local rr = 20 + love.math.random() * 70
    v.wx = ctx.village.x + math.cos(a) * rr
    v.wy = ctx.village.y + math.sin(a) * rr
  end
  move(v, v.wx, v.wy, dt, 4)
  v.state = "idle"
end

local function findBuildTarget(v)
  local best, bd = 0, math.huge
  for i = 1, Buildings.n do
    if not Buildings.built[i] then
      local dx, dy = Buildings.x[i] - v.x, Buildings.y[i] - v.y
      local d2 = dx * dx + dy * dy
      if d2 < bd then
        bd = d2
        best = i
      end
    end
  end
  return best
end

local function updateGather(v, dt, ctx, res)
  local cap = resData.carryCap
  if v.carry >= cap then v.state = "toDepot" end
  if v.state == "toDepot" then
    if move(v, ctx.village.x, ctx.village.y, dt, ctx.village.r * 0.7) then
      if v.carry > 0 and v.carryRes then
        ctx.stock[v.carryRes] = ctx.stock[v.carryRes] + v.carry
      end
      v.carry = 0
      v.carryRes = nil
      v.state = "toNode"
    end
    return
  end
  local node = v.node
  if not node or node.amount <= 0 then
    node = Nodes.nearest(v.x, v.y, res)
    v.node = node
    if not node then
      if v.carry > 0 then
        v.state = "toDepot"
      else
        idleWander(v, dt, ctx)
      end
      return
    end
    v.state = "toNode"
  end
  if v.state == "toNode" then
    if move(v, node.x, node.y, dt, node.r + v.r + 4) then
      v.state = "gathering"
      v.timer = resData.gatherInterval
    end
  elseif v.state == "gathering" then
    v.timer = v.timer - dt
    if v.timer <= 0 then
      if node.amount > 0 then
        node.amount = node.amount - 1
        v.carry = v.carry + 1
        v.carryRes = node.res
        if v.carry >= cap then
          v.state = "toDepot"
        else
          v.timer = resData.gatherInterval
        end
      else
        v.node = nil
      end
    end
  else
    v.state = "toNode"
  end
end

local function updateVillager(v, dt, ctx)
  v.hunger = math.min(150, v.hunger + vData.hungerRate * dt)
  if v.hunger > vData.eatAt and ctx.stock.food >= 1 then
    ctx.stock.food = ctx.stock.food - 1
    v.hunger = v.hunger - vData.eatRelief
  end
  if v.hunger >= 100 then
    v.hp = v.hp - vData.starveDps * dt
  end
  if v.flash > 0 then v.flash = v.flash - dt end
  if v.hp <= 0 then
    v.dead = true
    return
  end

  local job = v.job
  if job == "crew" then
    local b = v.building
    if not b or b > Buildings.n or not Buildings.isTower[b] then
      v.job, v.state = "idle", "idle"
      v.building = nil
      return
    end
    if v.state ~= "crewing" then
      local off = slotOff[(v.id % #slotOff) + 1]
      if move(v, Buildings.x[b] + off[1], Buildings.y[b] + off[2], dt, 6) then
        v.state = "crewing"
      end
    end
    return
  end

  if job == "build" then
    if v.buildTarget == 0 or v.buildTarget > Buildings.n or Buildings.built[v.buildTarget] then
      v.buildTarget = findBuildTarget(v)
    end
    if v.buildTarget == 0 then
      idleWander(v, dt, ctx)
      return
    end
    local b = v.buildTarget
    if move(v, Buildings.x[b], Buildings.y[b], dt, Grid.TILE * 0.9) then
      local d = buildingData[Buildings.kind[b]]
      Buildings.progress[b] = Buildings.progress[b] + vData.buildRate * dt
      if Buildings.progress[b] >= d.buildTime then
        Buildings.built[b] = true
        Buildings.progress[b] = d.buildTime
        v.buildTarget = 0
      end
    end
    return
  end

  if job == "wood" or job == "food" or job == "stone" then
    updateGather(v, dt, ctx, job)
    return
  end

  idleWander(v, dt, ctx)
end

function Villagers.update(dt, ctx)
  local list = Villagers.list
  for i = 1, #list do
    updateVillager(list[i], dt, ctx)
  end
  local w = 0
  for i = 1, #list do
    local v = list[i]
    if v.dead then
      if v.building and v.building <= Buildings.n then
        Buildings.crewCount[v.building] = Buildings.crewCount[v.building] - 1
      end
    else
      w = w + 1
      list[w] = v
    end
  end
  for i = w + 1, #list do
    list[i] = nil
  end
end

function Villagers.assignCrew(b)
  local pick
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and v.job == "idle" then
      pick = v
      break
    end
  end
  if not pick then
    for i = 1, #list do
      local v = list[i]
      if not v.dead and v.job ~= "crew" then
        pick = v
        break
      end
    end
  end
  if not pick then return false end
  pick.job = "crew"
  pick.state = "walking"
  pick.building = b
  pick.node = nil
  pick.buildTarget = 0
  Buildings.crewCount[b] = Buildings.crewCount[b] + 1
  return true
end

function Villagers.unassignCrew(b)
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and v.job == "crew" and v.building == b then
      Buildings.crewCount[b] = Buildings.crewCount[b] - 1
      v.job, v.state = "idle", "idle"
      v.building = nil
      return true
    end
  end
  return false
end

function Villagers.setJob(v, job)
  if v.job == "crew" and job ~= "crew" then
    Buildings.crewCount[v.building] = Buildings.crewCount[v.building] - 1
    v.building = nil
  end
  v.job = job
  v.state = "idle"
  v.node = nil
  v.buildTarget = 0
end

function Villagers.onBuildingRemoved(destroyed, movedFrom, movedTo)
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if movedFrom and v.building == movedFrom then
      v.building = movedTo
    elseif v.building == destroyed then
      v.job, v.state = "idle", "idle"
      v.building = nil
    end
    if movedFrom and v.buildTarget == movedFrom then
      v.buildTarget = movedTo or 0
    elseif v.buildTarget == destroyed then
      v.buildTarget = 0
    end
  end
end

return Villagers
