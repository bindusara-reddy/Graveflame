extends "res://tests/harness.gd"
## Storefront capture: stages the three README beats at native 1280x720 and
## writes them into docs/screenshots/. Uses a scratch save so it never touches
## real progress.
##   DISPLAY=:1 godot4 --path . --script res://tests/storefront_capture.gd \
##       --resolution 320x180 --position 0,0 --audio-driver Dummy --fixed-fps 60 -- OUT_DIR
## (--fixed-fps keeps the staged beats deterministic on a slow renderer.)
var out_dir := "docs/screenshots"
var _vp: SubViewport

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

## Freeze the room's actors so the frame is a stable portrait, not a mid-tick.
func _still() -> void:
	for enemy in game.room.enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)

## Press shots read as "nothing has happened yet" if the HUD is zeroed, because
## a freshly staged room has no kills behind it. These are ordinary mid-run
## values a real descent produces; the capture is staged, and this says so.
func _stage_run_state(score: int, cells: int, hp: float) -> void:
	game.score = score
	game._run_cells = cells
	game.player.build.hp = hp
	game.ui.set_score(score)
	game.ui.set_cells(cells)
	game.ui.set_hp(hp, float(game.player.build.max_hp))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	await process_frame
	auto_accept_quit = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	use_scratch_save("graveflame_storefront")
	# A returning player's save: no first-run lessons popping into the frame.
	for lesson in Content.HINTS:
		Save.mark_learned(lesson)
	_vp = make_capture_viewport()
	await load_main_scene(60, _vp)

	# --- Title: the full tableau with the menu over it ---
	await _shot("title-screen")

	# --- Magma slam: airborne down-slam over the Cinderworks spike pit ---
	game.ui.start_requested.emit()
	await ticks(40)
	var route: Array = game.run.route
	for i in range(route.size()):
		if str(route[i].get("tag", "")) == "gap":
			game.run.room_index = i - 1
			break
	game._advance_room()
	await ticks(60)
	game.ui.hide_banners()
	_still()
	_stage_run_state(1480, 96, 82.0)
	# Clear the pit: a stalker beside the knight reads as the subject, and the
	# room's floating causeway sits at the same height, so the slam looked like
	# standing on it. Park the enemies and hold the pose in open air.
	for enemy in game.room.enemies:
		if is_instance_valid(enemy):
			enemy.global_position = Vector2(1420.0, Content.FLOOR_Y - 40.0)
	var pit := Vector2(560.0, Content.FLOOR_Y - 270.0)
	game.player.respawn_at(pit)
	game.player.facing = 1.0
	game.player.state = Player.State.SLAM
	game.player._slam_active = true
	game.player.velocity = Vector2(0.0, Content.P_SLAM_VEL)
	# Physics is frozen for the portrait, so pose the puppet by hand.
	game.player._pose = {}
	game.player._step_animation(0.0)
	game.player.set_physics_process(false)
	game.feedback.camera.position = Vector2(640.0, 430.0)
	# Enemies land a hit or two before they freeze, and the floating damage
	# number would sit in the frame with nothing left to explain it.
	game.feedback._particles.clear()
	await ticks(3)
	game.feedback.camera.position = Vector2(640.0, 430.0)
	game.feedback._particles.clear()
	await _shot("magma-slam")

	# --- Ember Warden: phase two, facing the knight across the throne ---
	game.run.room_index = game.run.rooms_total() - 2
	game._advance_room()
	await ticks(70)
	var boss = game.room.boss
	boss.intro_t = 0.01
	await ticks(12)
	game.ui.hide_banners()
	_still()
	_stage_run_state(3120, 214, 58.0)
	if is_instance_valid(boss):
		boss.global_position = Vector2(880.0, Content.FLOOR_Y - Content.BOSS_H * 0.5)
		boss.facing = -1.0
		boss.take_damage(boss.hp_max * 0.58, Vector2.RIGHT, 0.0)
	game.player.respawn_at(Vector2(620.0, Content.FLOOR_Y - 27.0))
	game.player.facing = 1.0
	game.feedback.camera.position = game._camera_target_for(game.player.position)
	await ticks(150)
	game.ui.hide_banners()
	game.feedback._particles.clear()
	# The Warden wanders while the fight settles; square the pair up again so
	# the frame is a face-off, not a knight turning his back on the boss.
	game.player.respawn_at(Vector2(560.0, Content.FLOOR_Y - 27.0))
	game.player.facing = 1.0
	game.player.iframes = 30.0
	_stage_run_state(3120, 214, 58.0)
	if is_instance_valid(boss):
		boss.global_position = Vector2(800.0, Content.FLOOR_Y - Content.BOSS_H * 0.5)
		boss.velocity = Vector2.ZERO
		boss.facing = -1.0
		# Cancel whatever move it was in (a charge would carry it through the knight).
		boss._disarm()
		boss.state = Enemy.EState.SEEK
		boss.action_t = 5.0
	game.feedback.camera.position = game._camera_target_for(Vector2(680.0, game.player.position.y))
	await ticks(2)
	if is_instance_valid(boss):
		boss._begin_lunge()
	await ticks(6)
	game.feedback._particles.clear()
	await _shot("ember-warden")

	# Also leaves no scratch save behind in the player's userdata directory.
	await finish("STOREFRONT")
