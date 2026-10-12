-- The Antichrist checklist. Ordered chain: an entry becomes visible only once
-- every id in `requires` is complete. `unlocks` are building kinds (or the
-- sentinel "rituals") granted on completion. `progress(S)` is optional and
-- returns current, max for the HUD.
local Buildings = require("src.sim.buildings")

return {
  {
    id = "first_union",
    name = "The first union",
    desc = "Bind a couple to a house",
    condition = function(S) return S.villagers.coupleCount() >= 1 end,
    progress = function(S) return math.min(S.villagers.coupleCount(), 1), 1 end,
  },
  {
    id = "prove_flock",
    name = "Prove the flock",
    desc = "Survive the first horde",
    unlocks = { "ballista" },
    condition = function(S) return S.waves.hordesSurvived >= 1 end,
    progress = function(S) return math.min(S.waves.hordesSurvived, 1), 1 end,
  },
  {
    id = "flock_grows",
    name = "The flock grows",
    desc = "Grow the village to 8 servants",
    unlocks = { "altar" },
    condition = function(S) return S.villagers.count() >= 8 end,
    progress = function(S) return math.min(S.villagers.count(), 8), 8 end,
  },
  {
    id = "raise_altar",
    name = "Raise the Altar",
    desc = "Build the Altar",
    requires = { "flock_grows" },
    unlocks = { "rituals" },
    condition = function() return Buildings.hasBuilt("altar") end,
  },
  {
    id = "first_blood",
    name = "First blood",
    desc = "Let 10 servants die",
    requires = { "raise_altar" },
    condition = function(S) return S.villagers.deaths >= 10 end,
    progress = function(S) return math.min(S.villagers.deaths, 10), 10 end,
  },
  {
    id = "harvest_burns",
    name = "The harvest burns",
    desc = "Burn 50 food at the Altar",
    requires = { "first_blood" },
    condition = function(S) return S.checklist.burns >= 1 end,
  },
  {
    id = "blood_soil",
    name = "Blood for the soil",
    desc = "Sacrifice 3 servants at the Altar",
    requires = { "harvest_burns" },
    condition = function(S) return S.checklist.sacrifices >= 3 end,
    progress = function(S) return math.min(S.checklist.sacrifices, 3), 3 end,
  },
  {
    id = "horde_sated",
    name = "The horde is sated",
    desc = "Survive the year-5 horde",
    requires = { "blood_soil" },
    condition = function(S) return S.waves.hordesSurvived >= 5 end,
    progress = function(S) return math.min(S.waves.hordesSurvived, 5), 5 end,
  },
  {
    id = "fields_red",
    name = "The fields run red",
    desc = "Let 50 servants die",
    requires = { "horde_sated" },
    condition = function(S) return S.villagers.deaths >= 50 end,
    progress = function(S) return math.min(S.villagers.deaths, 50), 50 end,
  },
  {
    id = "stars_right",
    name = "The stars are right",
    desc = "Survive the year-6 horde",
    requires = { "fields_red" },
    condition = function(S) return S.waves.hordesSurvived >= 6 end,
    progress = function(S) return math.min(S.waves.hordesSurvived, 6), 6 end,
  },
  {
    id = "vessel_quickens",
    name = "The vessel quickens",
    desc = "Conceive the Antichrist at the Altar",
    requires = { "stars_right" },
    condition = function(S) return S.villagers.conceived end,
  },
}
