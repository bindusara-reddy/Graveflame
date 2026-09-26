extends "res://tests/harness.gd"
## Storefront capture: stages the README's five shots at native 1280x720 and
## writes them into docs/screenshots/: the title, a fight in the crypt yard,
## the Warden waiting on its throne, a boon offer and the Forge. The ending is
## never shown: it stays a surprise. Uses a scratch save so it never touches
## real progress. Run it on the private X server, never the desktop's:
##   DISPLAY=:97 godot4 --display-driver x11 --rendering-driver opengl3 --path . \
##       --script res://tests/storefront_capture.gd --resolution 1280x720 \
##       --audio-driver Dummy --fixed-fps 60 -- OUT_DIR
## (--fixed-fps and the seeded RNG keep the staged beats deterministic.)
var out_dir := "docs/screenshots"
var _vp: SubViewport

## The returning knight the shots are staged for: nine falls, no win yet (a win
## would relight the title and wake the Warden sooner), a few relics tempered.
const SAVE := {
	"falls": 9, "falls_legacy": false, "cells": 146,
	"meta": ["m_max_hp", "m_max_hp", "m_dmg", "m_flask", "m_special"],
}
## Global RNG seed for the descent, so its route, sparks and severing repeat.
const STAGE_SEED := 20260926
## The boon offer: one card of each rarity.
const OFFER := ["phoenix", "skyfall", "brand"]

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := _vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	# A null image means nothing rendered, which fails the shot as well.
	var written := img != null and img.save_png(out_dir.path_join(name + ".png")) == OK
	check(written, "could not write " + name)
	if written:
		print("SHOT ", name, " ", img.get_size())

## A freshly staged room has no kills behind it, and a zeroed HUD reads as
## "nothing has happened yet". These are ordinary mid-descent values; the
## capture is staged, and this says so.
func _stage_hud(score: int, cells: int, hp: float, graveflame: float) -> void:
	game.score = score
	game._run_cells = cells
	game._unbanked_cells = 0
	game.player.build.hp = hp
	game.player.special = graveflame
	game.ui.set_score(score)
	game.ui.set_cells(cells)
	game.ui.set_hp(hp, float(game.player.build.max_hp))
	game.ui.set_special(graveflame, Content.P_SPECIAL_MAX)

## One blade press, held for two frames like a tap.
func _swing() -> void:
	Input.action_press("attack")
	await ticks(2)
	Input.action_release("attack")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	await process_frame
	auto_accept_quit = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	use_scratch_save("graveflame_storefront")
	Save.save_save(Save.load_save().merged(SAVE, true))
	# A returning player's save: no first-run lessons popping into the frame.
	for lesson in Content.HINTS:
		Save.mark_learned(lesson)
	_vp = make_capture_viewport()
	await load_main_scene(60, _vp)

	# --- Title: the full tableau with the menu over it, once the reveal has lit ---
	await ticks(120)
	await _shot("title-screen")

	# --- The crypt yard: an ignited combo cuts a stalker in two under the moon ---
	seed(STAGE_SEED)
	game.ui.start_requested.emit()
	await ticks(40)
	var yard: Dictionary = Content.ROOM_TEMPLATES.filter(func(t): return t.tag == "arena")[0]
	game.run.route[3] = yard
	game.run.room_index = 2
	game._advance_room()
	# Cast the fight by hand instead of the chamber's own wave.
	for foe in game.room.enemies:
		foe.queue_free()
	game.room.enemies.clear()
	var knight_x := 560.0
	var stalker: Enemy = game.room._spawn_enemy(Content.EnemyKind.STALKER, Vector2(knight_x + 150.0, Content.FLOOR_Y - 40.0))
	var hopper: Enemy = game.room._spawn_enemy(Content.EnemyKind.HOPPER, Vector2(knight_x + 330.0, Content.FLOOR_Y - 40.0))
	var crow: Enemy = game.room._spawn_enemy(Content.EnemyKind.CROW, Vector2(960.0, Content.FLOOR_Y - 250.0))
	var wisp: Enemy = game.room._spawn_enemy(Content.EnemyKind.WISP, Vector2(knight_x - 200.0, Content.FLOOR_Y - 250.0))
	await ticks(90)
	game.ui.hide_banners()
	# The watchers hold their marks (the crow on its ledge, the wisp over the
	# graves); only the stalker takes the combo.
	for foe in [hopper, crow, wisp]:
		foe.set_physics_process(false)
	crow.global_position = Vector2(960.0, Content.FLOOR_Y - 236.0)
	wisp.global_position = Vector2(knight_x - 190.0, Content.FLOOR_Y - 250.0)
	hopper.global_position = Vector2(knight_x + 330.0, Content.FLOOR_Y - 23.0)
	hopper.facing = -1.0
	stalker.global_position = Vector2(knight_x + 92.0, Content.FLOOR_Y - 23.0)
	stalker.facing = -1.0
	game.player.respawn_at(Vector2(knight_x, Content.FLOOR_Y - 27.0))
	game.player.facing = 1.0
	game.player._flame_time = 10.0  # ignited, without the ignition's blast
	game._streak_kills = 5
	game._streak_t = 2.8
	game._streak_tier = Content.streak_tier(5)
	game.ui.set_streak(5, 0.8, Content.streak_multiplier(5))
	_stage_hud(1480, 96, 74.0, 45.0)
	await ticks(2)
	await _swing()
	await ticks(20)
	# The second cut severs it: the frame catches the halves under the smear.
	await _swing()
	await ticks(10)
	_stage_hud(1540, 96, 74.0, 53.0)
	# A swing's brief invulnerability flickers the coat ember-orange.
	game.player.iframes = 0.0
	await _shot("crypt-fight")

	# --- A boon offer: the yard cleared, one card of each rarity ---
	var guard := 0
	while not game.room.exit_open and guard < 600:
		for foe in live_enemies():
			foe.take_damage(99999.0, Vector2.RIGHT, 0.0)
		await ticks(1)
		guard += 1
	await ticks(30)
	game._on_room_completed()
	var offer: Array = OFFER.map(func(id): return upgrade(id))
	game._pending_upgrades = offer
	game.ui.setup_upgrades(offer)
	await ticks(50)
	check(game.ui.is_panel_visible("reward"), "the boon offer is open")
	await _shot("boon-offer")
	game._on_upgrade_selected(0)
	await ticks(10)

	# --- The Warden, seated on its throne as the knight walks up the hall ---
	game.run.room_index = game.run.rooms_total() - 2
	game._advance_room()
	game.ui.hide_streak()
	game.player._flame_time = 0.0
	game.player.respawn_at(Vector2(250.0, Content.FLOOR_Y - 27.0))
	await ticks(30)
	var boss: Boss = game.room.boss
	Input.action_press("move_right")
	while game.player.global_position.x < 300.0:
		await ticks(1)
	# The Warden would rise as the knight comes near; hold it on its seat.
	boss.set_physics_process(false)
	while game.player.global_position.x < 432.0:
		await ticks(1)
	Input.action_release("move_right")
	_stage_hud(2860, 184, 81.0, 70.0)
	check(boss.seated, "the Warden still sits on its throne")
	await _shot("warden-throne")
	boss.set_physics_process(true)

	# --- The Forge, between lives ---
	game._on_quit_to_title()
	await ticks(30)
	Save.save_save(Save.load_save().merged({ "cells": 154 }, true))
	game._on_forge_requested()
	await ticks(40)
	check(game.ui.is_panel_visible("forge"), "the Forge is open")
	await _shot("the-forge")

	# Also leaves no scratch save behind in the player's userdata directory.
	await finish("STOREFRONT")
