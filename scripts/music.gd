extends Node
## Procedural score. Three original pieces in D minor, written as notes and
## synthesized at boot from nothing but oscillators and noise:
##   title   "Threshold"    -- a slow harp and choir over the drop
##   explore "The Descent"  -- harp ostinato, choir, a heartbeat drum; the bells
##                            take the melody in its second half
##   boss    "Ember Warden" -- 132 bpm; a second layer (boss_hot) is rendered in
##                            lockstep and faded in when the Warden ignites
## Every note shape is synthesized once and mixed into a circular stereo buffer,
## so a loop's ringing tails wrap into its own head and every loop is seamless.
## Rendered on worker threads and cached under user:// after the first launch.

const RATE := 16000
## Bump when the score changes so stale caches are re-rendered.
const VERSION := 2
const CACHE_DIR := "user://audio_cache"
const FADE_TIME := 1.4

## Track name -> target volume in dB while active.
const LEVELS := { "title": -10.0, "explore": -12.0, "boss": -9.0, "boss_hot": -9.0 }
const TRACKS := ["title", "explore", "boss", "boss_hot"]

var enabled := true
var _players: Dictionary = {}
var _threads: Dictionary = {}
var _tracks_ready := false
var _current := ""
var _tweens: Dictionary = {}
var _intensity := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in TRACKS:
		var p := AudioStreamPlayer.new()
		p.name = str(name).capitalize().replace(" ", "")
		# Routed to the Music bus so the options mix owns the score's level;
		# track-to-track balance stays on the player's own volume_db.
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players[name] = p
		var cached := _load_cached(name)
		if cached != null:
			p.stream = cached
		else:
			var th := Thread.new()
			th.start(_render_track.bind(name))
			_threads[name] = th
	_check_ready()

func _exit_tree() -> void:
	for name in _threads:
		var th: Thread = _threads[name]
		if th.is_started():
			th.wait_to_finish()
	_threads.clear()

func is_ready() -> bool:
	return _tracks_ready

func _process(_delta: float) -> void:
	if _threads.is_empty():
		return
	for name in _threads.keys():
		var th: Thread = _threads[name]
		if th.is_alive():
			continue
		var pcm: PackedByteArray = th.wait_to_finish()
		_threads.erase(name)
		var stream := _make_stream(pcm)
		(_players[name] as AudioStreamPlayer).stream = stream
		_save_cached(name, stream)
		# A track that was asked for before it existed starts the moment it lands.
		if name == _current or (name == "boss_hot" and _current == "boss"):
			play_track(_current)
	_check_ready()

func _check_ready() -> void:
	if _tracks_ready:
		return
	for name in TRACKS:
		if (_players[name] as AudioStreamPlayer).stream == null:
			return
	_tracks_ready = true

## Switch tracks: "title", "explore", "boss", or "" for silence.
func play_track(track: String) -> void:
	_current = track
	if track != "boss":
		_intensity = 0.0
	for name in TRACKS:
		var p: AudioStreamPlayer = _players[name]
		var active: bool = enabled and (name == track or (name == "boss_hot" and track == "boss"))
		if active and p.stream != null:
			var target := float(LEVELS.get(name, -12.0))
			if name == "boss_hot":
				target = lerpf(-60.0, target, _intensity) if _intensity > 0.0 else -80.0
			if not p.playing:
				# The hot layer rides in lockstep with the boss theme.
				var at := 0.0
				if name == "boss_hot" and (_players["boss"] as AudioStreamPlayer).playing:
					at = (_players["boss"] as AudioStreamPlayer).get_playback_position()
				elif name == "boss" and (_players["boss_hot"] as AudioStreamPlayer).playing:
					at = (_players["boss_hot"] as AudioStreamPlayer).get_playback_position()
				p.play(at)
			_fade(p, target)
		else:
			_fade(p, -80.0)

## 0..1: how much of the boss theme's second layer is up (phase two).
func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	if _current == "boss":
		play_track("boss")

func set_enabled(value: bool) -> void:
	enabled = value
	play_track(_current)

func _fade(p: AudioStreamPlayer, target_db: float) -> void:
	if _tweens.has(p) and is_instance_valid(_tweens[p]):
		(_tweens[p] as Tween).kill()
	if target_db <= -79.0 and not p.playing:
		p.volume_db = -80.0
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(p, "volume_db", target_db, FADE_TIME)
	if target_db <= -79.0:
		tween.tween_callback(p.stop)
	_tweens[p] = tween

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

static func _make_stream(pcm: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = true
	stream.data = pcm
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = pcm.size() / 4
	return stream

# --- Pitch ---------------------------------------------------------------------

## MIDI note to Hz.
static func hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

# Note names used by the score (MIDI numbers).
const F2 := 41
const G2 := 43
const A2 := 45
const Bb2 := 46
const C3 := 48
const D3 := 50
const E3 := 52
const F3 := 53
const G3 := 55
const A3 := 57
const Cs4 := 61
const E4 := 64
const F4 := 65
const G4 := 67
const A4 := 69
const Bb4 := 70
const C5 := 72
const Cs5 := 73
const D5 := 74
const E5 := 76
const F5 := 77
const G5 := 79
const A5 := 81
const Bb5 := 82
const Eb3 := 51

# --- Mixing --------------------------------------------------------------------

## A circular stereo mix buffer plus a cache of rendered note shapes.
class Mix:
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	var n := 0
	var rate := 16000
	var shapes: Dictionary = {}

	func _init(seconds: float, p_rate: int) -> void:
		rate = p_rate
		n = int(seconds * rate)
		l.resize(n)
		r.resize(n)

	## Add a mono shape at `t` seconds with equal-power `pan` (-1..1). `haas`
	## delays one side by a few milliseconds for width.
	func put(shape: PackedFloat32Array, t: float, gain: float, pan: float = 0.0, haas: float = 0.0) -> void:
		var a := (clampf(pan, -1.0, 1.0) + 1.0) * PI * 0.25
		var gl := cos(a) * gain * 1.414
		var gr := sin(a) * gain * 1.414
		var j := posmod(int(t * rate), n)
		var jr := posmod(j + int(haas * rate), n)
		for i in range(shape.size()):
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

## Low filtered wind across the whole loop (periodic so the loop is seamless).
static func wind(mx: Mix, gain: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	var lp := 0.0
	var lp2 := 0.0
	var span := float(mx.n) / RATE
	for i in range(mx.n):
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
		"title": return _score_title()
		"explore": return _score_explore()
		"boss": return _score_boss(false)
		"boss_hot": return _score_boss(true)
	return PackedByteArray()

## Chord tones (MIDI) for the score's harmony, voiced around middle C.
const CHORDS := {
	"Dm": [D3, F3, A3], "Bb": [Bb2, D3, F3], "Gm": [G2, Bb2, D3], "A": [A2, Cs4 - 12, E3],
	"F": [F2, A2, C3], "C": [C3, E3, G3], "Eb": [Eb3 - 12, G2, Bb2], "A7": [A2, Cs4 - 12, G3],
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
static func _score_title() -> PackedByteArray:
	var beat := 60.0 / 72.0
	var bar := beat * 4.0
	var prog := ["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A"]
	var mx := Mix.new(bar * float(prog.size()), RATE)
	var up := [0, 1, 2, 3, 4, 3, 2, 1]
	var down := [5, 4, 2, 1, 3, 2, 1, 0]
	for b in range(prog.size()):
		var t := float(b) * bar
		var ch: Array = CHORDS[prog[b]]
		_arp(mx, ch, t, beat, 0, 0.32, up if b % 2 == 0 else down)
		mx.put(bass(mx, int(ch[0]) - 12, bar * 0.9), t, 0.5, 0.0)
		if b % 2 == 0:
			mx.put(choir(mx, [int(ch[0]) + 12, int(ch[1]) + 12, int(ch[2]) + 12], bar * 2.2, 0.2), t, 0.34, 0.0, 0.012)
	# The bell line: a question in the first half, its answer leaning on C#.
	var melody := [[0, A4, 3.0], [4, D5, 2.0], [6, C5, 1.0], [7, A4, 1.0], [8, F4, 3.0], [12, Bb4, 2.0], [14, A4, 1.0], [15, G4, 1.0],
		[16, G4, 3.0], [19, Bb4, 1.0], [20, A4, 2.0], [22, G4, 1.0], [23, F4, 1.0], [24, E4, 4.0], [28, Cs5, 4.0]]
	for n in melody:
		mx.put(bell(mx, int(n[1]), 3.2), float(n[0]) * beat, 0.2, 0.25, 0.008)
	wind(mx, 0.35)
	return mx.finish(0.9)

## "The Descent": 84 bpm, sixteen bars. The harp never stops walking; the bells
## pick up the tune when the progression comes round the second time.
static func _score_explore() -> PackedByteArray:
	var beat := 60.0 / 84.0
	var bar := beat * 4.0
	var prog := ["Dm", "Dm", "Bb", "Bb", "F", "F", "C", "C", "Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A"]
	var mx := Mix.new(bar * float(prog.size()), RATE)
	var pat_a := [0, 2, 4, 2, 3, 2, 4, 2]
	var pat_b := [3, 5, 4, 5, 6, 5, 4, 2]
	for b in range(prog.size()):
		var t := float(b) * bar
		var ch: Array = CHORDS[prog[b]]
		_arp(mx, ch, t, beat, 0, 0.27, pat_a if b < 8 else pat_b)
		mx.put(bass(mx, int(ch[0]) - 12, beat * 1.8), t, 0.55, -0.1)
		mx.put(bass(mx, int(ch[0]) - 12, beat * 1.8), t + beat * 2.5, 0.38, -0.1)
		if b % 2 == 0:
			mx.put(choir(mx, [int(ch[0]) + 12, int(ch[1]) + 12, int(ch[2]) + 12], bar * 2.15, 0.35 if b < 8 else 0.0), t, 0.26 if b < 8 else 0.34, 0.0, 0.014)
		# Heartbeat on the frame drum: da-dum, soft.
		mx.put(drum(mx, "frame"), t, 0.28, 0.1)
		mx.put(drum(mx, "frame"), t + beat * 0.5, 0.17, 0.1)
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
