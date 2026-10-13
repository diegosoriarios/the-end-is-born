-- Research catalog. Projects are run at a research building (School /
-- University); a servant is assigned per researcher slot and they walk there
-- and add progress. `time` is in researcher-seconds (N researchers finish in
-- time/N). `effect` feeds the Stats modifier channels.
return {
  sharp_bolts = { name = "Sharpened Bolts", desc = "+15% tower damage", age = "blood", tier = 1,
    cost = { wood = 40 }, time = 20, effect = { towerDamage = 0.15 } },

  swords = { name = "Forge Swords", desc = "Servants fight back", age = "blood", tier = 1,
    cost = { wood = 45, stone = 15 }, time = 24, effect = { villagerDamage = 1.0 } },

  shields = { name = "Beat Shields", desc = "Servants take less damage", age = "blood", tier = 1,
    cost = { wood = 35, stone = 30 }, time = 24, effect = { villagerArmor = 0.4 } },

  cursed_foundations = { name = "Cursed Foundations", desc = "+25% wall hp", age = "bones", tier = 2,
    cost = { stone = 80 }, time = 30, effect = { wallHp = 0.25 } },

  swift_hands = { name = "Swift Hands", desc = "+20% gather speed", age = "bones", tier = 2,
    cost = { wood = 60 }, time = 28, effect = { gatherSpeed = 0.2 } },

  bloody_rites = { name = "Bloody Rites", desc = "+25% tower damage", age = "chosen", tier = 3,
    cost = { wood = 100, stone = 60 }, time = 40, effect = { towerDamage = 0.25 } },
}
