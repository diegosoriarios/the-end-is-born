## What’s missing

> **Plan 1 status:** the shippability pass is implemented. The starting population now fits the Heart cap, help and destructive-action confirmations are in place, saves use a fallback backup with validation and visible errors, buildings can be repaired, moved, demolished, or cancelled for a refund, and the roster/idle count is available in-game.

The core loop is playable and stable, but it is still a polished prototype rather than a finished game. The remaining gaps fall into the later buckets.

### 1. First-run and UX correctness — highest priority

- **Starting population now fits the cap.** The Heart starts at `popCap=6`, matching the 3 starting families (6 servants).
- **Help is in-game.** Press `H`, use **How to Play** on the title, or **Help** in the pause menu. The overlay covers core controls and first steps.
- **Destructive actions now confirm.** `New Cult`, `Restart`, `Main Menu`, `Quit`, `R`, and quitting from the title prompt before discarding progress.
- **No minimap, edge pan, or camera reset.** The world is 64×64 tiles, but navigation is only WASD/arrow keys and zoom (`src/core/camera.lua`).
- **No accessibility or input options:** no key rebinding, gamepad support, UI scaling, minimum window size, colorblind options, or focus-loss pause.

### 2. Save safety and lifecycle

- **Corrupt saves now fail visibly.** `Continue` reports an unreadable save, and valid `save.bak` data is loaded automatically with an in-game notice.
- **One save slot remains, but writes keep a backup.** `save.dat` is backed up to `save.bak` before replacement, and restore validates the snapshot shape. There is still no delete/restore UI.
- **No post-victory or post-defeat flow.** Victory/game-over shows an ending message and `Restart` only (`src/ui/ui.lua:790`); there is no stats summary or “continue playing” option.
- **No end-game statistics screen.** Kills, deaths, years survived, births, and sacrifices are tracked internally but not presented as a result screen.

### 3. Build and villager management

- **Build management is in place.** Selected buildings can be repaired, moved, demolished for a partial refund, or cancelled during construction for a full refund.
- **Walls have no gates.** Enclosing the village can trap your own villagers, since walls are fully solid (`src/sim/walls.lua`).
- **Basic roster added.** `Tab` opens a clickable servant list, and the HUD shows an idle count. There is still no bulk assignment.
- **Construction can be cancelled.** There is still no multi-building queue.
- **Limited tower control.** No per-tower targeting mode or tower upgrades beyond building placement.

### 4. Content depth and long-term play

- **Thin content roster:** 5 enemy kinds, 8 buildable buildings, 6 research projects, 5 ages, 4 resources, and 11 checklist entries. Most ages are resource/sacrifice gates rather than new mechanics.
- **Enemy variety is limited:** all enemies are ground melee/ranged; there are no healers, summoners, flyers, sappers, or siege units.
- **No building/research branching:** research is a flat list of passive projects; the only building upgrade is School → University.
- **Villagers lack depth:** no names, traits, needs, morale, equipment, family tree, education, or meaningful childhood behavior.
- **Rituals are narrow:** burn, sacrifice, conceive, and the final birth; the Antichrist exists only as victory text.
- **No difficulty, sandbox, endless, challenge, or seed modes;** the only fallback is the year-12 victory.
- **Wood and stone are finite;** trees/rocks have `regen = 0` (`src/data/nodes.lua`), while food and farms renew. Long games can exhaust construction resources.

### 5. Presentation, release, and technical risks

- **No music.** `assets/music/` is empty, so `Audio` has no track; the Music volume slider controls nothing (`src/audio/audio.lua:57`).
- **Audio is procedural placeholder SFX;** there are no authored sound assets.
- **Art is procedural placeholder geometry.** If that is the intended final style, this is not a gap; otherwise production art is missing.
- **No README, packaging, CI, or lint/format configuration.** `plan.md` is the only documentation.
- **Known performance uncertainty:** the full `--stress` 10k-enemy run previously exceeded 300 seconds (`exit=124`) with `stepMs` around `7–8`; it is not yet isolated as a harness-duration issue or a real regression.

### Recommended order

1. **Shippability pass (done):** starting population, help, confirmations, save backups/validation, build repair/refund/move/cancel, and roster.
2. **Content pass:** expand enemies, buildings, research, rituals, and progression; add difficulty/endless and post-victory play.
3. **Presentation/release pass:** music, art, accessibility, README, packaging, and CI.
4. **Performance pass:** isolate the 10k-enemy stress timeout.

Plan 1 is implemented. The next available bucket is **content**, **presentation/release**, or **performance**.
