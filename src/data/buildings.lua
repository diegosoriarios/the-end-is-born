-- Building registry. Each entry carries stats + framework metadata:
--   name, role (behavior tag), render (drawer key), category, order (build-bar
--   position), and gates (unlock = milestone id, or age = age id later).
-- role drives sim behavior; render drives drawing. Adding a building with an
-- existing role+render needs no code.
return {
  village_center = { name = "Heart", role = "heart", hp = 500, r = 48, popCap = 4, sacrificeHeal = 40 },

  wall = { name = "Wall", role = "wall", render = "wall", category = "defense", order = 1,
    hp = 300, cost = { wood = 5 } },

  arrow_tower = { name = "Arrow Tower", role = "tower", render = "arrow_tower", category = "defense", order = 2,
    range = 170, fireInterval = 0.75, damage = 14, projectileSpeed = 420, hp = 180,
    cost = { wood = 20, stone = 10 }, buildTime = 6, crew = 1 },

  ballista = { name = "Ballista", role = "tower", render = "ballista", category = "defense", order = 3,
    range = 260, fireInterval = 2.2, damage = 60, projectileSpeed = 560, hp = 240,
    cost = { wood = 40, stone = 25 }, buildTime = 10, crew = 2, age = "blood" },

  house = { name = "House", role = "house", render = "house", category = "economy", order = 4,
    hp = 200, cost = { wood = 30 }, buildTime = 8, popCap = 2 },

  altar = { name = "Altar", role = "altar", render = "altar", category = "ritual", order = 5,
    hp = 300, cost = { wood = 60, stone = 40 }, buildTime = 14, age = "blood" },

  school = { name = "School", role = "research", render = "school", category = "research", order = 6,
    hp = 200, cost = { wood = 50, stone = 20 }, buildTime = 10, age = "blood",
    researchSlots = 2, researchTier = 1,
    upgradeTo = { kind = "university", cost = { wood = 120, stone = 80, food = 50 } },
    color = { 0.55, 0.45, 0.72 } },

  university = { name = "University", role = "research", render = "university", category = "research",
    hp = 320, cost = { wood = 120, stone = 80, food = 50 }, buildTime = 14, age = "bones",
    researchSlots = 4, researchTier = 3, buildable = false,
    color = { 0.42, 0.34, 0.62 } },

  -- Farm: destroyable building that becomes a high-yield renewable food node.
  farm = { name = "Farm", role = "farm", render = "farm", category = "economy", order = 7,
    hp = 140, cost = { wood = 25 }, buildTime = 6, age = "blood",
    food = { res = "food", amount = 40, regen = 0.15, r = 9 } },

  -- Graveyard: gathers bones from the dead; raise the dead as undead servants.
  graveyard = { name = "Graveyard", role = "graveyard", render = "graveyard", category = "ritual", order = 8,
    hp = 180, cost = { wood = 40, stone = 30 }, buildTime = 8, age = "bones",
    bonesPerDeath = 5, raiseCost = { bone = 20 } },
}
