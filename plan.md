# antic — Game Plan

A 2D top-down village builder / tower defense with a dark twist: you are the leader of a cute satanist cult (Cult of the Lamb vibes). Grow your village, survive escalating hordes of thousands of enemies, and secretly complete the dark checklist that will make the Antichrist come to earth. You win when the chosen couple births the baby.

## Core Loop

1. **Village phase** — gather resources (wood, food, stone), build houses/walls/towers, assign villagers to jobs, manage couples, complete checklist objectives. Countdown ticks down to the next wave.
2. **Wave phase** — hordes attack from the map edges toward the village. Only **staffed** defenses fire. Crew can die mid-wave, taking their tower offline.
3. Repeat. Waves scale toward thousands of enemies. Checklist progress unlocks the path to the final ritual.

**Win condition**: complete the customizable Antichrist checklist — the final step is the chosen couple birthing the Antichrist.

**Central tension**: villagers are the scarcest resource. Every villager gathering wood is one not crewing a ballista. Growth (approved births) fuels both defense and the dark checklist.

---

## Stack & Tooling

- **Engine**: LÖVE2D + Lua (installed at `/Applications/love.app`)
- **Run**:
  ```
  ./run.sh
  ```
  LÖVE 11.5's native arm64 build runs LuaJIT in **interpreter-only mode** (no JIT). `run.sh` forces the x86_64 slice via Rosetta, which enables the full LuaJIT JIT — measured ~7x faster hot loops (100M loop iterations: 0.16s vs 1.13s). This is required for thousands of enemies at 60fps; falls back to native mode if Rosetta is unavailable.
- **Headless test harnesses** (flag files, auto-deleted after run):
  - `./run.sh --smoke` — 43s self-playing run: skips first countdown, places 2 towers, plays wave 1, prints summary, quits.
  - `./run.sh --stress` — 10,000-enemy stress test: wall ring + 4 towers + full swarm, prints step/draw timings.
  - `./run.sh --stress2` — 2,000-enemy combat validation (no walls).
  - `./run.sh --test` — deterministic 12-enemy combat trace.
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
| `waves.lua` | Wave composition, scaling formula, countdowns |
| `enemies.lua` | hp, speed, damage, sprite per enemy type |
| `villagers.lua` | Job definitions, growth timers, birth request rules |
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

### M3 — Village sim: villagers, resources, staffed defenses

- [ ] Villager entities: 2 starting families, man/woman, needs (food), death
- [ ] Resources: wood, food, stone — gatherable nodes (trees, bushes/berries, rocks)
- [ ] Resource stockpile + costs on all buildings
- [ ] Buildings: house, wall, arrow tower, ballista (crew slots defined in data)
- [ ] Menu-based villager management:
  - click villager → job menu (Idle / Gather wood / Gather food / Gather stone / Build / Crew tower)
  - click defense → panel with crew slots → Assign / Unassign servant
- [ ] Crew logistics: assigned villager walks to the tower; tower only fires once staffed
- [ ] Crew deaths mid-wave → tower goes offline until re-staffed
- [ ] Housing: population capped by houses; villagers sleep at home
- [ ] Food consumption loop (farms/berries → stockpile → feeding)
- [ ] AoE-style camera polish: follow selection, hover tooltips

**Acceptance**: gather → build → staff towers → survive waves where unstaffed towers do nothing.

### M4 — Data-driven waves

- [ ] `waves.lua` composition system: mixed enemy types, per-wave budgets
- [ ] Scaling formula (count, speed, hp, new types over time)
- [ ] Spawn scheduling (groups, directions, ambushes)
- [ ] Wave preview UI (what's coming next)
- [ ] Boss/elite enemies at milestone waves

**Acceptance**: 10+ distinct, escalating waves defined purely in data.

### M5 — The Antichrist checklist

- [ ] `checklist.lua` engine: ordered milestones, `condition(state)`, unlocks, UI panel showing progress
- [ ] First dark milestones interlocking with gameplay, e.g.:
  - "Form the first couple" → unlocks Altar
  - "Population reaches 10 servants" → unlocks Ritual Site
  - "Let 50 villagers die" (the horde must taste blood)
  - "Sacrifice the harvest" (burn food at the Altar)
  - "Survive wave N with fewer than X villagers" (cruel constraints)
- [ ] Altar building + ritual interactions (spend resources/villagers)
- [ ] Unlock chain gating buildings/abilities
- [ ] Tension design: checklist rewards weaken defense or vice versa

**Acceptance**: add/remove/reorder checklist entries purely by editing `checklist.lua`.

### M6 — Couples, births, and the Antichrist ending

- [ ] Assign man + woman to a house → couple
- [ ] Servant approval loop: couple asks permission for a child → Allow / Deny popup
- [ ] Children: grow into workers over time
- [ ] "Chosen couple" designation (mark a couple as the vessel)
- [ ] Final checklist step: ritual → the chosen couple births the Antichrist → **win screen**
- [ ] Lose states: village destroyed, or all villagers dead (no couple left = ritual impossible)
- [ ] Multiple endings hook (fail states + victory)

**Acceptance**: full game loop from 2 families to the Antichrist birth.

### M7 — Juice & art direction (stretch)

- [ ] Cute-occult art pass: characters, buildings, enemies, terrain (replace placeholders)
- [ ] Particles: blood, ritual effects, building dust, projectile trails
- [ ] Sound: sfx (build, shoot, death, ritual) + dark-cute music loop
- [ ] Screen shake, hit flashes, death animations
- [ ] Main menu, pause, settings
- [ ] Save/load (serialize state, likely `bitser`)

---

## Current State

- **Done**: M1 (core loop) + M2 (perf foundation: flow fields, walls, SoA enemies, SpriteBatch, stress harness).
- **Next up**: M3 — villagers, resources, menu-based job/crew assignment, staffed defenses.
- Test commands: `./run.sh --smoke`, `./run.sh --stress`, `./run.sh --stress2`, `./run.sh --test` (flag files are gitignored).

## Controls (M2)

| Input | Action |
|---|---|
| `1` / `2` | Build wall / build arrow tower |
| `B` | Toggle build mode (current type) |
| Left click | Place building / UI buttons |
| Right click / `Esc` | Cancel build mode (Esc quits if not building) |
| `Space` | Skip countdown |
| WASD / arrows | Pan camera |
| Mouse wheel | Zoom |
| `F3` | Debug overlay |
| `K` / `Shift+K` | Spawn 1k / 10k enemies (debug) |
| `R` | Restart |
