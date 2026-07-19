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
var _hit_stop_active := false
var _hit_stop_until_usec: int = 0
var _hit_stop_restore_scale := 1.0

const MAX_PARTICLES := 220
const HIT_STOP_TIME_SCALE := 0.06

func _ready() -> void:
	camera = Camera2D.new()
	camera.enabled = true
	# Frame the authored 1280x720 play space before the player-follow code takes over.
	camera.position = Vector2(Content.VIEW_W, Content.VIEW_H) * 0.5
	add_child(camera)
	_init_audio()
	set_process(true)

func _exit_tree() -> void:
	# Never leave the entire game slowed if this node is removed during a freeze.
	_restore_hit_stop()

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
	# Distinct combat cues remain synthesized and asset-free.
	_streams["swing"] = _make_sweep(820.0, 150.0, 0.10, 0.34, 0.55)
	_streams["attack"] = _streams["swing"] # backwards-compatible cue name
	_streams["parry"] = _make_metallic(920.0, 0.17, 0.42)
	_streams["heal"] = _make_sweep(330.0, 820.0, 0.32, 0.32, 0.03)
	_streams["flame"] = _make_sweep(150.0, 560.0, 0.24, 0.38, 0.48)
	_streams["land"] = _make_sweep(105.0, 48.0, 0.10, 0.44, 0.30)
	_streams["shield"] = _make_metallic(250.0, 0.22, 0.48)
	for i in range(8):
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

func _make_sweep(start_freq: float, end_freq: float, dur: float, vol: float, noise_mix: float = 0.0) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var filtered_noise := 0.0
	for i in range(n):
		var t := float(i) / float(rate)
		var progress := clampf(t / maxf(dur, 0.001), 0.0, 1.0)
		var freq := lerpf(start_freq, end_freq, smoothstep(0.0, 1.0, progress))
		phase += TAU * freq / float(rate)
		var attack := clampf(t / 0.008, 0.0, 1.0)
		var env := attack * pow(1.0 - progress, 1.7)
		var raw_noise := randf() * 2.0 - 1.0
		filtered_noise = lerpf(filtered_noise, raw_noise, 0.38)
		var tone := sin(phase) + sin(phase * 2.01) * 0.18
		var sample := lerpf(tone, filtered_noise, noise_mix) * env * vol
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream

func _make_metallic(base_freq: float, dur: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(rate)
		var progress := clampf(t / maxf(dur, 0.001), 0.0, 1.0)
		var attack := clampf(t / 0.003, 0.0, 1.0)
		var env := attack * exp(-progress * 6.5)
		var sample := (
			sin(t * base_freq * TAU)
			+ sin(t * base_freq * 2.71 * TAU) * 0.52
			+ sin(t * base_freq * 4.13 * TAU) * 0.28
		) * env * vol * 0.62
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
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
	if not _streams.has(name): return
	var p := _audio_pool[_audio_idx]
	_audio_idx = (_audio_idx + 1) % _audio_pool.size()
	p.stream = _streams[name]
	p.pitch_scale = randf_range(0.97, 1.03)
	p.play(0.0)

## Briefly slows the world, measured in real time so restoration is reliable.
## Overlapping calls extend the current stop instead of racing separate timers.
func hit_stop(duration: float) -> void:
	if duration <= 0.0 or reduced_motion or not is_inside_tree():
		return
	var until := Time.get_ticks_usec() + int(duration * 1000000.0)
	_hit_stop_until_usec = maxi(_hit_stop_until_usec, until)
	if _hit_stop_active:
		return
	_hit_stop_active = true
	_hit_stop_restore_scale = Engine.time_scale
	Engine.time_scale = minf(Engine.time_scale, HIT_STOP_TIME_SCALE)
	_run_hit_stop()

func _run_hit_stop() -> void:
	while _hit_stop_active and is_inside_tree():
		var remaining := float(_hit_stop_until_usec - Time.get_ticks_usec()) / 1000000.0
		if remaining <= 0.0:
			break
		# process_always + ignore_time_scale makes this a real-time timer.
		await get_tree().create_timer(maxf(remaining, 0.001), true, false, true).timeout
	_restore_hit_stop()

func _restore_hit_stop() -> void:
	if not _hit_stop_active:
		return
	Engine.time_scale = _hit_stop_restore_scale
	_hit_stop_active = false
	_hit_stop_until_usec = 0

func shake(amp: float, time: float) -> void:
	if reduced_motion: return
	shake_amp = maxf(shake_amp, amp)
	shake_time = maxf(shake_time, time)

func burst(pos: Vector2, count: int, color: Color, speed: float = 220.0) -> void:
	if reduced_motion:
		count = maxi(2, count / 4)
		speed *= 0.35
	var effect_color := _accessible_color(color)
	for i in range(count):
		if _particles.size() >= MAX_PARTICLES: break
		var a := randf() * TAU
		var s := speed * randf_range(0.3, 1.0)
		_push_particle({
			"kind": "spark",
			"pos": pos, "vel": Vector2(cos(a), sin(a)) * s, "life": randf_range(0.25, 0.6),
			"max": 0.6, "color": effect_color, "size": randf_range(2.0, 5.0)
		})

func flash_hit(pos: Vector2) -> void:
	impact(pos, Content.PAL.attack, false)

func flash_hurt(pos: Vector2) -> void:
	impact(pos, Color("ff6b6b"), true)

func flash_death(pos: Vector2, color: Color) -> void:
	burst(pos, 22, color, 280.0)
	if not reduced_motion and not reduced_flash:
		_add_ring(pos, color, 12.0, 54.0, 0.28, 4.0)

## Forward-moving streaks for sword swings. `facing` should be -1 or 1.
func slash(pos: Vector2, facing: float, color: Color = Color("ffd23f"), heavy: bool = false) -> void:
	var count := 7 if heavy else 4
	if reduced_motion:
		count = 1
	var effect_color := _accessible_color(color)
	for i in range(count):
		var spread := randf_range(-0.55, 0.55)
		var dir := Vector2(absf(facing), spread).normalized()
		dir.x *= signf(facing) if facing != 0.0 else 1.0
		_push_particle({
			"kind": "streak",
			"pos": pos + Vector2(randf_range(-4.0, 4.0), randf_range(-18.0, 18.0)),
			"vel": dir * randf_range(180.0, 360.0) * (1.2 if heavy else 1.0),
			"life": randf_range(0.09, 0.18), "max": 0.18, "color": effect_color,
			"size": randf_range(1.5, 3.5), "length": randf_range(14.0, 28.0)
		})

## A short procedural player silhouette, useful while dashing.
func afterimage(pos: Vector2, facing: float, color: Color = Color("e8e0d0")) -> void:
	if reduced_motion:
		return
	var effect_color := _accessible_color(color)
	effect_color.a = minf(effect_color.a, 0.38 if not reduced_flash else 0.16)
	_push_particle({
		"kind": "afterimage", "pos": pos, "vel": Vector2(-facing * 28.0, 0.0),
		"life": 0.16, "max": 0.16, "color": effect_color, "size": 1.0, "facing": facing
	})

## Sparks plus a compact expanding ring at the actual point of contact.
func impact(pos: Vector2, color: Color = Color("ffd23f"), heavy: bool = false) -> void:
	burst(pos, 16 if heavy else 10, color, 330.0 if heavy else 250.0)
	if not reduced_motion:
		_add_ring(pos, color, 6.0, 36.0 if heavy else 25.0, 0.16, 4.0 if heavy else 2.5)

## Low, horizontal dust that reads as a landing rather than a combat flash.
func land_dust(pos: Vector2, strength: float = 1.0) -> void:
	if reduced_motion:
		return
	var count := clampi(int(6.0 * strength), 3, 12)
	for i in range(count):
		var side := -1.0 if i % 2 == 0 else 1.0
		_push_particle({
			"kind": "dust", "pos": pos + Vector2(randf_range(-8.0, 8.0), 0.0),
			"vel": Vector2(side * randf_range(45.0, 150.0), randf_range(-80.0, -25.0)) * strength,
			"life": randf_range(0.18, 0.34), "max": 0.34,
			"color": _accessible_color(Content.PAL.platform_edge), "size": randf_range(2.0, 4.5)
		})

func _add_ring(pos: Vector2, color: Color, radius_from: float, radius_to: float, life: float, width: float) -> void:
	var effect_color := _accessible_color(color)
	if reduced_flash:
		effect_color.a = minf(effect_color.a, 0.22)
	_push_particle({
		"kind": "ring", "pos": pos, "vel": Vector2.ZERO, "life": life, "max": life,
		"color": effect_color, "size": width, "radius_from": radius_from, "radius_to": radius_to
	})

func _accessible_color(color: Color) -> Color:
	var out := color
	if reduced_flash:
		out = out.lerp(Color(0.55, 0.52, 0.58, out.a), 0.35)
		out.a = minf(out.a, 0.48)
	return out

func _push_particle(particle: Dictionary) -> void:
	if _particles.size() < MAX_PARTICLES:
		_particles.append(particle)

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
		if p.get("kind", "spark") not in ["ring", "afterimage"]:
			p.vel.y += 600.0 * delta
		p.life -= delta
		if p.life <= 0.0:
			_particles.remove_at(i)
		else:
			i += 1
	queue_redraw()

func _draw() -> void:
	for p in _particles:
		var life: float = float(p.get("life", 0.0))
		var maximum: float = maxf(float(p.get("max", 0.001)), 0.001)
		var a := clampf(life / maximum, 0.0, 1.0)
		var c: Color = p.get("color", Color.WHITE)
		c.a *= a * (0.55 if reduced_flash else 1.0)
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		var size := float(p.get("size", 3.0))
		match String(p.get("kind", "spark")):
			"streak":
				var vel: Vector2 = p.get("vel", Vector2.RIGHT)
				var tail := vel.normalized() * float(p.get("length", 18.0)) * a
				draw_line(pos, pos - tail, c, maxf(1.0, size * a), true)
			"ring":
				var progress := 1.0 - a
				var radius := lerpf(float(p.get("radius_from", 4.0)), float(p.get("radius_to", 28.0)), progress)
				draw_arc(pos, radius, 0.0, TAU, 28, c, maxf(1.0, size * a), true)
			"afterimage":
				var facing := float(p.get("facing", 1.0))
				draw_rect(Rect2(pos - Vector2(13.0, 27.0), Vector2(26.0, 38.0)), c)
				draw_circle(pos + Vector2(0.0, -33.0), 11.0, c)
				draw_rect(Rect2(pos + Vector2(-13.0 - facing * 4.0, -27.0), Vector2(6.0, 32.0)), c)
			"dust":
				draw_circle(pos, maxf(0.8, size * a), c)
			_:
				draw_circle(pos, maxf(0.8, size * a), c)

func set_reduced_motion(v: bool) -> void:
	reduced_motion = v
	if v:
		shake_amp = 0.0
		shake_time = 0.0
		camera.offset = Vector2.ZERO
		_particles.clear()
		_restore_hit_stop()

func set_reduced_flash(v: bool) -> void:
	reduced_flash = v
	queue_redraw()

func randf_range(lo: float, hi: float) -> float:
	return lo + randf() * (hi - lo)
