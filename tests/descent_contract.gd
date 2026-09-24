extends SceneTree
## Contracts for the descent's choices and payoffs: rift routes out of a cleared
## chamber, the ranked Forge, move-changing boons, paper-cut deaths, and the
## per-chamber flask charge. Headless; uses a scratch save.
##   godot4 --headless --path . --script res://tests/descent_contract.gd
var game: Game
var checks := 0
var failures := 0
const TMP_SAVE := "user://descent_contract.json"

func _init() -> void:
	call_deferred("run")

func ticks(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func boot() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	paused = false
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await ticks(3)
	game.ui.start_requested.emit()
	await ticks(4)
	game.player.iframes = 99.0

func clear_room() -> void:
	for e in game.room.enemies.duplicate():
		if is_instance_valid(e) and not e.dead:
			e.take_damage(99999.0, Vector2.RIGHT, 0.0)
	game.room._wave_index = game.room._waves.size()
	game.room._unlock_exit()
	await ticks(2)

func run() -> void:
	Save.path = TMP_SAVE
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(TMP_SAVE)
	await _test_rifts()
	await _test_forge_ranks()
	await _test_boons()
	await _test_paper_cut()
	await _test_flask_charge()
	await _test_crow()
	await _test_vows()
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(TMP_SAVE)
	print("DESCENT_RESULT: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func _test_rifts() -> void:
	await boot()
	var room: Room = game.room
	check(room.exits.size() == 2, "a combat chamber opens two rifts")
	var kinds: Array = []
	for e in room.exits:
		kinds.append(str(e.kind))
	check(kinds.has("boon"), "one rift always leads to a boon")
	check(room.exit_center() == room._exit_rect.get_center(), "the boon rift keeps the template's exit point")
	# Every roll offers the boon plus exactly one alternative.
	var rm := RunModel.new(99)
	for i in range(40):
		rm.room_index = i % 6
		var ex: Array = rm.roll_exits(randf())
		check(ex.size() == 2 and ex[0] == "boon" and ex[1] in ["font", "cache", "trial"], "rift roll %d is boon plus one alternative" % i)
	var first := RunModel.new(3)
	first.room_index = 0
	var no_trial := true
	for i in range(30):
		if first.roll_exits(1.0).has("trial"):
			no_trial = false
	check(no_trial, "the first chamber never offers a trial")
	# Healing font: full health, a larger flame, every flask back.
	await clear_room()
	game.run.build.hp = 30.0
	game.player.build.hp = 30.0
	game.player.flask_charges = 0
	var max_before := float(game.run.build.max_hp)
	var idx_before := game.run.room_index
	room.chosen_exit = "font"
	game._on_room_completed()
	await ticks(2)
	check(game.run.room_index == idx_before + 1 and game.state == Game.GState.PLAYING, "the font carries straight into the next chamber")
	check(is_equal_approx(float(game.run.build.max_hp), max_before + 5.0) and is_equal_approx(float(game.run.build.hp), float(game.run.build.max_hp)), "the font restores all health and adds five")
	check(game.player.flask_charges == game.player.flask_max, "the font refills every flask")
	# Forge cache: cells land in the save.
	await clear_room()
	var cells_before := Save.get_cells()
	game.room.chosen_exit = "cache"
	game._on_room_completed()
	await ticks(2)
	check(Save.get_cells() > cells_before, "the cache banks cells")
	# Trial: a rare-or-better offer now, and the next chamber pays for it.
	await clear_room()
	game.room.chosen_exit = "trial"
	game._on_room_completed()
	await ticks(1)
	check(game.state == Game.GState.REWARD and game.run.trial_next, "a trial opens a boon offer and marks the next chamber")
	var rare_only := true
	for u in game._pending_upgrades:
		if Content.upgrade_rarity(u) == "common":
			rare_only = false
	check(rare_only, "a trial's offer holds no common boons")
	game._on_upgrade_selected(0)
	await ticks(2)
	check(game.room.trial and not game.run.trial_next, "the next chamber is the trial")
	var elite := false
	for w in range(game.room._waves.size()):
		if game.room._elite_slot.x == w:
			elite = true
	check(elite, "a trial chamber always carries an elite")

func _test_forge_ranks() -> void:
	var d := Save.load_save()
	d["cells"] = 200
	d["meta"] = ["m_max_hp"]
	Save.save_save(d)
	check(Save.get_meta_rank("m_max_hp") == 1, "an old single purchase reads as rank one")
	var def := Content.meta_def("m_max_hp")
	var cost := Content.meta_next_cost(def, 1)
	check(cost == int(def.costs[1]), "rank two costs the second price")
	check(Save.purchase_meta("m_max_hp") and Save.get_meta_rank("m_max_hp") == 2, "buying raises the rank")
	check(Save.get_cells() == 200 - cost, "a rank costs exactly its price")
	check(is_equal_approx(float(Save.get_meta_modifiers().max_hp), 20.0), "ranks stack their bonus")
	var seer := Content.meta_def("m_seer")
	check(Save.purchase_meta("m_seer") and not Save.purchase_meta("m_seer"), "a single-rank relic masters in one purchase")
	check(Content.meta_next_cost(seer, 1) < 0, "a mastered relic has no next price")
	await boot()
	check(game.run.offer_count == Content.UPGRADES_PER_OFFER + 1, "Seer's Eye adds a fourth boon to offers")
	check(game.run.roll_upgrades().size() == Content.UPGRADES_PER_OFFER + 1, "offers honour the Seer's Eye")
	d = Save.load_save()
	d["meta"] = []
	Save.save_save(d)

func _pick(id: String) -> Dictionary:
	return Content.UPGRADES.filter(func(u): return u.id == id)[0]

func _test_boons() -> void:
	await boot()
	var p: Player = game.player
	for id in ["cindertrail", "flareparry", "twinlance", "phoenix", "brand", "skyfall"]:
		game.run.apply_upgrade(_pick(id))
	p.build = game.run.build
	check(p.build.cinder_trail and p.build.twin_lance and p.build.skyfall and p.build.flare_parry > 0.0 and p.build.phoenix > 0.0 and p.build.brand > 0.0, "move-changing boons land in the build")
	# Twin Lance: two bolts per cast.
	var bolts := [0]
	p.projectile_requested.connect(func(_t, _p, _v, _d, _k, _pi, _l, _c): bolts[0] += 1)
	p.special = 100.0
	p._do_special()
	check(bolts[0] == 2, "Twin Lance looses two bolts")
	# Nova: every enemy nearby is hurt and set alight.
	var near: Array = []
	for e in game.room.enemies:
		if is_instance_valid(e) and not e.dead:
			e.global_position = p.global_position + Vector2(60.0, 0.0)
			near.append(e)
	await ticks(1)
	var hp_before: Array = near.map(func(e): return e.hp)
	p.nova(10.0, 120.0)
	var all_hit := not near.is_empty()
	for i in range(near.size()):
		var e = near[i]
		if is_instance_valid(e) and not e.dead and (e.hp >= hp_before[i] or e.burn_time <= 0.0):
			all_hit = false
	check(all_hit, "a flame nova hurts and ignites every enemy in reach")
	# Ember Brand: burning targets take more.
	var e0 = null
	for e in game.room.enemies:
		if is_instance_valid(e) and not e.dead:
			e0 = e
	if e0 != null:
		e0.burn_time = 2.0
		var hot := p._damage_mul(e0)
		e0.burn_time = 0.0
		var cold := p._damage_mul(e0)
		check(hot > cold, "Ember Brand raises damage against burning enemies")
	# Cinder Trail: a floor dash leaves burning ground.
	var fires_before := game.projectiles.get_children().filter(func(n): return n is GroundFire).size()
	p.respawn_at(Vector2(200.0, Content.FLOOR_Y - 27.0))
	await ticks(4)
	p._begin_dash()
	await ticks(10)
	var fires := game.projectiles.get_children().filter(func(n): return n is GroundFire).size()
	check(fires > fires_before, "Cinder Trail leaves burning ground behind a dash")

const GroundFire := preload("res://scripts/ground_fire.gd")

func _test_paper_cut() -> void:
	await boot()
	var victim = null
	for e in game.room.enemies:
		if is_instance_valid(e) and not e.dead:
			victim = e
			break
	check(victim != null, "the chamber has an enemy to cut down")
	if victim == null:
		return
	var before := game.room.get_children().size()
	victim.take_damage(99999.0, Vector2(1.0, -0.2), 0.0)
	await ticks(1)
	var halves := 0
	for c in game.room.get_children():
		if c.get_script() == load("res://scripts/severed.gd"):
			halves += c.get_child_count()
	check(halves == 2, "a felled enemy comes apart in two halves")
	await ticks(60)
	var left := 0
	for c in game.room.get_children():
		if c.get_script() == load("res://scripts/severed.gd"):
			left += 1
	check(left == 0, "the halves clear themselves away")
	# Echoes never fight: no collision, no hurtbox in the enemy group.
	var hurtboxes := get_nodes_in_group("enemy_hurtbox").size()
	var source := Enemy.new()
	var echo = source.echo()
	root.add_child(echo)
	await process_frame
	check(echo.ghost and echo.collision_layer == 0 and get_nodes_in_group("enemy_hurtbox").size() == hurtboxes, "an echo is a drawing-only copy with no hurtbox")
	echo.queue_free()
	source.free()

func _test_flask_charge() -> void:
	await boot()
	var p: Player = game.player
	p.flask_charges = 0
	await clear_room()
	game.room.chosen_exit = "boon"
	game._on_room_completed()
	await ticks(1)
	# Take a boon that does not itself touch the flask belt.
	var pick := 0
	for i in range(game._pending_upgrades.size()):
		if str(game._pending_upgrades[i].kind) != "flask_charge":
			pick = i
			break
	game._on_upgrade_selected(pick)
	await ticks(2)
	check(p.flask_charges == Content.FLASK_PER_ROOM, "clearing a chamber returns one flask charge, not all of them")

## The carrion crow must shriek before it dives, and the dive must connect with
## a knight who stands still under it.
func _test_crow() -> void:
	await boot()
	for e in game.room.enemies:
		if is_instance_valid(e):
			e.queue_free()
	game.room.enemies.clear()
	var p: Player = game.player
	p.respawn_at(Vector2(560.0, Content.FLOOR_Y - 27.0))
	p.iframes = 0.0
	var told := [false]
	game.room.telegraphed.connect(func(kind, _pos, _elite): if kind == "crow": told[0] = true)
	game.room._spawn_enemy(Content.EnemyKind.CROW, Vector2(640.0, Content.FLOOR_Y - 200.0), {})
	var crow: Enemy = game.room.enemies[-1]
	check(crow.collision_mask == 0, "the crow flies over the world rather than walking it")
	var hp_before := float(p.build.hp)
	var dived := false
	for i in range(360):
		p.iframes = 0.0 if not told[0] else p.iframes
		await ticks(1)
		if crow.state == Enemy.EState.ATTACK:
			dived = true
		if float(p.build.hp) < hp_before:
			break
	check(told[0], "the crow's shriek is voiced before it dives")
	check(dived, "the crow commits to a dive")
	check(float(p.build.hp) < hp_before, "a dive connects with a knight standing under it")

## Vows bind only after a victory, and each one actually changes the keep.
func _test_vows() -> void:
	var d := Save.load_save()
	d["vows"] = ["v_embers", "v_thirst", "v_gilded", "v_haste", "v_pyre"]
	d["victories"] = 0
	Save.save_save(d)
	await boot()
	check(Enemy.vows.is_empty() and is_equal_approx(game._vow_mult, 1.0), "vows sworn before any victory do not bind")
	d = Save.load_save()
	d["victories"] = 1
	Save.save_save(d)
	await boot()
	check(Enemy.vows.size() == 5 and game._vow_mult > 2.0, "after a victory every sworn vow binds and raises the score multiplier")
	var e0 = null
	for e in game.room.enemies:
		if is_instance_valid(e) and not e.dead:
			e0 = e
	if e0 != null:
		var base: Dictionary = Content.ENEMY[e0.kind]
		check(float(e0.data.speed) > float(base.speed) and float(e0.data.windup) < float(base.windup), "the Vow of Haste quickens enemies")
		check(e0.damage_mul >= 1.35 - 0.001, "the Vow of Embers hardens every blow")
		check(is_equal_approx(float(Content.ENEMY[Content.EnemyKind.STALKER].speed), 150.0), "haste never edits the shared archetype table")
	check(game.room._elite_slot.x >= 0, "the Vow of the Gilded puts an elite in the chamber")
	check(game._flask_per_room() == 0, "the Vow of Thirst returns no flask charge")
	game.run.room_index = game.run.rooms_total() - 2
	game._advance_room()
	await ticks(100)
	var boss: Boss = game.room.boss
	check(is_equal_approx(boss.max_hp, Content.BOSS_HP * 1.2), "the Vow of the Pyre hardens the Warden")
	check(boss.phase == Boss.BPhase.TWO, "the Vow of the Pyre wakes the Warden already ignited")
	d = Save.load_save()
	d["vows"] = []
	d["victories"] = 0
	Save.save_save(d)
	Enemy.vows = {}
