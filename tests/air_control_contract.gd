extends SceneTree
## Focused control regression tests on the real main scene.
## Movement/attack tests use input only; the summary test injects one damage event.
var game: Game
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func ticks(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func boot() -> void:
	for action in ["attack","jump","dash","move_left","move_right"]: Input.action_release(action)
	if InputMap.has_action("move_down"): Input.action_release("move_down")
	if is_instance_valid(game):
		paused=false
		game.queue_free()
		await process_frame
	Save.path="user://air_control_contract.json"
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await ticks(3)
	game.ui.start_requested.emit()
	await ticks(4)
	Input.action_press("move_left")
	await ticks(32)
	Input.action_release("move_left")
	await ticks(8)

func falling_jump() -> void:
	Input.action_press("jump")
	await ticks(1)
	for i in range(70):
		await ticks(1)
		if game.player.velocity.y>280.0 and not game.player.is_on_floor(): return

func active_attack(airborne: bool) -> void:
	if airborne:
		Input.action_press("jump")
		await ticks(12)
		Input.action_release("jump")
		await ticks(1)
	Input.action_press("attack")
	await ticks(1)
	Input.action_release("attack")
	for i in range(20):
		await ticks(1)
		if game.player.atk_phase=="active" and game.player.atk_time<=0.035: return

func run() -> void:
	await boot()
	await falling_jump()
	check(not game.player.is_on_floor() and game.player.velocity.y>250.0,"falling attack probe reached a real descent")
	Input.action_press("attack")
	await ticks(2)
	Input.action_release("attack")
	check(game.player.state==Player.State.ATTACK,"a falling blade press stays an air slash, never an accidental pit dive")
	check(not game.player._slam_active,"unmodified attack never arms a slam")

	await boot()
	check(InputMap.has_action("move_down"),"an explicit down modifier exists for deliberate air slams")
	if InputMap.has_action("move_down"):
		var keyboard := false
		var pad := false
		var heal_conflict := false
		for event in InputMap.action_get_events("move_down"):
			for heal_event in InputMap.action_get_events("heal"):
				if event.is_match(heal_event): heal_conflict = true
			if event is InputEventKey and event.physical_keycode==KEY_DOWN: keyboard=true
			if event is InputEventJoypadMotion and event.axis==1 and event.axis_value>0.0: pad=true
		check(keyboard and pad,"deliberate slam supports keyboard down and gamepad stick down")
		check(not heal_conflict,"slam direction does not share an existing flask button")
		Input.action_press("jump")
		await ticks(10)
		Input.action_press("move_down")
		Input.action_press("attack")
		await ticks(2)
		check(game.player.state==Player.State.SLAM,"down plus attack deliberately commits the air slam")
		Input.action_release("move_down")

	await boot()
	await active_attack(true)
	check(game.player.atk_phase=="active" and not game.player.is_on_floor(),"air-jump buffer probe reached active blade frames")
	var jumps_before := game.player.jumps_left
	Input.action_press("jump")
	await ticks(1)
	Input.action_release("jump")
	check(game.player.jumps_left==jumps_before,"jump input cannot cancel committed active frames")
	await ticks(5)
	check(game.player.state==Player.State.LOCOMOTION and game.player.velocity.y < -400.0,"buffered air jump executes as blade recovery opens")
	check(game.player.jumps_left==jumps_before-1,"recovery jump consumes exactly one real air jump")
	check(game.player._atk_shape.disabled and not game.player._draw_attack,"jump cancellation closes the blade hitbox and visual")

	await boot()
	await active_attack(false)
	check(game.player.atk_phase=="active","dash buffer probe reached active blade frames")
	Input.action_press("dash")
	await ticks(1)
	Input.action_release("dash")
	check(game.player.state==Player.State.ATTACK,"dash input cannot cancel committed active frames")
	await ticks(4)
	check(game.player.state==Player.State.DASH,"dash pressed just before recovery is buffered rather than lost")
	check(game.player._atk_shape.disabled,"dash cancellation closes the blade hitbox")

	await boot()
	# Rapid presses during the old coyote window must not mint extra air jumps.
	Input.action_press("jump")
	await ticks(1)
	Input.action_release("jump")
	await ticks(1)
	Input.action_press("jump")
	await ticks(1)
	Input.action_release("jump")
	await ticks(1)
	check(not game.player.is_on_floor() and game.player.jumps_left==0,"two rapid real jump presses exhaust the air-jump budget")
	var vy_before := game.player.velocity.y
	Input.action_press("jump")
	await ticks(2)
	Input.action_release("jump")
	check(game.player.jumps_left==0 and game.player.velocity.y>vy_before,"a third rapid jump cannot exploit residual coyote time")

	await boot()
	# Component fixture only: a real lethal damage signal must reach run statistics.
	game.player.iframes=0.0
	game.player.take_damage(100.0,Vector2.RIGHT,0.0)
	check(game.state==Game.GState.GAME_OVER,"lethal damage produces the real game-over flow")
	check(is_equal_approx(float(game._stats.damage_taken),100.0),"run summary includes the final hit, capped to actual health lost")

	await boot()
	game.player.iframes=0.0
	game.player.take_damage(9999.0,Vector2.RIGHT,0.0)
	check(game.state==Game.GState.GAME_OVER and is_equal_approx(float(game._stats.damage_taken),100.0),"overkill records health lost, not the raw damage request")

	await boot()
	# Boon/damage fixtures isolate signal accounting, not full-run survival.
	game.player.build.second_wind=true
	game.player.iframes=0.0
	game.player.take_damage(9999.0,Vector2.RIGHT,0.0)
	check(not game.player.dead and game.player.build.second_wind_used,"Second Wind consumes its one real survival charge")
	check(is_equal_approx(float(game.player.build.hp),30.0) and is_equal_approx(float(game._stats.damage_taken),100.0),"Second Wind reports the lethal loss before restoring health")
	game.player.take_damage(9999.0,Vector2.RIGHT,0.0)
	check(is_equal_approx(float(game._stats.damage_taken),100.0),"blocked damage during Second Wind immunity is not counted twice")
	game.player.iframes=0.0
	game.player.take_damage(9999.0,Vector2.RIGHT,0.0)
	check(game.state==Game.GState.GAME_OVER and is_equal_approx(float(game._stats.damage_taken),130.0),"a second lethal hit kills and records only the restored health")

	await boot()
	Input.action_press("dash")
	await ticks(1)
	Input.action_release("dash")
	await ticks(16)
	check(game.player.state==Player.State.LOCOMOTION and game.player.dash_cd>0.2,"expiry probe reaches locomotion while dash is cooling down")
	Input.action_press("dash")
	await ticks(1)
	Input.action_release("dash")
	await ticks(30)
	check(game.player.state==Player.State.LOCOMOTION and game.player._dash_buffer==0.0 and game.player.dash_cd<=0.0,"expired dash request never fires later when its cooldown ends")

	await boot()
	await active_attack(false)
	Input.action_press("jump")
	Input.action_press("dash")
	await ticks(1)
	Input.action_release("jump")
	Input.action_release("dash")
	game.player.suppress_gameplay_input(8)
	await ticks(10)
	check(game.player.is_on_floor() and game.player.state!=Player.State.DASH,"suppression cancels pending recovery movement")
	check(game.player.jump_buffer==0.0 and game.player._dash_buffer==0.0,"suppression leaves no delayed movement request")

	await boot()
	await active_attack(false)
	Input.action_press("jump")
	Input.action_press("dash")
	await ticks(1)
	Input.action_release("jump")
	Input.action_release("dash")
	game.player.respawn_at(game.player.global_position)
	check(game.player.jump_buffer==0.0 and game.player._dash_buffer==0.0,"room respawn clears pending jump and dash requests")
	await ticks(10)
	check(game.player.is_on_floor() and game.player.state==Player.State.LOCOMOTION,"respawn cannot execute a stale recovery move")

	paused=false
	game.queue_free()
	await process_frame
	for action in ["attack","jump","dash","move_left","move_right"]: Input.action_release(action)
	if InputMap.has_action("move_down"): Input.action_release("move_down")
	print("AIR_CONTROL_RESULT: %s (%d checks, %d failures)" % ["PASS" if failures==0 else "FAIL",checks,failures])
	quit(0 if failures==0 else 1)
