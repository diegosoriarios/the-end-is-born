-- Save/load of a running game. Snapshots primitives only, resolving all
-- references by id/index; restoring replays them onto a freshly reset world.
local Save = require("src.core.save")
local Grid = require("src.sim.grid")
local Camera = require("src.core.camera")
local Buildings = require("src.sim.buildings")
local Walls = require("src.sim.walls")
local Villagers = require("src.sim.villagers")
local Enemies = require("src.sim.enemies")
local Projectiles = require("src.sim.projectiles")
local EnemyShots = require("src.sim.enemyShots")
local Nodes = require("src.sim.nodes")
local Checklist = require("src.sim.checklist")
local Ages = require("src.sim.ages")
local Research = require("src.sim.research")
local Flow = require("src.sim.flowfield")

local Persistence = {}

local VERSION = 2

function Persistence.exists()
  return Save.exists()
end

function Persistence.canSave(S, force)
  if force then return S.mode == "playing" end
  return S.mode == "playing" and not S.harness
end

function Persistence.snapshot(S)
  local snap = { version = VERSION }
  local cal = S.waves.calendar
  snap.calendar = {
    year = cal.year, month = cal.month, t = cal.t,
    epoch = cal.epoch, apocalypse = cal.apocalypse, hordeDue = cal.hordeDue,
  }
  snap.stock = { wood = S.stock.wood, food = S.stock.food, stone = S.stock.stone, bone = S.stock.bone or 0 }
  snap.village = { hp = S.village.hp, maxHp = S.village.maxHp }
  snap.camera = { x = Camera.x, y = Camera.y, zoom = Camera.zoom }

  local bl = {}
  for i = 1, Buildings.n do
    bl[i] = {
      kind = Buildings.kind[i], gx = Buildings.gx[i], gy = Buildings.gy[i],
      hp = Buildings.hp[i], maxHp = Buildings.maxHp[i], progress = Buildings.progress[i],
      built = Buildings.built[i], crewCount = Buildings.crewCount[i], maxCrew = Buildings.maxCrew[i] or 0,
      graves = Buildings.graves[i] or 0, cd = Buildings.cd[i],
      project = Buildings.project[i], rprogress = Buildings.rprogress[i],
    }
  end
  snap.buildings = bl

  local wl = {}
  for i = 1, Walls.n do
    wl[i] = { gx = Walls.gx[i], gy = Walls.gy[i], hp = Walls.hp[i], maxHp = Walls.maxHp[i] }
  end
  snap.walls = wl

  local nl = {}
  for i = 1, #Nodes.list do
    local nd = Nodes.list[i]
    nl[i] = { kind = nd.kind, res = nd.res, x = nd.x, y = nd.y, amount = nd.amount, max = nd.max, regen = nd.regen, r = nd.r }
  end
  snap.nodes = nl

  local nodeIndex = {}
  for i = 1, #Nodes.list do nodeIndex[Nodes.list[i]] = i end
  local vl = {}
  for i = 1, #Villagers.list do
    local v = Villagers.list[i]
    vl[i] = {
      id = v.id, x = v.x, y = v.y, sex = v.sex, family = v.family,
      hp = v.hp, maxHp = v.maxHp, r = v.r,
      job = v.job, state = v.state, carry = v.carry, carryRes = v.carryRes,
      nodeIndex = v.node and nodeIndex[v.node] or nil,
      buildTarget = v.buildTarget, building = v.building, altar = v.altar,
      ritual = v.ritual, mob = v.mob,
      timer = v.timer, wx = v.wx, wy = v.wy, age = v.age, growLeft = v.growLeft,
      undead = v.undead, confined = v.confined,
    }
  end
  snap.villagers = vl

  local cl = {}
  for i = 1, #Villagers.couples do
    local c = Villagers.couples[i]
    cl[i] = {
      id = c.id, house = c.house,
      aId = c.a and c.a.id or nil, bId = c.b and c.b.id or nil, fertile = c.fertile,
      pregnant = c.pregnant, monthsLeft = c.monthsLeft, askIn = c.askIn, pending = c.pending,
      chosen = c.chosen, conceived = c.conceived, conceiving = c.conceiving, altar = c.altar,
    }
  end
  snap.couples = cl
  snap.requestId = Villagers.request and Villagers.request.id or nil
  snap.deaths = Villagers.deaths
  snap.conceived = Villagers.conceived
  snap.seenEpoch = Villagers.seenEpoch
  snap.mobilized = Villagers.mobilized
  snap.vesselId = Villagers.vesselId

  local el = {}
  for i = 1, Enemies.n do
    el[i] = {
      kind = Enemies.KINDS[Enemies.kind[i]],
      x = Enemies.x[i], y = Enemies.y[i], hx = Enemies.hx[i], hy = Enemies.hy[i],
      hp = Enemies.hp[i], maxHp = Enemies.maxHp[i],
      attackTimer = Enemies.attackTimer[i], blk = Enemies.blk[i],
    }
  end
  snap.enemies = el
  local pl = {}
  for i = 1, Projectiles.n do
    pl[i] = {
      x = Projectiles.x[i], y = Projectiles.y[i], vx = Projectiles.vx[i], vy = Projectiles.vy[i],
      damage = Projectiles.damage[i], life = Projectiles.life[i],
    }
  end
  snap.projectiles = pl
  local sl = {}
  for i = 1, EnemyShots.n do
    sl[i] = {
      x = EnemyShots.x[i], y = EnemyShots.y[i], vx = EnemyShots.vx[i], vy = EnemyShots.vy[i],
      damage = EnemyShots.damage[i], life = EnemyShots.life[i],
    }
  end
  snap.enemyShots = sl
  snap.kills = Enemies.kills
  snap.projectileHits = Projectiles.hits
  snap.shotHits = EnemyShots.hits

  snap.checklist = {
    ids = Checklist.doneIds(),
    sacrifices = Checklist.sacrifices,
    burns = Checklist.burns,
  }
  snap.age = Ages.current
  snap.research = Research.ids()

  local w = S.waves
  local tl = {}
  for i = 1, #w.timeline do
    local e = w.timeline[i]
    tl[i] = { t = e.t, kind = e.kind, edge = e.edge, hpMul = e.hpMul }
  end
  snap.timeline = tl
  snap.waves = {
    phase = w.phase, number = w.number, apocCount = w.apocCount,
    hordesSurvived = w.hordesSurvived, clock = w.clock, ti = w.ti, bossKind = w.bossKind,
  }
  return snap
end

function Persistence.save(S, force)
  if not Persistence.canSave(S, force) then return false end
  return Save.write(Persistence.snapshot(S))
end

function Persistence.restore(S, snap)
  if not snap or not snap.version or snap.version < 1 or snap.version > VERSION then return false end
  S.reset()
  local cal = S.waves.calendar
  cal.year = snap.calendar.year
  cal.month = snap.calendar.month
  cal.t = snap.calendar.t
  cal.epoch = snap.calendar.epoch
  cal.apocalypse = snap.calendar.apocalypse
  cal.hordeDue = snap.calendar.hordeDue
  S.stock.wood = snap.stock.wood
  S.stock.food = snap.stock.food
  S.stock.stone = snap.stock.stone
  S.stock.bone = snap.stock.bone or 0
  S.village.hp = snap.village.hp
  S.village.maxHp = snap.village.maxHp
  Camera.x, Camera.y, Camera.zoom = snap.camera.x, snap.camera.y, snap.camera.zoom
  Camera.clamp()
  Buildings.load(snap.buildings)
  Walls.load(snap.walls)
  Nodes.list = snap.nodes
  Checklist.load(snap.checklist.ids, snap.checklist.sacrifices, snap.checklist.burns)
  Ages.load(snap.age)
  Research.load(snap.research)
  Enemies.load(snap.enemies, snap.kills)
  Projectiles.load(snap.projectiles, snap.projectileHits)
  EnemyShots.load(snap.enemyShots, snap.shotHits)
  Villagers.load(snap.villagers, snap.couples, snap.requestId, snap.deaths, snap.conceived,
    snap.seenEpoch, snap.mobilized, snap.vesselId)
  local w = S.waves
  w.phase = snap.waves.phase
  w.number = snap.waves.number
  w.apocCount = snap.waves.apocCount
  w.hordesSurvived = snap.waves.hordesSurvived
  w.clock = snap.waves.clock
  w.ti = snap.waves.ti
  w.bossKind = snap.waves.bossKind
  w.timeline = snap.timeline
  w.pvKey = nil
  Flow.rebake(S.villageCells)
  S._prevHp = S.village.hp
  S._savedYear = cal.year
  S._pendingSave = false
  return true
end

function Persistence.validate(snap)
  if type(snap) ~= "table" then return false end
  if type(snap.version) ~= "number" or snap.version < 1 or snap.version > VERSION then return false end
  local required = {
    "calendar", "stock", "village", "camera", "buildings", "walls", "nodes",
    "villagers", "couples", "enemies", "projectiles", "enemyShots", "timeline",
    "waves", "checklist",
  }
  for i = 1, #required do
    if type(snap[required[i]]) ~= "table" then return false end
  end
  if snap.research ~= nil and type(snap.research) ~= "table" then return false end
  if type(snap.calendar.year) ~= "number" or type(snap.calendar.month) ~= "number" then return false end
  if type(snap.stock.wood) ~= "number" or type(snap.stock.food) ~= "number"
    or type(snap.stock.stone) ~= "number" then return false end
  if type(snap.village.hp) ~= "number" or type(snap.village.maxHp) ~= "number" then return false end
  if type(snap.camera.x) ~= "number" or type(snap.camera.y) ~= "number" or type(snap.camera.zoom) ~= "number" then return false end
  if type(snap.waves.phase) ~= "string" or type(snap.waves.clock) ~= "number" then return false end
  if type(snap.checklist.ids) ~= "table" then return false end
  return true
end

function Persistence.load(S)
  S.loadedFromBackup = false
  local snap = Save.read()
  if not snap then return false, "unreadable" end
  if not Persistence.validate(snap) and Save.lastRead == "primary" then
    snap = Save.readBackup()
  end
  if not snap or not Persistence.validate(snap) then return false, "invalid" end
  local ok, restored = pcall(Persistence.restore, S, snap)
  if not ok then return false, restored end
  if not restored then return false, "restore failed" end
  S.loadedFromBackup = Save.lastRead == "backup"
  return true
end

return Persistence
