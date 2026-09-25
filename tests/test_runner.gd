extends SceneTree
## Pure-data suite: every script compiles, content invariants hold, boons apply
## to the build, and the seeded run model is deterministic and keeps its route
## pacing.
## Run:  godot4 --headless --path . --script res://tests/test_runner.gd

var checks := 0
var failures := 0

func _init() -> void:
	_run_tests()
	var passed := failures == 0
	print("TEST_RESULT: %s (%d checks, %d failures)" % ["PASS" if passed else "FAIL", checks, failures])
	quit(0 if passed else 1)

func check(cond: bool, message: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + message)

func _run_tests() -> void:
	_test_script_loading()
	_test_content()
	_test_run_model()
	_test_run_pacing()
	_test_save()
	_test_new_upgrades()
	_test_rarity_and_uniques()
	_test_wave_generation()
	_test_difficulty_and_streaks()
	_test_synergy_boons()
	_test_moods()

func _test_script_loading() -> void:
	# A script whose globals failed to resolve (e.g. because `.godot/` carries no
	# global class cache) still returns a NON-NULL GDScript from load(), but one
	# that cannot be instantiated. Checking only for null would report a green
	# suite while every later check silently skipped, so assert instantiation.
	# Scanned, not listed, so a new script can never be left out.
	for file_name in DirAccess.get_files_at("res://scripts"):
		if not file_name.ends_with(".gd"):
			continue
		var path := "res://scripts".path_join(file_name)
		var s = load(path)
		check(s != null, "load script: %s" % path)
		if s == null:
			continue
		check(s is GDScript and s.can_instantiate(), "script compiles: %s (missing class cache?)" % path)
		if not (s is GDScript and s.can_instantiate()):
			continue
		var inst = s.new()
		if inst is Node:
			inst.queue_free()

func _test_content() -> void:
	var Content = load("res://scripts/content.gd")
	# Combat
	check(Content.COMBO.size() == 3, "COMBO has 3 swings")
	# Enemies — six archetypes
	check(Content.ENEMY.size() == Content.EnemyKind.size() and Content.ENEMY.size() >= 6, "ENEMY defines every archetype (six, with the carrion crow)")
	check(Content.ENEMY.has(Content.EnemyKind.BRUTE), "BRUTE kind exists")
	check(Content.ENEMY.has(Content.EnemyKind.BOMBER), "BOMBER kind exists")
	check(bool(Content.ENEMY[Content.EnemyKind.BRUTE].get("shielded", false)), "BRUTE is shielded")
	check(bool(Content.ENEMY[Content.EnemyKind.BOMBER].get("explodes", false)), "BOMBER explodes")
	check(Content.ENEMY[Content.EnemyKind.BOMBER].has("blast_radius"), "BOMBER has blast_radius")
	# Rooms
	check(Content.ROOM_TEMPLATES.size() >= 6, "at least 6 room templates (incl. chamber + crossfire)")
	var has_chamber := false
	var has_crossfire := false
	for t in Content.ROOM_TEMPLATES:
		if t.tag == "chamber": has_chamber = true
		if t.tag == "crossfire": has_crossfire = true
	check(has_chamber, "chamber room template present")
	check(has_crossfire, "crossfire room template present")
	# intro is first
	check(Content.ROOM_TEMPLATES[0].tag == "intro", "first template is intro")
	# Boss template tagged
	check(Content.BOSS_TEMPLATE.tag == "boss", "boss template tagged")
	# Meta upgrades
	check(Content.META_UPGRADES.size() >= 5, "at least 5 meta upgrades")
	# New mechanics constants present
	check(Content.P_SLAM_DAMAGE > 0.0, "slam damage defined")
	check(Content.PARRY_WINDOW > 0.0, "parry window defined")
	check(Content.FLASK_MAX > 0, "flask max charges defined")
	check(Content.P_WALL_JUMP_VEL != Vector2.ZERO, "wall jump velocity defined")

func _test_run_model() -> void:
	var RunModel = load("res://scripts/run_model.gd")
	var Content = load("res://scripts/content.gd")
	var rm1 = RunModel.new(12345)
	# advance
	rm1.advance_to_next_room()
	check(rm1.room_index == 0, "first advance -> room 0")
	check(rm1.is_boss_room() == false, "room 0 is not boss")
	for i in range(rm1.rooms_total() - 1):
		rm1.advance_to_next_room()
	check(rm1.is_boss_room() == true, "last room is boss")
	# upgrades — unique offers
	var ups = rm1.roll_upgrades()
	check(ups.size() == Content.UPGRADES_PER_OFFER, "upgrade offer count")
	var ids: Array = []
	for u in ups:
		check(not ids.has(u.id), "upgrade offer unique: " + str(u.id))
		ids.append(u.id)
	# apply upgrade and verify build changes
	var before := float(rm1.build.max_hp)
	rm1.apply_upgrade({ "kind": "max_hp", "value": 25.0 })
	check(rm1.build.max_hp == before + 25.0, "max_hp upgrade applied")
	check(rm1.build.hp == rm1.build.max_hp, "max_hp upgrade full heals")
	# special pierce flag
	rm1.apply_upgrade({ "kind": "special_pierce", "value": 0.2 })
	check(rm1.build.special_pierce == true, "special_pierce sets flag")
	# New upgrade kinds
	rm1.apply_upgrade({ "kind": "slam_mul", "value": 0.6 })
	check(rm1.build.slam_mul == 1.6, "slam_mul upgrade applied")
	rm1.apply_upgrade({ "kind": "flask_charge", "value": 1.0 })
	check(rm1.build.flask_charges == Content.FLASK_MAX + 1, "flask_charge upgrade applied")
	rm1.apply_upgrade({ "kind": "dash_master", "value": 0.5 })
	check(rm1.build.dash_cd_mul == 0.5, "dash_master reduces cooldown")
	rm1.apply_upgrade({ "kind": "parry", "value": 12.0 })
	check(rm1.build.parry_bonus_dmg == 12.0, "parry bonus damage applied")
	check(rm1.build.parry_window_mul == 1.5, "parry window extended")

## Seeded progression: safe combat foundations before pit and wall-jump gauntlets.
## Each rule is one check naming every seed that breaks it, so a systematic break
## prints a line per rule rather than one per seed.
func _test_run_pacing() -> void:
	var RunModel = load("res://scripts/run_model.gd")
	var Content = load("res://scripts/content.gd")
	var failing_seeds := {}
	var orders := {}
	for run_seed in range(1, 129):
		var tags: Array = RunModel.new(run_seed).route.map(func(room): return str(room.tag))
		var again: Array = RunModel.new(run_seed).route.map(func(room): return str(room.tag))
		orders[str(tags)] = true
		var kept := _pacing_rules(tags, again, Content.ROOMS_BEFORE_BOSS)
		for rule in kept:
			var seeds: Array = failing_seeds.get_or_add(rule, [])
			if not kept[rule]:
				seeds.append(run_seed)
	for rule in failing_seeds:
		var seeds: Array = failing_seeds[rule]
		check(seeds.is_empty(), "%s (failing seeds: %s)" % [rule, seeds])
	check(orders.size() > 1, "route order still varies within the pacing bands")

## Whether one seeded route keeps each pacing rule, keyed by the rule's message.
func _pacing_rules(tags: Array, again: Array, combat_room_count: int) -> Dictionary:
	var eight_rooms: bool = tags.size() == 8 and tags[0] == "intro" and tags[-1] == "boss"
	var rules := {
		"the original eight-room loop is preserved": eight_rooms,
		"safe arena and ascent teach combat before pits": true,
		"mid-run introduces the crossing rooms": true,
		"wall-jump and exposed gauntlets belong late": true,
		"every combat room appears once": true,
		"route remains seed-reproducible": tags == again,
	}
	# The bands read fixed slots 1-6. On a route of any other length that read
	# would go out of bounds, abort the calling test and still let the suite
	# print PASS, so they are judged only on an eight-room route; the length
	# rule above already fails the others.
	if tags.size() != 8:
		return rules
	var early := ["arena", "tiers"]
	var crossings := ["gap", "platforms"]
	var gauntlets := ["chamber", "crossfire"]
	var combat_rooms := {}
	for tag in tags.slice(1, -1):
		combat_rooms[tag] = true
	rules["safe arena and ascent teach combat before pits"] = tags[1] in early and tags[2] in early
	rules["mid-run introduces the crossing rooms"] = tags[3] in crossings and tags[4] in crossings
	rules["wall-jump and exposed gauntlets belong late"] = tags[5] in gauntlets and tags[6] in gauntlets
	rules["every combat room appears once"] = combat_rooms.size() == combat_room_count
	return rules

func _test_save() -> void:
	var Save = load("res://scripts/save.gd")
	# load_save returns a valid dict (defaults if no file)
	var d: Dictionary = Save.load_save()
	check(d.has("cells"), "save has cells key")
	check(d.has("best_score"), "save has best_score key")
	check(d.has("meta"), "save has meta key")
	# get_meta_modifiers returns expected keys
	var mods: Dictionary = Save.get_meta_modifiers()
	check(mods.has("max_hp"), "meta modifiers has max_hp")
	check(mods.has("flask"), "meta modifiers has flask")
	check(mods.has("special_start"), "meta modifiers has special_start")
	# meta upgrade lookup works
	var found := false
	for u in load("res://scripts/content.gd").META_UPGRADES:
		if u.id == "m_max_hp":
			found = true
			break
	check(found, "m_max_hp meta upgrade exists")

func _test_new_upgrades() -> void:
	var Content = load("res://scripts/content.gd")
	var slam_ok := false
	var parry_ok := false
	var flask_ok := false
	var dash_ok := false
	for u in Content.UPGRADES:
		match u.kind:
			"slam_mul": slam_ok = true
			"parry": parry_ok = true
			"flask_charge": flask_ok = true
			"dash_master": dash_ok = true
	check(slam_ok, "slam upgrade present")
	check(parry_ok, "parry upgrade present")
	check(flask_ok, "flask upgrade present")
	check(dash_ok, "dashmaster upgrade present")


func _test_rarity_and_uniques() -> void:
	var Content = load("res://scripts/content.gd")
	var RunModel = load("res://scripts/run_model.gd")
	check(Content.UPGRADES.size() >= 22, "boon pool grew to at least 22 entries")
	var ids := {}
	for u in Content.UPGRADES:
		check(Content.RARITY_WEIGHTS.has(Content.upgrade_rarity(u)), "boon %s has a weighted rarity" % str(u.id))
		check(not ids.has(u.id), "boon id unique: %s" % str(u.id))
		ids[u.id] = true
	check(Content.rarity_color("epic") != Content.rarity_color("common"), "rarities are colour-coded")
	# Weighted rolls stay distinct and deterministic per seed.
	var a = RunModel.new(777)
	var b = RunModel.new(777)
	var ra: Array = a.roll_upgrades()
	var rb: Array = b.roll_upgrades()
	check(ra.size() == Content.UPGRADES_PER_OFFER, "weighted roll offers the configured count")
	var seen := {}
	for u in ra:
		check(not seen.has(u.id), "weighted roll has no duplicate: %s" % str(u.id))
		seen[u.id] = true
	var same := true
	for i in range(ra.size()):
		if ra[i].id != rb[i].id:
			same = false
	check(same, "same seed -> same boon offers")
	# A unique boon leaves the pool once taken.
	var rm = RunModel.new(31337)
	var second_wind: Dictionary = {}
	for u in Content.UPGRADES:
		if u.id == "secondwind":
			second_wind = u
	check(not second_wind.is_empty() and bool(second_wind.get("unique", false)), "Second Wind is a unique boon")
	rm.apply_upgrade(second_wind)
	check(rm.build.second_wind == true, "Second Wind arms the build flag")
	var offered_again := false
	for i in range(40):
		for u in rm.roll_upgrades():
			if u.id == "secondwind":
				offered_again = true
	check(not offered_again, "a taken unique boon is never offered again")
	check(rm.available_upgrades().size() == Content.UPGRADES.size() - 1, "available pool shrinks by exactly the taken unique")
	# Non-unique boons remain rollable after being taken.
	var vitality: Dictionary = Content.UPGRADES[0]
	rm.apply_upgrade(vitality)
	check(rm.available_upgrades().size() == Content.UPGRADES.size() - 1, "stackable boons stay in the pool")


func _test_wave_generation() -> void:
	var Content = load("res://scripts/content.gd")
	for idx in range(0, 8):
		var r1 := RandomNumberGenerator.new()
		var r2 := RandomNumberGenerator.new()
		r1.seed = 99 + idx
		r2.seed = 99 + idx
		var w1: Array = Content.generate_waves(idx, r1)
		var w2: Array = Content.generate_waves(idx, r2)
		check(w1 == w2, "wave generation deterministic for room %d" % idx)
		check(w1.size() >= 1, "room %d has at least one wave" % idx)
		for wave in w1:
			check(wave.size() >= 1 and wave.size() <= Content.WAVE_MAX_ENEMIES, "room %d wave size in range" % idx)
			var brutes := 0
			var bombers := 0
			for k in wave:
				check(k >= 0 and k < Content.EnemyKind.size(), "generated kind in range")
				if k == Content.EnemyKind.BRUTE: brutes += 1
				if k == Content.EnemyKind.BOMBER: bombers += 1
				if idx < 3:
					check(k != Content.EnemyKind.BRUTE, "brutes only appear from room 3")
			check(brutes <= 1 and bombers <= 1, "at most one brute and one bomber per wave")
	var r0 := RandomNumberGenerator.new()
	check(Content.generate_waves(1, r0) == Content.OPENING_WAVES[1], "early rooms keep their authored waves")
	var r5 := RandomNumberGenerator.new()
	r5.seed = 5
	check(Content.generate_waves(5, r5).size() == 3, "deep rooms escalate to three waves")


func _test_difficulty_and_streaks() -> void:
	var Content = load("res://scripts/content.gd")
	var d0: Dictionary = Content.difficulty_for_room(0)
	var d5: Dictionary = Content.difficulty_for_room(5)
	check(is_equal_approx(float(d0.hp_mul), 1.0) and is_equal_approx(float(d0.dmg_mul), 1.0), "room 0 enemies are unscaled")
	check(float(d5.hp_mul) > float(d0.hp_mul) and float(d5.dmg_mul) > float(d0.dmg_mul), "deeper rooms scale enemies up")
	check(is_zero_approx(Content.elite_chance(0)) and is_zero_approx(Content.elite_chance(1)), "no elites in the opening rooms")
	check(Content.elite_chance(2) > 0.0 and Content.elite_chance(20) <= 0.7, "elite chance ramps and caps")
	check(is_equal_approx(Content.streak_multiplier(1), 1.0), "single kill has no multiplier")
	check(is_equal_approx(Content.streak_multiplier(2), 1.25), "two chained kills reach x1.25")
	check(is_equal_approx(Content.streak_multiplier(11), 3.0), "eleven chained kills reach x3")
	check(Content.streak_tier(0) == 0 and Content.streak_tier(7) == 3, "streak tiers step at the configured thresholds")


func _test_moods() -> void:
	var Content = load("res://scripts/content.gd")
	check(Content.MOODS.size() >= 3, "at least three mood keyframes")
	var keys: Array = Content.MOODS[0].keys()
	for m in Content.MOODS:
		for key in keys:
			check(m.has(key), "mood %s defines %s" % [str(m.name), str(key)])
	var first: Dictionary = Content.mood_for(0.0)
	var last: Dictionary = Content.mood_for(1.0)
	var mid: Dictionary = Content.mood_for(0.5)
	check(first.name == "crypt" and last.name == "throne", "mood endpoints are the crypt and the throne")
	check(first.bg_top == Content.MOODS[0].bg_top and last.bg_top == Content.MOODS[2].bg_top, "mood endpoints reproduce their keyframes exactly")
	check(is_equal_approx(float(first.stars), 1.0) and is_equal_approx(float(last.stars), 0.0), "stars fade out with depth")
	check(float(mid.ember_seep) > float(first.ember_seep) and float(mid.ember_seep) <= float(last.ember_seep), "ember seep rises with depth")
	check(mid.torch is Color and mid.bg_top is Color, "blended mood colours stay Colors")
	var below: Dictionary = Content.mood_for(-3.0)
	var above: Dictionary = Content.mood_for(7.0)
	check(below.name == "crypt" and above.name == "throne", "mood progress is clamped")


func _test_synergy_boons() -> void:
	var RunModel = load("res://scripts/run_model.gd")
	var rm = RunModel.new(1)
	for key in ["parry_special", "burn_bonus_dps", "burn_bonus_time", "momentum", "bloodrush", "second_wind", "second_wind_used", "execute_bonus", "pyre_dmg", "finisher_wave", "thorns"]:
		check(rm.build.has(key), "base build has %s" % key)
	rm.apply_upgrade({ "id": "pyre", "kind": "pyre", "value": 60.0 })
	check(is_equal_approx(rm.build.pyre_dmg, 60.0), "pyre boon sets detonation damage")
	rm.apply_upgrade({ "id": "kindling", "kind": "burn", "value": 6.0 })
	check(is_equal_approx(rm.build.burn_bonus_dps, 6.0) and is_equal_approx(rm.build.burn_bonus_time, 2.0), "kindling raises burn dps and duration")
	rm.apply_upgrade({ "id": "momentum", "kind": "momentum", "value": 0.12 })
	rm.apply_upgrade({ "id": "momentum", "kind": "momentum", "value": 0.12 })
	check(is_equal_approx(rm.build.momentum, 0.24), "momentum stacks additively")
	rm.apply_upgrade({ "id": "emberwave", "kind": "finisher_wave", "value": 1.0 })
	check(rm.build.finisher_wave == true, "emberwave arms finisher waves")
	rm.apply_upgrade({ "id": "thorns", "kind": "thorns", "value": 15.0 })
	rm.apply_upgrade({ "id": "executioner", "kind": "execute", "value": 0.5 })
	rm.apply_upgrade({ "id": "backdraft", "kind": "parry_special", "value": 30.0 })
	check(is_equal_approx(rm.build.thorns, 15.0) and is_equal_approx(rm.build.execute_bonus, 0.5) and is_equal_approx(rm.build.parry_special, 30.0), "thorns, executioner and backdraft apply")
