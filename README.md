# Graveflame

Graveflame is an original **2D action-roguelite vertical slice** built with **Godot 4**. It channels the speed and readability of modern roguelite platformers through its own setting, characters, combat systems, procedurally drawn visuals, and synthesized audio.

Fight through an introductory encounter, four two-wave combat rooms, and the active two-phase Ember Warden. Clear a room, approach its unsealed exit, interact to claim one of three boons, and carry your health, meter, and build deeper into the keep. Cells persist between runs and fund permanent upgrades at the Forge.

## Play

1. Install Godot **4.3 or newer** (tested with 4.7.1). The project uses the GL Compatibility renderer.
2. Import this folder by selecting `project.godot` in the Godot Project Manager.
3. Press **F5** to begin.

On a fresh checkout, run the headless editor once before direct script tests. This performs the initial import and builds Godot's global class cache:

```bash
godot --headless --editor --path . --quit
```

## Controls

Controller labels below use the standard Xbox-style Godot layout; equivalent buttons work on other supported pads.

| Action | Keyboard | Controller |
|---|---|---|
| Move | `A` / `D` or `Left` / `Right` | Left stick or D-pad |
| Jump / double-jump | `W`, `Space`, or `Up` | `A` |
| Attack / buffered 3-hit combo | `J` | `X` |
| Down-slam while falling | `J` in the air | `X` in the air |
| Cinder Lance (40 meter) | `K` | `Y` |
| Ignite Graveflame (full 100 meter) | `Q` | Right trigger |
| Dash | `Shift` or `L` | `B` |
| Timed parry | `S` | Left bumper |
| Healing flask | `F` | D-pad Down |
| Use an open exit | `E` or `Up` | D-pad Up or right bumper |
| Pause | `Esc` | Start |

Jump while sliding against a wall to wall-jump away from it.

## Combat

- **Buffered blade combo:** attack inputs are remembered for 0.18 seconds and chain cleanly through the three-hit sequence. Recovery frames can be dash-cancelled.
- **Cinder Lance:** spend 40 Graveflame meter on a fast ranged strike. The Surge boon adds piercing and damage.
- **Ignite Graveflame:** at 100 meter, press Ignite to consume the gauge and enter a five-second empowered mode. Strikes hit harder, apply burn, and the combo finisher launches a flame wave.
- **Parry and reflection:** a properly timed guard punishes active melee attacks, builds meter, and sends hostile projectiles back with increased damage.
- **Committed healing:** the flask restores 45 HP only after a 0.55-second drink. Taking a hit interrupts the heal before a charge is spent.
- **Mobility:** coyote time, jump buffering, variable jump height, double-jump, wall-slide, wall-jump, down-slam, and invulnerable dash frames keep movement responsive.

## Run flow

```text
Title -> Intro encounter -> Four two-wave rooms -> Ember Warden -> Victory
                |                    |
                +-- clear -> use exit -> choose a boon -> continue
```

- The intro teaches the core loop with a single wave; each following combat room stages two authored waves with a short breather between them.
- Clearing the final wave unseals the room exit. Travel to the portal and press Interact before the boon screen appears.
- Five enemy archetypes create distinct pressure: Stalker, Hopper, Wisp, shielded Brute, and Bomber.
- The Ember Warden actively cycles through lunge, projectile fan, and landing shockwave attacks, then becomes more relentless below half health.
- Flask charges refill between rooms. Earned cells persist and buy five permanent run-starting upgrades at the Forge.

## Boons and progression

Rooms offer three choices from a 13-boon pool covering health, speed, melee power, combo finishers, meter gain, invulnerability, lance piercing, lifesteal, slam, parry, flask capacity, and dash recovery.

The Forge spends persistent cells on Ember Soul, Potion Belt, Quickened, Sharpened, and Arcane Spark. Save data is stored at `user://graveflame_save.json`.

## Presentation and accessibility

- Responsive, anchored HUD with clear health, meter, flask, score, cell, room, boss, and room-clear states.
- Atmospheric title, pause, boon, defeat, victory, and scrollable Forge screens with visible keyboard/controller focus.
- Procedurally drawn actors and environments, impact effects, hit-stop, camera shake, afterimages, and original runtime-generated audio.
- Reduced-motion and reduced-flash options; attack tells use timing, shape, and motion rather than color alone.

## Validation

Run these commands from the repository root in order:

```bash
# Required once on a fresh checkout: imports resources and builds class caches.
godot --headless --editor --path . --quit

# Seeded model, content, save, and script-loading checks.
godot --headless --path . --script res://tests/test_runner.gd

# Scene-tree gameplay smoke checks.
godot --headless --path . --script res://tests/runtime_smoke.gd

# Short main-scene boot smoke.
godot --headless --path . --quit-after 180
```

Expected results are `TEST_RESULT: PASS (96 checks, 0 failures)` and `RUNTIME_SMOKE_RESULT: PASS (176 checks, 0 failures)`. Both test scripts exit nonzero on failure.

## Project map

```text
project.godot          Input map, renderer, physics layers
main.tscn              Minimal root scene
scripts/game.gd        Run lifecycle, rooms, feedback, pause, progression
scripts/player.gd      Movement, combo, slam, dash, parry, flask, Graveflame
scripts/enemy.gd       Five enemy state machines and status effects
scripts/boss.gd        Active two-phase Ember Warden
scripts/room.gd        Geometry, waves, hazards, exits, encounter flow
scripts/content.gd     Tuning, rooms, encounters, boons, meta upgrades
scripts/run_model.gd   Pure seeded route and build model
scripts/projectile.gd  Team-aware, reflectable projectiles
scripts/feedback.gd    Particles, hit-stop, shake, generated audio
scripts/ui.gd          Responsive HUD and all menus
scripts/save.gd        JSON persistence
tests/                 Unit and runtime smoke checks
```

Most runtime content is built programmatically; `RunModel` and `Save` remain pure `RefCounted` classes for headless testing.

## Original-IP notice

Graveflame is an independent, original work. It is inspired by the combat feel and run structure of games such as *Dead Cells*, but it is **not a port, remake, or fan game**, and it is not affiliated with or endorsed by Motion Twin or Evil Empire. It uses no *Dead Cells* code, art, audio, characters, story, names, levels, or other proprietary assets. All Graveflame-specific content is original to this project.

## License

MIT. See [LICENSE](LICENSE).
