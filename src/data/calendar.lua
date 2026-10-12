-- In-game calendar. One year = 12 months; the yearly horde arrives when the
-- year-end month (hordeMonth) begins. Months tick continuously through both
-- the village and wave phases (pregnancy will depend on this later).
return {
  monthLength = 48, -- real seconds per in-game month (~10 min per year)
  hordeMonth = 12,  -- the horde arrives when this month begins
  startMonth = 9,   -- campaign opens in month 9 of year 1 (~3 months to prep)
}
