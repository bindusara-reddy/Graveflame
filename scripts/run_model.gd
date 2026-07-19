class_name RunModel
extends RefCounted
## Pure, seeded run state: route, room index, player build, and upgrade offers.

var seed_value: int = 0
var rng: RandomNumberGenerator
var route: Array = []             # array of template dictionaries
var room_index: int = -1
var build: Dictionary = {}
var offered: Dictionary = {}      # upgrade ids already offered (to reduce repeats)
var rooms_cleared: int = 0

func _init(s: int = 0) -> void:
	seed_value = s if s != 0 else int(Time.get_ticks_msec())
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	_reset_build()
	generate_route()

func _reset_build() -> void:
	build = {
		"max_hp": Content.P_MAX_HP,
		"hp": Content.P_MAX_HP,
		"speed_mul": 1.0,
		"dmg_mul": 1.0,
		"finish_mul": 1.0,
		"special_mul": 1.0,
		"special_pierce": false,
		"lifesteal": 0.0,
		"iframes_bonus": 0.0,
		"slam_mul": 1.0,
		"slam_radius_bonus": 0.0,
		"parry_bonus_dmg": 0.0,
		"parry_window_mul": 1.0,
		"flask_charges": Content.FLASK_MAX,
		"dash_cd_mul": 1.0,
		"dash_iframes_bonus": 0.0,
		"special_start": 0.0,
	}

func generate_route() -> void:
	route.clear()
	# Intro room first, then shuffled combat rooms, then boss.
	var combat: Array = []
	var tags: Array = ["gap", "tiers", "arena", "platforms"]
	# Deterministic shuffle of combat templates by tag.
	var pool: Array = Content.ROOM_TEMPLATES.duplicate()
	pool = pool.filter(func(t): return t.tag != "intro")
	# pick ROOMS_BEFORE_BOSS combat rooms, shuffled, allowing repeats if fewer exist.
	var order: Array = []
	var idxs: Array = range(pool.size())
	for i in range(Content.ROOMS_BEFORE_BOSS):
		var pick: int = rng.randi_range(0, idxs.size() - 1)
		order.append(idxs[pick])
		idxs.remove_at(pick)
		if idxs.is_empty():
			idxs = range(pool.size())
	# Always start with intro
	route.append(Content.ROOM_TEMPLATES[0])
	for o in order:
		route.append(pool[o])
	route.append(Content.BOSS_TEMPLATE)

func current_room_template() -> Dictionary:
	if room_index < 0 or room_index >= route.size():
		return {}
	return route[room_index]

func is_boss_room() -> bool:
	return room_index == route.size() - 1

func rooms_total() -> int:
	return route.size()

func advance_to_next_room() -> Dictionary:
	room_index += 1
	return current_room_template()

func room_cleared() -> void:
	rooms_cleared += 1

## Offer UPGRADES_PER_OFFER distinct upgrades, biased away from already-offered ones.
func roll_upgrades() -> Array:
	var avail: Array = Content.UPGRADES.duplicate()
	# Fisher-Yates shuffle first (deterministic given rng)
	for i in range(avail.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = avail[i]
		avail[i] = avail[j]
		avail[j] = tmp
	# stable sort: not-yet-offered first
	avail.sort_custom(func(a, b):
		var ao: int = int(offered.get(a.id, 0))
		var bo: int = int(offered.get(b.id, 0))
		return ao < bo
	)
	var out: Array = []
	for i in range(mini(Content.UPGRADES_PER_OFFER, avail.size())):
		var u: Dictionary = avail[i].duplicate()
		out.append(u)
		offered[u.id] = int(offered.get(u.id, 0)) + 1
	return out

func apply_upgrade(u: Dictionary) -> void:
	match u.kind:
		"max_hp":
			build.max_hp += u.value
			build.hp = build.max_hp
		"speed_mul":
			build.speed_mul += u.value
		"dmg_mul":
			build.dmg_mul += u.value
		"finish_mul":
			build.finish_mul += u.value
		"special_mul":
			build.special_mul += u.value
		"special_pierce":
			build.special_pierce = true
			build.dmg_mul = build.dmg_mul * (1.0 + u.value) # optional extra
		"lifesteal":
			build.lifesteal += u.value
		"iframes":
			build.iframes_bonus += u.value
		"heal":
			build.hp = minf(build.max_hp, build.hp + u.value)
		"slam_mul":
			build.slam_mul += u.value
			build.slam_radius_bonus += u.value * 0.3
		"parry":
			build.parry_bonus_dmg += u.value
			build.parry_window_mul += 0.5
		"flask_charge":
			build.flask_charges += int(u.value)
		"dash_master":
			build.dash_cd_mul *= u.value
			build.dash_iframes_bonus += 0.12
		"special_start":
			build.special_start = maxf(build.special_start, u.value)

func is_dead() -> bool:
	return build.hp <= 0.0

func reset_run(new_seed: int) -> void:
	seed_value = new_seed if new_seed != 0 else int(Time.get_ticks_msec())
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	room_index = -1
	rooms_cleared = 0
	offered.clear()
	_reset_build()
	generate_route()
