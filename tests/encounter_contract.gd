extends "res://tests/harness.gd"
## Encounter contracts: how creatures take a blow (poise, a closed melee box,
## a guard that rings), how they arrive (spawn grace, clear slots) and how a
## chamber's waves are planned. Headless, on a bare floor with a stand-in knight.
##   godot4 --headless --path . --script res://tests/encounter_contract.gd

const SfxSynth := preload("res://scripts/sfx_synth.gd")

var _floor: StaticBody2D
var _knight: Node2D


func run() -> void:
	use_scratch_save("encounter_contract")
	_build_arena()
	await _test_interrupted_swing_disarms()
	await _test_poise()
	await _test_spawn_grace()
	await _test_wisp_skirmishes()
	await _test_bomber_blast()
	await _test_oaths()
	await _test_sexton_tolls()
	_clear_arena()
	await _test_pits()
	await _test_toll_ends_with_its_floor()
	await _test_ledge_drop()
	_test_wave_plan()
	_test_sexton_plan()
	await _test_room_plan()
	await finish("ENCOUNTER")


## A toll as the game spawns it from a sexton's wave_requested arguments.
func _toll(args: Array) -> Projectile:
	var wave := Projectile.new()
	wave.style = args[4]
	wave.setup("enemy", args[0], args[1], args[2], 120.0, 0, args[3], args[5])
	root.add_child(wave)
	return wave


## A sexton backs away from a close knight, voices its raised bell, and its
## toll rolls both ways along the floor, low enough to hop and parried home
## like any shot.
func _test_sexton_tolls() -> void:
	var sexton := await _foe(Enemy.Kind.SEXTON, _knight.global_position.x + 120.0)
	var start := sexton.global_position.x
	await ticks(30)
	check(sexton.global_position.x > start + 20.0, "a sexton backs away from a close knight")
	var tells: Array = []
	var tolls: Array = []
	sexton.telegraphed.connect(func(kind: String, _pos: Vector2, _elite: bool): tells.append(kind))
	sexton.wave_requested.connect(func(pos, vel, dmg, life, style, color): tolls.append([pos, vel, dmg, life, style, color]))
	sexton.global_position.x = _knight.global_position.x + 300.0
	sexton._begin_windup()
	check(tells == ["sexton"] and SfxSynth.LEVELS.has("tell_" + tells[0]), "the sexton's raised bell is voiced")
	sexton.st_timer = 0.0
	await ticks(2)
	check(tolls.size() == 2 and tolls[0][1].x * tolls[1][1].x < 0.0 and tolls.all(func(a): return a[1].y == 0.0), "its toll rolls out both ways along the floor")
	var toward: Array = tolls[0] if tolls[0][1].x < 0.0 else tolls[1]
	var crest: float = Content.FLOOR_Y - toward[0].y + 12.0
	check(crest < 40.0 and crest > 0.0, "the toll hugs the floor, a hop clears it (crest %d px)" % roundi(crest))
	var wave := _toll(toward)
	var from: Vector2 = wave.global_position
	await ticks(10)
	check(wave.global_position.x < from.x - 40.0 and is_equal_approx(wave.global_position.y, from.y), "the toll travels along the floor toward the knight")
	check(wave.get_meta("attack_kind") == "projectile" and wave.monitorable, "a parry can catch the toll like any shot")
	wave.reflect(Vector2.RIGHT)
	await ticks(60)
	check(sexton.hp < sexton.hp_max, "a parried toll rolls home into its sexton")
	if is_instance_valid(wave):
		wave.queue_free()
	sexton.queue_free()
	await ticks(1)


## A toll stops where its floor ends: at a pit's lip and at the chamber wall.
## A sexton cut down comes apart along the blow like any creature.
func _test_toll_ends_with_its_floor() -> void:
	var room := _empty_room("gap", Vector2(1000.0, Content.FLOOR_Y - 27.0))
	var lip := _toll([Vector2(560.0, Content.FLOOR_Y - Enemy.TOLL_LIFT), Vector2(340.0, 0.0), 10.0, 1.5, "toll", Content.TOLL_COLOR])
	var wall := _toll([Vector2(-100.0, Content.FLOOR_Y - Enemy.TOLL_LIFT), Vector2(-340.0, 0.0), 10.0, 1.5, "toll", Content.TOLL_COLOR])
	var open := _toll([Vector2(900.0, Content.FLOOR_Y - Enemy.TOLL_LIFT), Vector2(340.0, 0.0), 10.0, 1.5, "toll", Content.TOLL_COLOR])
	await ticks(24)
	check(not is_instance_valid(lip), "a toll stops at a pit's lip")
	check(not is_instance_valid(wall), "a toll stops at the chamber wall")
	check(is_instance_valid(open) and open.global_position.x > 1000.0, "a toll rolls on while floor lies ahead")
	open.queue_free()
	room._spawn_enemy(Enemy.Kind.SEXTON, Vector2(1100.0, Content.FLOOR_Y - 40.0))
	await ticks(2)
	room.enemies[-1].take_damage(99999.0, Vector2.LEFT, 0.0)
	check(room.get_children().any(func(n): return n.get_script() == Room.Severed), "a felled sexton comes apart along the blow")
	await _free_room(room)


## Chambers climb steadily, open with their newcomer, stage each set piece
## once per descent and keep generated waves readable.
func _test_wave_plan() -> void:
	var sizes: Array = []
	for idx in range(Content.ROOMS_BEFORE_BOSS + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = 40 + idx
		var total := 0
		for wave: Array in Content.generate_waves(idx, rng):
			total += wave.size()
			var flyers := wave.count(Content.EnemyKind.WISP) + wave.count(Content.EnemyKind.CROW)
			check(flyers <= 2, "room %d: no generated wave carries more than two flyers" % idx)
		sizes.append(total)
	for idx in range(1, sizes.size()):
		check(int(sizes[idx]) > int(sizes[idx - 1]), "room %d holds more foes than the one before (%s)" % [idx, sizes])
	for kind in Content.DEBUTS:
		var room := int(Content.DEBUTS[kind])
		if room >= Content.OPENING_WAVES.size():
			var opener: Array = Content.generate_waves(room, RandomNumberGenerator.new())[0]
			check(opener == [kind, Content.EnemyKind.STALKER], "room %d opens with its newcomer beside a stalker" % room)
	for run_seed in [1, 2, 3, 77, 4242]:
		var staged := {}
		for idx in range(Content.ROOMS_BEFORE_BOSS + 1):
			var piece: Dictionary = Content.set_piece_for(idx, run_seed)
			if piece.is_empty():
				continue
			check(idx >= int(piece.from_room), "%s never comes before room %d" % [piece.name, piece.from_room])
			staged[piece.name] = int(staged.get(piece.name, 0)) + 1
			var waves := Content.generate_waves(idx, RandomNumberGenerator.new(), piece)
			check(waves[-1] == piece.kinds, "a chamber's set piece is its final wave")
		check(staged.size() == Content.SET_PIECES.size() and staged.values().max() == 1, "seed %d stages every set piece exactly once" % run_seed)


## Sextons toll from their debut chamber on and never before; a chamber holds
## at most one a wave and two in all, one where it debuts.
func _test_sexton_plan() -> void:
	var debut := int(Content.DEBUTS[Content.EnemyKind.SEXTON])
	var early := 0
	var crowded := 0
	var later := 0
	for run_seed in range(40):
		for idx in range(Content.ROOMS_BEFORE_BOSS + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = run_seed * 31 + idx
			var in_room := 0
			for wave: Array in Content.generate_waves(idx, rng, Content.set_piece_for(idx, run_seed)):
				var n := wave.count(Content.EnemyKind.SEXTON)
				crowded += 1 if n > 1 else 0
				in_room += n
			early += in_room if idx < debut else 0
			crowded += 1 if in_room > (1 if idx == debut else 2) else 0
			later += in_room if idx > debut else 0
	check(early == 0, "no sexton tolls before chamber %d" % debut)
	check(crowded == 0, "one sexton a wave, two a chamber, one where it debuts")
	check(later > 0, "the chambers after its debut still call sextons")


## A live chamber names its newcomer, keeps its first wave clear of the entry,
## and the last chamber before the throne always fields a champion.
func _test_room_plan() -> void:
	var lessons: Array = []
	var room := Room.new()
	var stand_in := Node2D.new()
	root.add_child(stand_in)
	room.setup(Content.ROOM_TEMPLATES[1], false, stand_in, 11)
	room.room_index = Content.DEBUTS[Content.EnemyKind.BOMBER]
	room.lesson_requested.connect(func(id: String): lessons.append(id))
	root.add_child(room)
	check(lessons.has("debut_bomber") and Content.HINTS.has("debut_bomber"), "a chamber names its newcomer with a lesson")
	for foe in room.enemies:
		check(foe.global_position.distance_to(room.get_entry_point()) >= Room.SPAWN_CLEARANCE, "the first wave lands clear of the entry")
	room.queue_free()
	# Every wave of the sexton's debut chamber, called in turn, names it once.
	lessons.clear()
	var tolled := Room.new()
	tolled.setup(Content.ROOM_TEMPLATES[1], false, stand_in, 11)
	tolled.room_index = Content.DEBUTS[Content.EnemyKind.SEXTON]
	tolled.lesson_requested.connect(func(id: String): lessons.append(id))
	root.add_child(tolled)
	for w in range(1, tolled.wave_count()):
		tolled._wave_index = w
		tolled._spawn_wave()
	check(lessons.count("debut_sexton") == 1 and Content.HINTS.has("debut_sexton"), "the sexton's debut chamber teaches its lesson once")
	tolled.queue_free()
	for run_seed in [5, 6, 7]:
		var last := Room.new()
		last.setup(Content.ROOM_TEMPLATES[2], false, stand_in, run_seed)
		last.room_index = Content.ROOMS_BEFORE_BOSS
		last.run_seed = run_seed
		root.add_child(last)
		check(last._elite_slot.x == last.wave_count() - 1, "the last chamber's final wave carries a champion")
		last.queue_free()
	stand_in.queue_free()
	await ticks(1)


## Each oath does what its name promises.
func _test_oaths() -> void:
	var warded := await _foe(Enemy.Kind.STALKER, 900.0, { "elite": true, "oath": "warded" })
	for i in range(Enemy.WARD_RUNES):
		warded.take_damage(5.0, Vector2.LEFT, 0.0)
	check(warded.last_hit_blocked and is_equal_approx(warded.hp, warded.hp_max), "a warded elite's runes swallow its first blows")
	warded.take_damage(5.0, Vector2.LEFT, 0.0)
	check(warded.hp < warded.hp_max, "with its runes spent, a warded elite is hurt")
	warded.queue_free()
	var twinned := await _foe(Enemy.Kind.STALKER, 900.0, { "elite": true, "oath": "twinned" })
	var twins: Array = []
	twinned.twin_requested.connect(func(kind: int, _pos: Vector2): twins.append(kind))
	twinned.take_damage(twinned.hp_max * 0.6, Vector2.LEFT, 0.0)
	twinned.take_damage(1.0, Vector2.LEFT, 0.0)
	check(twins == [Enemy.Kind.STALKER], "a twinned elite splits once, at half health")
	twinned.queue_free()
	var kindled := await _foe(Enemy.Kind.STALKER, 1000.0, { "elite": true, "oath": "kindled" })
	kindled._spawn_grace = 0.0
	kindled.apply_burn(10.0, 3.0)
	check(is_zero_approx(kindled.burn_time), "a kindled elite cannot be set alight")
	await ticks(60)
	var fires := root.get_children().filter(func(n): return n.get_script() == Enemy.GroundFire)
	check(not fires.is_empty() and fires.all(func(f): return f.bite > 0.0), "a kindled elite sheds burning ground as it walks")
	kindled.queue_free()
	await ticks(1)


## An empty copy of the tagged chamber (no waves), with the stand-in knight at
## `knight_at`. Creatures are then placed by hand through the room itself.
func _empty_room(tag: String, knight_at: Vector2) -> Room:
	var tmpl: Dictionary = Content.ROOM_TEMPLATES.filter(func(t): return t.tag == tag)[0].duplicate(true)
	tmpl.slots = []
	_knight = Node2D.new()
	_knight.add_to_group("player")
	_knight.global_position = knight_at
	root.add_child(_knight)
	var room := Room.new()
	room.setup(tmpl, false, _knight, 7)
	room.room_index = 3
	root.add_child(room)
	return room


func _free_room(room: Room) -> void:
	room.queue_free()
	_knight.queue_free()
	await ticks(1)


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


## Wisps close on a distant knight and ride a line above their head.
func _test_wisp_skirmishes() -> void:
	var wisp := await _foe(Enemy.Kind.WISP, 1150.0)
	wisp.global_position.y = 250.0
	var start_x := wisp.global_position.x
	await ticks(180)
	check(start_x - wisp.global_position.x > 150.0, "a wisp closes on a distant knight (moved %d px)" % roundi(start_x - wisp.global_position.x))
	check(absf(wisp._wisp_y - (_knight.global_position.y - Enemy.WISP_ALTITUDE)) < 60.0, "a wisp's line follows the knight's height")
	wisp.global_position.x = Content.ROOM_LEFT - 300.0
	await ticks(2)
	check(wisp.global_position.x >= Enemy.FLYER_LEFT, "flyers stay inside the chamber's walls")
	wisp.queue_free()
	await ticks(1)


## A burnt-down fuse is the bomber's own doing; the creatures its blast kills
## are the knight's.
func _test_bomber_blast() -> void:
	var bomber := await _foe(Enemy.Kind.BOMBER, 900.0)
	var stalker := await _foe(Enemy.Kind.STALKER, 940.0)
	stalker.hp = 5.0
	var scores := {}
	bomber.died.connect(func(s: int): scores["bomber"] = s)
	stalker.died.connect(func(s: int): scores["stalker"] = s)
	bomber._bomb_armed = true
	bomber._begin_windup()
	var ring_full := 0.0
	for i in range(80):
		if bomber.dead:
			break
		ring_full = 1.0 - bomber._fuse_t / bomber._fuse_total
		await ticks(1)
	check(bomber.dead and int(scores.get("bomber", -1)) == 0, "a bomber whose fuse burns down earns the knight nothing")
	check(ring_full > 0.95, "the fuse ring completes before the blast")
	check(stalker.dead and int(scores.get("stalker", 0)) > 0, "a creature caught in the blast is the knight's kill")
	await ticks(1)


## Hoppers do not leap into pits; a creature the knight knocks onto the
## spikes is their kill; one that blunders in is cleared away quietly.
func _test_pits() -> void:
	var room := _empty_room("gap", Vector2(1000.0, Content.FLOOR_Y - 27.0))
	room._spawn_enemy(Enemy.Kind.HOPPER, Vector2(540.0, Content.FLOOR_Y - 40.0))
	var hopper: Enemy = room.enemies[-1]
	await ticks(180)
	check(not hopper.dead and hopper.global_position.x < 620.0, "a hopper waits at the lip instead of leaping into the pit")
	var deaths: Array = []
	var called: Array = []
	room.enemy_died.connect(func(score: int, _pos: Vector2, _tier: int, _color: Color, _kind: String): deaths.append(score))
	room.enemy_announced.connect(func(text: String, _cue: String, _pos: Vector2): called.append(text))
	hopper.take_damage(1.0, Vector2.RIGHT, 700.0)
	await ticks(60)
	check(not is_instance_valid(hopper) and deaths.size() == 1 and int(deaths[0]) > 0, "a creature knocked onto the spikes is the knight's kill")
	check(called.has("RING OUT"), "a ring-out is called out")
	room._spawn_enemy(Enemy.Kind.STALKER, Vector2(740.0, Content.FLOOR_Y - 40.0))
	await ticks(60)
	check(deaths.size() == 2 and int(deaths[1]) == 0, "a creature that falls in untouched earns nothing")
	room._spawn_enemy(Enemy.Kind.STALKER, Vector2(1200.0, Content.FLOOR_Y - 40.0), { "elite": true, "oath": "vengeful" })
	var shards: Array = []
	room.projectile_requested.connect(func(team: String, _p: Vector2, _v: Vector2, _d: float, _k: float, _pi: int, _l: float, _c: Color): shards.append(team))
	room.enemies[-1].take_damage(99999.0, Vector2.LEFT, 0.0)
	check(shards.is_empty(), "a vengeful elite's embers wait a beat after it falls")
	await ticks(30)
	check(shards.size() == Room.VENGEANCE_SHARDS and shards.all(func(t): return t == "enemy"), "then its ring of embers bursts")
	await _free_room(room)


## A walker on a ledge steps down to a knight waiting on the floor below.
func _test_ledge_drop() -> void:
	var room := _empty_room("tiers", Vector2(700.0, Content.FLOOR_Y - 27.0))
	room._spawn_enemy(Enemy.Kind.STALKER, Vector2(420.0, Content.FLOOR_Y - 210.0))
	var stalker: Enemy = room.enemies[-1]
	await ticks(150)
	check(stalker.global_position.y > Content.FLOOR_Y - 60.0, "a stalker drops from its ledge to reach the knight")
	await _free_room(room)


## A creature that lands beside the knight waits out its grace before striking.
func _test_spawn_grace() -> void:
	var stalker := await _foe(Enemy.Kind.STALKER, _knight.global_position.x + 40.0)
	await ticks(20)
	check(stalker.state != Enemy.EState.WINDUP, "a fresh spawn does not wind up on its first frames")
	await ticks(50)
	check(stalker.state == Enemy.EState.WINDUP or stalker.state == Enemy.EState.ATTACK, "after its grace the spawn attacks")
	stalker.queue_free()
	await ticks(1)
