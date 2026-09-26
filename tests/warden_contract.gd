extends "res://tests/harness.gd"
## The Warden's fight contract: poise and hyper-armour, the throne entrance,
## the deeper moveset, the Last Ember, its shots and waves, and the Trial and
## Vow of Haste. Real Boss nodes on a bare floor.

var _floor: StaticBody2D


func run() -> void:
	use_scratch_save("warden_contract")
	_floor = StaticBody2D.new()
	_floor.collision_layer = Content.L_WORLD
	_floor.add_child(Content.rect_shape(Vector2(4000.0, 100.0)))
	_floor.position = Vector2(640.0, Content.FLOOR_Y + 50.0)
	root.add_child(_floor)
	await _test_poise()
	await _test_throne()
	await _test_moveset()
	await _test_phases()
	await _test_shots()
	await _test_trial_and_haste()
	_floor.queue_free()
	await finish("WARDEN")


## A Warden past its intro, standing on the floor at x.
func _fighting_warden(x := 640.0) -> Boss:
	var boss := Boss.new()
	boss.intro_t = 0.01
	root.add_child(boss)
	boss.global_position = Vector2(x, Content.FLOOR_Y - Content.BOSS_H * 0.5)
	await ticks(3)
	return boss


func _test_poise() -> void:
	var boss := await _fighting_warden()
	boss._begin_lunge()
	boss.take_damage(5.0, Vector2.RIGHT, 300.0)
	check(boss.state == Enemy.EState.WINDUP, "a hit never cancels a committed windup")
	for i in range(int(Boss.POISE[Boss.BPhase.ONE])):
		boss.take_damage(5.0, Vector2.RIGHT, 300.0)
	check(boss.is_broken(), "a sustained assault breaks the guard")
	await ticks(10)
	check(float(boss.visual_pose().get("kneel", 0.0)) > 0.9, "a broken guard drops it to one knee")
	check(not boss._atk_area.monitoring, "a broken guard drops the blow in hand")
	var hp_before := boss.hp
	boss.take_damage(10.0, Vector2.RIGHT, 0.0)
	check(hp_before - boss.hp > 10.0, "a broken guard takes extra damage")
	boss.queue_free()
	boss = await _fighting_warden()
	boss._begin_charge()
	boss._do_charge()
	boss.on_parried(Vector2.LEFT)
	check(boss.is_broken() and boss.stagger_t >= Boss.BREAK_TIME - 0.01, "a parry breaks the guard outright")
	boss.queue_free()
	await process_frame


## A stand-in knight the Warden can find by group, standing at x.
func _knight(x: float) -> Node2D:
	var knight := Node2D.new()
	knight.add_to_group("player")
	knight.position = Vector2(x, Content.FLOOR_Y - 27.0)
	return knight


## A throne room with a stand-in knight at x; the room seats its Warden.
func _throne_room(knight_x: float, trial := false) -> Room:
	var knight := _knight(knight_x)
	var room := Room.new()
	room.setup(Content.BOSS_TEMPLATE, true, knight, 11)
	room.trial = trial
	room.add_child(knight)
	root.add_child(room)
	return room


func _test_throne() -> void:
	var room := _throne_room(40.0)
	var boss := room.boss
	await ticks(30)
	check(boss.seated and boss.phase == Boss.BPhase.INTRO, "the Warden waits seated while the knight is far off")
	check(boss.global_position.is_equal_approx(Boss.THRONE_SEAT), "it sits on the throne, not the floor")
	check(boss.visual_pose().get("eye", 1.0) == 0.0, "a dormant Warden's eye is dark")
	get_first_node_in_group("player").position.x = 420.0
	await ticks(2)
	check(not boss.seated, "the knight's approach wakes it")
	var guard := 0
	while boss.phase == Boss.BPhase.INTRO and guard < 180:
		await ticks(1)
		guard += 1
	check(boss.phase == Boss.BPhase.ONE and boss.is_on_floor(), "it steps down off the dais and the fight begins where it lands")
	check(boss.global_position.x < Boss.THRONE_SEAT.x, "it steps toward the knight")
	room.queue_free()
	await process_frame
	room = _throne_room(40.0)
	await ticks(2)
	room.boss.take_damage(4.0, Vector2.RIGHT, 0.0)
	check(not room.boss.seated, "a blow wakes a seated Warden")
	room.queue_free()
	await process_frame


## Runs physics frames until the Warden leaves `from_state`, or 200 frames.
func _until_not(boss: Boss, from_state: int) -> void:
	var guard := 0
	while boss.state == from_state and guard < 200:
		await physics_frame
		guard += 1


func _test_moveset() -> void:
	var boss := await _fighting_warden(400.0)
	boss._history = [Boss.Action.LUNGE, Boss.Action.LUNGE]
	boss._choose_action(null)
	check(boss.action_idx != Boss.Action.LUNGE, "no move comes three times running")
	boss.phase = Boss.BPhase.THREE
	seed(7)
	var strung := false
	for i in range(40):
		boss._history.clear()
		boss._string.clear()
		boss._choose_action(null)
		strung = strung or (boss._string.size() == 2 and boss._string[1] == Boss.Action.FAN)
	check(strung, "the Last Ember strings a lunge into lunge and fan")
	boss.queue_free()
	var knight := _knight(700.0)
	root.add_child(knight)
	boss = await _fighting_warden(400.0)
	var released: Array = []
	var hear := func(_text: String, cue: String, _pos: Vector2): released.append(cue)
	boss.announced.connect(hear)
	var x0 := boss.global_position.x
	boss._begin_slam()
	check(is_equal_approx(boss.slam_x, x0 + (700.0 - x0) * 0.6), "a phase-one leap-slam covers part of the gap, so a sidestep beats it")
	check(boss.visual_pose().has("marker"), "the leap-slam marks where it will land")
	await _until_not(boss, Enemy.EState.WINDUP)
	await _until_not(boss, Enemy.EState.ATTACK)
	check(absf(boss.global_position.x - boss.slam_x) < 12.0, "it comes down on its marker")
	var spent: Dictionary = boss.visual_pose()
	check(spent.get("pant", false) and float(spent.get("sag", 0.0)) > 0.0, "spent after the slam it slumps and pants: the knight's cue")
	boss.phase = Boss.BPhase.TWO
	boss._string = [Boss.Action.FAN]
	boss._start(Boss.Action.LUNGE)
	await _until_not(boss, Enemy.EState.WINDUP)
	await _until_not(boss, Enemy.EState.ATTACK)
	check(boss.state == Enemy.EState.WINDUP and boss.action_idx == Boss.Action.FAN, "an ignited lunge can run straight on into a fan")
	check(boss.st_timer < 0.5 * Boss.LINK_WINDUP + 0.01, "the linked fan comes on a shorter tell")
	await _until_not(boss, Enemy.EState.WINDUP)
	boss.queue_free()
	var wall := StaticBody2D.new()
	wall.collision_layer = Content.L_WORLD
	wall.add_child(Content.rect_shape(Vector2(48.0, 400.0)))
	wall.position = Vector2(1300.0, Content.FLOOR_Y - 200.0)
	root.add_child(wall)
	knight.position.x = 1200.0
	boss = await _fighting_warden(900.0)
	boss.announced.connect(hear)
	boss.facing = 1.0
	boss._begin_charge()
	boss._do_charge()
	await _until_not(boss, Enemy.EState.ATTACK)
	check(boss._dazed and boss.state == Enemy.EState.RECOVER and boss.st_timer > 1.0, "a charge baited into the wall leaves the Warden reeling")
	var unheard: Array = Boss.Action.keys().filter(func(a: String): return not released.has("release_" + a.to_lower()))
	check(unheard.is_empty(), "every move is voiced as it is loosed (unheard: %s)" % str(unheard))
	boss.queue_free()
	wall.queue_free()
	knight.queue_free()
	await process_frame


func _test_phases() -> void:
	var boss := await _fighting_warden()
	var phases: Array = []
	var summons: Array = []
	boss.phase_changed.connect(func(p: int): phases.append(p))
	boss.summon_requested.connect(func(k: int, _pos: Vector2): summons.append(k))
	boss.hp = boss.hp_max * 0.45
	await ticks(1)
	check(boss.phase == Boss.BPhase.TWO and boss._beat == Boss.Beat.ROAR, "ignition opens with a roar")
	check(phases.is_empty() and summons.size() == 2, "the wisps are called at once; the phase lands at the roar's peak")
	var hp_before := boss.hp
	boss.take_damage(10.0, Vector2.RIGHT, 0.0)
	check(boss.hp < hp_before, "the roar still takes blows")
	await ticks(int(Boss.ROAR_TIME * 60.0) + 2)
	check(phases == [2] and boss._beat == Boss.Beat.NONE, "the roar peaks once, then the fight resumes")
	var hot_lunge := boss._timing(0.55, 0.4)
	boss.hp = boss.hp_max * 0.2
	await ticks(1)
	check(boss.phase == Boss.BPhase.THREE and boss._beat == Boss.Beat.EMBER, "the Last Ember begins below 22%")
	check(boss.visual_pose().get("kneel", 0.0) > 0.0, "it drops to one knee")
	hp_before = boss.hp
	boss.take_damage(50.0, Vector2.RIGHT, 0.0)
	check(is_equal_approx(boss.hp, hp_before), "the kneeling, rising Last Ember turns every blow")
	await ticks(int(Boss.EMBER_PEAK * 60.0) + 2)
	var patches := 0
	for node in boss.get_parent().get_children():
		patches += 1 if node is Boss.EmberPatch else 0
	check(phases == [2, 3] and patches >= 4, "it roars and the floor around it catches fire")
	check(boss._timing(0.55, 0.4) < hot_lunge, "the Last Ember fights faster")
	boss.queue_free()
	await process_frame


## Fans never bury a shot short of the knight yet still reach it; slam waves
## run along the floor with a high pair above a standing knight's head.
func _test_shots() -> void:
	var knight := _knight(0.0)
	root.add_child(knight)
	var boss := await _fighting_warden()
	boss.phase = Boss.BPhase.TWO
	var shots: Array = []
	boss.projectile_requested.connect(func(_team, pos, vel, _dmg, _kb, _pierce, _life, color): shots.append([pos, vel, color]))
	var buried := 0
	var reached := 0
	for dx: float in [100.0, 260.0, 600.0, -260.0]:
		knight.position.x = boss.global_position.x + dx
		shots.clear()
		boss._do_fan()
		var hits := false
		for shot in shots:
			var pos: Vector2 = shot[0]
			var vel: Vector2 = shot[1]
			var y_at_knight := pos.y + vel.y * absf(dx) / absf(vel.x)
			buried += 1 if y_at_knight > Content.FLOOR_Y else 0
			hits = hits or (y_at_knight > Content.FLOOR_Y - Content.P_BODY_H - 9.0 and y_at_knight <= Content.FLOOR_Y)
		reached += 1 if hits else 0
	check(buried == 0 and reached == 4, "no fan shot buries itself short of the knight, and one still reaches a grounded knight")
	check(shots[0][2] == Boss.SHOT_COLOR, "the Warden's shots burn ember-bright")
	var waves: Array = []
	boss.wave_requested.connect(func(pos, _vel, _dmg, _life, _style, _color): waves.append(pos))
	shots.clear()
	boss._emit_slam_waves()
	check(waves.size() == 2 and is_equal_approx(waves[0].y, Content.FLOOR_Y - Boss.WAVE_LOW), "the slam's shockwaves run along the floor")
	check(shots.size() == 2 and shots[0][0].y + 9.0 < Content.FLOOR_Y - Content.P_BODY_H, "the ignited high pair flies over a standing knight's head")
	var wave := Projectile.new()
	wave.style = "wave"
	wave.setup("enemy", waves[0], Vector2(-266.0, 0.0), 10.0, 120.0, 0, 1.0, Boss.SHOT_COLOR)
	root.add_child(wave)
	await ticks(3)
	check(wave.rotation == 0.0 and wave.get_node_or_null("Trail") == null, "a slam wave runs upright, without a comet trail")
	var shoulder: Vector2 = boss.visual_pose().shoulder
	var within := true
	for staged: Dictionary in [Boss.WardenArt.SEATED, Boss.WardenArt.KNEEL, Boss.WardenArt.ROAR, Boss.WardenArt.SLUMP]:
		within = within and staged.hand.distance_to(staged.elbow) <= 85.0 and staged.elbow.distance_to(shoulder) <= 85.0 and absf(staged.lean) <= 0.35
	check(within, "every staged pose keeps boss_art_contract's arm and lean limits")
	wave.queue_free()
	boss.queue_free()
	knight.queue_free()
	await process_frame


func _test_trial_and_haste() -> void:
	var room := _throne_room(40.0, true)
	var boss := room.boss
	var summons := [0]
	boss.summon_requested.connect(func(_kind, _pos): summons[0] += 1)
	check(boss.trial and is_equal_approx(boss.hp_max, Content.BOSS_HP * Boss.TRIAL_HP), "the Trial of the Throne hardens the Warden")
	boss._ignite()
	check(summons[0] == 3, "the Trial of the Throne calls a third wisp")
	room.queue_free()
	await process_frame
	Enemy.vows = {"v_haste": true}
	boss = await _fighting_warden()
	boss._begin_lunge()
	check(boss.st_timer < 0.55 and boss._timing(0.55, 0.4) < 0.55, "the Vow of Haste quickens the Warden's tells")
	Enemy.vows = {}
	boss.queue_free()
	await process_frame
