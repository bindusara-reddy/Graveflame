extends SceneTree
## Headless test runner: validates script loading, run determinism, content invariants,
## and the new mechanics (slam, parry, flask, cells meta-progression, new enemy types).
## Run:  godot --headless --path . --script res://tests/test_runner.gd

var checks := 0
var failures := 0

const PRODUCTION_SCRIPTS := [
	"res://scripts/content.gd",
	"res://scripts/run_model.gd",
	"res://scripts/save.gd",
	"res://scripts/projectile.gd",
	"res://scripts/player.gd",
	"res://scripts/enemy.gd",
	"res://scripts/boss.gd",
	"res://scripts/room.gd",
	"res://scripts/feedback.gd",
	"res://scripts/ui.gd",
	"res://scripts/game.gd",
]

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
	_test_save()
	_test_new_upgrades()

func _test_script_loading() -> void:
	for path in PRODUCTION_SCRIPTS:
		var s = load(path)
		check(s != null, "load script: %s" % path)
		if s != null:
			var inst = s.new() if s.can_instantiate() else null
			if inst != null and inst is RefCounted:
				pass
			if inst != null and inst is Node:
				inst.queue_free()

func _test_content() -> void:
	var Content = load("res://scripts/content.gd")
	# Combat
	check(Content.COMBO.size() == 3, "COMBO has 3 swings")
	# Enemies — now 5 archetypes
	check(Content.ENEMY.size() == 5, "ENEMY has 5 archetypes")
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
	# Upgrades — now 13
	check(Content.UPGRADES.size() >= 13, "at least 13 upgrades (incl. slam, parry, flask, dashmaster)")
	# Meta upgrades
	check(Content.META_UPGRADES.size() >= 5, "at least 5 meta upgrades")
	# encounter list sane — all kinds in range [0, 5)
	for i in range(6):
		var enc = Content.encounter_for_room(i)
		check(enc.size() >= 1, "encounter room %d has enemies" % i)
		for k in enc:
			check(k >= 0 and k < Content.EnemyKind.size(), "encounter kind in range")
	# New mechanics constants present
	check(Content.P_SLAM_DAMAGE > 0.0, "slam damage defined")
	check(Content.PARRY_WINDOW > 0.0, "parry window defined")
	check(Content.FLASK_MAX > 0, "flask max charges defined")
	check(Content.P_WALL_JUMP_VEL != Vector2.ZERO, "wall jump velocity defined")
	check(Content.META_UPGRADES.size() > 0, "meta upgrades defined")

func _test_run_model() -> void:
	var RunModel = load("res://scripts/run_model.gd")
	var Content = load("res://scripts/content.gd")
	var rm1 = RunModel.new(12345)
	var rm2 = RunModel.new(12345)
	# determinism: same seed -> same route tags
	var tags1: Array = []
	var tags2: Array = []
	for r in rm1.route: tags1.append(r.tag)
	for r in rm2.route: tags2.append(r.tag)
	check(tags1 == tags2, "same seed -> same route tags")
	# route structure
	check(rm1.route.size() == Content.ROOMS_BEFORE_BOSS + 2, "route length = combat + intro + boss")
	check(rm1.route[0].tag == "intro", "route starts with intro")
	check(rm1.route[rm1.route.size() - 1].tag == "boss", "route ends with boss")
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
	# Build has all new keys
	check(rm1.build.has("slam_mul"), "build has slam_mul")
	check(rm1.build.has("parry_bonus_dmg"), "build has parry_bonus_dmg")
	check(rm1.build.has("flask_charges"), "build has flask_charges")
	check(rm1.build.has("dash_cd_mul"), "build has dash_cd_mul")
	# reset
	rm1.reset_run(99999)
	check(rm1.room_index == -1, "reset clears room index")
	check(rm1.build.max_hp == Content.P_MAX_HP, "reset restores base hp")
	check(rm1.build.slam_mul == 1.0, "reset restores slam_mul to base")

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
