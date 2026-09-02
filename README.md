# Graveflame

A dark 2D action-roguelite built with Godot 4. Descend through eight chambers of a ruined keep, chain kills, pick synergy boons, and put down the Ember Warden.

![Graveflame title screen](docs/screenshots/title.png)

<p align="center">
  <img src="docs/screenshots/combat.png" alt="Graveflame combat with floating damage numbers" width="49%">
  <img src="docs/screenshots/ember-warden.png" alt="Ember Warden phase two, wisps summoned" width="49%">
</p>

## Play

1. Install Godot 4.3 or newer.
2. Open `project.godot` in Godot.
3. Press **F5**.

## Controls

`A/D` move · `W/Space` jump · `J` attack · `K` lance · `Q` ignite · `Shift/L` dash · `S` parry · `F` flask · `E/Up` interact · `Esc` pause

Gamepad is mapped too: left stick / d-pad move, A jump, X attack, Y lance, B dash, LB parry, d-pad down flask, d-pad up / RB interact, RT ignite, Start pause.

## What a run looks like

- **Eight chambers.** An intro, six combat chambers (each of the seven authored layouts appears at most once per seed), then the throne room.
- **Generated gauntlets.** The first two chambers are hand-authored; deeper ones fill waves from a threat budget seeded by the run, escalating to three waves with brutes and bombers.
- **Depth scaling and elites.** Enemies gain health and damage per chamber. From the third chamber on, one enemy may spawn as a gilded elite: bigger, tougher, worth triple score and three cells.
- **Kill streaks.** Chained kills inside a short window multiply score up to x3, with a decaying meter on the HUD.
- **Boons with rarity.** Each clear offers three of 22 boons weighted common / rare / epic. Unique boons leave the pool once taken. Synergy picks include Second Wind, Pyre (burning enemies detonate), Executioner, Momentum, Backdraft, Emberwave, Kindling, Bloodrush, and Cinder Skin.
- **The Ember Warden.** Lunge, fan, slam, and a telegraphed arena charge. Below half health it ignites, calls two wisps, and stops flinching.
- **Feedback everywhere.** Floating damage numbers, blocked-hit callouts, hit-stop, a vignette that bleeds red at low health, chamber title cards, and an end-of-run summary (time, kills, elites, best streak, damage, chambers).
- **One pixel grid, all of it rendered.** The world draws at 640x360 and upscales 2x with nearest filtering. The environment is a Blender-rendered tileset and three seamless parallax layers (`tools/render_environment.py` + `tests/env_bake.gd`): bevelled stone bricks for platform tops, fills, broken ends, ledges and pillars; distant towers; an arcade of stone arches with glazed rose windows and banners; near buttresses with sconces. Every pixel is toned inside its material's ramp so the sheets share one palette with the creatures.
- **Real 2D lighting.** An ambient tint per mood and point lights on the knight's flame, torches, braziers, the open rift, the boss, wisps and elites, with atmospheric haze between the parallax planes.
- **The knight is rendered the same way as the creatures.** `tools/render_knight.py` models and poses the knight in Blender (fire crown, tunic and sash, cape, sword), renders 21 poses × 4 crown-flicker frames plus a material-ID pass, and `tests/knight_bake.gd` bakes `assets/knight/knight_sheet.png`. If a sheet is missing the game falls back to procedural drawing.
- **A keep that warms as you descend.** The palette blends from a cold, moonlit blue crypt through a forge to the crimson throne, tinting tiles, layers and light; chambers carry their own set dressing (candles, bone piles, gallows, gears and pipes, braziers, the Ember Throne).
- **Procedural score.** Two seamless loops (an exploration bed and a boss theme) are synthesized from sine math on a worker thread at boot. There are no audio assets. Toggle music under Pause → Sound.
- **Meta progression.** Cells persist between runs and buy permanent upgrades at the Forge.

<p align="center">
  <img src="docs/screenshots/forge.png" alt="A forge-depth chamber: lava pit, gallows, broken masonry" width="49%">
  <img src="docs/screenshots/boons.png" alt="Boon selection with rarity tiers" width="49%">
</p>

## Tests

Two headless suites cover data invariants (seeded routes, wave generation, boon rolls) and runtime behaviour (elites, Second Wind, Pyre, boss charge and summons, music rendering, and a full simulated run from title to victory):

```sh
godot4 --headless --path . --script res://tests/test_runner.gd
godot4 --headless --path . --script res://tests/runtime_smoke.gd
```

Developer tools:

```sh
# Render the procedural score to WAV for listening/analysis
godot4 --headless --path . --script res://tests/music_dump.gd -- /tmp/graveflame-music
# Rebuild the environment art: render tiles + parallax layers in Blender, bake into assets/env
blender -b --python tools/render_environment.py -- /tmp/graveflame-env-render
godot4 --headless --path . --script res://tests/env_bake.gd -- /tmp/graveflame-env-render
# Rebuild the knight: render in Blender, then bake the sheet into assets/knight
blender -b --python tools/render_knight.py -- /tmp/graveflame-knight-render
godot4 --headless --path . --script res://tests/knight_bake.gd -- /tmp/graveflame-knight-render
# Fallback tile compositor sheet (used only when assets/knight is absent)
godot4 --headless --path . --script res://tests/knight_dump.gd -- /tmp/graveflame-knight
# Drive a run and save 1280x720 screenshots of the key beats. Renders offscreen, so
# the window can be tiny (it still needs a display).
godot4 --path . --script res://tests/screenshot_probe.gd --resolution 320x180 --position 0,0 -- /tmp/graveflame-shots
```

Both tools and the runtime suite write to a scratch save file, never to the player's real progress.

## Status

Playable vertical slice. Visuals are procedural pixel art plus Blender-rendered sprite sheets (creature family and the knight); audio is synthesized at runtime.

## License

[MIT](LICENSE)
