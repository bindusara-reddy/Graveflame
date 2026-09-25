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
## Set by taking a Trial rift: the next chamber is harder, the boon was better.
var trial_next := false
## Boons shown per offer (the Seer's Eye relic adds one).
var offer_count := Content.UPGRADES_PER_OFFER

func _init(s: int = 0) -> void:
	seed_value = s if s != 0 else int(Time.get_ticks_msec())
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	build = base_build()
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
		"lance_mul": 1.0,
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
		# --- Move-changing boons ---
		"cinder_trail": false,
		"flare_parry": 0.0,
		"twin_lance": false,
		"phoenix": 0.0,
		"brand": 0.0,
		"skyfall": false,
	}

func generate_route() -> void:
	route.clear()
	# Keep variation inside a learning curve, not an early wall-jump lottery.
	var pool: Array = Content.ROOM_TEMPLATES.filter(func(t): return t.tag != "intro")
	var order: Array = []
	var idxs: Array = range(pool.size())
	for i in range(Content.ROOMS_BEFORE_BOSS):
		var first_band := 2
		for idx in idxs:
			first_band = mini(first_band, _room_pacing_band(str(pool[idx].tag)))
		var candidates: Array = idxs.filter(func(idx):
			return _room_pacing_band(str(pool[idx].tag)) == first_band
		)
		var pick: int = candidates[rng.randi_range(0, candidates.size() - 1)]
		order.append(pick)
		idxs.erase(pick)
		if idxs.is_empty():
			idxs = range(pool.size())
	route.append(Content.ROOM_TEMPLATES[0])
	for o in order:
		route.append(pool[o])
	route.append(Content.BOSS_TEMPLATE)

static func _room_pacing_band(tag: String) -> int:
	match tag:
		"arena", "tiers": return 0
		"gap", "platforms": return 1
		_: return 2

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

## Boons still eligible for an offer: unique boons already taken leave the pool.
func available_upgrades() -> Array:
	return Content.UPGRADES.filter(func(u):
		return not (bool(u.get("unique", false)) and taken.has(u.id))
	)

## Offer `offer_count` distinct upgrades. Rarity weights the draw, and boons
## offered earlier in the run are down-weighted so choices keep feeling fresh.
func roll_upgrades(floor_rarity: String = "") -> Array:
	var avail: Array = available_upgrades()
	if floor_rarity == "rare":
		avail = avail.filter(func(u): return Content.upgrade_rarity(u) != "common")
	var out: Array = []
	for i in range(mini(offer_count, avail.size())):
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
			build.lance_mul += u.value
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
		"cinder_trail":
			build.cinder_trail = true
		"flare_parry":
			build.flare_parry = maxf(float(build.flare_parry), u.value)
		"twin_lance":
			build.twin_lance = true
		"phoenix":
			build.phoenix = maxf(float(build.phoenix), u.value)
		"brand":
			build.brand += u.value
		"skyfall":
			build.skyfall = true

## What the doors out of a cleared chamber offer. One always leads to a boon;
## the other trades that for health, cells, or a harder road to a better boon.
## Hurt knights are shown the font more often. Seeded, so a seed replays.
func roll_exits(hp_frac: float) -> Array:
	var options := ["font", "cache", "trial"]
	var weights := [0.6 + 3.0 * clampf(1.0 - hp_frac, 0.0, 1.0), 1.0, 0.0 if room_index < 1 else 1.1]
	var total := 0.0
	for w in weights:
		total += float(w)
	var roll := rng.randf() * total
	var pick: String = options[0]
	for i in range(options.size()):
		roll -= float(weights[i])
		if roll <= 0.0:
			pick = options[i]
			break
	return ["boon", pick]
