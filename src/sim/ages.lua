-- Cult ages. Advance by completing the current age's objectives (checklist
-- entries tagged with that age id) and performing the Rite of Ascension at the
-- village heart: pay the age's cost and sacrifice a servant who walks to the
-- heart and dies. Unlocks land on ascension via Ages.reached / Ages.unlocked.
local ageData = require("src.data.ages")
local buildingData = require("src.data.buildings")
local Checklist = require("src.sim.checklist")
local Villagers = require("src.sim.villagers")
local Particles = require("src.fx.particles")
local Camera = require("src.core.camera")
local Audio = require("src.audio.audio")

local Ages = {
  current = 1,
  ascending = false,
  victim = nil,
}

local byId = {}
for i = 1, #ageData do byId[ageData[i].id] = i end

function Ages.reset()
  Ages.current = 1
  Ages.ascending = false
  Ages.victim = nil
end

function Ages.load(idx)
  Ages.current = math.max(1, math.min(#ageData, idx or 1))
  Ages.ascending = false
  Ages.victim = nil
end

function Ages.count() return #ageData end
function Ages.list() return ageData end
function Ages.age() return ageData[Ages.current] end
function Ages.next() return ageData[Ages.current + 1] end
function Ages.isEnd() return Ages.current >= #ageData end
function Ages.reached(id) return byId[id] ~= nil and Ages.current >= byId[id] end

-- Buildings unlocked once the given age is reached (no age = start kit).
function Ages.unlocked(kind)
  local d = buildingData[kind]
  if not d then return false end
  if not d.age then return true end
  return Ages.reached(d.age)
end

-- A kind's unlock requirement text for the build bar (nil if always available).
function Ages.lockLabel(kind)
  local d = buildingData[kind]
  if not d or not d.age then return nil end
  if Ages.reached(d.age) then return nil end
  local a = ageData[byId[d.age]]
  return a and a.name or d.age
end

-- Checklist objectives tagged with an age id.
function Ages.objectives(ageId)
  local entries = Checklist.list()
  local out = {}
  for i = 1, #entries do
    if entries[i].age == ageId then out[#out + 1] = entries[i] end
  end
  return out
end

function Ages.objectivesDone(ageId)
  local objs = Ages.objectives(ageId)
  for i = 1, #objs do
    if not Checklist.isDone(objs[i].id) then return false end
  end
  return true
end

function Ages.objectivesProgress(ageId)
  local objs = Ages.objectives(ageId)
  local done = 0
  for i = 1, #objs do
    if Checklist.isDone(objs[i].id) then done = done + 1 end
  end
  return done, #objs
end

-- Buildings the next age will unlock (for the "Next:" preview).
function Ages.nextUnlocks()
  local nxt = Ages.next()
  if not nxt then return {} end
  local out = {}
  for kind, d in pairs(buildingData) do
    if d.age == nxt.id then out[#out + 1] = d.name or kind end
  end
  table.sort(out)
  return out
end

function Ages.canAscend(S)
  if Ages.ascending or Ages.isEnd() then return false end
  if not Ages.objectivesDone(Ages.age().id) then return false end
  local a = Ages.age()
  if a.sacrifice and Villagers.idleAdults() < a.sacrifice then return false end
  if a.cost then
    for res, amt in pairs(a.cost) do
      if (S.stock[res] or 0) < amt then return false end
    end
  end
  return true
end

function Ages.ascend(S)
  if not Ages.canAscend(S) then return false end
  local a = Ages.age()
  local victim = Villagers.pickHeartSacrifice()
  if not victim then return false end
  if a.cost then
    for res, amt in pairs(a.cost) do S.stock[res] = (S.stock[res] or 0) - amt end
  end
  Ages.ascending = true
  Ages.victim = victim
  Villagers.startHeartSacrifice(victim)
  Camera.shake(6, 0.5)
  return true
end

-- Called when the ascension victim reaches the heart and dies.
function Ages.onVictim(S)
  if not Ages.ascending then return end
  Ages.ascending = false
  Ages.victim = nil
  Ages.current = math.min(#ageData, Ages.current + 1)
  local a = Ages.age()
  Particles.ritual(S.village.x, S.village.y)
  Camera.shake(9, 0.7)
  S.flash = 0.5
  Audio.play("ritual")
  Checklist.notice("THE AGE PASSES", a.name .. (Ages.isEnd() and " — name the vessel" or ""))
end

-- Recovery: if the victim died before reaching the heart, cancel the rite.
function Ages.update(dt, S)
  if Ages.ascending and Ages.victim and Ages.victim.dead then
    Ages.ascending = false
    Ages.victim = nil
    Checklist.notice("THE RITE FAILS", "the offering never reached the heart")
  end
end

return Ages
