extends Node2D
## Camera-following ambience: rising embers and a drifting particle each zone
## dresses its own way (moonlit dust, soot, ash, motes). Both are untextured
## CPUParticles2D (unit quads scaled to a few pixels) in world space.

const VFX := preload("res://scripts/vfx.gd")

var _embers: CPUParticles2D
var _motes: CPUParticles2D

func _ready() -> void:
	_embers = _emitter("Embers", 3.5, 2.5, VFX.additive_material(), 30.0)
	_embers.direction = Vector2(0.0, -1.0)
	_embers.spread = 24.0
	_motes = _emitter("Motes", 6.0, 4.0, VFX.unshaded_material(), 14.0)
	set_zone("crypt", Content.MOODS[0])

## A world-space emitter filling the view, wandering sideways by up to `wander`.
func _emitter(emitter_name: String, lifetime: float, preprocess: float, mat: Material, wander: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = emitter_name
	p.lifetime = lifetime
	p.preprocess = preprocess
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(720.0, 440.0)
	p.local_coords = false
	p.gravity = Vector2.ZERO
	p.tangential_accel_min = -wander
	p.tangential_accel_max = wander
	p.material = mat
	add_child(p)
	return p

## Re-dress the air for a chamber's zone: a few sparks over dust sinking through
## the crypt's moonlight, a spark-and-soot updraft in the works, ash flakes
## falling through the pit and a hot storm of embers at the throne. New counts
## restart the emitters, which the rift's burn-in hides.
func set_zone(zone: String, mood: Dictionary) -> void:
	match zone:
		"works":
			_tune(_embers, 70, Vector2(60.0, 120.0), Vector2(2.0, 3.0))
			_tune(_motes, 30, Vector2(10.0, 20.0), Vector2(2.0, 4.0))
			_drift(Color("1a1410", 0.5), Vector2(0.1, 1.0), 60.0)
		"ashpit":
			_tune(_embers, 25, Vector2(45.0, 90.0), Vector2(2.0, 3.0))
			_tune(_motes, 60, Vector2(14.0, 26.0), Vector2(1.5, 3.0))
			_drift(Color("b8aeb0", 0.35), Vector2(0.3, 1.0), 20.0)
		"throne":
			_tune(_embers, 110, Vector2(80.0, 160.0), Vector2(2.0, 4.0))
			_tune(_motes, 30, Vector2(8.0, 15.0), Vector2(1.0, 1.0))
			_drift(Color(VFX.SLATE, 0.28), Vector2(1.0, 0.0), 180.0)
		_:
			_tune(_embers, 10, Vector2(45.0, 90.0), Vector2(2.0, 3.0))
			_tune(_motes, 40, Vector2(6.0, 12.0), Vector2(1.0, 1.0))
			_drift(Color(mood.moon, 0.22), Vector2(0.2, 1.0), 20.0)
	# The throne's embers burn hotter, starting orange and dying ember-red.
	var hot := zone == "throne"
	var spark := VFX.ORANGE if hot else VFX.GOLD
	_embers.color_ramp = _ramp([0.0, 0.15, 0.6, 1.0], [Color(spark, 0.0), Color(spark, 0.8), Color(VFX.EMBER if hot else VFX.ORANGE, 0.5), Color(VFX.EMBER, 0.0)])
	if _embers.visible:
		_embers.restart()
		_motes.restart()

func _tune(p: CPUParticles2D, amount: int, speed: Vector2, size: Vector2) -> void:
	p.amount = amount
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y

## The drifting particle's colour (fading in and out), heading and spread.
func _drift(color: Color, heading: Vector2, spread: float) -> void:
	_motes.direction = heading
	_motes.spread = spread
	_motes.color_ramp = _ramp([0.0, 0.2, 0.8, 1.0], [Color(color, 0.0), color, color, Color(color, 0.0)])

static func _ramp(offsets: Array, colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g

func set_reduced_motion(value: bool) -> void:
	# Sustained drift is exactly what reduced motion asks to remove, so hide rather than freeze.
	for p in [_embers, _motes]:
		p.emitting = not value
		p.visible = not value
		if not value:
			p.restart()
