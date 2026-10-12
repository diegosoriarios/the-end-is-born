local waveData = require("src.data.waves")
local Calendar = require("src.sim.calendar")
local Grid = require("src.sim.grid")
local Camera = require("src.core.camera")
local Audio = require("src.audio.audio")

local EDGES = { "N", "S", "E", "W" }

local Waves = {}
Waves.__index = Waves

-- Flatten a wave definition into a time-sorted list of spawn events.
local function buildTimeline(def, hpMul)
  local evs = {}
  local groups = def.groups or {}
  for g = 1, #groups do
    local grp = groups[g]
    local gap = grp.gap or waveData.spawnInterval
    local delay = grp.delay or 0
    local count = grp.count or 0
    local mul = hpMul * (grp.hpMul or 1)
    for k = 0, count - 1 do
      evs[#evs + 1] = { t = delay + k * gap, kind = grp.kind, edge = grp.edge or "random", hpMul = mul }
    end
  end
  table.sort(evs, function(a, b) return a.t < b.t end)
  return evs
end

function Waves.new()
  return setmetatable({
    calendar = Calendar.new(),
    phase = "village",
    number = 0,
    apocCount = 0,
    timeline = {},
    ti = 1,
    clock = 0,
    bossKind = nil,
    hordesSurvived = 0,
    pv = nil,
    pvKey = nil,
  }, Waves)
end

function Waves:skip()
  if self.phase == "village" then
    self.calendar:skipToHorde()
  end
end

function Waves.resolveWave(year)
  return waveData.waves[year] or (waveData.default and waveData.default(year) or nil)
end

function Waves.startDef(cal, apocCount)
  if cal.apocalypse then
    return waveData.apocalypse(apocCount + 1), 1 + waveData.apocHpGrowth * apocCount
  end
  return Waves.resolveWave(cal.year), 1 + waveData.hpGrowth * (cal.year - 1)
end

-- Next horde summary for the HUD (cached; only `secs` updates per frame).
function Waves:preview()
  local cal = self.calendar
  local key = cal.apocalypse and ("a" .. self.apocCount) or ("y" .. cal.year)
  if self.pvKey ~= key or not self.pv then
    local def, hpMul = Waves.startDef(cal, self.apocCount)
    local counts, order, edges = {}, {}, {}
    if def then
      for _, grp in ipairs(def.groups or {}) do
        if not counts[grp.kind] then
          counts[grp.kind] = 0
          order[#order + 1] = grp.kind
        end
        counts[grp.kind] = counts[grp.kind] + (grp.count or 0)
        local e = grp.edge
        if type(e) == "table" then
          for _, name in ipairs(e) do edges[name] = true end
        elseif e then
          edges[e] = true
        else
          for _, name in ipairs(EDGES) do edges[name] = true end
        end
      end
    end
    self.pv = {
      label = cal.apocalypse and ("END TIMES HORDE " .. (self.apocCount + 1)) or ("YEAR " .. cal.year .. " HORDE"),
      counts = counts,
      order = order,
      edges = edges,
      hpMul = hpMul,
      boss = def and def.boss or nil,
    }
    self.pvKey = key
  end
  self.pv.secs = cal:secondsToHorde()
  return self.pv
end

local function edgePoint(which)
  local W, H = Grid.pixelWidth(), Grid.pixelHeight()
  local m = 24
  local r = love.math.random
  if which == "N" then
    return r(m, W - m), m
  elseif which == "S" then
    return r(m, W - m), H - m
  elseif which == "W" then
    return m, r(m, H - m)
  elseif which == "E" then
    return W - m, r(m, H - m)
  else
    return edgePoint(EDGES[r(4)])
  end
end

function Waves.spawnAtEdge(enemies, kind, hpMul, edge)
  local e = edge
  if type(e) == "table" then e = e[love.math.random(#e)] end
  local x, y = edgePoint(e)
  enemies.spawn(x, y, kind, hpMul)
end

function Waves:startWave()
  local cal = self.calendar
  local def, hpMul
  if cal.apocalypse then
    self.apocCount = self.apocCount + 1
    def = waveData.apocalypse(self.apocCount)
    hpMul = 1 + waveData.apocHpGrowth * (self.apocCount - 1)
    self.number = self.apocCount
  else
    self.number = cal.year
    def, hpMul = Waves.startDef(cal, self.apocCount)
  end
  self.phase = "wave"
  self.clock = 0
  self.ti = 1
  self.bossKind = def and def.boss or nil
  self.timeline = def and buildTimeline(def, hpMul) or {}
  self.pvKey = nil
  if self.bossKind then Camera.shake(8, 0.7) else Camera.shake(3, 0.35) end
  Audio.play("horn")
end

function Waves:update(dt, ctx)
  local cal = self.calendar
  cal:update(dt)
  if self.phase == "village" then
    if cal.hordeDue then
      cal.hordeDue = false
      self:startWave()
    end
    return
  end
  self.clock = self.clock + dt
  local evs = self.timeline
  local total = #evs
  while self.ti <= total and evs[self.ti].t <= self.clock do
    local ev = evs[self.ti]
    Waves.spawnAtEdge(ctx.enemies, ev.kind, ev.hpMul, ev.edge)
    self.ti = self.ti + 1
  end
  if self.ti > total and ctx.enemies.n == 0 then
    self.phase = "village"
    self.bossKind = nil
    if not cal.apocalypse then
      self.hordesSurvived = math.max(self.hordesSurvived, self.number)
      if waveData.victoryYear and self.number >= waveData.victoryYear then
        ctx.ending = "years"
        ctx.mode = "victory"
      end
    end
  end
end

return Waves
