class_name RunModel
extends RefCounted
## Pure, seeded run state: route, room index, player build, and upgrade offers.

var seed_value: int = 0
var rng: RandomNumberGenerator
var route: Array = []             # array of template dictionaries
var room_index: int = -1
var build: Dictionary = {}
var offered: Dictionary = {}      # upgrade ids already offered (to reduce repeats)
var taken: Dictionary = {}        # upgrade ids applied this run (unique boons leave the pool)
var rooms_cleared: int = 0

func _init(s: int = 0) -> void:
	seed_value = s if s != 0 else int(Time.get_ticks_msec())
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	_reset_build()
	generate_route()

static func base_build() -> Dictionary:
	return {
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
		# --- Synergy boons ---
		"parry_special": 0.0,
		"burn_bonus_dps": 0.0,
		"burn_bonus_time": 0.0,
		"momentum": 0.0,
		"bloodrush": 0.0,
		"second_wind": false,
		"second_wind_used": false,
		"execute_bonus": 0.0,
		"pyre_dmg": 0.0,
		"finisher_wave": false,
		"thorns": 0.0,
	}

func _reset_build() -> void:
	build = base_build()

func generate_route() -> void:
	route.clear()
	# Intro room first, then shuffled combat rooms, then boss.
	var pool: Array = Content.ROOM_TEMPLATES.duplicate()
	pool = pool.filter(func(t): return t.tag != "intro")
	# pick ROOMS_BEFORE_BOSS combat rooms, shuffled, allowing repeats only once
	# every template has been used.
	var order: Array = []
	var idxs: Array = range(pool.size())
	for i in range(Content.ROOMS_BEFORE_BOSS):
		var pick: int = rng.randi_range(0, idxs.size() - 1)
		order.append(idxs[pick])
		idxs.remove_at(pick)
		if idxs.is_empty():
			idxs = range(pool.size())
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

## Boons still eligible for an offer: unique boons already taken leave the pool.
func available_upgrades() -> Array:
	return Content.UPGRADES.filter(func(u):
		return not (bool(u.get("unique", false)) and taken.has(u.id))
	)

## Offer UPGRADES_PER_OFFER distinct upgrades. Rarity weights the draw, and boons
## offered earlier in the run are down-weighted so choices keep feeling fresh.
func roll_upgrades() -> Array:
	var avail: Array = available_upgrades()
	var out: Array = []
	for i in range(mini(Content.UPGRADES_PER_OFFER, avail.size())):
		var total := 0.0
		var weights: Array = []
		for u in avail:
			var w := float(Content.RARITY_WEIGHTS.get(Content.upgrade_rarity(u), 30.0))
			w /= 1.0 + 1.5 * float(offered.get(u.id, 0))
			weights.append(w)
			total += w
		var roll := rng.randf() * total
		var pick := avail.size() - 1
		for j in range(avail.size()):
			roll -= float(weights[j])
			if roll <= 0.0:
				pick = j
				break
		var u: Dictionary = avail[pick].duplicate()
		out.append(u)
		offered[u.id] = int(offered.get(u.id, 0)) + 1
		avail.remove_at(pick)
	return out

func apply_upgrade(u: Dictionary) -> void:
	if u.has("id"):
		taken[u.id] = int(taken.get(u.id, 0)) + 1
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
			build.slam_radius_bonus += u.value * 45.0
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
		"parry_special":
			build.parry_special += u.value
		"burn":
			build.burn_bonus_dps += u.value
			build.burn_bonus_time += 2.0
		"momentum":
			build.momentum += u.value
		"bloodrush":
			build.bloodrush += u.value
		"second_wind":
			build.second_wind = true
			build.second_wind_used = false
		"execute":
			build.execute_bonus += u.value
		"pyre":
			build.pyre_dmg += u.value
		"finisher_wave":
			build.finisher_wave = true
		"thorns":
			build.thorns += u.value

func is_dead() -> bool:
	return build.hp <= 0.0

func reset_run(new_seed: int) -> void:
	seed_value = new_seed if new_seed != 0 else int(Time.get_ticks_msec())
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	room_index = -1
	rooms_cleared = 0
	offered.clear()
	taken.clear()
	_reset_build()
	generate_route()
