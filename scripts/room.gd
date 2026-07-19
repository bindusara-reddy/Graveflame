class_name Room
extends Node2D
## Builds geometry from a template, spawns encounters, seals/unseals the exit.

signal completed
signal cleared(room_name: String)
signal wave_started(current: int, total: int)
signal enemy_died(score: int)
signal projectile_requested(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color)
signal boss_spawned
signal boss_phase_changed(phase: int)
signal enemy_exploded(pos: Vector2, radius: float, damage: float)

var template: Dictionary = {}
var enemies: Array[Node] = []
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

func setup(tmpl: Dictionary, p_is_boss: bool, player: Node, seed_val: int) -> void:
	template = tmpl
	is_boss = p_is_boss
	_player_ref = player
	_rng.seed = seed_val

func _ready() -> void:
	_build_geometry()
	_build_walls()
	_build_boundaries()
	_build_hazards()
	_setup_exit()
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
	if exit_open or _wave_delay > 0.0:
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
		body.take_damage(18.0, Vector2(0.0, -1.0), 260.0)

func _setup_exit() -> void:
	var ex: Vector2 = template.get("exit", Vector2(1180, Content.FLOOR_Y - 80))
	_exit_rect = Rect2(ex.x - 25.0, ex.y - 45.0, 50.0, 90.0)

func _spawn_encounter() -> void:
	if is_boss:
		_spawn_boss()
		return
	_waves = Content.encounter_waves_for_room(_room_index_from_template())
	_wave_index = 0
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
		_spawn_enemy(kinds[i], slot)

func _room_index_from_template() -> int:
	# derive from tag count; game.gd passes room index via meta
	return int(get_meta("room_index", 0))

func _spawn_enemy(kind: int, pos: Vector2) -> void:
	var e := Enemy.new()
	e.setup(kind, pos)
	add_child(e)
	e.died.connect(_on_enemy_died)
	e.projectile_requested.connect(_on_proj_requested)
	e.exploded.connect(_on_enemy_exploded)
	enemies.append(e)

func _on_enemy_exploded(pos: Vector2, radius: float, damage: float) -> void:
	emit_signal("enemy_exploded", pos, radius, damage)

func _spawn_boss() -> void:
	boss = Boss.new()
	boss.global_position = Vector2(900, Content.FLOOR_Y - 80)
	boss.data = Content.ENEMY[Enemy.Kind.STALKER].duplicate()
	add_child(boss)
	boss.died.connect(_on_enemy_died)
	boss.projectile_requested.connect(_on_proj_requested)
	boss.phase_changed.connect(func(p: int): emit_signal("boss_phase_changed", p))
	boss.exploded.connect(_on_enemy_exploded)
	emit_signal("boss_spawned")

func _on_enemy_died(score: int) -> void:
	emit_signal("enemy_died", score)
	_clean_dead()
	if is_boss:
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

func _draw() -> void:
	var tag := str(template.get("tag", "intro"))
	var accent := Color("9d6bff")
	match tag:
		"gap": accent = Color("4aa6b8")
		"tiers": accent = Color("7d70c9")
		"arena": accent = Color("b44c55")
		"platforms": accent = Color("d27a36")
		"chamber": accent = Color("468c86")
		"crossfire": accent = Color("9d425f")
		"boss": accent = Color("cf493f")
	# A restrained room sigil makes each procedural chamber feel authored.
	draw_string(ThemeDB.fallback_font, Vector2(440.0, 142.0), Content.room_name(template), HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER, 400.0, 20, Color(accent.r, accent.g, accent.b, 0.34))
	# Layered stone platforms with hand-cut brick seams.
	for plat in template.get("platforms", []):
		var pr := Rect2(plat.position, plat.size)
		draw_rect(pr, Color("211c2a"))
		draw_rect(Rect2(pr.position, Vector2(pr.size.x, 7.0)), Content.PAL.platform_edge)
		draw_rect(Rect2(pr.position + Vector2(0.0, 7.0), Vector2(pr.size.x, 3.0)), Color(accent.r, accent.g, accent.b, 0.22))
		var row_count := mini(4, int(pr.size.y / 28.0))
		for row in range(1, row_count + 1):
			var sy := pr.position.y + float(row) * 28.0
			draw_line(Vector2(pr.position.x, sy), Vector2(pr.end.x, sy), Color(0.0, 0.0, 0.0, 0.20), 1.0)
			var offset := 24.0 if row % 2 == 0 else 0.0
			var col_count := int(pr.size.x / 48.0)
			for col in range(1, col_count + 1):
				var sx := pr.position.x + float(col) * 48.0 + offset
				if sx < pr.end.x:
					draw_line(Vector2(sx, sy - 28.0), Vector2(sx, sy), Color(0.0, 0.0, 0.0, 0.16), 1.0)
	# climbable walls (distinct color so players know they can wall-slide)
	for wl in template.get("walls", []):
		draw_rect(Rect2(wl.position, wl.size), Color("352e43"))
		draw_line(Vector2(wl.position.x, wl.position.y), Vector2(wl.position.x, wl.end.y), Color(accent.r, accent.g, accent.b, 0.65), 3.0)
		# brick seams for visual texture
		var seams := int(float(wl.size.y) / 32.0)
		for i in range(1, seams):
			var y: float = wl.position.y + float(i) * 32.0
			draw_line(Vector2(wl.position.x, y), Vector2(wl.position.x + wl.size.x, y), Color(0, 0, 0, 0.25), 2.0)
	for hz in template.get("hazards", []):
		var r := Rect2(hz.position, hz.size)
		draw_rect(r, Color("35121c"))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 22.0)), Color(0.75, 0.16, 0.12, 0.18 + sin(_ambient_t * 4.0) * 0.04))
		var spike_count := int(r.size.x / 28.0)
		for i in range(spike_count):
			var x: float = r.position.x + float(i) * 28.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, r.position.y + 18.0),
				Vector2(x + 14.0, r.position.y - 10.0 - float(i % 3) * 3.0),
				Vector2(x + 28.0, r.position.y + 18.0),
			]), Color("8e3340"))
		for i in range(7):
			var ember_x := r.position.x + fmod(float(i * 79) + _ambient_t * (18.0 + float(i)), maxf(1.0, r.size.x))
			var ember_y := r.position.y + 10.0 - fmod(_ambient_t * (12.0 + float(i) * 2.0) + float(i * 9), 34.0)
			draw_circle(Vector2(ember_x, ember_y), 1.5 + float(i % 2), Color(1.0, 0.35, 0.12, 0.55))
	# exit portal
	var ec := Content.PAL.exit if exit_open else Color("555560")
	var c := _exit_rect.get_center()
	# Carved arch and locking pillars remain visible before the fight is clear.
	draw_rect(Rect2(c.x - 34.0, c.y - 44.0, 8.0, 88.0), Color("3a3245"))
	draw_rect(Rect2(c.x + 26.0, c.y - 44.0, 8.0, 88.0), Color("3a3245"))
	draw_arc(c + Vector2(0.0, -28.0), 30.0, PI, TAU, 20, Color("50445d"), 8.0)
	if exit_open:
		var pulse := 0.82 + sin(_ambient_t * 5.0) * 0.12
		draw_circle(c, 24.0 * pulse, Color(ec.r, ec.g, ec.b, 0.18))
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0.0, -30.0), c + Vector2(18.0, 0.0),
			c + Vector2(0.0, 30.0), c + Vector2(-18.0, 0.0),
		]), Color(ec.r, ec.g, ec.b, 0.22))
		draw_arc(c, 22.0 + sin(_ambient_t * 3.0) * 2.0, _ambient_t, _ambient_t + PI * 1.5, 24, ec, 3.0)
		if _near_exit:
			draw_string(ThemeDB.fallback_font, c + Vector2(-70.0, -58.0), "[E]  ENTER RIFT", HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER, 140.0, 16, ec)
	else:
		draw_arc(c, 22.0, 0, TAU, 24, ec, 3.0)
	if not exit_open:
		draw_line(c - Vector2(16, 16), c + Vector2(16, 16), ec, 3.0)
		draw_line(c - Vector2(-16, 16), c + Vector2(-16, -16), ec, 3.0)
	if _wave_delay > 0.0:
		var wave_alpha := clampf(_wave_delay / 0.85, 0.0, 1.0)
		for slot in template.get("slots", []):
			draw_arc(slot, 22.0 * (1.0 - wave_alpha * 0.35), 0.0, TAU, 20, Color(accent.r, accent.g, accent.b, wave_alpha * 0.7), 2.0)

func despawn() -> void:
	for e in enemies:
		if is_instance_valid(e): e.queue_free()
	if boss != null and is_instance_valid(boss): boss.queue_free()
	enemies.clear()
	queue_free()
