extends SceneTree
## Approval-frame capture: stages ONE real combat frame (finisher impact +
## warden windup + graveflame aura) and saves it at native 1280x720.
## Run headful: DISPLAY=:1 godot4 --path . --script res://tests/approval_frame_capture.gd --resolution 320x180 --position 0,0 --audio-driver Dummy -- OUT_DIR

var out_dir := "/tmp"
var game: Game
var _vp: SubViewport


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	call_deferred("_run")


func _wait(seconds: float) -> void:
	var frames := int(seconds * 60.0)
	for i in range(frames):
		await physics_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := _vp.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("SHOT ", name)


func _run() -> void:
	await process_frame
	auto_accept_quit = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_title("graveflame approval capture")
	Save.path = "user://graveflame_save_approval.json"
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.disable_3d = true
	root.add_child(_vp)
	var packed = load("res://main.tscn")
	game = packed.instantiate()
	_vp.add_child(game)
	await _wait(0.5)
	game._on_start()
	await _wait(1.4)
	# Stage the duel: hero left, elite stalker right, graveflame aura live.
	# The chamber card must be gone before the swing so it never shares the frame.
	game.ui.hide_banners()
	var player := game.player
	player.global_position = Vector2(520.0, Content.FLOOR_Y - 40.0)
	player.facing = 1.0
	player.special = Content.P_SPECIAL_MAX
	player._do_graveflame()
	for e in game.room.enemies:
		if is_instance_valid(e) and not e.dead:
			e.global_position = Vector2(640.0, Content.FLOOR_Y - 40.0)
			e.facing = -1.0
			if e.has_method("_begin_windup"):
				e._begin_windup()
			break
	# Chain into the cleave then freeze mid-active so the ribbon + numbers land.
	player._begin_attack(false)
	await _wait(0.09)
	player._begin_attack(true)
	await _wait(0.11)
	for e in game.room.enemies:
		if is_instance_valid(e) and not e.dead:
			e.take_damage(24.0, Vector2.RIGHT, 300.0)
			break
	game.feedback.hit_stop(0.12)
	await _wait(0.05)
	game.feedback.camera.global_position = Vector2(590.0, Content.FLOOR_Y - 200.0)
	await _shot("approval_combat")
	# Boss frame: throne room, slam windup, phase-2 palette.
	game.run.room_index = game.run.rooms_total() - 2
	game._advance_room()
	await _wait(1.0)
	var boss = game.room.boss
	boss.intro_t = 0.01
	await _wait(0.15)
	game.player.global_position = Vector2(740.0, Content.FLOOR_Y - 40.0)
	game.player.facing = 1.0
	boss.global_position = Vector2(950.0, Content.FLOOR_Y - Content.BOSS_H * 0.5)
	boss.facing = -1.0
	boss.take_damage(boss.max_hp * 0.55, Vector2.RIGHT, 0.0)
	# Let the phase-2 tag fade out so the slam pose reads clean.
	await _wait(2.4)
	game.ui.hide_banners()
	# Pull the warden off the screen edge so the whole silhouette reads.
	boss.global_position = Vector2(880.0, Content.FLOOR_Y - Content.BOSS_H * 0.5)
	game.player.global_position = Vector2(690.0, Content.FLOOR_Y - 40.0)
	boss._begin_slam()
	await _wait(0.25)
	game.feedback.camera.global_position = Vector2(790.0, Content.FLOOR_Y - 220.0)
	await _shot("approval_boss")
	quit(0)
