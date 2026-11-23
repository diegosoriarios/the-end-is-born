local vData = require("src.data.villagers")
local resData = require("src.data.resources")
local buildingData = require("src.data.buildings")
local Grid = require("src.sim.grid")
local Path = require("src.sim.path")
local Nodes = require("src.sim.nodes")
local Buildings = require("src.sim.buildings")
local Particles = require("src.fx.particles")
local Camera = require("src.core.camera")
local Audio = require("src.audio.audio")
local Stats = require("src.sim.stats")

local Villagers = {
  list = {}, deaths = 0, onSacrificed = nil, onNotice = nil, onHeartSacrifice = nil, onDeath = nil,
  couples = {}, request = nil, conceived = false, failReason = nil, seenEpoch = 0,
  mobilized = false, vesselId = nil,
}
local nextId = 1
local nextCouple = 1

-- Forward declarations (defined at the bottom of the module).
local dissolveOnDeath, advanceMonths, updateConceptions, finishConception

local JOB_LABEL = {
  idle = "Idle",
  wood = "Gathering wood",
  food = "Gathering food",
  stone = "Gathering stone",
  build = "Building",
  crew = "Crewing defense",
  research = "Researching",
  shelter = "Sheltering",
  home = "At home",
  sacrifice = "Walking to the altar",
  conceive = "Walking to the altar",
}

local slotOff = { { 20, 0 }, { -20, 0 }, { 0, 20 }, { 0, -20 } }

-- Release a villager from a crew/research building slot (keeps counters in
-- sync when their job changes or they're reassigned).
local function unassignBuilding(v)
  local b = v.building
  if b and b <= Buildings.n then
    if v.job == "crew" then
      Buildings.crewCount[b] = math.max(0, (Buildings.crewCount[b] or 0) - 1)
    elseif v.job == "research" then
      Buildings.researchers[b] = math.max(0, (Buildings.researchers[b] or 0) - 1)
    end
  end
  v.building = nil
end

-- Swords: probe the enemy hash for the nearest target in melee range.
local probeE, probeX, probeY, probeBest, probeBestD = nil, 0, 0, 0, 0
local function vprobe(j)
  local dx = probeX - probeE.x[j]
  local dy = probeY - probeE.y[j]
  local d2 = dx * dx + dy * dy
  if d2 < probeBestD and probeE.hp[j] > 0 then
    probeBestD = d2
    probeBest = j
  end
end

-- Where a villager shelters / rests: their couple's house, else the heart.
local function homePos(v, ctx)
  if v.coupleId then
    for i = 1, #Villagers.couples do
      local c = Villagers.couples[i]
      if c.id == v.coupleId and c.house and c.house <= Buildings.n then
        return Buildings.x[c.house], Buildings.y[c.house]
      end
    end
  end
  return ctx.village.x, ctx.village.y
end

function Villagers.clear()
  Villagers.list = {}
  Villagers.deaths = 0
  Villagers.onSacrificed = nil
  Villagers.onNotice = nil
  Villagers.onHeartSacrifice = nil
  Villagers.onDeath = nil
  Villagers.couples = {}
  Villagers.request = nil
  Villagers.conceived = false
  Villagers.failReason = nil
  Villagers.seenEpoch = 0
  Villagers.mobilized = false
  Villagers.vesselId = nil
  nextId = 1
  nextCouple = 1
end

function Villagers.spawn(x, y, sex, family)
  local v = {
    id = nextId,
    x = x, y = y,
    sex = sex, family = family,
    hp = vData.hp, maxHp = vData.hp,
    r = vData.r,
    job = "idle",
    state = "idle",
    carry = 0, carryRes = nil,
    node = nil,
    buildTarget = 0,
    building = nil,
    timer = love.math.random() * vData.wanderInterval,
    wx = x, wy = y,
    flash = 0,
    atk = 0,
    dead = false,
    undead = false,
    confined = false,
    mob = nil,
    path = nil, pathI = 0, pathDone = false, pathVersion = nil, blockedTime = 0,
    age = "adult",
    growLeft = 0,
    coupleId = nil,
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

function Villagers.roster()
  local out = {}
  local list = Villagers.list
  for i = 1, #list do
    if not list[i].dead then out[#out + 1] = list[i] end
  end
  return out
end

function Villagers.jobLabel(v)
  return JOB_LABEL[v.job] or v.job
end

function Villagers.damage(v, amount)
  if v.dead then return end
  local armor = Stats.bonus("villagerArmor")
  if armor > 0 then amount = amount / (1 + armor) end
  v.hp = v.hp - amount
  v.flash = 0.08
  Particles.blood(v.x, v.y, 1)
  Audio.play("hit")
end

function Villagers.kill(v)
  if v.dead then return end
  v.dead = true
  v.hp = 0
  Particles.blood(v.x, v.y, 6)
  Particles.decal(v.x, v.y, "bloodDark")
  Camera.shake(2, 0.2)
  Audio.play("squelch", { pitch = 0.85 })
  if not v.undead then
    Villagers.deaths = Villagers.deaths + 1
    if Villagers.onDeath then Villagers.onDeath(v) end
  end
  if v.coupleId then dissolveOnDeath(v) end
end

-- Raise a servant from the grave (Graveyard necromancy).
function Villagers.spawnUndead(x, y)
  local v = Villagers.spawn(x, y, love.math.random() < 0.5 and "m" or "f", 0)
  v.undead = true
  return v
end

local REPATH_DIST2 = 24 * 24
local BLOCKED_REPATH = 0.35
local WAYPOINT_DIST = 6
local REPATH_BUDGET = 8
local repathBudget = 0
local PATH_W = Grid.WIDTH

local function pathWorld(idx)
  local gx = (idx - 1) % PATH_W
  local gy = math.floor((idx - 1) / PATH_W)
  return Grid.tileToWorld(gx, gy)
end

-- Solid tiles block movement, except that a servant already stuck inside one
-- is allowed to walk out (buildings can be placed on top of them).
local function blockedTileFor(v, x, y)
  local gx, gy = Grid.worldToTile(x, y)
  if not Grid.isSolidTile(gx, gy) then return false end
  local cgx, cgy = Grid.worldToTile(v.x, v.y)
  return not Grid.isSolidTile(cgx, cgy)
end

local function requestPath(v, tx, ty)
  if repathBudget <= 0 then return false end
  repathBudget = repathBudget - 1
  local sgx, sgy = Grid.worldToTile(v.x, v.y)
  local ggx, ggy = Grid.worldToTile(tx, ty)
  if Grid.isSolidTile(ggx, ggy) then
    local nx, ny = Grid.nearestFree(ggx, ggy)
    if not nx then
      v.path, v.pathI, v.pathDone = nil, 0, true
      v.pathVersion = Grid.version
      v.pathGoalX, v.pathGoalY = tx, ty
      return false
    end
    ggx, ggy = nx, ny
  end
  v.path = Path.find(sgx, sgy, ggx, ggy)
  v.pathI = 1
  v.pathDone = false
  v.pathVersion = Grid.version
  v.pathGoalX, v.pathGoalY = tx, ty
  return v.path ~= nil
end

-- Cheap crowd separation: nudge away from nearby servants so they spread out
-- around nodes and doorways instead of stacking on one pixel.
local function separation(v)
  local sx, sy = 0, 0
  local list = Villagers.list
  for i = 1, #list do
    local o = list[i]
    if o ~= v and not o.dead then
      local dx, dy = v.x - o.x, v.y - o.y
      local rr = v.r + o.r + 3
      local d2 = dx * dx + dy * dy
      if d2 > 0.0001 and d2 < rr * rr then
        local d = math.sqrt(d2)
        local push = (rr - d) / rr
        sx = sx + dx / d * push
        sy = sy + dy / d * push
      end
    end
  end
  return sx, sy
end

local function move(v, tx, ty, dt, arriveDist)
  local dx, dy = tx - v.x, ty - v.y
  local d2 = dx * dx + dy * dy
  if d2 <= arriveDist * arriveDist then
    v.path, v.pathI, v.pathDone, v.blockedTime = nil, 0, false, 0
    return true
  end

  local goalMoved = not v.pathGoalX
    or (tx - v.pathGoalX) * (tx - v.pathGoalX) + (ty - v.pathGoalY) * (ty - v.pathGoalY) > REPATH_DIST2
  local stale = v.pathVersion ~= Grid.version
  if stale or goalMoved then
    v.path, v.pathDone = nil, false
  end
  if (v.path == nil and not v.pathDone) or goalMoved or stale then
    requestPath(v, tx, ty)
  elseif v.blockedTime and v.blockedTime > BLOCKED_REPATH then
    v.pathDone = false
    requestPath(v, tx, ty)
    v.blockedTime = 0
  end

  local mx, my = 0, 0
  if v.path and v.pathI <= #v.path then
    local guard = 0
    while v.pathI <= #v.path and guard < 8 do
      guard = guard + 1
      local wx, wy = pathWorld(v.path[v.pathI])
      local wdx, wdy = wx - v.x, wy - v.y
      if wdx * wdx + wdy * wdy <= WAYPOINT_DIST * WAYPOINT_DIST then
        v.pathI = v.pathI + 1
      else
        mx, my = wdx, wdy
        break
      end
    end
    if v.pathI > #v.path then
      v.path, v.pathDone = nil, true
    end
  end
  if mx == 0 and my == 0 then
    mx, my = dx, dy
  end
  local ml = math.sqrt(mx * mx + my * my)
  if ml < 0.0001 then
    mx, my, ml = 1, 0, 1
  end

  local sx, sy = separation(v)
  mx = mx / ml + sx * 0.8
  my = my / ml + sy * 0.8
  local nl = math.sqrt(mx * mx + my * my)
  if nl < 0.0001 then return false end
  mx, my = mx / nl, my / nl

  local step = vData.speed * dt
  if d2 <= step * step and not blockedTileFor(v, tx, ty) then
    v.x, v.y = tx, ty
    v.path, v.pathI, v.pathDone, v.blockedTime = nil, 0, false, 0
    return true
  end

  local moved = false
  local nx = v.x + mx * step
  if not blockedTileFor(v, nx, v.y) then
    v.x = nx
    moved = true
  end
  local ny = v.y + my * step
  if not blockedTileFor(v, v.x, ny) then
    v.y = ny
    moved = true
  end
  if moved then
    v.blockedTime = 0
  else
    v.blockedTime = (v.blockedTime or 0) + dt
  end
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
      local rate = Stats.value("gatherSpeed") * Villagers.workMul(v)
      v.timer = rate > 0 and (resData.gatherInterval / rate) or resData.gatherInterval
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
          local rate = Stats.value("gatherSpeed") * Villagers.workMul(v)
          v.timer = rate > 0 and (resData.gatherInterval / rate) or resData.gatherInterval
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
  if v.flash > 0 then v.flash = v.flash - dt end
  if v.hp <= 0 then
    Villagers.kill(v)
    return
  end

  -- Pregnancy confinement: the mother stays home until the child is born.
  if v.confined then
    local hx, hy = homePos(v, ctx)
    move(v, hx, hy, dt, 8)
    v.state = "home"
    return
  end

  -- Swords research: armed servants strike nearby foes.
  if Stats.bonus("villagerDamage") > 0 and v.age ~= "child" then
    v.atk = (v.atk or 0) - dt
    if v.atk <= 0 and ctx.hash and ctx.enemies then
      probeE = ctx.enemies
      probeX, probeY = v.x, v.y
      probeBest, probeBestD = 0, (v.r + 12) * (v.r + 12)
      ctx.hash:queryCircle(v.x, v.y, v.r + 12, vprobe)
      if probeBest > 0 then
        ctx.enemies.damage(probeBest, 5 * Stats.value("villagerDamage"))
        v.atk = 1.0
        Particles.blood(v.x, v.y, 3)
      end
    end
  end

  local job = v.job
  if job == "sacrifice" then
    local tx, ty, valid = 0, 0, false
    if v.altar == "heart" then
      tx, ty, valid = ctx.village.x, ctx.village.y, true
    else
      local b = v.altar
      valid = b and b <= Buildings.n and Buildings.kind[b] == "altar" and Buildings.built[b]
      if valid then tx, ty = Buildings.x[b], Buildings.y[b] end
    end
    if not valid then
      v.job, v.state, v.altar = "idle", "idle", nil
      return
    end
    local off = slotOff[(v.id % #slotOff) + 1]
    if move(v, tx + off[1], ty + off[2], dt, 6) then
      Audio.play("sacrifice")
      if v.altar == "heart" then
        Particles.ritual(tx, ty)
        Villagers.kill(v)
        if Villagers.onHeartSacrifice then Villagers.onHeartSacrifice(v) end
      else
        Particles.flame(tx, ty, 6)
        Villagers.kill(v)
        if Villagers.onSacrificed then Villagers.onSacrificed(v) end
      end
    end
    return
  end

  if job == "conceive" then
    local b = v.altar
    if not b or b > Buildings.n or Buildings.kind[b] ~= "altar" or not Buildings.built[b] then
      v.job, v.state = "idle", "idle"
      v.altar = nil
      return
    end
    local off = slotOff[(v.id % #slotOff) + 1]
    if move(v, Buildings.x[b] + off[1], Buildings.y[b] + off[2], dt, 6) then
      v.state = "arrived"
    end
    return
  end

  if job == "shelter" then
    local hx, hy = homePos(v, ctx)
    move(v, hx, hy, dt, 8)
    v.state = "sheltered"
    return
  end

  if v.age == "child" then
    idleWander(v, dt, ctx)
    return
  end

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

  if job == "research" then
    local b = v.building
    if not b or b > Buildings.n or Buildings.role[b] ~= "research" or not Buildings.built[b] then
      unassignBuilding(v)
      v.job, v.state = "idle", "idle"
      return
    end
    if v.state ~= "researching" then
      local off = slotOff[(v.id % #slotOff) + 1]
      if move(v, Buildings.x[b] + off[1], Buildings.y[b] + off[2], dt, 6) then
        v.state = "researching"
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
      Buildings.progress[b] = Buildings.progress[b]
        + vData.buildRate * Stats.value("buildSpeed") * Villagers.workMul(v) * dt
      if Buildings.progress[b] >= d.buildTime then
        Buildings.built[b] = true
        Buildings.progress[b] = d.buildTime
        v.buildTarget = 0
        Particles.dust(Buildings.x[b], Buildings.y[b], 10)
        Audio.play("build_done", { pitch = 1 + (love.math.random() - 0.5) * 0.1 })
        Buildings.emitBuilt(b)
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
  repathBudget = REPATH_BUDGET
  local list = Villagers.list
  for i = 1, #list do
    updateVillager(list[i], dt, ctx)
  end
  local w = 0
  for i = 1, #list do
    local v = list[i]
    if v.dead then
      if v.building and v.building <= Buildings.n then
        if v.job == "crew" then
          Buildings.crewCount[v.building] = math.max(0, Buildings.crewCount[v.building] - 1)
        elseif v.job == "research" then
          Buildings.researchers[v.building] = math.max(0, (Buildings.researchers[v.building] or 0) - 1)
        end
      end
    else
      w = w + 1
      list[w] = v
    end
  end
  for i = w + 1, #list do
    list[i] = nil
  end
  local cal = ctx.waves and ctx.waves.calendar
  if cal and cal.epoch > Villagers.seenEpoch then
    local n = cal.epoch - Villagers.seenEpoch
    Villagers.seenEpoch = cal.epoch
    advanceMonths(n, ctx)
  end
  updateConceptions(ctx)
end

function Villagers.assignCrew(b)
  local pick
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and not v.confined and v.age ~= "child" and v.job == "idle" then
      pick = v
      break
    end
  end
  if not pick then
    for i = 1, #list do
      local v = list[i]
      if not v.dead and v.age ~= "child" and v.job ~= "crew" and v.job ~= "research"
        and v.job ~= "sacrifice" and v.job ~= "conceive" then
        pick = v
        break
      end
    end
  end
  if not pick then return false end
  unassignBuilding(pick)
  pick.job = "crew"
  pick.state = "walking"
  pick.building = b
  pick.node = nil
  pick.buildTarget = 0
  Buildings.crewCount[b] = Buildings.crewCount[b] + 1
  return true
end

function Villagers.assignResearcher(b)
  local d = buildingData[Buildings.kind[b]]
  local slots = d and d.researchSlots or 0
  if (Buildings.researchers[b] or 0) >= slots then return false end
  local pick
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and not v.confined and v.age ~= "child" and v.job == "idle" then pick = v break end
  end
  if not pick then return false end
  unassignBuilding(pick)
  pick.job, pick.state = "research", "walking"
  pick.building = b
  pick.node = nil
  pick.buildTarget = 0
  Buildings.researchers[b] = (Buildings.researchers[b] or 0) + 1
  return true
end

-- Assign a specific villager (used by right-click targeting).
function Villagers.assignNode(v, node)
  if not v or v.dead or v.confined or v.age == "child"
    or v.job == "sacrifice" or v.job == "conceive" then return false end
  if not node then return false end
  unassignBuilding(v)
  v.job = node.res
  v.state = "toNode"
  v.node = node
  v.buildTarget = 0
  v.altar = nil
  return true
end

function Villagers.assignBuild(v, b)
  if not v or v.dead or v.confined or v.age == "child"
    or v.job == "sacrifice" or v.job == "conceive" then return false end
  if not b or b > Buildings.n then return false end
  unassignBuilding(v)
  v.job, v.state = "build", "idle"
  v.buildTarget = b
  v.node, v.altar = nil, nil
  return true
end

function Villagers.assignCrewTo(b, v)
  if not v or v.dead or v.confined or v.age == "child" then return false end
  if v.job == "crew" and v.building == b then return true end
  if (Buildings.crewCount[b] or 0) >= (Buildings.maxCrew[b] or 0) then return false end
  unassignBuilding(v)
  v.job, v.state = "crew", "walking"
  v.building = b
  v.node, v.buildTarget = nil, 0
  Buildings.crewCount[b] = (Buildings.crewCount[b] or 0) + 1
  return true
end

function Villagers.assignResearcherTo(b, v)
  if not v or v.dead or v.confined or v.age == "child" then return false end
  if v.job == "research" and v.building == b then return true end
  local d = buildingData[Buildings.kind[b]]
  local slots = d and d.researchSlots or 0
  if (Buildings.researchers[b] or 0) >= slots then return false end
  unassignBuilding(v)
  v.job, v.state = "research", "walking"
  v.building = b
  v.node, v.buildTarget = nil, 0
  Buildings.researchers[b] = (Buildings.researchers[b] or 0) + 1
  return true
end

function Villagers.unassignResearcher(b)
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and v.job == "research" and v.building == b then
      Buildings.researchers[b] = math.max(0, (Buildings.researchers[b] or 0) - 1)
      v.job, v.state, v.building = "idle", "idle", nil
      return true
    end
  end
  return false
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

function Villagers.startSacrifice(v, b)
  if not v or v.dead or v.confined or v.age == "child" or v.job == "sacrifice" or v.job == "crew"
    or v.job == "research" or v.job == "conceive" then
    return false
  end
  unassignBuilding(v)
  v.job = "sacrifice"
  v.state = "walking"
  v.altar = b
  v.node = nil
  v.buildTarget = 0
  return true
end

function Villagers.pickSacrifice(b)
  local list = Villagers.list
  local bx, by = Buildings.x[b], Buildings.y[b]
  local pick, pd = nil, math.huge
  for i = 1, #list do
    local v = list[i]
    if not v.dead and not v.undead and not v.confined and v.age ~= "child" and v.job ~= "sacrifice" and v.job ~= "crew"
      and v.job ~= "research" and v.job ~= "conceive" then
      local dx, dy = v.x - bx, v.y - by
      local d = dx * dx + dy * dy
      if v.job == "idle" then d = d - 10000 end
      if d < pd then
        pd = d
        pick = v
      end
    end
  end
  return pick
end

-- A servant walks to the village heart and dies there. `purpose` is
-- "ascend" (default) or "heal".
function Villagers.startHeartSacrifice(v, purpose)
  if not v or v.dead or v.confined or v.age == "child" or v.job == "crew" or v.job == "research"
    or v.job == "conceive" or v.job == "sacrifice" then
    return false
  end
  unassignBuilding(v)
  v.job, v.state = "sacrifice", "walking"
  v.altar = "heart"
  v.ritual = purpose or "ascend"
  v.node = nil
  v.buildTarget = 0
  return true
end

function Villagers.pickHeartSacrifice()
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and not v.undead and not v.confined and v.age ~= "child" and v.job == "idle" then return v end
  end
  return nil
end

function Villagers.idleAdults()
  local c = 0
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and not v.undead and not v.confined and v.age ~= "child" and v.job == "idle" then c = c + 1 end
  end
  return c
end

-- Mobilize everyone for a horde: fill empty tower slots (kept manual crew),
-- everyone else shelters at home. Jobs are restored on demobilize.
function Villagers.mobilize()
  if Villagers.mobilized then return end
  Villagers.mobilized = true
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and not v.confined and v.age ~= "child"
      and v.job ~= "sacrifice" and v.job ~= "conceive" then
      v.mob = { job = v.job, state = v.state, building = v.building, altar = v.altar, buildTarget = v.buildTarget }
    end
  end
  for b = 1, Buildings.n do
    if Buildings.isTower[b] and Buildings.built[b] then
      while Buildings.crewCount[b] < Buildings.maxCrew[b] do
        if not Villagers.assignCrew(b) then break end
      end
    end
  end
  for i = 1, #list do
    local v = list[i]
    if not v.dead and v.mob and v.job ~= "crew" and v.job ~= "sacrifice" and v.job ~= "conceive" then
      unassignBuilding(v)
      v.job, v.state = "shelter", "walking"
      v.node, v.buildTarget, v.altar = nil, 0, nil
    end
  end
end

function Villagers.demobilize()
  if not Villagers.mobilized then return end
  Villagers.mobilized = false
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and v.mob then
      local m = v.mob
      v.mob = nil
      if v.job == "crew" and m.job ~= "crew" then unassignBuilding(v) end
      v.job = m.job
      v.state = m.state or "idle"
      v.building = m.building
      v.altar = m.altar
      v.buildTarget = m.buildTarget or 0
      v.node = nil
    end
  end
end

function Villagers.setJob(v, job)
  if not v or v.age == "child" or v.confined then return end
  unassignBuilding(v)
  v.job = job
  v.state = "idle"
  v.node = nil
  v.buildTarget = 0
  v.altar = nil
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
    if v.job == "sacrifice" or v.job == "conceive" then
      if movedFrom and v.altar == movedFrom then
        v.altar = movedTo
      elseif v.altar == destroyed then
        v.job, v.state = "idle", "idle"
        v.altar = nil
      end
    end
  end
  if movedFrom then
    for i = 1, #Villagers.couples do
      if Villagers.couples[i].house == movedFrom then Villagers.couples[i].house = movedTo end
    end
  end
  for i = #Villagers.couples, 1, -1 do
    local c = Villagers.couples[i]
    if c.house == destroyed then
      for _, p in ipairs({ c.a, c.b }) do
        if p then
          p.coupleId = nil
          if p.confined then p.confined = false p.job, p.state = "idle", "idle" end
        end
      end
      if Villagers.vesselId == c.id then Villagers.vesselId = nil end
      if Villagers.request == c then Villagers.request = nil end
      table.remove(Villagers.couples, i)
    end
  end
end

-- Couples, births, and the Antichrist vessel ------------------------------

local function personAlive(v)
  return v ~= nil and not v.dead
end

function Villagers.aliveAdults(sex)
  local n = 0
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and not v.undead and v.age ~= "child" and (not sex or v.sex == sex) then n = n + 1 end
  end
  return n
end

-- Living (non-undead) servants — the population that needs housing.
function Villagers.population()
  local n = 0
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and not v.undead then n = n + 1 end
  end
  return n
end

function Villagers.coupleAt(house)
  for i = 1, #Villagers.couples do
    if Villagers.couples[i].house == house then return Villagers.couples[i] end
  end
  return nil
end

function Villagers.coupleById(id)
  if not id then return nil end
  for i = 1, #Villagers.couples do
    if Villagers.couples[i].id == id then return Villagers.couples[i] end
  end
  return nil
end

function Villagers.coupleOf(v)
  return v and Villagers.coupleById(v.coupleId) or nil
end

-- Which partner carries a pregnancy (opposite-sex unions only).
function Villagers.coupleMother(c)
  if not c then return nil end
  if c.a and c.a.sex == "f" then return c.a end
  if c.b and c.b.sex == "f" then return c.b end
  return c.a or c.b
end

function Villagers.coupleFather(c)
  if not c then return nil end
  if c.a and c.a.sex == "m" then return c.a end
  if c.b and c.b.sex == "m" then return c.b end
  return c.a or c.b
end

-- Same-sex households cannot conceive, but both partners work harder.
function Villagers.workMul(v)
  local c = Villagers.coupleOf(v)
  if c and not c.fertile then return vData.unionWorkMul or 1.15 end
  return 1
end

function Villagers.researchRateAt(b)
  local rate = 0
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and v.job == "research" and v.building == b then
      rate = rate + Villagers.workMul(v)
    end
  end
  return rate
end

function Villagers.coupleCount()
  local n = 0
  for i = 1, #Villagers.couples do
    local c = Villagers.couples[i]
    if personAlive(c.a) and personAlive(c.b) then n = n + 1 end
  end
  return n
end

function Villagers.freeAdult(sex)
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and not v.undead and v.age ~= "child" and v.sex == sex and not v.coupleId then return v end
  end
  return nil
end

function Villagers.canBindPair(a, b)
  if not a or not b or a == b then return false end
  if a.dead or b.dead or a.undead or b.undead then return false end
  if a.age == "child" or b.age == "child" then return false end
  if a.coupleId or b.coupleId then return false end
  return true
end

function Villagers.bindCoupleTo(house, a, b)
  if Villagers.coupleAt(house) then return false end
  if not (house and house <= Buildings.n and Buildings.kind[house] == "house") then return false end
  if not Villagers.canBindPair(a, b) then return false end
  local c = {
    id = nextCouple, house = house, a = a, b = b,
    fertile = a.sex ~= b.sex,
    pregnant = false, monthsLeft = 0, askIn = vData.askEvery,
    pending = false, chosen = false, conceived = false, conceiving = false, altar = nil,
  }
  nextCouple = nextCouple + 1
  a.coupleId = c.id
  b.coupleId = c.id
  Villagers.couples[#Villagers.couples + 1] = c
  if Villagers.onNotice then
    if c.fertile then
      Villagers.onNotice("A union is blessed", "the flock grows in the dark")
    else
      Villagers.onNotice("A household is bonded", "they toil together, twice devoted")
    end
  end
  return true
end

-- Auto-pick for harnesses and scripted setup; players bind picks manually.
function Villagers.bindCouple(house)
  local pool = {}
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and not v.undead and v.age ~= "child" and not v.coupleId then
      pool[#pool + 1] = v
    end
  end
  local man, woman
  for i = 1, #pool do
    if not man and pool[i].sex == "m" then man = pool[i] end
    if not woman and pool[i].sex == "f" then woman = pool[i] end
  end
  if man and woman then return Villagers.bindCoupleTo(house, man, woman) end
  if #pool >= 2 then return Villagers.bindCoupleTo(house, pool[1], pool[2]) end
  return false
end

function Villagers.unbind(house)
  local c = Villagers.coupleAt(house)
  if not c then return false end
  if c.conceived or c.conceiving or (c.chosen and c.pregnant) then return false end
  if c.a then c.a.coupleId = nil end
  if c.b then c.b.coupleId = nil end
  if c.chosen then c.chosen = false end
  if Villagers.vesselId == c.id then Villagers.vesselId = nil end
  if Villagers.request == c then Villagers.request = nil end
  for i = 1, #Villagers.couples do
    if Villagers.couples[i] == c then table.remove(Villagers.couples, i) break end
  end
  return true
end

function Villagers.choose(house)
  local c = Villagers.coupleAt(house)
  if not c or not c.fertile then return false end
  if c.conceived or c.conceiving then return false end
  for i = 1, #Villagers.couples do Villagers.couples[i].chosen = false end
  c.chosen = true
  Villagers.vesselId = c.id
  if Villagers.onNotice then Villagers.onNotice("The vessel is chosen", "conceive the Antichrist at the Altar") end
  return true
end

function Villagers.unchoose(house)
  local c = Villagers.coupleAt(house)
  if not c then return false end
  if c.conceived or c.conceiving then return false end
  c.chosen = false
  if Villagers.vesselId == c.id then Villagers.vesselId = nil end
  if Villagers.onNotice then Villagers.onNotice("The vessel is released", nil) end
  return true
end

function Villagers.chosenCouple()
  if Villagers.vesselId then
    local c = Villagers.coupleById(Villagers.vesselId)
    if c then return c end
    Villagers.vesselId = nil
  end
  for i = 1, #Villagers.couples do
    local c = Villagers.couples[i]
    if c.chosen then
      Villagers.vesselId = c.id
      return c
    end
  end
  return nil
end

function Villagers.canConceive()
  local c = Villagers.chosenCouple()
  return c ~= nil and c.fertile and not c.conceived and not c.conceiving
    and personAlive(c.a) and personAlive(c.b)
end

-- The Altar ritual: both partners walk to the altar, then the end times begin.
function Villagers.startConception(b)
  local c = Villagers.chosenCouple()
  if not c or not c.fertile or c.conceived or c.conceiving then return false end
  if not personAlive(c.a) or not personAlive(c.b) then return false end
  local function walk(v)
    unassignBuilding(v)
    v.job, v.state = "conceive", "walking"
    v.altar = b
    v.node = nil
    v.buildTarget = 0
  end
  walk(c.a)
  walk(c.b)
  c.conceiving = true
  c.altar = b
  return true
end

-- Manual birth: the player starts a pregnancy from the house panel. Costs
-- food (Age-of-Empires style).
function Villagers.makeChild(house, S)
  local c = Villagers.coupleAt(house)
  if not c or not c.fertile or c.pregnant or c.conceived or c.conceiving then return false end
  if not personAlive(c.a) or not personAlive(c.b) then return false end
  local cap = (S and S.buildings and S.buildings.popCap()) or 0
  if Villagers.population() >= cap then return false end
  local cost = vData.birthCost or 0
  if S and (S.stock.food or 0) < cost then return false end
  if S then S.stock.food = S.stock.food - cost end
  c.pregnant = true
  c.monthsLeft = vData.pregnancyMonths
  local mother = Villagers.coupleMother(c)
  if mother then mother.confined = false end
  if Villagers.onNotice then Villagers.onNotice("A child is conceived", cost > 0 and (cost .. " food offered") or nil) end
  return true
end

dissolveOnDeath = function(v)
  for i = 1, #Villagers.couples do
    local c = Villagers.couples[i]
    if c.id == v.coupleId then
      if c.conceived and (c.a == v or c.b == v) then Villagers.failReason = "vessel" end
      local partner = (c.a == v) and c.b or c.a
      if partner then
        partner.coupleId = nil
        if partner.confined then
          partner.confined = false
          partner.job, partner.state = "idle", "idle"
        end
      end
      v.coupleId = nil
      c.chosen = false
      if Villagers.vesselId == c.id then Villagers.vesselId = nil end
      if Villagers.request == c then Villagers.request = nil end
      table.remove(Villagers.couples, i)
      return
    end
  end
end

finishConception = function(c, ctx)
  c.conceiving = false
  c.altar = nil
  c.pregnant = true
  c.conceived = true
  c.monthsLeft = vData.pregnancyMonths
  Villagers.conceived = true
  for _, v in ipairs({ c.a, c.b }) do
    if personAlive(v) then
      v.job, v.state, v.altar = "idle", "idle", nil
    end
  end
  ctx.waves.calendar.apocalypse = true
  local bearer = Villagers.coupleMother(c) or c.a
  local bx, by = ctx.village.x, ctx.village.y
  if bearer then bx, by = bearer.x, bearer.y end
  if c.altar and c.altar <= Buildings.n then
    bx, by = Buildings.x[c.altar], Buildings.y[c.altar]
  end
  Particles.ritual(bx, by)
  Camera.shake(10, 0.7)
  ctx.flash = 0.55
  Audio.play("conceive")
  if Villagers.onNotice then Villagers.onNotice("THE END TIMES BEGIN", "a horde every month until the birth") end
end

updateConceptions = function(ctx)
  for i = 1, #Villagers.couples do
    local c = Villagers.couples[i]
    if c.conceiving then
      if personAlive(c.a) and personAlive(c.b) then
        if c.a.job ~= "conceive" or c.b.job ~= "conceive" then
          c.conceiving = false
          c.altar = nil
        elseif c.a.state == "arrived" and c.b.state == "arrived" then
          finishConception(c, ctx)
        end
      end
    end
  end
end

advanceMonths = function(n, ctx)
  local list = Villagers.list
  for i = 1, #list do
    local v = list[i]
    if not v.dead and v.age == "child" then
      v.growLeft = v.growLeft - n
      if v.growLeft <= 0 then
        v.age = "adult"
        v.r = vData.r
        v.hp = vData.hp
        v.maxHp = vData.hp
      end
    end
  end
  local cap = ctx.buildings and ctx.buildings.popCap() or 0
  for i = 1, #Villagers.couples do
    local c = Villagers.couples[i]
    local mother = Villagers.coupleMother(c)
    if not c.conceiving and personAlive(c.a) and personAlive(c.b) then
      if c.pregnant then
        c.monthsLeft = c.monthsLeft - n
        local half = math.floor((vData.pregnancyMonths or 9) / 2)
        if mother and personAlive(mother) and c.monthsLeft <= half and not mother.confined then
          -- second half: the mother drops everything and stays home
          unassignBuilding(mother)
          mother.confined = true
          mother.job, mother.state = "home", "idle"
          mother.node, mother.buildTarget = nil, 0
        end
        if c.monthsLeft <= 0 then
          if mother then
            mother.confined = false
            mother.job, mother.state = "idle", "idle"
          end
          if c.conceived then
            c.pregnant = false
            ctx.ending = "birth"
            ctx.mode = "victory"
            Audio.play("birth")
          elseif Villagers.population() < cap then
            local baby = Villagers.spawn(ctx.village.x, ctx.village.y, love.math.random() < 0.5 and "m" or "f", 0)
            baby.age = "child"
            baby.growLeft = vData.growMonths
            baby.r = vData.childR
            baby.hp = math.max(1, math.floor(vData.hp / 2))
            baby.maxHp = vData.hp
            c.pregnant = false
            if Villagers.onNotice then Villagers.onNotice("A child is born to the flock", nil) end
          else
            c.monthsLeft = 1
          end
        end
      end
    end
  end
end

-- Rebuild villagers + couples from a save snapshot. Callbacks are preserved.
function Villagers.load(vlist, clist, requestId, deaths, conceived, seenEpoch, mobilized, vesselId)
  Villagers.list = {}
  Villagers.couples = {}
  Villagers.request = nil
  local byId = {}
  local maxId = 0
  for idx = 1, #vlist do
    local r = vlist[idx]
    local v = {
      id = r.id, x = r.x, y = r.y, sex = r.sex, family = r.family,
      hp = r.hp, maxHp = r.maxHp, r = r.r,
      job = r.job, state = r.state, carry = r.carry or 0, carryRes = r.carryRes,
      node = nil, buildTarget = r.buildTarget or 0, building = r.building, altar = r.altar,
      timer = r.timer or 0, wx = r.wx or r.x, wy = r.wy or r.y,
      ritual = r.ritual,
      flash = 0, atk = 0, dead = false, undead = r.undead or false,
      confined = r.confined or false, mob = r.mob,
      age = r.age or "adult", growLeft = r.growLeft or 0,
      coupleId = nil,
      path = nil, pathI = 0, pathDone = false, pathVersion = nil, blockedTime = 0,
    }
    if r.nodeIndex and Nodes.list[r.nodeIndex] then v.node = Nodes.list[r.nodeIndex] end
    Villagers.list[idx] = v
    byId[v.id] = v
    if v.id > maxId then maxId = v.id end
  end
  nextId = maxId + 1
  local maxC = 0
  for _, cr in ipairs(clist or {}) do
    local a = byId[cr.aId or cr.manId]
    local b = byId[cr.bId or cr.womanId]
    local fertile = cr.fertile
    if fertile == nil then fertile = (a ~= nil and b ~= nil and a.sex ~= b.sex) end
    local c = {
      id = cr.id, house = cr.house, a = a, b = b, fertile = fertile,
      pregnant = cr.pregnant, monthsLeft = cr.monthsLeft, askIn = cr.askIn, pending = cr.pending,
      chosen = cr.chosen, conceived = cr.conceived, conceiving = cr.conceiving, altar = cr.altar,
    }
    if c.a then c.a.coupleId = c.id end
    if c.b then c.b.coupleId = c.id end
    Villagers.couples[#Villagers.couples + 1] = c
    if c.id > maxC then maxC = c.id end
  end
  nextCouple = maxC + 1
  if requestId then
    for _, c in ipairs(Villagers.couples) do
      if c.id == requestId then Villagers.request = c break end
    end
  end
  Villagers.deaths = deaths or 0
  Villagers.conceived = conceived or false
  Villagers.failReason = nil
  Villagers.seenEpoch = seenEpoch or 0
  Villagers.mobilized = mobilized or false
  Villagers.vesselId = vesselId
  if not Villagers.vesselId then
    for _, c in ipairs(Villagers.couples) do
      if c.chosen then Villagers.vesselId = c.id break end
    end
  end
  -- recompute pregnancy confinement
  local half = math.floor((vData.pregnancyMonths or 9) / 2)
  for _, c in ipairs(Villagers.couples) do
    local mother = Villagers.coupleMother(c)
    if c.pregnant and c.monthsLeft and c.monthsLeft <= half and mother then
      mother.confined = true
      mother.job, mother.state = "home", "idle"
    end
  end
  -- rebuild researcher counts from the restored villagers
  for i = 1, Buildings.n do Buildings.researchers[i] = 0 end
  for i = 1, #Villagers.list do
    local v = Villagers.list[i]
    if not v.dead and v.job == "research" and v.building and v.building <= Buildings.n then
      Buildings.researchers[v.building] = (Buildings.researchers[v.building] or 0) + 1
    end
  end
end

return Villagers
