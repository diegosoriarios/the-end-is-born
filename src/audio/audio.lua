-- Audio manager. Prefers real files in assets/sfx/<name>.<ext> and
-- assets/music/theme.<ext>; otherwise uses procedurally generated SoundData.
-- Fully pcall-guarded: no audio device (or a load failure) disables it
-- silently so headless harness runs never crash.
local sfxgen = require("src.audio.sfxgen")

local EXT = { "ogg", "wav", "mp3" }

local Audio = {
  enabled = true,
  master = 0.8,
  sfxVol = 0.9,
  musicVol = 0.6,
  sources = {},
  pools = {},
  last = {},
  music = nil,
}

-- Per-sfx minimum spacing (seconds) and max concurrent clones.
local INTERVAL = {
  click = 0.03, place = 0.05, build_done = 0.08, error = 0.15,
  shoot = 0.045, ballista = 0.08, hit = 0.05, squelch = 0.09,
  horn = 0.5, ritual = 0.3,
}
local POLY = {
  shoot = 8, ballista = 6, hit = 6, squelch = 6, click = 4,
}

local function fileFor(dir, name)
  for i = 1, #EXT do
    local p = dir .. name .. "." .. EXT[i]
    if love.filesystem.getInfo(p) then return p end
  end
  return nil
end

function Audio.load()
  if not (love.audio and love.sound) then
    Audio.enabled = false
    return
  end
  local ok, err = pcall(function()
    for name in pairs(sfxgen.defs) do
      local path = fileFor("assets/sfx/", name)
      Audio.sources[name] = path
        and love.audio.newSource(path, "static")
        or love.audio.newSource(sfxgen.build(name), "static")
    end
  end)
  if not ok then
    Audio.enabled = false
    print("[audio] disabled: " .. tostring(err))
    return
  end
  pcall(function()
    local path = fileFor("assets/music/", "theme")
    if path then
      Audio.music = love.audio.newSource(path, "stream")
      Audio.music:setLooping(true)
    end
  end)
end

function Audio.setEnabled(v)
  Audio.enabled = v and true or false
  if not Audio.enabled then
    if Audio.music then Audio.music:stop() end
    for _, pool in pairs(Audio.pools) do
      for i = 1, #pool do pool[i]:stop() end
    end
  end
end

function Audio.setVolumes(master, sfx, music)
  if master then Audio.master = master end
  if sfx then Audio.sfxVol = sfx end
  if music then Audio.musicVol = music end
  if Audio.music then Audio.music:setVolume(Audio.master * Audio.musicVol) end
end

function Audio.startMusic()
  if not Audio.enabled or not Audio.music then return end
  Audio.music:setVolume(Audio.master * Audio.musicVol)
  if not Audio.music:isPlaying() then Audio.music:play() end
end

function Audio.play(name, opts)
  if not Audio.enabled then return end
  local base = Audio.sources[name]
  if not base then return end
  local now = love.timer.getTime()
  if Audio.last[name] and now - Audio.last[name] < (INTERVAL[name] or 0.02) then return end
  Audio.last[name] = now
  if love.audio.getActiveSourceCount and love.audio.getActiveSourceCount() > 48 then return end
  local pool = Audio.pools[name]
  if not pool then
    pool = {}
    Audio.pools[name] = pool
  end
  local src
  for i = 1, #pool do
    if not pool[i]:isPlaying() then
      src = pool[i]
      break
    end
  end
  if not src then
    if #pool >= (POLY[name] or 4) then return end
    src = base:clone()
    pool[#pool + 1] = src
  end
  local pitch = (opts and opts.pitch) or (1 + (love.math.random() - 0.5) * 0.12)
  src:setPitch(pitch)
  src:setVolume((opts and opts.volume or 1) * Audio.master * Audio.sfxVol)
  src:play()
end

return Audio
