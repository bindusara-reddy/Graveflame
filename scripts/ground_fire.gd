extends Area2D
## Burning ground left behind by a Cinder Trail dash. Anything hostile that
## stands in it catches fire; the flames gutter out over LIFE seconds.

const VFX := preload("res://scripts/vfx.gd")
const LIFE := 1.6
const WIDTH := 34.0

var _t := 0.0
var _seed := 0.0
## Enemy instance id -> seconds until this patch may ignite it again.
var _cooldown: Dictionary = {}

func _ready() -> void:
	collision_layer = Content.L_PLAYER_ATK
	collision_mask = Content.L_ENEMY_HURT
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
	for area in get_overlapping_areas():
		if not is_instance_valid(area) or area.get_meta("team", "") != "enemy":
			continue
		var tgt = area.get_meta("owner", null)
		if tgt == null or not is_instance_valid(tgt) or not tgt.has_method("apply_burn"):
			continue
		var id := int(tgt.get_instance_id())
		if _cooldown.has(id):
			continue
		_cooldown[id] = 0.5
		tgt.apply_burn(Content.P_FLAME_BURN_DPS, 2.5)
	queue_redraw()

func _draw() -> void:
	var k := clampf(1.0 - _t / LIFE, 0.0, 1.0)
	var t := 0.0 if Feedback.motion_reduced else _t
	VFX.draw_ellipse(self, Vector2(0.0, -1.0), WIDTH * 0.6, 4.0, Color(VFX.EMBER, 0.35 * k))
	for i in range(3):
		var x := (float(i) - 1.0) * 10.0
		VFX.draw_flame(self, Vector2(x, 0.0), (10.0 + float(i % 2) * 6.0) * k, 6.0, t, _seed + float(i) * 2.1, Color(VFX.ORANGE, 0.9 * k), Color(VFX.GOLD, k))
