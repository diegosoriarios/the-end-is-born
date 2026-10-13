-- Research: timed, worker-driven projects at a research building (School /
-- University). Assign servants as researchers; they walk there and add
-- progress (more researchers = faster). Completing a project applies its
-- effect to the Stats channels.
local researchData = require("src.data.research")
local buildingData = require("src.data.buildings")
local Buildings = require("src.sim.buildings")
local Ages = require("src.sim.ages")
local Stats = require("src.sim.stats")
local Checklist = require("src.sim.checklist")
local Audio = require("src.audio.audio")

local RESEARCH_RATE = 1 -- researcher-seconds per second

local Research = { purchased = {} }

function Research.reset()
  Research.purchased = {}
end

function Research.load(ids)
  Research.purchased = {}
  for i = 1, #(ids or {}) do Research.purchased[ids[i]] = true end
end

function Research.has(id) return Research.purchased[id] == true end
function Research.def(id) return researchData[id] end

function Research.ids()
  local out = {}
  for id in pairs(Research.purchased) do out[#out + 1] = id end
  return out
end

function Research.available(kind)
  local d = buildingData[kind]
  local tier = (d and d.researchTier) or 0
  local out = {}
  for id, def in pairs(researchData) do
    if not Research.has(id) and (def.tier or 1) <= tier and (not def.age or Ages.reached(def.age)) then
      out[#out + 1] = { id = id, def = def }
    end
  end
  table.sort(out, function(a, b)
    local ta, tb = a.def.tier or 1, b.def.tier or 1
    if ta ~= tb then return ta < tb end
    return a.id < b.id
  end)
  return out
end

function Research.canStart(S, i, id)
  local def = researchData[id]
  if not def or Research.has(id) then return false end
  if Buildings.project[i] then return false end
  if not Buildings.built[i] or Buildings.role[i] ~= "research" then return false end
  local kind = Buildings.kind[i]
  if (def.tier or 1) > ((buildingData[kind].researchTier) or 0) then return false end
  if def.age and not Ages.reached(def.age) then return false end
  if def.cost then
    for res, amt in pairs(def.cost) do
      if (S.stock[res] or 0) < amt then return false end
    end
  end
  return true
end

function Research.start(S, i, id)
  if not Research.canStart(S, i, id) then return false end
  local def = researchData[id]
  if def.cost then
    for res, amt in pairs(def.cost) do S.stock[res] = (S.stock[res] or 0) - amt end
  end
  Buildings.project[i] = id
  Buildings.rprogress[i] = 0
  return true
end

function Research.progressFrac(i)
  local id = Buildings.project[i]
  if not id then return 0 end
  local def = researchData[id]
  if not def then return 0 end
  return math.min(1, (Buildings.rprogress[i] or 0) / def.time)
end

function Research.update(dt, S)
  for i = 1, Buildings.n do
    if Buildings.role[i] == "research" and Buildings.built[i] then
      local id = Buildings.project[i]
      if id then
        local def = researchData[id]
        local rate = Buildings.researchers[i] or 0
        if rate > 0 then
          Buildings.rprogress[i] = Buildings.rprogress[i] + rate * RESEARCH_RATE * dt
          if Buildings.rprogress[i] >= def.time then
            Research.purchased[id] = true
            Stats.apply(def.effect)
            Buildings.project[i] = nil
            Buildings.rprogress[i] = 0
            Audio.play("build_done")
            Checklist.notice("RESEARCH COMPLETE", def.name)
          end
        end
      end
    end
  end
end

return Research
