-- Save/load of a running game. Snapshots primitives only, resolving all
-- references by id/index; restoring replays them onto a freshly reset world.
local Save = require("src.core.save")
local Grid = require("src.sim.grid")
local Camera = require("src.core.camera")
local Buildings = require("src.sim.buildings")
local Walls = require("src.sim.walls")
local Villagers = require("src.sim.villagers")
local Nodes = require("src.sim.nodes")
local Checklist = require("src.sim.checklist")
local Ages = require("src.sim.ages")
local Research = require("src.sim.research")
local Flow = require("src.sim.flowfield")

local Persistence = {}

local VERSION = 1

function Persistence.exists()
  return Save.exists()
end

function Persistence.canSave(S, force)
  if force then return S.mode == "playing" end
  return S.mode == "playing" and S.waves.phase == "village" and not S.harness
end

function Persistence.snapshot(S)
  local snap = { version = VERSION }
  local cal = S.waves.calendar
  snap.calendar = {
    year = cal.year, month = cal.month, t = cal.t,
    epoch = cal.epoch, apocalypse = cal.apocalypse, hordeDue = cal.hordeDue,
  }
  snap.stock = { wood = S.stock.wood, food = S.stock.food, stone = S.stock.stone }
  snap.village = { hp = S.village.hp, maxHp = S.village.maxHp }
  snap.camera = { x = Camera.x, y = Camera.y, zoom = Camera.zoom }

  local bl = {}
  for i = 1, Buildings.n do
    bl[i] = {
      kind = Buildings.kind[i], gx = Buildings.gx[i], gy = Buildings.gy[i],
      hp = Buildings.hp[i], maxHp = Buildings.maxHp[i], progress = Buildings.progress[i],
      built = Buildings.built[i], crewCount = Buildings.crewCount[i], cd = Buildings.cd[i],
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
      manId = c.man and c.man.id or nil, womanId = c.woman and c.woman.id or nil,
      pregnant = c.pregnant, monthsLeft = c.monthsLeft, askIn = c.askIn, pending = c.pending,
      chosen = c.chosen, conceived = c.conceived, conceiving = c.conceiving, altar = c.altar,
    }
  end
  snap.couples = cl
  snap.requestId = Villagers.request and Villagers.request.id or nil
  snap.deaths = Villagers.deaths
  snap.conceived = Villagers.conceived
  snap.seenEpoch = Villagers.seenEpoch

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
  if not snap or snap.version ~= VERSION then return false end
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
  Villagers.load(snap.villagers, snap.couples, snap.requestId, snap.deaths, snap.conceived, snap.seenEpoch)
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

function Persistence.load(S)
  local snap = Save.read()
  if not snap then return false end
  return Persistence.restore(S, snap)
end

return Persistence
