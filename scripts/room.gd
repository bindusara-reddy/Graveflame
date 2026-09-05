class_name Room
extends Node2D
## Builds geometry from a template, spawns encounters, seals/unseals the exit.

const VFX := preload("res://scripts/vfx.gd")
const CryptProp := preload("res://scripts/crypt_prop.gd")

signal completed
signal cleared(room_name: String)
signal wave_started(current: int, total: int)
## tier: 0 regular, 1 elite, 2 boss.
signal enemy_died(score: int, pos: Vector2, tier: int, color: Color)
signal enemy_damaged(amount: float, pos: Vector2, blocked: bool)
signal projectile_requested(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color)
signal boss_spawned
signal boss_phase_changed(phase: int)
signal enemy_exploded(pos: Vector2, radius: float, damage: float)
signal pyre_burst(pos: Vector2, radius: float)
signal enemy_spawned(pos: Vector2, color: Color)
signal prop_shattered(pos: Vector2, force: Vector2, color: Color)

var template: Dictionary = {}
var enemies: Array[Node] = []
var props: Array[Area2D] = []
var boss: Boss = null
var is_boss: bool = false
var exit_open: bool = false
var _exit_rect := Rect2(0, 0, 50, 90)
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
var _difficulty: Dictionary = { "hp_mul": 1.0, "dmg_mul": 1.0 }
## Depth palette handed down by the game (see Content.MOODS).
var mood: Dictionary = {}

func setup(tmpl: Dictionary, p_is_boss: bool, player: Node, seed_val: int) -> void:
	template = tmpl
	is_boss = p_is_boss
	_player_ref = player
	_rng.seed = seed_val

func _ready() -> void:
	_difficulty = Content.difficulty_for_room(_room_index_from_template())
	_build_geometry()
	_build_walls()
	_build_boundaries()
	_build_hazards()
	_setup_exit()
	_build_props()
	_spawn_encounter()
	set_process(true)

func _process(delta: float) -> void:
	_ambient_t += delta
	if _wave_delay > 0.0:
		_wave_delay -= delta
		if _wave_delay <= 0.0:
			_wave_index += 1
			_spawn_wave()
	if exit_open and not is_boss and is_instance_valid(_player_ref):
		_near_exit = _exit_rect.grow(42.0).has_point(_player_ref.global_position)
		if _near_exit and not _exit_used and Input.is_action_just_pressed("interact"):
			_exit_used = true
			emit_signal("completed")
	queue_redraw()

func _build_geometry() -> void:
	for plat in template.get("platforms", []):
		var sb := StaticBody2D.new()
		sb.collision_layer = Content.L_WORLD
		sb.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(plat.size)
		cs.shape = rs
		sb.add_child(cs)
		sb.position = Vector2(plat.position) + Vector2(plat.size) * 0.5
		add_child(sb)

## Geometry-derived, deterministic dressing uses no encounter RNG draws.
func _build_props() -> void:
	var entry: Vector2 = template.get("entry", Vector2.ZERO)
	var exit: Vector2 = template.get("exit", Vector2.ZERO)
	for platform: Rect2 in template.get("platforms", []):
		if platform.size.x < 180.0 or platform.position.y > Content.FLOOR_Y:
			continue
		var count := clampi(int(platform.size.x / 240.0), 1, 6)
		for i in range(count):
			if props.size() >= 18: return
			var point := Vector2(platform.position.x + platform.size.x * (float(i) + 0.5) / float(count), platform.position.y)
			if absf(point.x - entry.x) < 85.0 or absf(point.x - exit.x) < 65.0:
				continue
			var blocked := false
			for wall: Rect2 in template.get("walls", []):
				if wall.grow(24.0).has_point(point + Vector2(0.0, -24.0)):
					blocked = true
			if blocked: continue
			var prop := CryptProp.new()
			prop.position = point
			prop.kind = props.size() % 2
			prop.z_index = 0
			prop.shattered.connect(func(pos, force, color): prop_shattered.emit(pos, force, color))
			add_child(prop)
			props.append(prop)

func _build_walls() -> void:
	# Optional 'walls' array in template — climbable vertical surfaces for wall slide/jump.
	for wl in template.get("walls", []):
		var sb := StaticBody2D.new()
		sb.collision_layer = Content.L_WORLD
		sb.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(wl.size)
		cs.shape = rs
		sb.add_child(cs)
		sb.position = Vector2(wl.position) + Vector2(wl.size) * 0.5
		sb.set_meta("wall", true)
		add_child(sb)

func _build_boundaries() -> void:
	# Invisible arena rails keep high-speed attacks and the boss inside the room
	# while leaving the authored pit hazards open underneath the platforms.
	for x in [Content.ROOM_LEFT - 24.0, Content.ROOM_RIGHT + 24.0]:
		var body := StaticBody2D.new()
		body.collision_layer = Content.L_WORLD
		body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(48.0, 1400.0)
		shape.shape = rect
		body.add_child(shape)
		body.position = Vector2(x, 150.0)
		add_child(body)

func _build_hazards() -> void:
	for hz in template.get("hazards", []):
		var area := Area2D.new()
		area.collision_layer = Content.L_TRIGGER
		area.collision_mask = Content.L_PLAYER_BODY
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(hz.size)
		cs.shape = rs
		area.add_child(cs)
		area.position = Vector2(hz.position) + Vector2(hz.size) * 0.5
		area.set_meta("hazard", true)
		area.body_entered.connect(_on_hazard_body)
		add_child(area)

func _on_hazard_body(body: Node) -> void:
	if body is Player:
		# Damage cancels combat hitboxes; defer it until physics queries finish.
		body.take_damage.call_deferred(18.0, Vector2(0.0, -1.0), 260.0)

func _setup_exit() -> void:
	var ex: Vector2 = template.get("exit", Vector2(1180, Content.FLOOR_Y - 80))
	_exit_rect = Rect2(ex.x - 25.0, ex.y - 45.0, 50.0, 90.0)

func _spawn_encounter() -> void:
	if is_boss:
		_spawn_boss()
		return
	var idx := _room_index_from_template()
	_waves = Content.generate_waves(idx, _rng)
	_wave_index = 0
	# At most one elite per room, placed in a random wave slot.
	if not _waves.is_empty() and _rng.randf() < Content.elite_chance(idx):
		var w := _rng.randi_range(0, _waves.size() - 1)
		var wave: Array = _waves[w]
		_elite_slot = Vector2i(w, _rng.randi_range(0, wave.size() - 1))
	_spawn_wave()

func _spawn_wave() -> void:
	if _wave_index < 0 or _wave_index >= _waves.size():
		_unlock_exit()
		return
	var kinds: Array = _waves[_wave_index]
	var slots: Array = template.get("slots", [])
	if slots.is_empty(): 
		_unlock_exit()
		return
	emit_signal("wave_started", _wave_index + 1, _waves.size())
	for i in range(kinds.size()):
		var slot_idx := (i + _wave_index) % slots.size()
		var slot: Vector2 = slots[slot_idx]
		# Enemies sharing a slot fan out a little so they do not stack perfectly.
		if i >= slots.size():
			slot.x += float(((i / slots.size()) % 2) * 2 - 1) * 36.0
		var mods := _difficulty.duplicate()
		mods["elite"] = _elite_slot == Vector2i(_wave_index, i)
		_spawn_enemy(kinds[i], slot, mods)

func wave_count() -> int:
	return _waves.size()

func _room_index_from_template() -> int:
	# derive from tag count; game.gd passes room index via meta
	return int(get_meta("room_index", 0))

func _spawn_enemy(kind: int, pos: Vector2, mods: Dictionary = {}) -> void:
	var e := Enemy.new()
	e.setup(kind, pos, mods)
	add_child(e)
	e.died.connect(_on_enemy_died.bind(e))
	e.damaged.connect(_on_enemy_damaged)
	e.projectile_requested.connect(_on_proj_requested)
	e.exploded.connect(_on_enemy_exploded)
	e.pyre_burst.connect(_on_pyre_burst)
	enemies.append(e)
	emit_signal("enemy_spawned", pos, Content.ELITE_COLOR if bool(mods.get("elite", false)) else Color(e.data.color))

func _on_enemy_exploded(pos: Vector2, radius: float, damage: float) -> void:
	emit_signal("enemy_exploded", pos, radius, damage)

func _on_pyre_burst(pos: Vector2, radius: float) -> void:
	emit_signal("pyre_burst", pos, radius)

func _on_enemy_damaged(amount: float, pos: Vector2, blocked: bool) -> void:
	emit_signal("enemy_damaged", amount, pos, blocked)

func _spawn_boss() -> void:
	boss = Boss.new()
	boss.global_position = Vector2(900, Content.FLOOR_Y - 80)
	boss.data = Content.ENEMY[Enemy.Kind.STALKER].duplicate()
	add_child(boss)
	boss.died.connect(_on_enemy_died.bind(boss))
	boss.damaged.connect(_on_enemy_damaged)
	boss.projectile_requested.connect(_on_proj_requested)
	boss.phase_changed.connect(func(p: int): emit_signal("boss_phase_changed", p))
	boss.exploded.connect(_on_enemy_exploded)
	boss.summon_requested.connect(_on_boss_summon)
	emit_signal("boss_spawned")

func _on_boss_summon(kind: int, pos: Vector2) -> void:
	_spawn_enemy(kind, pos, _difficulty.duplicate())

func _on_enemy_died(score: int, who: Node) -> void:
	var tier := 0
	var pos := Vector2.ZERO
	var color: Color = Content.PAL.attack
	if is_instance_valid(who):
		pos = who.global_position
		var d = who.get("data")
		if d is Dictionary and d.has("color"):
			color = d.color
		if who is Boss:
			tier = 2
		elif bool(who.get("elite")):
			tier = 1
	emit_signal("enemy_died", score, pos, tier, color)
	_clean_dead()
	if is_boss:
		# Adds dying mid-fight must never unseal or "clear" the throne room.
		if boss == null or not is_instance_valid(boss) or boss.dead:
			emit_signal("completed")
		return
	if _all_enemies_dead():
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

func _all_enemies_dead() -> bool:
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			return false
	return true

func _on_proj_requested(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color) -> void:
	emit_signal("projectile_requested", team, pos, vel, dmg, kb, pierce, life, color)

func get_entry_point() -> Vector2:
	return Vector2(template.get("entry", Vector2(180, Content.FLOOR_Y - 80)))

func is_at_exit(pos: Vector2) -> bool:
	return exit_open and _exit_rect.has_point(pos)

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

func _mood() -> Dictionary:
	return mood if not mood.is_empty() else Content.mood_for(0.0)

## Static light sources for the light layer: braziers, candle clusters, vents.
func light_points() -> Array:
	var out: Array = []
	var tag := str(template.get("tag", "intro"))
	var m := _mood()
	var torch: Color = m.torch
	match tag:
		"intro":
			out.append({ "pos": Vector2(260.0, Content.FLOOR_Y - 12.0), "radius": 70.0, "color": torch, "alpha": 0.22, "rate": 9.0, "phase": 0.0 })
			out.append({ "pos": Vector2(1010.0, Content.FLOOR_Y - 12.0), "radius": 60.0, "color": torch, "alpha": 0.2, "rate": 7.0, "phase": 1.3 })
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
			out.append({ "pos": Vector2(300.0, Content.FLOOR_Y - 58.0), "radius": 160.0, "color": torch, "alpha": 0.36, "rate": 8.0, "phase": 0.0 })
			out.append({ "pos": Vector2(980.0, Content.FLOOR_Y - 58.0), "radius": 160.0, "color": torch, "alpha": 0.36, "rate": 8.0, "phase": 1.7 })
			out.append({ "pos": Vector2(640.0, Content.FLOOR_Y - 150.0), "radius": 220.0, "color": m.glow, "alpha": 0.16, "rate": 3.0, "phase": 0.5 })
	# Fixed room lights retain priority in the small PointLight pool. Every candle
	# also gets its inexpensive halo from LightLayer, including those outside it.
	for prop in props:
		if is_instance_valid(prop) and prop.kind == 1 and not prop.broken:
			out.append({ "pos": prop.global_position + Vector2(0.0, -49.0), "radius": 72.0, "color": Color("ffac67"), "alpha": 0.16, "rate": 8.0, "phase": prop.position.x })
	return out

func exit_center() -> Vector2:
	return _exit_rect.get_center()

func _draw() -> void:
	var tag := str(template.get("tag", "intro"))
	var accent := _accent_for(tag)
	var m := _mood()
	_draw_decor_back(tag, m)
	# Volumetric masonry: slab courses, mortar joints, a lit rim and occlusion under the lip.
	var platforms: Array = template.get("platforms", [])
	for pi in range(platforms.size()):
		var pr := Rect2(platforms[pi].position, platforms[pi].size)
		_draw_masonry(pr, accent, pi + 1, m)
		_draw_platform_dressing(pr, m, pi + 1)
	# climbable walls (accent edge so players know they can wall-slide)
	var walls: Array = template.get("walls", [])
	for wi in range(walls.size()):
		var wr := Rect2(walls[wi].position, walls[wi].size)
		_draw_masonry(wr, accent, 40 + wi, m)
		draw_line(Vector2(wr.position.x, wr.position.y), Vector2(wr.position.x, wr.end.y), Color(accent.r, accent.g, accent.b, 0.65), 3.0)
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
func _draw_masonry(pr: Rect2, accent: Color, salt: int, m: Dictionary) -> void:
	var lip := 6.0
	var stone: Color = m.stone
	var base := stone.darkened(0.22)
	draw_rect(pr, base)
	var y := pr.position.y + lip
	var row := 0
	while y < pr.end.y - 1.0:
		var row_h := 16.0 if row < 3 else 26.0
		row_h = minf(row_h, pr.end.y - y)
		var x := pr.position.x - VFX.hash01(row + salt * 7, 3) * 56.0
		var col := 0
		while x < pr.end.x:
			var pick := VFX.hash01(col * 31 + row * 17, salt)
			var slab_w := 48.0 if pick < 0.34 else (64.0 if pick < 0.67 else 80.0)
			var x0 := maxf(x, pr.position.x)
			var x1 := minf(x + slab_w, pr.end.x)
			if x1 > x0 + 1.0:
				var tone := (VFX.hash01(col * 13 + row * 5, salt + 11) - 0.5) * 0.10
				if tone < -0.015:
					draw_rect(Rect2(x0, y, x1 - x0, row_h), Color(0.0, 0.0, 0.0, -tone))
				elif tone > 0.015:
					draw_rect(Rect2(x0, y, x1 - x0, row_h), Color(1.0, 1.0, 1.0, tone * 0.5))
				# Occasional crack across a slab.
				if VFX.hash01(col * 7 + row * 3, salt + 23) > 0.86 and x1 - x0 > 30.0:
					var cx := x0 + (x1 - x0) * 0.5
					draw_polyline(PackedVector2Array([
						Vector2(cx - 8.0, y + 2.0), Vector2(cx - 2.0, y + row_h * 0.45), Vector2(cx + 5.0, y + row_h * 0.6), Vector2(cx + 3.0, y + row_h - 2.0),
					]), VFX.JOINT, 1.5)
				if x + slab_w < pr.end.x - 1.0:
					draw_line(Vector2(x + slab_w, y), Vector2(x + slab_w, y + row_h), VFX.JOINT, 2.0)
			x += slab_w
			col += 1
		if y + row_h < pr.end.y - 1.0:
			draw_line(Vector2(pr.position.x, y + row_h), Vector2(pr.end.x, y + row_h), VFX.JOINT, 2.0)
		y += row_h
		row += 1
	VFX.draw_vgradient(self, Rect2(pr.position.x, pr.position.y + lip, pr.size.x, 12.0), Color(0.03, 0.016, 0.06, 0.7), Color(0.03, 0.016, 0.06, 0.0))
	draw_rect(Rect2(pr.position, Vector2(pr.size.x, lip)), (m.edge as Color).lightened(0.12))
	draw_rect(Rect2(pr.position + Vector2(0.0, lip), Vector2(pr.size.x, 2.0)), Color(accent.r, accent.g, accent.b, 0.28))
	draw_line(Vector2(pr.position.x, pr.position.y + 0.75), Vector2(pr.end.x, pr.position.y + 0.75), VFX.RIM, 1.5)
	draw_rect(Rect2(pr.position.x, pr.end.y - 2.0, pr.size.x, 2.0), VFX.JOINT)

## Broken ends, ash tufts, moss drips in the crypt, ember veins nearer the forge.
func _draw_platform_dressing(pr: Rect2, m: Dictionary, salt: int) -> void:
	var t := _ambient_t if not Feedback.motion_reduced else 0.0
	var seep := float(m.ember_seep)
	var moss := float(m.moss)
	var stone: Color = m.stone
	# Jagged broken corners on ends that hang over a drop (the tiles carry their own).
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
		draw_colored_polygon(pts, stone.darkened(0.3))
		draw_polyline(pts, VFX.JOINT, 1.5)
		# Loose stones tumbling off the lip.
		for i in range(3):
			var sy := pr.position.y + depth + 10.0 + float(i) * 14.0 + VFX.hash01(salt + i, 92) * 8.0
			var sx := ex + side * (6.0 + VFX.hash01(salt + i, 93) * 14.0)
			draw_rect(Rect2(sx - 4.0, sy, 8.0 - float(i), 5.0), stone.darkened(0.35 + float(i) * 0.1))
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

func _draw_hazard(r: Rect2, m: Dictionary) -> void:
	var t := _ambient_t
	var seep := float(m.ember_seep)
	draw_rect(r, Color("35121c").lerp(Color("4a1408"), seep))
	if seep > 0.05:
		# Magma skin: glowing gradient and slow bubbles.
		VFX.draw_vgradient(self, Rect2(r.position.x, r.position.y + 12.0, r.size.x, 48.0), Color(m.glow, 0.42 * seep), Color(m.glow, 0.0))
		var n := int(r.size.x / 54.0)
		for i in range(n):
			var ph := fmod(t * 0.7 + VFX.hash01(i, 97) * 3.0, 3.0)
			var bx := r.position.x + 27.0 + float(i) * 54.0 + VFX.hash01(i, 98) * 20.0
			var br := 3.0 + ph * 4.0
			draw_arc(Vector2(bx, r.position.y + 26.0), br, 0.0, TAU, 12, Color(m.glow, (1.0 - ph / 3.0) * 0.6 * seep), 1.5)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 22.0)), Color(0.75, 0.16, 0.12, 0.18 + sin(t * 4.0) * 0.04))
	var spike_count := int(r.size.x / 28.0)
	var spike := Color("8e3340").lerp(Color("3a2a2e"), seep * 0.6)
	for i in range(spike_count):
		var x: float = r.position.x + float(i) * 28.0
		var tip := Vector2(x + 14.0, r.position.y - 10.0 - float(i % 3) * 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x, r.position.y + 18.0), tip, Vector2(x + 28.0, r.position.y + 18.0)]), spike)
		draw_line(Vector2(x + 14.0, r.position.y + 18.0), tip, Color(VFX.HOT, 0.12 + seep * 0.25), 1.0)
	for i in range(7):
		var ember_x := r.position.x + fmod(float(i * 79) + t * (18.0 + float(i)), maxf(1.0, r.size.x))
		var ember_y := r.position.y + 10.0 - fmod(t * (12.0 + float(i) * 2.0) + float(i * 9), 34.0)
		draw_circle(Vector2(ember_x, ember_y), 1.5 + float(i % 2), Color(1.0, 0.35, 0.12, 0.55))

## Rift gate: runed pillars, a keystone arch and, once unsealed, a turning vortex.
func _draw_exit(m: Dictionary) -> void:
	if is_boss:
		return  # The throne room has no rift; the Warden's death ends the run.
	var t := _ambient_t if not Feedback.motion_reduced else 0.0
	var ec: Color = Content.PAL.exit if exit_open else Color("555560")
	var c := _exit_rect.get_center()
	var stone: Color = (m.stone as Color).lightened(0.1)
	# Pillars with rune notches that light when the way is open.
	for side: float in [-1.0, 1.0]:
		var px := c.x + side * 30.0
		draw_rect(Rect2(px - 5.0, c.y - 44.0, 10.0, 88.0), stone)
		draw_rect(Rect2(px - 7.0, c.y - 48.0, 14.0, 6.0), stone.lightened(0.1))
		for i in range(4):
			var ry := c.y - 32.0 + float(i) * 18.0
			var lit := exit_open and (fmod(t * 2.0 + float(i) * 0.7, 4.0) < 3.0)
			draw_rect(Rect2(px - 2.5, ry, 5.0, 8.0), Color(ec, 0.9 if lit else 0.35))
	draw_arc(c + Vector2(0.0, -28.0), 30.0, PI, TAU, 20, stone.darkened(0.1), 8.0)
	draw_rect(Rect2(c.x - 5.0, c.y - 62.0, 10.0, 8.0), Color(ec, 0.9 if exit_open else 0.4))
	if exit_open:
		var pulse := 0.82 + sin(t * 5.0) * 0.12
		draw_circle(c, 30.0 * pulse, Color(ec, 0.14))
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0.0, -30.0), c + Vector2(18.0, 0.0),
			c + Vector2(0.0, 30.0), c + Vector2(-18.0, 0.0),
		]), Color(ec, 0.2))
		for i in range(3):
			var a0 := t * 1.6 + float(i) * TAU / 3.0
			draw_arc(c, 9.0 + float(i) * 6.0, a0, a0 + PI * 1.2, 18, Color(ec, 0.75 - float(i) * 0.18), 2.5)
			draw_arc(c, 26.0 - float(i) * 4.0, -a0 * 1.3, -a0 * 1.3 + PI * 0.9, 14, Color(VFX.HOT, 0.3), 1.5)
		draw_circle(c, 5.0 + sin(t * 8.0) * 1.5, Color(VFX.HOT, 0.85))
		for i in range(7):
			var rise := fmod(t * (28.0 + float(i) * 6.0) + float(i * 13), 72.0)
			var mx := c.x + sin(t * 2.0 + float(i) * 1.1) * 12.0
			draw_circle(Vector2(mx, c.y + 34.0 - rise), 1.6, Color(ec, 0.7 * (1.0 - rise / 72.0)))
		if _near_exit:
			draw_string(ThemeDB.fallback_font, c + Vector2(-70.0, -76.0), "[E]  ENTER RIFT", HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER, 140.0, 28, ec)
	else:
		# Sealed: iron bar across the gate and a dim lock glyph.
		draw_line(Vector2(c.x - 34.0, c.y - 6.0), Vector2(c.x + 34.0, c.y - 6.0), Color("2a2430"), 5.0)
		draw_line(Vector2(c.x - 34.0, c.y + 10.0), Vector2(c.x + 34.0, c.y + 10.0), Color("2a2430"), 5.0)
		draw_arc(c, 18.0, 0.0, TAU, 20, ec, 2.5)
		draw_line(c - Vector2(10.0, 10.0), c + Vector2(10.0, 10.0), ec, 2.5)
		draw_line(c - Vector2(-10.0, 10.0), c + Vector2(-10.0, -10.0), ec, 2.5)

# --- Props --------------------------------------------------------------------

func _candles(base: Vector2, n: int, t: float, m: Dictionary) -> void:
	for i in range(n):
		var h := VFX.hash01(i, 101)
		var x := base.x + (float(i) - float(n - 1) * 0.5) * 11.0 + (h - 0.5) * 4.0
		var height := 8.0 + h * 12.0
		draw_rect(Rect2(x - 2.5, base.y - height, 5.0, height), Color("d8cfc0").darkened(0.35))
		draw_rect(Rect2(x - 3.5, base.y - height * 0.3, 7.0, 3.0), Color("d8cfc0").darkened(0.5))
		VFX.draw_flame(self, Vector2(x, base.y - height), 9.0, 4.0, t, float(i) * 1.7, m.torch, VFX.GOLD)
	draw_rect(Rect2(base.x - float(n) * 6.0, base.y - 2.0, float(n) * 12.0, 3.0), Color(0.0, 0.0, 0.0, 0.35))

func _bone_pile(base: Vector2, m: Dictionary) -> void:
	var bone := Color("bdb3a3").lerp(m.stone, 0.35)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-26.0, 0.0), base + Vector2(-14.0, -10.0), base + Vector2(2.0, -14.0), base + Vector2(18.0, -8.0), base + Vector2(28.0, 0.0)]), bone.darkened(0.45))
	draw_line(base + Vector2(-18.0, -4.0), base + Vector2(4.0, -9.0), bone, 3.0, true)
	draw_line(base + Vector2(-2.0, -2.0), base + Vector2(20.0, -5.0), bone, 3.0, true)
	draw_circle(base + Vector2(8.0, -14.0), 6.0, bone)
	draw_circle(base + Vector2(6.0, -15.0), 1.5, VFX.VOID)
	draw_circle(base + Vector2(11.0, -15.0), 1.5, VFX.VOID)
	draw_rect(Rect2(base.x + 5.0, base.y - 10.0, 6.0, 3.0), VFX.VOID)

func _chain(from: Vector2, length: float, sway: float, weight: bool = true) -> void:
	var to := from + Vector2(sway, length)
	draw_dashed_line(from, to, Color("3a3245"), 2.5, 5.0)
	if weight:
		draw_rect(Rect2(to.x - 5.0, to.y, 10.0, 8.0), Color("2a2430"))

func _banner_prop(top: Vector2, length: float, t: float, m: Dictionary, k: int) -> void:
	var sway := sin(t * 0.9 + float(k)) * 4.0
	var bc: Color = m.banner
	draw_line(top + Vector2(-26.0, 0.0), top + Vector2(26.0, 0.0), Color("3a3245"), 4.0)
	draw_colored_polygon(PackedVector2Array([
		top + Vector2(-20.0, 0.0), top + Vector2(20.0, 0.0), top + Vector2(20.0 + sway, length - 20.0),
		top + Vector2(sway, length), top + Vector2(-20.0 + sway, length - 20.0),
	]), bc)
	draw_line(top + Vector2(-20.0, 0.0), top + Vector2(-20.0 + sway, length - 20.0), Color(VFX.RIM, 0.15), 1.0)
	VFX.draw_flame(self, top + Vector2(sway * 0.5, length * 0.58), 16.0, 9.0, 0.0, 0.0, Color(m.torch, 0.6), Color(VFX.GOLD, 0.4))

func _brazier(base: Vector2, t: float, m: Dictionary) -> void:
	var iron := Color("2a2430")
	draw_rect(Rect2(base.x - 4.0, base.y - 40.0, 8.0, 40.0), iron)
	draw_rect(Rect2(base.x - 16.0, base.y - 4.0, 32.0, 4.0), iron)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-22.0, -40.0), base + Vector2(22.0, -40.0), base + Vector2(14.0, -56.0), base + Vector2(-14.0, -56.0)]), iron.lightened(0.1))
	draw_arc(base + Vector2(0.0, -40.0), 22.0, PI, TAU, 16, iron.lightened(0.2), 3.0)
	for i in range(3):
		VFX.draw_flame(self, base + Vector2(-9.0 + float(i) * 9.0, -54.0), 30.0 - float(i % 2) * 8.0, 12.0, t, float(i) * 2.2, m.torch, VFX.GOLD)
	draw_circle(base + Vector2(0.0, -2.0), 26.0, Color(m.torch, 0.06))

func _throne(base: Vector2, m: Dictionary) -> void:
	var stone: Color = (m.stone as Color).darkened(0.1)
	# Dais steps.
	for i in range(3):
		var w := 300.0 - float(i) * 60.0
		draw_rect(Rect2(base.x - w * 0.5, base.y - 14.0 * float(i + 1), w, 14.0), stone.lightened(0.05 * float(i)))
		draw_line(Vector2(base.x - w * 0.5, base.y - 14.0 * float(i + 1)), Vector2(base.x + w * 0.5, base.y - 14.0 * float(i + 1)), Color(VFX.RIM, 0.2), 1.5)
	var seat := base + Vector2(0.0, -42.0)
	# Back with a crown of blades.
	draw_rect(Rect2(seat.x - 60.0, seat.y - 190.0, 120.0, 190.0), stone.darkened(0.15))
	for i in range(7):
		var x := seat.x - 54.0 + float(i) * 18.0
		var h := 40.0 + (24.0 if i == 3 else (12.0 if i % 2 == 0 else 0.0))
		draw_colored_polygon(PackedVector2Array([Vector2(x - 6.0, seat.y - 190.0), Vector2(x, seat.y - 190.0 - h), Vector2(x + 6.0, seat.y - 190.0)]), stone.darkened(0.05))
	# Armrests and seat.
	draw_rect(Rect2(seat.x - 78.0, seat.y - 70.0, 18.0, 70.0), stone)
	draw_rect(Rect2(seat.x + 60.0, seat.y - 70.0, 18.0, 70.0), stone)
	draw_rect(Rect2(seat.x - 60.0, seat.y - 30.0, 120.0, 30.0), stone.lightened(0.06))
	# Ember sigil burning in the backrest.
	draw_circle(seat + Vector2(0.0, -120.0), 22.0, Color(m.glow, 0.25))
	VFX.draw_flame(self, seat + Vector2(0.0, -104.0), 34.0, 18.0, _ambient_t if not Feedback.motion_reduced else 0.0, 0.0, Color(m.torch, 0.85), VFX.GOLD)
	draw_arc(seat + Vector2(0.0, -120.0), 30.0, 0.0, TAU, 28, Color(m.torch, 0.35), 2.0)

func _gear(c: Vector2, r: float, angle: float, m: Dictionary) -> void:
	var iron := (m.stone as Color).darkened(0.3)
	var teeth := int(r / 6.0)
	var pts := PackedVector2Array()
	for i in range(teeth * 2):
		var a := angle + TAU * float(i) / float(teeth * 2)
		var rr := r if i % 2 == 0 else r * 0.82
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, iron)
	draw_circle(c, r * 0.5, (m.wall as Color))
	draw_arc(c, r * 0.5, 0.0, TAU, 24, Color(VFX.RIM, 0.25), 2.0)
	draw_circle(c, r * 0.12, iron.lightened(0.15))
	for i in range(4):
		var a := angle + float(i) * PI * 0.5
		draw_line(c + Vector2(cos(a), sin(a)) * r * 0.14, c + Vector2(cos(a), sin(a)) * r * 0.5, iron.lightened(0.12), 5.0)

func _pipe(from: Vector2, to: Vector2, m: Dictionary) -> void:
	var iron := (m.stone as Color).darkened(0.28)
	draw_line(from, to, iron, 12.0)
	draw_line(from + Vector2(0.0, -3.0), to + Vector2(0.0, -3.0), Color(VFX.RIM, 0.14), 2.0)
	var n := int(from.distance_to(to) / 120.0)
	for i in range(n + 1):
		var p := from.lerp(to, float(i) / maxf(1.0, float(n)))
		draw_rect(Rect2(p.x - 5.0, p.y - 9.0, 10.0, 18.0), iron.lightened(0.1))

func _roots(top: Vector2, t: float, m: Dictionary) -> void:
	var root := Color("2b1d12").lerp(m.stone, 0.2)
	for i in range(5):
		var h := VFX.hash01(i, 111)
		var x := top.x + (float(i) - 2.0) * 16.0
		var len := 80.0 + h * 140.0
		var sway := sin(t * 0.8 + float(i)) * 4.0
		draw_polyline(PackedVector2Array([Vector2(x, top.y), Vector2(x + 6.0 + sway, top.y + len * 0.4), Vector2(x - 4.0 + sway, top.y + len * 0.75), Vector2(x + 3.0 + sway * 1.5, top.y + len)]), root, 4.0 - h * 2.0)
		if float(m.moss) > 0.05:
			draw_circle(Vector2(x + 3.0 + sway * 1.5, top.y + len), 3.0, Color("2f6b4a", 0.6 * float(m.moss)))

func _drip(x: float, y0: float, y1: float, t: float) -> void:
	var d := fmod(t * 160.0, y1 - y0 + 40.0)
	var y := y0 + d
	if y < y1:
		draw_line(Vector2(x, y - 8.0), Vector2(x, y), Color(0.6, 0.75, 0.9, 0.5), 1.5)
		draw_circle(Vector2(x, y), 1.8, Color(0.7, 0.85, 1.0, 0.6))
	else:
		var r := (y - y1) / 40.0
		draw_arc(Vector2(x, y1), 4.0 + r * 12.0, 0.0, TAU, 12, Color(0.7, 0.85, 1.0, 0.5 * (1.0 - r)), 1.0)

func _gallows(top: Vector2, t: float, m: Dictionary) -> void:
	var wood := Color("2b1d12").lerp(m.stone, 0.25)
	draw_rect(Rect2(top.x - 6.0, top.y - 130.0, 12.0, 130.0), wood)
	draw_rect(Rect2(top.x - 6.0, top.y - 130.0, 90.0, 10.0), wood)
	draw_line(Vector2(top.x + 4.0, top.y - 96.0), Vector2(top.x + 40.0, top.y - 124.0), wood, 6.0)
	var sway := sin(t * 0.7) * 5.0
	var hook := Vector2(top.x + 70.0, top.y - 120.0)
	_chain(hook, 44.0, sway, false)
	# Hanging cage.
	var cage := hook + Vector2(sway, 44.0)
	var iron := Color("2a2430")
	draw_arc(cage + Vector2(0.0, 8.0), 14.0, PI, TAU, 12, iron, 2.5)
	for i in range(5):
		var cx := cage.x - 12.0 + float(i) * 6.0
		draw_line(Vector2(cx, cage.y + 8.0), Vector2(cx + sway * 0.1, cage.y + 40.0), iron, 2.0)
	draw_line(cage + Vector2(-14.0, 40.0), cage + Vector2(14.0, 40.0), iron, 3.0)
	draw_circle(cage + Vector2(0.0, 24.0), 4.0, Color("bdb3a3").darkened(0.3))

func _stain(base: Vector2, w: float, color: Color) -> void:
	VFX.draw_ellipse(self, base + Vector2(0.0, -1.0), w * 0.5, 4.0, color)
	VFX.draw_ellipse(self, base + Vector2(w * 0.2, -1.0), w * 0.22, 2.5, color)

func _fallen_blade(base: Vector2) -> void:
	draw_line(base + Vector2(-16.0, -3.0), base + Vector2(14.0, -12.0), Color("7f8896"), 3.0, true)
	draw_line(base + Vector2(-13.0, -8.0), base + Vector2(-9.0, 0.0), Color("8a6a3a"), 3.0, true)

func _draw_decor_back(tag: String, m: Dictionary) -> void:
	var t := _ambient_t if not Feedback.motion_reduced else 0.0
	var fy := Content.FLOOR_Y
	match tag:
		"tiers":
			_banner_prop(Vector2(430.0, fy - 134.0), 90.0, t, m, 1)
			_banner_prop(Vector2(850.0, fy - 134.0), 90.0, t, m, 2)
		"platforms":
			_gear(Vector2(640.0, fy - 430.0), 74.0, t * 0.35, m)
			_gear(Vector2(768.0, fy - 372.0), 46.0, -t * 0.56 + 0.3, m)
			_gear(Vector2(536.0, fy - 356.0), 38.0, -t * 0.68 + 1.1, m)
			_pipe(Vector2(Content.ROOM_LEFT, fy - 96.0), Vector2(470.0, fy - 96.0), m)
			_pipe(Vector2(810.0, fy - 96.0), Vector2(Content.ROOM_RIGHT, fy - 96.0), m)
			_pipe(Vector2(470.0, fy - 96.0), Vector2(470.0, fy + 40.0), m)
			_pipe(Vector2(810.0, fy - 96.0), Vector2(810.0, fy + 40.0), m)
		"chamber":
			_roots(Vector2(400.0, 100.0), t, m)
			_roots(Vector2(880.0, 100.0), t, m)
		"crossfire":
			_gallows(Vector2(640.0, fy - 360.0), t, m)
		"boss":
			_throne(Vector2(640.0, fy), m)
			_banner_prop(Vector2(120.0, 120.0), 230.0, t, m, 3)
			_banner_prop(Vector2(1160.0, 120.0), 230.0, t, m, 4)

func _draw_decor_front(tag: String, m: Dictionary) -> void:
	var t := _ambient_t if not Feedback.motion_reduced else 0.0
	var fy := Content.FLOOR_Y
	match tag:
		"intro":
			_candles(Vector2(260.0, fy), 5, t, m)
			_candles(Vector2(1010.0, fy), 3, t, m)
			_fallen_blade(Vector2(700.0, fy))
			_bone_pile(Vector2(1320.0, fy), m)
		"gap":
			_chain(Vector2(606.0, fy + 8.0), 90.0, sin(t * 0.8) * 6.0)
			_chain(Vector2(874.0, fy + 8.0), 120.0, sin(t * 0.7 + 1.0) * 6.0)
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
		"platforms":
			pass
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
			_stain(Vector2(640.0, fy), 200.0, Color(0.32, 0.05, 0.08, 0.35))
			_bone_pile(Vector2(-40.0, fy), m)
			_bone_pile(Vector2(1330.0, fy), m)

func despawn() -> void:
	for e in enemies:
		if is_instance_valid(e): e.queue_free()
	if boss != null and is_instance_valid(boss): boss.queue_free()
	enemies.clear()
	queue_free()
