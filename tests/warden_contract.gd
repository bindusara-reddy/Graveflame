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
