-- Persisted user settings (hand-rolled key=value in the LÖVE save dir).
local Settings = {
  master = 0.8,
  sfx = 0.9,
  music = 0.6,
  shake = true,
  fullscreen = false,
}

local PATH = "settings.cfg"
local Audio = require("src.audio.audio")
local Camera = require("src.core.camera")

local function truthy(v)
  return v == "1" or v == "true" or v == "yes"
end

function Settings.load()
  local data = love.filesystem.read(PATH)
  if not data then return end
  for line in data:gmatch("[^\n]+") do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k == "master" then
      Settings.master = tonumber(v) or Settings.master
    elseif k == "sfx" then
      Settings.sfx = tonumber(v) or Settings.sfx
    elseif k == "music" then
      Settings.music = tonumber(v) or Settings.music
    elseif k == "shake" then
      Settings.shake = truthy(v)
    elseif k == "fullscreen" then
      Settings.fullscreen = truthy(v)
    end
  end
end

function Settings.save()
  local s = ("master=%.3f\nsfx=%.3f\nmusic=%.3f\nshake=%d\nfullscreen=%d\n")
    :format(Settings.master, Settings.sfx, Settings.music,
      Settings.shake and 1 or 0, Settings.fullscreen and 1 or 0)
  love.filesystem.write(PATH, s)
end

function Settings.apply()
  Audio.setVolumes(Settings.master, Settings.sfx, Settings.music)
  Camera.setShakeEnabled(Settings.shake)
  if love.window.getFullscreen() ~= Settings.fullscreen then
    love.window.setFullscreen(Settings.fullscreen, "desktop")
  end
end

function Settings.adjust(key, delta)
  Settings[key] = math.max(0, math.min(1, (Settings[key] or 0) + delta))
  Settings.apply()
  Settings.save()
end

function Settings.toggle(key)
  Settings[key] = not Settings[key]
  Settings.apply()
  Settings.save()
end

return Settings
