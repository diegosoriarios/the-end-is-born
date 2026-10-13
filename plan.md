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

## Post-M7 fixes & design pass

- **Enemy visibility** — the M7d per-kind sprites read as transparent/hollow at gameplay scale (the dark eye/fang features dominated). Reverted to **solid opaque disc sprites** per kind (rim + color + highlight, no face), keeping the per-kind atlas + single `SpriteBatch`.
- **Hunger removed** — deleted the per-villager hunger/eat/starve system (`data/villagers.lua`, sim update, save snapshot, HUD bar/tooltip). The villager selection panel now shows a compact `hp N/M` line instead of the hunger bar (which also fixed the bar overlapping the **Build** job button).
- **Food sink: births cost food** — `data/villagers.lua` `birthCost = 15`. Couples only request a child when `count < cap` **and** food ≥ cost; `Villagers.allowBirth(S)` deducts the food; the birth modal shows the cost and disables **Allow** when unaffordable. (More food-costing options to be added later.)
- **Central horde clock** — top-center `HORDE IN mm:ss` (turns red under 30s) with a `[Space]` hint during the village phase; red `UNDER ATTACK — enemies N` during a wave. The old dim top-left countdown was removed; the boss bar moved down clear of it.
- **Vessel is now an end-game choice** — the house panel only offers **Choose as vessel / Unchoose vessel** once `Checklist.isDone("stars_right")` (survive the year-6 horde), and you can freely unchoose until conception starts. `Villagers.unchoose` added; `choose` refuses once conceiving/conceived.
- **Crash fix** — `drawButton` now guards `if b.label` so label-less panel-background buttons (any selection panel) no longer crash on `getWidth(nil)`.

## Content framework (Phase 0) ✅ DONE

Making new **buildings** and **upgrades** data-driven so the ages/research can be added almost entirely in data.

- [x] **Building registry** (`data/buildings.lua`) now carries framework metadata: `name`, `role` (behavior tag: `heart|wall|tower|house|altar|farm|research|graveyard`), `render` (drawer key), `category`, `order`, plus gates (`unlock` milestone, `age` later).
- [x] **Auto build bar** — generated from `Buildings.buildOrder()` (data, sorted by `order`); numbers `1-9` auto-map; wraps if the list grows. No more hard-coded buttons/keys (`ui.lua`, `main.lua`).
- [x] **Render dispatch** (`render.lua`) — `RENDERERS[render]` keyed by data, with a **generic fallback** so any new building is visible before custom art.
- [x] **Role-based behavior** — towers by `role == "tower"`; `popCap` sums any built building's `popCap`; `Buildings.hasRole(role)` helper. New buildings of an existing role are data-only.
- [x] **Modifier channels** (`src/sim/stats.lua`) — additive bonuses (`towerDamage, towerRate, wallHp, gatherSpeed, buildSpeed, …`); sim reads `Stats.value(channel)`. Towers/walls/gather are wired (no-op until research exists).
- [x] **In-place building upgrades** — data `upgradeTo = { kind, cost }` + `Buildings.upgrade(i, kind)` (swaps kind, resets to unbuilt so a builder finishes it, keeps position/crew) → this is School → University.
- [x] **Content-sanity harness** (`--content`) — asserts every building resolves a name/role/render/order and valid `upgradeTo`; prints the build order.

## Ages roadmap

- **Phase 1 — Ages ✅ DONE.** `data/ages.lua` (Whispers → Blood → Bones → Chosen → End) + `sim/ages.lua`. Customs are tagged with an `age` (their objectives). Click the **village heart** → **Ascend**: pay the age's resources + a servant who **walks to the heart and dies**; the age advances with a banner/particles and unlocks land. HUD shows the age; the customs panel is retitled per age with a "Next/Ascend" footer; **buildings gate by `age`** (`Ages.unlocked`, `Ages.lockLabel`); the vessel choice + conception are gated on **reaching Age V**. Saved in the snapshot.
- **Phase 2 — Research ✅ DONE.** `data/research.lua` + `sim/research.lua`. Research buildings: **School** (Age Blood, 2 researcher slots, tier 1) → **upgraded in place to University** (Age Bones, 4 slots, tier 3). **Timed, worker-driven**: assign servants as researchers (slots); they walk there and add progress (`progress = Σ researcher rate`, so N finish in time/N); cost paid at project start. Catalog: `sharp_bolts`, `swords`, `shields` (Blood) · `cursed_foundations`, `swift_hands` (Bones) · `bloody_rites` (Chosen). Effects feed `Stats` channels; **swords** give servants a melee strike, **shields** reduce damage taken. Panel = project list + progress bar + researcher Assign/Unassign + Upgrade. Saved (purchased ids + per-building project/progress; researcher counts rebuilt on load).
- **Phase 3 — Farm ✅ DONE.** `farm` building (Age Blood, `role="farm"`, cost 25 wood). On construction completion it registers a **high-yield renewable food node** at its tile (`Nodes.add` — amount 40, regen 0.15, vs berries 15/0.04); villagers gather it like any food node. If the farm is destroyed, its node is removed (`Nodes.removeAt` via the building remove hook). New `Buildings.emitBuilt` hook drives the role effect; `Render.nodes` ignores farm nodes (the building draws the field). Saved via the node + building snapshots.
- **Phase 4 — Graveyard / bones / necromancy ✅ DONE.** New **bones** resource. **Graveyard** building (Age Bones, `role="graveyard"`): every real servant death (when a graveyard is built) adds **+5 bones** to the stockpile and increments the graveyard's grave count. Its panel raises the dead — **Raise undead (20 bones)** spawns an `undead` villager (sickly-green tint) that works any job but can't couple and doesn't count toward the housing/birth cap. Undead deaths don't count toward the death customs (no cheese). Bones shown in the HUD; saved via stock + villager `undead` flags.

## Combat & family pass ✅ DONE

- **Time freezes under attack.** `Waves:update` only advances the calendar in the village phase — during a horde, months/pregnancy/child-growth/the year all pause until it's cleared.
- **Mobilize on attack.** `Villagers.mobilize()` (at wave start) saves each servant's job, **fills empty tower slots** (manual crew kept), and sends the surplus to **shelter** at their house (or the heart if unpaired); `demobilize()` (on clear) restores everyone's saved job. Undead mobilize too; servants mid-sacrifice/conception are left alone.
- **Heal the heart by sacrifice.** The heart sacrifice walk takes a purpose (`ascend`|`heal`). The heart panel gains **Heal (+40) — sacrifice** (repeatable, when hp < max): a servant walks to the heart and dies, restoring 40 hp.
- **Manual, food-gated birth + confinement.** The random birth popup is gone — the house panel has **Make a child (15 food)** (needs food + pop cap headroom). The mother works normally for the **first half** of the pregnancy; in the second half she's **confined** — drops her job, un-assigns from any tower/research slot, and stays home until the birth (released if the house is lost). Saved via the villager `confined` flag.
- New `--war` harness verifies all three: `mobilize=true heal=true confine=true`.

## UI redesign — top status bar + bottom command bar ✅ DONE

Reorganized the whole HUD into two fixed zones (all in `src/ui/ui.lua`; `menu.lua` untouched):

- **Top status bar** (`TOP_H = 100`, read-only): age/date (left) · heart hp bar (left) · resources incl. Bones (right) · the horde clock / `UNDER ATTACK` (centre) · next-horde preview (centre, under the clock) · boss bar just below. The objectives panel stays a floating top-right panel (`C`); toasts appear under the bar.
- **Bottom command bar** (`BOTTOM_H = 138`): **BUILD** on the left — category tabs (**Defense / Economy / Ritual / Research**, from each building's `category`) + a wrapped palette for the active category (name, cost, hotkey, age lock); **ACTIONS** on the right — a title line for the current selection and its buttons (servant jobs; tower crew; house; altar; research + researchers + upgrade; graveyard; heart), laid out in a wrapping grid. Global buttons: **Custom [C]** and **Debug [F3]**.
- Removed the scattered old UI: the bottom-left build bar, the floating bottom-right selection panel, and the bottom-centre hint lines. Number keys `1-9` now map to the **active category's** buildings. Hover tooltips unchanged.
- New data helpers: `Buildings.categories()`, `Buildings.buildIn(category)`; `State.buildCategory` (default `defense`).

**Acceptance**: `--shot` screenshot reviewed (top bar, command bar, actions, resources incl. Bones); all harnesses green.

## Interaction & palette pass ✅ DONE

- **Right-click to assign the selected villager** — with a servant selected, right-click a **resource node** to gather it (`tree→wood`, `berry/farm→food`, `rock→stone`), or a **building** to smart-assign (tower→crew, School/University→researcher, Farm→gather its food, under-construction→build; house/altar/graveyard do nothing). The selection is kept so you can chain assignments; right-click empty ground deselects (build-mode right-click still cancels). `State.assignTo` + `Villagers.assignNode/assignBuild/assignCrewTo/assignResearcherTo`.
- **Selected villager builds a placed building** — place a non-wall building with a servant selected and they're sent to construct it (`buildTarget` set in `State.tryPlace`). Walls stay instant.
- **Hide locked build content** — the palette shows only **unlocked** (age-reached) buildings; a **category tab is hidden** until it has at least one unlocked building; the active category falls back to the first available. Number keys map to the **unlocked** items of the active category. Unaffordable items remain visible but greyed.
- New `--assign` harness: `node=true tower=true school=true build=true`.

## Current State

- **Done**: M1–M7, the post-M7 fixes, the content framework (Phase 0), and Ages (Phase 1). Full loop to the Antichrist birth, plus juice, audio, menu/save, a data-driven content framework, and a 5-tier Age progression.
- **Next up**: the planned ages/content roadmap is complete. Future polish: balance pass, real art/audio under `assets/`, more food/bone-costing content, more research/ages, tune `monthLength`/wave scaling.
- Test commands: `./run.sh --smoke`, `./run.sh --stress`, `./run.sh --stress2`, `./run.sh --test`, `./run.sh --life`, `./run.sh --menu`, `./run.sh --shot`, `./run.sh --save`, `./run.sh --content`, `./run.sh --ages`, `./run.sh --research`, `./run.sh --farm`, `./run.sh --grave`, `./run.sh --war`, `./run.sh --assign` (flag files are gitignored and removed after each run).
- Title screen on boot (Continue / New Cult / Settings / Quit); `settings.cfg` and `save.dat` live in the LÖVE save dir.

## Controls (M7c)

| Input | Action |
|---|---|
| `1`–`9` | Build the N-th **unlocked** building of the active build category (bottom-bar tabs; locked items/categories are hidden) |
| Right-click (servant selected) | Assign the servant to the clicked resource node (gather) or building (crew/research/build/farm) |
| Bottom-bar buttons | Category tabs · build palette · contextual ACTIONS for the current selection · Custom [C] · Debug [F3] |
| `B` | Toggle build mode (current type) |
| Left click villager | Select → job menu (Idle / Wood / Food / Stone / Build); camera follows |
| Left click defense | Select → crew panel (Assign / Unassign servant) |
| Left click village heart | Ascension panel — Ascend to the next age (cost + a servant sacrifice) |
| Left click School/University | Research panel — pick a project, Assign/Unassign researchers, Upgrade |
| Left click Graveyard | Necromancy panel — Raise undead (costs bones) |
| Left click house | Bind a couple / **Make a child (15 food)** / Unbind (Choose·Unchoose vessel only at the end game) |
| Left click altar | Ritual panel (Burn harvest / Sacrifice / Conceive the Antichrist) |
| Heart panel (second row) | **Heal the Heart** — sacrifice a servant for +40 hp |
| Birth prompt | Allow (costs food) / Deny a couple's request for a child |
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
