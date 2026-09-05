class_name Projectile
extends Area2D
## Team-aware ranged shot. Overlaps opposing hurtboxes and applies damage once per target.

const VFX := preload("res://scripts/vfx.gd")

var team: String = "enemy"
var vel := Vector2.ZERO
var damage := 10.0
var knockback := 220.0
var pierce := 0
var life := 2.0
var radius := 9.0
var color := Color("7fd4ff")
var _hit: Dictionary = {}
var _shape: CollisionShape2D
var _age := 0.0
var _trail: Line2D
var _trail_times := PackedFloat32Array()

const TRAIL_LIFE := 0.22
const TRAIL_POINTS := 14

func setup(p_team: String, p_pos: Vector2, p_vel: Vector2, p_dmg: float, p_kb: float, p_pierce: int, p_life: float, p_color: Color) -> void:
	team = p_team
	global_position = p_pos
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
	var circ := CircleShape2D.new()
	circ.radius = radius
	_shape.shape = circ
	add_child(_shape)
	monitoring = true
	# Parry areas need to be able to detect the projectile itself.
	monitorable = true
	_update_layers()
	_build_trail()
	material = VFX.unshaded_material()

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
	global_position += vel * delta
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
		tgt.take_damage(damage, dir, knockback)
	if ateam == "scenery":
		return # Dressing shatters without consuming enemy penetration.
	if pierce > 0:
		pierce -= 1
	else:
		_die()

func reflect(direction: Vector2, damage_boost: float = 1.6) -> void:
	team = "player"
	var speed := maxf(vel.length() * 1.2, 520.0)
	var out_dir := direction.normalized()
	if out_dir == Vector2.ZERO:
		out_dir = -vel.normalized()
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

func _die() -> void:
	set_physics_process(false)
	queue_free()

func _draw() -> void:
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
