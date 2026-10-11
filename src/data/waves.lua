return {
  startDelay = 20,
  countdown = 25,
  spawnInterval = 0.3,
  totalWaves = 3,
  enemyType = "grunt",
  hpGrowth = 0.15,
  spawnPerWave = function(n)
    return 12 + n * n * 6
  end,
}
