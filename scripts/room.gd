class_name Room
extends Node2D
## Builds geometry from a template, spawns encounters, seals/unseals the exit.

signal completed
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

func setup(tmpl: Dictionary, p_is_boss: bool, player: Node, seed_val: int) -> void:
	template = tmpl
	is_boss = p_is_boss
	_player_ref = player
	_rng.seed = seed_val

func _ready() -> void:
	_build_geometry()
	_build_walls()
	_build_hazards()
	_setup_exit()
	_spawn_encounter()

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
	var kinds: Array = Content.encounter_for_room(_room_index_from_template())
	var slots: Array = template.get("slots", [])
	if slots.is_empty(): 
		exit_open = true
		return
	for i in range(kinds.size()):
		var slot: Vector2 = slots[i % slots.size()] if not slots.is_empty() else Vector2(400 + i * 120, Content.FLOOR_Y - 40)
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
		exit_open = true
		emit_signal("completed")

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
	# Background handled by feedback/game; draw platforms + hazards + exit
	for plat in template.get("platforms", []):
		draw_rect(Rect2(plat.position, plat.size), Content.PAL.platform)
		# edge highlight
		draw_rect(Rect2(plat.position.x, plat.position.y, plat.size.x, 4.0), Content.PAL.platform_edge)
	# climbable walls (distinct color so players know they can wall-slide)
	for wl in template.get("walls", []):
		draw_rect(Rect2(wl.position, wl.size), Content.PAL.platform_edge)
		# brick seams for visual texture
		var seams := int(float(wl.size.y) / 32.0)
		for i in range(1, seams):
			var y: float = wl.position.y + float(i) * 32.0
			draw_line(Vector2(wl.position.x, y), Vector2(wl.position.x + wl.size.x, y), Color(0, 0, 0, 0.25), 2.0)
	for hz in template.get("hazards", []):
		var r := Rect2(hz.position, hz.size)
		draw_rect(r, Content.PAL.hazard)
		# hazard stripes
		for i in range(int(r.size.x / 24.0)):
			var x: float = r.position.x + float(i) * 24.0
			draw_line(Vector2(x, r.position.y), Vector2(x + 12, r.position.y + r.size.y), Color(0,0,0,0.3), 2.0)
	# exit portal
	var ec := Content.PAL.exit if exit_open else Color("555560")
	var c := _exit_rect.get_center()
	if exit_open:
		var pulse := 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.2
		draw_circle(c, 28.0 * pulse, Color(ec.r, ec.g, ec.b, 0.25))
	draw_arc(c, 22.0, 0, TAU, 24, ec, 3.0)
	if not exit_open:
		draw_line(c - Vector2(16, 16), c + Vector2(16, 16), ec, 3.0)
		draw_line(c - Vector2(-16, 16), c + Vector2(-16, -16), ec, 3.0)

func despawn() -> void:
	for e in enemies:
		if is_instance_valid(e): e.queue_free()
	if boss != null and is_instance_valid(boss): boss.queue_free()
	enemies.clear()
	queue_free()
