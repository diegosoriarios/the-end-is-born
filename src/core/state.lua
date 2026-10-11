local Grid = require("src.sim.grid")
local SpatialHash = require("src.sim.spatialhash")
local Enemies = require("src.sim.enemies")
local Towers = require("src.sim.towers")
local Projectiles = require("src.sim.projectiles")
local Village = require("src.sim.village")
local Waves = require("src.sim.waves")
local Walls = require("src.sim.walls")
local Buildings = require("src.sim.buildings")
local Villagers = require("src.sim.villagers")
local Nodes = require("src.sim.nodes")
local Flow = require("src.sim.flowfield")
local Camera = require("src.core.camera")
local Render = require("src.render.render")
local UI = require("src.ui.ui")
local resData = require("src.data.resources")
local vData = require("src.data.villagers")
local buildingData = require("src.data.buildings")

local State = {}

function State.canAfford(cost)
  if not cost then return true end
  for res, amt in pairs(cost) do
    if (State.stock[res] or 0) < amt then return false end
  end
  return true
end

local function pay(cost)
  for res, amt in pairs(cost) do
    State.stock[res] = State.stock[res] - amt
  end
end

local function spawnBurst(count)
  local W, H = Grid.pixelWidth(), Grid.pixelHeight()
  local m = 24
  for _ = 1, count do
    local edge = love.math.random(0, 3)
    local x, y
    if edge == 0 then
      x, y = love.math.random(m, W - m), m
    elseif edge == 1 then
      x, y = love.math.random(m, W - m), H - m
    elseif edge == 2 then
      x, y = m, love.math.random(m, H - m)
    else
      x, y = W - m, love.math.random(m, H - m)
    end
    Enemies.spawn(x, y, "grunt", 1)
  end
end

local function buildStressWalls(v)
  local cx, cy = Grid.worldToTile(v.x, v.y)
  local R = 7
  for gx = cx - R, cx + R do
    if not (gx >= cx - 1 and gx <= cx + 1) and Walls.canPlace(gx, cy - R) then
      Walls.place(gx, cy - R)
    end
    if not (gx >= cx - 1 and gx <= cx + 1) and Walls.canPlace(gx, cy + R) then
      Walls.place(gx, cy + R)
    end
  end
  for gy = cy - R + 1, cy + R - 1 do
    if not (gy >= cy - 1 and gy <= cy + 1) and Walls.canPlace(cx - R, gy) then
      Walls.place(cx - R, gy)
    end
    if not (gy >= cy - 1 and gy <= cy + 1) and Walls.canPlace(cx + R, gy) then
      Walls.place(cx + R, gy)
    end
  end
end

function State.reset()
  UI.load()
  State.mode = "playing"
  State.buildMode = false
  State.buildType = "arrow_tower"
  State.debug = false
  State.accumulator = 0
  State.selection = nil
  State.follow = false
  Grid.resetOccupancy()
  State.hash = SpatialHash.new(Grid.TILE)
  Enemies.n = 0
  Towers.clear()
  Projectiles.n = 0
  Walls.clear()
  Buildings.clear()
  Villagers.clear()
  Nodes.clear()
  State.stock = {
    wood = resData.starting.wood,
    food = resData.starting.food,
    stone = resData.starting.stone,
  }
  State.village = Village.new(Grid.pixelWidth() / 2, Grid.pixelHeight() / 2)
  State.enemies = Enemies
  State.towers = Towers
  State.projectiles = Projectiles
  State.walls = Walls
  State.buildings = Buildings
  State.villagers = Villagers
  State.nodes = Nodes
  State.flow = Flow
  State.waves = Waves.new()
  State.stats = { simMs = 0, drawMs = 0, frameMs = 0, stepMs = 0 }
  State.villageCells = Grid.cellsInCircle(State.village.x, State.village.y, State.village.r)
  for _, c in ipairs(State.villageCells) do
    Grid.occupancy[c] = Grid.OCC_VILLAGE
  end
  local rebake = function() Flow.rebake(State.villageCells) end
  Walls.setRebuildHook(rebake)
  Buildings.setRebuildHook(rebake)
  Buildings.setRemoveHook(function(destroyed, movedFrom, movedTo)
    Villagers.onBuildingRemoved(destroyed, movedFrom, movedTo)
  end)
  Flow.rebake(State.villageCells)
  Nodes.generate(State.village)
  for f = 1, vData.startFamilies do
    Villagers.spawn(State.village.x + 30 + (f - 1) * 16, State.village.y - 20, "m", f)
    Villagers.spawn(State.village.x + 30 + (f - 1) * 16, State.village.y + 20, "f", f)
  end
  State.smoke = nil
  State.stress = nil
  if love.filesystem.getInfo("smoke.flag") then
    State.smoke = 2600
    State.smokeAction = 2570
  elseif love.filesystem.getInfo("stress.flag") then
    State.stress = 3600
    State.stressAction = 3540
    State.stressFrames = 0
    State.stressT0 = nil
  elseif love.filesystem.getInfo("stress2.flag") then
    State.stress2 = 1800
    State.stress2Action = 1740
    State.stressFrames = 0
    State.stressT0 = nil
  elseif love.filesystem.getInfo("test.flag") then
    State.test = 900
    State.testAction = 840
  end
  Camera.reset()
end

local function stressUpdate()
  local v = State.village
  if State.stress == State.stressAction then
    State.waves:skip()
    v.hp = 1e9
    v.maxHp = 1e9
    local spots = { { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 } }
    for _, s in ipairs(spots) do
      local gx, gy = Grid.worldToTile(v.x + s[1] * Grid.TILE, v.y + s[2] * Grid.TILE)
      if Towers.canPlace(gx, gy, v) then
        local b = Towers.place(gx, gy)
        Villagers.assignCrew(b)
      end
    end
    buildStressWalls(v)
    print("[stress] towers + wall ring placed, spawning 10000 enemies")
  elseif State.stress < State.stressAction and Enemies.n < 10000 then
    spawnBurst(100)
  end
  if Enemies.n >= 10000 and not State.stressT0 then
    State.stressT0 = love.timer.getTime()
    State.stressFrames = 0
    print("[stress] full swarm spawned, measuring...")
  end
  if State.stressT0 then
    State.stressFrames = State.stressFrames + 1
    if State.stressFrames % 300 == 0 then
      print(("[stress] %5.1fs: enemies=%d frameMs=%.1f stepMs=%.1f drawMs=%.1f kills=%d shots=%d hits=%d")
        :format(State.stressFrames / 60, Enemies.n, State.stats.frameMs, State.stats.stepMs, State.stats.drawMs, Enemies.kills, Towers.shots, Projectiles.hits))
    end
  end
  if State.stress <= 0 then
    if State.stressT0 then
      local elapsed = love.timer.getTime() - State.stressT0
      print(("[stress] done: frames=%d elapsed=%.1fs avgFps=%.1f enemies=%d villageHp=%d wallsLeft=%d rebakes=%d")
        :format(State.stressFrames, elapsed, State.stressFrames / elapsed, Enemies.n, State.village.hp, Walls.n, Flow.rebakes))
    else
      print("[stress] done: swarm never fully spawned")
    end
    love.event.quit()
    State.stress = nil
  end
end

local function stress2Update()
  local v = State.village
  if State.stress2 == State.stress2Action then
    State.waves:skip()
    v.hp = 1e9
    v.maxHp = 1e9
    local spots = { { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 } }
    for _, s in ipairs(spots) do
      local gx, gy = Grid.worldToTile(v.x + s[1] * Grid.TILE, v.y + s[2] * Grid.TILE)
      if Towers.canPlace(gx, gy, v) then
        local b = Towers.place(gx, gy)
        Villagers.assignCrew(b)
      end
    end
    print("[stress2] 4 towers, no walls, spawning 2000 enemies")
  elseif State.stress2 < State.stress2Action and Enemies.n < 2000 then
    spawnBurst(50)
  end
  if Enemies.n >= 2000 and not State.stressT0 then
    State.stressT0 = love.timer.getTime()
    State.stressFrames = 0
  end
  if State.stressT0 then
    State.stressFrames = State.stressFrames + 1
  end
  if State.stress2 <= 0 then
    if State.stressT0 then
      local elapsed = love.timer.getTime() - State.stressT0
      print(("[stress2] done: frames=%d elapsed=%.1fs avgFps=%.1f enemies=%d kills=%d shots=%d hits=%d stepMs=%.1f")
        :format(State.stressFrames, elapsed, State.stressFrames / elapsed, Enemies.n, Enemies.kills, Towers.shots, Projectiles.hits, State.stats.stepMs))
    else
      print("[stress2] done: swarm never fully spawned")
    end
    love.event.quit()
    State.stress2 = nil
  end
end

local function testUpdate()
  local v = State.village
  if State.test == State.testAction then
    State.waves:skip()
    v.hp = 1e9
    v.maxHp = 1e9
    local gx, gy = Grid.worldToTile(v.x + 3 * Grid.TILE, v.y)
    local b = Towers.place(gx, gy)
    Villagers.assignCrew(b)
    for k = 0, 11 do
      Enemies.spawn(v.x + 150 + (k % 4) * 18, v.y - 40 + math.floor(k / 4) * 30, "grunt", 1)
    end
    print("[test] tower + 12 enemies spawned")
  end
  if State.test <= 0 then
    print(("[test] done: enemies=%d kills=%d shots=%d hits=%d villageHp=%d")
      :format(Enemies.n, Enemies.kills, Towers.shots, Projectiles.hits, State.village.hp))
    love.event.quit()
    State.test = nil
  end
end

function State.update(dt)
  if State.smoke then
    State.smoke = State.smoke - 1
    if State.smoke == State.smokeAction then
      State.smokeAction = nil
      State.waves:skip()
      local gx, gy = Grid.worldToTile(State.village.x + 120, State.village.y)
      if Towers.canPlace(gx, gy, State.village) then
        local b = Towers.place(gx, gy)
        Villagers.assignCrew(b)
      end
      gx, gy = Grid.worldToTile(State.village.x - 120, State.village.y)
      if Towers.canPlace(gx, gy, State.village) then
        local b = Towers.place(gx, gy)
        Villagers.assignCrew(b)
      end
      print("[smoke] wave skipped, 2 towers placed + staffed")
    end
    if State.smoke <= 0 then
      print(("[smoke] done: mode=%s wave=%s phase=%s villageHp=%d buildings=%d villagers=%d enemiesAlive=%d")
        :format(State.mode, State.waves.number, State.waves.phase, State.village.hp, Buildings.n, Villagers.count(), Enemies.n))
      love.event.quit()
      State.smoke = nil
      return
    end
  end
  if State.stress then
    State.stress = State.stress - 1
    stressUpdate()
    if not State.stress or State.stress <= 0 then return end
  end
  if State.stress2 then
    State.stress2 = State.stress2 - 1
    stress2Update()
    if not State.stress2 or State.stress2 <= 0 then return end
  end
  if State.test then
    State.test = State.test - 1
    testUpdate()
    if not State.test or State.test <= 0 then return end
  end
  if State.mode ~= "playing" then return end
  local stepT0 = love.timer.getTime()
  State.hash:rebuild(Enemies)
  State.waves:update(dt, State)
  Enemies.update(dt, State)
  Towers.update(dt, State.hash, Projectiles)
  Projectiles.update(dt, State.hash)
  Enemies.compact()
  Villagers.update(dt, State)
  Nodes.update(dt)
  Walls.update(dt)
  Buildings.update(dt)
  local sel = State.selection
  if sel then
    if sel.villager and sel.villager.dead then
      State.selection = nil
    elseif sel.building and sel.building > Buildings.n then
      State.selection = nil
    end
  end
  local stepMs = (love.timer.getTime() - stepT0) * 1000
  State.stats.stepMs = State.stats.stepMs * 0.95 + stepMs * 0.05
  if State.village.hp <= 0 then State.mode = "gameover" end
end

function State.tryPlace(mx, my)
  if State.mode ~= "playing" or not State.buildMode then return end
  local wx, wy = Camera.toWorld(mx, my)
  local gx, gy = Grid.worldToTile(wx, wy)
  if State.buildType == "wall" then
    local d = buildingData.wall
    if State.canAfford(d.cost) and Walls.canPlace(gx, gy) then
      pay(d.cost)
      Walls.place(gx, gy)
    end
  else
    local d = buildingData[State.buildType]
    if d and State.canAfford(d.cost) and Buildings.canPlace(gx, gy, State.village) then
      pay(d.cost)
      Buildings.place(gx, gy, State.buildType, false)
    end
  end
end

function State.setBuildType(t)
  State.buildType = t
  State.buildMode = true
end

function State.draw()
  local panned = Camera.updateKeyboard(1 / 60)
  if panned then State.follow = false end
  if State.follow and State.selection and State.selection.villager then
    local v = State.selection.villager
    Camera.x = Camera.x + (v.x - Camera.x) * 0.08
    Camera.y = Camera.y + (v.y - Camera.y) * 0.08
    Camera.clamp()
  end
  Camera.apply()
  Render.draw(State)
  Camera.unapply()
  UI.draw(State)
end

function State.handleClick(x, y)
  return UI.handleClick(x, y, State)
end

return State
