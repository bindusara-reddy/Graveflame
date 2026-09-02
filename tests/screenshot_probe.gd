extends SceneTree
## Dev harness: boots the game in an offscreen 1280x720 viewport, drives a run,
## and saves screenshots of the key beats. Uses a scratch save file. Needs a
## display, but the OS window can be tiny:
##   godot4 --path . --script res://tests/screenshot_probe.gd --resolution 320x180 --position 0,0 -- OUT_DIR

var out_dir := "/tmp"
var game: Game
var _vp: SubViewport

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	call_deferred("_run")

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := _vp.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("SHOT ", name)

func _press(action: String, frames: int = 2) -> void:
	Input.action_press(action)
	for i in range(frames):
		await physics_frame
	Input.action_release(action)
	await physics_frame

func _wait(seconds: float) -> void:
	var frames := int(seconds * 60.0)
	for i in range(frames):
		await physics_frame

func _live_enemies() -> Array:
	var out: Array = []
	if is_instance_valid(game.room):
		for e in game.room.enemies:
			if is_instance_valid(e) and not e.dead:
				out.append(e)
	return out

func _run() -> void:
	await process_frame
	auto_accept_quit = false
	root.close_requested.connect(func(): print("WINDOW CLOSE REQUESTED (ignored)"))
	# The game renders into an offscreen 1280x720 viewport; the OS window can stay
	# tiny and unfocused so the probe never takes over the desktop.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_title("graveflame render probe")
	Save.path = "user://graveflame_save_probe.json"
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.disable_3d = true
	root.add_child(_vp)
	var packed = load("res://main.tscn")
	game = packed.instantiate()
	_vp.add_child(game)
	await _wait(0.5)
	await _shot("01_title")
	game._on_start()
	await _wait(0.25)
	await _shot("02_room_intro")
	await _wait(1.2)
	# Stand next to the first stalker and land real swings.
	var enemies := _live_enemies()
	if enemies.size() > 0:
		game.player.global_position = enemies[0].global_position + Vector2(-70.0, -10.0)
		game.player.facing = 1.0
	await _wait(0.1)
	for i in range(3):
		await _press("attack")
		await _wait(0.12)
	await _shot("03_combat_numbers")
	# Chain the rest quickly for a streak read on the HUD.
	for e in _live_enemies():
		e.take_damage(99999.0, Vector2.RIGHT, 0.0)
		await _wait(0.15)
	await _wait(0.05)
	await _shot("04_streak_hud")
	# Skip ahead: clear rooms to reach the reward screen.
	var guard := 0
	while not game.room.exit_open and guard < 600:
		for e in _live_enemies():
			e.take_damage(99999.0, Vector2.RIGHT, 0.0)
		await physics_frame
		guard += 1
	await _wait(0.4)
	game._on_room_completed()
	await _wait(0.3)
	await _shot("05_reward_rarity")
	game._on_upgrade_selected(0)
	await _wait(0.3)
	await _shot("06_room_two_intro")
	# Jump to a deep room to show scaled waves / elites, then the throne room.
	game.run.room_index = 3
	game._advance_room()
	await _wait(1.0)
	game.player.take_damage(0.0, Vector2.RIGHT, 0.0)
	await _shot("07_deep_room")
	game.run.room_index = game.run.rooms_total() - 2
	game._advance_room()
	await _wait(0.9)
	await _shot("08_boss_intro")
	await _wait(1.2)
	game.room.boss.take_damage(game.room.boss.max_hp * 0.55, Vector2.RIGHT, 0.0)
	await _wait(0.5)
	await _shot("09_boss_phase2")
	# Low HP vignette, then death for the summary.
	game.player.iframes = 0.0
	game.player.take_damage(float(game.player.build.max_hp) * 0.8, Vector2.RIGHT, 100.0)
	await _wait(0.6)
	await _shot("10_low_hp")
	game.player.iframes = 0.0
	game.player.take_damage(99999.0, Vector2.RIGHT, 100.0)
	await _wait(0.4)
	await _shot("11_game_over_summary")
	quit(0)
