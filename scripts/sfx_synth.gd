extends RefCounted
## Sound design for every cue, synthesized from noise and oscillators. Each cue
## is layered the way a foley sound is: a transient that says "contact", a body
## that says "weight", and a texture that says what it was (steel, cloth, paper,
## stone, fire). Nothing is sampled; nothing is a bare sine blip.
##
## All builders are static and deterministic per seed, so a cue sounds the same
## on every launch and can be rendered off the main thread and cached.

const RATE := 22050
## Bump whenever a cue's design changes, so cached renders are rebuilt.
const VERSION := 2
const CACHE_DIR := "user://audio_cache"

# --- Buffers and primitives ------------------------------------------------------

static func buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(1, int(seconds * RATE)))
	return b

## Exponential decay envelope with a linear attack.
static func env_ad(i: int, attack: float, decay: float) -> float:
	var t := float(i) / RATE
	if t < attack:
		return t / maxf(attack, 0.0001)
	return exp(-(t - attack) / maxf(decay, 0.0001))

## Add a sine whose frequency glides exponentially from f0 to f1 over `glide` s.
static func add_tone(b: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, glide: float, amp: float, attack: float, decay: float, harmonics: float = 0.0) -> void:
	var s0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - s0)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var g := clampf(t / maxf(glide, 0.0001), 0.0, 1.0)
		var f := f0 * pow(f1 / f0, g)
		phase += TAU * f / RATE
		var v := sin(phase)
		if harmonics > 0.0:
			v += harmonics * sin(phase * 2.0) * 0.5 + harmonics * sin(phase * 3.0) * 0.25
		b[s0 + i] += v * amp * env_ad(i, attack, decay)

## Inharmonic struck-metal partials (bell, blade ring, parry clang).
static func add_metal(b: PackedFloat32Array, start: float, dur: float, base: float, amp: float, decay: float, ratios: Array = [1.0, 2.76, 5.40, 8.93], bright: float = 0.6) -> void:
	var s0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - s0)
	var k := 0
	for r in ratios:
		var f := base * float(r)
		if f > RATE * 0.45:
			continue
		var pa := amp * pow(bright, float(k)) / (1.0 + float(k) * 0.35)
		var pd := decay / (1.0 + float(k) * 0.9)
		var w := TAU * f / RATE
		for i in range(n):
			b[s0 + i] += sin(w * float(i)) * pa * env_ad(i, 0.0015, pd)
		k += 1

## Filtered noise through a zero-delay-feedback state-variable filter (stable at
## any cutoff) whose centre sweeps from fc0 to fc1.
## mode: 0 low-pass, 1 band-pass, 2 high-pass.
static func add_noise(b: PackedFloat32Array, start: float, dur: float, fc0: float, fc1: float, q: float, amp: float, attack: float, decay: float, mode: int, seed_val: int, grain_hz: float = 0.0) -> void:
	var s0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - s0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var k := 1.0 / maxf(q, 0.3)
	var ic1 := 0.0
	var ic2 := 0.0
	var grain := 1.0
	var grain_left := 0
	for i in range(n):
		var u := float(i) / maxf(1.0, float(n - 1))
		var fc := minf(fc0 * pow(fc1 / fc0, u), RATE * 0.45)
		var g := tan(PI * fc / RATE)
		var a1 := 1.0 / (1.0 + g * (g + k))
		var a2 := g * a1
		var a3 := g * a2
		var x := rng.randf() * 2.0 - 1.0
		# Crackle: amplitude re-rolled in short random grains, the texture of paper.
		if grain_hz > 0.0:
			grain_left -= 1
			if grain_left <= 0:
				grain_left = int(RATE / (grain_hz * rng.randf_range(0.5, 1.5)))
				grain = pow(rng.randf(), 2.2) * 1.8
			x *= grain
		var v3 := x - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		var y := v2
		if mode == 1:
			y = v1 * k
		elif mode == 2:
			y = x - k * v1 - v2
		b[s0 + i] += y * amp * env_ad(i, attack, decay)

## A few milliseconds of bright noise: the "contact" of an impact.
static func add_click(b: PackedFloat32Array, start: float, amp: float, seed_val: int, tone: float = 5000.0) -> void:
	add_noise(b, start, 0.012, tone, tone * 0.7, 0.9, amp, 0.0004, 0.0035, 2, seed_val)

static func to_stream(pcm: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = pcm
	return s

## Normalise to `gain` peak through a soft clipper, with a short tail fade.
static func finish(b: PackedFloat32Array, gain: float = 1.0) -> PackedByteArray:
	var peak := 0.0001
	for v in b:
		peak = maxf(peak, absf(v))
	var norm := gain / peak
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	var fade := mini(64, b.size())
	for i in range(b.size()):
		var v := tanh(b[i] * norm * 1.15) / tanh(1.15)
		if i >= b.size() - fade:
			v *= float(b.size() - i) / float(fade)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	return data

# --- The cue book ----------------------------------------------------------------
## name -> level (0..1 peak) for every cue, so a mix change is one number.
const LEVELS := {
	"swing": 0.42, "swing_heavy": 0.55, "hit": 0.62, "hit_heavy": 0.75, "tear": 0.6,
	"hurt": 0.8, "jump": 0.28, "land": 0.5, "dash": 0.42, "parry": 0.7, "shield": 0.4,
	"riposte": 0.62, "slam": 0.85, "flame": 0.7, "shoot": 0.45, "heal": 0.45,
	"die": 0.75, "boom": 0.85, "pickup": 0.45, "streak": 0.4, "elite": 0.6,
	"second_wind": 0.6, "pyre": 0.75, "shatter": 0.45, "clear": 0.45, "wave": 0.45,
	"rift": 0.5, "boss": 0.8, "step": 0.16,
	"ui_move": 0.2, "ui_confirm": 0.32, "ui_back": 0.28,
	"victory": 0.6, "defeat": 0.65,
	"tell_stalker": 0.42, "tell_hopper": 0.36, "tell_wisp": 0.36, "tell_brute": 0.55,
	"tell_bomber": 0.45, "tell_crow": 0.42, "tell_lunge": 0.55, "tell_fan": 0.5, "tell_slam": 0.58, "tell_charge": 0.6,
}

## Number of distinct takes per cue. Repeated cues rotate takes so a flurry of
## hits never machine-guns the same waveform.
const VARIANTS := { "swing": 3, "hit": 3, "tear": 3, "step": 4, "hurt": 2, "hit_heavy": 2, "jump": 2, "land": 2 }

static func cue_names() -> Array:
	return LEVELS.keys()

static func cache_path(name: String, take: int) -> String:
	return CACHE_DIR.path_join("sfx_v%d_%s_%d.res" % [VERSION, name, take])

## The whole cue book from the render cache, or {} if any take is missing.
static func load_cached() -> Dictionary:
	var out := {}
	for name in cue_names():
		var takes: Array = []
		for take in range(int(VARIANTS.get(name, 1))):
			var path := cache_path(name, take)
			if not FileAccess.file_exists(path):
				return {}
			var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamWAV
			if res == null:
				return {}
			takes.append(res)
		out[name] = takes
	return out

static func save_cached(book: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	for name in book:
		var takes: Array = book[name]
		for take in range(takes.size()):
			ResourceSaver.save(takes[take], cache_path(name, take))

static func build(name: String, take: int = 0) -> AudioStreamWAV:
	return to_stream(build_pcm(name, take))

## Pure PCM, safe to run on a worker thread.
static func build_pcm(name: String, take: int = 0) -> PackedByteArray:
	var sd := hash(name) + take * 7919
	var b: PackedFloat32Array
	match name:
		"swing":
			# Blade through air: a band of noise sweeping up then settling, and the
			# faintest steel glint at its peak.
			b = buf(0.2)
			var c0 := 520.0 + 90.0 * float(take)
			add_noise(b, 0.0, 0.2, c0, c0 * 4.2, 2.2, 1.0, 0.045, 0.05, 1, sd)
			add_noise(b, 0.02, 0.15, 2600.0, 5200.0, 1.2, 0.25, 0.03, 0.04, 2, sd + 1)
			add_metal(b, 0.04, 0.12, 3150.0 + 140.0 * float(take), 0.05, 0.05, [1.0, 1.51], 0.4)
		"swing_heavy":
			b = buf(0.3)
			add_noise(b, 0.0, 0.3, 300.0, 1900.0, 2.0, 1.0, 0.08, 0.08, 1, sd)
			add_noise(b, 0.03, 0.22, 90.0, 260.0, 0.9, 0.5, 0.06, 0.07, 0, sd + 3)
			add_metal(b, 0.08, 0.2, 2400.0, 0.07, 0.08, [1.0, 1.51, 2.3], 0.45)
		"hit":
			# Blade into a body: contact click, a short low thump, and a cloth/paper
			# crunch in the mids. Takes vary the crunch band and thump pitch.
			b = buf(0.22)
			add_click(b, 0.0, 0.9, sd, 4200.0)
			add_tone(b, 0.0, 0.16, 170.0 - 12.0 * float(take), 62.0, 0.09, 1.0, 0.002, 0.045)
			add_noise(b, 0.0, 0.12, 1500.0 + 300.0 * float(take), 900.0, 1.6, 0.85, 0.001, 0.032, 1, sd + 5)
			add_noise(b, 0.003, 0.05, 3800.0, 2400.0, 1.0, 0.35, 0.001, 0.012, 1, sd + 9)
		"hit_heavy":
			b = buf(0.34)
			add_click(b, 0.0, 1.0, sd, 3600.0)
			add_tone(b, 0.0, 0.3, 140.0, 44.0, 0.16, 1.0, 0.002, 0.09)
			add_noise(b, 0.0, 0.2, 1100.0, 500.0, 1.4, 0.9, 0.001, 0.06, 1, sd + 5)
			add_noise(b, 0.0, 0.25, 600.0, 180.0, 0.8, 0.6, 0.002, 0.08, 0, sd + 11)
			add_metal(b, 0.0, 0.3, 1320.0, 0.12, 0.09, [1.0, 2.76, 4.1], 0.5)
		"tear":
			# The paper-cut kill: a quick rip (crackling high noise, rising) over a
			# soft body drop. This is the sound of a cut-out coming apart.
			b = buf(0.36)
			add_noise(b, 0.0, 0.3, 2400.0, 5200.0 + 400.0 * float(take), 1.3, 1.0, 0.03, 0.09, 1, sd, 240.0 + 40.0 * float(take))
			add_noise(b, 0.01, 0.24, 900.0, 1600.0, 1.1, 0.4, 0.02, 0.07, 1, sd + 2, 120.0)
			add_tone(b, 0.0, 0.2, 120.0, 55.0, 0.12, 0.55, 0.003, 0.06)
			add_click(b, 0.0, 0.5, sd + 4, 3000.0)
		"hurt":
			# Taking a hit: a dull, close thud and a hollow knock, darker than any
			# sound the knight makes when dealing damage.
			b = buf(0.36)
			add_click(b, 0.0, 0.6, sd, 2200.0)
			add_tone(b, 0.0, 0.3, 120.0 - 10.0 * float(take), 48.0, 0.14, 1.0, 0.002, 0.08)
			add_noise(b, 0.0, 0.2, 700.0, 300.0, 1.8, 0.8, 0.002, 0.06, 1, sd + 3)
			add_tone(b, 0.0, 0.25, 233.0, 207.0, 0.2, 0.25, 0.004, 0.08, 0.6)
		"jump":
			b = buf(0.14)
			add_noise(b, 0.0, 0.14, 700.0 + 80.0 * float(take), 1500.0, 1.4, 1.0, 0.012, 0.04, 1, sd)
			add_noise(b, 0.0, 0.08, 180.0, 260.0, 0.8, 0.4, 0.004, 0.025, 0, sd + 1)
		"step":
			b = buf(0.07)
			add_noise(b, 0.0, 0.07, 900.0 + 200.0 * float(take), 500.0, 1.4, 1.0, 0.001, 0.014, 1, sd)
			add_tone(b, 0.0, 0.05, 110.0 + 8.0 * float(take), 70.0, 0.03, 0.6, 0.001, 0.015)
		"land":
			b = buf(0.22)
			add_tone(b, 0.0, 0.2, 95.0 + 6.0 * float(take), 40.0, 0.1, 1.0, 0.002, 0.06)
			add_noise(b, 0.0, 0.16, 500.0, 200.0, 0.9, 0.7, 0.002, 0.045, 0, sd)
			add_noise(b, 0.0, 0.1, 2200.0, 1200.0, 1.3, 0.25, 0.002, 0.02, 1, sd + 1)
		"dash":
			b = buf(0.26)
			add_noise(b, 0.0, 0.26, 260.0, 3400.0, 1.6, 1.0, 0.03, 0.08, 1, sd)
			add_noise(b, 0.0, 0.2, 4000.0, 7000.0, 1.0, 0.25, 0.02, 0.05, 2, sd + 1)
		"parry":
			# Steel meets steel: a hard bright transient and a long inharmonic ring.
			b = buf(0.8)
			add_click(b, 0.0, 1.0, sd, 6000.0)
			add_metal(b, 0.0, 0.8, 880.0, 0.9, 0.28, [1.0, 2.76, 5.40, 8.93, 1.49], 0.7)
			add_metal(b, 0.0, 0.8, 1173.0, 0.45, 0.2, [1.0, 2.6, 4.9], 0.6)
			add_noise(b, 0.0, 0.08, 5000.0, 3000.0, 1.0, 0.5, 0.0005, 0.015, 2, sd + 1)
		"shield":
			b = buf(0.2)
			add_noise(b, 0.0, 0.14, 3500.0, 1800.0, 1.4, 0.8, 0.003, 0.03, 1, sd)
			add_metal(b, 0.0, 0.2, 1480.0, 0.3, 0.05, [1.0, 2.76], 0.5)
		"riposte":
			b = buf(0.5)
			add_noise(b, 0.0, 0.2, 1200.0, 6000.0, 2.0, 0.9, 0.02, 0.05, 1, sd)
			add_click(b, 0.05, 0.8, sd + 1, 6000.0)
			add_metal(b, 0.05, 0.45, 1760.0, 0.6, 0.16, [1.0, 2.76, 5.4], 0.6)
		"slam":
			# The down-slam: stone boom, rubble, a short ringing floor.
			b = buf(0.6)
			add_click(b, 0.0, 1.0, sd, 2000.0)
			add_tone(b, 0.0, 0.55, 90.0, 32.0, 0.25, 1.0, 0.002, 0.16)
			add_noise(b, 0.0, 0.45, 800.0, 160.0, 0.8, 0.9, 0.003, 0.12, 0, sd + 1)
			add_noise(b, 0.02, 0.3, 2500.0, 1400.0, 1.2, 0.3, 0.004, 0.06, 1, sd + 2, 90.0)
		"flame":
			# Ignite: a rushing whoomp of fire catching.
			b = buf(0.6)
			add_noise(b, 0.0, 0.6, 180.0, 2600.0, 0.9, 1.0, 0.07, 0.17, 0, sd, 60.0)
			add_tone(b, 0.0, 0.45, 70.0, 140.0, 0.3, 0.6, 0.04, 0.14)
			add_noise(b, 0.05, 0.4, 3000.0, 5000.0, 1.0, 0.3, 0.05, 0.1, 2, sd + 1, 180.0)
		"shoot":
			b = buf(0.3)
			add_tone(b, 0.0, 0.25, 520.0, 1450.0, 0.12, 0.6, 0.004, 0.06, 0.4)
			add_noise(b, 0.0, 0.25, 900.0, 4200.0, 1.8, 0.8, 0.01, 0.06, 1, sd, 150.0)
		"heal":
			# A sip and a glassy rising shimmer.
			b = buf(0.7)
			add_noise(b, 0.0, 0.12, 600.0, 900.0, 2.0, 0.4, 0.01, 0.04, 1, sd)
			for k in range(4):
				add_metal(b, 0.08 + float(k) * 0.07, 0.5, [659.25, 783.99, 987.77, 1318.5][k], 0.35, 0.25, [1.0, 2.0, 3.01], 0.35)
		"die", "boom":
			# Explosions and heavy deaths: a deep boom with crackling debris.
			b = buf(0.8)
			add_click(b, 0.0, 0.9, sd, 1800.0)
			add_tone(b, 0.0, 0.7, 75.0, 28.0, 0.35, 1.0, 0.003, 0.22)
			add_noise(b, 0.0, 0.7, 1200.0, 140.0, 0.8, 1.0, 0.003, 0.2, 0, sd + 1)
			add_noise(b, 0.05, 0.5, 3000.0, 1500.0, 1.1, 0.35, 0.02, 0.12, 1, sd + 2, 70.0)
		"pickup":
			b = buf(0.5)
			add_metal(b, 0.0, 0.5, 1046.5, 0.6, 0.18, [1.0, 2.0, 3.01], 0.35)
			add_metal(b, 0.07, 0.43, 1568.0, 0.5, 0.2, [1.0, 2.0, 3.01], 0.35)
		"streak":
			b = buf(0.4)
			add_metal(b, 0.0, 0.4, 1318.5, 0.5, 0.14, [1.0, 2.0, 2.76], 0.4)
			add_noise(b, 0.0, 0.1, 3000.0, 5000.0, 1.0, 0.2, 0.004, 0.02, 2, sd)
		"elite":
			# A gong for the gilded: low bronze with a slow bloom.
			b = buf(1.2)
			add_click(b, 0.0, 0.5, sd, 2500.0)
			add_metal(b, 0.0, 1.2, 146.8, 0.9, 0.5, [1.0, 1.52, 2.44, 2.76, 3.9], 0.75)
			add_tone(b, 0.0, 1.0, 73.4, 73.4, 0.1, 0.4, 0.01, 0.35)
		"second_wind":
			b = buf(1.1)
			add_noise(b, 0.0, 0.8, 200.0, 3000.0, 1.0, 0.8, 0.2, 0.25, 0, sd, 50.0)
			for k in range(3):
				add_metal(b, 0.2 + float(k) * 0.1, 0.8, [523.25, 659.25, 783.99][k], 0.5, 0.35, [1.0, 2.0, 3.01], 0.4)
		"pyre":
			b = buf(0.9)
			add_click(b, 0.0, 0.8, sd, 2000.0)
			add_tone(b, 0.0, 0.7, 80.0, 30.0, 0.3, 0.9, 0.003, 0.2)
			add_noise(b, 0.0, 0.8, 300.0, 3000.0, 0.8, 1.0, 0.03, 0.25, 0, sd + 1, 70.0)
		"shatter":
			# Ceramic and brass breaking: bright irregular shards.
			b = buf(0.4)
			add_click(b, 0.0, 0.8, sd, 5000.0)
			for k in range(5):
				add_metal(b, float(k) * 0.025, 0.3, 1800.0 + float(k) * 610.0, 0.35, 0.05, [1.0, 2.3, 3.7], 0.5)
			add_noise(b, 0.0, 0.3, 4000.0, 2500.0, 1.2, 0.5, 0.002, 0.07, 1, sd + 1, 160.0)
		"clear":
			# Chamber cleared: a resolved rising bell figure.
			b = buf(1.3)
			var notes := [587.33, 698.46, 880.0, 1174.66]
			for k in range(notes.size()):
				add_metal(b, float(k) * 0.11, 1.1, notes[k], 0.55, 0.45, [1.0, 2.0, 3.01, 4.2], 0.35)
		"wave":
			b = buf(1.0)
			add_metal(b, 0.0, 1.0, 196.0, 0.8, 0.4, [1.0, 1.52, 2.44, 2.76], 0.7)
			add_metal(b, 0.18, 0.8, 293.66, 0.5, 0.3, [1.0, 1.52, 2.76], 0.6)
		"rift":
			b = buf(1.0)
			add_noise(b, 0.0, 1.0, 180.0, 2400.0, 3.0, 0.8, 0.25, 0.3, 1, sd)
			add_tone(b, 0.0, 0.9, 110.0, 440.0, 0.8, 0.5, 0.2, 0.3, 0.5)
			add_metal(b, 0.5, 0.5, 1318.5, 0.3, 0.2, [1.0, 2.0, 3.01], 0.4)
		"boss":
			b = buf(1.4)
			add_click(b, 0.0, 0.8, sd, 1500.0)
			add_tone(b, 0.0, 1.3, 55.0, 41.0, 0.8, 1.0, 0.004, 0.45, 0.8)
			add_metal(b, 0.0, 1.4, 110.0, 0.6, 0.6, [1.0, 1.52, 2.44, 2.76], 0.7)
			add_noise(b, 0.0, 1.0, 400.0, 120.0, 0.8, 0.6, 0.01, 0.35, 0, sd + 1, 40.0)
		"ui_move":
			b = buf(0.08)
			add_noise(b, 0.0, 0.05, 2600.0, 2200.0, 3.0, 0.8, 0.001, 0.008, 1, sd)
			add_metal(b, 0.0, 0.08, 1760.0, 0.25, 0.02, [1.0, 2.76], 0.4)
		"ui_confirm":
			b = buf(0.45)
			add_metal(b, 0.0, 0.45, 880.0, 0.6, 0.14, [1.0, 2.0, 3.01], 0.35)
			add_metal(b, 0.06, 0.39, 1318.5, 0.5, 0.16, [1.0, 2.0, 3.01], 0.35)
		"ui_back":
			b = buf(0.4)
			add_metal(b, 0.0, 0.4, 880.0, 0.5, 0.12, [1.0, 2.0, 3.01], 0.35)
			add_metal(b, 0.06, 0.34, 659.25, 0.5, 0.14, [1.0, 2.0, 3.01], 0.35)
		"victory":
			# D major bells climbing out of the minor keep, over a warm swell.
			b = buf(3.0)
			var up := [293.66, 369.99, 440.0, 587.33, 739.99, 880.0]
			for k in range(up.size()):
				add_metal(b, float(k) * 0.16, 2.2, up[k], 0.55, 0.9, [1.0, 2.0, 3.01, 4.2], 0.4)
			add_tone(b, 0.0, 2.9, 146.83, 146.83, 0.1, 0.35, 0.4, 1.2, 0.4)
			add_tone(b, 0.0, 2.9, 220.0, 220.0, 0.1, 0.25, 0.4, 1.2, 0.3)
		"defeat":
			# A funeral toll: two slow, low bronze strikes falling a fifth.
			b = buf(3.2)
			add_metal(b, 0.0, 3.2, 146.83, 0.9, 1.1, [1.0, 1.52, 2.44, 2.76, 3.9], 0.7)
			add_metal(b, 1.1, 2.1, 98.0, 1.0, 1.0, [1.0, 1.52, 2.44, 2.76, 3.9], 0.7)
			add_noise(b, 0.0, 1.5, 300.0, 100.0, 0.8, 0.2, 0.2, 0.6, 0, sd, 30.0)
		"tell_stalker":
			# Blade drawn back: a rising scrape of steel on leather.
			b = buf(0.32)
			add_noise(b, 0.0, 0.32, 900.0, 3400.0, 3.5, 0.9, 0.2, 0.06, 1, sd, 90.0)
			add_tone(b, 0.0, 0.3, 220.0, 440.0, 0.28, 0.35, 0.18, 0.06, 0.6)
		"tell_hopper":
			b = buf(0.2)
			add_tone(b, 0.0, 0.18, 520.0, 1180.0, 0.14, 0.6, 0.01, 0.05, 0.3)
			add_noise(b, 0.0, 0.15, 1500.0, 3000.0, 2.0, 0.4, 0.02, 0.04, 1, sd)
		"tell_wisp":
			# A spirit drawing breath: an eerie hollow rise.
			b = buf(0.5)
			add_tone(b, 0.0, 0.5, 330.0, 1240.0, 0.45, 0.7, 0.2, 0.1, 0.2)
			add_tone(b, 0.0, 0.5, 337.0, 1265.0, 0.45, 0.5, 0.2, 0.1)
			add_noise(b, 0.0, 0.5, 2000.0, 5000.0, 4.0, 0.2, 0.3, 0.1, 1, sd)
		"tell_brute":
			# Iron on iron, a heavy hauling grunt.
			b = buf(0.55)
			add_tone(b, 0.0, 0.5, 80.0, 140.0, 0.4, 0.9, 0.12, 0.15, 0.9)
			add_noise(b, 0.0, 0.45, 300.0, 700.0, 2.0, 0.6, 0.15, 0.12, 1, sd, 40.0)
			add_metal(b, 0.25, 0.3, 440.0, 0.2, 0.1, [1.0, 2.76], 0.5)
		"tell_bomber":
			# A lit fuse: sputtering crackle.
			b = buf(0.5)
			add_noise(b, 0.0, 0.5, 3000.0, 4500.0, 1.5, 1.0, 0.02, 0.2, 1, sd, 320.0)
			add_tone(b, 0.0, 0.4, 900.0, 1400.0, 0.4, 0.15, 0.05, 0.15)
		"tell_crow":
			# A carrion caw: a rasping, falling cry in two beats.
			b = buf(0.5)
			for k in range(2):
				var st := float(k) * 0.2
				add_tone(b, st, 0.18, 760.0 - 60.0 * float(k), 560.0, 0.16, 0.7, 0.01, 0.07, 1.0)
				add_noise(b, st, 0.18, 1300.0, 1000.0, 3.0, 0.8, 0.01, 0.07, 1, sd + k, 140.0)
				add_noise(b, st, 0.16, 2200.0, 1700.0, 4.0, 0.4, 0.01, 0.06, 1, sd + 7 + k)
		"tell_lunge":
			b = buf(0.45)
			add_noise(b, 0.0, 0.45, 200.0, 900.0, 1.2, 0.9, 0.25, 0.1, 0, sd, 45.0)
			add_tone(b, 0.0, 0.4, 110.0, 190.0, 0.35, 0.8, 0.2, 0.1, 0.9)
		"tell_fan":
			# Fire gathering in a palm: a rising roar and a bright ring.
			b = buf(0.5)
			add_noise(b, 0.0, 0.5, 400.0, 3500.0, 1.0, 0.9, 0.3, 0.1, 0, sd, 80.0)
			add_metal(b, 0.25, 0.25, 660.0, 0.4, 0.1, [1.0, 2.76], 0.5)
		"tell_slam":
			b = buf(0.5)
			add_tone(b, 0.0, 0.45, 70.0, 150.0, 0.4, 1.0, 0.25, 0.1, 0.9)
			add_noise(b, 0.0, 0.45, 250.0, 1400.0, 1.3, 0.6, 0.3, 0.1, 0, sd, 40.0)
		"tell_charge":
			# Hooves on stone: a bellowing rise and pounding grain.
			b = buf(0.65)
			add_tone(b, 0.0, 0.6, 65.0, 160.0, 0.55, 1.0, 0.3, 0.12, 1.0)
			add_noise(b, 0.0, 0.6, 180.0, 700.0, 1.2, 0.8, 0.3, 0.12, 0, sd, 14.0)
		_:
			b = buf(0.1)
			add_click(b, 0.0, 0.5, sd)
	return finish(b, float(LEVELS.get(name, 0.5)))
