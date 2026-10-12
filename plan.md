# antic — Game Plan

A 2D top-down village builder / tower defense with a dark twist: you are the leader of a cute satanist cult (Cult of the Lamb vibes). Grow your village, survive escalating hordes of thousands of enemies, and secretly complete the dark checklist that will make the Antichrist come to earth. You win when the chosen couple births the baby.

## Core Loop

1. **Village phase** — months tick by (~48s each). Gather resources (wood, food, stone), build houses/walls/towers, assign villagers to jobs, manage couples, complete checklist objectives. The horde arrives when the year-end month (12) begins.
2. **Horde phase** — the yearly horde attacks from the map edges toward the village. Only **staffed** defenses fire. Crew can die mid-wave, taking their tower offline. Clearing the horde skips the rest of month 12 and a new year begins.
3. Repeat. Each year the horde grows and mixes in new enemy types (bosses at milestone years). Checklist progress unlocks the path to the final ritual.

**Win condition**: complete the customizable Antichrist checklist — the chosen couple conceives, the **end times begin** (one apocalypse horde per month), and after 9 months of pregnancy the Antichrist is born.

**Central tension**: villagers are the scarcest resource. Every villager gathering wood is one not crewing a ballista. Growth (approved births) fuels both defense and the dark checklist.

---

## Stack & Tooling

- **Engine**: LÖVE2D + Lua (installed at `/Applications/love.app`)
- **Run**:
  ```
  ./run.sh
  ```
  LÖVE 11.5's native arm64 build runs LuaJIT in **interpreter-only mode** (no JIT). `run.sh` forces the x86_64 slice via Rosetta, which enables the full LuaJIT JIT — measured ~7x faster hot loops (100M loop iterations: 0.16s vs 1.13s). This is required for thousands of enemies at 60fps; falls back to native mode if Rosetta is unavailable.
- **Headless test harnesses** (flag files, auto-deleted after run by `run.sh`):
  - `./run.sh --smoke` — 43s self-playing run: summons the year-1 horde, places 2 towers, plays the wave, prints summary, quits.
  - `./run.sh --stress` — 10,000-enemy stress test: wall ring + 4 towers + full swarm, prints step/draw timings.
  - `./run.sh --stress2` — 2,000-enemy combat validation (no walls).
  - `./run.sh --test` — deterministic 12-enemy combat trace.
  - `./run.sh --life` — couple/birth validation: binds 2 couples, conceives the vessel at the altar, fast-forwards 9 months, checks the Antichrist birth victory.
  - `./run.sh --menu` — boots to the title, opens/closes the settings screen, exercises the menu draw/hit paths, quits. Also captures `menu_title.png` / `menu_settings.png`.
  - `./run.sh --shot` — builds a small scene and captures `shot.png` (game view) to the save dir for visual checks.
  - `./run.sh --save` — builds a scene, saves, wipes it, loads, and asserts the round-trip matches.
- **Performance strategy (non-negotiables for thousands of enemies)**:
  - `SpriteBatch` rendering — one batched draw call per atlas
  - Data-oriented enemy storage — flat arrays, no metatable-heavy OOP in the hot loop
  - Flow-field pathfinding — one baked gradient from the village, O(1) per enemy (no per-enemy A*)
  - Spatial hash grid — cheap collision/separation/targeting
  - Zero allocations in the sim hot loop

## Customization (data-driven)

All tunables are plain Lua tables in `src/data/`:

| File | Contents |
|---|---|
| `checklist.lua` | Antichrist milestones: `{id, name, desc, condition(state), unlocks}` — add/remove/edit freely |
| `buildings.lua` | Cost, size, hp, crew slots, stats per building |
| `waves.lua` | Yearly horde compositions (spawn groups, edges, delays), hp scaling, `default(year)` generator, apocalypse template |
| `calendar.lua` | Month length, horde month, campaign start month |
| `enemies.lua` | hp, speed, damage, sprite color, ranged/boss knobs per enemy type |
| `villagers.lua` | Speed/hunger/build rates, pregnancy length, child growth, birth-request interval |
| `resources.lua` | Resource types, gather rates, costs |

---

## Milestones

### M1 — Core loop skeleton ✅ DONE- [x] Project scaffold: `main.lua`, fixed 60Hz timestep loop, state machine
- [x] Camera: WASD pan, wheel zoom, world clamping
- [x] Tile grid + world borders
- [x] Spatial hash (separation + tower targeting)
- [x] Enemies: pool, spawn at edges, seek village, melee the village heart
- [x] Arrow towers: placement (validity ghost), auto-target, projectiles with homing
- [x] Village heart: hp, damage, game over
- [x] Wave system: countdown, skip, scaling spawns, wave clear → next countdown
- [x] HUD: wave info, countdown, village hp bar, build button, win/lose overlays
- [x] Occult placeholder palette + pentagram village
- [x] Smoke test harness (`smoke.flag`) — verified full wave loop

**Acceptance**: countdown → swarm → towers shoot → win (3 waves) / lose (village 0 hp). ✅ Verified via smoke run.

### M2 — Performance foundation (thousands of enemies) ✅ DONE

- [x] Flow-field pathfinding baked from village (Dijkstra with binary heap + 8-dir flow vectors, no corner cutting)
- [x] Walls: buildable, block flow field, enemies path around/through breaches (walls cost 60 tiles in the field — enemies detour up to ~57 tiles to find a gap, otherwise bash the cheapest wall)
- [x] Enemy hp scaling + wall damage/breaching (`hpGrowth` per wave in `waves.lua`)
- [x] SpriteBatch rendering pipeline (runtime-generated circle sprites, one draw call for all enemies + one for projectiles)
- [x] Data-oriented enemy storage (SoA: flat number arrays, swap-remove, zero per-frame allocation in hot loop)
- [x] No per-frame allocations in hot loop (preallocated hash buckets, inlined spatial scans, module-level closures)
- [x] Stress tested: 10,000 enemies — draw ~3ms (SpriteBatch ✓), sim ~23ms/step under Rosetta LuaJIT
- [x] Debug overlay (F3: fps/counts/timings/rebakes), spawn keys (K +1k, shift+K +10k)
- [x] Sim/render decoupling review (fixed 60Hz timestep with accumulator already in place)

**Acceptance**: 10k enemies path around walls and swarm the village. Draw pipeline holds 60fps easily; sim step ~23ms at 10k under Rosetta JIT (≈40fps worst-case crush), 60fps comfortably up to ~6-7k enemies. Notes:
- The ARM64 LuaJIT interpreter limitation was the big discovery — Rosetta x86_64 JIT is 7x faster (see run instructions above).
- Separation is inlined with a 24-candidate visit cap + 6-neighbor cap; pressed (blocked) enemies skip separation with 1-frame lag.
- Enemies skip separation while attacking; towers aim with velocity prediction; projectiles do proximity hits (no entity references — swap-remove safe).

### Known M2 caveats (for later polish)

- Sim step at 10k enemies is ~23ms (JIT): potential future wins — 30Hz enemy updates with 60Hz towers/projectiles, flow-field sampling every other step, moving enemy sim to FFI/native if ever needed.
- Wave 1 balance unchanged from M1 (resource gating arrives in M3).

### M3 — Village sim: villagers, resources, staffed defenses ✅ DONE

- [x] Villager entities: 2 starting families, man/woman, needs (food), death
- [x] Resources: wood, food, stone — gatherable nodes (trees, bushes/berries, rocks)
- [x] Resource stockpile + costs on all buildings
- [x] Buildings: house, wall, arrow tower, ballista (crew slots defined in data)
- [x] Menu-based villager management:
  - click villager → job menu (Idle / Gather wood / Gather food / Gather stone / Build / Crew tower)
  - click defense → panel with crew slots → Assign / Unassign servant
- [x] Crew logistics: assigned villager walks to the tower; tower only fires once staffed
- [x] Crew deaths mid-wave → tower goes offline until re-staffed (enemies attack villagers in melee range before walls/heart)
- [x] Housing: population capped by houses (heart base 4, +2/house); idle villagers loiter near home area (no day/night sleep cycle yet)
- [x] Food consumption loop (berries → stockpile → feeding; berries regrow; starvation drains hp → death)
- [x] AoE-style camera polish: camera soft-follows a selected villager (WASD pan cancels), hover tooltips for villagers/buildings/nodes

**Acceptance**: gather → build → staff towers → survive waves where unstaffed towers do nothing. ✅ Verified headless (21 checks) + all four harnesses pass.

Implementation notes:
- New modules: `src/sim/buildings.lua` (registry: construction, hp, crew, swap-remove), `src/sim/villagers.lua` (job state machine), `src/sim/nodes.lua` (scatter + regen). Data: `buildings.lua` (costs/buildTime/crew/popCap), `villagers.lua`, `resources.lua`, `nodes.lua`.
- Towers fire only when `built && crewCount >= crew` (`src/sim/towers.lua` now iterates the Buildings registry).
- Buildings occupy their tile (`OCC_BUILD`) — block enemies and the flow field (same +60 wall cost); enemies bash them when blocked.
- Costs are deducted at placement; walls build instantly (palisade), towers/houses/ballista need a builder (Build job).
- **Known M3 caveats**: villagers walk in straight lines and pass through walls (placeholder — outbound pathing arrives later); enemies ignore villagers unless in melee range while attacking/blocked; no enemy targeting of villagers at range; sleeping is cosmetic idling.

**Known M2 caveats (partially addressed)**

- ~~Wave 1 balance unchanged from M1 (resource gating arrives in M3)~~ — M3 gates all builds behind gatherable resources.
- Fixed latent harness bug found during M3 testing: after a harness finished it nil'd its frame counter and `State.update` compared `nil <= 0` (crashed after the summary print).

### M4 — Calendar & data-driven waves ✅ DONE

- [x] Game calendar (`src/data/calendar.lua` + `src/sim/calendar.lua`): 12 months/year, ~48s/month (~10 min/year), ticks continuously through village *and* wave phases (pregnancy will depend on this in M6). Campaign opens month 9 of year 1.
- [x] Yearly hordes: the horde arrives when the year-end month (12) begins — ~11 months of building per year; clearing the horde early skips the rest of month 12.
- [x] `waves.lua` composition system: 12 authored years, each a list of spawn groups `{kind, count, edge, delay, gap, hpMul}`; `default(year)` generator escalates forever beyond the authored list.
- [x] New enemy roster: `runner` (fast/fragile), `brute` (slow/tanky, 3× wall damage), `spitter` (ranged siege — stops at range, lobs shots at nearest building/village), `behemoth` (boss: 1800 hp, 8× wall damage).
- [x] Spawn scheduling: wave start flattens groups into a time-sorted spawn-event timeline; groups from fixed/random/multi edges, timed ambush prongs mid-siege.
- [x] Wave preview UI: village-phase HUD shows next horde label, composition (counts × names), arrival edges, boss tag, and seconds-to-arrival; cached per year (no per-frame rebuild).
- [x] Boss waves: milestone years (5, 10, 12, every 5th via `default`) — combined boss health bar in HUD.
- [x] Victory placeholder: survive the year-12 horde → victory overlay (replaced by the Antichrist birth in M6).
- [x] Apocalypse mode ready: `waves.lua` `apocalypse(n)` template builds one big escalating horde per month; trigger is debug-only (`P`) until the M5 checklist wires it. In end times the calendar summons a horde at *every* month transition.
- [x] Hostile projectile pool (`src/sim/enemyShots.lua`): positional impact resolution (villager → building → wall → village heart).
- [x] Per-kind enemy sprites: runtime atlas (one SpriteBatch draw) with data-driven colors from `enemies.lua`.
- [x] Fixed latent `run.sh` issue: stale harness flags could hijack the next run — flags are now removed after every run (matches the documented behavior).

**Acceptance**: 10+ distinct escalating waves defined purely in data. ✅ 12 authored years + default generator; verified via smoke/stress/stress2/test (all pass; 10k stress: draw ~3ms, step ~15-17ms).

Implementation notes:
- `Waves.preview()` is the single wave-definition resolver shared by startWave and the HUD (apocalypse-aware).
- Spitters only besiege when within `range` of the village heart; if blocked outside it they melee as usual. They never target villagers at range (shots land positionally, so a passing villager can be clipped).
- Calendar never pauses (horde chaining if a wave outlasts the year); `hordeDue` is consumed by Waves only when idle, so overdue hordes fire back-to-back.
- **Known M4 caveats**: no enemy type targets villagers at range; boss bar is a combined bar across all alive bosses; apocalypse win/lose integration lands in M5/M6.

### M5 — The Antichrist checklist ✅ DONE

- [x] Checklist engine (`src/sim/checklist.lua` + `src/data/checklist.lua`): ordered chain, `requires`, `condition(S)`, optional `progress(S)`, unlocks. An entry stays hidden until its prerequisites complete (AoE-style reveal).
- [x] Nine customs completable with current systems (couple milestone deferred to M6, added as pure data then):
  - Prove the flock (survive year 1) → unlocks **Ballista**
  - The flock grows (8 servants) → unlocks the **Altar** (mid-game)
  - Raise the Altar → unlocks **Dark Rituals**
  - First blood (10 deaths) → The harvest burns (50 food) → Blood for the soil (3 altar sacrifices)
  - The horde is sated (year 5) → The fields run red (50 deaths) → The stars are right (year 6)
- [x] Completing the chain flips `calendar.apocalypse` — monthly end-times hordes. Surviving 9 of them is the placeholder win ("THE ANTICHRIST IS BORN") until M6 wires conception/birth.
- [x] Altar building + ritual panel: burn the harvest (instant), sacrifice a servant (they walk to the altar and die there).
- [x] Unlock gating: `buildings.lua` `unlock = milestone id`; locked buttons, ghost, and placement all respect it.
- [x] HUD: "THE CUSTOM" panel (toggle `C`), completion toasts, death counter (`Villagers.deaths`), `Waves.hordesSurvived`.

**Acceptance**: add/remove/reorder checklist entries purely by editing `checklist.lua`. ✅

Implementation notes:
- Sacrifices only count if the servant reaches the altar alive. Dying on the way still increments `Villagers.deaths` but not the ritual counter.
- `P` still force-toggles end times (debug). The real trigger is the last custom.
- **Known M5 caveats**: year-12 victory remains as a fallback if the checklist is never finished; checklist panel and debug overlay stack on the right. (Couples/births landed in M6.)

### M6 — Couples, births, and the Antichrist ending ✅ DONE

- [x] House panel: **Bind a couple** (nearest free adult man + woman), **Choose as vessel**, **Unbind**. Couples dissolve if their house is destroyed or a partner dies.
- [x] Approval loop: bound couples periodically ask permission for a child → centered **Allow / Deny** popup; denying resets the timer.
- [x] Children: born as small pale `child` villagers, count toward the cap, cannot work/crew/sacrifice; grow into adult workers after a year. Births stall if the village is at population cap.
- [x] Pregnancy lasts 9 continuous in-game months (`vData.pregnancyMonths`); the calendar keeps ticking through village *and* wave phases via a month `epoch` counter.
- [x] Chosen couple ritual: clicking **Conceive the Antichrist** at the Altar (available once the checklist is complete) sends both partners to the altar; on arrival the **end times begin** — one apocalypse horde per month.
- [x] Victory = the vessel gives birth 9 months later ("THE ANTICHRIST IS BORN"). The old 9-horde placeholder win is gone; a year-12 fallback win remains if the ritual is never attempted.
- [x] Lose states: village destroyed, bloodline extinct (`Villagers.count() == 0`), the vessel lost mid-pregnancy, or no adult of one sex left to continue the line (`no_vessel`).
- [x] New checklist bookends: **The first union** (bind a couple) at the start and **The vessel quickens** (conceive) as the finale; chain completion no longer triggers the end times by itself.
- [x] `--life` headless harness verifies the whole couple→conception→birth path.

**Acceptance**: full game loop from 2 families to the Antichrist birth. ✅ (`--life`: `mode=victory ending=birth conceived=true`)

Implementation notes:
- `src/sim/villagers.lua` owns couples, births, growth, and conception; `Calendar.epoch` drives month ticks for pregnancies/growth (survives `Space` skips).
- The Altar's conceive ritual walks both partners to the altar (job `conceive`); losing a partner mid-walk just cancels the rite.
- **Known M6 caveats**: couples are pair-picked automatically (no manual pairing UI); the chosen vessel is a single global flag; no pregnancy visuals beyond house-panel status text.

### M7 — Juice & art direction ✅ DONE

#### M7a — Game feel / FX ✅ DONE

- [x] `src/fx/particles.lua`: data-oriented SoA pool, hard cap 2,600, one color-atlas `SpriteBatch` (one draw call). Emitters: blood, dust/debris, trails, muzzle flashes, flame, ritual burst, death decals.
- [x] Hooks: enemy hit/death + village melee, villager hit/death (with a fading blood decal), tower muzzle flashes, spitter trails + impacts, building place/complete/destroy dust, wall breach dust, altar burn/sacrifice flames, conception burst.
- [x] `Camera.shake(amount, duration)` (strongest-impulse, decaying) applied in `Camera.apply`; triggers on horde/boss start, destruction, and village damage.
- [x] Screen flash: `State.flash` red vignette on village damage; decays over `State.update`.
- [x] Altar candle flicker; particle count in the debug overlay (F3).
- [x] Budget-gated emitters: mass deaths at 10k enemies cannot flood the pool.

**Acceptance**: all harnesses green; `--stress` (10k) unchanged at ~60fps (step ~11ms, draw ~2ms).

#### M7b — Audio ✅ DONE

- [x] `src/audio/sfxgen.lua`: procedural `SoundData` — one oscillator with pitch sweeps, percussive/swell envelopes, noise, vibrato. 13 SFX: click, place, build_done, error, shoot, ballista, hit, squelch, horn, ritual, sacrifice, conceive, birth.
- [x] `src/audio/audio.lua`: manager (`play`, `setVolumes`, `startMusic`, `setEnabled`). Prefers real files in `assets/sfx/<name>.<ext>` / `assets/music/theme.<ext>`, else the generated sound. Per-SFX interval throttle + clone-pool polyphony caps + active-source budget. Fully `pcall`-guarded (auto-mutes with no device).
- [x] Hooks: build place/complete/error, UI click, tower/ballista shots, enemy hit/death, villager hit/death, sacrifice, horde/boss horn, harvest burn, conception, birth.
- [x] Harness runs auto-disable audio (`State.reset` detects a flag) so headless runs stay silent and fast.
- [x] `assets/sfx/` + `assets/music/` created for drop-in real files (music is a no-op until you add `assets/music/theme.ogg`).

**Acceptance**: `sfxgen` builds all 13 sounds and `Audio.load` enables the mixer (verified via a headless audio check: `build ok: 13`, `audio enabled: true`); all game harnesses green with audio muted.

#### M7c — Menu / pause / settings ✅ DONE

- [x] `src/ui/menu.lua`: main menu (New Cult / Settings / Quit), pause overlay (Resume / Settings / Restart / Main Menu), settings screen. Shared layout drives both drawing and click hit-testing.
- [x] `State.mode = "menu"` boots the game to the title; the sim is skipped while in the menu or paused.
- [x] `Escape` now opens the pause overlay (it no longer quits); from the menu `Escape` quits. Building/selection still cancel first, then pause.
- [x] `src/core/settings.lua`: hand-rolled `settings.cfg` in the LÖVE save dir — master/sfx/music volume, screen-shake toggle, fullscreen. Live-applied and saved on change.
- [x] Screen shake is now behind the setting (`Camera.setShakeEnabled`).
- [x] New `--menu` harness boots to the title, opens settings mid-run, closes them, and quits.

**Acceptance**: `--menu` runs clean; all game harnesses bypass the menu and stay green.

#### M7d — Procedural art direction ✅ DONE

- [x] Enemies: per-kind atlas sprites with distinct features — horns (grunt/brute/behemoth), glowing eyes, fangs (brute/behemoth), a cyclops eye (spitter), rim outline and specular shine. Still one batched draw call.
- [x] Villagers: hooded robed figures with a face, glowing eyes, sex/child tinting, and a cheap `sin` walk bob; ground shadows.
- [x] Buildings: houses with shingle roofs, doors and flickering lit windows; crenellated stone towers with windows; a wooden ballista mount + bolt; the altar keeps its pentagram plus flickering candles; scaffolding cross-braces while under construction.
- [x] Terrain: checker tiles now dotted with deterministic grass tufts (no per-frame allocation); walls are beveled stone courses with a top highlight; the village heart pulses.
- [x] Nodes: layered tree canopies, shadowed bushes with berries, faceted rocks — all with soft shadows.
- [x] New `--shot` harness captures `shot.png` (game) and `--menu` captures title/settings PNGs to the LÖVE save dir for visual review.

**Acceptance**: screenshots reviewed (title, settings, in-game combat); all harnesses green; `--stress` draw ~2ms, still 60fps.

#### M7e — Save / load ✅ DONE

- [x] `src/core/save.lua`: hand-rolled recursive serializer/parser for numbers/strings/booleans/nested tables — no dependency, no code execution. Reads/writes `save.dat` in the LÖVE save dir.
- [x] `src/core/persistence.lua`: `snapshot`/`restore` of primitives only (calendar, stock, village, camera, buildings, walls, nodes, villagers, couples, checklist ids + counters, wave phase/timeline), all references by id/index. Restore replays onto a fresh `reset()` world and rebakes the flow field.
- [x] New `load` functions: `Buildings.load`, `Walls.load`, `Villagers.load` (rebuilds couples/marriage), `Checklist.load` (done ids + counters).
- [x] Saves allowed in the **village phase** only; autosave at each new year + manual **Save** in the pause menu; main-menu **Continue** appears when `save.dat` exists.
- [x] New `--save` harness: builds a scene, saves, wipes it, loads, and asserts the state matches.

**Acceptance**: `--save` round-trips exactly (`match=true`); all other harnesses green; menu shows Continue when a save exists.

---

## Current State

- **Done**: M1–M7. The plan is complete: full loop to the Antichrist birth, plus particles/shake/flash, procedural SFX, menu/pause/settings, a procedural art pass, and save/load.
- **Next up**: nothing scheduled. Future polish: a balance pass, drop in real art/audio under `assets/`, and playtest-tune `monthLength`/wave scaling.
- Test commands: `./run.sh --smoke`, `./run.sh --stress`, `./run.sh --stress2`, `./run.sh --test`, `./run.sh --life`, `./run.sh --menu`, `./run.sh --shot`, `./run.sh --save` (flag files are gitignored and removed after each run).
- Title screen on boot (Continue / New Cult / Settings / Quit); `settings.cfg` and `save.dat` live in the LÖVE save dir.

## Controls (M7c)

| Input | Action |
|---|---|
| `1` / `2` / `3` / `4` / `5` | Build wall / arrow tower / ballista / house / altar |
| `B` | Toggle build mode (current type) |
| Left click villager | Select → job menu (Idle / Wood / Food / Stone / Build); camera follows |
| Left click defense | Select → crew panel (Assign / Unassign servant) |
| Left click house | Bind a couple / Choose as vessel / Unbind |
| Left click altar | Ritual panel (Burn harvest / Sacrifice / Conceive the Antichrist) |
| Birth prompt | Allow / Deny a couple's request for a child |
| Pause overlay | Resume / Save / Settings / Restart / Main Menu |
| `C` | Toggle the checklist panel |
| Left click ground | Deselect |
| Right click | Close panel → cancel build mode |
| `Esc` | Clear selection → cancel build mode → pause overlay (from the title, `Esc` quits) |
| `Space` | Summon the horde early (village phase only) |
| WASD / arrows | Pan camera (cancels follow) |
| Mouse wheel | Zoom |
| `F3` | Debug overlay (fps, date, counts, timings) |
| `K` / `Shift+K` | Spawn 1k / 10k enemies (debug) |
| `P` | Toggle end times — apocalypse hordes every month (debug; the Altar conception does this for real) |
| `R` | Restart |
