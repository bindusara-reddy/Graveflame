# Graveflame

An original **2D action-roguelite** built with **Godot 4**, inspired by the fast, fluid combat flow of *Dead Cells* — but with entirely original, procedurally drawn art and synthesized audio (no copied or licensed assets).

> Fight through a chain of combat rooms. Chain a 3-hit melee combo, **down-slam** airborne enemies, **wall-jump** up vertical shafts, **parry** attacks and reflect projectiles, brew a **healing flask**, build a special meter, unleash a piercing shot, choose a boon between rooms, and topple a two-phase boss. Die and you lose your run — but earned **cells** persist to unlock permanent upgrades at **the Forge**.

## Play

1. Install **Godot 4.3+** (stable; tested on 4.7). The **GL Compatibility** renderer is used so it runs on any machine.
2. Open the `graveflame/` folder in the Godot Project Manager (Import → select the folder).
3. Press **F5** (or `Run`) to play.

### Headless verification (no GUI)

```bash
# Parse-check every script and run the logic tests:
godot --headless --path . --script res://tests/test_runner.gd
```

Expect `TEST_RESULT: PASS (96 checks, 0 failures)`.

## Controls

| Action | Keyboard |
|---|---|
| Move | `A`/`D` or `←`/`→` |
| Jump (double-jump in air) | `W` or `Space` |
| Attack (3-hit combo) | `J` |
| **Down-slam** (while airborne) | `J` in air |
| Special (ranged, costs meter) | `K` |
| **Parry** (timed deflect) | `S` |
| **Heal** (flask) | `F` |
| Dash (i-frames) | `Shift` or `L` |
| Pause | `Esc` |

**Wall jump** — jump while sliding down a wall to leap off it.

Controller/joypad bindings also work for movement and face buttons via Godot's default joypad mapping — add more in Project Settings → Input Map.

## Gameplay loop

```
Title → Room 1 (intro) → combat rooms 2–5 → Boss room → Victory
                 │              │
                 └─ choose 1 of 3 boons + refill flask after each non-boss room
```

- Clear all enemies in a room → pick an **upgrade** → advance.
- Build a **special meter** by landing hits; spend it on a piercing shot.
- **Dash** through attacks (brief invulnerability).
- **Parry** enemy melee attacks (deals damage + builds meter) and **reflect** projectiles back at the caster.
- **Down-slam** from the air for an AoE impact that knocks enemies away.
- **Healing flask** with limited charges; refills between rooms.
- Earn **cells** from kills; spend them at **the Forge** on permanent run-starting bonuses.
- The boss has two phases — it gets faster, fires more projectiles, and refuses to stagger below 50% HP.

## Enemies

| Enemy | Behavior |
|---|---|
| **Stalker** | Relentless melee chaser. |
| **Hopper** | Leaps to close distance, then strikes. |
| **Wisp** | Hovering ranged caster — keeps its distance and fires aimed shots. |
| **Brute** | Shielded heavy. **Frontal hits are absorbed by its shield** — flank it from behind. |
| **Bomber** | Kamikaze that rushes you and detonates. Kill it during the fuse to avoid the blast (it still pops, but smaller). |

## Upgrades (boons, offered between rooms)

Vitality, Swift Feet, Power, Razor Edge, Magnetism, Warden, Surge, Leech, Ember Heart, **Crater** (slam), **Riposte** (parry), **Witch Flask** (+1 charge), **Dashmaster**.

## The Forge (meta-progression)

Cells earned during runs persist after death. Spend them at the Forge (from the title screen) on permanent upgrades applied at the start of every run:

- **Ember Soul** — +10 starting HP
- **Potion Belt** — +1 starting flask charge
- **Quickened** — +8% move speed
- **Sharpened** — +10% melee damage
- **Arcane Spark** — start each run with special meter

## Accessibility

- **Reduced motion** (kills camera shake / particles).
- **Reduced flash** toggle.
- Enemy attacks telegraph with **shape, motion, and timing**, not color alone.

## Project structure

```
graveflame/
├── project.godot          # config, input map, physics layers
├── main.tscn              # minimal root scene → scripts/game.gd
├── scripts/
│   ├── game.gd            # root orchestrator (state, rooms, pause, cells, forge)
│   ├── run_model.gd       # pure seeded run/upgrade logic
│   ├── save.gd            # persistent cells / best score / meta upgrades (JSON)
│   ├── content.gd         # tuning, room templates, enemy/combo/upgrade data
│   ├── room.gd            # geometry, walls, hazards, encounter spawning
│   ├── player.gd          # platforming, combo, slam, dash, parry, wall-jump, flask
│   ├── enemy.gd           # stalker / hopper / wisp / brute / bomber AI
│   ├── boss.gd            # two-phase boss
│   ├── projectile.gd      # team-aware ranged shots (reflectable by parry)
│   ├── feedback.gd        # particles, shake, synthesized audio
│   └── ui.gd              # HUD, flask/cells/best, all panels, the Forge
└── tests/
    └── test_runner.gd     # headless logic tests (96 checks)
```

Everything is built **programmatically** (only `main.tscn` exists as a scene file), so the project is easy to read top-to-bottom and robust across Godot 4.x minor versions.

## Design notes

- `RunModel` and `Save` are pure (`RefCounted`, no `Input`/SceneTree deps) so they are unit-testable headlessly.
- Actors are `CharacterBody2D`/`Area2D` with collision layers: World, Player/Enemy Body, Player/Enemy Hurtbox, Player/Enemy Attack, Trigger.
- Art is drawn with `_draw()` (polygons, arcs, circles). Audio is generated into `AudioStreamWAV` at runtime.
- The player's slam AoE scans the `enemy_hurtbox` group; the parry reflects projectiles by flipping their `vel`/`team`/`damage` fields.
- Save data lives at `user://graveflame_save.json` (per-user app data).
- No external assets, no copyrighted material — safe to publish and extend.

## License

MIT (see `LICENSE`). The game design and all content are original.

## Acknowledgements

Inspired by the combat feel of *Dead Cells* (Motion Twin, 2018) — a roguelike-Metroidvania with fluid melee, dodge-rolls, parries, down-slams, and flask healing. Graveflame is an original tribute, not a port or copy.
