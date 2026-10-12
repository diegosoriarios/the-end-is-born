-- Procedural sound effects. Builds love SoundData in code (no asset files
-- needed): a single oscillator with pitch sweeps, envelopes, optional noise
-- and vibrato. If a real file exists in assets/sfx/<name>.<ext> the audio
-- manager prefers it instead.
local sfxgen = {}

local RATE = 44100

local function synth(o)
  local dur = o.dur
  local n = math.floor(RATE * dur)
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  local phase = 0
  local f0 = o.f0 or 0
  local f1 = o.f1 or f0
  local shape = o.shape or "sine"
  local noise = o.noise or 0
  local vol = o.vol or 1
  for i = 0, n - 1 do
    local t = i / RATE
    local frac = dur > 0 and t / dur or 0
    local f
    if f0 == 0 then
      f = 0
    elseif o.exp then
      f = f0 * ((f1 / f0) ^ frac)
    else
      f = f0 + (f1 - f0) * frac
    end
    if o.vib then f = f * (1 + math.sin(t * o.vib.rate * 2 * math.pi) * o.vib.depth) end
    phase = phase + f / RATE
    local ph = phase - math.floor(phase)
    local w
    if shape == "sine" then
      w = math.sin(ph * 2 * math.pi)
    elseif shape == "square" then
      w = ph < 0.5 and 1 or -1
    elseif shape == "saw" then
      w = 2 * ph - 1
    elseif shape == "tri" then
      w = 1 - 4 * math.abs(ph - 0.5)
    else
      w = love.math.random() * 2 - 1
    end
    if noise > 0 then
      w = w * (1 - noise) + (love.math.random() * 2 - 1) * noise
    end
    local e
    if o.env == "swell" then
      local at = o.attack or 0.05
      local rl = o.release or 0.15
      e = math.min(1, t / at) * math.min(1, (dur - t) / rl)
    else
      local at = o.attack or 0.004
      local dc = o.decay or (dur * 0.6)
      e = math.min(1, t / at) * math.exp(-t / dc)
    end
    local s = w * e * vol
    if s > 1 then s = 1 elseif s < -1 then s = -1 end
    sd:setSample(i, s)
  end
  return sd
end

sfxgen.defs = {
  click = { dur = 0.05, shape = "square", f0 = 900, f1 = 1350, exp = true, decay = 0.018, vol = 0.30 },
  place = { dur = 0.14, shape = "sine", f0 = 220, f1 = 90, exp = true, decay = 0.06, noise = 0.25, vol = 0.55 },
  build_done = { dur = 0.32, shape = "tri", f0 = 520, f1 = 780, exp = true, env = "swell", attack = 0.02, release = 0.14, vol = 0.45 },
  error = { dur = 0.18, shape = "saw", f0 = 160, f1 = 92, exp = true, decay = 0.09, vol = 0.35 },
  shoot = { dur = 0.07, shape = "sine", f0 = 1500, f1 = 720, exp = true, decay = 0.024, noise = 0.15, vol = 0.22 },
  ballista = { dur = 0.20, shape = "saw", f0 = 320, f1 = 110, exp = true, decay = 0.08, noise = 0.30, vol = 0.40 },
  hit = { dur = 0.05, shape = "noise", decay = 0.02, noise = 1.0, vol = 0.22 },
  squelch = { dur = 0.24, shape = "saw", f0 = 240, f1 = 60, exp = true, decay = 0.10, noise = 0.35, vol = 0.35 },
  horn = { dur = 0.9, shape = "saw", f0 = 110, f1 = 150, env = "swell", attack = 0.16, release = 0.3, vib = { rate = 6, depth = 0.03 }, vol = 0.40 },
  ritual = { dur = 1.2, shape = "sine", f0 = 88, f1 = 132, env = "swell", attack = 0.3, release = 0.4, vol = 0.40 },
  sacrifice = { dur = 0.5, shape = "saw", f0 = 520, f1 = 70, exp = true, env = "swell", attack = 0.02, release = 0.22, noise = 0.2, vol = 0.42 },
  conceive = { dur = 1.5, shape = "sine", f0 = 60, f1 = 42, exp = true, env = "swell", attack = 0.4, release = 0.5, noise = 0.1, vol = 0.45 },
  birth = { dur = 1.6, shape = "sine", f0 = 220, f1 = 540, exp = true, env = "swell", attack = 0.25, release = 0.6, vib = { rate = 5, depth = 0.02 }, vol = 0.45 },
}

function sfxgen.build(name)
  local def = sfxgen.defs[name]
  if not def then return nil end
  return synth(def)
end

return sfxgen
