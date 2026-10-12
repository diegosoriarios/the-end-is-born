local entries = require("src.data.checklist")
local buildingData = require("src.data.buildings")
local Buildings = require("src.sim.buildings")
local Particles = require("src.fx.particles")
local Audio = require("src.audio.audio")

local HARVEST_COST = 50
local TOAST_LIFE = 4

local Checklist = {
  sacrifices = 0,
  burns = 0,
  toasts = {},
}

local done = {}
local stateOf = {}
local byId = {}
local poll = 0

for i = 1, #entries do
  byId[entries[i].id] = entries[i]
end

local function unlockText(entry)
  if not entry.unlocks then return nil end
  local parts = {}
  for _, u in ipairs(entry.unlocks) do
    if u == "rituals" then
      parts[#parts + 1] = "Dark Rituals"
    else
      local labels = { ballista = "Ballista", altar = "Altar" }
      parts[#parts + 1] = labels[u] or u
    end
  end
  return table.concat(parts, ", ")
end

local function toast(text, sub)
  Checklist.toasts[#Checklist.toasts + 1] = { text = text, sub = sub, t = TOAST_LIFE }
end

local function revealed(entry)
  if not entry.requires then return true end
  for _, id in ipairs(entry.requires) do
    if not done[id] then return false end
  end
  return true
end

local function complete(entry, S)
  done[entry.id] = true
  stateOf[entry.id] = "done"
  local sub = unlockText(entry)
  toast("THE CUSTOM IS FULFILLED", entry.name .. (sub and ("  —  Unlocked: " .. sub) or ""))
  if entry.id == "stars_right" then
    toast("NAME THE VESSEL", "choose a couple, then conceive at the Altar")
  end
  for i = 1, #entries do
    local e = entries[i]
    if stateOf[e.id] == "hidden" and revealed(e) then
      stateOf[e.id] = "active"
    end
  end
end

function Checklist.reset()
  Checklist.sacrifices = 0
  Checklist.burns = 0
  Checklist.toasts = {}
  done = {}
  stateOf = {}
  poll = 0
  for i = 1, #entries do
    local e = entries[i]
    stateOf[e.id] = revealed(e) and "active" or "hidden"
  end
end

function Checklist.notice(text, sub)
  toast(text, sub)
end

function Checklist.isDone(id)
  return done[id] == true
end

function Checklist.canBuild(kind)
  local d = buildingData[kind]
  if not d or not d.unlock then return true end
  return done[d.unlock] == true
end

function Checklist.ritualUnlocked()
  return done.raise_altar == true
end

function Checklist.doneCount()
  local n = 0
  for i = 1, #entries do
    if done[entries[i].id] then n = n + 1 end
  end
  return n, #entries
end

function Checklist.entryName(id)
  local e = byId[id]
  return e and e.name or id
end

function Checklist.list()
  return entries, stateOf
end

function Checklist.doneIds()
  local ids = {}
  for i = 1, #entries do
    if done[entries[i].id] then ids[#ids + 1] = entries[i].id end
  end
  return ids
end

function Checklist.load(doneIds, sacrifices, burns)
  Checklist.reset()
  Checklist.sacrifices = sacrifices or 0
  Checklist.burns = burns or 0
  for i = 1, #(doneIds or {}) do
    done[doneIds[i]] = true
  end
  for i = 1, #entries do
    local e = entries[i]
    if done[e.id] then
      stateOf[e.id] = "done"
    elseif revealed(e) then
      stateOf[e.id] = "active"
    else
      stateOf[e.id] = "hidden"
    end
  end
end

function Checklist.burnHarvest(S)
  if not Checklist.ritualUnlocked() then return false end
  if (S.stock.food or 0) < HARVEST_COST then return false end
  S.stock.food = S.stock.food - HARVEST_COST
  Checklist.burns = Checklist.burns + 1
  for i = 1, Buildings.n do
    if Buildings.kind[i] == "altar" and Buildings.built[i] then
      Particles.flame(Buildings.x[i], Buildings.y[i], 10)
      break
    end
  end
  Audio.play("ritual")
  toast("THE HARVEST BURNS", HARVEST_COST .. " food offered to the dark")
  return true
end

function Checklist.update(dt, S)
  local i = 1
  while i <= #Checklist.toasts do
    local t = Checklist.toasts[i]
    t.t = t.t - dt
    if t.t <= 0 then
      table.remove(Checklist.toasts, i)
    else
      i = i + 1
    end
  end
  poll = poll + dt
  if poll < 0.25 then return end
  poll = 0
  for k = 1, #entries do
    local e = entries[k]
    if stateOf[e.id] == "active" and e.condition(S) then
      complete(e, S)
    end
  end
end

Checklist.HARVEST_COST = HARVEST_COST

return Checklist
