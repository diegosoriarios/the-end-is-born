local Grid = require("src.sim.grid")
local SpatialHash = require("src.sim.spatialhash")
local Enemies = require("src.sim.enemies")
local Towers = require("src.sim.towers")
local Projectiles = require("src.sim.projectiles")
local EnemyShots = require("src.sim.enemyShots")
local Village = require("src.sim.village")
local Waves = require("src.sim.waves")
local Walls = require("src.sim.walls")
local Buildings = require("src.sim.buildings")
local Villagers = require("src.sim.villagers")
local Checklist = require("src.sim.checklist")
local Nodes = require("src.sim.nodes")
local Flow = require("src.sim.flowfield")
local Camera = require("src.core.camera")
local Particles = require("src.fx.particles")
local Audio = require("src.audio.audio")
local Persistence = require("src.core.persistence")
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
  State.checklistVisible = true
  Grid.resetOccupancy()
  Particles.clear()
  State.flash = 0
  State._prevHp = nil
  State.hash = SpatialHash.new(Grid.TILE)
  Enemies.n = 0
  Towers.clear()
  Projectiles.n = 0
  EnemyShots.n = 0
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
  State.enemyShots = EnemyShots
  State.walls = Walls
  State.buildings = Buildings
  State.villagers = Villagers
  State.nodes = Nodes
  State.flow = Flow
  State.waves = Waves.new()
  State.checklist = Checklist
  Checklist.reset()
  Villagers.onSacrificed = function()
    Checklist.sacrifices = Checklist.sacrifices + 1
  end
  Villagers.onNotice = function(text, sub)
    Checklist.notice(text, sub)
  end
  State.ending = nil
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
  State.menu = nil
  if love.filesystem.getInfo("menu.flag") then
    State.menu = 300
    State.settingsOpen = false
  elseif love.filesystem.getInfo("shot.flag") then
    State.shot = 300
    State.shotAction = 240
  elseif love.filesystem.getInfo("save.flag") then
    State.save = 400
    State.saveAction = 340
  elseif love.filesystem.getInfo("smoke.flag") then
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
  elseif love.filesystem.getInfo("life.flag") then
    State.life = 900
    State.lifeAction = 840
    State.lifePhase = "setup"
    State.lifeGestate = nil
  end
  State.harness = (State.smoke or State.stress or State.stress2 or State.test or State.life or State.menu or State.shot or State.save) and true or false
  State.paused = false
  State._savedYear = State.waves.calendar.year
  State._pendingSave = false
  if State.harness then
    Audio.setEnabled(false)
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

local function lifeUpdate()
  local v = State.village
  if State.lifeAction and State.life == State.lifeAction then
    v.hp, v.maxHp = 1e9, 1e9
    local function tile(dx, dy)
      return Grid.worldToTile(v.x + dx * Grid.TILE, v.y + dy * Grid.TILE)
    end
    local hx, hy = tile(4, 0)
    local houseA = Buildings.place(hx, hy, "house", true)
    local bx, by = tile(-4, 0)
    local houseB = Buildings.place(bx, by, "house", true)
    local ax, ay = tile(0, 4)
    local altar = Buildings.place(ax, ay, "altar", true)
    local okA = Villagers.bindCouple(houseA)
    local okB = Villagers.bindCouple(houseB)
    Villagers.choose(houseA)
    local cB = Villagers.coupleAt(houseB)
    if cB then
      cB.pending = true
      Villagers.request = cB
      Villagers.allowBirth()
    end
    local conc = Villagers.startConception(altar)
    print(("[life] setup: coupleA=%s coupleB=%s conceive=%s"):format(tostring(okA), tostring(okB), tostring(conc)))
    State.lifePhase = "walk"
    State.lifeAction = nil
  end
  if State.lifePhase == "walk" then
    local c = Villagers.chosenCouple()
    if c and c.conceived then
      State.lifePhase = "gestate"
      State.lifeGestate = State.life - 90
      print("[life] conceived — the end times begin")
    end
  elseif State.lifePhase == "gestate" and State.lifeGestate and State.life == State.lifeGestate then
    State.waves.calendar.epoch = State.waves.calendar.epoch + 9
    print("[life] advanced 9 months")
  end
  if State.mode == "victory" or State.mode == "gameover" or State.life <= 0 then
    local children = 0
    for _, vv in ipairs(Villagers.list) do
      if not vv.dead and vv.age == "child" then children = children + 1 end
    end
    print(("[life] done: mode=%s ending=%s conceived=%s apocalypse=%s couples=%d children=%d servants=%d")
      :format(State.mode, tostring(State.ending), tostring(Villagers.conceived), tostring(State.waves.calendar.apocalypse),
        #Villagers.couples, children, Villagers.count()))
    love.event.quit()
    State.life = nil
  end
end

local function shotUpdate()
  local v = State.village
  if State.shotAction and State.shot == State.shotAction then
    v.hp, v.maxHp = 1e9, 1e9
    local function place(dx, dy, kind)
      local gx, gy = Grid.worldToTile(v.x + dx * Grid.TILE, v.y + dy * Grid.TILE)
      if Buildings.canPlace(gx, gy, v) then return Buildings.place(gx, gy, kind, true) end
      return 0
    end
    local tw = place(3, 0, "arrow_tower")
    local ba = place(-3, 0, "ballista")
    place(0, 4, "house")
    place(5, 3, "house")
    place(0, -3, "altar")
    if tw > 0 then Villagers.assignCrew(tw) end
    if ba > 0 then Villagers.assignCrew(ba) end
    for gx = -3, 3 do
      local wx, wy = Grid.worldToTile(v.x + gx * Grid.TILE, v.y + 6 * Grid.TILE)
      if Walls.canPlace(wx, wy) then Walls.place(wx, wy) end
    end
    local kinds = { "grunt", "runner", "brute", "spitter", "grunt", "grunt" }
    for k = 1, 44 do
      local kind = kinds[(k % #kinds) + 1]
      Enemies.spawn(v.x + 190 + (k % 6) * 18, v.y - 120 + math.floor(k / 6) * 18, kind, 1)
    end
    Camera.zoom = 1.6
    Camera.x = v.x + 120
    Camera.y = v.y - 40
    Camera.clamp()
    State.shotAction = nil
  end
  if State.shot and State.shot <= 40 then State.flash = 0 end
  if State.shot <= 0 then
    print("[shot] done: captured shot.png")
    love.event.quit()
    State.shot = nil
  end
end

local function saveUpdate()
  local v = State.village
  if State.saveAction and State.save == State.saveAction then
    v.hp, v.maxHp = 1e9, 1e9
    State.stock.wood, State.stock.food = 777, 555
    local hx, hy = Grid.worldToTile(v.x + 4 * Grid.TILE, v.y)
    local house = Buildings.place(hx, hy, "house", true)
    local ax, ay = Grid.worldToTile(v.x, v.y + 4 * Grid.TILE)
    Buildings.place(ax, ay, "altar", true)
    local bx, by = Grid.worldToTile(v.x - 4 * Grid.TILE, v.y)
    Buildings.place(bx, by, "arrow_tower", true)
    Villagers.bindCouple(house)
    Villagers.choose(house)
    State._saveBefore = {
      buildings = Buildings.n, wood = State.stock.wood, couples = #Villagers.couples,
      year = State.waves.calendar.year, month = State.waves.calendar.month,
      villagers = #Villagers.list, nodes = #Nodes.list,
    }
    local b = State._saveBefore
    local ok = Persistence.save(State, true)
    State.stock.wood, State.stock.food = 0, 0
    Buildings.clear()
    Walls.clear()
    Villagers.clear()
    Nodes.list = {}
    print(("[save] wrote=%s before: b=%d wood=%d couples=%d y=%d m=%d villagers=%d nodes=%d")
      :format(tostring(ok), b.buildings, b.wood, b.couples, b.year, b.month, b.villagers, b.nodes))
    State.saveAction = nil
  elseif State.saveAction == nil and not State._saveDone then
    State._saveDone = true
    local ok = Persistence.load(State)
    local a = {
      buildings = Buildings.n, wood = State.stock.wood, couples = #Villagers.couples,
      year = State.waves.calendar.year, month = State.waves.calendar.month,
      villagers = #Villagers.list, nodes = #Nodes.list,
    }
    local b = State._saveBefore
    local match = ok and a.buildings == b.buildings and a.wood == b.wood and a.couples == b.couples
      and a.year == b.year and a.month == b.month and a.villagers == b.villagers and a.nodes == b.nodes
    print(("[save] loaded=%s after: b=%d wood=%d couples=%d y=%d m=%d villagers=%d nodes=%d match=%s")
      :format(tostring(ok), a.buildings, a.wood, a.couples, a.year, a.month, a.villagers, a.nodes, tostring(match)))
    love.event.quit()
    State.save = nil
  end
  if State.save and State.save <= 0 then
    love.event.quit()
    State.save = nil
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
      local doneN, totalN = Checklist.doneCount()
      print(("[smoke] done: mode=%s wave=%s phase=%s date=y%d:m%d villageHp=%d buildings=%d villagers=%d enemiesAlive=%d customs=%d/%d")
        :format(State.mode, State.waves.number, State.waves.phase, State.waves.calendar.year, State.waves.calendar.month,
          State.village.hp, Buildings.n, Villagers.count(), Enemies.n, doneN, totalN))
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
  if State.life then
    State.life = State.life - 1
    lifeUpdate()
    if not State.life then return end
  end
  if State.shot then
    State.shot = State.shot - 1
    shotUpdate()
    if not State.shot then return end
  end
  if State.save then
    State.save = State.save - 1
    saveUpdate()
    if not State.save then return end
  end
  if State.mode ~= "playing" then return end
  local stepT0 = love.timer.getTime()
  State.hash:rebuild(Enemies)
  State.waves:update(dt, State)
  Enemies.update(dt, State)
  Towers.update(dt, State.hash, Projectiles)
  Projectiles.update(dt, State.hash)
  EnemyShots.update(dt, State)
  Enemies.compact()
  Villagers.update(dt, State)
  Checklist.update(dt, State)
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
  Particles.update(dt)
  if State.flash > 0 then State.flash = math.max(0, State.flash - dt * 1.6) end
  if State._prevHp and State.village.hp < State._prevHp then
    Camera.shake(5, 0.3)
    State.flash = math.min(0.55, State.flash + 0.35)
  end
  State._prevHp = State.village.hp
  if not State.harness and State.mode == "playing" then
    local cal = State.waves.calendar
    if cal.year > State._savedYear then State._pendingSave = true end
    State._savedYear = cal.year
    if State._pendingSave and State.waves.phase == "village" and Persistence.save(State) then
      State._pendingSave = false
      Checklist.notice("THE CULT ENDURES", "progress carved into the dark")
    end
  end
  local stepMs = (love.timer.getTime() - stepT0) * 1000
  State.stats.stepMs = State.stats.stepMs * 0.95 + stepMs * 0.05
  if State.village.hp <= 0 then
    State.ending = "fallen"
    State.mode = "gameover"
  elseif Villagers.failReason then
    State.ending = Villagers.failReason
    State.mode = "gameover"
  elseif Villagers.count() == 0 and Villagers.deaths > 0 then
    State.ending = "extinct"
    State.mode = "gameover"
  elseif Checklist.isDone("stars_right") and not Villagers.conceived
    and (Villagers.aliveAdults("m") == 0 or Villagers.aliveAdults("f") == 0) then
    State.ending = "no_vessel"
    State.mode = "gameover"
  end
end

function State.tryPlace(mx, my)
  if State.mode ~= "playing" or not State.buildMode then return end
  local wx, wy = Camera.toWorld(mx, my)
  local gx, gy = Grid.worldToTile(wx, wy)
  local placed = false
  if State.buildType == "wall" then
    local d = buildingData.wall
    if State.canAfford(d.cost) and Walls.canPlace(gx, gy) then
      pay(d.cost)
      Walls.place(gx, gy)
      placed = true
    end
  else
    local d = buildingData[State.buildType]
    if d and Checklist.canBuild(State.buildType) and State.canAfford(d.cost) and Buildings.canPlace(gx, gy, State.village) then
      pay(d.cost)
      Buildings.place(gx, gy, State.buildType, false)
      placed = true
    end
  end
  Audio.play(placed and "place" or "error")
end

function State.setBuildType(t)
  State.buildType = t
  State.buildMode = true
end

function State.draw()
  local panned = false
  if not State.paused then panned = Camera.updateKeyboard(1 / 60) end
  if panned then State.follow = false end
  if State.follow and State.selection and State.selection.villager then
    local v = State.selection.villager
    Camera.x = Camera.x + (v.x - Camera.x) * 0.08
    Camera.y = Camera.y + (v.y - Camera.y) * 0.08
    Camera.clamp()
  end
  Camera.updateShake(love.timer.getDelta())
  Camera.apply()
  Render.draw(State)
  Camera.unapply()
  UI.draw(State)
  if State.shot and State.shot == 1 then
    love.graphics.captureScreenshot("shot.png")
  end
end

function State.handleClick(x, y)
  return UI.handleClick(x, y, State)
end

return State
