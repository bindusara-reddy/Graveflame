extends RefCounted
## The flame-headed knight as a paper puppet: bone coat, ember sash, dark ink
## limbs, round mask, four-tongue flame crown and steel blade, jointed at hip,
## knee, shoulder, wrist and neck so every move reads as a pose instead of a slide.
##
## Geometry is authored facing right in body space: origin at the body centre,
## feet on y = +27 (Content.P_BODY_H * 0.5). paint() mirrors for facing.
## A pose is a flat Dictionary of floats so poses can be blended key by key.
## Angles: limb angles are screen angles (0 = forward, +PI/2 = down). Leg angles
## are measured from straight down, positive swinging forward; knee bend folds
## the shin backward.

const VFX := preload("res://scripts/vfx.gd")

const FOOT_Y := 27.0
const HIP := Vector2(0.0, 6.0)
const THIGH := 10.5
const SHIN := 10.5
const NECK := Vector2(0.0, -17.0)
const HEAD_R := 10.4
const SHOULDER_F := Vector2(5.0, -12.0)
const SHOULDER_B := Vector2(-5.0, -12.0)
const ARM_F := 11.0
const ARM_B := 9.0
const BLADE := 27.0

const INK_BACK := Color("17131f")
const INK_FRONT := Color("221a2c")
const INK_ARM := Color("1c1524")
const MASK := Color("211828")
const CAPE := Color("c94a28")
const STEEL := Color("aab4c4")
const HILT := Color("f0b45a")
const EYE := Color("ffe8a3")
const FLAME := Color("ff7a18")

## Coat polygon in body space: the original asymmetric tabard.
const COAT := [
	Vector2(-12.48, -15.12), Vector2(10.92, -17.28),
	Vector2(13.52, 12.96), Vector2(0.0, 19.44),
	Vector2(-14.56, 10.8),
]

## Every blendable key with its rest value.
const REST := {
	"x": 0.0, "y": 0.0, "rot": 0.0, "sx": 1.0, "sy": 1.0,
	"torso": 0.0, "head": 0.0, "breath": 0.0,
	"hip_f": 0.12, "knee_f": 0.08, "hip_b": -0.1, "knee_b": 0.1,
	"arm_f": 1.14, "sword": -0.3, "arm_b": 1.9,
	"cape": 0.0, "flutter": 0.25, "flame": 1.0, "lean_flame": 0.0,
	"ground": 1.0, "flask": 0.0, "reach": 1.0,
}

## Attack keyframes: the wind (end of startup) and strike (end of active).
## `smear` is the blade sweep in body angles around the shoulder, from -> to.
const SWINGS := {
	"cut": {
		"wind": { "arm_f": -2.2, "sword": -0.4, "torso": -0.1, "head": -0.06, "hip_f": 0.2, "knee_f": 0.2, "hip_b": -0.25, "knee_b": 0.15, "arm_b": 2.4 },
		"strike": { "arm_f": 0.95, "sword": 0.3, "torso": 0.17, "head": 0.1, "hip_f": 0.42, "knee_f": 0.35, "hip_b": -0.42, "knee_b": 0.1, "arm_b": 2.0 },
		"smear": [-1.3, 0.95],
	},
	"cleave": {
		"wind": { "arm_f": 2.35, "sword": 0.45, "torso": 0.1, "head": 0.08, "hip_f": 0.35, "knee_f": 0.55, "hip_b": -0.3, "knee_b": 0.35, "arm_b": 1.4 },
		"strike": { "arm_f": -1.15, "sword": -0.35, "torso": -0.1, "head": -0.1, "hip_f": 0.28, "knee_f": 0.2, "hip_b": -0.45, "knee_b": 0.05, "arm_b": 2.6 },
		"smear": [1.05, -1.15],
	},
	"finish": {
		"wind": { "arm_f": -2.75, "sword": -0.25, "torso": -0.26, "head": -0.14, "hip_f": 0.1, "knee_f": 0.6, "hip_b": -0.2, "knee_b": 0.7, "arm_b": 2.9, "sy": 0.94, "sx": 1.05 },
		"strike": { "arm_f": 1.3, "sword": 0.35, "torso": 0.4, "head": 0.18, "hip_f": 0.75, "knee_f": 1.0, "hip_b": -0.7, "knee_b": 0.15, "arm_b": 2.2, "sy": 1.0, "sx": 1.0 },
		"smear": [-1.7, 1.3],
	},
	"riposte": {
		"wind": { "arm_f": 2.75, "sword": -2.65, "torso": -0.14, "head": -0.05, "hip_f": 0.1, "knee_f": 0.5, "hip_b": -0.35, "knee_b": 0.4, "arm_b": 2.8 },
		"strike": { "arm_f": 0.02, "sword": 0.0, "torso": 0.3, "head": 0.1, "hip_f": 0.8, "knee_f": 0.9, "hip_b": -0.8, "knee_b": 0.05, "arm_b": 2.9 },
		"smear": [],
	},
}

static func swing_name(p) -> String:
	if p._riposte_attack:
		return "riposte"
	match int(p.attack_index):
		1: return "cleave"
		2: return "finish"
	return "cut"

static func _merged(over: Dictionary) -> Dictionary:
	var out := REST.duplicate()
	for k in over:
		out[k] = over[k]
	return out

static func _lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = lerpf(float(a.get(k, REST.get(k, 0.0))), float(b[k]), t)
	return out

static func _ease_out(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - u) * (1.0 - u) * (1.0 - u)

## Frame-rate independent approach toward `target`. rate <= 0 snaps.
static func blend(current: Dictionary, target: Dictionary, rate: float, delta: float) -> Dictionary:
	if current.is_empty() or rate <= 0.0:
		return target.duplicate()
	var k := 1.0 - exp(-rate * delta)
	var out := {}
	for key in target:
		out[key] = lerpf(float(current.get(key, target[key])), float(target[key]), k)
	return out

## Target pose for the player's current state plus how fast to reach it.
## Returns { "pose": Dictionary, "rate": float, "smear": Dictionary }.
static func target(p) -> Dictionary:
	var t: float = p._anim_time
	var vx: float = p.velocity.x * p.facing
	var vy: float = p.velocity.y
	var speed := clampf(absf(p.velocity.x) / Content.P_SPEED, 0.0, 1.4)
	var grounded: bool = p.is_on_floor()
	var pose := REST.duplicate()
	var rate := 18.0
	var smear := {}
	# Idle breath and a resting sword that drifts a hair.
	pose.breath = sin(t * 1.9) * 0.018
	pose.arm_f = 1.14 + sin(t * 1.9 + 0.6) * 0.03
	pose.cape = 0.0
	pose.flutter = 0.25 + speed * 0.9
	pose.lean_flame = clampf(-vx / 520.0, -1.0, 1.0)
	match int(p.state):
		Player.State.LOCOMOTION:
			if grounded:
				if speed > 0.08:
					var ph: float = p._run_phase
					var s := sin(ph)
					var c := cos(ph)
					var amt := clampf(speed, 0.0, 1.0)
					pose.hip_f = 0.78 * s * amt + 0.05
					pose.hip_b = -0.78 * s * amt + 0.05
					pose.knee_f = 0.12 + 1.25 * maxf(0.0, c) * amt
					pose.knee_b = 0.12 + 1.25 * maxf(0.0, -c) * amt
					pose.torso = 0.14 * amt
					pose.head = -0.04 * amt
					pose.arm_f = 1.0 - 0.28 * s * amt
					pose.arm_b = 1.9 + 0.5 * s * amt
					pose.cape = 0.55 * amt
					rate = 24.0
				if p._land_squash > 0.0:
					var k: float = p._land_squash / 0.12
					pose.sy = 1.0 - 0.14 * k
					pose.sx = 1.0 + 0.1 * k
					pose.knee_f = maxf(pose.knee_f, 0.9 * k)
					pose.knee_b = maxf(pose.knee_b, 0.8 * k)
					pose.hip_f = maxf(pose.hip_f, 0.4 * k)
					rate = 40.0
			elif p.wall_sliding:
				pose.torso = -0.18
				pose.head = -0.12
				pose.hip_f = 1.0
				pose.knee_f = 1.7
				pose.hip_b = 0.15
				pose.knee_b = 0.7
				pose.arm_f = -0.55
				pose.sword = 0.9
				pose.arm_b = 2.5
				pose.cape = -0.4
				pose.ground = 0.0
			else:
				pose.ground = 0.0
				# Rising: knees tucked. Falling: legs reach for the floor, cape lifts.
				var fall := clampf((vy + 150.0) / 750.0, 0.0, 1.0)
				pose.hip_f = lerpf(0.85, 0.3, fall)
				pose.knee_f = lerpf(1.5, 0.35, fall)
				pose.hip_b = lerpf(0.15, -0.3, fall)
				pose.knee_b = lerpf(1.2, 0.55, fall)
				pose.torso = lerpf(0.06, -0.05, fall)
				pose.arm_f = lerpf(0.7, -0.1, fall)
				pose.arm_b = lerpf(2.2, 3.4, fall)
				pose.cape = lerpf(0.3, -0.9, fall)
				pose.sy = lerpf(1.06, 1.0, fall)
				pose.sx = lerpf(0.96, 1.0, fall)
				if p._flip_t > 0.0:
					# Double-jump somersault: tucked tight, the whole cut-out turning over.
					pose.hip_f = 1.3
					pose.knee_f = 2.1
					pose.hip_b = 1.1
					pose.knee_b = 2.0
					pose.arm_f = 0.4
					pose.arm_b = 1.0
					pose.torso = 0.3
					rate = 45.0
			if p._cast_t > 0.0:
				# Flame lance: an open-handed thrust after the bolt.
				var ck: float = clampf(p._cast_t / 0.22, 0.0, 1.0)
				pose.arm_f = lerpf(0.9, -0.05, ck)
				pose.sword = lerpf(-0.3, -1.5, ck)
				pose.arm_b = lerpf(1.9, 0.1, ck)
				pose.torso = lerpf(pose.torso, 0.12, ck)
				rate = 35.0
			if p._ignite_t > 0.0:
				var ik: float = clampf(p._ignite_t / 0.4, 0.0, 1.0)
				pose.arm_f = lerpf(pose.arm_f, -1.9, ik)
				pose.sword = lerpf(pose.sword, -0.2, ik)
				pose.arm_b = lerpf(pose.arm_b, -1.2 + TAU, ik)
				pose.head = -0.25 * ik
				pose.torso = -0.12 * ik
				pose.flame = 1.0 + 0.8 * ik
				rate = 30.0
		Player.State.ATTACK:
			var sw: Dictionary = SWINGS[swing_name(p)]
			var def: Dictionary = p.get_meta("atk_def", Content.COMBO[0])
			var wind := _merged(sw.wind)
			var strike := _merged(sw.strike)
			match str(p.atk_phase):
				"startup":
					pose = wind
					rate = 55.0
				"active":
					var u := 1.0 - float(p.atk_time) / maxf(0.001, float(def.active))
					pose = _lerp_pose(wind, strike, _ease_out(u))
					rate = 0.0
					var arc: Array = sw.smear
					if arc.size() == 2:
						smear = { "from": float(arc[0]), "to": lerpf(float(arc[0]), float(arc[1]), _ease_out(u)),
							"radius": float(def.range), "heavy": int(p.attack_index) == Content.COMBO.size() - 1 }
				_:
					var u := 1.0 - float(p.atk_time) / maxf(0.001, float(def.recover))
					pose = strike if u < 0.55 else _lerp_pose(strike, REST, (u - 0.55) / 0.45)
					rate = 30.0
			if not grounded:
				pose.ground = 0.0
			pose.cape = 0.45
			pose.flutter = 0.8
		Player.State.SLAM:
			pose.ground = 0.0
			pose.hip_f = 1.25
			pose.knee_f = 2.1
			pose.hip_b = 0.8
			pose.knee_b = 1.9
			pose.torso = 0.2
			pose.head = 0.15
			pose.arm_f = PI * 0.5
			pose.sword = 0.0
			pose.arm_b = -2.0 + TAU
			pose.cape = -1.0
			pose.flutter = 1.2
			pose.lean_flame = 0.0
			pose.flame = 1.3
			rate = 40.0
		Player.State.DASH:
			pose.torso = 0.5
			pose.head = 0.2
			pose.hip_f = 1.0
			pose.knee_f = 1.5
			pose.hip_b = -1.0
			pose.knee_b = 0.6
			pose.arm_f = 2.7
			pose.sword = 0.2
			pose.arm_b = 2.6
			pose.cape = 1.0
			pose.flutter = 1.4
			pose.sx = 1.12
			pose.sy = 0.9
			pose.y = 3.0
			pose.ground = 0.0
			pose.lean_flame = -1.0
			rate = 50.0
		Player.State.PARRY:
			pose.torso = -0.1
			pose.head = -0.05
			pose.hip_f = 0.45
			pose.knee_f = 0.55
			pose.hip_b = -0.5
			pose.knee_b = 0.25
			pose.arm_f = -0.35
			pose.sword = -1.35
			pose.arm_b = 0.4
			pose.cape = 0.2
			rate = 60.0
		Player.State.HEAL:
			var hk := clampf(1.0 - float(p._heal_time) / Content.P_HEAL_TIME, 0.0, 1.0)
			pose.hip_f = 0.55
			pose.knee_f = 1.0
			pose.hip_b = -0.25
			pose.knee_b = 0.95
			pose.torso = 0.08 - 0.12 * hk
			pose.head = -0.35 * hk
			pose.arm_f = 1.35
			pose.arm_b = lerpf(1.2, -1.2, hk)
			pose.flask = 1.0
			rate = 22.0
		Player.State.HURT:
			pose.torso = -0.42
			pose.head = -0.45
			pose.hip_f = 0.55
			pose.knee_f = 0.9
			pose.hip_b = -0.45
			pose.knee_b = 0.3
			pose.arm_f = -2.3
			pose.sword = -0.6
			pose.arm_b = -2.6 + TAU
			pose.cape = -0.3
			pose.flutter = 1.2
			pose.rot = -0.12
			pose.ground = 1.0 if grounded else 0.0
			rate = 45.0
		Player.State.DEAD:
			var d: float = p._death_t
			var buckle := _ease_out(d / 0.35)
			var topple := _ease_out((d - 0.3) / 0.55)
			pose.hip_f = lerpf(0.3, 1.3, buckle)
			pose.knee_f = lerpf(0.4, 2.2, buckle)
			pose.hip_b = lerpf(-0.2, 0.9, buckle)
			pose.knee_b = lerpf(0.3, 2.3, buckle)
			pose.torso = lerpf(0.2, 0.9, buckle) + 0.3 * topple
			pose.head = lerpf(0.2, 0.6, buckle)
			pose.arm_f = lerpf(1.3, 1.9, buckle)
			pose.sword = lerpf(0.0, 1.2, topple)
			pose.arm_b = 1.7
			pose.rot = 1.25 * topple
			pose.flame = clampf(1.0 - d / 1.1, 0.0, 1.0)
			pose.cape = 0.0
			pose.flutter = 0.1
			rate = 0.0
	if not grounded and int(p.state) != Player.State.DEAD:
		pose.ground = 0.0
	if p._flip_t > 0.0:
		pose.rot = TAU * (1.0 - float(p._flip_t) / Player.FLIP_TIME)
	return { "pose": pose, "rate": rate, "smear": smear }

## Leg forward kinematics from the hip: thigh down-and-forward by `hip`, the shin
## folded back by `knee`. Returns [knee, foot, shin_angle].
static func _leg(hip: Vector2, hip_a: float, knee_a: float) -> Array:
	var k := hip + Vector2(sin(hip_a), cos(hip_a)) * THIGH
	var shin := hip_a - knee_a
	var f := k + Vector2(sin(shin), cos(shin)) * SHIN
	return [k, f, shin]

## Vertical offset that plants the lower foot on the floor line.
static func ground_offset(pose: Dictionary) -> float:
	if float(pose.get("ground", 1.0)) < 0.5:
		return 0.0
	var fb: Vector2 = _leg(HIP, float(pose.hip_b), float(pose.knee_b))[1]
	var ff: Vector2 = _leg(HIP, float(pose.hip_f), float(pose.knee_f))[1]
	return FOOT_Y - maxf(fb.y, ff.y)

## Body-space transform: squash about the feet, whole-body turn (about the feet
## while standing, so a stagger or a collapse pivots on the boots; about the
## centre in the air, so a somersault turns in place), the root offset, and the
## facing mirror.
static func body_xform(pose: Dictionary, facing: float, flip_scale: float = 1.0) -> Transform2D:
	var feet := Vector2(0.0, FOOT_Y)
	var sq := Transform2D(0.0, Vector2(float(pose.sx), float(pose.sy)), 0.0, Vector2.ZERO)
	sq.origin = feet - sq.basis_xform(feet)
	var pivot := Vector2.ZERO.lerp(feet, clampf(float(pose.get("ground", 1.0)), 0.0, 1.0))
	var turn := _rot_about(pivot, float(pose.rot))
	var root := Transform2D(0.0, Vector2(float(pose.x), float(pose.y) + ground_offset(pose)))
	var mirror := Transform2D(0.0, Vector2(facing * flip_scale, 1.0), 0.0, Vector2.ZERO)
	return mirror * root * turn * sq

## Torso frame: leans about the hip and breathes by stretching up from it.
static func torso_xform(pose: Dictionary) -> Transform2D:
	var lean := Transform2D(float(pose.torso), Vector2(1.0, 1.0 + float(pose.get("breath", 0.0))), 0.0, Vector2.ZERO)
	return Transform2D(0.0, HIP) * lean * Transform2D(0.0, -HIP)

static func _rot_about(pivot: Vector2, angle: float) -> Transform2D:
	return Transform2D(angle, pivot) * Transform2D(0.0, -pivot)

static func _tri(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	ci.draw_primitive(PackedVector2Array([a, b, c]), PackedColorArray([col, col, col]), PackedVector2Array())

## A tapered paper strip between two points (limb segment).
static func _strip(a: Vector2, b: Vector2, w0: float, w1: float) -> PackedVector2Array:
	var d := (b - a)
	if d.length_squared() < 0.0001:
		d = Vector2.DOWN
	var n := Vector2(-d.y, d.x).normalized()
	return PackedVector2Array([a + n * w0 * 0.5, b + n * w1 * 0.5, b - n * w1 * 0.5, a - n * w0 * 0.5])

static func _boot(foot: Vector2, shin_angle: float) -> PackedVector2Array:
	# Toe points forward, perpendicular to the shin.
	var fwd := Vector2(cos(shin_angle), -sin(shin_angle))
	var up := Vector2(-sin(shin_angle), -cos(shin_angle))
	return PackedVector2Array([
		foot + up * 3.2 - fwd * 3.0, foot + up * 2.4 + fwd * 3.0,
		foot + fwd * 6.5 - up * 0.8, foot + fwd * 5.5 - up * 1.8, foot - fwd * 3.5 - up * 1.8,
	])

## `look` keys: coat (Color), flat (Color or null for a solid silhouette),
## flame_mode (bool), t (anim time), blink (0..1 eyelid), alpha.
static func paint(ci: CanvasItem, origin: Vector2, pose: Dictionary, facing: float, look: Dictionary, smear: Dictionary = {}) -> void:
	var flat = look.get("flat", null)
	var solid: bool = flat != null
	var fc: Color = flat if solid else Color.WHITE
	var t: float = float(look.get("t", 0.0))
	var coat_col: Color = fc if solid else look.get("coat", Content.PAL.player)
	var flame_mode: bool = bool(look.get("flame_mode", false))
	var sc := float(look.get("scale", 1.0))
	var xf := Transform2D(0.0, Vector2(sc, sc), 0.0, origin) * body_xform(pose, facing, float(look.get("flip_scale", 1.0)))
	ci.draw_set_transform_matrix(xf)
	var torso_xf := torso_xform(pose)
	var neck: Vector2 = torso_xf * NECK
	var head_a := float(pose.torso) + float(pose.head)
	var head := neck + Vector2(0.0, -11.0).rotated(head_a)
	var sh_f: Vector2 = torso_xf * SHOULDER_F
	var sh_b: Vector2 = torso_xf * SHOULDER_B
	# --- Cape: a three-link strip hung from the back of the collar. ---
	var cape_col: Color = fc if solid else CAPE
	var anchor: Vector2 = torso_xf * Vector2(-7.0, -15.5)
	var anchor2: Vector2 = torso_xf * Vector2(-2.0, -16.5)
	var lift := float(pose.cape)
	var flutter := float(pose.flutter)
	var base_a := lerpf(PI * 0.62, PI * 0.95, clampf(lift, 0.0, 1.0))
	if lift < 0.0:
		base_a = lerpf(PI * 0.62, PI * 1.3, clampf(-lift, 0.0, 1.0))
	# Edges: `outer` runs down the back of the cape, `inner` down its face.
	var outer := PackedVector2Array([anchor])
	var inner := PackedVector2Array([anchor2])
	var joint := anchor + (anchor2 - anchor) * 0.5
	var widths := [8.0, 7.0, 5.5]
	for i in range(3):
		var wav := sin(t * (7.0 + flutter * 5.0) - float(i) * 1.25) * (0.06 + 0.14 * flutter) * float(i + 1)
		var a := base_a + wav + float(i) * 0.1 * (1.0 - absf(lift))
		joint += Vector2(cos(a), sin(a)) * (9.0 + float(i) * 0.5)
		var n := Vector2(-sin(a), cos(a)) * float(widths[i]) * 0.5
		outer.append(joint + n)
		inner.append(joint - n)
	var tip_a := base_a + sin(t * 9.0) * 0.2 * flutter
	var cape_tip := joint + Vector2(cos(tip_a), sin(tip_a)) * 5.0
	# Drawn as triangles: a hard bend can fold a single strip polygon over itself,
	# which a triangle fan never does.
	for i in range(outer.size() - 1):
		_tri(ci, outer[i], outer[i + 1], inner[i + 1], cape_col)
		_tri(ci, outer[i], inner[i + 1], inner[i], cape_col)
	_tri(ci, outer[outer.size() - 1], cape_tip, inner[inner.size() - 1], cape_col)
	if not solid:
		# One darker fold along the inner edge keeps the strip reading as cloth.
		ci.draw_polyline(inner, Color(cape_col.darkened(0.35), 0.8), 1.2, true)
	# --- Back arm (behind the coat; carries the flask when drinking). ---
	var hand_b := sh_b + Vector2(cos(float(pose.arm_b)), sin(float(pose.arm_b))) * ARM_B
	ci.draw_colored_polygon(_strip(sh_b, hand_b, 4.5, 3.6), fc if solid else INK_ARM)
	ci.draw_circle(hand_b, 2.2, fc if solid else INK_ARM)
	# --- Legs: back leg darker, both behind the coat hem. ---
	var hip_b := HIP + Vector2(-3.5, 0.0)
	var hip_f := HIP + Vector2(3.5, 0.0)
	var lb := _leg(hip_b, float(pose.hip_b), float(pose.knee_b))
	var lf := _leg(hip_f, float(pose.hip_f), float(pose.knee_f))
	var back_ink: Color = fc if solid else INK_BACK
	var front_ink: Color = fc if solid else INK_FRONT
	for leg in [[lb, hip_b, back_ink], [lf, hip_f, front_ink]]:
		var l: Array = leg[0]
		var col: Color = leg[2]
		ci.draw_colored_polygon(_strip(leg[1], l[0], 8.0, 7.2), col)
		ci.draw_circle(l[0], 3.6, col)
		ci.draw_colored_polygon(_strip(l[0], l[1], 7.2, 6.0), col)
		ci.draw_colored_polygon(_boot(l[1], float(l[2])), col)
	# --- Coat, rim and sash. ---
	var coat := PackedVector2Array()
	for v in COAT:
		coat.append(torso_xf * (v as Vector2))
	if solid:
		ci.draw_colored_polygon(coat, fc)
	else:
		VFX.draw_shaded_polygon(ci, coat, coat_col, not bool(look.get("unshaded", false)))
		VFX.draw_rim(ci, coat, 1.0, 1.25 if flame_mode else 1.0)
		ci.draw_line(torso_xf * Vector2(-7.0, -13.0), torso_xf * Vector2(8.0, 13.0), Content.PAL.player_accent, 4.0, true)
	# --- Head: dark mask, rim, one eye, and the flame crown. ---
	ci.draw_circle(head, HEAD_R, fc if solid else MASK)
	var flame_amt := clampf(float(pose.flame), 0.0, 2.0)
	var lean := float(pose.lean_flame)
	var crown_col: Color = fc if solid else (VFX.GOLD if flame_mode else FLAME)
	var up := Vector2(0.0, -1.0).rotated(head_a)
	var side := Vector2(1.0, 0.0).rotated(head_a)
	if flame_amt > 0.02:
		for i in range(4):
			var fx := -9.0 + float(i) * 6.0
			var tip := (9.0 + sin(t * 10.0 + float(i) * 1.7) * 4.0) * flame_amt
			var base := head + side * fx + up * 4.0
			var drift := Vector2(-lean * (4.0 + float(i)) , 0.0)
			ci.draw_colored_polygon(PackedVector2Array([
				base - side * 4.0 * minf(1.0, flame_amt),
				head + side * fx + up * (tip + 7.0 * minf(1.0, flame_amt)) + drift,
				base + side * 4.0 * minf(1.0, flame_amt) - up * 1.0,
			]), crown_col)
		if not solid:
			# Inner gold tongues on the two centre flames: the crown's hot core.
			for i in [1, 2]:
				var fx := -9.0 + float(i) * 6.0
				var tip := (5.0 + sin(t * 13.0 + float(i) * 2.3) * 2.5) * flame_amt
				var base := head + side * fx + up * 5.0
				ci.draw_colored_polygon(PackedVector2Array([
					base - side * 2.0, head + side * fx + up * (tip + 7.0) + Vector2(-lean * 3.0, 0.0), base + side * 2.0,
				]), VFX.GOLD if not flame_mode else VFX.HOT)
	if not solid:
		VFX.draw_rim_circle(ci, head, HEAD_R, 1.0, 0.9)
		var blink := clampf(float(look.get("blink", 0.0)), 0.0, 1.0)
		var eye := head + side * 4.0 - up * 1.0
		if blink < 0.5:
			ci.draw_circle(eye, 2.8, EYE)
		else:
			ci.draw_line(eye - side * 2.6, eye + side * 2.6, EYE, 1.4, true)
	# --- Smear under the blade: the sweep the sword has actually travelled. ---
	if not smear.is_empty() and not solid:
		var o: Vector2 = sh_f + Vector2(2.0, 3.0)
		var r := float(smear.radius)
		# A faint wedge from the blade's reach out to the cut's reach, so the arc
		# reads as thrown by the sword rather than floating in front of it.
		arc_fill(ci, o, r * 0.42, r, float(smear.from), float(smear.to), Color(VFX.GOLD, 0.2))
		arc_smear(ci, o, r, float(smear.from), float(smear.to), 13.0 if bool(smear.get("heavy", false)) else 10.0, 1.0)
	# --- Flask in the back hand while drinking. ---
	if float(pose.flask) > 0.5 and not solid:
		var fpos := hand_b + Vector2(0.0, -3.0)
		ci.draw_rect(Rect2(fpos.x - 3.0, fpos.y - 4.0, 6.0, 8.0), Color(VFX.TEAL, 0.9))
		ci.draw_rect(Rect2(fpos.x - 1.5, fpos.y - 7.0, 3.0, 3.0), Color("8a6a3a"))
	# --- Sword arm and blade, frontmost. ---
	var arm_a := float(pose.arm_f)
	var hand := sh_f + Vector2(cos(arm_a), sin(arm_a)) * ARM_F
	var blade_a := arm_a + float(pose.sword)
	var bdir := Vector2(cos(blade_a), sin(blade_a))
	var bn := Vector2(-bdir.y, bdir.x)
	ci.draw_colored_polygon(_strip(sh_f, hand, 5.0, 4.0), fc if solid else INK_ARM)
	var steel: Color = fc if solid else (STEEL.lerp(VFX.GOLD, 0.45) if flame_mode else STEEL)
	var tip := hand + bdir * BLADE * float(pose.get("reach", 1.0))
	ci.draw_colored_polygon(PackedVector2Array([
		hand + bdir * 2.5 + bn * 1.9, tip - bdir * 4.0 + bn * 1.2, tip, tip - bdir * 4.0 - bn * 1.2, hand + bdir * 2.5 - bn * 1.9,
	]), steel)
	if not solid:
		ci.draw_line(hand + bdir * 4.0 + bn * 0.6, tip - bdir * 3.0 + bn * 0.3, Color(VFX.HOT, 0.55 if not flame_mode else 0.85), 1.0, true)
		if flame_mode:
			ci.draw_line(hand + bdir * 5.0, tip, Color(VFX.ORANGE, 0.5), 3.5, true)
	var guard_col: Color = fc if solid else HILT
	ci.draw_line(hand + bdir * 1.5 + bn * 5.0, hand + bdir * 1.5 - bn * 5.0, guard_col, 2.6, true)
	ci.draw_line(hand - bdir * 1.0, hand - bdir * 5.0, guard_col, 2.4, true)
	ci.draw_circle(hand - bdir * 5.5, 1.8, guard_col)
	ci.draw_circle(hand, 2.4, fc if solid else INK_ARM)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## A soft annular wedge between `r0` and `r1`, clear at the inner edge and
## `color` at the outer, swept from `a0` to `a1`.
static func arc_fill(ci: CanvasItem, origin: Vector2, r0: float, r1: float, a0: float, a1: float, color: Color) -> void:
	var sweep := a1 - a0
	if absf(sweep) < 0.05:
		return
	var segs := clampi(int(absf(sweep) * 6.0), 3, 16)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in range(segs + 1):
		var a := a0 + sweep * float(i) / float(segs)
		pts.append(origin + Vector2(cos(a), sin(a)) * r1)
		cols.append(Color(color, color.a * (0.35 + 0.65 * float(i) / float(segs))))
	for i in range(segs, -1, -1):
		var a := a0 + sweep * float(i) / float(segs)
		pts.append(origin + Vector2(cos(a), sin(a)) * r0)
		cols.append(Color(color, 0.0))
	ci.draw_polygon(pts, cols)

## A tapered crescent swept from angle `a0` to `a1` around `origin`: white-hot at
## the leading edge (a1), gold through the body, dissolving to ember at the tail.
static func arc_smear(ci: CanvasItem, origin: Vector2, radius: float, a0: float, a1: float, thickness: float, alpha: float) -> void:
	var sweep := a1 - a0
	if absf(sweep) < 0.05:
		return
	var segs := clampi(int(absf(sweep) * 8.0), 4, 22)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var oc := PackedColorArray()
	var ic := PackedColorArray()
	for i in range(segs + 1):
		var u := float(i) / float(segs)
		var a := a0 + sweep * u
		var w := maxf(1.2, thickness * (0.15 + 0.85 * u))
		var ray := Vector2(cos(a), sin(a))
		outer.append(origin + ray * radius)
		inner.append(origin + ray * (radius - w))
		var c: Color
		if u < 0.55:
			c = Color(VFX.EMBER, 0.0).lerp(VFX.GOLD, u / 0.55)
		else:
			c = VFX.GOLD.lerp(Color.WHITE, (u - 0.55) / 0.45)
		c.a *= alpha
		oc.append(c)
		ic.append(Color(c, c.a * 0.8))
	inner.reverse()
	ic.reverse()
	outer.append_array(inner)
	oc.append_array(ic)
	ci.draw_polygon(outer, oc)
