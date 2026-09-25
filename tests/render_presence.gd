extends "res://tests/harness.gd"
## Headful only: exercises production drawing and guards duplicate geometry.
## godot4 --path . --audio-driver Dummy --script res://tests/render_presence.gd

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

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("RENDER_PRESENCE requires a real rendering display, not --headless")
		quit(2)
		return
	use_scratch_save("render_presence")
	var vp := make_capture_viewport()
	var probe = load("res://main.tscn").instantiate()
	# The paint counters must be on the script before the scene enters the tree.
	probe.set_script(PaintProbe)
	vp.add_child(probe)
	game = probe
	await process_frame
	game.ui.start_requested.emit()
	game.player.respawn_at(Vector2(540.0, Content.FLOOR_Y - 27.0))
	for enemy in game.room.enemies: enemy.set_physics_process(false)
	game.feedback.camera.position = game._camera_target_for(game.player.position)
	await create_timer(0.65).timeout
	game.ui.hide_banners()
	await RenderingServer.frame_post_draw
	check(game.player.z_index > game.room.z_index, "the hero must draw above opaque room dressing such as the throne")
	check(game.projectiles.z_index > game.room.z_index, "projectiles must draw above opaque room dressing")
	check(game.feedback.z_index > game.player.z_index, "contact effects must remain visible above the hero")
	for key in probe.paints:
		var paint_count: int = probe.paints[key]
		check(paint_count == 1, "%s painted %d times in a single frame; expected 1" % [key, paint_count])
	var img := vp.get_texture().get_image()
	check(img != null and img.get_size() == Vector2i(1280, 720) and not img.is_empty(), "the capture viewport renders a full 1280x720 frame")
	await finish("RENDER_PRESENCE")
