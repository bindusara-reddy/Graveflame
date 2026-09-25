extends "res://tests/harness.gd"
## The Warden's fight contract: poise and hyper-armour, the throne entrance,
## the deeper moveset and the Last Ember. Real Boss nodes on a bare floor.

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


## A throne room with a stand-in knight at x; the room seats its Warden.
func _throne_room(knight_x: float) -> Room:
	var knight := Node2D.new()
	knight.add_to_group("player")
	knight.position = Vector2(knight_x, Content.FLOOR_Y - 27.0)
	var room := Room.new()
	room.setup(Content.BOSS_TEMPLATE, true, knight, 11)
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
