extends Area2D
## Burning ground. A Cinder Trail dash leaves it behind the knight, and anything
## hostile standing in it catches fire. A kindled elite sheds it as it walks
## (`bite` > 0), and then it scorches the knight instead. Either way the flames
## gutter out over LIFE seconds.

const VFX := preload("res://scripts/vfx.gd")
const LIFE := 1.6
const WIDTH := 34.0

## Damage a patch shed by a kindled elite deals the knight per touch; 0 for the
## knight's own fire.
var bite := 0.0
var _t := 0.0
var _seed := 0.0
## Target instance id -> seconds until this patch may burn it again.
var _cooldown: Dictionary = {}

func _ready() -> void:
	var hostile := bite > 0.0
	collision_layer = Content.L_ENEMY_ATK if hostile else Content.L_PLAYER_ATK
	collision_mask = Content.L_PLAYER_HURT if hostile else Content.L_ENEMY_HURT
	monitoring = true
	monitorable = false
	var shape := Content.rect_shape(Vector2(WIDTH, 22.0))
	shape.position = Vector2(0.0, -11.0)
	add_child(shape)
	material = VFX.unshaded_material()
	_seed = fmod(global_position.x * 0.37, TAU)

func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	for id in _cooldown.keys():
		_cooldown[id] = float(_cooldown[id]) - delta
		if float(_cooldown[id]) <= 0.0:
			_cooldown.erase(id)
	var prey := "player" if bite > 0.0 else "enemy"
	for area in get_overlapping_areas():
		if not is_instance_valid(area) or area.get_meta("team", "") != prey:
			continue
		var tgt = area.get_meta("owner", null)
		if tgt == null or not is_instance_valid(tgt):
			continue
		var id := int(tgt.get_instance_id())
		if _cooldown.has(id):
			continue
		_cooldown[id] = 0.5
		if bite > 0.0:
			tgt.take_damage(bite, Vector2.UP, 120.0)
		elif tgt.has_method("apply_burn"):
			tgt.apply_burn(Content.P_FLAME_BURN_DPS, 2.5)
	queue_redraw()

func _draw() -> void:
	var k := clampf(1.0 - _t / LIFE, 0.0, 1.0)
	var t := 0.0 if Feedback.motion_reduced else _t
	# A kindled elite's fire burns deeper red over a scorch mark, so it reads as
	# the enemy's and not the knight's own trail.
	var outer := VFX.EMBER if bite > 0.0 else VFX.ORANGE
	var inner := VFX.ORANGE if bite > 0.0 else VFX.GOLD
	var scorch := Color(0.08, 0.03, 0.02, 0.5 * k) if bite > 0.0 else Color(VFX.EMBER, 0.35 * k)
	VFX.draw_ellipse(self, Vector2(0.0, -1.0), WIDTH * 0.6, 4.0, scorch)
	for i in range(3):
		var x := (float(i) - 1.0) * 10.0
		VFX.draw_flame(self, Vector2(x, 0.0), (10.0 + float(i % 2) * 6.0) * k, 6.0, t, _seed + float(i) * 2.1, Color(outer, 0.9 * k), Color(inner, k))
