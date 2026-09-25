class_name Feedback
extends Node2D
## Particles, camera shake, flash, and procedurally generated original audio.

const VFX := preload("res://scripts/vfx.gd")
const KnightArt := preload("res://scripts/knight_art.gd")

## Per-kind [drag, gravity]: light hangs where it flared, debris falls, smoke and
## embers rise. Any kind not listed falls like a spark.
const MOTION := {
	"ring": [3.0, 0.0], "afterimage": [3.0, 0.0], "parry_ring": [3.0, 0.0], "ground_ring": [3.0, 0.0],
	"slash": [3.0, 0.0], "flash": [3.0, 0.0], "riposte": [3.0, 0.0],
	"shard": [2.2, 400.0], "hitspark": [3.0, 400.0], "number": [4.0, 240.0],
	"puff": [4.5, -15.0], "ember": [1.5, -40.0], "cut": [3.0, 0.0],
}
const SPARK_MOTION := [3.0, 600.0]

var camera: Camera2D
## Trauma shake: every shake() adds amp / SHAKE_TRAUMA_PX of trauma (capped at
## 1), the camera wanders SHAKE_MAX_PX * trauma^2 along smooth noise, and the
## trauma drains at SHAKE_DECAY per second once the caller's hold has passed.
## Squaring keeps a lone light hit subtle while a pile-up really rocks.
const SHAKE_TRAUMA_PX := 18.0
const SHAKE_MAX_PX := 14.0
const SHAKE_DECAY := 2.2
## Screen-shake strength (Options); 0 turns shake off without touching the rest.
static var shake_scale := 1.0
var _trauma := 0.0
var _trauma_hold := 0.0
## Directional kick: a shove of the view that peaks KICK_PEAK real seconds
## after the blow and springs back, critically damped, in about five times that.
const KICK_PEAK := 0.03
var _kick := Vector2.ZERO
var _kick_at := -1.0
var _zoom_tween: Tween
## The zoom a punch returns to, held while a punch is running.
var _zoom_rest := Vector2.ONE
## Vignette edge pulse (see flash_edge): its colour and real-time window.
var _edge_color := Color.TRANSPARENT
var _edge_from_usec := 0
var _edge_until_usec := 0
## Accessibility switches, static so visual-only nodes can honor them without a
## reference to this instance; write them through set_reduced_motion /
## set_reduced_flash, which also clear effects.
static var motion_reduced := false
static var flash_reduced := false
## Controller vibration switch (Options). Off means the pad never rumbles.
static var vibration := true
## Screen-shake strength (Options); scales shakes and kicks, 0 turns them off.
static var shake_scale := 1.0
var _glow: Node2D
var _particles: Array[Dictionary] = []
var _audio_pool: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _hit_stop_active := false
var _hit_stop_until_usec: int = 0
## Cinematic slow motion (death and victory beats). Hit-stop and slow motion
## both want Engine.time_scale; the slower of the two always wins, and ending
## one restores whatever the other still asks for instead of a stale snapshot.
var _slowmo := 1.0
var _slowmo_tween: Tween

const MAX_PARTICLES := 320
const HIT_STOP_TIME_SCALE := 0.06

func _ready() -> void:
	camera = Camera2D.new()
	camera.enabled = true
	# Frame the authored 1280x720 play space, tightened by CAM_ZOOM so fighters
	# read at the locked approval scale before the follow code takes over.
	camera.position = Vector2(Content.VIEW_W, Content.VIEW_H) * 0.5
	# CAM_ZOOM is the only world scaling.
	camera.zoom = Vector2.ONE * Content.CAM_ZOOM
	add_child(camera)
	# Additive layer for pure-light effects: rings, parry halo, slash afterglow, flashes.
	_glow = Node2D.new()
	_glow.name = "Glow"
	_glow.material = VFX.additive_material()
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	material = VFX.unshaded_material()
	_init_audio()

func _exit_tree() -> void:
	if _sfx_thread != null and _sfx_thread.is_started():
		_sfx_thread.wait_to_finish()
		_sfx_thread = null
	# Never leave the entire game slowed if this node is removed during a freeze.
	_restore_hit_stop()
	if _slowmo_tween != null and _slowmo_tween.is_valid():
		_slowmo_tween.kill()
	_slowmo = 1.0
	Engine.time_scale = 1.0

func _apply_time_scale() -> void:
	Engine.time_scale = minf(HIT_STOP_TIME_SCALE if _hit_stop_active else 1.0, _slowmo)

## Ease into `scale` and back out to full speed over `duration` real seconds.
## Reduced motion keeps real time: a sudden world slowdown is exactly the kind
## of motion change that setting exists to remove.
func slow_motion(scale: float, duration: float) -> void:
	if motion_reduced or not is_inside_tree():
		return
	if _slowmo_tween != null and _slowmo_tween.is_valid():
		_slowmo_tween.kill()
	_slowmo_tween = create_tween()
	_slowmo_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_slowmo_tween.set_ignore_time_scale(true)
	_slowmo_tween.tween_method(_set_slowmo, _slowmo, scale, 0.12)
	_slowmo_tween.tween_interval(maxf(0.0, duration * 0.55))
	_slowmo_tween.tween_method(_set_slowmo, scale, 1.0, maxf(0.05, duration * 0.45)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func end_slow_motion() -> void:
	if _slowmo_tween != null and _slowmo_tween.is_valid():
		_slowmo_tween.kill()
	_set_slowmo(1.0)

func _set_slowmo(v: float) -> void:
	_slowmo = clampf(v, 0.01, 1.0)
	_apply_time_scale()

const SfxSynth := preload("res://scripts/sfx_synth.gd")
## World voices pause with the tree. The persistent few play through a pause:
## a toll ringing over a panel, menu cues while the game is held.
const VOICES := 20
const PERSISTENT_VOICES := 4
## Who may cut whom when every voice is busy: a footstep never cuts a toll.
## Unlisted cues rank 1.
const PRIORITY := {
	"victory": 3, "defeat": 3, "boss": 3, "roar": 3, "last_ember": 3,
	"elite": 2, "wave": 2, "clear": 2, "parry": 2, "perfect_parry": 2, "second_wind": 2, "pyre": 2, "rift": 2,
	"step": 0, "ui_move": 0,
}
## Most copies of a cue that may sound at once; another restarts the oldest.
const POLYPHONY := { "step": 2, "swing": 3, "hit": 3, "tear": 4, "shoot": 2, "spit": 2 }
## Cues with a musical pitch: never humanized, so they stay in the score's key.
const PITCHED := [
	"clear", "wave", "victory", "defeat", "heal", "pickup", "streak", "second_wind", "elite",
	"ui_move", "ui_confirm", "ui_back", "perfect_parry", "tell_sexton", "grave_light",
	"fold", "grave_bell", "kindle",
]
## Cues that duck the score through its sidechained compressor (music.gd).
const STINGERS := ["boss", "roar", "last_ember", "elite", "wave", "clear", "victory", "defeat"]
const STINGER_BUS := "Stinger"
var _sfx_thread: Thread
## name -> Array of takes; play() rotates through them.
var _takes: Dictionary = {}
var _take_idx: Dictionary = {}
var _persistent_pool: Array[AudioStreamPlayer] = []
## The low-flame heartbeat's last beat, so each pulse sounds once.
var _heartbeat_beat := 0

func _init_audio() -> void:
	# Every cue is registered up front so callers and contracts can see the full
	# cue book at once; the waveforms arrive from a worker thread a moment later
	# (about a second of synthesis), and play() stays silent for a cue until then.
	for name in SfxSynth.cue_names():
		_streams[name] = null
	for i in range(VOICES + PERSISTENT_VOICES):
		var p := AudioStreamPlayer.new()
		# One bus for every gameplay and menu cue, so a single slider mixes them.
		p.bus = "SFX"
		add_child(p)
		if i < VOICES:
			_audio_pool.append(p)
		else:
			p.process_mode = Node.PROCESS_MODE_ALWAYS
			_persistent_pool.append(p)
	var cached := SfxSynth.load_cached()
	if not cached.is_empty():
		_install_sfx(cached)
		return
	_sfx_thread = Thread.new()
	_sfx_thread.start(_render_sfx)

static func _render_sfx() -> Dictionary:
	var out := {}
	for name in SfxSynth.cue_names():
		var takes: Array = []
		for take in range(int(SfxSynth.VARIANTS.get(name, 1))):
			takes.append(SfxSynth.build_pcm(name, take))
		out[name] = takes
	return out

## Collect the rendered cue book once the worker is done.
func _collect_sfx() -> void:
	if _sfx_thread == null or _sfx_thread.is_alive():
		return
	var pcm: Dictionary = _sfx_thread.wait_to_finish()
	_sfx_thread = null
	var book := {}
	for name in pcm:
		var takes: Array = []
		for data in pcm[name]:
			takes.append(SfxSynth.to_stream(data))
		book[name] = takes
	_install_sfx(book)
	SfxSynth.save_cached(book)

func _install_sfx(book: Dictionary) -> void:
	for name in book:
		var takes: Array = book[name]
		_takes[name] = takes
		_streams[name] = takes[0]

## Play a cue; an unknown or not-yet-rendered one is silently skipped.
## `humanize` detunes by up to 3% so repeats never machine-gun; melodic calls
## pass false, and PITCHED cues are never detuned. A cue played while the tree
## is paused (menus) goes to a persistent voice so the pause cannot hold it.
func play(name: String, pitch: float = 1.0, volume_db: float = 0.0, humanize: bool = true) -> void:
	var paused := is_inside_tree() and get_tree().paused
	_voice(name, pitch, volume_db, humanize, _persistent_pool if paused else _audio_pool)

## Play a cue that must ring on through a paused tree (a toll over a panel).
func play_persistent(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	_voice(name, pitch, volume_db, true, _persistent_pool)

## Before a panel pauses the tree: world sounds end here, instead of freezing
## and replaying their tails in the next chamber or run.
func stop_world_voices() -> void:
	for p in _audio_pool:
		p.stop()

## One heartbeat per turn of the low-health pulse, louder as the flame gutters.
## `phase` is the vignette's own clock, so each beat lands on its reddest frame.
func heartbeat(phase: float, strength: float) -> void:
	var beat := floori((phase - PI * 0.5) / TAU)
	if beat > _heartbeat_beat:
		play("heartbeat", 1.0, linear_to_db(0.3 + 0.7 * strength))
	# A pulse that restarted from zero (the flame recovered) waits for its peak.
	_heartbeat_beat = beat

## Sound the next take of `name` on a voice from `pool`.
func _voice(name: String, pitch: float, volume_db: float, humanize: bool, pool: Array[AudioStreamPlayer]) -> void:
	if _streams.get(name) == null:
		return
	var takes: Array = _takes.get(name, [])
	var stream: AudioStream = _streams[name]
	if takes.size() > 1:
		var ti := (int(_take_idx.get(name, 0)) + 1) % takes.size()
		_take_idx[name] = ti
		stream = takes[ti]
	var p := _pick_voice(name, pool)
	if p == null:
		return
	p.stream = stream
	p.set_meta("cue", name)
	# Stingers key the score's compressor so the music steps back under them.
	var stinger := STINGERS.has(name) and AudioServer.get_bus_index(STINGER_BUS) >= 0
	p.bus = STINGER_BUS if stinger else "SFX"
	var detune := randf_range(0.97, 1.03) if humanize and not PITCHED.has(name) else 1.0
	p.pitch_scale = pitch * detune
	# Telegraphs attenuate with distance; UI and player cues stay flat.
	p.volume_db = volume_db
	p.play(0.0)

## A cue at its polyphony cap restarts its own oldest copy; otherwise a free
## voice; otherwise the least important voice, furthest into its cue. A voice
## that outranks the new cue is never cut: then the new cue is dropped instead.
func _pick_voice(name: String, pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	var rank := int(PRIORITY.get(name, 1))
	var copies := 0
	var oldest_copy: AudioStreamPlayer = null
	var free: AudioStreamPlayer = null
	var victim: AudioStreamPlayer = null
	var victim_score := INF
	for p in pool:
		if not p.playing and not p.stream_paused:
			if free == null:
				free = p
			continue
		var cue := str(p.get_meta("cue", ""))
		var progress := p.get_playback_position()
		if cue == name:
			copies += 1
			if oldest_copy == null or progress > oldest_copy.get_playback_position():
				oldest_copy = p
		# Rank first; among equals, the voice nearest the end of its cue.
		var p_rank := int(PRIORITY.get(cue, 1))
		var score := float(p_rank) * 1000.0 - progress
		if p_rank <= rank and score < victim_score:
			victim = p
			victim_score = score
	if copies >= int(POLYPHONY.get(name, pool.size())):
		return oldest_copy
	return free if free != null else victim

## Rift bloom where an enemy is pulled into the chamber: ring plus rising embers.
func spawn_rift(pos: Vector2, color: Color) -> void:
	_add_ring(pos, color, 4.0, 48.0, 0.36, 3.0)
	if motion_reduced:
		return
	var effect_color := _accessible_color(color)
	for i in range(12):
		if _particles.size() >= MAX_PARTICLES: break
		_push_particle({
			"kind": "ember", "pos": pos + Vector2(randf_range(-16.0, 16.0), randf_range(0.0, 14.0)),
			"vel": Vector2(randf_range(-30.0, 30.0), -randf_range(110.0, 240.0)),
			"life": randf_range(0.3, 0.55), "max": 0.55, "color": effect_color, "size": randf_range(1.5, 3.2)
		})

## Floating combat text. `kind` picks the palette: hit, heavy, block, hurt, heal,
## elite. Pass `text` for a word instead of a number.
func damage_number(pos: Vector2, amount: float, kind: String = "hit", text: String = "") -> void:
	var label := text if text != "" else str(roundi(amount))
	if text == "" and roundi(amount) <= 0:
		return
	var tally := text == "" and (kind == "hit" or kind == "heavy")
	if tally and _add_to_number(pos, amount, kind):
		return
	var color: Color = VFX.GOLD
	var size := 26.0
	match kind:
		"heavy":
			color = VFX.HOT
			size = 34.0
		"block":
			color = VFX.SLATE.lightened(0.25)
			size = 22.0
		"hurt":
			color = Content.PAL.hurt_number
			size = 30.0
		"heal":
			color = Content.PAL.heal_number
			size = 28.0
		"elite":
			color = Content.ELITE_COLOR
			size = 32.0
		_:
			if amount >= 30.0:
				color = VFX.GOLD.lerp(VFX.HOT, 0.5)
				size = 30.0
	var vel := Vector2(randf_range(-26.0, 26.0), -randf_range(120.0, 170.0))
	if motion_reduced:
		vel = Vector2(0.0, -40.0)
	var number := {
		"kind": "number", "pos": pos + Vector2(randf_range(-8.0, 8.0), 0.0), "vel": vel,
		"life": 0.85, "max": 0.85, "color": _accessible_color(color), "size": size, "text": label
	}
	if tally:
		number.merge({ "total": amount, "anchor": pos })
	_push_particle(number)

## Seconds a damage number stays open for the next blow, and how near (px)
## that blow must land to add to it instead of stacking a new glyph on top.
const NUMBER_TALLY_TIME := 0.45
const NUMBER_TALLY_REACH := 56.0

## Fold `amount` into a damage number still rising from about `pos`: it shows
## the running total and re-pops a size larger. False when none is open.
func _add_to_number(pos: Vector2, amount: float, kind: String) -> bool:
	for p in _particles:
		var open: bool = p.has("total") and float(p.max) - float(p.life) <= NUMBER_TALLY_TIME
		if not open or p.anchor.distance_to(pos) > NUMBER_TALLY_REACH:
			continue
		p.total += amount
		p.text = str(roundi(p.total))
		p.anchor = pos
		p.life = p.max
		p.size = minf(float(p.size) + 4.0, 38.0)
		p.vel = Vector2(0.0, -40.0 if motion_reduced else -110.0)
		if kind == "heavy":
			p.color = _accessible_color(VFX.HOT)
		return true
	return false

## Briefly slows the world, measured in real time so restoration is reliable.
## Overlapping calls extend the current stop instead of racing separate timers.
func hit_stop(duration: float) -> void:
	if duration <= 0.0 or motion_reduced or not is_inside_tree():
		return
	var until := Time.get_ticks_usec() + int(duration * 1000000.0)
	_hit_stop_until_usec = maxi(_hit_stop_until_usec, until)
	if _hit_stop_active:
		return
	_hit_stop_active = true
	_apply_time_scale()
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
	_hit_stop_active = false
	_hit_stop_until_usec = 0
	_apply_time_scale()

## Pad rumble: `weak` is the fast motor, `strong` the heavy one (0..1).
func rumble(weak: float, strong: float, duration: float) -> void:
	if not vibration:
		return
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)

## Add trauma worth `amp` pixels; it holds for half of `time` before draining.
func shake(amp: float, time: float) -> void:
	if motion_reduced: return
	_trauma = minf(1.0, _trauma + amp / SHAKE_TRAUMA_PX)
	_trauma_hold = maxf(_trauma_hold, time * 0.5)

## Shove the world `px` pixels along `dir` (the way the blow travelled) and let
## it spring back, so a hit reads as a push rather than noise. Real time, so it
## plays through a hit-stop freeze.
func kick(dir: Vector2, px: float) -> void:
	if motion_reduced or dir == Vector2.ZERO:
		return
	_kick = -dir.normalized() * px
	_kick_at = _now()

## Punch the camera in by `mul` over `in_t` real seconds and ease it back over
## `out_t`, for the moments that deserve a lean-in: a perfect parry, ignition,
## a chamber's last kill. Back-to-back punches return to the original zoom.
func punch_zoom(mul: float, in_t: float, out_t: float) -> void:
	if motion_reduced or not is_inside_tree():
		return
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	else:
		_zoom_rest = camera.zoom
	_zoom_tween = create_tween().set_ignore_time_scale(true)
	_zoom_tween.tween_property(camera, "zoom", _zoom_rest * mul, in_t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(camera, "zoom", _zoom_rest, out_t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Tint the vignette's edge toward `color`, fading back over `seconds` of real
## time. The game passes its own edge colour through vignette_edge().
func flash_edge(color: Color, seconds: float) -> void:
	_edge_color = color
	_edge_from_usec = Time.get_ticks_usec()
	_edge_until_usec = _edge_from_usec + int(seconds * 1000000.0)

## `edge` with any running flash_edge pulse blended over it; reduced flash
## keeps the pulse faint.
func vignette_edge(edge: Color) -> Color:
	var now := Time.get_ticks_usec()
	if now >= _edge_until_usec:
		return edge
	var left := float(_edge_until_usec - now) / float(maxi(1, _edge_until_usec - _edge_from_usec))
	return edge.lerp(_edge_color, left * (0.45 if flash_reduced else 1.0))

## Real seconds; the camera's kick and shake noise run on it.
func _now() -> float:
	return float(Time.get_ticks_usec()) * 0.000001

## Smooth noise in -1..1: two detuned sines, so the shake drifts instead of
## jumping to a fresh random spot every frame.
static func _wobble(x: float) -> float:
	return (sin(x) + 0.5 * sin(x * 2.3 + 1.7)) / 1.5

## Shake plus kick: the camera's whole offset this frame.
func _camera_offset() -> Vector2:
	var offset := Vector2.ZERO
	var now := _now()
	if _trauma > 0.0:
		var amp := SHAKE_MAX_PX * _trauma * _trauma * shake_scale
		offset += Vector2(_wobble(now * 38.0), _wobble(now * 41.0 + 7.0)) * amp
	var k := (now - _kick_at) / KICK_PEAK
	if _kick_at >= 0.0 and k < 6.0:
		offset += _kick * k * exp(1.0 - k)
	return offset

func burst(pos: Vector2, count: int, color: Color, speed: float = 220.0) -> void:
	if motion_reduced:
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

## Ceramic/brass fragments follow the blow, with no loot or explosion flash.
func shatter(pos: Vector2, force: Vector2, color: Color) -> void:
	play("shatter")
	var count := 3 if motion_reduced else 12
	for i in range(count):
		var speed := 0.18 if motion_reduced else 1.0
		var size := randf_range(3.0, 7.0)
		_push_particle({
			"kind": "shard", "pos": pos + Vector2(randf_range(-10.0, 10.0), randf_range(-12.0, 10.0)),
			"vel": (force * 0.45 + Vector2(randf_range(-100.0, 100.0), randf_range(-190.0, -60.0))) * speed,
			"life": 0.5, "max": 0.5, "color": _accessible_color(color), "size": 1.0,
			"shape": PackedVector2Array([Vector2(-size, 0.0), Vector2(0.0, -size), Vector2(size, size * 0.5)]),
			"rot": randf() * TAU, "angvel": randf_range(-9.0, 9.0) * speed,
		})

func flash_hurt(pos: Vector2) -> void:
	impact(pos, Color("ff6b6b"), true)

## Death burst: a gold flash, dark ember-rimmed shards that tumble and drop, sparks.
func flash_death(pos: Vector2, color: Color, big: bool = false) -> void:
	_flash(pos, 64.0 if big else 45.0)
	# Ordinary kills come apart as paper halves (see Severed), so their confetti
	# stays light; the big deaths keep the full shower.
	var shards := 32 if big else 9
	var sparks := 20 if big else 12
	if motion_reduced:
		shards = 5
		sparks = 3
	var outline := _accessible_color(VFX.EMBER.lerp(color, 0.35))
	for i in range(shards):
		if _particles.size() >= MAX_PARTICLES: break
		var a := randf() * TAU
		var s := randf_range(220.0, 480.0) * (0.35 if motion_reduced else 1.0)
		var corners := 3 + (i % 3)
		var size := randf_range(3.0, 11.0)
		var shape := PackedVector2Array()
		for v in range(corners):
			var va := TAU * float(v) / float(corners) + randf_range(-0.3, 0.3)
			shape.append(Vector2(cos(va), sin(va)) * size * randf_range(0.6, 1.0))
		_push_particle({
			"kind": "shard", "pos": pos, "vel": Vector2(cos(a), sin(a)) * s,
			"life": randf_range(0.45, 0.75), "max": 0.75, "color": outline, "size": 1.5,
			"shape": shape, "rot": randf() * TAU, "angvel": randf_range(-12.0, 12.0)
		})
	burst_sparks(pos, sparks, 320.0, color)
	if not motion_reduced and not flash_reduced:
		_add_ring(pos, color, 12.0, 54.0, 0.28, 4.0)

## Sparks that stretch along their velocity and ramp white -> tint -> ember.
## Given a `dir` they spray within SPARK_CONE of it, out through the far side
## of a blow; without one they burst all around.
const SPARK_CONE := 0.7
func burst_sparks(pos: Vector2, count: int, speed: float, tint: Color = VFX.GOLD, dir := Vector2.ZERO) -> void:
	if motion_reduced:
		count = maxi(2, count / 4)
		speed *= 0.35
	var tint_col := _accessible_color(tint)
	for i in range(count):
		if _particles.size() >= MAX_PARTICLES: break
		var a := dir.angle() + randf_range(-SPARK_CONE, SPARK_CONE) if dir != Vector2.ZERO else randf() * TAU
		_push_particle({
			"kind": "hitspark", "pos": pos, "vel": Vector2(cos(a), sin(a)) * speed * randf_range(0.55, 1.0),
			"life": randf_range(0.14, 0.22), "max": 0.22, "color": tint_col, "size": 2.0,
			"length": randf_range(6.0, 14.0)
		})

## Additive afterglow of a blade sweep. `a0` -> `a1` are body angles (authored
## facing right) so the glow travels the way the sword actually swung: down for
## the cut, up for the cleave, overhead for the finisher.
func slash_arc(origin: Vector2, facing: float, radius: float, a0: float, a1: float, heavy: bool = false) -> void:
	if motion_reduced:
		return
	_push_particle({
		"kind": "slash", "pos": origin, "vel": Vector2.ZERO, "life": 0.16, "max": 0.16,
		"color": Color.WHITE, "size": 16.0 if heavy else 12.0, "radius": radius, "a0": a0, "a1": a1, "facing": facing
	})

## Thin counterthrust silhouette, readable even with motion reduction enabled.
func riposte_cut(origin: Vector2, facing: float, reach: float) -> void:
	_push_particle({
		"kind": "riposte", "pos": origin, "vel": Vector2.ZERO, "life": 0.22, "max": 0.22,
		"color": _accessible_color(VFX.TEAL), "radius": reach, "facing": facing, "size": 1.0,
	})

## A paper-cut sliver through the point of contact, slanted along the swing
## (`angle` in screen radians): white-hot for CUT_HOT seconds, then cooling to
## ember as it fades. It never moves, so reduced motion keeps it.
const CUT_HOT := 0.06
const CUT_LIFE := 0.16
func cut_line(pos: Vector2, angle: float, heavy: bool) -> void:
	_push_particle({
		"kind": "cut", "pos": pos, "vel": Vector2.ZERO, "life": CUT_LIFE, "max": CUT_LIFE,
		"color": _accessible_color(Color.WHITE), "size": 92.0 if heavy else 64.0, "angle": angle,
	})

## Teal-to-gold dual ring for a successful deflect.
func parry_flash(pos: Vector2) -> void:
	var life := 0.16
	_push_particle({
		"kind": "parry_ring", "pos": pos, "vel": Vector2.ZERO, "life": life, "max": life,
		"color": Color(VFX.TEAL, 0.22 if flash_reduced else 1.0), "size": 3.0,
		"radius_from": 8.0, "radius_to": 40.0 if motion_reduced else 78.0
	})
	burst_sparks(pos, 12, 300.0)

## Explosion payoff: gold flash plus an ember ring out to the blast radius.
func blast(pos: Vector2, radius: float) -> void:
	_flash(pos, radius * 0.5)
	if not motion_reduced:
		_add_ring(pos, VFX.EMBER, 12.0, radius, 0.3, 5.0)

func _flash(pos: Vector2, radius: float) -> void:
	if flash_reduced:
		return
	_push_particle({ "kind": "flash", "pos": pos, "vel": Vector2.ZERO, "life": 0.05, "max": 0.05, "color": VFX.GOLD, "size": radius })

## Forward-moving streaks for sword swings. `facing` should be -1 or 1.
func slash(pos: Vector2, facing: float, color: Color = Color("ffd23f"), heavy: bool = false) -> void:
	var count := 7 if heavy else 4
	if motion_reduced:
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

## A flat echo of the knight in the pose it held, left behind while dashing.
## No pose, no echo.
func afterimage(pos: Vector2, facing: float, color: Color = Color("e8e0d0"), pose: Dictionary = {}) -> void:
	if motion_reduced or pose.is_empty():
		return
	var effect_color := _accessible_color(color)
	effect_color.a = minf(effect_color.a, 0.38 if not flash_reduced else 0.16)
	_push_particle({
		"kind": "afterimage", "pos": pos, "vel": Vector2(-facing * 28.0, 0.0),
		"life": 0.20, "max": 0.20, "color": effect_color, "size": 1.0, "facing": facing,
		"pose": pose.duplicate(),
	})

## Stretched sparks plus a compact additive ring at the actual point of
## contact; `dir` (the way the blow travelled) sprays the sparks through.
func impact(pos: Vector2, color: Color = Color("ffa827"), heavy: bool = false, dir := Vector2.ZERO) -> void:
	burst_sparks(pos, 18 if heavy else 14, 380.0 if heavy else 300.0, color, dir)
	if not motion_reduced:
		_add_ring(pos, color, 6.0, 36.0 if heavy else 25.0, 0.16, 4.0 if heavy else 2.5)

## A shot meeting something (see Projectile.struck). A landed player shot
## sparks along its flight with a tick of freeze and a light rumble, and a
## returned one lands harder; a guard or the stonework throws sparks back.
func projectile_struck(pos: Vector2, dir: Vector2, color: Color, what: String) -> void:
	if what == "stone" or what == "guard":
		burst_sparks(pos, 6, 200.0, color, -dir)
		play("clang" if what == "guard" else "bolt_hit", 1.3, -10.0)
		return
	impact(pos, color, false, dir)
	play("bolt_hit")
	hit_stop(0.06 if what == "returned" else 0.025)
	rumble(0.15, 0.0, 0.05)
	if what == "returned":
		play("parry", 1.4, -6.0)

## Floor-hugging slam dust: a flattened expanding ring plus squashed puffs.
func land_dust(pos: Vector2, strength: float = 1.0) -> void:
	if motion_reduced:
		return
	_push_particle({
		"kind": "ground_ring", "pos": pos, "vel": Vector2.ZERO, "life": 0.38, "max": 0.38,
		"color": _accessible_color(VFX.SLATE), "size": 4.0, "radius_from": 8.0, "radius_to": 135.0 * strength
	})
	var count := clampi(int(16.0 * strength), 8, 24)
	for i in range(count):
		var side := -1.0 if i % 2 == 0 else 1.0
		_push_particle({
			"kind": "puff", "pos": pos + Vector2(randf_range(-10.0, 10.0), randf_range(-2.0, 2.0)),
			"vel": Vector2(side * randf_range(160.0, 260.0) * strength * 0.75, randf_range(-30.0, -6.0)),
			"life": randf_range(0.26, 0.38), "max": 0.38,
			"color": _accessible_color(VFX.SLATE), "size": randf_range(8.0, 22.0)
		})

func _add_ring(pos: Vector2, color: Color, radius_from: float, radius_to: float, life: float, width: float) -> void:
	var effect_color := _accessible_color(color)
	if flash_reduced:
		effect_color.a = minf(effect_color.a, 0.22)
	_push_particle({
		"kind": "ring", "pos": pos, "vel": Vector2.ZERO, "life": life, "max": life,
		"color": effect_color, "size": width, "radius_from": radius_from, "radius_to": radius_to
	})

func _accessible_color(color: Color) -> Color:
	var out := color
	if flash_reduced:
		out = out.lerp(Color(0.55, 0.52, 0.58, out.a), 0.35)
		out.a = minf(out.a, 0.48)
	return out

func _push_particle(particle: Dictionary) -> void:
	if _particles.size() < MAX_PARTICLES:
		_particles.append(particle)

func _process(delta: float) -> void:
	if _sfx_thread != null:
		_collect_sfx()
	# Trauma drains on game time, so a freeze holds the shake it started.
	if _trauma_hold > 0.0:
		_trauma_hold -= delta
	else:
		_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
	camera.offset = _camera_offset()
	# Particles
	var i := 0
	while i < _particles.size():
		var p: Dictionary = _particles[i]
		var kind := String(p.get("kind", "spark"))
		p.pos += p.vel * delta
		var motion: Array = MOTION.get(kind, SPARK_MOTION)
		p.vel *= maxf(0.0, 1.0 - float(motion[0]) * delta)
		p.vel.y += float(motion[1]) * delta
		if kind == "shard":
			p.rot = float(p.get("rot", 0.0)) + float(p.get("angvel", 0.0)) * delta
		elif kind == "ember":
			p.pos.x += sin(float(p.get("life", 0.0)) * 20.0) * 12.0 * delta
		p.life -= delta
		if p.life <= 0.0:
			_particles.remove_at(i)
		else:
			i += 1
	queue_redraw()
	if _glow != null:
		_glow.queue_redraw()

func _draw() -> void:
	for p in _particles:
		var life: float = float(p.get("life", 0.0))
		var maximum: float = maxf(float(p.get("max", 0.001)), 0.001)
		var a := clampf(life / maximum, 0.0, 1.0)
		var c: Color = p.get("color", Color.WHITE)
		c.a *= a * (0.55 if flash_reduced else 1.0)
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		var size := float(p.get("size", 3.0))
		match String(p.get("kind", "spark")):
			"riposte":
				var face := float(p.facing)
				var reach := float(p.radius)
				var blade := PackedVector2Array([
					pos + Vector2(face * 12.0, 0.0), pos + Vector2(face * reach * 0.64, -8.0 * a),
					pos + Vector2(face * reach, 0.0), pos + Vector2(face * reach * 0.64, 8.0 * a),
				])
				draw_colored_polygon(blade, Color(c, c.a * 0.32))
				draw_polyline(blade, c, 1.5, true)
				draw_line(pos + Vector2(face * 20.0, 0.0), pos + Vector2(face * reach, 0.0), Color(VFX.HOT, c.a), 2.0, true)
				for side in [-1.0, 1.0]:
					draw_line(pos + Vector2(face * reach * 0.85, side * 14.0 * a), pos + Vector2(face * reach, 0.0), c, 1.5, true)
			"streak":
				var vel: Vector2 = p.get("vel", Vector2.RIGHT)
				var tail := vel.normalized() * float(p.get("length", 18.0)) * a
				draw_line(pos, pos - tail, c, maxf(1.0, size * a), true)
			"ring", "parry_ring", "slash", "flash", "cut":
				pass  # drawn on the additive glow layer
			"hitspark":
				var vel: Vector2 = p.get("vel", Vector2.RIGHT)
				var age := 1.0 - a
				var base: Color = p.get("color", VFX.GOLD)
				var ramp := Color.WHITE.lerp(base, minf(age * 2.0, 1.0)) if age < 0.5 else base.lerp(VFX.EMBER, (age - 0.5) * 2.0)
				ramp.a = c.a
				var tail := vel.normalized() * float(p.get("length", 10.0)) * (0.4 + 0.6 * a)
				draw_line(pos, pos - tail, ramp, 2.0, true)
			"puff":
				var grow := 0.45 + 0.55 * (1.0 - a)
				var pc := c.lerp(VFX.MORTAR, 1.0 - a)
				pc.a = c.a * 0.55
				VFX.draw_ellipse(self, pos, size * grow, size * grow * 0.45, pc)
			"ground_ring":
				var progress := 1.0 - a
				var eased := 1.0 - (1.0 - progress) * (1.0 - progress)
				var radius := lerpf(float(p.get("radius_from", 8.0)), float(p.get("radius_to", 190.0)), eased)
				var rc := c.lerp(VFX.MORTAR, progress)
				rc.a = c.a * 0.55
				VFX.draw_ellipse_ring(self, pos, radius, radius * 0.19, rc, maxf(1.0, size * a))
			"shard":
				var shape: PackedVector2Array = p.get("shape", PackedVector2Array())
				if shape.size() >= 3:
					draw_set_transform(pos, float(p.get("rot", 0.0)), Vector2.ONE)
					draw_colored_polygon(shape, Color(VFX.VOID, c.a))
					var outline := shape.duplicate()
					outline.append(shape[0])
					draw_polyline(outline, c, 1.5, true)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"afterimage":
				KnightArt.paint(self, pos, p.pose, float(p.facing), {"flat": c})
			"number":
				var font := ThemeDB.fallback_font
				var txt := str(p.get("text", ""))
				# Pop in over the first 20% of life, hold, then fade over the last 40%.
				var age := 1.0 - a
				var pop := 1.0 + 0.4 * (1.0 - clampf(age / 0.2, 0.0, 1.0))
				var alpha := clampf(a / 0.4, 0.0, 1.0) * (0.55 if flash_reduced else 1.0)
				var fs := maxi(8, int(size * pop))
				var width := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
				var at := pos + Vector2(-width * 0.5, 0.0)
				var base: Color = p.get("color", VFX.GOLD)
				draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.0, 0.0, 0.0, alpha * 0.85))
				draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(base.r, base.g, base.b, alpha))
			_:
				draw_circle(pos, maxf(0.8, size * a), c)

## Additive pass: rings, the parry halo, slash afterglow and death/blast flashes.
func _draw_glow() -> void:
	for p in _particles:
		var kind := String(p.get("kind", "spark"))
		if kind not in ["ring", "parry_ring", "slash", "flash", "cut"]:
			continue
		var a := clampf(float(p.get("life", 0.0)) / maxf(float(p.get("max", 0.001)), 0.001), 0.0, 1.0)
		var c: Color = p.get("color", Color.WHITE)
		c.a *= a * (0.55 if flash_reduced else 1.0)
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		var size := float(p.get("size", 3.0))
		match kind:
			"ring":
				var progress := 1.0 - a
				var radius := lerpf(float(p.get("radius_from", 4.0)), float(p.get("radius_to", 28.0)), progress)
				_glow.draw_arc(pos, radius, 0.0, TAU, 28, c, maxf(1.0, size * a), true)
			"parry_ring":
				var progress := 1.0 - a
				var radius := lerpf(float(p.get("radius_from", 8.0)), float(p.get("radius_to", 140.0)), progress)
				var width := lerpf(3.0, 1.0, progress)
				var outer := c.lerp(VFX.GOLD, progress)
				outer.a = c.a
				_glow.draw_arc(pos, radius, 0.0, TAU, 48, outer, width, true)
				_glow.draw_arc(pos, radius * 0.72, 0.0, TAU, 40, Color(VFX.GOLD, c.a * 0.7), width + 0.5, true)
				_glow.draw_circle(pos, radius * 0.5, Color(VFX.TEAL, c.a * 0.12))
			"slash":
				var progress := 1.0 - a
				var a0 := float(p.get("a0", -1.0))
				var a1 := float(p.get("a1", 1.0))
				# The glow's tail catches up with its head as it fades.
				var tail := lerpf(a0, a1, clampf(progress * 0.8, 0.0, 0.85))
				_glow.draw_set_transform(pos, 0.0, Vector2(float(p.get("facing", 1.0)), 1.0))
				KnightArt.arc_smear(_glow, Vector2.ZERO, float(p.get("radius", 48.0)), tail, a1, size, 0.55 * c.a)
				_glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"flash":
				_glow.draw_circle(pos, size, Color(c.r, c.g, c.b, c.a * 0.8))
			"cut":
				# Full strength while hot, then cooling and fading together.
				var base: Color = p.color
				var cool := clampf((CUT_LIFE - float(p.life) - CUT_HOT) / (CUT_LIFE - CUT_HOT), 0.0, 1.0)
				var col := base.lerp(VFX.EMBER, cool)
				col.a = base.a * (1.0 - cool) * (0.55 if flash_reduced else 1.0)
				var along := Vector2.from_angle(float(p.angle)) * size * 0.5
				var across := along.orthogonal().normalized() * 2.5
				_glow.draw_colored_polygon(PackedVector2Array([pos - along, pos + across, pos + along, pos - across]), col)

func set_reduced_motion(v: bool) -> void:
	motion_reduced = v
	if v:
		_trauma = 0.0
		_kick_at = -1.0
		camera.offset = Vector2.ZERO
		if _zoom_tween != null and _zoom_tween.is_valid():
			_zoom_tween.kill()
			camera.zoom = _zoom_rest
		_particles.clear()
		_restore_hit_stop()
		end_slow_motion()
	if _glow != null:
		_glow.queue_redraw()

func set_reduced_flash(v: bool) -> void:
	flash_reduced = v
	queue_redraw()
	if _glow != null:
		_glow.queue_redraw()
