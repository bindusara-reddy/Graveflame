extends Node2D
## Camera-following ambience: rising embers and drifting dust motes. Both are
## untextured CPUParticles2D (unit quads scaled to a few pixels) in world space.

const VFX := preload("res://scripts/vfx.gd")

var _embers: CPUParticles2D
var _motes: CPUParticles2D

func _ready() -> void:
	_embers = CPUParticles2D.new()
	_embers.name = "Embers"
	_embers.amount = 50
	_embers.lifetime = 3.5
	_embers.preprocess = 2.5
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(720.0, 440.0)
	_embers.local_coords = false
	_embers.direction = Vector2(0.0, -1.0)
	_embers.spread = 24.0
	_embers.gravity = Vector2.ZERO
	_embers.initial_velocity_min = 45.0
	_embers.initial_velocity_max = 90.0
	_embers.tangential_accel_min = -30.0
	_embers.tangential_accel_max = 30.0
	_embers.scale_amount_min = 2.0
	_embers.scale_amount_max = 3.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	ramp.colors = PackedColorArray([
		Color(VFX.GOLD, 0.0), Color(VFX.GOLD, 0.8), Color(VFX.ORANGE, 0.5), Color(VFX.EMBER, 0.0),
	])
	_embers.color_ramp = ramp
	_embers.material = VFX.additive_material()
	add_child(_embers)

	_motes = CPUParticles2D.new()
	_motes.name = "Motes"
	_motes.amount = 30
	_motes.lifetime = 6.0
	_motes.preprocess = 4.0
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(720.0, 440.0)
	_motes.local_coords = false
	_motes.direction = Vector2(1.0, 0.0)
	_motes.spread = 180.0
	_motes.gravity = Vector2.ZERO
	_motes.initial_velocity_min = 8.0
	_motes.initial_velocity_max = 15.0
	_motes.tangential_accel_min = -14.0
	_motes.tangential_accel_max = 14.0
	_motes.scale_amount_min = 1.0
	_motes.scale_amount_max = 1.0
	var mote_ramp := Gradient.new()
	mote_ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	mote_ramp.colors = PackedColorArray([
		Color(VFX.SLATE, 0.0), Color(VFX.SLATE, 0.28), Color(VFX.SLATE, 0.28), Color(VFX.SLATE, 0.0),
	])
	_motes.color_ramp = mote_ramp
	add_child(_motes)

func set_reduced_motion(value: bool) -> void:
	# Sustained drift is exactly what reduced motion asks to remove, so hide rather than freeze.
	for p in [_embers, _motes]:
		p.emitting = not value
		p.visible = not value
		if not value:
			p.restart()
