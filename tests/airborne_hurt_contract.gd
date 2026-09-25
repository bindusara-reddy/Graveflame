extends "res://tests/harness.gd"
## Real main-scene input plus explicit damage fixtures, not full-run combat proof.
## No position, velocity, health, immunity or jump-budget setup mutations.

func boot() -> void:
	release(["jump", "move_left", "move_right"])
	await load_main_scene()
	# These fixtures count knockback frames; the hurt freeze would stretch them.
	game.feedback.set_reduced_motion(true)
	await start_run(0)
	await hold_action("move_left", 30)
	await ticks(60)

func jump() -> void:
	await hold_action("jump", 10)
	await ticks(1)

func grounded_hit(label: String) -> void:
	var p := game.player
	check(p.is_on_floor() and p.iframes <= 0.0, label + ": grounded with expired immunity")
	print("GROUND_HURT_EVIDENCE: ", label, " state=", p.state, " pos=", p.position, " floor=", p.is_on_floor(), " iframes=", p.iframes, " hp=", p.build.hp)
	var hp_before := float(p.build.hp)
	p.take_damage(12.0, Vector2.RIGHT, 600.0)
	check(p.state == Player.State.HURT and p.velocity == Vector2(600.0, -210.0), label + ": full initial knockback")
	check(is_equal_approx(float(p.build.hp), hp_before - 12.0), label + ": full damage")
	await hold_action("jump")
	check(p.state == Player.State.HURT and p.jumps_left == Content.P_MAX_JUMPS and p.velocity.y > -210.0, label + ": jump cannot cancel initial stun")
	await ticks(7)
	check(not p.is_on_floor() and p.velocity.y >= 0.0 and absf(p.velocity.x) < 30.0, label + ": descending before landing")
	check(p.state == Player.State.HURT, label + ": grounded-start hit still requires landing")
	await ticks(8)
	check(p.is_on_floor() and p.state == Player.State.LOCOMOTION and p.jumps_left == Content.P_MAX_JUMPS, label + ": normal landing recovery and budget")

func run() -> void:
	use_scratch_save("airborne_hurt_contract")
	await boot()
	await grounded_hit("fresh grounded hit")

	await boot()
	await jump()
	var p := game.player
	check(not p.is_on_floor() and p.jumps_left == 1 and p.iframes <= 0.0, "real jump leaves one air jump after spawn immunity expires")
	p.take_damage(12.0, Vector2.RIGHT, 180.0)
	check(p.state == Player.State.HURT and p.velocity == Vector2(180.0, -63.0) and p.build.hp == 88.0, "airborne hit retains initial knockback and full damage")
	await ticks(1)
	check(p.state == Player.State.HURT and p.velocity.x > 30.0 and p.velocity.y < 0.0, "initial airborne knockback cannot be skipped")
	await ticks(7)
	print("AIR_HURT_EVIDENCE: state=", p.state, " y=", p.position.y, " vy=", p.velocity.y, " vx=", p.velocity.x, " floor=", p.is_on_floor(), " jumps=", p.jumps_left)
	check(not p.is_on_floor() and p.velocity.y >= 0.0 and p.state == Player.State.LOCOMOTION, "airborne-start hurt recovers after knockback settles before landing")
	check(p.iframes > 0.0, "damage immunity outlasts stun independently")
	check(p.jumps_left == 1, "hurt recovery cannot mint an air jump")
	var velocity_before := p.velocity
	p.take_damage(12.0, Vector2.LEFT, 600.0)
	check(p.build.hp == 88.0 and p.velocity == velocity_before, "remaining immunity still rejects a follow-up hit")
	await hold_action("jump", 2)
	check(not p.is_on_floor() and p.jumps_left == 0 and p.velocity.y < -400.0, "next real jump consumes the remaining air jump")
	# Reuse the same actor: an earlier airborne hit must not relax grounded stun.
	await ticks(35)
	await grounded_hit("grounded hit after airborne recovery")

	await boot()
	await jump()
	await jump()
	p = game.player
	check(not p.is_on_floor() and p.jumps_left == 0 and p.iframes <= 0.0, "two real jumps exhaust the airborne budget")
	p.take_damage(12.0, Vector2.UP, 180.0)
	check(p.velocity == Vector2(0.0, -180.0), "vertical hit retains its upward impulse")
	await ticks(1)
	check(p.state == Player.State.HURT and p.velocity.y < 0.0 and is_zero_approx(p.velocity.x), "settled horizontal speed cannot cancel rising knockback")
	await ticks(7)
	check(not p.is_on_floor() and p.state == Player.State.LOCOMOTION and p.velocity.y >= 0.0 and p.jumps_left == 0, "vertical airborne recovery preserves an exhausted budget")
	var vy_before := p.velocity.y
	await hold_action("jump", 2)
	check(not p.is_on_floor() and p.jumps_left == 0 and p.velocity.y > vy_before, "recovery cannot supply a third jump")

	await boot()
	check(await enter_empty_room("gap"), "gap room selected for the walked-off ledge fixture")
	p = game.player
	check(p.is_on_floor() and p.iframes <= 0.0, "ledge fixture starts grounded after room-entry immunity expires")
	Input.action_press("move_right")
	var left_ledge := false
	for i in range(90):
		await ticks(1)
		if not p.is_on_floor():
			left_ledge = true
			break
	Input.action_release("move_right")
	print("LEDGE_HURT_ENTRY: pos=", p.position, " floor=", p.is_on_floor(), " coyote=", p.coyote, " jumps=", p.jumps_left)
	# The causeway's near floor ends where its pit begins; read it from the room
	# rather than pinning a number that moves whenever the room is re-laid.
	var ledge_x: float = (game.room.template.platforms[0] as Rect2).end.x
	check(left_ledge and p.position.x > ledge_x - 20.0 and p.position.x < ledge_x + 30.0, "real right input walks off the selected causeway ledge")
	check(p.coyote > 0.0 and p.jumps_left == Content.P_MAX_JUMPS, "damage fixture begins inside real coyote time with the untouched grounded budget")
	var ledge_hp_before := float(p.build.hp)
	p.take_damage(12.0, Vector2.UP, 260.0)
	check(p.state == Player.State.HURT and p.velocity == Vector2(0.0, -260.0), "coyote-time hit retains its full initial upward knockback")
	check(is_equal_approx(float(p.build.hp), ledge_hp_before - 12.0), "coyote-time hit applies full explicit fixture damage")
	for i in range(8):
		if p.state == Player.State.HURT and p.velocity.y < 0.0 and p.coyote <= 0.0:
			break
		await ticks(1)
	check(p.state == Player.State.HURT and p.velocity.y < 0.0 and p.coyote <= 0.0, "coyote expires while real knockback remains committed")
	await hold_action("jump")
	check(p.state == Player.State.HURT, "buffered ledge jump cannot skip the remaining hurt ascent")
	for i in range(8):
		if p.state == Player.State.LOCOMOTION:
			break
		await ticks(1)
	print("LEDGE_HURT_RECOVERY: pos=", p.position, " vy=", p.velocity.y, " coyote=", p.coyote, " jumps=", p.jumps_left, " buffer=", p.jump_buffer)
	check(not p.is_on_floor() and p.state == Player.State.LOCOMOTION and p.jump_buffer > 0.0, "ledge hit reaches airborne recovery with the jump still buffered")
	check(p.jumps_left == Content.P_MAX_JUMPS - 1, "hurt recovery expires the stale grounded jump slot before locomotion")
	await ticks(1)
	check(not p.is_on_floor() and p.velocity.y < -600.0 and p.jumps_left == 0, "first locomotion tick spends the sole remaining air jump")

	await boot()
	check(await enter_empty_room("chamber"), "chamber selected for the real wall-contact fixture")
	p = game.player
	check(p.is_on_floor() and p.iframes <= 0.0, "wall fixture starts grounded after room-entry immunity expires")
	Input.action_press("move_right")
	await hold_action("jump", 20)
	await ticks(1)
	await hold_action("jump", 18)
	var reached_wall_slide := false
	for i in range(90):
		await ticks(1)
		if p.wall_sliding:
			reached_wall_slide = true
			break
		if p.dead:
			break
	Input.action_release("move_right")
	print("WALL_HURT_ENTRY: pos=", p.position, " floor=", p.is_on_floor(), " wall_sliding=", p.wall_sliding, " wall_dir=", p._wall_dir, " jumps=", p.jumps_left)
	check(reached_wall_slide and not p.is_on_floor() and p.position.x > 330.0 and p.position.x < 360.0, "two real jumps and right input reach the chamber wall slide")
	check(p._wall_dir == 1.0 and p.jumps_left == 0, "real wall contact is tracked after both jumps are spent")
	var wall_hp_before := float(p.build.hp)
	p.take_damage(12.0, Vector2.LEFT, 260.0)
	check(p.state == Player.State.HURT and p.velocity == Vector2(-260.0, -91.0), "wall hit retains its full initial away-and-up knockback")
	check(is_equal_approx(float(p.build.hp), wall_hp_before - 12.0), "wall hit applies full explicit fixture damage")
	await hold_action("jump")
	check(p.state == Player.State.HURT and p.velocity.x < 0.0 and p.velocity.y < 0.0, "buffered wall jump cannot skip the initial away knockback")
	for i in range(8):
		if p.state == Player.State.LOCOMOTION:
			break
		await ticks(1)
	print("WALL_HURT_RECOVERY: pos=", p.position, " velocity=", p.velocity, " wall_dir=", p._wall_dir, " jumps=", p.jumps_left, " buffer=", p.jump_buffer)
	check(not p.is_on_floor() and p.state == Player.State.LOCOMOTION and p.position.x < 347.0 and p.jump_buffer > 0.0, "away knockback reaches airborne recovery off the contacted wall")
	check(p._wall_dir == 0.0, "hurt recovery clears wall contact that away knockback left behind")
	await ticks(1)
	check(not p.is_on_floor() and p.velocity.y > 0.0 and absf(p.velocity.x) < 100.0 and p.jumps_left == 0, "first locomotion tick cannot phantom-wall-jump after leaving the wall")
	await finish("AIRBORNE_HURT")
