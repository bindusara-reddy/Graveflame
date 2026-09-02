class_name Music
extends Node
## Procedural score. Two seamless loops (explore, boss) are synthesized on a
## worker thread at boot from nothing but sine math and noise, then crossfaded
## by game state. No audio assets exist; everything here is original.

const RATE := 11025
const XFADE_SECONDS := 0.6
const FADE_TIME := 1.4

## Track name -> target volume in dB while active.
const LEVELS := { "explore": -13.0, "boss": -9.5, "title": -19.0 }

var enabled := true
var _players: Dictionary = {}
var _thread: Thread
var _tracks_ready := false
var _current := ""
var _pending := ""
var _tweens: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in ["explore", "boss"]:
		var p := AudioStreamPlayer.new()
		p.name = name.capitalize()
		p.bus = "Master"
		p.volume_db = -80.0
		add_child(p)
		_players[name] = p
	_thread = Thread.new()
	_thread.start(_render_all)
	set_process(true)

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null

func is_ready() -> bool:
	return _tracks_ready

func _process(_delta: float) -> void:
	if _tracks_ready or _thread == null or _thread.is_alive():
		return
	var rendered: Dictionary = _thread.wait_to_finish()
	_thread = null
	for name in rendered:
		(_players[name] as AudioStreamPlayer).stream = _make_stream(rendered[name])
	_tracks_ready = true
	if _pending != "":
		var next := _pending
		_pending = ""
		play_track(next)

## Switch tracks: "explore", "boss", "title" (soft explore) or "" for silence.
func play_track(track: String) -> void:
	if not _tracks_ready:
		_pending = track
		return
	var source := "explore" if track == "title" else track
	for name in _players:
		var p: AudioStreamPlayer = _players[name]
		var target := -80.0
		if enabled and name == source:
			target = float(LEVELS.get(track, -13.0))
			if not p.playing:
				p.play()
		_fade(p, target)
	_current = track

func set_enabled(value: bool) -> void:
	enabled = value
	play_track(_current)

func _fade(p: AudioStreamPlayer, target_db: float) -> void:
	if _tweens.has(p) and is_instance_valid(_tweens[p]):
		(_tweens[p] as Tween).kill()
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(p, "volume_db", target_db, FADE_TIME)
	if target_db <= -79.0:
		tween.tween_callback(p.stop)
	_tweens[p] = tween

# --- Synthesis ------------------------------------------------------------------

func _render_all() -> Dictionary:
	return { "explore": _render_explore(), "boss": _render_boss() }

static func _make_stream(pcm: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = pcm
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = pcm.size() / 2
	return stream

## Blend the tail past the loop point into the head so the wrap is click-free,
## soft-clip, and pack to 16-bit.
static func _finish(buf: PackedFloat32Array, loop_samples: int, gain: float) -> PackedByteArray:
	var x := mini(int(XFADE_SECONDS * RATE), loop_samples / 2)
	var out := PackedByteArray()
	out.resize(loop_samples * 2)
	for i in range(loop_samples):
		var s := buf[i]
		if i < x:
			var w := float(i) / float(x)
			s = buf[i] * w + buf[loop_samples + i] * (1.0 - w)
		s = tanh(s * gain)
		out.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return out

## Pad voice: detuned pair with two soft harmonics.
static func _pad(freq: float, t: float) -> float:
	var a := TAU * freq * 1.0015 * t
	var b := TAU * freq * 0.9985 * t
	return sin(a) + sin(b) + 0.32 * (sin(a * 2.0) + sin(b * 2.0)) + 0.08 * sin(a * 3.0)

static func _chord_voice(chord: Array, t: float) -> float:
	var v := 0.0
	for f in chord:
		v += _pad(float(f), t)
	return v / float(chord.size())

## Equal-power crossfade between consecutive chords over the last `xfade_frac`
## of each segment, so the bed never dips or clicks at a change. `chords` is an
## Array of Arrays of Hz; the sequence repeats.
static func _chord_bed(t: float, chords: Array, seg_time: float, xfade_frac: float) -> float:
	var kc := floori(t / seg_time)
	var u := t / seg_time - float(kc)
	var cur := _chord_voice(chords[posmod(kc, chords.size())], t)
	if u < 1.0 - xfade_frac:
		return cur
	var w := smoothstep(1.0 - xfade_frac, 1.0, u) * PI * 0.5
	var nxt := _chord_voice(chords[posmod(kc + 1, chords.size())], t)
	return cur * cos(w) + nxt * sin(w)

## Same crossfade for a single bass root per segment.
static func _root_bed(t: float, roots: Array, seg_time: float, xfade_frac: float) -> float:
	var kc := floori(t / seg_time)
	var u := t / seg_time - float(kc)
	var cur := sin(TAU * float(roots[posmod(kc, roots.size())]) * t)
	if u < 1.0 - xfade_frac:
		return cur
	var w := smoothstep(1.0 - xfade_frac, 1.0, u) * PI * 0.5
	var nxt := sin(TAU * float(roots[posmod(kc + 1, roots.size())]) * t)
	return cur * cos(w) + nxt * sin(w)

static func _bell(freq: float, age: float, decay: float) -> float:
	if age < 0.0:
		return 0.0
	var env := exp(-age * decay)
	return (sin(TAU * freq * age) + 0.35 * sin(TAU * freq * 2.76 * age) + 0.15 * sin(TAU * freq * 5.4 * age)) * env

func _render_explore() -> PackedByteArray:
	# D minor: Dm - Bb - Gm - Asus. 2.4 s per chord, 9.6 s loop.
	var seg := 2.4
	var chords := [
		[146.83, 174.61, 220.0],
		[116.54, 146.83, 174.61],
		[98.0, 116.54, 146.83],
		[110.0, 164.81, 220.0],
	]
	var roots := [73.42, 58.27, 49.0, 55.0]
	var loop_len := seg * float(chords.size())
	var n := int(loop_len * RATE)
	var total := n + int(XFADE_SECONDS * RATE) + 1
	var buf := PackedFloat32Array()
	buf.resize(total)
	# Sparse bells on the D minor pentatonic, positions fixed by a hash so the
	# loop is identical every launch.
	var bell_notes := [587.33, 698.46, 783.99, 880.0, 1046.5]
	var bells: Array = []
	for i in range(9):
		var when := fmod(float(i) * 1.13 + _hash(i, 3) * 0.9, loop_len)
		bells.append([when, float(bell_notes[int(_hash(i, 7) * 5.0) % 5])])
	var wind := 0.0
	var wind_lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	for i in range(total):
		var t := float(i) / float(RATE)
		var tl := fmod(t, loop_len)
		var s := 0.0
		# Pad bed with a slow, loop-periodic swell.
		var swell := 0.75 + 0.25 * sin(TAU * t / loop_len * 2.0 - PI * 0.5)
		s += _chord_bed(t, chords, seg, 0.45) * 0.11 * swell
		# Sub root, crossfaded across chord changes.
		s += _root_bed(t, roots, seg, 0.3) * 0.16
		# Bells.
		for b in bells:
			var age: float = tl - float(b[0])
			if age < 0.0:
				age += loop_len
			if age < 3.0:
				s += _bell(float(b[1]), age, 2.6) * 0.045
		# Filtered wind, swelling twice per loop.
		wind_lp = lerpf(wind_lp, rng.randf() * 2.0 - 1.0, 0.045)
		wind = lerpf(wind, wind_lp, 0.5)
		var gust := 0.5 + 0.5 * sin(TAU * t / loop_len * 2.0 + 1.0)
		s += wind * 0.05 * gust
		buf[i] = s
	return _finish(buf, n, 1.35)

func _render_boss() -> PackedByteArray:
	# 120 BPM, 16 beats, 8 s loop. Dm against a Neapolitan Eb for two bars each.
	var beat := 0.5
	var loop_len := 8.0
	var n := int(loop_len * RATE)
	var total := n + int(XFADE_SECONDS * RATE) + 1
	var buf := PackedFloat32Array()
	buf.resize(total)
	var chords := [
		[146.83, 174.61, 220.0],
		[146.83, 174.61, 220.0],
		[155.56, 196.0, 233.08],
		[146.83, 174.61, 233.08],
	]
	var seg := 2.0
	var bell_notes := [587.33, 622.25, 880.0, 932.33]
	var hits: Array = []
	for i in range(6):
		var when := float(int(_hash(i, 11) * 16.0)) * beat + (0.25 if _hash(i, 13) > 0.6 else 0.0)
		hits.append([when, float(bell_notes[int(_hash(i, 17) * 4.0) % 4])])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var hiss_lp := 0.0
	for i in range(total):
		var t := float(i) / float(RATE)
		var tl := fmod(t, loop_len)
		var s := 0.0
		# Drone fifth with a 4 Hz tremolo (32 cycles per loop, so it is periodic).
		var trem := 0.8 + 0.2 * sin(TAU * 4.0 * t)
		s += (sin(TAU * 73.42 * t) + 0.5 * sin(TAU * 110.0 * t) + 0.25 * sin(TAU * 146.83 * t)) * 0.13 * trem
		# Pad bed, tighter overlap for urgency.
		s += _chord_bed(t, chords, seg, 0.25) * 0.09
		# Kick every beat, heavier on the downbeat; a tom on the last off-beat of each bar.
		var beat_idx := int(tl / beat)
		var age := tl - float(beat_idx) * beat
		var accent := 1.0 if beat_idx % 4 == 0 else 0.75
		if age < 0.28:
			var f := lerpf(150.0, 42.0, minf(1.0, age / 0.12))
			s += sin(TAU * f * age) * exp(-age * 14.0) * 0.55 * accent
		if beat_idx % 8 == 7:
			var tom_age := age - 0.25
			if tom_age >= 0.0 and tom_age < 0.25:
				s += sin(TAU * lerpf(190.0, 90.0, tom_age / 0.25) * tom_age) * exp(-tom_age * 16.0) * 0.4
		# Dissonant bell stabs.
		for h in hits:
			var hage: float = tl - float(h[0])
			if hage < 0.0:
				hage += loop_len
			if hage < 1.6:
				s += _bell(float(h[1]), hage, 4.0) * 0.06
		# Riser hiss through the final bar, cut by the downbeat.
		hiss_lp = lerpf(hiss_lp, rng.randf() * 2.0 - 1.0, 0.18)
		if tl >= 6.0:
			s += hiss_lp * 0.09 * ((tl - 6.0) / 2.0)
		buf[i] = s
	return _finish(buf, n, 1.4)

static func _hash(i: int, salt: int) -> float:
	var x := sin(float(i) * 12.9898 + float(salt) * 78.233) * 43758.5453
	return x - floor(x)
