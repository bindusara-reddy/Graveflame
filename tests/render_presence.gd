extends SceneTree
## Headful only: exercises production drawing and guards duplicate geometry.
## godot4 --path . --audio-driver Dummy --script res://tests/render_presence.gd -- OUT_DIR

class PaintProbe extends Game:
	var paints := {"spires": 0, "arches": 0, "shafts": 0, "buttresses": 0}
	func _paint_backdrop(ci: CanvasItem) -> void:
		for key in paints: paints[key] = 0
		super._paint_backdrop(ci)
	func _draw_spires(ci: CanvasItem, horizon: float) -> void:
		paints.spires += 1
		super._draw_spires(ci, horizon)
	func _draw_arches(ci: CanvasItem, horizon: float) -> void:
		paints.arches += 1
		super._draw_arches(ci, horizon)
	func _draw_light_shafts(ci: CanvasItem, top: float, horizon: float) -> void:
		paints.shafts += 1
		super._draw_light_shafts(ci, top, horizon)
	func _draw_buttresses(ci: CanvasItem, horizon: float) -> void:
		paints.buttresses += 1
		super._draw_buttresses(ci, horizon)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("RENDER_PRESENCE requires a real rendering display, not --headless")
		quit(2)
		return
	Save.path = "user://render_presence.json"
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var game = load("res://main.tscn").instantiate()
	game.set_script(PaintProbe)
	vp.add_child(game)
	await process_frame
	game.ui.start_requested.emit()
	game.player.respawn_at(Vector2(540.0, Content.FLOOR_Y - 27.0))
	for enemy in game.room.enemies: enemy.set_physics_process(false)
	game.feedback.camera.position = game._camera_target_for(game.player.position)
	await create_timer(0.65).timeout
	game.ui.hide_banners()
	await RenderingServer.frame_post_draw
	var failed := 0
	if game.player.z_index <= game.room.z_index:
		failed += 1
		printerr("FAIL: the hero must draw above opaque room dressing such as the throne")
	if game.projectiles.z_index <= game.room.z_index:
		failed += 1
		printerr("FAIL: projectiles must draw above opaque room dressing")
	if game.feedback.z_index <= game.player.z_index:
		failed += 1
		printerr("FAIL: contact effects must remain visible above the hero")
	for key in game.paints:
		if game.paints[key] != 1:
			failed += 1
			printerr("FAIL: %s painted %d times in a single frame; expected 1" % [key, game.paints[key]])
	var img := vp.get_texture().get_image()
	if img.get_size() != Vector2i(1280, 720) or img.is_empty(): failed += 1
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0])
		if img.save_png(args[0].path_join("crypt.png")) != OK: failed += 1
	print("RENDER_PRESENCE_RESULT: %s (8 checks, %d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	game.queue_free()
	await process_frame
	vp.queue_free()
	await process_frame
	quit(0 if failed == 0 else 1)
