local calData = require("src.data.calendar")

local Calendar = {}
Calendar.__index = Calendar

function Calendar.new()
  return setmetatable({
    year = 1,
    month = calData.startMonth,
    t = 0,
    monthLength = calData.monthLength,
    hordeMonth = calData.hordeMonth,
    apocalypse = false,
    hordeDue = false,
    epoch = 0,
  }, Calendar)
end

function Calendar:update(dt)
  self.t = self.t + dt
  local due = false
  local advanced = 0
  while self.t >= self.monthLength do
    self.t = self.t - self.monthLength
    self.month = self.month + 1
    advanced = advanced + 1
    if self.month > 12 then
      self.month = 1
      self.year = self.year + 1
    end
    if self.apocalypse or self.month == self.hordeMonth then
      due = true
    end
  end
  if advanced > 0 then self.epoch = self.epoch + advanced end
  if due then self.hordeDue = true end
end

-- Fast-forward to the horde (Space key / harness skip).
function Calendar:skipToHorde()
  if self.apocalypse then
    self.t = math.max(self.t, self.monthLength - 1 / 60)
    return
  end
  if self.month == self.hordeMonth then
    self.month = self.hordeMonth - 1
    self.year = self.year + 1
    self.epoch = self.epoch + 11
  else
    local target = self.hordeMonth - 1
    local jumped = (target - self.month) % 12
    self.month = target
    self.epoch = self.epoch + jumped
  end
  self.t = self.monthLength - 1 / 60
end

-- Real seconds until the next horde trigger (for the preview UI).
function Calendar:secondsToHorde()
  if self.apocalypse then return self.monthLength - self.t end
  local months = (self.hordeMonth - self.month) % 12
  if months == 0 then months = 12 end
  return months * self.monthLength - self.t
end

return Calendar
