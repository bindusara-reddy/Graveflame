class_name Projectile
extends Area2D
## Team-aware ranged shot. Overlaps opposing hurtboxes and applies damage once per target.

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

func _ready() -> void:
	# Build collision shape
	_shape = CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = radius
	_shape.shape = circ
	add_child(_shape)
	monitoring = true
	monitorable = false
	set_meta("team", team)
	set_meta("damage", damage)

func _physics_process(delta: float) -> void:
	global_position += vel * delta
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
	if pierce > 0:
		pierce -= 1
	else:
		_die()

func _die() -> void:
	set_physics_process(false)
	queue_free()
