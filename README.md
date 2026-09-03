# Graveflame


![Graveflame title screen](docs/screenshots/title.png)

<p align="center">
  <img src="docs/screenshots/combat.png" alt="Chamber combat with agile knight and slash arcs" width="49%">
  <img src="docs/screenshots/ember-warden.png" alt="The Ember Warden boss fight in the throne room" width="49%">
</p>

<p align="center">
  <img src="docs/screenshots/forge.png" alt="Platforming through deeper keep chambers" width="49%">
  <img src="docs/screenshots/boons.png" alt="Boon draft selection" width="49%">
</p>

## Play

1. Install [Godot 4.3](https://godotengine.org/) or newer.
2. Open `project.godot` in Godot.
3. Press **F5** (or run `godot4 --path .`).

## Controls

`A/D` move · `W/Space` jump · `J` blade · `K` lance · `Q` ignite · `Shift/L` dash · `S` parry · `F` flask · `E/Up` enter rift · `Esc` pause

Full gamepad support included (left stick/d-pad move, A jump, X attack, Y lance, B dash, LB parry, d-pad down flask, RT ignite, Start pause).

## What's in the run

- **Eight chambers:** A cold crypt descent warming into a subterranean forge and the crimson Ember Throne.
- **Procedural vector art & lighting:** Clean, cohesive vector-native silhouettes, dual rim lighting, and real-time atmospheric depth without resolution clashes.
- **Dynamic combat feel:** Directional slashes, ground slam impacts, front-facing parry windows, and kill-streak multiplier meters.
- **The Ember Warden:** Towering gothic inquisitor/executioner with a cathedral ribcage furnace, horned mitre, executioner's greatsword, and phase 2 wisp summons.
- **22 Synergy Boons:** Common, rare, and epic passive power-ups that alter flame properties, streaks, and survivability.
- **Synthesized score:** Seamless ambient and boss audio themes generated procedurally at runtime.

## Tests

Headless verification suites covering data invariants, mechanics, and runtime behavior:

```sh
godot4 --headless --path . --script res://tests/test_runner.gd
godot4 --headless --path . --script res://tests/runtime_smoke.gd
```

## License

[MIT](LICENSE)
