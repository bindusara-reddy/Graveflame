class_name Feedback
extends Node2D
## Particles, camera shake, flash, and procedurally generated original audio.

var camera: Camera2D
var shake_amp := 0.0
var shake_time := 0.0
var reduced_motion := false
var reduced_flash := false
var _particles: Array[Dictionary] = []
var _audio_pool: Array[AudioStreamPlayer] = []
var _audio_idx := 0
var _streams: Dictionary = {}

const MAX_PARTICLES := 220

func _ready() -> void:
	camera = Camera2D.new()
	camera.enabled = true
	add_child(camera)
	_init_audio()
	set_process(true)

func _init_audio() -> void:
	# Generate short original PCM samples into AudioStreamWAV
	_streams["hit"] = _make_blip(220.0, 0.08, 0.6)
	_streams["hurt"] = _make_blip(120.0, 0.14, 0.7, true)
	_streams["jump"] = _make_blip(420.0, 0.07, 0.35)
	_streams["dash"] = _make_noise(0.12, 0.4)
	_streams["shoot"] = _make_blip(660.0, 0.06, 0.3)
	_streams["die"] = _make_blip(90.0, 0.4, 0.8, true)
	_streams["pickup"] = _make_blip(740.0, 0.18, 0.4)
	_streams["boss"] = _make_noise(0.5, 0.6, true)
	_streams["clear"] = _make_arpeggio()
	_streams["attack"] = _make_noise(0.05, 0.25)
	for i in range(6):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_audio_pool.append(p)

func _make_blip(freq: float, dur: float, vol: float, downward: bool = false) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(rate)
		var env := exp(-t * 6.0)
		var f := freq - (freq * 0.4 * t) if downward else freq
		var s := sin(t * f * TAU) * env * vol
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream

func _make_noise(dur: float, vol: float, low: bool = false) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var prev := 0.0
	for i in range(n):
		var t := float(i) / float(rate)
		var env := exp(-t * 5.0)
		var raw := (randf() * 2.0 - 1.0)
		if low: prev = lerpf(prev, raw, 0.25); raw = prev
		var s := raw * env * vol
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream

func _make_arpeggio() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.4
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var notes := [523.0, 659.0, 784.0, 1046.0]
	for i in range(n):
		var t := float(i) / float(rate)
		var env := exp(-t * 3.5)
		var ni := int(t / 0.1) % notes.size()
		var s := sin(t * notes[ni] * TAU) * env * 0.4
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream

func play(name: String) -> void:
	if reduced_motion and name in ["dash"]: return
	if not _streams.has(name): return
	var p := _audio_pool[_audio_idx]
	_audio_idx = (_audio_idx + 1) % _audio_pool.size()
	p.stream = _streams[name]
	p.play(0.0)

func shake(amp: float, time: float) -> void:
	if reduced_motion: return
	shake_amp = maxf(shake_amp, amp)
	shake_time = maxf(shake_time, time)

func burst(pos: Vector2, count: int, color: Color, speed: float = 220.0) -> void:
	if reduced_motion: count = maxi(2, count / 3)
	for i in range(count):
		if _particles.size() >= MAX_PARTICLES: break
		var a := randf() * TAU
		var s := speed * randf_range(0.3, 1.0)
		_particles.append({
			"pos": pos, "vel": Vector2(cos(a), sin(a)) * s, "life": randf_range(0.25, 0.6),
			"max": 0.6, "color": color, "size": randf_range(2.0, 5.0)
		})

func flash_hit(pos: Vector2) -> void:
	burst(pos, 10, Content.PAL.attack, 260.0)

func flash_hurt(pos: Vector2) -> void:
	burst(pos, 14, Color("ff6b6b"), 200.0)

func flash_death(pos: Vector2, color: Color) -> void:
	burst(pos, 22, color, 280.0)

func _process(delta: float) -> void:
	# Shake
	if shake_time > 0.0 and not reduced_motion:
		shake_time -= delta
		var o := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amp
		camera.offset = o
		if shake_time <= 0.0: shake_amp = 0.0
	else:
		camera.offset = camera.offset.lerp(Vector2.ZERO, 12.0 * delta)
	# Particles
	var i := 0
	while i < _particles.size():
		var p: Dictionary = _particles[i]
		p.pos += p.vel * delta
		p.vel *= maxf(0.0, 1.0 - 3.0 * delta)
		p.vel.y += 600.0 * delta
		p.life -= delta
		if p.life <= 0.0:
			_particles.remove_at(i)
		else:
			i += 1
	queue_redraw()

func _draw() -> void:
	for p in _particles:
		var a: float = clampf(p.life / p.max, 0.0, 1.0)
		var c: Color = p.color
		c.a = a
		draw_circle(p.pos, p.size * a, c)

func set_reduced_motion(v: bool) -> void:
	reduced_motion = v
	if v:
		shake_amp = 0.0
		shake_time = 0.0
		camera.offset = Vector2.ZERO

func set_reduced_flash(v: bool) -> void:
	reduced_flash = v

func randf_range(lo: float, hi: float) -> float:
	return lo + randf() * (hi - lo)
