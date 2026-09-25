extends "res://tests/harness.gd"
## Runtime contracts: real scene, input actions and collision-based deflection.
## godot4 --headless --audio-driver Dummy --path . --script res://tests/combat_presence.gd

func run() -> void:
	use_scratch_save("combat_presence")
	await load_main_scene(2)
	await start_run(3)
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
	await test_impact_grammar()
	await test_parry_tiers()
	await test_buffers_and_cancels()
	await test_guard_rings_off()
	await test_shots_strike()
	await test_parry_aims()
	test_number_tally()
	await test_ignition_and_clear_beat()
	await test_soft_separation()
	release(["attack", "parry", "move_left"])
	Feedback.motion_reduced = false
	await finish("COMBAT_PRESENCE")

func deflect() -> void:
	var p := game.player
	var shot := Projectile.new()
	shot.setup("enemy", p.global_position + Vector2(p.facing * 52.0, -5.0), Vector2.ZERO, 10.0, 100.0, 0, 2.0, Content.PAL.special)
	game.projectiles.add_child(shot)
	await hold_action("parry")
	await ticks(3)
	check(shot.team == "player", "real parry input reflects an overlapping hostile projectile")
	shot.queue_free()

func test_riposte() -> void:
	var p := game.player
	await deflect()
	check(p.riposte_time > 0.0, "confirmed deflection opens a timed riposte opportunity")
	await hold_action("attack")
	await ticks(1)
	check(p.state == Player.State.ATTACK, "attack input cancels a successful parry into a counterattack")
	check(p._riposte_attack, "the counterattack is the distinct riposte, not the normal combo")
	check(is_zero_approx(p.riposte_time), "starting the riposte consumes its opportunity once")
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
	check(is_equal_approx(hp_before - target.hp, float(attack.get("damage", 0.0)) * p._riposte_mul), "one riposte damages a target only once")
	target.queue_free()
	await ticks(35)
	await hold_action("attack")
	check(not p._riposte_attack and p.attack_index == 0, "following attack returns to the normal combo")
	await ticks(35)
	await deflect()
	await ticks(95)
	check(is_zero_approx(p.riposte_time), "unused riposte expires instead of becoming a permanent buff")
	await hold_action("parry")
	await ticks(12)
	check(is_zero_approx(p.riposte_time), "whiffing a parry does not award a counterattack")
	await ticks(32)
	await deflect()
	p.respawn_at(game.room.get_entry_point())
	check(is_zero_approx(p.riposte_time), "room travel discards a banked riposte")
	await ticks(32)
	await deflect()
	await ticks(14)
	p.iframes = 0.0
	p.take_damage(1.0, Vector2.LEFT, 0.0)
	check(is_zero_approx(p.riposte_time), "taking an unblocked hit loses the riposte opportunity")

func test_dash_trail() -> void:
	var p := game.player
	p.respawn_at(Vector2(420.0, Content.FLOOR_Y - Content.P_BODY_H * 0.5))
	await ticks(4)
	game.feedback.set_reduced_motion(false)
	game.feedback._particles.clear()
	# A dash cancel may be requested opposite to the last attack facing.
	p.facing = 1.0
	Input.action_press("move_left")
	await hold_action("dash")
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
	await hold_action("dash")
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
	await hold_action("attack")
	await ticks(5)
	var cuts: Array = game.feedback._particles.filter(func(v): return v.kind == "riposte")
	check(cuts.size() == 1, "a live counterattack emits its own directional cut effect")
	if cuts.size() == 1:
		check(is_equal_approx(cuts[0].radius, float(Content.RIPOSTE.range)), "counterattack visual reach matches its live hitbox")
	check(game.feedback._streams.has("riposte"), "counterattack has a distinct synthesized audio cue")
	await ticks(30)
	check(game.feedback._particles.filter(func(v): return v.kind == "riposte").is_empty(), "counterattack effect cleans itself up")

## A sturdy stalker a step ahead of the knight, for blows that must land.
func dummy_ahead(dx := 56.0) -> Enemy:
	var p := game.player
	var foe := Enemy.new()
	foe.setup(Enemy.Kind.STALKER, p.global_position + Vector2(p.facing * dx, 0.0))
	foe.hp_max = 400.0
	foe.hp = 400.0
	game.world.add_child(foe)
	return foe

## A blade hit lands on the silhouette's edge with a cut sliver, a shivering
## victim and a freeze; being struck freezes the world too.
func test_impact_grammar() -> void:
	var p := game.player
	p.respawn_at(Vector2(480.0, Content.FLOOR_Y - Content.P_BODY_H * 0.5))
	p.facing = 1.0
	await ticks(5)
	game.feedback.set_reduced_motion(false)
	game.feedback._particles.clear()
	var foe := dummy_ahead()
	var contacts := []
	var probe := func(_dmg, pos, _heavy): contacts.append(pos)
	p.hit_landed.connect(probe)
	await hold_action("attack")
	await ticks(10)
	p.hit_landed.disconnect(probe)
	check(contacts.size() == 1 and contacts[0].x < foe.global_position.x - 4.0, "a blade hit lands on the foe's near edge, not its centre")
	check(game.feedback._particles.any(func(v): return v.kind == "cut"), "a blade hit leaves a cut sliver along the swing")
	check(foe.has_meta("jolt_until_usec"), "the struck foe shivers through the freeze")
	foe.queue_free()
	await ticks(30)
	p.iframes = 0.0
	p.take_damage(1.0, Vector2.LEFT, 100.0)
	check(game.feedback._hit_stop_active, "being struck freezes the world")
	check(game.feedback.vignette_edge(Game.VIGNETTE_EDGE) != Game.VIGNETTE_EDGE, "being struck flushes the vignette edge")
	await ticks(40)
	game.feedback.set_reduced_motion(true)

## A deflect in the window's first frames is perfect, a late one is plain, and
## a whiff holds the stance a beat past the window.
func test_parry_tiers() -> void:
	var p := game.player
	p.respawn_at(Vector2(480.0, Content.FLOOR_Y - Content.P_BODY_H * 0.5))
	await ticks(40)
	p.special = 0.0
	await deflect()
	check(is_equal_approx(p._riposte_mul, Player.PERFECT_RIPOSTE_MUL), "a deflect in the window's first frames is perfect")
	check(p.special >= Player.PERFECT_PARRY_METER, "a perfect parry pays the larger meter")
	await ticks(100)
	await hold_action("parry")
	await ticks(5)
	var shot := Projectile.new()
	shot.setup("enemy", p.global_position + Vector2(p.facing * 52.0, -5.0), Vector2.ZERO, 10.0, 100.0, 0, 2.0, Content.PAL.special)
	game.projectiles.add_child(shot)
	await ticks(3)
	check(shot.team == "player" and is_equal_approx(p._riposte_mul, 1.0), "a late deflect is an ordinary parry")
	shot.queue_free()
	await ticks(100)
	await hold_action("parry")
	await ticks(12)
	check(p.state == Player.State.PARRY and not p._parry_area.monitoring, "a whiffed parry holds its stance past the window")
	await ticks(8)
	check(p.state == Player.State.LOCOMOTION, "a whiffed parry lets go after its short lag")

## Ticks until `done` holds or `limit` frames pass; true when it held.
func ticks_until(done: Callable, limit := 60) -> bool:
	for i in range(limit):
		if done.call():
			return true
		await ticks(1)
	return done.call()

## Presses made mid-move are honoured once the move allows; a queued swing
## links in halfway through recovery and turns to the held direction.
func test_buffers_and_cancels() -> void:
	var p := game.player
	p.respawn_at(Vector2(480.0, Content.FLOOR_Y - Content.P_BODY_H * 0.5))
	p.facing = 1.0
	await ticks(80)
	await hold_action("attack")
	await ticks_until(func(): return p.atk_phase == "recover")
	await hold_action("parry")
	check(p.state == Player.State.PARRY, "a parry pressed in blade recovery cancels into the parry")
	await ticks(40)
	await hold_action("attack")
	Input.action_press("move_left")
	await hold_action("attack")
	var cut: Dictionary = Content.COMBO[0]
	var linked: bool = await ticks_until(func(): return p.attack_index == 1, int((cut.startup + cut.active + cut.recover * 0.5) * 60.0) + 2)
	Input.action_release("move_left")
	check(linked, "a queued swing links in halfway through the cut's recovery")
	check(p.facing == -1.0, "a chained swing turns to the held direction")
	await ticks(60)
	await hold_action("dash")
	await ticks(7)
	await hold_action("parry")
	await ticks(2)
	check(p.state == Player.State.PARRY, "a parry pressed late in a dash flows out of it")
	await ticks(40)
	p.build.hp = float(p.build.max_hp) - 20.0
	await hold_action("attack")
	await ticks_until(func(): return p.atk_phase == "recover" and p.atk_time < 0.06)
	await hold_action("heal")
	await ticks_until(func(): return p.state != Player.State.ATTACK and p.state != Player.State.LOCOMOTION, 20)
	check(p.state == Player.State.HEAL, "a flask pressed during a swing is drunk when it ends")
	await ticks(40)

## A foe whose every blow is caught on its guard, as a brute's shield reports it.
class Guard extends Node2D:
	var last_hit_blocked := true
	var blows := 0
	func take_damage(_amount: float, _dir: Vector2, _knock: float, _poise := 1.0) -> void:
		blows += 1

## A blow caught on a guard rings off: no hit feedback, meter or lifesteal,
## and the knight is thrown back off the shield.
func test_guard_rings_off() -> void:
	var p := game.player
	p.respawn_at(Vector2(480.0, Content.FLOOR_Y - Content.P_BODY_H * 0.5))
	p.facing = 1.0
	await ticks(80)
	var guard := Guard.new()
	var box := Area2D.new()
	box.collision_layer = Content.L_ENEMY_HURT
	box.add_child(Content.rect_shape(Vector2(40.0, 54.0)))
	box.set_meta("team", "enemy")
	box.set_meta("owner", guard)
	box.set_meta("owner_id", guard.get_instance_id())
	guard.add_child(box)
	game.world.add_child(guard)
	guard.global_position = p.global_position + Vector2(50.0, 0.0)
	p.special = 0.0
	p.build.lifesteal = 10.0
	p.build.hp = float(p.build.max_hp) - 30.0
	var hp_before := float(p.build.hp)
	var landed := [0]
	var probe := func(_dmg, _pos, _heavy): landed[0] += 1
	p.hit_landed.connect(probe)
	await hold_action("attack")
	await ticks_until(func(): return guard.blows > 0, 20)
	p.hit_landed.disconnect(probe)
	check(guard.blows == 1 and landed[0] == 0, "a blow on a raised guard gives no flesh-hit feedback")
	check(is_zero_approx(p.special) and is_equal_approx(float(p.build.hp), hp_before), "a guarded blow pays neither meter nor lifesteal")
	check(p.velocity.x < 0.0, "a guarded blow throws the knight back off the shield")
	p.build.lifesteal = 0.0
	guard.queue_free()
	await ticks(30)

## A lance that lands reports its strike for feedback, and any shot breaks
## on the stonework instead of passing through it.
func test_shots_strike() -> void:
	var p := game.player
	p.respawn_at(Vector2(480.0, Content.FLOOR_Y - Content.P_BODY_H * 0.5))
	p.facing = 1.0
	await ticks(20)
	var foe := dummy_ahead(160.0)
	var seen := []
	var lance := Projectile.new()
	lance.setup("player", p.global_position + Vector2(40.0, -5.0), Vector2(600.0, 0.0), 20.0, 100.0, 0, 1.0, Content.PAL.special)
	lance.struck.connect(func(_pos, _dir, _color, what): seen.append(what))
	game.projectiles.add_child(lance)
	await ticks_until(func(): return not seen.is_empty(), 30)
	check(seen == ["foe"], "a lance that lands reports its strike")
	foe.queue_free()
	var bolt := Projectile.new()
	bolt.setup("enemy", Vector2(p.global_position.x + 120.0, Content.FLOOR_Y - 60.0), Vector2(0.0, 500.0), 5.0, 100.0, 0, 2.0, Color("ff6b6b"))
	bolt.struck.connect(func(_pos, _dir, _color, what): seen.append(what))
	var gone := [false]
	bolt.tree_exiting.connect(func(): gone[0] = true)
	game.projectiles.add_child(bolt)
	await ticks_until(func(): return gone[0], 40)
	check(seen.back() == "stone" and gone[0], "a shot breaks on the stonework")

## A parried shot flies back at the shooter that loosed it, and a parried
## swing drives its attacker away from the knight.
func test_parry_aims() -> void:
	var p := game.player
	p.respawn_at(Vector2(480.0, Content.FLOOR_Y - Content.P_BODY_H * 0.5))
	p.facing = 1.0
	await ticks(60)
	var shooter := dummy_ahead(220.0)
	shooter.global_position.y -= 140.0
	var shot := Projectile.new()
	shot.setup("enemy", shooter.global_position, Vector2.ZERO, 10.0, 100.0, 0, 2.0, Content.PAL.special)
	shot.global_position = p.global_position + Vector2(52.0, -5.0)
	game.projectiles.add_child(shot)
	await hold_action("parry")
	await ticks(3)
	var to_shooter := (shooter.global_position - shot.global_position).normalized()
	check(shot.team == "player" and shot.vel.normalized().dot(to_shooter) > 0.9, "a parried shot flies back at the foe that loosed it")
	shot.queue_free()
	shooter.queue_free()
	await ticks(60)
	var swinger := dummy_ahead(44.0)
	swinger._arm(20.0)
	await hold_action("parry")
	await ticks(3)
	check(swinger._last_hit_dir.x > 0.0 and swinger.state == Enemy.EState.STAGGER, "a parried swing drives its attacker away and staggers it")
	swinger.queue_free()
	await ticks(30)

## Blows on one spot in quick succession add up in one number.
func test_number_tally() -> void:
	game.feedback._particles.clear()
	var at := Vector2(600.0, 300.0)
	game.feedback.damage_number(at, 12.0, "hit")
	game.feedback.damage_number(at + Vector2(10.0, 0.0), 16.0, "hit")
	var numbers: Array = game.feedback._particles.filter(func(v): return v.kind == "number")
	check(numbers.size() == 1 and numbers[0].text == "28", "blows on one foe add up in one damage number")

## Ignition throws close foes clear and sets them alight; a cleared chamber
## eases the world into slow motion.
func test_ignition_and_clear_beat() -> void:
	var p := game.player
	p.respawn_at(Vector2(480.0, Content.FLOOR_Y - Content.P_BODY_H * 0.5))
	p.facing = 1.0
	await ticks(40)
	var foe := dummy_ahead(80.0)
	p.special = p.max_special
	await hold_action("ignite")
	await ticks(2)
	check(foe.velocity.x > 0.0 and foe.burn_time > 0.0, "ignition throws a close foe clear and sets it alight")
	foe.queue_free()
	await ticks(20)
	game.feedback.set_reduced_motion(false)
	game.room.cleared.emit("test chamber")
	await ticks(12)
	check(Engine.time_scale < 1.0, "a cleared chamber's last kill eases into slow motion")
	game.feedback.end_slow_motion()
	game.feedback.set_reduced_motion(true)

## The knight is eased out of a foe it stands in, and a swing's lunge stops
## short against a foe already at the blade.
func test_soft_separation() -> void:
	var p := game.player
	p.respawn_at(Vector2(480.0, Content.FLOOR_Y - Content.P_BODY_H * 0.5))
	p.facing = 1.0
	await ticks(40)
	p.iframes = 5.0
	var foe := dummy_ahead(10.0)
	foe.cd = 99.0
	await ticks(20)
	var gap := (Content.P_BODY_W + float(foe.data.w)) * 0.5
	check(absf(p.global_position.x - foe.global_position.x) >= gap - 1.0, "the knight is eased out of a foe it stands in")
	p.facing = signf(foe.global_position.x - p.global_position.x)
	await hold_action("attack")
	check(absf(p.velocity.x) <= float(Content.COMBO[0].lunge) * 0.2 + 1.0, "a swing's lunge stops short against a foe already at the blade")
	foe.queue_free()
	p.iframes = 0.0
	await ticks(30)

func test_breakable_crypt() -> void:
	var props := game.room.props
	check(props.size() >= 3, "the real opening chamber contains breakable crypt objects")
	if props.size() < 3:
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
	await hold_action("attack")
	await ticks(15)
	check(urn.broken, "real blade input shatters a nearby crypt object")
	check(events[0] == 1 and not urn.monitorable, "shattered object emits once and retires its hurtbox")
	check(is_equal_approx(p.special, meter_before), "scenery cannot farm Graveflame meter")
	check(is_equal_approx(float(p.build.hp), hp_before), "scenery cannot trigger lifesteal")
	check(Save.get_cells() == cells_before and game.score == score_before, "scenery awards neither cells nor score")
	check(not game.room.exit_open, "breaking scenery never counts as clearing the encounter")
	await ticks(20)
	await hold_action("attack")
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
	await hold_action("attack")
	await ticks(20)
	check(third.broken, "a falling blade input smashes nearby scenery on slam impact")
	check(is_equal_approx(p.special, meter_before), "slam on scenery cannot farm meter")
	for tmpl in Content.ROOM_TEMPLATES + [Content.BOSS_TEMPLATE]:
		var room := Room.new()
		room.setup(tmpl, false, null, 991)
		root.add_child(room)
		var count: int = room.props.size()
		check(count > 0 and count <= 18, "crypt dressing is bounded in " + str(tmpl.tag))
		for prop in room.props:
			var supported := false
			for platform: Rect2 in tmpl.platforms:
				if is_equal_approx(prop.position.y, platform.position.y) and prop.position.x >= platform.position.x + 24.0 and prop.position.x <= platform.end.x - 24.0:
					supported = true
			check(supported, "breakable is supported by a real platform in " + str(tmpl.tag))
			check(not (prop.collision_layer & Content.L_WORLD), "dressing cannot block player traversal")
			check(prop.z_index >= room.z_index, "intact props and rubble draw above the opaque backdrop")
		room.queue_free()
		await ticks(1)
