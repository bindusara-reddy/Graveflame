extends Node2D
## Real 2D lighting for the pixel viewport: an ambient CanvasModulate per mood
## and pooled PointLight2Ds for the knight's flame, wall torches, room braziers,
## the open rift, the boss, wisps and elites. Runs inside the pixel viewport so
## light falls on the same grid as everything else.

const VFX := preload("res://scripts/vfx.gd")

var game: Game
var _modulate: CanvasModulate
var _player_light: PointLight2D
var _exit_light: PointLight2D
var _boss_light: PointLight2D
var _torches: Array[PointLight2D] = []
var _room_lights: Array[PointLight2D] = []
var _actor_lights: Array[PointLight2D] = []
var _t := 0.0
static var _tex: GradientTexture2D

const TORCH_POOL := 5
const ROOM_POOL := 3
const ACTOR_POOL := 3

static func light_texture() -> GradientTexture2D:
	if _tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.0)])
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)
		_tex.fill_to = Vector2(1.0, 0.5)
		_tex.width = 128
		_tex.height = 128
	return _tex

func _ready() -> void:
	_modulate = CanvasModulate.new()
	_modulate.name = "Ambient"
	_modulate.color = Color(0.4, 0.36, 0.5)
	add_child(_modulate)
	_player_light = _make_light("KnightFlame", Color(1.0, 0.72, 0.42), 1.3, 4.8)
	_exit_light = _make_light("RiftLight", Content.PAL.exit, 1.0, 3.4)
	_boss_light = _make_light("BossLight", VFX.EMBER, 0.9, 4.2)
	for i in range(TORCH_POOL):
		_torches.append(_make_light("Torch%d" % i, VFX.GOLD, 1.2, 3.6))
	for i in range(ROOM_POOL):
		_room_lights.append(_make_light("Room%d" % i, VFX.GOLD, 1.0, 3.0))
	for i in range(ACTOR_POOL):
		_actor_lights.append(_make_light("Actor%d" % i, Color.WHITE, 0.8, 2.0))
	set_process(true)

func _make_light(light_name: String, color: Color, energy: float, scale: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.name = light_name
	l.texture = light_texture()
	l.color = color
	l.energy = energy
	l.texture_scale = scale
	l.shadow_enabled = false
	l.enabled = false
	add_child(l)
	return l

func set_ambient(color: Color) -> void:
	if _modulate != null:
		_modulate.color = color

func _process(delta: float) -> void:
	if game == null:
		return
	var moving := not Feedback.motion_reduced
	if moving:
		_t += delta
	var gain := 0.75 if Feedback.flash_reduced else 1.0
	var playing := game.state != Game.GState.TITLE
	var mood: Dictionary = game.mood
	var torch: Color = mood.get("torch", VFX.GOLD)
	# Knight flame.
	var player := game.player
	if playing and is_instance_valid(player) and not player.dead:
		var flame := player._flame_time > 0.0
		_player_light.enabled = true
		_player_light.global_position = player.global_position + Vector2(0.0, -10.0)
		_player_light.energy = (1.8 if flame else 1.3) * gain + (sin(_t * 9.0) * 0.05 if moving else 0.0)
		_player_light.texture_scale = 5.8 if flame else 4.8
		_player_light.color = VFX.GOLD.lerp(Color.WHITE, 0.35) if flame else Color(1.0, 0.72, 0.42)
	else:
		_player_light.enabled = false
	# Wall torches: nearest visible sconces take the pool.
	var torches := game.torch_positions() if playing else PackedVector2Array()
	for i in range(_torches.size()):
		var l := _torches[i]
		if i < torches.size():
			l.enabled = true
			l.global_position = torches[i]
			l.color = torch
			l.energy = (1.2 + (sin(_t * 8.0 + float(i) * 1.7) * 0.07 + sin(_t * 21.0 + float(i)) * 0.03 if moving else 0.0)) * gain
		else:
			l.enabled = false
	# Room lights, rift and boss.
	var room := game.room
	var points: Array = room.light_points() if playing and is_instance_valid(room) else []
	for i in range(_room_lights.size()):
		var l := _room_lights[i]
		if i < points.size():
			var lp: Dictionary = points[i]
			l.enabled = true
			l.global_position = lp.pos
			l.color = lp.color
			l.texture_scale = float(lp.radius) / 64.0 * 1.8
			l.energy = float(lp.alpha) * 3.6 * gain * (1.0 + (sin(_t * float(lp.get("rate", 8.0)) + float(lp.get("phase", 0.0))) * 0.08 if moving else 0.0))
		else:
			l.enabled = false
	if playing and is_instance_valid(room) and room.exit_open and not room.is_boss:
		_exit_light.enabled = true
		_exit_light.global_position = room.exit_center()
		_exit_light.energy = (1.1 + (sin(_t * 3.0) * 0.1 if moving else 0.0)) * gain
	else:
		_exit_light.enabled = false
	if playing and is_instance_valid(room) and room.boss != null and is_instance_valid(room.boss) and not room.boss.dead:
		_boss_light.enabled = true
		_boss_light.global_position = room.boss.global_position
		_boss_light.energy = (1.0 + (sin(_t * 6.0) * 0.08 if moving else 0.0)) * gain
	else:
		_boss_light.enabled = false
	# Wisps, elites and burning enemies share a small pool.
	var used := 0
	if playing and is_instance_valid(room):
		for e in room.enemies:
			if used >= _actor_lights.size():
				break
			if not is_instance_valid(e) or e.dead:
				continue
			var l := _actor_lights[used]
			if e.kind == Enemy.Kind.WISP:
				l.color = e.data.color
				l.energy = 0.7 * gain
				l.texture_scale = 2.0
			elif e.elite:
				l.color = Content.ELITE_COLOR
				l.energy = 0.55 * gain
				l.texture_scale = 2.4
			elif e.burn_time > 0.0:
				l.color = VFX.ORANGE
				l.energy = 0.7 * gain
				l.texture_scale = 1.9
			else:
				continue
			l.enabled = true
			l.global_position = e.global_position
			used += 1
	for i in range(used, _actor_lights.size()):
		_actor_lights[i].enabled = false
