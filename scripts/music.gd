extends Node
## Procedural score in D minor, written as notes and synthesized from nothing
## but oscillators and noise:
##   title   "Threshold"    -- a slow harp and choir over the drop; after the
##                            first victory it plays at dawn (title_dawn), its
##                            question answered in D major
##   explore "The Descent"  -- harp ostinato, choir, a heartbeat drum; the bells
##                            take the melody in its second half; a combat layer
##                            (explore_hot) rides in lockstep and rises with waves
##   boss    "Ember Warden" -- 132 bpm; a second layer (boss_hot) is rendered in
##                            lockstep and faded in when the Warden ignites
##   curtain_* "Strike the Set" -- the ending's cues, one-shots and one loop that
##                            the finale overlaps on its own clock
## Every note shape is synthesized once and mixed into a stereo buffer. A loop's
## buffer is circular, so its ringing tails wrap into its own head and the loop
## is seamless; a one-shot's buffer holds its whole tail instead.
## Rendered on worker threads and cached under user:// after the first launch.

const RATE := 16000
## Bump when the score changes so stale caches are re-rendered.
const VERSION := 2
const CACHE_DIR := "user://audio_cache"
const FADE_TIME := 1.4

## Track name -> target volume in dB while active.
const LEVELS := {
	"title": -10.0, "title_dawn": -10.0, "explore": -12.0, "explore_hot": -12.0,
	"boss": -9.0, "boss_hot": -9.0,
}
## Rendered in parallel at boot; is_ready() waits for exactly these.
const TRACKS := ["title", "explore", "boss", "boss_hot"]
## A base track's second layer. It starts with its base, sits at silence until
## set_intensity() raises it, and never stops while the base plays, so the two
## stay locked together.
const LAYERS := { "explore": "explore_hot", "boss": "boss_hot" }
## The ending's cues, on players of their own so one cue's tail can ring under
## the next cue's head.
const CUES := ["curtain_a", "curtain_hold", "curtain_b1", "curtain_b2"]
const CUE_LEVELS := { "curtain_a": -11.0, "curtain_hold": -12.0, "curtain_b1": -9.0, "curtain_b2": -10.0 }
const CUE_LOOP := ["curtain_hold"]
## The score's low-pass: wide open, at the lowest flame, and behind a panel
## that holds a run (pause, reward).
const OPEN_HZ := 20000.0
const LOW_FLAME_HZ := 2200.0
const HELD_HZ := 1100.0
## Feedback routes stinger cues here; the score's compressor listens to it, so
## a gong or a roar pushes the music back for a breath.
const STINGER_BUS := "Stinger"

var enabled := true
var _players: Dictionary = {}
var _threads: Dictionary = {}
var _tracks_ready := false
var _current := ""
var _tweens: Dictionary = {}
var _intensity := 0.0
## Pieces that must never delay the tracks (the combat layer, the ending's cues,
## the dawn title once earned), rendered one at a time after the tracks.
var _late_queue: Array = []
## 0..1: how far the knight's flame has guttered.
var _muffle := 0.0
var _filter: AudioEffectLowPassFilter

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in LEVELS.keys() + CUES:
		var p := AudioStreamPlayer.new()
		p.name = str(name).capitalize().replace(" ", "")
		# Routed to the Music bus so the options mix owns the score's level;
		# track-to-track balance stays on the player's own volume_db.
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players[name] = p
	for name in TRACKS:
		var p: AudioStreamPlayer = _players[name]
		p.stream = _load_cached(name)
		if p.stream == null:
			_start_render(name)
	for name in ["explore_hot"] + CUES:
		_queue_late(name)
	_check_ready()
	_dress_bus()

func _exit_tree() -> void:
	# A render cut short by quitting is still banked, so the next boot carries
	# on down the queue instead of starting it over.
	for name in _threads:
		var th: Thread = _threads[name]
		if th.is_started():
			_save_cached(name, _make_stream(th.wait_to_finish(), _loops(name)))
	_threads.clear()
	if _filter != null:
		_filter.cutoff_hz = OPEN_HZ

func is_ready() -> bool:
	return _tracks_ready

func _process(delta: float) -> void:
	for name in _threads.keys():
		var th: Thread = _threads[name]
		if not th.is_alive():
			_threads.erase(name)
			_install(name, th.wait_to_finish())
	_check_ready()
	if _tracks_ready and _threads.is_empty() and not _late_queue.is_empty():
		_start_render(_late_queue.pop_front())
	_steer_filter(delta)

func _start_render(name: String) -> void:
	var th := Thread.new()
	th.start(_render_track.bind(name))
	_threads[name] = th

## Load a late piece from the cache, or queue its render behind the others.
func _queue_late(name: String) -> void:
	var p: AudioStreamPlayer = _players[name]
	if p.stream != null or _late_queue.has(name) or _threads.has(name):
		return
	p.stream = _load_cached(name)
	if p.stream == null:
		_late_queue.append(name)

## Hand a finished render to its player and the cache. A track asked for before
## it existed starts the moment it lands.
func _install(name: String, pcm: PackedByteArray) -> void:
	var stream := _make_stream(pcm, _loops(name))
	(_players[name] as AudioStreamPlayer).stream = stream
	_save_cached(name, stream)
	if _current != "" and (name == _voice_of(_current) or name == LAYERS.get(_current, "")):
		play_track(_current)

func _check_ready() -> void:
	if _tracks_ready:
		return
	for name in TRACKS:
		if (_players[name] as AudioStreamPlayer).stream == null:
			return
	_tracks_ready = true

## Switch tracks: "title", "explore", "boss", or "" for silence. `fade` is in
## real seconds; 0 is a hard entrance on the downbeat.
func play_track(track: String, fade: float = FADE_TIME) -> void:
	if track != _current:
		# A new scene never inherits the low-flame filter of the last one.
		_muffle = 0.0
	_current = track
	if Save.get_victories() > 0:
		_queue_late("title_dawn")
	var voice := _voice_of(track)
	var layer: String = LAYERS.get(track, "")
	for name in LEVELS:
		var p: AudioStreamPlayer = _players[name]
		if not enabled or p.stream == null or (name != voice and name != layer):
			_fade(p, -80.0, fade)
			continue
		if not p.playing:
			p.play(_partner_position(name))
		var target := float(LEVELS[name])
		if name == layer:
			target = lerpf(-60.0, target, _intensity) if _intensity > 0.0 else -80.0
		_fade(p, target, fade, name == layer)

## The player that voices `track`: once the keep has fallen, the title plays at
## dawn, with the old title standing in until that render lands.
func _voice_of(track: String) -> String:
	var dawn: AudioStreamPlayer = _players["title_dawn"]
	if track == "title" and dawn.stream != null and Save.get_victories() > 0:
		return "title_dawn"
	return track

## A layer joining its base mid-loop (or a base rejoining its layer) starts at
## the partner's position; started together, both start at zero.
func _partner_position(name: String) -> float:
	var partner = LAYERS.get(name, LAYERS.find_key(name))
	if partner != null and (_players[partner] as AudioStreamPlayer).playing:
		return (_players[partner] as AudioStreamPlayer).get_playback_position()
	return 0.0

## 0..1: how far a track's second layer is up (a wave in progress, the Warden
## ignited), faded over `fade` real seconds. It belongs to the moment, not the
## track: a run's first wave is called before its track starts, and a cleared
## chamber hands the throne a silent layer.
func set_intensity(value: float, fade: float = FADE_TIME) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	if LAYERS.has(_current):
		play_track(_current, fade)

func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		stop_cues()
	play_track(_current)

## Silence everything at once (the killing blow): tracks and cues alike.
func cut(fade: float = 0.15) -> void:
	play_track("", fade)
	stop_cues(fade)

## 0..1: how far the knight's flame has guttered; the score closes in with it.
func set_muffle(amount: float) -> void:
	_muffle = clampf(amount, 0.0, 1.0)

## True when a cue can sound right now; without it the finale falls back to
## effects and keeps its timing.
func has_cue(name: String) -> bool:
	return enabled and CUES.has(name) and (_players[name] as AudioStreamPlayer).stream != null

## Start a cue at its level from `from` seconds. Other cues keep playing: the
## finale overlaps one cue's tail with the next one's head.
func play_cue(name: String, from: float = 0.0) -> void:
	if not has_cue(name):
		return
	var p: AudioStreamPlayer = _players[name]
	_fade(p, float(CUE_LEVELS[name]), 0.0)
	p.play(from)

func stop_cue(name: String, fade: float = 0.3) -> void:
	if CUES.has(name):
		_fade(_players[name], -80.0, fade)

func stop_cues(fade: float = 0.3) -> void:
	for name in CUES:
		stop_cue(name, fade)

## Tween a player's level over `time` real seconds: Engine.time_scale is low
## through the beats and hit-stops, and a fade must not stretch with it.
## Reaching silence stops the player, unless `hold` keeps a layer running in
## step with its base.
func _fade(p: AudioStreamPlayer, target_db: float, time: float = FADE_TIME, hold := false) -> void:
	if _tweens.has(p) and is_instance_valid(_tweens[p]):
		(_tweens[p] as Tween).kill()
	var silent := target_db <= -79.0
	if time <= 0.0 or (silent and not p.playing):
		p.volume_db = target_db
		if silent and not hold:
			p.stop()
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_ignore_time_scale(true)
	tween.tween_property(p, "volume_db", target_db, time)
	if silent and not hold:
		tween.tween_callback(p.stop)
	_tweens[p] = tween

# --- The score's bus ------------------------------------------------------------

## The score's inserts: a low-pass that closes as the flame gutters or while a
## panel holds the run, and a compressor keyed from the Stinger bus. Buses
## outlive any one game, so a later boot finds what an earlier one added.
func _dress_bus() -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		return
	if AudioServer.get_bus_index(STINGER_BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, STINGER_BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "SFX")
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			_filter = AudioServer.get_bus_effect(bus, i)
			return
	_filter = AudioEffectLowPassFilter.new()
	_filter.cutoff_hz = OPEN_HZ
	AudioServer.add_bus_effect(bus, _filter)
	var duck := AudioEffectCompressor.new()
	duck.threshold = -18.0
	duck.ratio = 2.0
	duck.attack_us = 5000.0
	duck.release_ms = 400.0
	duck.sidechain = STINGER_BUS
	AudioServer.add_bus_effect(bus, duck)

## Glide the low-pass to where it belongs over about a quarter second of real
## time, in log frequency so the close-in sounds even.
func _steer_filter(delta: float) -> void:
	if _filter == null:
		return
	var target := OPEN_HZ * pow(LOW_FLAME_HZ / OPEN_HZ, _muffle)
	if get_tree().paused and LAYERS.has(_current):
		target = HELD_HZ
	var real_dt := delta / maxf(Engine.time_scale, 0.001)
	var k := 1.0 - exp(-real_dt / 0.08)
	_filter.cutoff_hz = exp(lerpf(log(_filter.cutoff_hz), log(target), k))

# --- Cache ---------------------------------------------------------------------

static func _cache_path(name: String) -> String:
	return CACHE_DIR.path_join("music_v%d_%d_%s.res" % [VERSION, RATE, name])

static func _load_cached(name: String) -> AudioStreamWAV:
	var path := _cache_path(name)
	if not FileAccess.file_exists(path):
		return null
	var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return res as AudioStreamWAV

static func _save_cached(name: String, stream: AudioStreamWAV) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	ResourceSaver.save(stream, _cache_path(name))

static func _make_stream(pcm: PackedByteArray, loop: bool = true) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = true
	stream.data = pcm
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = pcm.size() / 4
	return stream

## Tracks loop; cues play once, except the hold under the gathering.
static func _loops(name: String) -> bool:
	return CUE_LOOP.has(name) or not CUES.has(name)

# --- Pitch ---------------------------------------------------------------------

## MIDI note to Hz.
static func hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

# Note names used by the score (MIDI numbers).
const D2 := 38
const F2 := 41
const G2 := 43
const A2 := 45
const Bb2 := 46
const B2 := 47
const C3 := 48
const D3 := 50
const E3 := 52
const F3 := 53
const Fs3 := 54
const G3 := 55
const A3 := 57
const B3 := 59
const C4 := 60
const Cs4 := 61
const D4 := 62
const E4 := 64
const F4 := 65
const Fs4 := 66
const G4 := 67
const A4 := 69
const Bb4 := 70
const B4 := 71
const C5 := 72
const Cs5 := 73
const D5 := 74
const E5 := 76
const F5 := 77
const Fs5 := 78
const G5 := 79
const A5 := 81
const Bb5 := 82
const D6 := 86
const Eb3 := 51

# --- Mixing --------------------------------------------------------------------

## A stereo mix buffer plus a cache of rendered note shapes. A loop's buffer is
## circular; a one-shot's (`wrap` false) drops whatever would run off its end.
class Mix:
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	var n := 0
	var rate := 16000
	var wrap := true
	var shapes: Dictionary = {}

	func _init(seconds: float, p_rate: int, p_wrap: bool = true) -> void:
		rate = p_rate
		wrap = p_wrap
		n = int(seconds * rate)
		l.resize(n)
		r.resize(n)

	## Add a mono shape at `t` seconds with equal-power `pan` (-1..1). `haas`
	## delays one side by a few milliseconds for width.
	func put(shape: PackedFloat32Array, t: float, gain: float, pan: float = 0.0, haas: float = 0.0) -> void:
		var a := (clampf(pan, -1.0, 1.0) + 1.0) * PI * 0.25
		var gl := cos(a) * gain * 1.414
		var gr := sin(a) * gain * 1.414
		var j := int(t * rate)
		var jr := j + int(haas * rate)
		var count := shape.size()
		if wrap:
			j = posmod(j, n)
			jr = posmod(jr, n)
		else:
			count = clampi(n - jr, 0, count)
		for i in range(count):
			var v := shape[i]
			l[j] += v * gl
			r[jr] += v * gr
			j += 1
			if j >= n: j = 0
			jr += 1
			if jr >= n: jr = 0

	## Soft-clip both channels and interleave to 16-bit stereo PCM.
	func finish(gain: float) -> PackedByteArray:
		var peak := 0.0001
		for i in range(n):
			peak = maxf(peak, maxf(absf(l[i]), absf(r[i])))
		var k := gain / peak
		var out := PackedByteArray()
		out.resize(n * 4)
		for i in range(n):
			out.encode_s16(i * 4, int(clampf(tanh(l[i] * k * 1.2) / tanh(1.2), -1.0, 1.0) * 30000.0))
			out.encode_s16(i * 4 + 2, int(clampf(tanh(r[i] * k * 1.2) / tanh(1.2), -1.0, 1.0) * 30000.0))
		return out

# --- Voices (each returns a mono note shape, cached per pitch and length) ------

## Plucked harp: harmonic partials, the upper ones dying first, and a breath of
## string noise on the attack.
static func harp(mx: Mix, m: float, dur: float, bright: float = 1.0) -> PackedFloat32Array:
	var key := "harp:%s:%s:%s" % [m, dur, bright]
	if mx.shapes.has(key):
		return mx.shapes[key]
	var f := hz(m)
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(m * 131.0)
	for k in range(1, 7):
		var fk := f * float(k) * (1.0 + 0.0008 * float(k * k))
		if fk > RATE * 0.45:
			break
		var amp := pow(0.62, float(k - 1)) * (bright if k > 2 else 1.0)
		var tau := 1.4 / (1.0 + 0.9 * float(k - 1))
		var w := TAU * fk / RATE
		for i in range(n):
			var t := float(i) / RATE
			s[i] += sin(w * float(i)) * amp * exp(-t / tau) * minf(1.0, t / 0.003)
	var lp := 0.0
	for i in range(mini(n, int(0.02 * RATE))):
		lp = lerpf(lp, rng.randf() * 2.0 - 1.0, 0.35)
		s[i] += lp * 0.25 * exp(-float(i) / (0.004 * RATE))
	mx.shapes[key] = s
	return s

## Struck bell: inharmonic partials, long bloom.
static func bell(mx: Mix, m: float, dur: float) -> PackedFloat32Array:
	var key := "bell:%s:%s" % [m, dur]
	if mx.shapes.has(key):
		return mx.shapes[key]
	var f := hz(m)
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var parts := [[1.0, 1.0, 1.0], [2.0, 0.55, 0.7], [2.76, 0.35, 0.45], [4.07, 0.22, 0.3], [5.4, 0.12, 0.2], [0.5, 0.25, 1.2]]
	for p in parts:
		var fk := f * float(p[0])
		if fk > RATE * 0.45:
			continue
		var w := TAU * fk / RATE
		var tau := dur * 0.45 * float(p[2])
		for i in range(n):
			var t := float(i) / RATE
			s[i] += sin(w * float(i)) * float(p[1]) * exp(-t / tau) * minf(1.0, t / 0.002)
	mx.shapes[key] = s
	return s

## Low pizzicato bass: round fundamental, a little second harmonic.
static func bass(mx: Mix, m: float, dur: float) -> PackedFloat32Array:
	var key := "bass:%s:%s" % [m, dur]
	if mx.shapes.has(key):
		return mx.shapes[key]
	var f := hz(m)
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var w := TAU * f / RATE
	for i in range(n):
		var t := float(i) / RATE
		var e := exp(-t / (dur * 0.35)) * minf(1.0, t / 0.006)
		s[i] = (sin(w * float(i)) + 0.35 * sin(2.0 * w * float(i)) + 0.12 * sin(3.0 * w * float(i))) * e
	mx.shapes[key] = s
	return s

## Choir: detuned saw pairs per chord note through two vowel formants ("ah"),
## with a slow swell in and out.
static func choir(mx: Mix, notes: Array, dur: float, vowel: float = 0.0) -> PackedFloat32Array:
	var key := "choir:%s:%s:%s" % [str(notes), dur, vowel]
	if mx.shapes.has(key):
		return mx.shapes[key]
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phases := PackedFloat32Array()
	var incs := PackedFloat32Array()
	for m in notes:
		for d in [-0.07, 0.07]:
			phases.append(randf_seeded(int(m) * 7 + int(d * 100.0)))
			incs.append(hz(float(m) + d) / RATE)
	var voices := phases.size()
	# Two formant band-passes (ZDF SVF) and a gentle low-pass.
	var f1 := lerpf(700.0, 400.0, vowel)
	var f2 := lerpf(1150.0, 800.0, vowel)
	var g1 := tan(PI * f1 / RATE)
	var g2 := tan(PI * f2 / RATE)
	var k := 1.0 / 4.0
	var a11 := 1.0 / (1.0 + g1 * (g1 + k))
	var a12 := g1 * a11
	var a13 := g1 * a12
	var a21 := 1.0 / (1.0 + g2 * (g2 + k))
	var a22 := g2 * a21
	var a23 := g2 * a22
	var s11 := 0.0
	var s12 := 0.0
	var s21 := 0.0
	var s22 := 0.0
	var lp := 0.0
	var att := minf(1.2, dur * 0.35)
	var rel := minf(1.4, dur * 0.4)
	for i in range(n):
		var x := 0.0
		for v in range(voices):
			var ph := phases[v] + incs[v]
			ph -= floorf(ph)
			phases[v] = ph
			x += 2.0 * ph - 1.0
		x /= float(voices)
		var v3 := x - s12
		var v1 := a11 * s11 + a12 * v3
		var v2 := s12 + a12 * s11 + a13 * v3
		s11 = 2.0 * v1 - s11
		s12 = 2.0 * v2 - s12
		var w3 := x - s22
		var w1 := a21 * s21 + a22 * w3
		var w2 := s22 + a22 * s21 + a23 * w3
		s21 = 2.0 * w1 - s21
		s22 = 2.0 * w2 - s22
		lp += 0.08 * (x - lp)
		var t := float(i) / RATE
		var env := minf(1.0, t / att) * minf(1.0, (dur - t) / rel)
		env = env * env * (3.0 - 2.0 * env)
		s[i] = (v1 * 1.0 + w1 * 0.7 + lp * 0.5) * env
	mx.shapes[key] = s
	return s

## Brass-like stab: a saw stack whose low-pass opens then closes.
static func brass(mx: Mix, notes: Array, dur: float) -> PackedFloat32Array:
	var key := "brass:%s:%s" % [str(notes), dur]
	if mx.shapes.has(key):
		return mx.shapes[key]
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phases := PackedFloat32Array()
	var incs := PackedFloat32Array()
	for m in notes:
		for d in [-0.05, 0.05]:
			phases.append(randf_seeded(int(m) * 13))
			incs.append(hz(float(m) + d) / RATE)
	var lp := 0.0
	var lp2 := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var x := 0.0
		for v in range(phases.size()):
			var ph := phases[v] + incs[v]
			ph -= floorf(ph)
			phases[v] = ph
			x += 2.0 * ph - 1.0
		x /= float(phases.size())
		var cut := 0.03 + 0.25 * exp(-t / 0.12)
		lp += cut * (x - lp)
		lp2 += cut * (lp - lp2)
		var env := minf(1.0, t / 0.015) * exp(-t / (dur * 0.5))
		s[i] = lp2 * env
	mx.shapes[key] = s
	return s

## Percussion: kick, taiko, snare, hat, frame drum.
static func drum(mx: Mix, kind: String) -> PackedFloat32Array:
	var key := "drum:" + kind
	if mx.shapes.has(key):
		return mx.shapes[key]
	var dur := {"kick": 0.35, "taiko": 0.7, "snare": 0.25, "hat": 0.06, "frame": 0.5, "tom": 0.45}.get(kind, 0.3) as float
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var ph := 0.0
	var lp := 0.0
	var hp_prev := 0.0
	var hp := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var noise := rng.randf() * 2.0 - 1.0
		var v := 0.0
		match kind:
			"kick":
				ph += TAU * lerpf(130.0, 45.0, minf(1.0, t / 0.08)) / RATE
				v = sin(ph) * exp(-t / 0.11) + noise * 0.1 * exp(-t / 0.004)
			"taiko":
				ph += TAU * lerpf(110.0, 62.0, minf(1.0, t / 0.12)) / RATE
				lp += 0.1 * (noise - lp)
				v = sin(ph) * exp(-t / 0.22) * 0.9 + lp * 0.9 * exp(-t / 0.08)
			"tom":
				ph += TAU * lerpf(180.0, 95.0, minf(1.0, t / 0.1)) / RATE
				v = sin(ph) * exp(-t / 0.16)
			"frame":
				ph += TAU * lerpf(95.0, 70.0, minf(1.0, t / 0.1)) / RATE
				lp += 0.2 * (noise - lp)
				v = sin(ph) * exp(-t / 0.15) * 0.8 + lp * 0.35 * exp(-t / 0.03)
			"snare":
				lp += 0.45 * (noise - lp)
				ph += TAU * 190.0 / RATE
				v = lp * exp(-t / 0.07) + sin(ph) * 0.4 * exp(-t / 0.04)
			"hat":
				hp = 0.6 * (hp + noise - hp_prev)
				hp_prev = noise
				v = hp * exp(-t / 0.015)
		s[i] = v
	mx.shapes[key] = s
	return s

## Low filtered wind across the whole loop (faded at both ends so the loop is
## seamless), or across the first `seconds` of a one-shot, clear of its tail.
static func wind(mx: Mix, gain: float, seconds: float = 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	var lp := 0.0
	var lp2 := 0.0
	var count := int(seconds * RATE) if seconds > 0.0 else mx.n
	var span := float(count) / RATE
	for i in range(count):
		lp += 0.02 * (rng.randf() * 2.0 - 1.0 - lp)
		lp2 += 0.05 * (lp - lp2)
		var t := float(i) / RATE
		var gust := 0.55 + 0.45 * sin(TAU * t / span * 3.0 + 1.0)
		var edge := minf(1.0, minf(t, span - t) / 0.8)
		var v := lp2 * gain * gust * edge
		mx.l[i] += v
		mx.r[posmod(i + 211, mx.n)] += v * 0.9

static func randf_seeded(seed_val: int) -> float:
	var x := sin(float(seed_val) * 12.9898) * 43758.5453
	return x - floor(x)

# --- The score -------------------------------------------------------------------

static func _render_track(name: String) -> PackedByteArray:
	match name:
		"title": return _score_title(false)
		"title_dawn": return _score_title(true)
		"explore": return _score_explore(false)
		"explore_hot": return _score_explore(true)
		"boss": return _score_boss(false)
		"boss_hot": return _score_boss(true)
		"curtain_a": return _score_curtain_a()
		"curtain_hold": return _score_curtain_hold()
		"curtain_b1": return _score_curtain_b1()
		"curtain_b2": return _score_curtain_b2()
	return PackedByteArray()

## Chord tones (MIDI) for the score's harmony, voiced around middle C. The
## major chords after "A7" belong to the ending and the title at dawn.
const CHORDS := {
	"Dm": [D3, F3, A3], "Bb": [Bb2, D3, F3], "Gm": [G2, Bb2, D3], "A": [A2, Cs4 - 12, E3],
	"F": [F2, A2, C3], "C": [C3, E3, G3], "Eb": [Eb3 - 12, G2, Bb2], "A7": [A2, Cs4 - 12, G3],
	"D": [D3, Fs3, A3], "G": [G2, B2, D3], "Bm": [B2, D3, Fs3], "Em": [E3, G3, B3],
}

## Rolling harp arpeggio over a chord for one bar of eighths.
static func _arp(mx: Mix, chord: Array, t0: float, beat: float, lift: int, gain: float, pattern: Array) -> void:
	var tones := []
	for oct in [12, 24, 36]:
		for m in chord:
			tones.append(int(m) + oct)
	for i in range(pattern.size()):
		var idx: int = pattern[i]
		if idx < 0:
			continue
		var m: int = tones[clampi(idx, 0, tones.size() - 1)] + lift
		var pan := sin(float(i) * 0.9) * 0.45
		mx.put(harp(mx, m, 1.6, 0.9), t0 + float(i) * beat * 0.5, gain * (1.0 if i % 4 == 0 else 0.78), pan, 0.004)

## "Threshold": 72 bpm, eight bars. A slow harp over a choir; a lone bell line.
## At dawn (after a victory) the last bars turn A7 to D major, the choir opens
## its vowel, and the bells' hanging C# rises to D before the loop falls back
## into the minor keep.
static func _score_title(dawn: bool) -> PackedByteArray:
	var beat := 60.0 / 72.0
	var bar := beat * 4.0
	var prog := ["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A"]
	if dawn:
		prog = ["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A7", "D"]
	var mx := Mix.new(bar * float(prog.size()), RATE)
	var up := [0, 1, 2, 3, 4, 3, 2, 1]
	var down := [5, 4, 2, 1, 3, 2, 1, 0]
	var vowel := 0.6 if dawn else 0.2
	for b in range(prog.size()):
		var t := float(b) * bar
		var ch: Array = CHORDS[prog[b]]
		var sunrise := dawn and b == prog.size() - 1
		_arp(mx, ch, t, beat, 12 if sunrise else 0, 0.24 if sunrise else 0.32, up if b % 2 == 0 else down)
		mx.put(bass(mx, int(ch[0]) - 12, bar * 0.9), t, 0.5, 0.0)
		var voiced := [int(ch[0]) + 12, int(ch[1]) + 12, int(ch[2]) + 12]
		if dawn and b >= prog.size() - 2:
			# A7 and D each get their own voices, not one A held across both.
			mx.put(choir(mx, voiced, bar * 1.15, vowel), t, 0.34, 0.0, 0.012)
		elif b % 2 == 0:
			mx.put(choir(mx, voiced, bar * 2.2, vowel), t, 0.34, 0.0, 0.012)
	# The bell line: a question in the first half, its answer leaning on C#.
	var melody := [[0, A4, 3.0], [4, D5, 2.0], [6, C5, 1.0], [7, A4, 1.0], [8, F4, 3.0], [12, Bb4, 2.0], [14, A4, 1.0], [15, G4, 1.0],
		[16, G4, 3.0], [19, Bb4, 1.0], [20, A4, 2.0], [22, G4, 1.0], [23, F4, 1.0], [24, E4, 4.0]]
	melody += [[27, Cs5, 1.0], [28, D5, 4.0]] if dawn else [[28, Cs5, 4.0]]
	for n in melody:
		mx.put(bell(mx, int(n[1]), 3.2), float(n[0]) * beat, 0.2, 0.25, 0.008)
	wind(mx, 0.2 if dawn else 0.35)
	return mx.finish(0.9)

## "The Descent": 84 bpm, sixteen bars. The harp never stops walking; the bells
## pick up the tune when the progression comes round the second time. The hot
## layer (a wave in progress) is taiko, a bass drive of roots, fifths and
## octaves, brass stabs and tom fills, with no harp or choir to crowd the tune.
static func _score_explore(hot: bool) -> PackedByteArray:
	var beat := 60.0 / 84.0
	var bar := beat * 4.0
	var prog := ["Dm", "Dm", "Bb", "Bb", "F", "F", "C", "C", "Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A"]
	var mx := Mix.new(bar * float(prog.size()), RATE)
	var pat_a := [0, 2, 4, 2, 3, 2, 4, 2]
	var pat_b := [3, 5, 4, 5, 6, 5, 4, 2]
	var drive := [0, 0, 12, 0, 7, 0, 12, 7]
	for b in range(prog.size()):
		var t := float(b) * bar
		var ch: Array = CHORDS[prog[b]]
		if hot:
			var root := int(ch[0])
			mx.put(drum(mx, "taiko"), t, 0.42, -0.15)
			mx.put(drum(mx, "taiko"), t + beat * 2.5, 0.3, 0.15)
			for i in range(8):
				mx.put(bass(mx, root - 12 + int(drive[i]), beat * 0.55), t + float(i) * beat * 0.5, 0.32 if i % 2 == 0 else 0.24, -0.05)
			var voiced := [root + 12, int(ch[1]) + 12, int(ch[2]) + 12]
			if b % 2 == 0:
				mx.put(brass(mx, voiced, beat * 1.2), t, 0.26, 0.0, 0.01)
			else:
				mx.put(brass(mx, voiced, beat * 0.6), t + beat * 2.5, 0.18, 0.0, 0.01)
			if b % 4 == 3:
				mx.put(drum(mx, "tom"), t + beat * 3.0, 0.3, -0.4)
				mx.put(drum(mx, "tom"), t + beat * 3.5, 0.3, 0.4)
			continue
		_arp(mx, ch, t, beat, 0, 0.27, pat_a if b < 8 else pat_b)
		mx.put(bass(mx, int(ch[0]) - 12, beat * 1.8), t, 0.55, -0.1)
		mx.put(bass(mx, int(ch[0]) - 12, beat * 1.8), t + beat * 2.5, 0.38, -0.1)
		if b % 2 == 0:
			mx.put(choir(mx, [int(ch[0]) + 12, int(ch[1]) + 12, int(ch[2]) + 12], bar * 2.15, 0.35 if b < 8 else 0.0), t, 0.26 if b < 8 else 0.34, 0.0, 0.014)
		# Heartbeat on the frame drum: da-dum, soft.
		mx.put(drum(mx, "frame"), t, 0.28, 0.1)
		mx.put(drum(mx, "frame"), t + beat * 0.5, 0.17, 0.1)
	if hot:
		return mx.finish(0.6)
	var melody := [[32, A4, 2.0], [34, D5, 1.0], [35, E5, 1.0], [36, F5, 3.0], [39, E5, 1.0], [40, D5, 2.0], [42, C5, 1.0], [43, Bb4, 1.0],
		[44, Bb4, 3.0], [47, A4, 1.0], [48, G4, 2.0], [50, Bb4, 1.0], [51, D5, 1.0], [52, D5, 2.0], [54, C5, 1.0], [55, Bb4, 1.0],
		[56, A4, 3.0], [59, G4, 1.0], [60, E4, 2.0], [62, Cs5, 2.0]]
	for n in melody:
		mx.put(bell(mx, int(n[1]), 2.6), float(n[0]) * beat, 0.19, -0.2, 0.009)
	wind(mx, 0.28)
	return mx.finish(0.9)

## "Ember Warden": 132 bpm, sixteen bars, D minor against a Neapolitan E-flat.
## The hot layer adds sixteenth hats, the ostinato an octave up, and tom fills.
static func _score_boss(hot: bool) -> PackedByteArray:
	var beat := 60.0 / 132.0
	var bar := beat * 4.0
	var prog := ["Dm", "Dm", "Bb", "A", "Dm", "Dm", "Eb", "A7", "Dm", "Dm", "Bb", "A", "Gm", "Eb", "A", "A7"]
	var mx := Mix.new(bar * float(prog.size()), RATE)
	var osti := [0, 0, 12, 0, 10, 0, 7, 0]
	for b in range(prog.size()):
		var t := float(b) * bar
		var ch: Array = CHORDS[prog[b]]
		var root := int(ch[0])
		if hot:
			for i in range(16):
				mx.put(drum(mx, "hat"), t + float(i) * beat * 0.25, 0.22 if i % 2 == 0 else 0.13, 0.35)
			for i in range(8):
				mx.put(harp(mx, root + 12 + int(osti[i]), 0.5, 1.2), t + float(i) * beat * 0.5, 0.2, -0.3)
			if b % 4 == 3:
				for i in range(4):
					mx.put(drum(mx, "tom"), t + beat * (2.0 + float(i) * 0.5), 0.45, lerpf(-0.5, 0.5, float(i) / 3.0))
			continue
		# Driving low ostinato in eighths.
		for i in range(8):
			mx.put(bass(mx, root - 12 + int(osti[i]), beat * 0.6), t + float(i) * beat * 0.5, 0.5 if i % 2 == 0 else 0.38, -0.05)
		# Kick every beat, taiko on the one and the and-of-three, snare on 2 and 4.
		for i in range(4):
			mx.put(drum(mx, "kick"), t + float(i) * beat, 0.55, 0.0)
		mx.put(drum(mx, "taiko"), t, 0.55, -0.15)
		mx.put(drum(mx, "taiko"), t + beat * 2.5, 0.4, 0.15)
		mx.put(drum(mx, "snare"), t + beat, 0.3, 0.1)
		mx.put(drum(mx, "snare"), t + beat * 3.0, 0.3, 0.1)
		# Brass on every chord change, a syncopated answer on the and-of-two.
		var voiced := [int(ch[0]) + 12, int(ch[1]) + 12, int(ch[2]) + 12]
		if b == 0 or prog[b] != prog[b - 1]:
			mx.put(brass(mx, voiced, beat * 1.6), t, 0.42, 0.0, 0.01)
		else:
			mx.put(brass(mx, voiced, beat * 0.8), t + beat * 1.5, 0.3, 0.0, 0.01)
		if b % 2 == 0:
			mx.put(choir(mx, [int(ch[0]) + 24, int(ch[1]) + 12, int(ch[2]) + 12], bar * 2.1, 0.0), t, 0.36, 0.0, 0.015)
	if not hot:
		# The bells' motif rubs the fifth against a flat sixth.
		var motif := [[16, A5, 1.5], [17.5, Bb5, 0.5], [18, A5, 2.0], [20, E5, 2.0], [22, F5, 1.0], [23, E5, 1.0],
			[48, A5, 1.5], [49.5, Bb5, 0.5], [50, A5, 2.0], [52, G5, 2.0], [54, F5, 1.0], [55, E5, 1.0]]
		for n in motif:
			mx.put(bell(mx, int(n[1]), 2.0), float(n[0]) * beat, 0.2, 0.3, 0.008)
	return mx.finish(0.92 if not hot else 0.6)

# --- The ending: "Strike the Set" ------------------------------------------------
# Everything stays D minor until the knight lets go; the thrust lands the score's
# first D major (a Picardy third), and the curtain call re-spells the title's
# bell line in that major, so its C# finally rises to D.

## "The Hoard": 66 bpm, three bars and a silent tail. The flames fall one by one
## down a D-minor harp line; the choir leaves an open fifth, unresolved.
static func _score_curtain_a() -> PackedByteArray:
	var beat := 60.0 / 66.0
	var bar := beat * 4.0
	var mx := Mix.new(bar * 3.0 + 3.0, RATE, false)
	for b in range(3):
		mx.put(bass(mx, D2, bar), float(b) * bar, 0.5, 0.0)
	mx.put(choir(mx, [D4, F4, A4], bar * 2.2, 0.0), 0.0, 0.3, 0.0, 0.012)
	mx.put(choir(mx, [A3, E4], bar * 1.6, 0.0), bar * 2.0, 0.3, 0.0, 0.012)
	var fall := [D5, C5, A4, F4, E4, D4, C4, A3]
	for i in range(fall.size()):
		mx.put(harp(mx, fall[i], 1.6, 0.9), bar + float(i) * beat, 0.3, sin(float(i) * 0.9) * 0.45, 0.004)
	wind(mx, 0.35, bar * 3.0)
	return mx.finish(0.9)

## The hold under the gathering: two looping bars of D and A in the bass, an
## open-fifth "oo" and the heartbeat, so every note of the question sits on it.
static func _score_curtain_hold() -> PackedByteArray:
	var beat := 60.0 / 66.0
	var bar := beat * 4.0
	var mx := Mix.new(bar * 2.0, RATE)
	for b in range(2):
		var t := float(b) * bar
		mx.put(bass(mx, D2, bar), t, 0.5, -0.05)
		mx.put(bass(mx, A2, bar), t, 0.32, 0.05)
		# Overlapping swells, one per bar, so the drone breathes but never gaps.
		mx.put(choir(mx, [D4, A4], bar * 2.2, 1.0), t, 0.26, 0.0, 0.012)
		mx.put(drum(mx, "frame"), t, 0.2, 0.1)
		mx.put(drum(mx, "frame"), t + beat * 0.5, 0.12, 0.1)
	wind(mx, 0.3)
	return mx.finish(0.9)

## "Strike the Set": 84 bpm, ten beats and a tail. The thrust lands on D major;
## the harp climbs D, G, B minor; cinders ring high; A7 leans into the call.
static func _score_curtain_b1() -> PackedByteArray:
	var beat := 60.0 / 84.0
	var mx := Mix.new(beat * 10.0 + 4.0, RATE, false)
	mx.put(brass(mx, [D3, Fs3, A3, D4], beat * 4.0), 0.0, 0.42, 0.0, 0.01)
	mx.put(drum(mx, "taiko"), 0.0, 0.55, -0.1)
	mx.put(bell(mx, D5, 3.2), 0.0, 0.22, 0.25, 0.008)
	mx.put(bass(mx, D2, beat * 4.0), 0.0, 0.55, 0.0)
	mx.put(choir(mx, [D4, Fs4, A4], beat * 8.0, 0.0), 0.0, 0.34, 0.0, 0.014)
	_arp(mx, CHORDS["D"], 0.0, beat, 0, 0.26, [0, 1, 2, 3, 4, 3, 4, 5])
	_arp(mx, CHORDS["G"], beat * 4.0, beat, 0, 0.26, [1, 2, 3, 4])
	_arp(mx, CHORDS["Bm"], beat * 6.0, beat, 0, 0.26, [2, 3, 4, 5])
	# Cinders: six high bells at seeded moments over the burn.
	var cinders := [Fs5, A5, D6]
	var rng := RandomNumberGenerator.new()
	rng.seed = 841
	for i in range(6):
		var at := rng.randf_range(0.3, beat * 9.0)
		mx.put(bell(mx, cinders[i % 3], 2.0), at, rng.randf_range(0.08, 0.12), rng.randf_range(-0.6, 0.6), 0.006)
	# The choir swell crests on the last beat, as the curtain call comes in.
	var a7: Array = CHORDS["A7"]
	mx.put(brass(mx, a7, beat * 2.0), beat * 8.0, 0.4, 0.0, 0.01)
	mx.put(choir(mx, [int(a7[0]) + 12, int(a7[1]) + 12, int(a7[2]) + 12], 2.4, 0.0), beat * 8.0, 0.45, 0.0, 0.014)
	return mx.finish(0.9)

## "Curtain Call": 84 bpm, eight bars and a downbeat. The title's bell line in
## D major (F to F#, Bb to B) over D D G G Em Em A A; on beat 32 its C# rises
## to D under a held D-major choir and a rolled harp.
static func _score_curtain_b2() -> PackedByteArray:
	var beat := 60.0 / 84.0
	var bar := beat * 4.0
	var prog := ["D", "D", "G", "G", "Em", "Em", "A", "A"]
	var mx := Mix.new(beat * 32.0 + 6.0, RATE, false)
	var up := [0, 1, 2, 3, 4, 3, 2, 1]
	var down := [5, 4, 2, 1, 3, 2, 1, 0]
	for b in range(prog.size()):
		var t := float(b) * bar
		var ch: Array = CHORDS[prog[b]]
		_arp(mx, ch, t, beat, 0, 0.26, up if b % 2 == 0 else down)
		mx.put(bass(mx, int(ch[0]) - 12, bar * 0.9), t, 0.5, 0.0)
		if b % 2 == 0:
			mx.put(choir(mx, [int(ch[0]) + 12, int(ch[1]) + 12, int(ch[2]) + 12], bar * 2.2, 0.2), t, 0.3, 0.0, 0.012)
		if b < 6:
			mx.put(drum(mx, "frame"), t, 0.2, 0.1)
			mx.put(drum(mx, "frame"), t + beat * 0.5, 0.12, 0.1)
	var melody := [[0, A4], [4, D5], [6, Cs5], [7, A4], [8, Fs4], [12, B4], [14, A4], [15, G4],
		[16, G4], [19, B4], [20, A4], [22, G4], [23, Fs4], [24, E4], [28, Cs5]]
	for n in melody:
		mx.put(bell(mx, int(n[1]), 3.2), float(n[0]) * beat, 0.2, 0.25, 0.008)
	var home := beat * 32.0
	mx.put(bell(mx, D5, 3.2), home, 0.24, 0.25, 0.008)
	mx.put(bell(mx, Fs5, 3.2), home, 0.16, -0.25, 0.008)
	# Held almost to the end of the tail, then silence for the house to settle.
	mx.put(choir(mx, [D4, Fs4, A4], 5.4, 0.2), home, 0.34, 0.0, 0.012)
	mx.put(bass(mx, D2, 4.0), home, 0.55, 0.0)
	var roll := [D3, Fs3, A3, D4, Fs4, A4, D5]
	for i in range(roll.size()):
		mx.put(harp(mx, roll[i], 2.4, 0.9), home + float(i) * 0.04, 0.26, lerpf(-0.4, 0.4, float(i) / 6.0), 0.004)
	return mx.finish(0.9)
