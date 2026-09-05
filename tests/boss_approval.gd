extends SceneTree
## Real main-scene approval captures. Staging only; not combat-clear evidence.
var game: Game
var vp: SubViewport
var out: String
var failed := false

func _init() -> void:
	call_deferred("_run")

func ticks(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img.get_size() != Vector2i(1280,720) or img.save_png(out.path_join(name+".png")) != OK:
		failed = true
	print("BOSS_FRAME ", name, " player_alive=", not game.player.dead, " boss_alive=", not game.room.boss.dead)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	Save.path = "user://boss_approval.json"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	vp = SubViewport.new()
	vp.size = Vector2i(1280,720)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	game = load("res://main.tscn").instantiate()
	vp.add_child(game)
	await ticks(2)
	game.ui.start_requested.emit()
	game.run.room_index = game.run.rooms_total()-2
	game._advance_room()
	await ticks(2)
	var boss := game.room.boss
	boss.intro_t = 0.01
	await ticks(2)
	game.ui.hide_banners()
	game.player.respawn_at(Vector2(600,Content.FLOOR_Y-27))
	game.player.facing = 1.0
	boss.global_position = Vector2(845,Content.FLOOR_Y-59)
	boss.facing = -1.0
	boss.velocity = Vector2.ZERO
	game.feedback.camera.position = game._camera_target_for(game.player.position)
	await ticks(4)
	game.ui.hide_banners()
	await shot("warden_stance")
	boss._begin_lunge()
	await ticks(12)
	await shot("warden_windup")
	boss._begin_slam()
	await ticks(7)
	await shot("warden_slam")
	boss.take_damage(boss.max_hp*0.55,Vector2.RIGHT,0.0)
	await ticks(3)
	boss.global_position = Vector2(845,Content.FLOOR_Y-59)
	boss.velocity = Vector2.ZERO
	game.player.respawn_at(Vector2(600,Content.FLOOR_Y-27))
	boss._begin_fan()
	await ticks(5)
	game.ui.hide_banners()
	await shot("warden_ignited")
	failed = failed or game.player.dead or boss.dead
	print("BOSS_APPROVAL_CAPTURE: ", "FAIL" if failed else "PASS")
	game.queue_free()
	await process_frame
	vp.queue_free()
	await process_frame
	quit(1 if failed else 0)
