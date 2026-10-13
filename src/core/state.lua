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
local Ages = require("src.sim.ages")
local Research = require("src.sim.research")
local Stats = require("src.sim.stats")
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
  State.buildCategory = "defense"
  State.debug = false
  State.accumulator = 0
  State.selection = nil
  State.follow = false
  State.checklistVisible = true
  Grid.resetOccupancy()
  Particles.clear()
  Stats.reset()
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
    bone = resData.starting.bone or 0,
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
  Ages.reset()
  Research.reset()
  Villagers.onSacrificed = function()
    Checklist.sacrifices = Checklist.sacrifices + 1
  end
  Villagers.onHeartSacrifice = function(v)
    if v and v.ritual == "heal" then
      local d = buildingData.village_center
      State.village.hp = math.min(State.village.maxHp, State.village.hp + (d.sacrificeHeal or 40))
      Checklist.notice("THE HEART ENDURES", "+" .. (d.sacrificeHeal or 40) .. " hp")
    else
      Ages.onVictim(State)
    end
  end
  Villagers.onDeath = function()
    if not Buildings.hasRole("graveyard") then return end
    State.stock.bone = (State.stock.bone or 0) + (buildingData.graveyard.bonesPerDeath or 0)
    for i = 1, Buildings.n do
      if Buildings.kind[i] == "graveyard" and Buildings.built[i] then
        Buildings.graves[i] = (Buildings.graves[i] or 0) + 1
        break
      end
    end
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
  Buildings.setRemoveHook(function(destroyed, movedFrom, movedTo, wx, wy)
    Villagers.onBuildingRemoved(destroyed, movedFrom, movedTo)
    if wx then Nodes.removeAt(wx, wy) end
  end)
  Buildings.setBuiltHook(function(i)
    local d = buildingData[Buildings.kind[i]]
    if d and d.role == "farm" and d.food then
      Nodes.add(d.food, Buildings.x[i], Buildings.y[i])
    end
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
  elseif love.filesystem.getInfo("content.flag") then
    State.content = 10
  elseif love.filesystem.getInfo("ages.flag") then
    State.ages = 600
    State.agesAction = 540
    State.agesDone = false
  elseif love.filesystem.getInfo("research.flag") then
    State.research = 900
    State.researchAction = 840
    State.researchDone = false
    State.researchSchool = nil
  elseif love.filesystem.getInfo("farm.flag") then
    State.farm = 5
    State.farmAction = 3
  elseif love.filesystem.getInfo("grave.flag") then
    State.grave = 40
    State.graveAction = 30
  elseif love.filesystem.getInfo("war.flag") then
    State.war = 700
    State.warAction = 640
    State.warPhase = "setup"
    State.warMob, State.warHealOk, State.warConfOk = false, false, false
  elseif love.filesystem.getInfo("assign.flag") then
    State.assign = 20
    State.assignAction = 10
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
  State.harness = (State.smoke or State.stress or State.stress2 or State.test or State.life or State.menu or State.shot or State.save or State.content or State.ages or State.research or State.farm or State.grave or State.war or State.assign) and true or false
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
    Villagers.makeChild(houseB, State)
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
    local house = place(0, 4, "house")
    place(5, 3, "house")
    place(0, -3, "altar")
    place(4, -4, "farm")
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
    -- showcase the house (couple / Make a child) panel + hidden locked tabs
    Checklist.load({ "first_union", "prove_flock", "flock_grows" }, 0, 0)
    Ages.load(1)
    State.stock.wood, State.stock.stone, State.stock.bone, State.stock.food = 300, 300, 60, 120
    place(-4, 4, "graveyard")
    if house > 0 then
      Villagers.bindCouple(house)
      State.selection = { building = house }
    else
      State.selection = { heart = true }
    end
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

local function contentUpdate()
  if State.content ~= 8 then return end
  local buildingData = require("src.data.buildings")
  local ageData = require("src.data.ages")
  local entries = require("src.data.checklist")
  local ageId = {}
  for i = 1, #ageData do ageId[ageData[i].id] = true end
  local problems, count = 0, 0
  for kind, d in pairs(buildingData) do
    count = count + 1
    if d.role ~= "heart" then
      if not d.name then print("[content] missing name: " .. kind); problems = problems + 1 end
      if not d.role then print("[content] missing role: " .. kind); problems = problems + 1 end
      if not d.render then print("[content] missing render: " .. kind); problems = problems + 1 end
      if d.buildable ~= false and d.cost and not d.order then print("[content] buildable missing order: " .. kind); problems = problems + 1 end
      if d.upgradeTo and not buildingData[d.upgradeTo.kind] then print("[content] bad upgradeTo: " .. kind); problems = problems + 1 end
      if d.age and not ageId[d.age] then print("[content] bad age: " .. kind .. " -> " .. tostring(d.age)); problems = problems + 1 end
    end
  end
  for i = 1, #entries do
    if entries[i].age and not ageId[entries[i].age] then
      print("[content] bad custom age: " .. entries[i].id .. " -> " .. tostring(entries[i].age)); problems = problems + 1
    end
  end
  local researchData = require("src.data.research")
  local rcount = 0
  for id, r in pairs(researchData) do
    rcount = rcount + 1
    if not r.name then print("[content] research missing name: " .. id); problems = problems + 1 end
    if r.age and not ageId[r.age] then print("[content] research bad age: " .. id); problems = problems + 1 end
    if not r.effect then print("[content] research missing effect: " .. id); problems = problems + 1 end
  end
  print(("[content] research=%d"):format(rcount))
  local order = Buildings.buildOrder()
  local names = {}
  for _, e in ipairs(order) do names[#names + 1] = e.kind end
  print(("[content] buildings=%d buildable=%d ages=%d order=%s problems=%d")
    :format(count, #order, #ageData, table.concat(names, ","), problems))
  love.event.quit()
  State.content = nil
end

local function agesUpdate()
  if State.agesAction and State.ages == State.agesAction then
    State.village.hp, State.village.maxHp = 1e9, 1e9
    State.stock.wood, State.stock.stone = 500, 500
    Checklist.load({ "first_union", "prove_flock", "flock_grows" }, 0, 0)
    local ok = Ages.ascend(State)
    print(("[ages] ascend=%s from=%s objectives=%s idleAdults=%d")
      :format(tostring(ok), Ages.age().name, tostring(Ages.objectivesDone("whispers")), Villagers.idleAdults()))
    State.agesAction = nil
  end
  if not State.agesDone and Ages.reached("blood") then
    State.agesDone = true
    print(("[ages] done: age=%d name=%s ballistaUnlocked=%s lockLabel=%s")
      :format(Ages.current, Ages.age().name, tostring(Ages.unlocked("ballista")), tostring(Ages.lockLabel("ballista"))))
    love.event.quit()
    State.ages = nil
  elseif State.ages and State.ages <= 0 then
    if not State.agesDone then
      print(("[ages] FAIL: age=%d ascending=%s (ascension did not complete)")
        :format(Ages.current, tostring(Ages.ascending)))
    end
    love.event.quit()
    State.ages = nil
  end
end

local function researchUpdate()
  if State.researchAction and State.research == State.researchAction then
    State.village.hp, State.village.maxHp = 1e9, 1e9
    State.stock.wood, State.stock.stone = 500, 500
    Ages.load(2) -- Blood: research becomes available
    local gx, gy = Grid.worldToTile(State.village.x + 4 * Grid.TILE, State.village.y)
    local school = Buildings.place(gx, gy, "school", true)
    local a1 = Villagers.assignResearcher(school)
    local a2 = Villagers.assignResearcher(school)
    local ok = Research.start(State, school, "sharp_bolts")
    print(("[research] school=%d assign=%s,%s start=%s researchers=%d")
      :format(school, tostring(a1), tostring(a2), tostring(ok), Buildings.researchers[school] or 0))
    State.researchSchool = school
    State.researchAction = nil
  end
  if not State.researchDone and Research.has("sharp_bolts") then
    State.researchDone = true
    print(("[research] done: purchased=%s towerDamageMul=%.2f")
      :format(tostring(Research.has("sharp_bolts")), Stats.value("towerDamage")))
    love.event.quit()
    State.research = nil
  elseif State.research and State.research <= 0 then
    if not State.researchDone then
      print(("[research] FAIL: project=%s progress=%.1f"):format(
        tostring(State.researchSchool and Buildings.project[State.researchSchool]),
        State.researchSchool and Buildings.rprogress[State.researchSchool] or 0))
    end
    love.event.quit()
    State.research = nil
  end
end

local function nodesAt(x, y)
  local c = 0
  for i = 1, #Nodes.list do
    local nd = Nodes.list[i]
    if nd.x == x and nd.y == y then c = c + 1 end
  end
  return c
end

local function farmUpdate()
  if State.farmAction and State.farm == State.farmAction then
    State.stock.wood = 500
    local gx, gy = Grid.worldToTile(State.village.x + 5 * Grid.TILE, State.village.y + 5 * Grid.TILE)
    local f = Buildings.place(gx, gy, "farm", true)
    Buildings.emitBuilt(f)
    local wx, wy = Buildings.x[f], Buildings.y[f]
    local afterBuild = nodesAt(wx, wy)
    Buildings.damage(f, 1e9)
    local afterDestroy = nodesAt(wx, wy)
    print(("[farm] built nodeAtTile=%d  destroyed nodeAtTile=%d  pass=%s")
      :format(afterBuild, afterDestroy, tostring(afterBuild == 1 and afterDestroy == 0)))
    love.event.quit()
    State.farm = nil
  end
  if State.farm and State.farm <= 0 then
    love.event.quit()
    State.farm = nil
  end
end

local function undeadCount()
  local c = 0
  for i = 1, #Villagers.list do
    local v = Villagers.list[i]
    if not v.dead and v.undead then c = c + 1 end
  end
  return c
end

local function graveUpdate()
  if State.graveAction and State.grave == State.graveAction then
    State.stock.wood, State.stock.stone, State.stock.bone = 500, 500, 0
    local gx, gy = Grid.worldToTile(State.village.x - 5 * Grid.TILE, State.village.y + 5 * Grid.TILE)
    local g = Buildings.place(gx, gy, "graveyard", true)
    local before = State.stock.bone
    local victim
    for i = 1, #Villagers.list do
      local v = Villagers.list[i]
      if not v.dead and not v.undead then victim = v break end
    end
    if victim then Villagers.kill(victim) end
    local afterDeath = State.stock.bone
    local graves = Buildings.graves[g] or 0
    State.stock.bone = 100
    local u0 = undeadCount()
    Villagers.spawnUndead(Buildings.x[g], Buildings.y[g])
    local u1 = undeadCount()
    local pass = afterDeath == (buildingData.graveyard.bonesPerDeath or 0) and graves == 1 and u1 == u0 + 1
    print(("[grave] graveyard=%d bones %d->%d graves=%d undead %d->%d pass=%s")
      :format(g, before, afterDeath, graves, u0, u1, tostring(pass)))
    love.event.quit()
    State.grave = nil
  end
  if State.grave and State.grave <= 0 then
    love.event.quit()
    State.grave = nil
  end
end

local function countJob(job)
  local c = 0
  for i = 1, #Villagers.list do
    local v = Villagers.list[i]
    if not v.dead and v.job == job then c = c + 1 end
  end
  return c
end

local function findConfined()
  for i = 1, #Villagers.list do
    local v = Villagers.list[i]
    if not v.dead and v.confined then return v end
  end
  return nil
end

local function warUpdate()
  if State.warAction and State.war == State.warAction then
    State.stock.wood, State.stock.stone, State.stock.food = 800, 800, 800
    local v = State.village
    local tx, ty = Grid.worldToTile(v.x + 3 * Grid.TILE, v.y)
    local tower = Buildings.place(tx, ty, "arrow_tower", true)
    local hx, hy = Grid.worldToTile(v.x - 4 * Grid.TILE, v.y)
    local house = Buildings.place(hx, hy, "house", true)
    Villagers.bindCouple(house)
    -- 1) mobilize: fill empty tower slots + shelter surplus, then restore
    local before = Buildings.crewCount[tower] or 0
    Villagers.mobilize()
    local mob = Buildings.crewCount[tower] or 0
    local shelter = countJob("shelter")
    Villagers.demobilize()
    local after = Buildings.crewCount[tower] or 0
    local left = countJob("shelter") + countJob("home")
    State.warMob = (before == 0 and mob == 1 and shelter >= 1 and after == 0 and left == 0)
    -- 2) heart heal via sacrifice
    v.hp = v.maxHp - 200
    State.warHealBase = v.hp
    local victim = Villagers.pickHeartSacrifice()
    if victim then Villagers.startHeartSacrifice(victim, "heal") end
    -- 3) confinement: start a pregnancy, jump it to the second half
    local c = Villagers.coupleAt(house)
    if c then
      Villagers.makeChild(house, State)
      c.monthsLeft = math.floor((vData.pregnancyMonths or 9) / 2) + 1
    end
    State.waves.calendar.epoch = State.waves.calendar.epoch + 1
    State.warPhase = "wait"
    State.warAction = nil
  end
  if State.warPhase == "wait" then
    if not State.warHealOk and State.village.hp > (State.warHealBase or 0) then State.warHealOk = true end
    if not State.warConfOk and findConfined() then State.warConfOk = true end
    if State.warHealOk and State.warConfOk then
      print(("[war] mobilize=%s heal=%s confine=%s")
        :format(tostring(State.warMob), tostring(State.warHealOk), tostring(State.warConfOk)))
      love.event.quit()
      State.war = nil
    end
  end
  if State.war and State.war <= 0 then
    print(("[war] TIMEOUT mobilize=%s heal=%s confine=%s")
      :format(tostring(State.warMob), tostring(State.warHealOk), tostring(State.warConfOk)))
    love.event.quit()
    State.war = nil
  end
end

local function assignUpdate()
  if not (State.assignAction and State.assign == State.assignAction) then return end
  State.stock.wood, State.stock.stone, State.stock.food = 800, 800, 800
  local v = State.village
  local vv
  for i = 1, #Villagers.list do
    local x = Villagers.list[i]
    if not x.dead and not x.undead then vv = x break end
  end
  local r = { node = false, tower = false, school = false, build = false }
  local tree
  for i = 1, #Nodes.list do
    if Nodes.list[i].kind == "tree" then tree = Nodes.list[i] break end
  end
  if tree and vv then
    r.node = State.assignTo(vv, tree.x, tree.y) and vv.job == "wood" and vv.node == tree
  end
  local tgx, tgy = Grid.worldToTile(v.x + 3 * Grid.TILE, v.y)
  local tower = Buildings.place(tgx, tgy, "arrow_tower", true)
  if vv then r.tower = State.assignTo(vv, Buildings.x[tower], Buildings.y[tower]) and vv.job == "crew" end
  local sgx, sgy = Grid.worldToTile(v.x - 4 * Grid.TILE, v.y)
  local school = Buildings.place(sgx, sgy, "school", true)
  if vv then r.school = State.assignTo(vv, Buildings.x[school], Buildings.y[school]) and vv.job == "research" end
  if vv then
    State.selection = { villager = vv }
    State.setBuildType("house")
    local hgx, hgy = Grid.worldToTile(v.x, v.y + 5 * Grid.TILE)
    local wx, wy = Grid.tileToWorld(hgx, hgy)
    local mx = (wx - Camera.x) * Camera.zoom + love.graphics.getWidth() / 2
    local my = (wy - Camera.y) * Camera.zoom + love.graphics.getHeight() / 2
    State.tryPlace(mx, my)
    local hb = Buildings.at(hgx, hgy)
    r.build = hb > 0 and (not Buildings.built[hb]) and vv.buildTarget == hb and vv.job == "build"
  end
  print(("[assign] node=%s tower=%s school=%s build=%s"):format(
    tostring(r.node), tostring(r.tower), tostring(r.school), tostring(r.build)))
  love.event.quit()
  State.assign = nil
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
  if State.content then
    State.content = State.content - 1
    contentUpdate()
    if not State.content then return end
  end
  if State.ages then
    State.ages = State.ages - 1
    agesUpdate()
    if not State.ages then return end
  end
  if State.research then
    State.research = State.research - 1
    researchUpdate()
    if not State.research then return end
  end
  if State.farm then
    State.farm = State.farm - 1
    farmUpdate()
    if not State.farm then return end
  end
  if State.grave then
    State.grave = State.grave - 1
    graveUpdate()
    if not State.grave then return end
  end
  if State.war then
    State.war = State.war - 1
    warUpdate()
    if not State.war then return end
  end
  if State.assign then
    State.assign = State.assign - 1
    assignUpdate()
    if not State.assign then return end
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
  Ages.update(dt, State)
  Research.update(dt, State)
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
  elseif Ages.reached("end") and not Villagers.conceived
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
    if d and Ages.unlocked(State.buildType) and State.canAfford(d.cost) and Buildings.canPlace(gx, gy, State.village) then
      pay(d.cost)
      local bi = Buildings.place(gx, gy, State.buildType, false)
      placed = true
      -- if a villager is selected, send them to build it
      local sel = State.selection
      if sel and sel.villager then Villagers.assignBuild(sel.villager, bi) end
    end
  end
  Audio.play(placed and "place" or "error")
end

-- Right-click targeting: assign the selected villager to whatever was clicked.
function State.assignTo(v, wx, wy)
  if not v or v.dead or v.confined or v.age == "child" then return false end
  local gx, gy = Grid.worldToTile(wx, wy)
  local b = Buildings.at(gx, gy)
  if b == 0 then
    for i = 1, Buildings.n do
      local dx, dy = Buildings.x[i] - wx, Buildings.y[i] - wy
      if dx * dx + dy * dy < 400 then b = i break end
    end
  end
  if b > 0 then
    local d = buildingData[Buildings.kind[b]]
    if not Buildings.built[b] then return Villagers.assignBuild(v, b) end
    if d.role == "tower" then return Villagers.assignCrewTo(b, v) end
    if d.role == "research" then return Villagers.assignResearcherTo(b, v) end
    if d.role == "farm" then
      local node = Nodes.atWorld(Buildings.x[b], Buildings.y[b])
      if node then return Villagers.assignNode(v, node) end
    end
    return false
  end
  for i = 1, #Nodes.list do
    local nd = Nodes.list[i]
    local dx, dy = nd.x - wx, nd.y - wy
    if dx * dx + dy * dy < (nd.r + 6) * (nd.r + 6) then
      return Villagers.assignNode(v, nd)
    end
  end
  return false
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
  if State.shot then State.flash = 0 end -- keep harness screenshots clean
  UI.draw(State)
  if State.shot and State.shot == 1 then
    love.graphics.captureScreenshot("shot.png")
  end
end

function State.handleClick(x, y)
  return UI.handleClick(x, y, State)
end

return State
