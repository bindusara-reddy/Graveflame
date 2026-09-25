class_name Room
extends Node2D
## Builds geometry from a template, spawns encounters, seals/unseals the exit.

const VFX := preload("res://scripts/vfx.gd")
const CryptProp := preload("res://scripts/crypt_prop.gd")
const Severed := preload("res://scripts/severed.gd")
## Past victories shown as candles on the throne dais, at most.
const MAX_DAIS_CANDLES := 12
## The starved or broken throne's stone.
const THRONE_ASH := Color("4a4650")

signal completed
signal cleared(room_name: String)
signal wave_started(current: int, total: int)
## tier: 0 regular, 1 elite, 2 boss. kind names the archetype ("warden" for the boss).
signal enemy_died(score: int, pos: Vector2, tier: int, color: Color, kind: String)
signal enemy_damaged(amount: float, pos: Vector2, blocked: bool)
signal projectile_requested(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color)
signal boss_spawned
signal boss_phase_changed(phase: int)
signal enemy_exploded(pos: Vector2, radius: float, damage: float)
signal pyre_burst(pos: Vector2, radius: float)
signal telegraphed(kind: String, pos: Vector2, elite: bool)
signal enemy_spawned(pos: Vector2, color: Color)
signal prop_shattered(pos: Vector2, force: Vector2, color: Color)
signal boss_shattered(pos: Vector2)
signal boss_wave_requested(pos: Vector2, vel: Vector2, dmg: float, life: float)
## A creature's named or voiced beat (see Enemy.announced).
signal enemy_announced(text: String, cue: String, pos: Vector2)
## A first-time lesson worth showing now: a HINTS id the game teaches once.
signal lesson_requested(id: String)

## A wave never spawns closer than this to the knight.
const SPAWN_CLEARANCE := 220.0
## A vengeful elite's dying ring (see _loose_vengeance).
const VENGEANCE_DELAY := 0.3
const VENGEANCE_SHARDS := 6
const VENGEANCE_SPEED := 200.0
const VENGEANCE_BITE := 8.0

var template: Dictionary = {}
var enemies: Array[Node] = []
var props: Array[Area2D] = []
var boss: Boss = null
var is_boss: bool = false
var exit_open: bool = false
## The primary (boon) rift. Kept as its own rect for callers that only care
## where "the way out" is; `exits` holds every rift the chamber opens.
var _exit_rect := Rect2(0, 0, 50, 90)
## What the doors out of this chamber lead to, set by the game before _ready.
var exit_kinds: Array = ["boon"]
## [{ "kind": String, "rect": Rect2 }], in the order they stand left to right.
var exits: Array = []
## The rift the knight actually walked into.
var chosen_exit := "boon"
## A Trial chamber: a guaranteed elite and an extra wave.
var trial := false
## Depth of this chamber in the run, set by the game before _ready.
var room_index := 0
## The descent's seed, set by the game before _ready: it picks which chambers
## stage which set piece (Content.set_piece_for).
var run_seed := 0
var _near_idx := -1
var _rng := RandomNumberGenerator.new()
var _player_ref: Node = null
var _waves: Array = []
var _wave_index := 0
var _wave_delay := 0.0
var _exit_used := false
var _near_exit := false
var _room_cleared := false
var _ambient_t := 0.0
var _elite_slot := Vector2i(-1, -1)   # (wave, index) that spawns as an elite
var _elite_oath := ""
## This chamber's set piece (Content.SET_PIECES) and the wave that stages it.
var _set_piece: Dictionary = {}
var _set_piece_wave := -1
var _difficulty: Dictionary = { "hp_mul": 1.0, "dmg_mul": 1.0 }
## Depth palette handed down by the game (see Content.MOODS).
var mood: Dictionary = {}
## The swaying back decor's canvas (see _ready).
var _back_decor: Node2D
## Depth band (Content.zone_for): picks the floor's material and the dressing.
var zone := "crypt"
## The throne room is where the ending plays, and the finale plays it: the
## Warden's sigil gutters out (heat 0) and relights, the braziers sink and
## lean toward the throne as it calls (fire_lean), the throne greys to ash
## (throne_ash) or cracks in two (throne_split), and every past victory stands
## a candle on the dais. The braziers' and the sigil's lights follow the heat,
## so each change rebuilds the light list.
var sigil_heat := 1.0:
	set(value):
		sigil_heat = value
		_light_points_dirty = true
var sigil_gold := 0.0:
	set(value):
		sigil_gold = value
		_light_points_dirty = true
var fire_heat := 1.0:
	set(value):
		fire_heat = value
		_light_points_dirty = true
var fire_lean := 0.0
var throne_ash := 0.0
var throne_split := 0.0
var victory_candles := 0
## Re-deals the hashed dressing per chamber: prop placement and kinds here, and
## the backdrop's bays, banners and mounds through Game. The opening chamber
## keeps 0, so its composed first impression never shifts.
var dress_salt := 0

func setup(tmpl: Dictionary, p_is_boss: bool, player: Node, seed_val: int) -> void:
	template = tmpl
	var tag := str(tmpl.get("tag", "intro"))
	zone = Content.zone_for(tag)
	dress_salt = 0 if tag == "intro" else hash(tag) & 0xffff
	is_boss = p_is_boss
	_player_ref = player
	_rng.seed = seed_val

func _ready() -> void:
	# The set piece and the stonework are fixed for the chamber, so they are
	# painted once; the back decor sways, so it repaints every frame. All three
	# sit behind the room's own drawing: set piece, back decor, stonework.
	_add_paint_layer("SetPiece", _draw_set_piece)
	_back_decor = _add_paint_layer("BackDecor", _draw_decor_back)
	_add_paint_layer("Masonry", _draw_masonry_layer)
	_difficulty = Content.difficulty_for_room(room_index)
	_difficulty.dmg_mul = float(_difficulty.dmg_mul) * Enemy.vow_damage()
	_build_geometry()
	_setup_exit()
	_build_props()
	_spawn_encounter()

func _process(delta: float) -> void:
	_ambient_t += delta
	if _wave_delay > 0.0:
		_wave_delay -= delta
		if _wave_delay <= 0.0:
			_wave_index += 1
			_spawn_wave()
	if exit_open and not is_boss and is_instance_valid(_player_ref):
		_near_idx = -1
		var best := INF
		for i in range(exits.size()):
			var r: Rect2 = exits[i].rect
			var d := absf(r.get_center().x - _player_ref.global_position.x)
			if r.grow(42.0).has_point(_player_ref.global_position) and d < best:
				best = d
				_near_idx = i
		_near_exit = _near_idx >= 0
		if _near_exit and not _exit_used and Input.is_action_just_pressed("interact"):
			_exit_used = true
			chosen_exit = str(exits[_near_idx].kind)
			emit_signal("completed")
	queue_redraw()
	_back_decor.queue_redraw()

## A child canvas drawn behind the room itself, painted by `painter(layer)`.
func _add_paint_layer(layer_name: String, painter: Callable) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	layer.show_behind_parent = true
	layer.draw.connect(painter.bind(layer))
	add_child(layer)
	return layer

## The chamber's physics, in this child order: platforms, walls and arena rails
## as solid bodies, then the hazard triggers.
func _build_geometry() -> void:
	for plat: Rect2 in template.get("platforms", []):
		_add_solid(plat)
	# Optional 'walls' array in template — climbable vertical surfaces for wall slide/jump.
	for wall: Rect2 in template.get("walls", []):
		_add_solid(wall)
	# Invisible arena rails keep high-speed attacks and the boss inside the room
	# while leaving the authored pit hazards open underneath the platforms.
	for x in [Content.ROOM_LEFT - 24.0, Content.ROOM_RIGHT + 24.0]:
		_add_solid(Rect2(x - 24.0, -550.0, 48.0, 1400.0))
	for hazard: Rect2 in template.get("hazards", []):
		var area := Area2D.new()
		area.collision_layer = Content.L_TRIGGER
		area.collision_mask = Content.L_PLAYER_BODY | Content.L_ENEMY_BODY
		area.add_child(Content.rect_shape(hazard.size))
		area.position = hazard.get_center()
		area.body_entered.connect(_on_hazard_body)
		add_child(area)

## A static world body filling `r`.
func _add_solid(r: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Content.L_WORLD
	body.collision_mask = 0
	body.add_child(Content.rect_shape(r.size))
	body.position = r.get_center()
	add_child(body)

## Geometry-derived, deterministic dressing uses no encounter RNG draws.
## The throne is left clear for the finale: its only dressing is the candles.
func _build_props() -> void:
	# The candles placed here join the light list.
	_light_points_dirty = true
	if is_boss:
		victory_candles = mini(Save.get_victories(), MAX_DAIS_CANDLES)
		return
	var entry: Vector2 = template.get("entry", Vector2.ZERO)
	var exit: Vector2 = template.get("exit", Vector2.ZERO)
	var walls: Array = template.get("walls", [])
	var kinds: Array = CryptProp.ZONE_KINDS.get(zone, [CryptProp.Kind.URN, CryptProp.Kind.STAND])
	for platform: Rect2 in template.get("platforms", []):
		if platform.size.x < 180.0 or platform.position.y > Content.FLOOR_Y:
			continue
		var count := clampi(int(platform.size.x / 240.0), 1, 6)
		for i in range(count):
			if props.size() >= 18: return
			# Evenly spread, then nudged per chamber so no two stamp the same row.
			var nudge := (VFX.hash01(i + int(platform.position.x), dress_salt) - 0.5) * 90.0
			var point := Vector2(platform.position.x + platform.size.x * (float(i) + 0.5) / float(count) + nudge, platform.position.y)
			if absf(point.x - entry.x) < 85.0 or absf(point.x - exit.x) < 65.0:
				continue
			var against_wall := walls.any(func(wall: Rect2): return wall.grow(24.0).has_point(point + Vector2(0.0, -24.0)))
			if against_wall or not _clear_of_rifts(point):
				continue
			var prop := CryptProp.new()
			prop.position = point
			prop.kind = kinds[(props.size() + dress_salt) % kinds.size()]
			prop.z_index = 0
			prop.shattered.connect(prop_shattered.emit)
			# A broken candle stops casting light.
			prop.shattered.connect(func(_pos, _force, _color): _light_points_dirty = true)
			add_child(prop)
			props.append(prop)

## Damage and death close hitboxes, which cannot happen while the physics
## queries that reported the contact are still running, so both are deferred.
func _on_hazard_body(body: Node) -> void:
	if body is Player:
		body.hit_hazard.call_deferred(18.0)
	elif body is Enemy and not (body is Boss):
		body.ring_out.call_deferred()

## The boon rift stands at the template's exit; an alternative, when offered,
## stands 170px nearer the room so the knight passes it on the way.
func _setup_exit() -> void:
	var ex: Vector2 = template.get("exit", Vector2(1180, Content.FLOOR_Y - 80))
	_exit_rect = Rect2(ex.x - 25.0, ex.y - 45.0, 50.0, 90.0)
	exits.clear()
	for kind in exit_kinds:
		if str(kind) == "boon":
			continue
		exits.append({ "kind": str(kind), "rect": Rect2(ex.x - 195.0, ex.y - 45.0, 50.0, 90.0) })
	exits.append({ "kind": "boon", "rect": _exit_rect })

func _spawn_encounter() -> void:
	if is_boss:
		_spawn_boss()
		return
	_set_piece = Content.set_piece_for(room_index, run_seed)
	_waves = Content.generate_waves(room_index, _rng, _set_piece)
	_set_piece_wave = _waves.size() - 1 if not _set_piece.is_empty() else -1
	_wave_index = 0
	if trial and not _waves.is_empty():
		# A Trial doubles down: one more wave, and it always carries an elite.
		_waves.append((_waves[_waves.size() - 1] as Array).duplicate())
		_difficulty.hp_mul = float(_difficulty.hp_mul) * 1.15
	# At most one elite per room, placed in a random wave slot. The last chamber
	# before the throne always has one, leading its final wave as a champion.
	var gilded := Enemy.vows.has("v_gilded")
	var champion := room_index >= Content.ROOMS_BEFORE_BOSS
	if not _waves.is_empty() and (trial or gilded or champion or _rng.randf() < Content.elite_chance(room_index)):
		var w := _waves.size() - 1 if champion else _rng.randi_range(0, _waves.size() - 1)
		var wave: Array = _waves[w]
		_elite_slot = Vector2i(w, 0 if champion else _rng.randi_range(0, wave.size() - 1))
		_elite_oath = Content.roll_oath(int(wave[_elite_slot.y]), room_index, _rng)
	_spawn_wave()

func _spawn_wave() -> void:
	if _wave_index < 0 or _wave_index >= _waves.size():
		_unlock_exit()
		return
	var kinds: Array = _waves[_wave_index]
	var slots := _clear_slots()
	if slots.is_empty():
		_unlock_exit()
		return
	emit_signal("wave_started", _wave_index + 1, _waves.size())
	for i in range(kinds.size()):
		var slot: Vector2 = slots[(i + _wave_index) % slots.size()]
		# Enemies sharing a slot fan out to alternate sides so they never stack.
		var lap := i / slots.size()
		slot.x += 36.0 * float((lap + 1) / 2) * (1.0 if lap % 2 == 1 else -1.0)
		var mods := _difficulty.duplicate()
		if _elite_slot == Vector2i(_wave_index, i):
			mods["elite"] = true
			mods["oath"] = _elite_oath
		var foe := _spawn_enemy(kinds[i], slot, mods)
		if _wave_index == _set_piece_wave and _set_piece.has("stagger"):
			# First strikes spaced out, counted from the end of the spawn grace.
			foe.cd = Enemy.SPAWN_GRACE + float(_set_piece.stagger) * float(i)
	for kind in Content.DEBUTS:
		if int(Content.DEBUTS[kind]) == room_index and kinds.has(kind):
			lesson_requested.emit("debut_" + Enemy.telegraph_id(kind))

## The template's spawn slots that stand clear of the knight, so no wave lands
## on top of them; when none is clear, the farthest. The opening wave spawns
## before the knight steps in, so it measures from the entry.
func _clear_slots() -> Array:
	var slots: Array = template.get("slots", [])
	var knight := get_entry_point()
	if _wave_index > 0 and is_instance_valid(_player_ref):
		knight = _player_ref.global_position
	var clear := slots.filter(func(s: Vector2): return s.distance_to(knight) >= SPAWN_CLEARANCE)
	if clear.is_empty() and not slots.is_empty():
		var far: Vector2 = slots[0]
		for s: Vector2 in slots:
			if s.distance_to(knight) > far.distance_to(knight):
				far = s
		clear = [far]
	return clear

func wave_count() -> int:
	return _waves.size()

func _spawn_enemy(kind: int, pos: Vector2, mods: Dictionary = {}) -> Enemy:
	var e := Enemy.new()
	e.setup(kind, pos, mods)
	add_child(e)
	_relay(e)
	enemies.append(e)
	emit_signal("enemy_spawned", pos, Content.ELITE_COLOR if bool(mods.get("elite", false)) else Color(e.data.color))
	if not e.oath.is_empty():
		enemy_announced.emit("%s %s" % [e.oath.to_upper(), e.data.name], "", pos + Vector2(0.0, -float(e.data.h) - 30.0))
	return e

## Pass a creature's combat signals up as the room's own: the game listens to
## the room, never to the creatures inside it.
func _relay(foe: Enemy) -> void:
	foe.died.connect(_on_enemy_died.bind(foe))
	foe.damaged.connect(enemy_damaged.emit)
	foe.projectile_requested.connect(projectile_requested.emit)
	foe.exploded.connect(enemy_exploded.emit)
	foe.pyre_burst.connect(pyre_burst.emit)
	foe.telegraphed.connect(telegraphed.emit)
	foe.announced.connect(enemy_announced.emit)
	foe.twin_requested.connect(_on_boss_summon)

func _spawn_boss() -> void:
	boss = Boss.new()
	# The Warden waits seated on its throne and rises when the knight comes.
	boss.seated = true
	boss.trial = trial
	boss.global_position = Boss.THRONE_SEAT
	# Trial of the Throne: the Warden reads this as it readies, so it goes first.
	boss.set("trial", trial)
	add_child(boss)
	_relay(boss)
	boss.wave_requested.connect(boss_wave_requested.emit)
	boss.phase_changed.connect(boss_phase_changed.emit)
	boss.summon_requested.connect(_on_boss_summon)
	boss.shattered.connect(boss_shattered.emit)
	emit_signal("boss_spawned")

## A plain creature called into the fight mid-wave: the Warden's wisps, or
## the copy a twinned elite splits off.
func _on_boss_summon(kind: int, pos: Vector2) -> void:
	_spawn_enemy(kind, pos, _difficulty.duplicate())

## A vengeful elite's dying ring: slow embers burst from where it fell, each
## one parryable back.
func _loose_vengeance(pos: Vector2, damage: float) -> void:
	for i in range(VENGEANCE_SHARDS):
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / float(VENGEANCE_SHARDS))
		projectile_requested.emit("enemy", pos, dir * VENGEANCE_SPEED, damage, 140.0, 0, 2.2, Content.ELITE_COLOR)

func _on_enemy_died(score: int, who: Node) -> void:
	var tier := 0
	var pos := Vector2.ZERO
	var color: Color = Content.PAL.attack
	var kind := ""
	if is_instance_valid(who):
		pos = who.global_position
		color = who.data.color
		kind = "warden" if who is Boss else Enemy.telegraph_id(who.kind)
		if who is Boss:
			tier = 2
		elif who.elite:
			tier = 1
		# A creature cut down by the knight comes apart along the blow; one that
		# fell into the pit or blew itself up leaves nothing to split.
		if score > 0 and tier < 2 and not who.exploded_out:
			Severed.spawn(self, who, who._last_hit_dir, int(who.get_instance_id()))
		if who.oath == "vengeful":
			# Named at once; the embers follow a beat later, time to back off.
			enemy_announced.emit("VENGEANCE", "", pos + Vector2(0.0, -60.0))
			get_tree().create_timer(VENGEANCE_DELAY, false).timeout.connect(_loose_vengeance.bind(pos, VENGEANCE_BITE * float(who.damage_mul)))
	emit_signal("enemy_died", score, pos, tier, color, kind)
	_clean_dead()
	if is_boss:
		# Adds dying mid-fight must never unseal or "clear" the throne room.
		if not is_instance_valid(boss) or boss.dead:
			emit_signal("completed")
		return
	if enemies.is_empty():
		if _wave_index + 1 < _waves.size():
			_wave_delay = 0.85
		else:
			_unlock_exit()

func _unlock_exit() -> void:
	if _room_cleared:
		return
	_room_cleared = true
	exit_open = true
	queue_redraw()
	emit_signal("cleared", Content.room_name(template))

func _clean_dead() -> void:
	for e in enemies:
		if is_instance_valid(e) and e.dead:
			e.queue_free()
	enemies = enemies.filter(func(e): return is_instance_valid(e) and not e.dead)

func get_entry_point() -> Vector2:
	return Vector2(template.get("entry", Vector2(180, Content.FLOOR_Y - 80)))

## Rift colour and label by what lies beyond it.
static func exit_style(kind: String) -> Dictionary:
	match kind:
		"font": return { "color": Color("2be4c8"), "label": "HEALING FONT", "sigil": "rift_font" }
		"cache": return { "color": Color("ffd166"), "label": "FORGE CACHE", "sigil": "rift_cache" }
		"trial": return { "color": Color("e8405c"), "label": "TRIAL", "sigil": "rift_trial" }
	return { "color": Color("ff8a2a"), "label": "BOON", "sigil": "rift_boon" }

func _accent_for(tag: String) -> Color:
	match tag:
		"gap": return Color("4aa6b8")
		"tiers": return Color("7d70c9")
		"arena": return Color("b44c55")
		"platforms": return Color("d27a36")
		"chamber": return Color("468c86")
		"crossfire": return Color("9d425f")
		"boss": return Color("cf493f")
	return Color("9d6bff")

## The decor's clock. Reduced motion holds every decoration, hazards included,
## at its rest pose.
func _decor_t() -> float:
	return 0.0 if Feedback.motion_reduced else _ambient_t

func _mood() -> Dictionary:
	return mood if not mood.is_empty() else Content.mood_for(0.0)

## Static light sources for the light layer: braziers, candle clusters, vents.
## Both lighting passes (LightLayer's additive glow and LightRig's PointLight2Ds)
## ask for this every frame, so it is built once per chamber and rebuilt when a
## candle breaks. Callers must not mutate the result; they only read positions,
## colours and flicker rates.
var _light_points_cache: Array = []
var _light_points_dirty := true

func light_points() -> Array:
	if not _light_points_dirty:
		return _light_points_cache
	var out: Array = []
	var tag := str(template.get("tag", "intro"))
	var m := _mood()
	var torch: Color = m.torch
	match tag:
		"intro":
			out.append({ "pos": Vector2(260.0, Content.FLOOR_Y - 12.0), "radius": 70.0, "color": torch, "alpha": 0.22, "rate": 9.0, "phase": 0.0 })
			out.append({ "pos": Vector2(860.0, Content.FLOOR_Y - 12.0), "radius": 60.0, "color": torch, "alpha": 0.2, "rate": 7.0, "phase": 1.3 })
		"gap":
			out.append({ "pos": Vector2(150.0, Content.FLOOR_Y - 12.0), "radius": 60.0, "color": torch, "alpha": 0.2, "rate": 8.0, "phase": 0.4 })
		"tiers":
			out.append({ "pos": Vector2(640.0, Content.FLOOR_Y - 332.0), "radius": 70.0, "color": torch, "alpha": 0.22, "rate": 8.0, "phase": 2.0 })
		"platforms":
			out.append({ "pos": Vector2(500.0, Content.FLOOR_Y + 30.0), "radius": 120.0, "color": m.glow, "alpha": 0.25, "rate": 5.0, "phase": 0.0 })
			out.append({ "pos": Vector2(780.0, Content.FLOOR_Y + 30.0), "radius": 120.0, "color": m.glow, "alpha": 0.25, "rate": 5.0, "phase": 2.1 })
		"chamber":
			out.append({ "pos": Vector2(1120.0, Content.FLOOR_Y - 12.0), "radius": 60.0, "color": torch, "alpha": 0.2, "rate": 8.0, "phase": 0.9 })
		"crossfire":
			out.append({ "pos": Vector2(640.0, Content.FLOOR_Y - 300.0), "radius": 80.0, "color": Content.PAL.special, "alpha": 0.12, "rate": 2.0, "phase": 0.0 })
		"boss":
			out.append({ "pos": Vector2(300.0, Content.FLOOR_Y - 58.0), "radius": 160.0, "color": torch, "alpha": 0.36 * fire_heat, "rate": 8.0, "phase": 0.0 })
			out.append({ "pos": Vector2(980.0, Content.FLOOR_Y - 58.0), "radius": 160.0, "color": torch, "alpha": 0.36 * fire_heat, "rate": 8.0, "phase": 1.7 })
			out.append({ "pos": Vector2(640.0, Content.FLOOR_Y - 150.0), "radius": 220.0, "color": (m.glow as Color).lerp(VFX.GOLD, sigil_gold), "alpha": 0.16 * sigil_flare(), "rate": 3.0, "phase": 0.5 })
	# Fixed room lights retain priority in the small PointLight pool. Every candle
	# also gets its inexpensive halo from LightLayer, including those outside it.
	for prop in props:
		if is_instance_valid(prop) and prop.flame_height() > 0.0 and not prop.broken:
			out.append({ "pos": prop.global_position + Vector2(0.0, -prop.flame_height()), "radius": 72.0, "color": Color("ffac67"), "alpha": 0.16, "rate": 8.0, "phase": prop.position.x })
	# Grave flames come last, so they glow without taking the chamber's PointLights.
	for grave: Array in GRAVES.get(tag, []):
		if not grave[1]:
			out.append({ "pos": Vector2(grave[0], Content.FLOOR_Y) + GRAVE_FLAME, "radius": 46.0, "color": torch, "alpha": 0.16, "rate": 9.0, "phase": grave[0] })
	_light_points_cache = out.filter(func(lp: Dictionary) -> bool: return _clear_of_rifts(lp.pos))
	_light_points_dirty = false
	return _light_points_cache

func exit_center() -> Vector2:
	return _exit_rect.get_center()

## The chamber's fixed stonework, painted once onto the Masonry layer. Each
## platform's masonry is followed by its broken ends, in template order, so a
## later block still covers an earlier floor's ends; then the climbable walls.
func _draw_masonry_layer(ci: CanvasItem) -> void:
	var accent := _accent_for(str(template.get("tag", "intro")))
	var m := _mood()
	# Volumetric masonry: slab courses, mortar joints, a lit rim and occlusion under the lip.
	var platforms: Array = template.get("platforms", [])
	for pi in range(platforms.size()):
		var pr := Rect2(platforms[pi].position, platforms[pi].size)
		_draw_masonry(ci, pr, accent, pi + 1, m, true)
		_draw_platform_ends(ci, pr, m, pi + 1)
	# climbable walls (accent edge so players know they can wall-slide)
	var walls: Array = template.get("walls", [])
	for wi in range(walls.size()):
		var wr := Rect2(walls[wi].position, walls[wi].size)
		_draw_masonry(ci, wr, accent, 40 + wi, m)
		ci.draw_line(Vector2(wr.position.x, wr.position.y), Vector2(wr.position.x, wr.end.y), Color(accent.r, accent.g, accent.b, 0.65), 3.0)
		# A lit capital on corbels, so the wall's top reads as built, not cut off.
		var cap := Rect2(wr.get_center().x - 22.0, wr.position.y - 10.0, 44.0, 10.0)
		for side: float in [-1.0, 1.0]:
			var corner := Vector2(wr.get_center().x + side * wr.size.x * 0.5, wr.position.y)
			ci.draw_colored_polygon(PackedVector2Array([corner, corner + Vector2(side * 7.0, 0.0), corner + Vector2(0.0, 12.0)]), (m.edge as Color).darkened(0.1))
		ci.draw_rect(cap, (m.edge as Color).lightened(0.2))
		ci.draw_line(cap.position, Vector2(cap.end.x, cap.position.y), VFX.RIM, 1.5)

## Everything that moves or reacts, over the BackDecor and Masonry layers.
func _draw() -> void:
	var tag := str(template.get("tag", "intro"))
	var accent := _accent_for(tag)
	var m := _mood()
	var platforms: Array = template.get("platforms", [])
	for pi in range(platforms.size()):
		var pr := Rect2(platforms[pi].position, platforms[pi].size)
		_draw_platform_dressing(pr, m, pi + 1)
	for hz in template.get("hazards", []):
		_draw_hazard(Rect2(hz.position, hz.size), m)
	_draw_decor_front(tag, m)
	_draw_exit(m)
	if _wave_delay > 0.0:
		var wave_alpha := clampf(_wave_delay / 0.85, 0.0, 1.0)
		for slot in template.get("slots", []):
			draw_arc(slot, 22.0 * (1.0 - wave_alpha * 0.35), 0.0, TAU, 20, Color(accent.r, accent.g, accent.b, wave_alpha * 0.7), 2.0)

## Stone courses with deterministic slab widths (48/64/80) so joints never line
## up between rows, a 6px trim, a 1.5px rim catch-light and a 12px occlusion band.
## The works lay riveted iron deck plates with a furnace glow in every third
## seam; the ashpit is rough-hewn rock in deep courses with bone set into it.
##
## `walkable` marks geometry the player can stand on. Its cap is drawn as a
## distinct lit deck instead of the shared stone edge, because the mood's edge
## and stone tones sit within a few percent of each other and the walkable floor
## was reading as the same material as the wall behind it. Knowing what you can
## stand on must not depend on inferring it from where the props sit.
func _draw_masonry(ci: CanvasItem, pr: Rect2, accent: Color, salt: int, m: Dictionary, walkable: bool = false) -> void:
	var lip := 6.0
	var stone: Color = m.stone
	var base := stone.darkened(0.22)
	var plated := zone == "works"
	var hewn := zone == "ashpit"
	var seam := Color(m.glow, 0.45 * float(m.ember_seep))
	ci.draw_rect(pr, base)
	var y := pr.position.y + lip
	var row := 0
	while y < pr.end.y - 1.0:
		# Course heights vary per row. A constant vertical rhythm is the one part
		# of the masonry that genuinely repeated, and it is what makes the wall
		# read as printed wallpaper rather than laid stone. Horizontal variation
		# (slab widths, tones, cracks) already existed; this is the missing axis.
		var row_h := (16.0 if row < 3 else 26.0) + (VFX.hash01(row * 29 + salt, 71) - 0.5) * 6.0
		if hewn:
			row_h = 20.0 + VFX.hash01(row * 29 + salt, 71) * 14.0
		row_h = minf(row_h, pr.end.y - y)
		var x := pr.position.x - VFX.hash01(row + salt * 7, 3) * 56.0
		var col := 0
		while x < pr.end.x:
			var pick := VFX.hash01(col * 31 + row * 17, salt)
			var slab_w := 48.0 if pick < 0.34 else (64.0 if pick < 0.67 else 80.0)
			if plated:
				slab_w = 96.0
			var x0 := maxf(x, pr.position.x)
			var x1 := minf(x + slab_w, pr.end.x)
			if x1 > x0 + 1.0:
				var tone := (VFX.hash01(col * 13 + row * 5, salt + 11) - 0.5) * 0.10
				if tone < -0.015:
					ci.draw_rect(Rect2(x0, y, x1 - x0, row_h), Color(0.0, 0.0, 0.0, -tone))
				elif tone > 0.015:
					ci.draw_rect(Rect2(x0, y, x1 - x0, row_h), Color(1.0, 1.0, 1.0, tone * 0.5))
				# Occasional crack across a slab.
				if VFX.hash01(col * 7 + row * 3, salt + 23) > 0.86 and x1 - x0 > 30.0:
					var cx := x0 + (x1 - x0) * 0.5
					ci.draw_polyline(PackedVector2Array([
						Vector2(cx - 8.0, y + 2.0), Vector2(cx - 2.0, y + row_h * 0.45), Vector2(cx + 5.0, y + row_h * 0.6), Vector2(cx + 3.0, y + row_h - 2.0),
					]), VFX.JOINT, 1.5)
				if hewn and pick > 0.94 and x1 - x0 > 40.0:
					# A long bone set into the rock.
					var by := y + row_h * 0.5
					ci.draw_line(Vector2(x0 + 12.0, by + 2.0), Vector2(x0 + 34.0, by - 2.0), Color("bdb3a3").darkened(0.5), 3.0)
				if x + slab_w < pr.end.x - 1.0:
					var jx := x + slab_w
					ci.draw_line(Vector2(jx, y), Vector2(jx, y + row_h), VFX.JOINT, 2.0)
					if plated:
						if col % 3 == 2:
							ci.draw_line(Vector2(jx, y + 2.0), Vector2(jx, y + row_h - 2.0), seam, 1.5)
						for corner in [Vector2(-5.0, 4.0), Vector2(5.0, 4.0), Vector2(-5.0, row_h - 4.0), Vector2(5.0, row_h - 4.0)]:
							ci.draw_circle(Vector2(jx, y) + corner, 1.5, stone.lightened(0.12))
			x += slab_w
			col += 1
		if y + row_h < pr.end.y - 1.0:
			ci.draw_line(Vector2(pr.position.x, y + row_h), Vector2(pr.end.x, y + row_h), VFX.JOINT, 2.0)
		y += row_h
		row += 1
	VFX.draw_vgradient(ci, Rect2(pr.position.x, pr.position.y + lip, pr.size.x, 12.0), Color(0.03, 0.016, 0.06, 0.7), Color(0.03, 0.016, 0.06, 0.0))
	if walkable:
		# A lit deck: the stone edge family is too close to the wall tone to read
		# on its own, so the standing surface is lifted and the body below it is
		# sunk, giving one strong value break exactly where the feet land.
		var deck: Color = (m.edge as Color).lightened(0.22)
		ci.draw_rect(Rect2(pr.position, Vector2(pr.size.x, lip + 4.0)), deck)
		ci.draw_rect(Rect2(pr.position + Vector2(0.0, lip + 4.0), Vector2(pr.size.x, 8.0)), Color(0.0, 0.0, 0.0, 0.28))
		ci.draw_line(Vector2(pr.position.x, pr.position.y + 1.0), Vector2(pr.end.x, pr.position.y + 1.0), deck.lightened(0.45), 2.0)
		if hewn:
			# Rough rock breaks the deck's lower edge; the standing line stays true.
			var lip_pts := PackedVector2Array()
			for i in range(int(pr.size.x / 14.0) + 1):
				lip_pts.append(Vector2(pr.position.x + float(i) * 14.0, pr.position.y + lip + 4.0 + (VFX.hash01(i, salt + 31) - 0.5) * 6.0))
			ci.draw_polyline(lip_pts, VFX.JOINT, 2.0)
	else:
		ci.draw_rect(Rect2(pr.position, Vector2(pr.size.x, lip)), (m.edge as Color).lightened(0.12))
	ci.draw_rect(Rect2(pr.position + Vector2(0.0, lip), Vector2(pr.size.x, 2.0)), Color(accent.r, accent.g, accent.b, 0.28))
	ci.draw_line(Vector2(pr.position.x, pr.position.y + 0.75), Vector2(pr.end.x, pr.position.y + 0.75), VFX.RIM, 1.5)
	ci.draw_rect(Rect2(pr.position.x, pr.end.y - 2.0, pr.size.x, 2.0), VFX.JOINT)

## Jagged broken corners on ends that hang over a drop, with loose stones
## tumbling off the lip. Fixed for the chamber, so they paint with the masonry.
func _draw_platform_ends(ci: CanvasItem, pr: Rect2, m: Dictionary, salt: int) -> void:
	var stone: Color = m.stone
	for side: float in [-1.0, 1.0]:
		var ex := pr.position.x if side < 0.0 else pr.end.x
		if ex <= Content.ROOM_LEFT + 1.0 or ex >= Content.ROOM_RIGHT - 1.0:
			continue
		var pts := PackedVector2Array([Vector2(ex, pr.position.y + 4.0)])
		var depth := minf(pr.size.y, 70.0)
		for i in range(1, 5):
			var u := float(i) / 5.0
			pts.append(Vector2(ex + side * (4.0 + VFX.hash01(salt * 5 + i, 91) * 16.0), pr.position.y + 4.0 + u * depth))
		pts.append(Vector2(ex, pr.position.y + depth + 4.0))
		ci.draw_colored_polygon(pts, stone.darkened(0.3))
		ci.draw_polyline(pts, VFX.JOINT, 1.5)
		for i in range(3):
			var sy := pr.position.y + depth + 10.0 + float(i) * 14.0 + VFX.hash01(salt + i, 92) * 8.0
			var sx := ex + side * (6.0 + VFX.hash01(salt + i, 93) * 14.0)
			ci.draw_rect(Rect2(sx - 4.0, sy, 8.0 - float(i), 5.0), stone.darkened(0.35 + float(i) * 0.1))

## Ash tufts, moss drips in the crypt, ember veins nearer the forge.
func _draw_platform_dressing(pr: Rect2, m: Dictionary, salt: int) -> void:
	var t := _decor_t()
	var seep := float(m.ember_seep)
	var moss := float(m.moss)
	# Surface dressing along the top edge.
	var count := int(pr.size.x / 46.0)
	for i in range(count):
		var h := VFX.hash01(i * 3 + salt, 94)
		var x := pr.position.x + 12.0 + float(i) * 46.0 + h * 20.0
		if x > pr.end.x - 8.0:
			continue
		var yy := pr.position.y
		if moss > 0.05 and h > 0.55:
			# Pale ash tuft.
			var sway := sin(t * 2.0 + float(i)) * 1.5
			var tuft := Color(VFX.SLATE.lightened(0.2), 0.45 * moss)
			draw_line(Vector2(x, yy), Vector2(x - 3.0 + sway, yy - 7.0), tuft, 1.5)
			draw_line(Vector2(x + 2.0, yy), Vector2(x + 4.0 + sway, yy - 9.0), tuft, 1.5)
			draw_line(Vector2(x + 4.0, yy), Vector2(x + 7.0 + sway, yy - 5.0), tuft, 1.5)
		if seep > 0.05 and h < 0.4:
			# Ember veins glowing in the mortar.
			var pulse := 0.5 + 0.5 * sin(t * 3.0 + float(i) * 1.7)
			var vein := Color(m.glow, (0.35 + 0.4 * pulse) * seep)
			var vy := yy + 24.0 + h * 30.0
			draw_polyline(PackedVector2Array([Vector2(x - 10.0, vy), Vector2(x - 2.0, vy + 4.0), Vector2(x + 6.0, vy - 3.0), Vector2(x + 16.0, vy + 2.0)]), vein, 1.5)
	# Moss drips under the lip in the crypt.
	if moss > 0.05:
		var drips := int(pr.size.x / 90.0)
		for i in range(drips):
			var x := pr.position.x + 30.0 + float(i) * 90.0 + VFX.hash01(i + salt, 95) * 40.0
			if x > pr.end.x - 10.0:
				continue
			var len := 6.0 + VFX.hash01(i + salt, 96) * 14.0
			var by := pr.end.y - 2.0
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, by), Vector2(x + 4.0, by), Vector2(x + 1.0, by + len), Vector2(x - 1.0, by + len * 0.7)]), Color("2f6b4a", 0.55 * moss))

## A pit drawn in what fills it (see _pit_material); the hitbox never changes.
## Reduced motion holds the surface still and drops the drifting embers.
func _draw_hazard(r: Rect2, m: Dictionary) -> void:
	var t := _decor_t()
	var seep := float(m.ember_seep)
	var fill := _pit_material()
	match fill:
		"water":
			# Black water under a moonlit skin, rings spreading where the drips land.
			draw_rect(r, Color("070b14"))
			for i in range(3):
				var k := fmod(t / 3.0 + float(i) / 3.0, 1.0)
				var ring := Vector2(r.position.x + r.size.x * (0.2 + 0.3 * float(i)), r.position.y + 12.0)
				VFX.draw_ellipse_ring(self, ring, 4.0 + k * 22.0, 1.0 + k * 5.5, Color(m.moon, 0.3 * (1.0 - k)), 1.2)
			draw_line(Vector2(r.position.x, r.position.y + 12.0), Vector2(r.end.x, r.position.y + 12.0), Color(m.moon, 0.35), 2.0)
		"crust":
			# Grey ash plates floating on embers that glow through every crack.
			draw_rect(r, Color("140e10"))
			draw_rect(Rect2(r.position.x, r.position.y + 8.0, r.size.x, 30.0), Color(m.glow, 0.65 + 0.15 * sin(t * 2.0)))
			var n := maxi(1, roundi(r.size.x / 44.0))
			var span := r.size.x / float(n)
			for i in range(n):
				var c := Vector2(r.position.x + (float(i) + 0.5) * span, r.position.y + 22.0)
				var sides := 5 + int(VFX.hash01(i, 99) * 3.0)
				var plate := PackedVector2Array()
				for j in range(sides):
					var a := TAU * float(j) / float(sides) + VFX.hash01(i, 100)
					plate.append(c + Vector2(cos(a) * span * 0.55, sin(a) * 15.0) * (0.8 + 0.2 * VFX.hash01(i * 7 + j, 101)))
				draw_colored_polygon(plate, Color("2e2628"))
		_:
			draw_rect(r, Color("35121c").lerp(Color("4a1408"), seep))
			if seep > 0.05:
				# Magma skin: glowing gradient and slow bubbles.
				VFX.draw_vgradient(self, Rect2(r.position.x, r.position.y + 12.0, r.size.x, 48.0), Color(m.glow, 0.42 * seep), Color(m.glow, 0.0))
				for i in range(int(r.size.x / 54.0)):
					var ph := fmod(t * 0.7 + VFX.hash01(i, 97) * 3.0, 3.0)
					var bx := r.position.x + 27.0 + float(i) * 54.0 + VFX.hash01(i, 98) * 20.0
					draw_arc(Vector2(bx, r.position.y + 26.0), 3.0 + ph * 4.0, 0.0, TAU, 12, Color(m.glow, (1.0 - ph / 3.0) * 0.6 * seep), 1.5)
			draw_rect(Rect2(r.position, Vector2(r.size.x, 22.0)), Color(0.75, 0.16, 0.12, 0.18 + sin(t * 4.0) * 0.04))
	_draw_stakes(r, fill, m)
	if fill == "water" or Feedback.motion_reduced:
		return
	for i in range(7):
		var ember_x := r.position.x + fmod(float(i * 79) + t * (18.0 + float(i)), maxf(1.0, r.size.x))
		var ember_y := r.position.y + 10.0 - fmod(t * (12.0 + float(i) * 2.0) + float(i * 9), 34.0)
		draw_circle(Vector2(ember_x, ember_y), 1.5 + float(i % 2), Color(1.0, 0.35, 0.12, 0.55))

## What fills this chamber's pits: black water under the dripping Hollow Shaft
## (and in any crypt pit), magma in the works, an ash crust over the ashpit's.
func _pit_material() -> String:
	if str(template.get("tag", "")) == "chamber":
		return "water"
	return { "works": "magma", "ashpit": "crust" }.get(zone, "water")

## The pit's teeth: the old red spikes in magma, pale bone stakes in water and
## charred iron through the crust, the stakes leaning a little off true.
func _draw_stakes(r: Rect2, fill: String, m: Dictionary) -> void:
	var seep := float(m.ember_seep)
	var body := Color("8e3340").lerp(Color("3a2a2e"), seep * 0.6)
	var edge := Color(VFX.HOT, 0.12 + seep * 0.25)
	if fill == "water":
		body = Color("bdb3a3").darkened(0.45)
		edge = Color("bdb3a3").darkened(0.1)
	elif fill == "crust":
		body = Color("2a2226")
		edge = Color(m.glow, 0.5)
	var half := 14.0 if fill == "magma" else 7.0
	for i in range(int(r.size.x / 28.0)):
		var foot := Vector2(r.position.x + 14.0 + float(i) * 28.0, r.position.y + 18.0)
		var lean := 0.0 if fill == "magma" else (VFX.hash01(i, 102) - 0.5) * 8.0
		var tip := Vector2(foot.x + lean, r.position.y - 10.0 - float(i % 3) * 3.0)
		draw_colored_polygon(PackedVector2Array([foot - Vector2(half, 0.0), tip, foot + Vector2(half, 0.0)]), body)
		draw_line(foot, tip, edge, 1.0)

## Rift gates: runed pillars, a keystone arch and, once unsealed, a turning
## vortex in the colour of what lies beyond, with its sigil hung over the arch.
func _draw_exit(m: Dictionary) -> void:
	if is_boss:
		return  # The throne room has no rift; the Warden's death ends the run.
	for i in range(exits.size()):
		_draw_rift((exits[i].rect as Rect2).get_center(), str(exits[i].kind), m, i == _near_idx, i)

func _draw_rift(c: Vector2, kind: String, m: Dictionary, near: bool, salt: int) -> void:
	var t := _decor_t()
	var style := exit_style(kind)
	var ec: Color = style.color if exit_open else Color("555560")
	var stone: Color = (m.stone as Color).lightened(0.1)
	var ph := float(salt) * 1.7
	# Pillars with rune notches that light when the way is open.
	for side: float in [-1.0, 1.0]:
		var px := c.x + side * 30.0
		draw_rect(Rect2(px - 5.0, c.y - 44.0, 10.0, 88.0), stone)
		draw_rect(Rect2(px - 7.0, c.y - 48.0, 14.0, 6.0), stone.lightened(0.1))
		for i in range(4):
			var ry := c.y - 32.0 + float(i) * 18.0
			var lit := exit_open and (fmod(t * 2.0 + float(i) * 0.7 + ph, 4.0) < 3.0)
			draw_rect(Rect2(px - 2.5, ry, 5.0, 8.0), Color(ec, 0.9 if lit else 0.35))
	draw_arc(c + Vector2(0.0, -28.0), 30.0, PI, TAU, 20, stone.darkened(0.1), 8.0)
	draw_rect(Rect2(c.x - 5.0, c.y - 62.0, 10.0, 8.0), Color(ec, 0.9 if exit_open else 0.4))
	if exit_open:
		var pulse := 0.82 + sin(t * 5.0 + ph) * 0.12
		draw_circle(c, 30.0 * pulse, Color(ec, 0.14))
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0.0, -30.0), c + Vector2(18.0, 0.0),
			c + Vector2(0.0, 30.0), c + Vector2(-18.0, 0.0),
		]), Color(ec, 0.2))
		for i in range(3):
			var a0 := t * 1.6 + float(i) * TAU / 3.0 + ph
			draw_arc(c, 9.0 + float(i) * 6.0, a0, a0 + PI * 1.2, 18, Color(ec, 0.75 - float(i) * 0.18), 2.5)
			draw_arc(c, 26.0 - float(i) * 4.0, -a0 * 1.3, -a0 * 1.3 + PI * 0.9, 14, Color(VFX.HOT, 0.3), 1.5)
		draw_circle(c, 5.0 + sin(t * 8.0 + ph) * 1.5, Color(VFX.HOT, 0.85))
		for i in range(7):
			var rise := fmod(t * (28.0 + float(i) * 6.0) + float(i * 13), 72.0)
			var mx := c.x + sin(t * 2.0 + float(i) * 1.1) * 12.0
			draw_circle(Vector2(mx, c.y + 34.0 - rise), 1.6, Color(ec, 0.7 * (1.0 - rise / 72.0)))
		# The promise over the arch: a medallion carrying what lies beyond.
		var bob := sin(t * 2.2 + ph) * 3.0
		var mc := c + Vector2(0.0, -96.0 + bob)
		draw_circle(mc + Vector2(2.0, 3.0), 19.0, Color(0.0, 0.0, 0.0, 0.45))
		draw_circle(mc, 19.0, Color("120e19"))
		draw_arc(mc, 19.0, 0.0, TAU, 32, Color(ec, 0.9), 2.0, true)
		BoonArt.draw(self, str(style.sigil), mc, 12.0, ec)
		if near:
			var font := ThemeDB.fallback_font
			var label := UI.prompt("interact") + "  " + str(style.label)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			draw_string_outline(font, mc + Vector2(-w * 0.5, -30.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color("100c1b"))
			draw_string(font, mc + Vector2(-w * 0.5, -30.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ec)
	else:
		# Sealed: iron bar across the gate and a dim lock glyph.
		draw_line(Vector2(c.x - 34.0, c.y - 6.0), Vector2(c.x + 34.0, c.y - 6.0), Color("2a2430"), 5.0)
		draw_line(Vector2(c.x - 34.0, c.y + 10.0), Vector2(c.x + 34.0, c.y + 10.0), Color("2a2430"), 5.0)
		draw_arc(c, 18.0, 0.0, TAU, 20, ec, 2.5)
		draw_line(c - Vector2(10.0, 10.0), c + Vector2(10.0, 10.0), ec, 2.5)
		draw_line(c - Vector2(-10.0, 10.0), c + Vector2(-10.0, -10.0), ec, 2.5)

# --- Props --------------------------------------------------------------------

## Hand-placed floor dressing never stands in a rift's doorway, whichever rifts
## the chamber rolled.
func _clear_of_rifts(pos: Vector2) -> bool:
	# The throne room never opens a rift, so its lights and dressing stay put.
	return is_boss or not exits.any(func(e: Dictionary) -> bool: return (e.rect as Rect2).grow(45.0).has_point(pos))

func _candles(base: Vector2, n: int, t: float, m: Dictionary, flame: float = 1.0) -> void:
	if not _clear_of_rifts(base):
		return
	for i in range(n):
		var h := VFX.hash01(i, 101)
		var x := base.x + (float(i) - float(n - 1) * 0.5) * 11.0 + (h - 0.5) * 4.0
		var height := 8.0 + h * 12.0
		draw_rect(Rect2(x - 2.5, base.y - height, 5.0, height), Color("d8cfc0").darkened(0.35))
		draw_rect(Rect2(x - 3.5, base.y - height * 0.3, 7.0, 3.0), Color("d8cfc0").darkened(0.5))
		if flame > 0.15:
			VFX.draw_flame(self, Vector2(x, base.y - height), 9.0 * flame, 4.0 * flame, t, float(i) * 1.7, m.torch, VFX.GOLD)
	draw_rect(Rect2(base.x - float(n) * 6.0, base.y - 2.0, float(n) * 12.0, 3.0), Color(0.0, 0.0, 0.0, 0.35))

func _bone_pile(base: Vector2, m: Dictionary) -> void:
	if not _clear_of_rifts(base):
		return
	var bone := Color("bdb3a3").lerp(m.stone, 0.35)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-26.0, 0.0), base + Vector2(-14.0, -10.0), base + Vector2(2.0, -14.0), base + Vector2(18.0, -8.0), base + Vector2(28.0, 0.0)]), bone.darkened(0.45))
	draw_line(base + Vector2(-18.0, -4.0), base + Vector2(4.0, -9.0), bone, 3.0, true)
	draw_line(base + Vector2(-2.0, -2.0), base + Vector2(20.0, -5.0), bone, 3.0, true)
	draw_circle(base + Vector2(8.0, -14.0), 6.0, bone)
	draw_circle(base + Vector2(6.0, -15.0), 1.5, VFX.VOID)
	draw_circle(base + Vector2(11.0, -15.0), 1.5, VFX.VOID)
	draw_rect(Rect2(base.x + 5.0, base.y - 10.0, 6.0, 3.0), VFX.VOID)

func _chain(ci: CanvasItem, from: Vector2, length: float, sway: float, weight: bool = true) -> void:
	var to := from + Vector2(sway, length)
	ci.draw_dashed_line(from, to, Color("3a3245"), 2.5, 5.0)
	if weight:
		ci.draw_rect(Rect2(to.x - 5.0, to.y, 10.0, 8.0), Color("2a2430"))

func _banner_prop(ci: CanvasItem, top: Vector2, length: float, t: float, m: Dictionary, k: int) -> void:
	var sway := sin(t * 0.9 + float(k)) * 4.0
	var bc: Color = m.banner
	ci.draw_line(top + Vector2(-26.0, 0.0), top + Vector2(26.0, 0.0), Color("3a3245"), 4.0)
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(-20.0, 0.0), top + Vector2(20.0, 0.0), top + Vector2(20.0 + sway, length - 20.0),
		top + Vector2(sway, length), top + Vector2(-20.0 + sway, length - 20.0),
	]), bc)
	ci.draw_line(top + Vector2(-20.0, 0.0), top + Vector2(-20.0 + sway, length - 20.0), Color(VFX.RIM, 0.15), 1.0)
	VFX.draw_flame(ci, top + Vector2(sway * 0.5, length * 0.58), 16.0, 9.0, 0.0, 0.0, Color(m.torch, 0.6), Color(VFX.GOLD, 0.4))

func _brazier(base: Vector2, t: float, m: Dictionary) -> void:
	var iron := Color("2a2430")
	draw_rect(Rect2(base.x - 4.0, base.y - 40.0, 8.0, 40.0), iron)
	draw_rect(Rect2(base.x - 16.0, base.y - 4.0, 32.0, 4.0), iron)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-22.0, -40.0), base + Vector2(22.0, -40.0), base + Vector2(14.0, -56.0), base + Vector2(-14.0, -56.0)]), iron.lightened(0.1))
	draw_arc(base + Vector2(0.0, -40.0), 22.0, PI, TAU, 16, iron.lightened(0.2), 3.0)
	# The flames lean toward the throne as it calls.
	draw_set_transform(base + Vector2(0.0, -54.0), fire_lean * 0.45 * signf(640.0 - base.x))
	for i in range(3):
		VFX.draw_flame(self, Vector2(-9.0 + float(i) * 9.0, 0.0), (30.0 - float(i % 2) * 8.0) * fire_heat, 12.0, t, float(i) * 2.2, m.torch, VFX.GOLD)
	draw_set_transform(Vector2.ZERO)
	draw_circle(base + Vector2(0.0, -2.0), 26.0, Color(m.torch, 0.06 * fire_heat))

## The Ember Throne on its dais. The finale can grey it to ash or split it:
## each half then tips outward about its outer foot, the crack between them
## jagged, and the sigil is gone. Public so the ending can paint it again
## once the rest of the keep has gone dark.
func paint_throne(ci: CanvasItem, base: Vector2, m: Dictionary) -> void:
	var stone: Color = (m.stone as Color).darkened(0.1).lerp(THRONE_ASH, throne_ash)
	var rim: Color = (m.torch as Color).lerp(THRONE_ASH.lightened(0.3), throne_ash)
	# Dais steps with gilt nosing and a crimson runner up to the seat.
	for i in range(3):
		var w := 300.0 - float(i) * 60.0
		var y := base.y - 14.0 * float(i + 1)
		ci.draw_rect(Rect2(base.x - w * 0.5, y, w, 14.0), stone.lightened(0.05 * float(i)))
		ci.draw_rect(Rect2(base.x - 30.0, y, 60.0, 14.0), (m.banner as Color).lerp(stone, throne_ash).lightened(0.1))
		ci.draw_line(Vector2(base.x - w * 0.5, y), Vector2(base.x + w * 0.5, y), Color(VFX.GOLD, 0.5 * (1.0 - throne_ash)), 2.0)
	var seat := base + Vector2(0.0, -42.0)
	if throne_split > 0.0:
		for side: float in [-1.0, 1.0]:
			ci.draw_set_transform(seat + Vector2(side * 78.0, 0.0), side * 0.16 * throne_split)
			_throne_half(ci, Vector2(-side * 78.0 + side * 10.0 * throne_split, 0.0), side, stone, rim)
		ci.draw_set_transform(Vector2.ZERO)
		return
	# Back with a crown of blades, cut and bevelled like the rest of the set.
	var back := PackedVector2Array([seat + Vector2(-60.0, 0.0), seat + Vector2(-60.0, -190.0), seat + Vector2(60.0, -190.0), seat + Vector2(60.0, 0.0)])
	VFX.draw_shaded_polygon(ci, back, stone.darkened(0.15))
	VFX.draw_rim(ci, back, 1.0, 0.6, rim)
	for i in range(7):
		var x := seat.x - 54.0 + float(i) * 18.0
		var h := 40.0 + (24.0 if i == 3 else (12.0 if i % 2 == 0 else 0.0))
		var blade := PackedVector2Array([Vector2(x - 6.0, seat.y - 190.0), Vector2(x, seat.y - 190.0 - h), Vector2(x + 6.0, seat.y - 190.0)])
		ci.draw_colored_polygon(blade, stone.darkened(0.05))
		VFX.draw_rim(ci, blade, 1.0, 0.6, rim)
	# Armrests and seat.
	ci.draw_rect(Rect2(seat.x - 78.0, seat.y - 70.0, 18.0, 70.0), stone)
	ci.draw_rect(Rect2(seat.x + 60.0, seat.y - 70.0, 18.0, 70.0), stone)
	ci.draw_rect(Rect2(seat.x - 60.0, seat.y - 30.0, 120.0, 30.0), stone.lightened(0.06))
	# Ember sigil burning in the backrest: the Warden's red, or the knight's gold.
	var heat := sigil_flare()
	var fire: Color = (m.torch as Color).lerp(VFX.GOLD, sigil_gold)
	ci.draw_circle(seat + Vector2(0.0, -120.0), 22.0, Color((m.glow as Color).lerp(VFX.GOLD, sigil_gold), 0.25 * heat))
	if heat > 0.02:
		VFX.draw_flame(ci, seat + Vector2(0.0, -104.0), 34.0 * heat, 18.0, _decor_t(), 0.0, Color(fire, minf(1.0, 0.85 * heat)), VFX.GOLD.lerp(VFX.HOT, sigil_gold))
	ci.draw_arc(seat + Vector2(0.0, -120.0), 30.0, 0.0, TAU, 28, Color(fire, 0.35 * heat), 2.0)

## One half of the split throne, drawn about the seat's centre at `seat`: its
## half of the back ending in the crack, its blades, armrest and half seat.
func _throne_half(ci: CanvasItem, seat: Vector2, side: float, stone: Color, rim: Color) -> void:
	var crack := PackedVector2Array()
	for k in range(9):
		var y := -190.0 + 190.0 * float(k) / 8.0
		crack.append(seat + Vector2(side * (2.0 + 7.0 * VFX.hash01(k, 91)), y))
	var back := PackedVector2Array([seat + Vector2(side * 60.0, 0.0), seat + Vector2(side * 60.0, -190.0)])
	back.append_array(crack)
	VFX.draw_shaded_polygon(ci, back, stone.darkened(0.15))
	VFX.draw_rim(ci, back, 1.0, 0.6, rim)
	ci.draw_polyline(crack, Color(VFX.VOID, 0.9), 2.0)
	for i in [4, 5, 6]:
		var x := seat.x + side * (float(i) * 18.0 - 54.0)
		var h := 40.0 + (12.0 if i % 2 == 0 else 0.0)
		var blade := PackedVector2Array([Vector2(x - 6.0, seat.y - 190.0), Vector2(x, seat.y - 190.0 - h), Vector2(x + 6.0, seat.y - 190.0)])
		ci.draw_colored_polygon(blade, stone.darkened(0.05))
		VFX.draw_rim(ci, blade, 1.0, 0.6, rim)
	ci.draw_rect(Rect2(seat.x + (60.0 if side > 0.0 else -78.0), seat.y - 70.0, 18.0, 70.0), stone)
	ci.draw_rect(Rect2(seat.x + (2.0 if side > 0.0 else -60.0), seat.y - 30.0, 58.0, 30.0), stone.lightened(0.06))


## Sigil heat as drawn (the apse window shares it): reduced flash caps the
## finale's flare.
func sigil_flare() -> float:
	return minf(sigil_heat, 1.2) if Feedback.flash_reduced else sigil_heat

func _gear(ci: CanvasItem, c: Vector2, r: float, angle: float, m: Dictionary) -> void:
	var iron := (m.stone as Color).darkened(0.3)
	var teeth := int(r / 6.0)
	var pts := PackedVector2Array()
	for i in range(teeth * 2):
		var a := angle + TAU * float(i) / float(teeth * 2)
		var rr := r if i % 2 == 0 else r * 0.82
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, iron)
	ci.draw_circle(c, r * 0.5, (m.wall as Color))
	ci.draw_arc(c, r * 0.5, 0.0, TAU, 24, Color(VFX.RIM, 0.25), 2.0)
	ci.draw_circle(c, r * 0.12, iron.lightened(0.15))
	for i in range(4):
		var a := angle + float(i) * PI * 0.5
		ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.14, c + Vector2(cos(a), sin(a)) * r * 0.5, iron.lightened(0.12), 5.0)

func _pipe(ci: CanvasItem, from: Vector2, to: Vector2, m: Dictionary) -> void:
	var iron := (m.stone as Color).darkened(0.28)
	ci.draw_line(from, to, iron, 12.0)
	ci.draw_line(from + Vector2(0.0, -3.0), to + Vector2(0.0, -3.0), Color(VFX.RIM, 0.14), 2.0)
	var n := int(from.distance_to(to) / 120.0)
	for i in range(n + 1):
		var p := from.lerp(to, float(i) / maxf(1.0, float(n)))
		ci.draw_rect(Rect2(p.x - 5.0, p.y - 9.0, 10.0, 18.0), iron.lightened(0.1))

func _roots(ci: CanvasItem, top: Vector2, t: float, m: Dictionary) -> void:
	var root := Color("2b1d12").lerp(m.stone, 0.2)
	for i in range(5):
		var h := VFX.hash01(i, 111)
		var x := top.x + (float(i) - 2.0) * 16.0
		var len := 80.0 + h * 140.0
		var sway := sin(t * 0.8 + float(i)) * 4.0
		ci.draw_polyline(PackedVector2Array([Vector2(x, top.y), Vector2(x + 6.0 + sway, top.y + len * 0.4), Vector2(x - 4.0 + sway, top.y + len * 0.75), Vector2(x + 3.0 + sway * 1.5, top.y + len)]), root, 4.0 - h * 2.0)
		if float(m.moss) > 0.05:
			ci.draw_circle(Vector2(x + 3.0 + sway * 1.5, top.y + len), 3.0, Color("2f6b4a", 0.6 * float(m.moss)))

func _drip(x: float, y0: float, y1: float, t: float) -> void:
	var d := fmod(t * 160.0, y1 - y0 + 40.0)
	var y := y0 + d
	if y < y1:
		draw_line(Vector2(x, y - 8.0), Vector2(x, y), Color(0.6, 0.75, 0.9, 0.5), 1.5)
		draw_circle(Vector2(x, y), 1.8, Color(0.7, 0.85, 1.0, 0.6))
	else:
		var r := (y - y1) / 40.0
		draw_arc(Vector2(x, y1), 4.0 + r * 12.0, 0.0, TAU, 12, Color(0.7, 0.85, 1.0, 0.5 * (1.0 - r)), 1.0)

## A floor-standing gallows: a 330px post, a beam reaching `reach` out over the
## pit (negative reaches left) on a braced corner, and a cage on a long chain.
func _gallows(ci: CanvasItem, base: Vector2, reach: float, t: float, m: Dictionary) -> void:
	var wood := Color("2b1d12").lerp(m.stone, 0.25)
	var top := base.y - 330.0
	var dir := signf(reach)
	ci.draw_rect(Rect2(base.x - 7.0, top, 14.0, 330.0), wood)
	ci.draw_rect(Rect2(minf(base.x, base.x + reach) - 7.0, top, absf(reach) + 14.0, 12.0), wood)
	ci.draw_line(Vector2(base.x, top + 56.0), Vector2(base.x + dir * 56.0, top + 6.0), wood, 7.0)
	ci.draw_rect(Rect2(base.x - 16.0, base.y - 10.0, 32.0, 10.0), wood.darkened(0.2))
	_hanging_cage(ci, Vector2(base.x + reach - dir * 12.0, top + 12.0), 150.0, sin(t * 0.7 + reach) * 5.0)

## An iron gibbet cage hung on a chain from `hook`, holding a skull.
func _hanging_cage(ci: CanvasItem, hook: Vector2, length: float, sway: float) -> void:
	_chain(ci, hook, length, sway, false)
	var cage := hook + Vector2(sway, length)
	var iron := Color("2a2430")
	ci.draw_arc(cage + Vector2(0.0, 8.0), 14.0, PI, TAU, 12, iron, 2.5)
	for i in range(5):
		var cx := cage.x - 12.0 + float(i) * 6.0
		ci.draw_line(Vector2(cx, cage.y + 8.0), Vector2(cx + sway * 0.1, cage.y + 40.0), iron, 2.0)
	ci.draw_line(cage + Vector2(-14.0, 40.0), cage + Vector2(14.0, 40.0), iron, 3.0)
	ci.draw_circle(cage + Vector2(0.0, 24.0), 4.0, Color("bdb3a3").darkened(0.3))

func _stain(base: Vector2, w: float, color: Color) -> void:
	VFX.draw_ellipse(self, base + Vector2(0.0, -1.0), w * 0.5, 4.0, color)
	VFX.draw_ellipse(self, base + Vector2(w * 0.2, -1.0), w * 0.22, 2.5, color)

## Knight graves in the crypt chambers, [x, open] along the floor: the keep
## lights a flame on each, and the first chamber keeps the one this knight got
## up from. Their flames glow in the light layer too (see light_points).
const GRAVES := {
	"intro": [[-12.0, false], [40.0, false], [100.0, true]],
	"tiers": [[590.0, false], [650.0, false]],
	"arena": [[300.0, false], [364.0, false], [428.0, false]],
}
## Where a grave's flame burns, from the grave's foot.
const GRAVE_FLAME := Vector2(15.0, -12.0)

## A headstone, feet at the origin: a slab with a rounded head.
const GRAVE_STONE := [
	Vector2(-11, 0), Vector2(-11, -22), Vector2(-9.5, -27.5), Vector2(-5.5, -31.5), Vector2(0, -33),
	Vector2(5.5, -31.5), Vector2(9.5, -27.5), Vector2(11, -22), Vector2(11, 0),
]

## A knight's grave in the crypt: a headstone cut with the knight's crowned
## mask, a low mound, and the small flame the keep lights on every one. The
## `open` grave is the one this knight got up from (the first chamber's): dug
## out from inside, its stone knocked askew and its cup cold, because the
## flame walked away in the knight.
func _grave(base: Vector2, t: float, m: Dictionary, k: int, open := false) -> void:
	if not _clear_of_rifts(base):
		return
	var earth := (m.wall as Color).darkened(0.3)
	var xf := Transform2D(-0.32 if open else 0.0, base + (Vector2(-9.0, 2.0) if open else Vector2.ZERO))
	var slab: PackedVector2Array = xf * PackedVector2Array(GRAVE_STONE)
	VFX.draw_shaded_polygon(self, slab, (m.stone as Color).lightened(0.14))
	VFX.draw_rim(self, slab, 1.0, 0.5, m.torch)
	var cut := Color(VFX.VOID, 0.6)
	draw_circle(xf * Vector2(0.0, -17.0), 4.0, cut)
	for i in range(4):
		draw_line(xf * Vector2(-4.5 + 3.0 * float(i), -22.0), xf * Vector2(-4.5 + 3.0 * float(i), -27.0 + absf(1.5 - float(i))), cut, 1.5)
	var cup := base + Vector2(GRAVE_FLAME.x, 0.0)
	var iron := Color("2a2430")
	if open:
		# The hollow it climbed out of, the spoil thrown to either side, the cup kicked over.
		VFX.draw_ellipse(self, base + Vector2(4.0, -1.0), 20.0, 4.0, VFX.VOID)
		for side: float in [-1.0, 1.0]:
			var heap := base + Vector2(4.0 + side * 22.0, 0.0)
			draw_colored_polygon(PackedVector2Array([heap + Vector2(-9.0, 0.0), heap + Vector2(-2.0, -7.0), heap + Vector2(6.0, -3.0), heap + Vector2(9.0, 0.0)]), earth)
		draw_colored_polygon(PackedVector2Array([cup + Vector2(4.0, -1.0), cup + Vector2(4.0, -9.0), cup + Vector2(9.0, -7.0), cup + Vector2(9.0, -3.0)]), iron)
		return
	draw_colored_polygon(PackedVector2Array([base + Vector2(-20.0, 0.0), base + Vector2(-13.0, -5.0), base + Vector2(2.0, -7.0), base + Vector2(15.0, -4.0), base + Vector2(21.0, 0.0)]), earth)
	draw_colored_polygon(PackedVector2Array([cup + Vector2(-4.0, -6.0), cup + Vector2(4.0, -6.0), cup + Vector2(2.5, 0.0), cup + Vector2(-2.5, 0.0)]), iron)
	VFX.draw_flame(self, cup + Vector2(0.0, -6.0), 12.0, 6.0, t, float(k) * 1.9, m.torch, VFX.GOLD)

func _fallen_blade(base: Vector2) -> void:
	if not _clear_of_rifts(base):
		return
	draw_line(base + Vector2(-16.0, -3.0), base + Vector2(14.0, -12.0), Color("7f8896"), 3.0, true)
	draw_line(base + Vector2(-13.0, -8.0), base + Vector2(-9.0, 0.0), Color("8a6a3a"), 3.0, true)

## A dead yard tree grown from hashed angles: each limb forks twice, four levels
## deep, and both first forks hang a gibbet cage.
func _dead_branch(ci: CanvasItem, from: Vector2, angle: float, length: float, level: int, key: int, t: float, m: Dictionary) -> void:
	var to := from + Vector2.from_angle(angle) * length
	ci.draw_line(from, to, Color("2b1d12").lerp(m.stone, 0.3), [10.0, 6.0, 3.0, 1.5][level])
	if level == 1:
		_hanging_cage(ci, to + Vector2(0.0, 6.0), 70.0 + VFX.hash01(key, 131) * 50.0, sin(t * 0.7 + float(key)) * 4.0)
	if level == 3:
		return
	for side: int in [-1, 1]:
		var spread := 0.3 + VFX.hash01(key * 2 + side, 132) * 0.45
		_dead_branch(ci, to, angle + float(side) * spread, length * 0.68, level + 1, key * 2 + (side + 1) / 2, t, m)

## Each chamber's signature architecture, fixed for the chamber and painted once
## behind everything else the room draws.
func _draw_set_piece(ci: CanvasItem) -> void:
	var m := _mood()
	var fy := Content.FLOOR_Y
	match str(template.get("tag", "intro")):
		"intro":
			_cell_door(ci, -120.0, m, false, false)
			_cell_door(ci, 420.0, m, false, true)
			_cell_door(ci, 760.0, m, true, false)
		"gap":
			_broken_span(ci, 620.0, 860.0, m)
		"tiers":
			_grand_stair(ci, m)
			_warden_statue(ci, Vector2(40.0, fy), m)
			_warden_statue(ci, Vector2(1380.0, fy), m)
		"chamber":
			# The shaft darkens as it deepens, under a pale disc of daylight far above.
			VFX.draw_vgradient(ci, Rect2(390.0, 100.0, 500.0, fy + 20.0), Color(m.pit, 0.0), Color(m.pit, 0.55))
			var day := Color("dfe6f0")
			ci.draw_polygon(PackedVector2Array([Vector2(600.0, -120.0), Vector2(680.0, -120.0), Vector2(890.0, fy), Vector2(390.0, fy)]),
				PackedColorArray([Color(day, 0.05), Color(day, 0.05), Color(day, 0.0), Color(day, 0.0)]))
			ci.draw_circle(Vector2(640.0, -120.0), 60.0, Color(day, 0.08))
			ci.draw_circle(Vector2(640.0, -120.0), 40.0, Color(day, 0.5))
			_frieze(ci, -182.0, fy - 160.0, m)
		"crossfire":
			_frieze(ci, -192.0, fy - 130.0, m)

## The ashpit frieze's figure as two paper cut-outs with matching points, feet
## at the origin, facing +x: a knight under its four-tongue crown, and the
## Warden it becomes, hunched and swollen, the crown's outer tongues grown into
## horns. Parts back to front: back leg, front leg, torso, arm, hand or claw,
## then the crown's four tongues. The head is a circle, `head` [centre, radius].
const FRIEZE_KNIGHT := [
	[Vector2(-7, -30), Vector2(-1, -30), Vector2(-3, 0), Vector2(-10, 0)],
	[Vector2(1, -30), Vector2(7, -30), Vector2(10, 0), Vector2(4, 0)],
	[Vector2(-9, -28), Vector2(-10, -44), Vector2(-8, -58), Vector2(0, -61), Vector2(8, -57), Vector2(9, -28)],
	[Vector2(3, -56), Vector2(9, -55), Vector2(13, -34), Vector2(8, -33)],
	[Vector2(7, -34), Vector2(14, -34), Vector2(11, -29)],
	[Vector2(-6, -73), Vector2(-5, -83), Vector2(-2, -74)],
	[Vector2(-3, -75), Vector2(-1, -87), Vector2(1, -76)],
	[Vector2(0, -76), Vector2(2, -87), Vector2(4, -75)],
	[Vector2(3, -74), Vector2(6, -83), Vector2(7, -73)],
]
const FRIEZE_BEAST := [
	[Vector2(-16, -34), Vector2(-5, -36), Vector2(-10, 0), Vector2(-24, 0)],
	[Vector2(4, -36), Vector2(15, -34), Vector2(22, 0), Vector2(9, 0)],
	[Vector2(-17, -30), Vector2(-25, -60), Vector2(-12, -84), Vector2(12, -82), Vector2(30, -62), Vector2(16, -30)],
	[Vector2(18, -72), Vector2(30, -64), Vector2(36, -6), Vector2(26, -6)],
	[Vector2(23, -7), Vector2(40, -7), Vector2(44, 0)],
	[Vector2(19, -80), Vector2(0, -108), Vector2(24, -82)],
	[Vector2(23, -82), Vector2(24, -89), Vector2(27, -83)],
	[Vector2(27, -83), Vector2(30, -90), Vector2(31, -82)],
	[Vector2(31, -80), Vector2(48, -100), Vector2(35, -77)],
]
const FRIEZE_HEAD := [[Vector2(0, -69), 8.0], [Vector2(27, -72), 11.0]]
## The crown's parts start here in the cut-outs.
const FRIEZE_CROWN := 5
## The knight's sword, held point-down; the beast has dropped it.
const FRIEZE_SWORD := [Vector2(11, -34), Vector2(14, -34), Vector2(20, -2), Vector2(18, -2)]

## The ashpit's relief: four niches read left to right, a knight crowned and
## bent, niche by niche, into the Warden. Each is a paper cut-out raised off a
## recessed panel (its shadow falls on the panel), under a pointed gable so the
## run of niches never reads as a ledge. `base` is the niches' bottom edge.
func _frieze(ci: CanvasItem, left: float, base: float, m: Dictionary) -> void:
	var frame := (m.edge as Color).darkened(0.3)
	var recess := (m.wall as Color).darkened(0.5)
	for i in range(4):
		var cx := left + 42.0 + 94.0 * float(i)
		var x0 := cx - 42.0
		var x1 := cx + 42.0
		var y0 := base - 96.0
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, base), Vector2(x0, y0), Vector2(cx, y0 - 22.0), Vector2(x1, y0), Vector2(x1, base)]), frame)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x0 + 5.0, base - 5.0), Vector2(x0 + 5.0, y0 + 2.0), Vector2(cx, y0 - 15.0), Vector2(x1 - 5.0, y0 + 2.0), Vector2(x1 - 5.0, base - 5.0)]), recess)
		# The first niche holds the crown just over the knight's head, still to be put on.
		_frieze_figure(ci, Vector2(cx - 6.0, base - 8.0), float(i) / 3.0, 14.0 if i == 0 else 0.0, m)

## One frieze figure, `bend` of the way from knight (0) to Warden (1), with
## its crown `lift` px over its head. Drawn twice: a shadow nudged down-right
## onto the panel, then the paper itself, rim-lit, its crown in ember.
func _frieze_figure(ci: CanvasItem, foot: Vector2, bend: float, lift: float, m: Dictionary) -> void:
	# Dark paper: it sits at sconce height, where the torches light it hardest,
	# and must stay behind the fight.
	var paper := (m.wall as Color).lightened(0.04)
	var ember := (m.torch as Color).darkened(0.5)
	var head_c: Vector2 = (FRIEZE_HEAD[0][0] as Vector2).lerp(FRIEZE_HEAD[1][0], bend)
	var head_r := lerpf(FRIEZE_HEAD[0][1], FRIEZE_HEAD[1][1], bend)
	for shadow: bool in [true, false]:
		var xf := Transform2D(0.0, Vector2(0.85, 0.85), 0.0, foot + (Vector2(2.5, 2.5) if shadow else Vector2.ZERO))
		var ink := Color(VFX.VOID, 0.55)
		if bend < 0.5:
			var sword: PackedVector2Array = xf * PackedVector2Array(FRIEZE_SWORD)
			ci.draw_colored_polygon(sword, ink if shadow else Color("7f8896").darkened(0.45))
		for p in range(FRIEZE_KNIGHT.size()):
			var pts := PackedVector2Array()
			for v in range(FRIEZE_KNIGHT[p].size()):
				pts.append(xf * ((FRIEZE_KNIGHT[p][v] as Vector2).lerp(FRIEZE_BEAST[p][v], bend) + (Vector2(0.0, -lift) if p >= FRIEZE_CROWN else Vector2.ZERO)))
			if shadow:
				ci.draw_colored_polygon(pts, ink)
			else:
				ci.draw_colored_polygon(pts, ember if p >= FRIEZE_CROWN else paper)
				VFX.draw_rim(ci, pts, 1.0, 0.45, m.torch)
			if p == FRIEZE_CROWN - 1:
				ci.draw_circle(xf * head_c, head_r * 0.85, ink if shadow else paper.darkened(0.25))

## A cell in the crypt wall: a recess behind six iron bars under a lintel, with a
## shackle chain on the jamb. `open` swings the barred door 20 degrees out on its
## hinge; `hand` curls a bone hand round one bar from inside.
func _cell_door(ci: CanvasItem, x: float, m: Dictionary, open: bool, hand: bool) -> void:
	var fy := Content.FLOOR_Y
	var hole := Rect2(x - 42.0, fy - 140.0, 84.0, 140.0)
	var iron := Color("2a2430")
	ci.draw_rect(hole.grow_individual(6.0, 6.0, 6.0, 0.0), (m.stone as Color).darkened(0.1))
	ci.draw_rect(hole, (m.wall as Color).darkened(0.4))
	ci.draw_rect(Rect2(hole.position.x - 10.0, hole.position.y - 14.0, hole.size.x + 20.0, 8.0), (m.edge as Color).lightened(0.1))
	_chain(ci, Vector2(hole.end.x + 12.0, fy - 118.0), 46.0, 0.0)
	if open:
		# Hinged on the left jamb and foreshortened as it swings toward us.
		ci.draw_set_transform_matrix(Transform2D(Vector2(cos(deg_to_rad(20.0)), 0.12), Vector2(0.0, 1.0), hole.position))
	else:
		ci.draw_set_transform(hole.position)
	for i in range(6):
		var bx := 7.0 + float(i) * 14.0
		ci.draw_line(Vector2(bx, 0.0), Vector2(bx, 140.0), iron, 2.5)
	for ry: float in [10.0, 128.0]:
		ci.draw_line(Vector2(0.0, ry), Vector2(84.0, ry), iron, 4.0)
	if hand:
		var bone := Color("bdb3a3").darkened(0.2)
		VFX.draw_ellipse(ci, Vector2(38.0, 72.0), 6.0, 8.0, bone)
		for f in range(3):
			ci.draw_line(Vector2(38.0, 66.0 + float(f) * 5.0), Vector2(47.0, 64.0 + float(f) * 5.0), bone, 2.0)
	ci.draw_set_transform(Vector2.ZERO)

## The Broken Causeway's fallen bridge: voussoirs along a radius-150 arc sprung
## from each pit lip, five a side, the crown gone and each side's last wedge
## slipped 30px and turned 25 degrees on its way down.
func _broken_span(ci: CanvasItem, left: float, right: float, m: Dictionary) -> void:
	var fy := Content.FLOOR_Y
	var half := (right - left) * 0.5
	var centre := Vector2(left + half, fy + sqrt(150.0 * 150.0 - half * half))
	var spring := atan2(fy - centre.y, -half)
	var step := (-PI * 0.5 - spring) / 6.0
	var stone := (m.wall as Color).lightened(0.06)
	for side: float in [-1.0, 1.0]:
		for i in range(5):
			var a0 := spring + step * float(i) + 0.012
			var a1 := a0 + step - 0.024
			var pts := PackedVector2Array([
				centre + Vector2.from_angle(a0) * 150.0, centre + Vector2.from_angle(a1) * 150.0,
				centre + Vector2.from_angle(a1) * 176.0, centre + Vector2.from_angle(a0) * 176.0,
			])
			if side > 0.0:
				# The right half mirrors the left about the span's centre line.
				for j in range(pts.size()):
					pts[j].x = 2.0 * centre.x - pts[j].x
			if i == 4:
				var mid := (pts[0] + pts[2]) * 0.5
				pts = Transform2D(-side * deg_to_rad(25.0), mid + Vector2(0.0, 30.0)) * (Transform2D(0.0, -mid) * pts)
			VFX.draw_shaded_polygon(ci, pts, stone)
			pts.append(pts[0])
			ci.draw_polyline(pts, VFX.JOINT, 1.5)

## Warden's Ascent: a grand stair of 18 steps climbing the back wall across the
## chamber on three piers, with a balustrade along its flight.
func _grand_stair(ci: CanvasItem, m: Dictionary) -> void:
	var fy := Content.FLOOR_Y
	var stone := (m.wall as Color).lightened(0.04)
	var nosing := Color(m.edge, 0.5)
	var pts := PackedVector2Array([Vector2(-160.0, fy)])
	for i in range(18):
		var y := fy - float(i + 1) * 22.0
		pts.append(Vector2(-160.0 + float(i) * 70.0, y))
		pts.append(Vector2(-90.0 + float(i) * 70.0, y))
	pts.append(Vector2(1100.0, fy - 336.0))
	pts.append(Vector2(-100.0, fy + 20.0))
	ci.draw_colored_polygon(pts, stone)
	for i in range(18):
		ci.draw_line(pts[i * 2 + 1], pts[i * 2 + 2], nosing, 2.0)
	for px: float in [260.0, 610.0, 960.0]:
		var under := fy - (px + 160.0) / 70.0 * 22.0 + 50.0
		ci.draw_rect(Rect2(px - 22.0, under, 44.0, fy - under), stone.darkened(0.12))
	# Balustrade: a rail 44px over the nosings, on a post every second step.
	ci.draw_line(Vector2(-160.0, fy - 66.0), Vector2(1100.0, fy - 462.0), nosing, 3.0)
	for i in range(0, 18, 2):
		var foot := Vector2(-125.0 + float(i) * 70.0, fy - float(i + 1) * 22.0)
		ci.draw_line(foot, foot + Vector2(0.0, -55.0), nosing, 2.0)

## An armoured Warden carved in stone on a pedestal, hunched under its horned helm.
func _warden_statue(ci: CanvasItem, base: Vector2, m: Dictionary) -> void:
	var stone := (m.stone as Color).lightened(0.05)
	ci.draw_rect(Rect2(base.x - 34.0, base.y - 40.0, 68.0, 40.0), stone.darkened(0.2))
	ci.draw_rect(Rect2(base.x - 40.0, base.y - 46.0, 80.0, 8.0), stone.darkened(0.05))
	var body := PackedVector2Array([
		base + Vector2(-26.0, -46.0), base + Vector2(-34.0, -110.0), base + Vector2(-20.0, -140.0),
		base + Vector2(20.0, -140.0), base + Vector2(34.0, -110.0), base + Vector2(26.0, -46.0),
	])
	VFX.draw_shaded_polygon(ci, body, stone)
	VFX.draw_shaded_polygon(ci, PackedVector2Array([
		base + Vector2(-14.0, -138.0), base + Vector2(-26.0, -176.0), base + Vector2(-10.0, -158.0), base + Vector2(0.0, -166.0),
		base + Vector2(10.0, -158.0), base + Vector2(26.0, -176.0), base + Vector2(14.0, -138.0),
	]), stone)
	ci.draw_line(base + Vector2(-8.0, -150.0), base + Vector2(8.0, -150.0), VFX.VOID, 2.0)
	VFX.draw_rim(ci, body, 1.0, 0.5)

func _draw_decor_back(ci: CanvasItem) -> void:
	var tag := str(template.get("tag", "intro"))
	var m := _mood()
	var t := _decor_t()
	var fy := Content.FLOOR_Y
	match tag:
		"tiers":
			_banner_prop(ci, Vector2(430.0, fy - 134.0), 90.0, t, m, 1)
			_banner_prop(ci, Vector2(850.0, fy - 134.0), 90.0, t, m, 2)
		"platforms":
			_gear(ci, Vector2(640.0, fy - 430.0), 74.0, t * 0.35, m)
			_gear(ci, Vector2(768.0, fy - 372.0), 46.0, -t * 0.56 + 0.3, m)
			_gear(ci, Vector2(536.0, fy - 356.0), 38.0, -t * 0.68 + 1.1, m)
			_pipe(ci, Vector2(Content.ROOM_LEFT, fy - 96.0), Vector2(470.0, fy - 96.0), m)
			_pipe(ci, Vector2(810.0, fy - 96.0), Vector2(Content.ROOM_RIGHT, fy - 96.0), m)
			_pipe(ci, Vector2(470.0, fy - 96.0), Vector2(470.0, fy + 40.0), m)
			_pipe(ci, Vector2(810.0, fy - 96.0), Vector2(810.0, fy + 40.0), m)
		"chamber":
			_roots(ci, Vector2(400.0, 100.0), t, m)
			_roots(ci, Vector2(880.0, 100.0), t, m)
		"arena":
			_dead_branch(ci, Vector2(700.0, fy), -PI * 0.5, 170.0, 0, 1, t, m)
		"crossfire":
			# One gallows each side of the pit, their cages hung out over the spikes.
			_gallows(ci, Vector2(190.0, fy), 230.0, t, m)
			_gallows(ci, Vector2(1090.0, fy), -230.0, t, m)
		"boss":
			paint_throne(ci, Vector2(640.0, fy), m)
			_banner_prop(ci, Vector2(120.0, 120.0), 230.0, t, m, 3)
			_banner_prop(ci, Vector2(1160.0, 120.0), 230.0, t, m, 4)

func _draw_decor_front(tag: String, m: Dictionary) -> void:
	var t := _decor_t()
	var fy := Content.FLOOR_Y
	var graves: Array = GRAVES.get(tag, [])
	for i in range(graves.size()):
		_grave(Vector2(graves[i][0], fy), t, m, i, graves[i][1])
	match tag:
		"intro":
			_candles(Vector2(260.0, fy), 5, t, m)
			_candles(Vector2(860.0, fy), 3, t, m)
			_fallen_blade(Vector2(700.0, fy))
			_bone_pile(Vector2(1320.0, fy), m)
		"gap":
			_chain(self, Vector2(606.0, fy + 8.0), 90.0, sin(t * 0.8) * 6.0)
			_chain(self, Vector2(874.0, fy + 8.0), 120.0, sin(t * 0.7 + 1.0) * 6.0)
			_candles(Vector2(150.0, fy), 3, t, m)
			_bone_pile(Vector2(1240.0, fy), m)
		"tiers":
			_candles(Vector2(640.0, fy - 320.0), 4, t, m)
			_bone_pile(Vector2(1300.0, fy), m)
		"arena":
			_stain(Vector2(640.0, fy), 140.0, Color(0.32, 0.05, 0.08, 0.5))
			_bone_pile(Vector2(180.0, fy), m)
			_bone_pile(Vector2(720.0, fy), m)
			_bone_pile(Vector2(1120.0, fy), m)
			_fallen_blade(Vector2(560.0, fy))
		"chamber":
			_drip(500.0, 120.0, fy - 150.0, t)
			_drip(760.0, 120.0, fy - 280.0, t + 1.3)
			_candles(Vector2(1120.0, fy), 3, t, m)
		"crossfire":
			_bone_pile(Vector2(120.0, fy), m)
			_bone_pile(Vector2(1300.0, fy), m)
		"boss":
			_brazier(Vector2(300.0, fy), t, m)
			_brazier(Vector2(980.0, fy), t, m)
			# One candle per past victory on the top step: the Warden is fought
			# in front of the knight's own tally.
			if victory_candles > 0:
				_candles(Vector2(640.0, fy - 42.0), victory_candles, t, m, fire_heat)
			_stain(Vector2(640.0, fy), 200.0, Color(0.32, 0.05, 0.08, 0.35))
			_bone_pile(Vector2(-40.0, fy), m)
			_bone_pile(Vector2(1330.0, fy), m)

func despawn() -> void:
	# Every creature, the Warden included, is a child and goes with the room.
	enemies.clear()
	queue_free()
