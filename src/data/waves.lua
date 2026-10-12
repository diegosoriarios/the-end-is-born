-- Data-driven yearly hordes. The horde arrives when the year-end month begins
-- (see src/data/calendar.lua). Each wave definition:
--   boss   = "behemoth"          -- optional boss kind (hp bar in HUD)
--   groups = { { kind = "grunt", count = 20, edge = "N"|"S"|"E"|"W"|"random"|{...},
--                      delay = 5, gap = 0.3, hpMul = 1 }, ... }
-- `apocalypse(n)` builds the escalating monthly end-times waves (triggered by
-- the checklist in a later milestone; debug-toggle in game with P).
return {
  hpGrowth = 0.12,     -- enemy hp multiplier per year
  apocHpGrowth = 0.25, -- enemy hp multiplier per apocalypse month
  spawnInterval = 0.3, -- default seconds between spawns in a group
  victoryYear = 12,    -- fallback win if the ritual is never attempted

  waves = {
    [1] = { groups = {
      { kind = "grunt", count = 15, gap = 0.4 },
    } },
    [2] = { groups = {
      { kind = "grunt", count = 24, gap = 0.32 },
      { kind = "runner", count = 8, edge = "E", delay = 8, gap = 0.5 },
    } },
    [3] = { groups = {
      { kind = "grunt", count = 32, gap = 0.28 },
      { kind = "runner", count = 12, edge = { "N", "S" }, delay = 6, gap = 0.4 },
      { kind = "spitter", count = 4, edge = "W", delay = 14, gap = 1.6 },
    } },
    [4] = { groups = {
      { kind = "grunt", count = 42, gap = 0.24 },
      { kind = "runner", count = 16, edge = { "N", "S" }, delay = 5, gap = 0.35 },
      { kind = "spitter", count = 6, edge = { "E", "W" }, delay = 12, gap = 1.4 },
      { kind = "brute", count = 3, edge = "N", delay = 20, gap = 3 },
    } },
    [5] = { boss = "behemoth", groups = {
      { kind = "behemoth", count = 1, edge = "N", delay = 2, gap = 1 },
      { kind = "grunt", count = 30, gap = 0.3 },
      { kind = "runner", count = 10, edge = "S", delay = 10, gap = 0.5 },
    } },
    [6] = { groups = {
      { kind = "grunt", count = 60, gap = 0.18 },
      { kind = "runner", count = 20, edge = { "E", "W" }, delay = 6, gap = 0.3 },
      { kind = "spitter", count = 8, edge = { "N", "S" }, delay = 12, gap = 1.2 },
      { kind = "brute", count = 5, edge = "random", delay = 18, gap = 2.4 },
    } },
    [7] = { groups = { -- ambush year: a second prong arrives mid-siege
      { kind = "grunt", count = 45, gap = 0.2 },
      { kind = "runner", count = 14, edge = "W", delay = 4, gap = 0.35 },
      { kind = "grunt", count = 35, edge = "E", delay = 35, gap = 0.22 },
      { kind = "brute", count = 6, edge = "E", delay = 40, gap = 2.2 },
      { kind = "spitter", count = 8, edge = "W", delay = 25, gap = 1.4 },
    } },
    [8] = { groups = {
      { kind = "grunt", count = 90, gap = 0.15 },
      { kind = "runner", count = 30, edge = { "N", "S", "E", "W" }, delay = 5, gap = 0.25 },
      { kind = "spitter", count = 12, edge = { "E", "W" }, delay = 15, gap = 1.2 },
      { kind = "brute", count = 10, edge = "random", delay = 22, gap = 2 },
    } },
    [9] = { groups = {
      { kind = "grunt", count = 120, gap = 0.12 },
      { kind = "runner", count = 36, edge = { "N", "S" }, delay = 4, gap = 0.22 },
      { kind = "spitter", count = 16, edge = { "E", "W" }, delay = 12, gap = 1 },
      { kind = "brute", count = 16, edge = "random", delay = 18, gap = 1.6 },
    } },
    [10] = { boss = "behemoth", groups = {
      { kind = "behemoth", count = 2, edge = { "N", "S" }, delay = 2, gap = 12 },
      { kind = "grunt", count = 100, gap = 0.14 },
      { kind = "runner", count = 40, edge = { "E", "W" }, delay = 8, gap = 0.22 },
      { kind = "spitter", count = 12, edge = "N", delay = 20, gap = 1.2 },
    } },
    [11] = { groups = {
      { kind = "grunt", count = 200, gap = 0.1 },
      { kind = "runner", count = 60, edge = { "N", "S", "E", "W" }, delay = 4, gap = 0.18 },
      { kind = "spitter", count = 24, edge = { "E", "W" }, delay = 10, gap = 0.9 },
      { kind = "brute", count = 24, edge = "random", delay = 16, gap = 1.3 },
    } },
    [12] = { boss = "behemoth", groups = {
      { kind = "behemoth", count = 3, edge = { "N", "E", "W" }, delay = 2, gap = 10 },
      { kind = "grunt", count = 320, gap = 0.07 },
      { kind = "runner", count = 90, edge = { "N", "S", "E", "W" }, delay = 6, gap = 0.14 },
      { kind = "spitter", count = 32, edge = { "E", "W" }, delay = 12, gap = 0.8 },
      { kind = "brute", count = 40, edge = "random", delay = 20, gap = 1.1 },
    } },
  },

  -- Years beyond the authored list keep escalating.
  default = function(year)
    local y = year
    return {
      boss = (y % 5 == 0) and "behemoth" or nil,
      groups = {
        { kind = "grunt", count = 20 + y * 15, gap = 0.08 },
        { kind = "runner", count = 5 + y * 5, edge = { "N", "S", "E", "W" }, delay = 4, gap = 0.16 },
        { kind = "spitter", count = 2 + math.floor(y * 1.5), edge = { "E", "W" }, delay = 10, gap = 0.8 },
        { kind = "brute", count = math.floor(y * 2), edge = "random", delay = 16, gap = 1.2 },
      },
    }
  end,

  -- End times: one big horde per month while the Antichrist gestates.
  apocalypse = function(n)
    return {
      boss = (n % 3 == 0) and "behemoth" or nil,
      groups = {
        { kind = "grunt", count = 60 + n * 40, gap = 0.06 },
        { kind = "runner", count = 20 + n * 12, edge = { "N", "S", "E", "W" }, delay = 3, gap = 0.12 },
        { kind = "brute", count = 4 + n * 3, edge = "random", delay = 8, gap = 1.0 },
        { kind = "spitter", count = 4 + n * 2, edge = { "E", "W" }, delay = 6, gap = 0.7 },
      },
    }
  end,
}
