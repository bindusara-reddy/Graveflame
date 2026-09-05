extends SceneTree
## Fixture-free opening clear: reads live AI, sends input, never edits actors.
## --headless for behavior; headful with -- OUT_DIR captures real combat evidence.
var game: Game
var vp: SubViewport
var parries := 0
var counters := 0
var frame := 0
var out := ""
var capture_pending := ""
var capture_serial := 0

var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	Save.path = "user://input_combat_clear.json"
	if FileAccess.file_exists(Save.path): DirAccess.remove_absolute(Save.path)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		out = args[0]
		DirAccess.make_dir_recursive_absolute(out)
	vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	game = load("res://main.tscn").instantiate()
	vp.add_child(game)
	await process_frame
	game.ui.start_requested.emit()
	game.player.parried.connect(func(_pos, success):

		if success:
			parries += 1
			capture_pending = "parry"
	)
	game.player.hit_landed.connect(func(_damage, _pos, _heavy):
		if game.player._riposte_attack:
			counters += 1

			capture_pending = "riposte"
	)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 35000 and not game.room.exit_open and not game.player.dead:
		await physics_frame
		await process_frame
		frame += 1
		for action in ["attack", "parry", "move_left", "move_right"]: Input.action_release(action)
		var p := game.player
		var closest: Enemy = null
		var distance := INF
		for e in game.room.enemies:
			if is_instance_valid(e) and not e.dead:
				var d: float = absf(e.global_position.x - p.global_position.x)
				if d < distance:
					distance = d
					closest = e
		if closest == null: continue
		var dx := closest.global_position.x - p.global_position.x
		if distance > 46.0 and p.state == Player.State.LOCOMOTION:
			Input.action_press("move_right" if dx > 0.0 else "move_left")
		if p.riposte_time > 0.0 and distance < 118.0 and p.facing == signf(dx):

			Input.action_press("attack")
		elif closest.state == Enemy.EState.WINDUP and closest.st_timer < 0.10 and p.parry_cd <= 0.0:

			Input.action_press("parry")
		if out != "" and capture_pending != "":
			await RenderingServer.frame_post_draw
			var name := capture_pending
			capture_pending = ""
			if vp.get_texture().get_image().save_png(out.path_join(name + ".png")) != OK: failed = true
			capture_serial += 1
	for action in ["attack", "parry", "move_left", "move_right"]: Input.action_release(action)
	var cleared: bool = game.room.exit_open and not game.player.dead and game._stats.kills == 2
	if not cleared or parries < 2 or counters < 2:
		failed = true
	# Traverse to the exit using the same controls as the player, then use E.
	var exit_start := Time.get_ticks_msec()
	while cleared and absf(game.player.global_position.x - game.room.exit_center().x) > 20.0 and Time.get_ticks_msec() - exit_start < 10000:
		Input.action_press("move_right")
		await physics_frame
	Input.action_release("move_right")
	if cleared:
		await process_frame
		Input.action_press("interact")
		for i in range(3):
			await physics_frame
			await process_frame
		Input.action_release("interact")
		if game.state != Game.GState.REWARD: failed = true
	print("INPUT_CLEAR_RESULT: %s (kills=%d parries=%d ripostes=%d hp=%.1f reward=%s captures=%d)" % ["FAIL" if failed else "PASS", game._stats.kills, parries, counters, float(game.player.build.hp), game.state == Game.GState.REWARD, capture_serial])
	paused = false
	game.queue_free()
	await process_frame
	vp.queue_free()
	await process_frame
	if FileAccess.file_exists(Save.path): DirAccess.remove_absolute(Save.path)
	quit(1 if failed else 0)
