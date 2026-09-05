extends SceneTree
## Staged screenshots only. Live performance: tests/render_performance.gd.
## Never used as proof of a fixture-free clear; input_combat_clear.gd covers that.
var game: Game
var vp: SubViewport
var out := ""
var failures := 0

func _init() -> void:
	call_deferred("_run")

func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	if vp.get_texture().get_image().save_png(out.path_join(name + ".png")) != OK:
		failures += 1
	print("SHOT ", name)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Provide output directory and a real rendering display.")
		quit(2)
		return
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	Save.path = "user://presence_showcase.json"
	vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	root.add_child(vp)
	# Present the measured viewport. An unused offscreen viewport leaves a blank
	# Xwayland window that the compositor throttles to 1 FPS when occluded.
	var screen := TextureRect.new()
	screen.texture = vp.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	game = load("res://main.tscn").instantiate()
	vp.add_child(game)
	await ticks(4)
	game.ui.start_requested.emit()
	await ticks(40)
	for e in game.room.enemies: e.set_physics_process(false)
	game.ui.hide_banners()
	var p := game.player
	p.respawn_at(Vector2(500.0, Content.FLOOR_Y - 27.0))
	game.feedback.camera.position = game._camera_target_for(p.position)
	await ticks(5)
	Input.action_press("move_right")
	Input.action_press("dash")
	await ticks(1)
	Input.action_release("dash")
	Input.action_release("move_right")
	await ticks(5)
	await shot("dash")
	await ticks(35)
	var prop = game.room.props.filter(func(v): return not v.broken)[-1]
	p.respawn_at(prop.global_position + Vector2(-44.0, -27.0))
	p.facing = 1.0
	game.feedback.camera.position = game._camera_target_for(p.position)
	await ticks(5)
	Input.action_press("attack")
	await ticks(1)
	Input.action_release("attack")
	await ticks(6)
	await shot("shatter")
	if not prop.broken: failures += 1
	await ticks(28)
	game.run.room_index = game.run.rooms_total() - 2
	game._advance_room()
	await ticks(2)
	var boss := game.room.boss
	boss.intro_t = 0.01
	await ticks(3)
	game.ui.hide_banners()
	boss.global_position = Vector2(820.0, Content.FLOOR_Y - Content.BOSS_H * 0.5)
	p.respawn_at(Vector2(690.0, Content.FLOOR_Y - 27.0))
	p.facing = 1.0
	game.feedback.camera.position = game._camera_target_for(p.position)
	await ticks(5)
	boss._begin_lunge()
	await ticks(7)
	await shot("boss")

	if p.dead or boss.dead:
		failures += 1
		quit(1)
		return
	print("SHOWCASE_RESULT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	game.queue_free()
	await process_frame
	vp.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
