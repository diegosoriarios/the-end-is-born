-- Enemy roster. `color` drives the runtime sprite generator (base, rim, shine).
-- Optional per-kind knobs: wallDamageMul (melee damage vs walls/buildings),
-- range + projectileSpeed (ranged siege behavior), boss (milestone waves).
return {
  grunt = {
    name = "Grunt", hp = 30, speed = 42, r = 7, damage = 5, attackInterval = 1.0,
    color = { { 0.82, 0.20, 0.24 }, { 0.45, 0.08, 0.12 }, { 1, 0.55, 0.55 } },
  },
  runner = {
    name = "Runner", hp = 14, speed = 88, r = 5, damage = 3, attackInterval = 0.8,
    color = { { 0.93, 0.62, 0.18 }, { 0.55, 0.30, 0.06 }, { 1, 0.85, 0.55 } },
  },
  brute = {
    name = "Brute", hp = 150, speed = 26, r = 11, damage = 25, attackInterval = 1.6,
    wallDamageMul = 3,
    color = { { 0.45, 0.16, 0.50 }, { 0.22, 0.05, 0.26 }, { 0.85, 0.55, 0.90 } },
  },
  spitter = {
    name = "Spitter", hp = 40, speed = 34, r = 7, damage = 10, attackInterval = 2.2,
    range = 150, projectileSpeed = 240,
    color = { { 0.35, 0.65, 0.25 }, { 0.14, 0.32, 0.10 }, { 0.75, 1, 0.6 } },
  },
  behemoth = {
    name = "Behemoth", hp = 1800, speed = 16, r = 18, damage = 60, attackInterval = 2.0,
    wallDamageMul = 8, boss = true,
    color = { { 0.16, 0.10, 0.18 }, { 0.55, 0.08, 0.14 }, { 0.7, 0.3, 0.4 } },
  },
}
