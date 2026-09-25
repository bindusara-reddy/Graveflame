extends "res://tests/harness.gd"
## Encounter contracts: how creatures take a blow (poise, a closed melee box,
## a guard that rings), how they arrive (spawn grace, clear slots) and how a
## chamber's waves are planned. Headless, on a bare floor with a stand-in knight.
##   godot4 --headless --path . --script res://tests/encounter_contract.gd

var _floor: StaticBody2D
var _knight: Node2D


func run() -> void:
	use_scratch_save("encounter_contract")
	_build_arena()
	await _test_interrupted_swing_disarms()
	await _test_poise()
	await _test_spawn_grace()
	_clear_arena()
	await finish("ENCOUNTER")


## A floor across the chamber and a stand-in knight the creatures can find.
func _build_arena() -> void:
	_floor = StaticBody2D.new()
	_floor.collision_layer = Content.L_WORLD
	_floor.add_child(Content.rect_shape(Vector2(4000.0, 100.0)))
	_floor.position = Vector2(640.0, Content.FLOOR_Y + 50.0)
	root.add_child(_floor)
	_knight = Node2D.new()
	_knight.add_to_group("player")
	_knight.global_position = Vector2(400.0, Content.FLOOR_Y - 27.0)
	root.add_child(_knight)


func _clear_arena() -> void:
	_floor.queue_free()
	_knight.queue_free()


## A live creature standing on the floor at x, settled for a couple of frames.
func _foe(kind: int, x: float, mods: Dictionary = {}) -> Enemy:
	var foe := Enemy.new()
	foe.setup(kind, Vector2(x, Content.FLOOR_Y - 40.0), mods)
	root.add_child(foe)
	await ticks(2)
	return foe


## A swing cut short must not leave a live melee box behind: a parry against
## it would deflect a strike that is no longer coming.
func _test_interrupted_swing_disarms() -> void:
	var stalker := await _foe(Enemy.Kind.STALKER, 450.0)
	stalker._spawn_grace = 0.0
	stalker._begin_windup()
	stalker.st_timer = 0.0
	await ticks(2)
	check(stalker.state == Enemy.EState.ATTACK and bool(stalker._atk_area.get_meta("attack_active")), "the stalker's swing arms its melee box")
	stalker.take_damage(5.0, Vector2.LEFT, 100.0)
	check(stalker.state == Enemy.EState.STAGGER, "a blow mid-swing staggers a stalker")
	check(not bool(stalker._atk_area.get_meta("attack_active")) and not stalker._atk_area.monitoring, "a staggered swing closes its melee box")
	check(stalker.cd >= float(stalker.data.cd) * 0.5 - 0.01, "a called-off swing waits out half a cooldown")
	await ticks(30)
	check(not bool(stalker._atk_area.get_meta("attack_active")), "the melee box stays closed after the stagger")
	stalker.queue_free()
	await ticks(1)


## Brutes hold a committed windup through a blow; a full combo breaks the
## guard; a parry always staggers; the shield reports the blows it takes.
func _test_poise() -> void:
	var brute := await _foe(Enemy.Kind.BRUTE, 450.0)
	brute.facing = -1.0
	brute.take_damage(5.0, Vector2.RIGHT, 100.0)
	check(brute.last_hit_blocked and is_equal_approx(brute.hp, brute.hp_max), "a frontal blow rings off the brute's shield")
	brute.take_damage(5.0, Vector2.LEFT, 100.0)
	check(not brute.last_hit_blocked and brute.hp < brute.hp_max, "a blow from behind lands")
	await ticks(70)
	brute._begin_windup()
	brute.st_timer = float(brute.data.windup) * 0.3
	brute.take_damage(1.0, Vector2.LEFT, 100.0)
	check(brute.state == Enemy.EState.WINDUP, "a committed brute holds its windup through a blow")
	brute.take_damage(1.0, Vector2.LEFT, 100.0, 3.0)
	check(brute.state == Enemy.EState.STAGGER and brute._vulnerable_t > 0.0, "a worn-through guard breaks into an opening")
	var before := brute.hp
	brute.take_damage(8.0, Vector2.LEFT, 0.0)
	check(is_equal_approx(before - brute.hp, 8.0 * Enemy.BREAK_DAMAGE_MUL), "a broken guard takes harder blows")
	await ticks(80)
	brute._begin_windup()
	brute.st_timer = float(brute.data.windup) * 0.3
	brute.on_parried(Vector2.RIGHT)
	check(brute.state == Enemy.EState.STAGGER, "a parry staggers even a committed brute")
	var stalker := await _foe(Enemy.Kind.STALKER, 700.0)
	stalker._begin_windup()
	stalker.st_timer = 0.05
	stalker.take_damage(1.0, Vector2.LEFT, 100.0)
	check(stalker.state == Enemy.EState.STAGGER, "fodder has no poise: any blow interrupts it")
	brute.queue_free()
	stalker.queue_free()
	await ticks(1)


## A creature that lands beside the knight waits out its grace before striking.
func _test_spawn_grace() -> void:
	var stalker := await _foe(Enemy.Kind.STALKER, _knight.global_position.x + 40.0)
	await ticks(20)
	check(stalker.state != Enemy.EState.WINDUP, "a fresh spawn does not wind up on its first frames")
	await ticks(50)
	check(stalker.state == Enemy.EState.WINDUP or stalker.state == Enemy.EState.ATTACK, "after its grace the spawn attacks")
	stalker.queue_free()
	await ticks(1)
