extends SceneTree
## Live-window, wall-clock performance gate. No extra presentation SubViewport,
## frozen actors, fixed FPS, stat boosts or direct combat calls during sampling.
## godot4 --path . --audio-driver Dummy --script res://tests/render_performance.gd -- OUT_JSON [PROBE]

class TimedGame extends Game:
	var paint_us := 0
	var paint_count := 0
	var game_us := 0
	func _paint_backdrop(ci: CanvasItem) -> void:
		var started := Time.get_ticks_usec()
		super._paint_backdrop(ci)
		paint_us = Time.get_ticks_usec() - started
		paint_count += 1
	func _process(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._process(delta)
		game_us = Time.get_ticks_usec() - started

var game: Game
var output := ""
var probe := "normal"
var started := 0
var last := 0
var samples: Array[float] = []
var process_ms: Array[float] = []
var physics_ms: Array[float] = []
var backdrop_ms: Array[float] = []
var draw_calls: Array[float] = []
var valid := true
var measuring := false
var _stopping := false
const WARMUP_US := 3000000
const SAMPLE_US := 6000000
const P95_LIMIT_MS := 20.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		printerr("LIVE_PERF requires a real display and output JSON path")
		quit(2)
		return
	output = args[0]
	if args.size() > 1: probe = args[1]
	Save.path = "user://render_performance.json"
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP,true)
	game = load("res://main.tscn").instantiate()
	game.set_script(TimedGame)
	root.add_child(game)
	await process_frame
	seed(424242)
	game.ui.start_requested.emit()
	game.run.room_index = game.run.rooms_total()-2
	game._advance_room()
	if probe == "phase-two":
		# Stage phase two via the real damage/transition path before measurement.
		game.room.boss.take_damage(Content.BOSS_HP*0.55,Vector2.ZERO,0.0)
	seed(1777)
	# Initial placement only. Player stats, attack damage and AI stay at production values.
	game.player.respawn_at(Vector2(260,Content.FLOOR_Y-27))
	game.room.boss.global_position = Vector2(980,Content.FLOOR_Y-59)
	game.feedback.camera.position = game._camera_target_for(game.player.position)
	match probe:

		"no-backdrop": game._backdrop.hide()
		"no-lights": game._lights.hide()
		"no-room": game.room.hide()
		"no-vignette": game._vignette_rect.hide()
		"no-atmosphere":
			game._atmosphere.hide()
			game._light_layer.hide()
	game.ui.hide_banners()
	started = Time.get_ticks_usec()
	last = started
	measuring = true

func _process(_delta: float) -> bool:
	if not measuring or _stopping:
		return false
	var now := Time.get_ticks_usec()
	var elapsed := now-started
	var ms := float(now-last)/1000.0
	last = now
	if game.state != Game.GState.PLAYING or paused or game.player.dead or game.room.boss.dead:
		valid = false
		_stopping = true
		_finish.call_deferred()
		return false
	# Real controls keep the fight active. Heal takes priority over offence.
	var p := game.player
	var boss := game.room.boss
	var dx := boss.global_position.x-p.global_position.x
	_set_action("heal", float(p.build.hp) < 70.0 and p.flask_charges > 0)
	var needs_heal := float(p.build.hp) < 70.0 and p.flask_charges > 0
	var move := absf(dx) > 125.0 and not needs_heal
	_set_action("move_right", move and dx > 0.0)
	_set_action("move_left", move and dx < 0.0)
	_set_action("attack", probe != "phase-two" and not needs_heal and absf(dx) < 135.0 and elapsed % 600000 < 100000)
	_set_action("parry", boss.state == Enemy.EState.WINDUP and boss.st_timer < 0.14 and p.parry_cd <= 0.0)
	_set_action("dash", boss.state == Enemy.EState.ATTACK and p.dash_cd <= 0.0 and elapsed % 1200000 < 100000)
	if elapsed >= WARMUP_US:
		samples.append(ms)
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		backdrop_ms.append(float(game.paint_us)/1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if elapsed >= WARMUP_US+SAMPLE_US:
		_stopping = true
		_finish.call_deferred()
	return false

func _set_action(action: String, pressed: bool) -> void:
	if Input.is_action_pressed(action) == pressed: return
	if pressed: Input.action_press(action)
	else: Input.action_release(action)

func percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty(): return INF
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[mini(ordered.size()-1,int(float(ordered.size())*fraction))]

func _finish() -> void:
	measuring = false
	for action in ["heal","move_right","move_left","attack","parry","dash"]: Input.action_release(action)
	var total_ms := 0.0
	for ms in samples: total_ms += ms
	var mean_fps := float(samples.size())*1000.0/total_ms if total_ms > 0.0 else 0.0
	var result := {
		"probe":probe,"scenario_valid":valid,"frames":samples.size(),
		"p50_ms":percentile(samples,0.5),"p95_ms":percentile(samples,0.95),"max_ms":percentile(samples,1.0),
		"process_p95_ms":percentile(process_ms,0.95),"physics_p95_ms":percentile(physics_ms,0.95),
		"backdrop_p95_ms":percentile(backdrop_ms,0.95),"draw_calls_p50":percentile(draw_calls,0.5),
		"player_hp":game.player.build.hp,"boss_hp":game.room.boss.hp,"boss_paints":game.paint_count,
		"renderer":RenderingServer.get_video_adapter_name(),"viewport":str(game.pixel_view.size),
		"mean_fps":mean_fps,"boss_phase":game.room.boss.phase,
	}
	var passed := valid and samples.size() >= 180 and float(result.p95_ms) <= P95_LIMIT_MS and float(result.max_ms) <= 40.0 and mean_fps >= 58.0
	passed = passed and (probe != "phase-two" or game.room.boss.phase == Boss.BPhase.TWO)
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: passed = false
	result["passed"] = passed
	if file != null: file.store_string(JSON.stringify(result,"  "))
	print("LIVE_PERF_RESULT: ","PASS" if passed else "FAIL"," ",JSON.stringify(result))
	game.queue_free()
	await process_frame
	quit(0 if passed else 1)
