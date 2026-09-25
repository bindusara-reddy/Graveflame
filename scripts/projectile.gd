class_name Projectile
extends Area2D
## Team-aware ranged shot. Overlaps opposing hurtboxes and applies damage once per target.

const VFX := preload("res://scripts/vfx.gd")

## The shot met something, travelling along `dir`. `what` is "foe" (a player
## shot landed), "returned" (a parried shot landed), "guard" (caught on a
## shield) or "stone" (the chamber's stonework, which ends any shot).
signal struck(pos: Vector2, dir: Vector2, color: Color, what: String)

var team: String = "enemy"
var vel := Vector2.ZERO
var damage := 10.0
var knockback := 220.0
var pierce := 0
var life := 2.0
var radius := 9.0
var color := Color("7fd4ff")
## "" is a shot. "wave" is the Warden's slam shockwave, a fire ridge running
## along the floor: it stays upright and leaves no comet trail. Set before
## the projectile enters the tree.
var style := ""
var _hit: Dictionary = {}
var _shape: CollisionShape2D
var _age := 0.0
var _trail: Line2D
var _trail_times := PackedFloat32Array()
var _reflected := false
## Probes the stonework at the shot's centre each tick.
var _stone_query := PhysicsPointQueryParameters2D.new()
## Where the shot was loosed; a parry sends it back to whoever stands there.
var _origin := Vector2.ZERO
var _sender: Enemy
var _homing_t := 0.0

const TRAIL_LIFE := 0.22
const TRAIL_POINTS := 14
## A parried shot returns to the live foe nearest its origin (within
## SENDER_REACH px) at RETURN_SPEED_MUL its old speed, curving toward it at
## RETURN_TURN rad/s for RETURN_HOMING seconds so a drifting wisp is still hit.
const SENDER_REACH := 120.0
const RETURN_SPEED_MUL := 1.3
const RETURN_TURN := 3.0
const RETURN_HOMING := 0.6

func setup(p_team: String, p_pos: Vector2, p_vel: Vector2, p_dmg: float, p_kb: float, p_pierce: int, p_life: float, p_color: Color) -> void:
	team = p_team
	global_position = p_pos
	_origin = p_pos
	vel = p_vel
	damage = p_dmg
	knockback = p_kb
	pierce = p_pierce
	life = p_life
	color = p_color
	_update_layers()

func _update_layers() -> void:
	if team == "player":
		collision_layer = Content.L_PLAYER_ATK
		collision_mask = Content.L_ENEMY_HURT
		color = color if color != Color("7fd4ff") else Content.PAL.special
	else:
		collision_layer = Content.L_ENEMY_ATK
		collision_mask = Content.L_PLAYER_HURT
		color = color if color != Color("7fd4ff") else Color("ff6b6b")
	set_meta("team", team)
	set_meta("damage", damage)
	set_meta("attack_kind", "projectile")
	set_meta("owner_id", get_instance_id())

func _ready() -> void:
	# Build collision shape
	_shape = CollisionShape2D.new()
	if style == "wave":
		radius = 12.0  # as tall as its flames, down to the floor
	var circ := CircleShape2D.new()
	circ.radius = radius
	_shape.shape = circ
	add_child(_shape)
	monitoring = true
	# Parry areas need to be able to detect the projectile itself.
	monitorable = true
	_update_layers()
	if style == "":
		_build_trail()
	material = VFX.unshaded_material()
	_stone_query.collision_mask = Content.L_WORLD

## Comet ribbon: world-space points appended every physics tick and aged out.
func _build_trail() -> void:
	_trail = Line2D.new()
	_trail.name = "Trail"
	_trail.top_level = true
	_trail.show_behind_parent = true
	_trail.width = 6.0
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.0))
	taper.add_point(Vector2(1.0, 1.0))
	_trail.width_curve = taper
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.material = VFX.additive_material()
	add_child(_trail)
	_update_trail_gradient()

func _update_trail_gradient() -> void:
	if _trail == null:
		return
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	ramp.colors = PackedColorArray([
		Color(color.darkened(0.45).lerp(VFX.TYRIAN, 0.4), 0.0),
		Color(color, 0.6),
		Color(color.lightened(0.35), 0.9),
	])
	_trail.gradient = ramp

func _step_trail() -> void:
	if _trail == null:
		return
	var max_points := 5 if Feedback.motion_reduced else TRAIL_POINTS
	var life := 0.08 if Feedback.motion_reduced else TRAIL_LIFE
	_trail.add_point(global_position)
	_trail_times.append(_age)
	while _trail_times.size() > max_points or (_trail_times.size() > 0 and _age - _trail_times[0] > life):
		_trail.remove_point(0)
		_trail_times.remove_at(0)

func _physics_process(delta: float) -> void:
	_age += delta
	if _homing_t > 0.0:
		_home_on_sender(delta)
	global_position += vel * delta
	if style == "":
		rotation = vel.angle()
	_step_trail()
	queue_redraw()
	life -= delta
	if life <= 0.0:
		_die()
		return
	# Check overlaps with opposing hurtboxes
	for area in get_overlapping_areas():
		_try_hit(area)
	if is_queued_for_deletion():
		return
	if _in_stone():
		struck.emit(global_position, vel.normalized(), color, "stone")
		_die()
		return
	# Cull off-screen / below world
	var p := global_position
	if p.x < Content.ROOM_LEFT - 80 or p.x > Content.ROOM_RIGHT + 80 or p.y > Content.FLOOR_Y + 240 or p.y < -400:
		_die()

func _try_hit(area: Area2D) -> void:
	if not is_instance_valid(area):
		return
	var ateam = area.get_meta("team")
	if ateam == null or ateam == team:
		return
	var owner_id: int = area.get_meta("owner_id", 0)
	if _hit.has(owner_id):
		return
	_hit[owner_id] = true
	var tgt = area.get_meta("owner")
	if tgt != null and is_instance_valid(tgt) and tgt.has_method("take_damage"):
		var dir := vel.normalized() if vel.length() > 1.0 else Vector2.RIGHT
		Player.deal(tgt, damage, dir, knockback, 1.0)
		if team == "player" and ateam != "scenery":
			var what := "returned" if _reflected else "foe"
			if tgt.get("last_hit_blocked") == true:
				what = "guard"
			struck.emit(global_position, dir, color, what)
	if ateam == "scenery":
		return # Dressing shatters without consuming enemy penetration.
	if pierce > 0:
		pierce -= 1
	else:
		_die()

func reflect(direction: Vector2, damage_boost: float = 1.6) -> void:
	team = "player"
	_reflected = true
	var speed := maxf(vel.length() * 1.2, 520.0)
	var out_dir := direction.normalized()
	if out_dir == Vector2.ZERO:
		out_dir = -vel.normalized()
	# Back to whoever loosed it, when they are still standing near the spot.
	_sender = _foe_nearest(_origin)
	if _sender != null:
		out_dir = (_sender.global_position - global_position).normalized()
		speed = maxf(vel.length() * RETURN_SPEED_MUL, 520.0)
		_homing_t = RETURN_HOMING
	vel = out_dir * speed
	damage *= damage_boost
	pierce = maxi(pierce, 1)
	color = Content.PAL.special
	_hit.clear()
	_update_layers()
	_update_trail_gradient()
	if _trail != null:
		_trail.clear_points()
		_trail_times.clear()
	queue_redraw()

## The live foe standing nearest `spot`, within SENDER_REACH, or null.
func _foe_nearest(spot: Vector2) -> Enemy:
	var best: Enemy = null
	for foe in Enemy.living_near(get_tree(), spot, SENDER_REACH):
		if best == null or foe.global_position.distance_to(spot) < best.global_position.distance_to(spot):
			best = foe
	return best

## Curve a returned shot toward its sender, gently, while the homing lasts.
func _home_on_sender(delta: float) -> void:
	_homing_t -= delta
	if not is_instance_valid(_sender) or _sender.dead:
		_homing_t = 0.0
		return
	var turn := angle_difference(vel.angle(), (_sender.global_position - global_position).angle())
	vel = vel.rotated(clampf(turn, -RETURN_TURN * delta, RETURN_TURN * delta))

## True when the shot's centre is inside the chamber's stonework.
func _in_stone() -> bool:
	_stone_query.position = global_position
	return not get_world_2d().direct_space_state.intersect_point(_stone_query, 1).is_empty()

func _die() -> void:
	set_physics_process(false)
	queue_free()

func _draw() -> void:
	if style == "wave":
		_draw_wave()
		return
	var pulse := 0.85 + sin(_age * 22.0) * 0.15
	var glow := Color(color.r, color.g, color.b, 0.16)
	draw_circle(Vector2.ZERO, radius * 2.2 * pulse, glow)
	draw_colored_polygon(PackedVector2Array([
		Vector2(radius * 1.35, 0.0),
		Vector2(0.0, radius * 0.7),
		Vector2(-radius * 1.5, 0.0),
		Vector2(0.0, -radius * 0.7),
	]), color)
	draw_circle(Vector2(radius * 0.2, 0.0), radius * 0.42, color.lightened(0.45))
	draw_circle(Vector2(radius * 0.35, -1.0), 2.0, Color.WHITE)

## The slam wave: three flame tongues over a scorch on the floor, leaning back
## from the way the wave runs.
func _draw_wave() -> void:
	var t := 0.0 if Feedback.motion_reduced else _age
	var ground := Vector2(0.0, Content.FLOOR_Y - global_position.y)
	VFX.draw_ellipse(self, ground, 28.0, 8.0, Color(color, 0.18))
	VFX.draw_ellipse(self, ground, 18.0, 4.0, Color(VFX.JOINT, 0.6))
	draw_set_transform_matrix(Transform2D(0.0, Vector2.ONE, -signf(vel.x) * 0.35, ground))
	for i in range(3):
		var side := float(i) - 1.0
		VFX.draw_flame(self, Vector2(side * 9.0, 0.0), 30.0 - absf(side) * 8.0, 12.0, t, float(i) * 2.1, color, VFX.HOT)
	draw_set_transform_matrix(Transform2D.IDENTITY)
