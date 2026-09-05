extends SceneTree
## Runtime contracts: real scene, input actions and collision-based deflection.
## godot4 --headless --audio-driver Dummy --path . --script res://tests/combat_presence.gd

var checks := 0
var failures := 0
var game: Game

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func press(action: String) -> void:
	Input.action_press(action)
	await ticks(1)
	Input.action_release(action)

func _run() -> void:
	Save.path = "user://combat_presence.json"
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await ticks(2)
	game.ui.start_requested.emit()
	await ticks(3)
	# Isolate focused combat contracts from the room's separate encounter tests.
	for enemy in game.room.enemies:
		enemy.queue_free()
	game.room.enemies.clear()
	await ticks(6)
	game.feedback.set_reduced_motion(true)
	await test_riposte()
	await test_dash_trail()
	await test_riposte_feedback()
	await test_breakable_crypt()
	Input.action_release("attack")
	Input.action_release("parry")
	game.queue_free()
	await ticks(2)
	Feedback.motion_reduced = false
	if FileAccess.file_exists(Save.path):
		DirAccess.remove_absolute(Save.path)
	print("COMBAT_PRESENCE_RESULT: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func deflect() -> void:
	var p := game.player
	var shot := Projectile.new()
	shot.setup("enemy", p.global_position + Vector2(p.facing * 52.0, -5.0), Vector2.ZERO, 10.0, 100.0, 0, 2.0, Content.PAL.special)
	game.projectiles.add_child(shot)
	await press("parry")
	await ticks(3)
	check(shot.team == "player", "real parry input reflects an overlapping hostile projectile")
	shot.queue_free()

func test_riposte() -> void:
	var p := game.player
	await deflect()
	var window = p.get("riposte_time")
	check(window != null and float(window) > 0.0, "confirmed deflection opens a timed riposte opportunity")
	if window == null:
		return
	await press("attack")
	await ticks(1)
	check(p.state == Player.State.ATTACK, "attack input cancels a successful parry into a counterattack")
	check(bool(p.get("_riposte_attack")), "the counterattack is the distinct riposte, not the normal combo")
	check(is_zero_approx(float(p.get("riposte_time"))), "starting the riposte consumes its opportunity once")
	var attack: Dictionary = p.get_meta("atk_def", {})
	check(float(attack.get("damage", 0.0)) > float(Content.COMBO[2].damage), "riposte hits harder than the base combo finisher")
	check(float(attack.get("range", 0.0)) > float(Content.COMBO[2].range), "riposte reaches a deflected opponent")
	# Full-strength target: damage comes from the actual active melee hitbox.
	var target := Enemy.new()
	target.setup(Enemy.Kind.STALKER, p.global_position + Vector2(p.facing * 78.0, 0.0))
	game.world.add_child(target)
	var hp_before := target.hp
	await ticks(10)
	check(target.hp < hp_before, "riposte deals damage through the live attack Area2D")
	check(is_equal_approx(hp_before - target.hp, float(attack.get("damage", 0.0))), "one riposte damages a target only once")
	target.queue_free()
	await ticks(35)
	await press("attack")
	check(not bool(p.get("_riposte_attack")) and p.attack_index == 0, "following attack returns to the normal combo")
	await ticks(35)
	await deflect()
	await ticks(95)
	check(is_zero_approx(float(p.get("riposte_time"))), "unused riposte expires instead of becoming a permanent buff")
	await press("parry")
	await ticks(12)
	check(is_zero_approx(float(p.get("riposte_time"))), "whiffing a parry does not award a counterattack")
	await ticks(32)
	await deflect()
	p.respawn_at(game.room.get_entry_point())
	check(is_zero_approx(float(p.get("riposte_time"))), "room travel discards a banked riposte")
	await ticks(32)
	await deflect()
	await ticks(14)
	p.iframes = 0.0
	p.take_damage(1.0, Vector2.LEFT, 0.0)
	check(is_zero_approx(float(p.get("riposte_time"))), "taking an unblocked hit loses the riposte opportunity")

func test_dash_trail() -> void:
	var p := game.player
	p.respawn_at(Vector2(420.0, Content.FLOOR_Y - Content.P_BODY_H * 0.5))
	await ticks(4)
	game.feedback.set_reduced_motion(false)
	game.feedback._particles.clear()
	# A dash cancel may be requested opposite to the last attack facing.
	p.facing = 1.0
	Input.action_press("move_left")
	Input.action_press("dash")
	await ticks(1)
	Input.action_release("dash")
	Input.action_release("move_left")
	check(p.state == Player.State.DASH and p.facing == -1.0, "dash silhouette faces its actual travel direction")
	await ticks(5)
	var ghosts: Array = game.feedback._particles.filter(func(v): return v.kind == "afterimage")
	check(ghosts.size() >= 3 and ghosts.size() <= 8, "dash leaves a bounded chain of silhouettes, not one static rectangle")
	if ghosts.size() >= 2:
		check(ghosts[0].pos.x > ghosts[-1].pos.x, "dash silhouettes record distinct positions along the path")
	await ticks(42)
	check(game.feedback._particles.filter(func(v): return v.kind == "afterimage").is_empty(), "dash silhouettes expire after movement ends")
	game.feedback.set_reduced_motion(true)
	game.feedback._particles.clear()
	await press("dash")
	await ticks(5)
	check(game.feedback._particles.filter(func(v): return v.kind == "afterimage").is_empty(), "reduced motion suppresses dash echoes")
	await ticks(40)

func test_riposte_feedback() -> void:
	var p := game.player
	p.respawn_at(Vector2(480.0, Content.FLOOR_Y - Content.P_BODY_H * 0.5))
	await ticks(5)
	game.feedback.set_reduced_motion(false)
	game.feedback._particles.clear()
	await deflect()
	var rings: Array = game.feedback._particles.filter(func(v): return v.kind == "parry_ring")
	check(rings.size() == 1 and float(rings[0].radius_to) <= 90.0, "parry halo stays local instead of engulfing both combatants")
	check(game.feedback._particles.filter(func(v): return v.kind == "hitspark").size() <= 16, "successful parry uses one restrained impact burst")
	game.feedback.set_reduced_motion(true)
	game.feedback._particles.clear()
	await press("attack")
	await ticks(5)
	var cuts: Array = game.feedback._particles.filter(func(v): return v.kind == "riposte")
	check(cuts.size() == 1, "a live counterattack emits its own directional cut effect")
	if cuts.size() == 1:
		check(is_equal_approx(cuts[0].radius, float(Content.RIPOSTE.range)), "counterattack visual reach matches its live hitbox")
	check(game.feedback._streams.has("riposte"), "counterattack has a distinct synthesized audio cue")
	await ticks(30)
	check(game.feedback._particles.filter(func(v): return v.kind == "riposte").is_empty(), "counterattack effect cleans itself up")

func test_breakable_crypt() -> void:
	var props = game.room.get("props")
	check(props != null and props.size() >= 3, "the real opening chamber contains breakable crypt objects")
	if props == null or props.size() < 3:
		return
	var p := game.player
	var cells_before := Save.get_cells()
	var score_before := game.score
	var meter_before := p.special
	var hp_before := float(p.build.hp)
	p.build.lifesteal = 10.0
	var urn = props[0]
	var events := [0]
	urn.shattered.connect(func(_pos, _force, _color): events[0] += 1)
	p.respawn_at(urn.global_position + Vector2(-42.0, -27.0))
	p.facing = 1.0
	await ticks(5)
	await press("attack")
	await ticks(15)
	check(urn.broken, "real blade input shatters a nearby crypt object")
	check(events[0] == 1 and not urn.monitorable, "shattered object emits once and retires its hurtbox")
	check(is_equal_approx(p.special, meter_before), "scenery cannot farm Graveflame meter")
	check(is_equal_approx(float(p.build.hp), hp_before), "scenery cannot trigger lifesteal")
	check(Save.get_cells() == cells_before and game.score == score_before, "scenery awards neither cells nor score")
	check(not game.room.exit_open, "breaking scenery never counts as clearing the encounter")
	await ticks(20)
	await press("attack")
	await ticks(20)
	check(events[0] == 1, "rubble cannot shatter repeatedly")
	p.build.lifesteal = 0.0
	var second = props[1]
	var shot := Projectile.new()
	shot.setup("player", second.global_position + Vector2(-50.0, -24.0), Vector2(400.0, 0.0), 26.0, 200.0, 0, 2.0, Content.PAL.special)
	game.projectiles.add_child(shot)
	await ticks(18)
	check(second.broken, "a ranged lance shatters an object through real overlap")
	check(is_instance_valid(shot) and not shot.is_queued_for_deletion(), "scenery does not eat the lance intended for an enemy")
	if is_instance_valid(shot): shot.queue_free()
	var third = props[2]
	p.respawn_at(third.global_position + Vector2(0.0, -200.0))
	await ticks(18)
	await press("attack")
	await ticks(20)
	check(third.broken, "a falling blade input smashes nearby scenery on slam impact")
	check(is_equal_approx(p.special, meter_before), "slam on scenery cannot farm meter")
	for tmpl in Content.ROOM_TEMPLATES + [Content.BOSS_TEMPLATE]:
		var room := Room.new()
		room.setup(tmpl, false, null, 991)
		root.add_child(room)
		var count: int = room.get("props").size()
		check(count > 0 and count <= 18, "crypt dressing is bounded in " + str(tmpl.tag))
		for prop in room.get("props"):
			var supported := false
			for platform: Rect2 in tmpl.platforms:
				if is_equal_approx(prop.position.y, platform.position.y) and prop.position.x >= platform.position.x + 24.0 and prop.position.x <= platform.end.x - 24.0:
					supported = true
			check(supported, "breakable is supported by a real platform in " + str(tmpl.tag))
			check(not (prop.collision_layer & Content.L_WORLD), "dressing cannot block player traversal")
			check(prop.z_index >= room.z_index, "intact props and rubble draw above the opaque backdrop")
		room.queue_free()
		await ticks(1)
