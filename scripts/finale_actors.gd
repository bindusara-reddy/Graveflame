extends RefCounted
## The finale's cast, all procedural paper: the knight's stand-in, the fallen
## that fold up out of the floor, their crowns, the hoard of flames, the streams
## that carry fire between heads, the mended Warden on its wires, the rostrum
## and the paper ash. The director (Finale) advances every actor from its own
## clock, so a test that steps the director steps the whole stage, and nothing
## here keeps a static or runs a _process of its own.

const VFX := preload("res://scripts/vfx.gd")
const KnightArt := preload("res://scripts/knight_art.gd")
const WardenArt := preload("res://scripts/warden_art.gd")

## Held gestures, as pose keys laid over the knight's idle. They live here so
## the gameplay painter stays untouched. `raise` is the IGNITE gesture.
const GESTURES := {
	"raise": { "arm_f": -1.9, "sword": -0.2, "arm_b": -1.2 + TAU, "head": -0.25, "torso": -0.12 },
	"thrust": { "arm_f": -0.55, "sword": -0.25, "torso": 0.18, "head": 0.05, "hip_f": 0.45, "knee_f": 0.35, "hip_b": -0.4, "knee_b": 0.1, "arm_b": 2.2 },
	"salute": { "arm_f": -1.4, "sword": -0.15 },
	"bow": { "torso": 0.5, "head": 0.3, "hip_f": 0.2, "sword": 0.9 },
	"knight_bow": { "torso": 0.5, "head": 0.3, "hip_f": 0.35, "knee_f": 0.3, "arm_f": 1.9, "sword": 1.1, "arm_b": 2.6 },
	"nod": { "head": 0.25, "torso": 0.15 },
}
const THRONE_X := 640.0
## The dais is decor on a flat boss floor: three 14 px steps, 300/240/180 wide.
const STEP_H := 14.0
const STEP_HALF_WIDTHS := [150.0, 120.0, 90.0]
const EMBER_INK := Color("5e4b75")

## Feet height at x, counting the dais steps the feet stand over.
static func stage_floor(x: float) -> float:
	var y := Content.FLOOR_Y
	for half: float in STEP_HALF_WIDTHS:
		if absf(x - THRONE_X) < half:
			y -= STEP_H
	return y

## The knight's four-tongue crown with its two hot inner tongues, as a free
## flame: `base` is the tongues' base line (KnightArt.head_point), `amt` the
## flame size, `tilt` leans the whole crown.
static func draw_crown(ci: CanvasItem, base: Vector2, size: float, amt: float, tilt: float, t: float, outer: Color, inner: Color) -> void:
	if amt <= 0.02:
		return
	var up := Vector2(0.0, -size).rotated(tilt)
	var side := Vector2(size, 0.0).rotated(tilt)
	var body := minf(1.0, amt)
	for i in range(4):
		var fx := -9.0 + float(i) * 6.0
		var tip := (9.0 + sin(t * 10.0 + float(i) * 1.7) * 4.0) * amt + 7.0 * body - 4.0
		var foot := base + side * fx
		ci.draw_colored_polygon(PackedVector2Array([foot - side * 4.0 * body, foot + up * tip, foot + side * 4.0 * body - up]), outer)
	for i in [1, 2]:
		var fx := -9.0 + float(i) * 6.0
		var tip := (5.0 + sin(t * 13.0 + float(i) * 2.3) * 2.5) * amt + 3.0
		var foot := base + side * fx + up
		ci.draw_colored_polygon(PackedVector2Array([foot - side * 2.0, foot + up * tip, foot + side * 2.0]), inner)

## Flicker clock that freezes under reduced motion (the title tableau's convention).
static func flicker_t(t: float) -> float:
	return 0.0 if Feedback.motion_reduced else t


## Fakes the Player fields KnightArt.target() reads, so the stand-in walks with
## the exact gameplay stride and idles with the same breath.
class KnightProxy extends RefCounted:
	var _anim_time := 0.0
	var velocity := Vector2.ZERO
	var facing := 1.0
	var state: int = Player.State.LOCOMOTION
	var _run_phase := 0.0
	var _land_squash := 0.0
	var wall_sliding := false
	var _flip_t := 0.0
	var _cast_t := 0.0
	var _ignite_t := 0.0
	var _heal_time := 0.0
	var _death_t := 0.0

	func is_on_floor() -> bool:
		return true


## The knight's stand-in: takes the player's exact pose, then walks the dais,
## raises the blade, thrusts, salutes and bows. Origin at the body centre, like
## the player, so the swap at the take-over is invisible.
class FinaleKnight extends Node2D:
	const G := preload("res://scripts/finale_actors.gd")
	var proxy := KnightProxy.new()
	var pose: Dictionary = {}
	var facing := 1.0
	## A GESTURES key held over the idle pose ("" for none) and the blend rate
	## toward it; a rate of 0 keeps the gameplay rates, as the walk needs.
	var gesture := ""
	var gesture_rate := 0.0
	## Flame size the crown settles toward; `gold` burns it in the Graveflame colour.
	var crown := 1.0
	var gold := false
	var _walk_x := 0.0
	var _walk_speed := 0.0
	var _walking := false
	var _face_after := 1.0
	var _on_arrive := Callable()
	var _fall_v := 0.0
	var _hop_t := 0.0
	var _hop_from := 0.0

	func setup(player: Player, burns_gold: bool) -> void:
		position = player.global_position
		facing = player.facing
		pose = player._pose.duplicate() if not player._pose.is_empty() else KnightArt.REST.duplicate()
		proxy._run_phase = player._run_phase
		proxy._anim_time = player._anim_time
		gold = burns_gold

	## Walk to `x` at `speed`, then face `face` and call `on_arrive`.
	func walk(x: float, speed: float, face: float, on_arrive: Callable) -> void:
		_walk_x = x
		_walk_speed = speed
		_face_after = face
		_on_arrive = on_arrive
		_walking = true

	## Stand at `x` on the dais at once (a dip-cut hides the jump).
	func place(x: float, face: float) -> void:
		position = Vector2(x, G.stage_floor(x) - KnightArt.FOOT_Y)
		facing = face
		_walking = false
		_fall_v = 0.0
		_hop_t = 0.0

	func gesture_to(name: String, rate: float = 12.0) -> void:
		gesture = name
		gesture_rate = rate

	func head_point() -> Vector2:
		return KnightArt.head_point(position, pose, facing)

	func blade_tip() -> Vector2:
		return KnightArt.blade_tip(position, pose, facing)

	func advance(dt: float) -> void:
		proxy._anim_time += dt
		proxy._land_squash = maxf(0.0, proxy._land_squash - dt)
		proxy.velocity.x = 0.0
		var ground_before := G.stage_floor(position.x)
		if _walking:
			var dir := signf(_walk_x - position.x)
			var travel := minf(absf(_walk_x - position.x), _walk_speed * dt)
			position.x += dir * travel
			facing = dir if dir != 0.0 else facing
			proxy.velocity.x = dir * _walk_speed
			proxy._run_phase = fmod(proxy._run_phase + travel / Player.STRIDE * TAU, TAU)
			if absf(_walk_x - position.x) < 0.01:
				_walking = false
				facing = _face_after
				_on_arrive.call()
		_settle_height(ground_before, dt)
		proxy.facing = facing
		var want: Dictionary = KnightArt.target(proxy)
		var target: Dictionary = want.pose
		var rate := float(want.rate)
		if not gesture.is_empty():
			var held: Dictionary = GESTURES[gesture]
			for key in held:
				target[key] = held[key]
		if gesture_rate > 0.0:
			rate = gesture_rate
		target.flame = crown
		pose = KnightArt.blend(pose, target, rate, dt)
		queue_redraw()

	## Falls to the floor if it took over in the air, and hops each dais step:
	## the dais is decor, so the steps are only ever visual.
	func _settle_height(ground_before: float, dt: float) -> void:
		var rest_y := G.stage_floor(position.x) - KnightArt.FOOT_Y
		if G.stage_floor(position.x) != ground_before and _fall_v == 0.0:
			_hop_t = 0.1
			_hop_from = position.y
		if _hop_t > 0.0:
			_hop_t = maxf(0.0, _hop_t - dt)
			var k := 1.0 - _hop_t / 0.1
			position.y = lerpf(_hop_from, rest_y, k) - sin(k * PI) * 5.0
			if _hop_t == 0.0:
				proxy._land_squash = 0.12
		elif position.y < rest_y - 0.5:
			_fall_v += Content.GRAVITY * dt
			position.y = minf(rest_y, position.y + _fall_v * dt)
			if position.y >= rest_y:
				_fall_v = 0.0
				proxy._land_squash = 0.12
		else:
			position.y = rest_y

	func _draw() -> void:
		VFX.draw_contact_shadow(self, Vector2(0.0, KnightArt.FOOT_Y + 1.0), 36.0, 8.0, 0.0)
		var t := G.flicker_t(proxy._anim_time)
		KnightArt.paint(self, Vector2.ZERO, pose, facing, {
			"coat": Content.PAL.player, "flame_mode": gold, "t": t,
			"blink": 1.0 if fmod(t, 3.7) > 3.58 else 0.0,
		})


## A black paper knight that hinges up out of the floor like a pop-up-book
## page. Origin at the feet; the hinge is the node's own scale and skew, so the
## body only repaints while its pose (a bow) is still moving.
class FinaleFallen extends Node2D:
	const BEVEL := Color("5a3040")
	const INK := Color("140d1a")
	const ELDER_INK := Color("3a3346")
	const TAB := Color("c9b99a")
	var ink := INK
	var bevel := BEVEL
	var size := 1.0
	var facing := 1.0
	var pose: Dictionary = {}
	var gesture := ""
	var hinge := 0.0:
		set(h):
			hinge = h
			scale = Vector2(1.0, maxf(h, 0.02))
			skew = (1.0 - clampf(h, 0.0, 1.0)) * 0.35
	var _rest: Dictionary = {}
	var _gesture_t := 0.0

	## Stands at a station with seeded variation, turned toward the throne.
	func setup(station: Dictionary, seed: int, elder: bool) -> void:
		position = Vector2(float(station.x), Content.FLOOR_Y)
		size = float(station.scale) * lerpf(0.93, 1.05, VFX.hash01(seed, 301))
		facing = signf(THRONE_X - position.x)
		ink = ELDER_INK if elder else INK
		bevel = ink.lightened(0.2) if elder else BEVEL
		if bool(station.back):
			ink = ink.darkened(0.35)
			bevel = bevel.darkened(0.35)
		_rest = KnightArt.REST.duplicate()
		_rest.arm_f = lerpf(1.3, 1.7, VFX.hash01(seed, 302))
		_rest.sword = lerpf(-0.3, 0.4, VFX.hash01(seed, 303))
		_rest.flame = 0.0
		_rest.flutter = 0.1
		pose = _rest.duplicate()
		hinge = 0.0

	## Hold a gesture ("bow", "nod") for `hold` seconds, then rise.
	func bow(name: String, hold: float) -> void:
		gesture = name
		_gesture_t = hold

	func crown_point() -> Vector2:
		return transform * KnightArt.head_point(_body_origin(), pose, facing, size)

	## Where the crown will sit once the page stands fully up.
	func crown_at_rest() -> Vector2:
		return position + KnightArt.head_point(_body_origin(), _rest, facing, size)

	func advance(dt: float) -> void:
		if _gesture_t > 0.0:
			_gesture_t -= dt
			if _gesture_t <= 0.0:
				gesture = ""
		var target := _rest.duplicate()
		if not gesture.is_empty():
			var held: Dictionary = GESTURES[gesture]
			for key in held:
				target[key] = held[key]
		for key in target:
			if absf(float(pose[key]) - float(target[key])) > 0.002:
				pose = KnightArt.blend(pose, target, 8.0, dt)
				queue_redraw()
				return

	func _body_origin() -> Vector2:
		return Vector2(0.0, -KnightArt.FOOT_Y * size)

	func _draw() -> void:
		var origin := _body_origin()
		KnightArt.paint(self, origin + Vector2(1.4, -1.4), pose, facing, { "flat": bevel, "scale": size })
		KnightArt.paint(self, origin, pose, facing, { "flat": ink, "scale": size })
		# The pop-up tab: a pale fold line where the page meets the floor.
		draw_line(Vector2(-11.0 * size, 0.0), Vector2(11.0 * size, 0.0), Color(TAB, 0.55), 1.0)


## Every fallen's crown in one draw: burning, a charred stub, or crossfading
## between the two. `lean` tilts them all toward `lean_x`.
class CrownField extends Node2D:
	const G := preload("res://scripts/finale_actors.gd")
	var fallen: Array = []
	var elder := false
	var lean := 0.0
	var lean_x := 640.0
	## Per fallen: -1 no crown yet, 1 burning, 0 a charred stub.
	var _lit: Array[float] = []
	var _lit_to: Array[float] = []
	var _lit_rate: Array[float] = []
	var _t := 0.0

	func add(f: Node2D) -> void:
		fallen.append(f)
		_lit.append(-1.0)
		_lit_to.append(-1.0)
		_lit_rate.append(0.0)

	## Set a crown burning (1) or charred (0), crossfading over `dur` seconds.
	func set_lit(i: int, value: float, dur: float = 0.0) -> void:
		if dur <= 0.0 or _lit[i] < 0.0:
			_lit[i] = value
		_lit_to[i] = value
		_lit_rate[i] = 1.0 / maxf(dur, 0.001)

	func lit(i: int) -> float:
		return _lit[i]

	func advance(dt: float) -> void:
		_t += dt
		for i in range(_lit.size()):
			_lit[i] = move_toward(_lit[i], _lit_to[i], _lit_rate[i] * dt)
		queue_redraw()

	func _draw() -> void:
		var t := G.flicker_t(_t)
		var outer := Color(VFX.GOLD, 0.8) if elder else KnightArt.FLAME
		var inner := Color(VFX.HOT, 0.8) if elder else VFX.GOLD
		for i in range(fallen.size()):
			var f: Node2D = fallen[i]
			if _lit[i] < 0.0 or not is_instance_valid(f) or not f.visible:
				continue
			var fade := f.modulate.a
			var base: Vector2 = f.crown_point()
			var tilt := lean * clampf((lean_x - base.x) / 240.0, -1.0, 1.0) * 0.5
			var size: float = f.size * 0.9
			if _lit[i] < 1.0:
				_draw_stub(base, size, tilt, (1.0 - _lit[i]) * fade)
			G.draw_crown(self, base, size, _lit[i], tilt, t + float(i), Color(outer, outer.a * fade), Color(inner, inner.a * fade))

	## What is left once the flame is lent: three charred stubs, ember-tipped.
	func _draw_stub(base: Vector2, size: float, tilt: float, alpha: float) -> void:
		var up := Vector2(0.0, -size).rotated(tilt)
		var side := Vector2(size, 0.0).rotated(tilt)
		for fx: float in [-6.0, 0.0, 6.0]:
			var foot := base + side * fx
			draw_colored_polygon(PackedVector2Array([foot - side * 2.5, foot + up * 5.0, foot + side * 2.5]), Color(EMBER_INK, alpha))
			draw_circle(foot + up * 5.0, 0.9 * size, Color(VFX.EMBER, 0.7 * alpha))


## The Warden's hoard: one flame per knight it took, burst loose at the shatter,
## drawn into a slow ring over the throne, then sent down one by one to crown
## the fallen. It also carries the final flame that rises from under the curtain.
class HoardField extends Node2D:
	const G := preload("res://scripts/finale_actors.gd")
	const RING_CENTER := Vector2(640.0, 300.0)
	const RING_RX := 300.0
	const RING_RY := 80.0
	var elder := false
	var released := false
	## The last flame: rises on the resolving D, then blooms into the results.
	var ember_pos := Vector2(640.0, 600.0)
	var ember_alpha := 0.0
	var halo_radius := 90.0
	var halo_alpha := 0.0
	var _flames: Array = []
	var _count := 0
	var _ring_t := 0.0
	var _t := 0.0
	var _halo: Node2D

	func _ready() -> void:
		material = VFX.unshaded_material()
		_halo = Node2D.new()
		_halo.material = VFX.radial_material()
		_halo.show_behind_parent = true
		_halo.draw.connect(_draw_halo)
		add_child(_halo)

	## Burst `count` flames from `pos`. Under reduced motion they fade in at
	## their ring slots instead of flying.
	func release(pos: Vector2, count: int) -> void:
		released = true
		_count = count
		for i in range(count):
			var a := VFX.hash01(i, 311) * TAU
			var still := Feedback.motion_reduced
			_flames.append({
				"i": i, "mode": "ring" if still else "burst", "alpha": 0.0 if still else 1.0,
				"pos": slot_point(i) if still else pos,
				"vel": Vector2(cos(a), sin(a)) * lerpf(180.0, 320.0, VFX.hash01(i, 312)),
			})

	func gather_to_ring() -> void:
		for f in _flames:
			f.mode = "ring"

	func slot_point(i: int) -> Vector2:
		var a := TAU * float(i) / float(maxi(_count, 1)) + _ring_t * 0.15
		return RING_CENTER + Vector2(cos(a) * RING_RX, sin(a) * RING_RY)

	## Send flame i down a bezier arc to `to` over `dur`, then call `on_land`.
	## Under reduced motion it fades out where it hangs instead.
	func descend(i: int, to: Vector2, dur: float, on_land: Callable) -> void:
		for f in _flames:
			if int(f.i) == i:
				f.mode = "fade" if Feedback.motion_reduced else "descend"
				f.from = f.pos
				f.to = to
				f.t = 0.0
				f.dur = dur
				f.on_land = on_land

	func advance(dt: float) -> void:
		_t += dt
		if not Feedback.motion_reduced:
			_ring_t += dt
		var i := 0
		while i < _flames.size():
			var f: Dictionary = _flames[i]
			match str(f.mode):
				"burst":
					f.vel *= exp(-2.2 * dt)
					f.pos += f.vel * dt
				"ring":
					f.pos += (slot_point(int(f.i)) - f.pos) * (1.0 - exp(-2.0 * dt))
					f.alpha = minf(1.0, f.alpha + dt * 2.0)
				"descend", "fade":
					f.t += dt
					var k := minf(1.0, float(f.t) / float(f.dur))
					var mid: Vector2 = (f.from + f.to) * 0.5 + Vector2(0.0, -60.0)
					if f.mode == "descend":
						f.pos = (f.from as Vector2).bezier_interpolate(f.from.lerp(mid, 0.67), mid.lerp(f.to, 0.33), f.to, k)
					else:
						f.alpha = 1.0 - k
					if k >= 1.0:
						(f.on_land as Callable).call()
						_flames.remove_at(i)
						continue
			i += 1
		queue_redraw()
		_halo.queue_redraw()

	func _bob(f: Dictionary) -> Vector2:
		if Feedback.motion_reduced or f.mode == "descend":
			return Vector2.ZERO
		return Vector2(0.0, sin(_t * 2.4 + float(f.i) * 1.3) * 4.0)

	func _draw() -> void:
		var t := G.flicker_t(_t)
		var outer := VFX.GOLD if elder else KnightArt.FLAME
		var inner := VFX.HOT if elder else VFX.GOLD
		var alpha := 0.8 if elder else 1.0
		for f in _flames:
			var a := alpha * float(f.alpha)
			G.draw_crown(self, f.pos + _bob(f), 0.9, 1.0, 0.0, t + float(f.i), Color(outer, a), Color(inner, a))
		if ember_alpha > 0.0:
			G.draw_crown(self, ember_pos, 2.2, 1.0, 0.0, t, Color(VFX.GOLD, ember_alpha), Color(VFX.HOT, ember_alpha))

	func _draw_halo() -> void:
		var gain := 0.75 if Feedback.flash_reduced else 1.0
		for f in _flames:
			VFX.draw_radial(_halo, f.pos + _bob(f) + Vector2(0.0, -8.0), 30.0, Color(VFX.GOLD, 0.22 * float(f.alpha) * gain))
		VFX.draw_radial(_halo, ember_pos + Vector2(0.0, -16.0), halo_radius, Color(VFX.GOLD, halo_alpha * gain))


## Fire carried between heads: each stream a bezier arc with a tapered trail
## (gold at the head, ember at the tail). Under reduced motion streams are not
## drawn; the crowns crossfade instead and only the timing is kept.
class FlameStream extends Node2D:
	const G := preload("res://scripts/finale_actors.gd")
	const TRAIL := 10
	var _streams: Array = []
	var _t := 0.0

	func _ready() -> void:
		material = VFX.unshaded_material()

	## `from` and `to` are Callables returning points, so a stream follows a
	## head that is still moving. `arc` lifts the path's middle.
	func launch(from: Callable, to: Callable, dur: float, on_arrive: Callable, arc: float = 90.0) -> void:
		_streams.append({ "from": from, "to": to, "t": 0.0, "dur": dur, "arc": arc, "on_arrive": on_arrive, "trail": PackedVector2Array() })

	func busy() -> bool:
		return not _streams.is_empty()

	func advance(dt: float) -> void:
		_t += dt
		var i := 0
		while i < _streams.size():
			var s: Dictionary = _streams[i]
			s.t += dt
			var k := minf(1.0, float(s.t) / float(s.dur))
			var a: Vector2 = (s.from as Callable).call()
			var b: Vector2 = (s.to as Callable).call()
			var lift := Vector2(0.0, -float(s.arc) * 4.0 / 3.0)
			var p := a.bezier_interpolate(a.lerp(b, 0.25) + lift, a.lerp(b, 0.75) + lift, b, k)
			var trail: PackedVector2Array = s.trail
			trail.append(p)
			if trail.size() > TRAIL:
				trail.remove_at(0)
			s.trail = trail
			if k >= 1.0:
				_streams.remove_at(i)
				if (s.on_arrive as Callable).is_valid():
					(s.on_arrive as Callable).call()
				continue
			i += 1
		queue_redraw()

	func _draw() -> void:
		if Feedback.motion_reduced:
			return
		for s in _streams:
			var trail: PackedVector2Array = s.trail
			for j in range(1, trail.size()):
				var u := float(j) / float(TRAIL)
				draw_line(trail[j - 1], trail[j], VFX.EMBER.lerp(VFX.GOLD, u), 1.0 + 4.0 * u, true)
			if not trail.is_empty():
				G.draw_crown(self, trail[trail.size() - 1], 0.8, 1.0, 0.0, G.flicker_t(_t), KnightArt.FLAME, VFX.GOLD)


## The Warden lowered on two wires as a mended paper puppet. This node is the
## pivot at the feet (bows and the Oath fold turn about it) and draws the wires;
## the puppet child is the duck-typed Boss host that WardenArt paints.
class FinaleWarden extends Node2D:
	const WIRE := Color("8a7a5a")
	const FEET := 58.0
	var facing := -1.0:
		set(v):
			facing = v
			if puppet != null:
				puppet.facing = v
	## 0..1 of a stiff bow about the feet; `swing` is a decaying pendulum.
	var bow := 0.0
	var swing := 0.0
	var wires := true
	var puppet: WardenPuppet
	var _t := 0.0

	func _init() -> void:
		puppet = WardenPuppet.new()
		puppet.position = Vector2(0.0, -FEET)
		puppet.facing = facing
		add_child(puppet)

	func advance(dt: float) -> void:
		_t += dt
		swing *= exp(-1.3 * dt)
		var wobble := sin(_t * 18.0) * 0.01 * bow
		rotation = (bow * 0.38 + wobble + swing * sin(_t * 3.4)) * facing
		puppet._anim_t += dt
		puppet.queue_redraw()
		queue_redraw()

	func _draw() -> void:
		if not wires:
			return
		for sx: float in [-26.0, 24.0]:
			var shoulder := puppet.position + Vector2(sx * facing, -36.0)
			var anchor := get_transform().affine_inverse() * Vector2(position.x + sx * facing, -1000.0)
			draw_line(shoulder, anchor, WIRE, 1.2, true)


## The Boss fields WardenArt.pose() and paint() read, held still: no windup,
## no hurt flash, off the floor (which fades the contact shadow), and painted
## mended and spent.
class WardenPuppet extends Node2D:
	var _anim_t := 0.0
	var facing := -1.0
	var _hurt_flash := 0.0
	var velocity := Vector2.ZERO
	var state: int = Enemy.EState.SEEK
	var st_timer := 0.0
	var data := { "windup": 0.5 }
	var action_idx := 0
	var phase := 1
	var _air_time := 1.0

	func is_on_floor() -> bool:
		return false

	func _draw() -> void:
		var p := WardenArt.pose(self)
		p["mended"] = true
		p["spent"] = true
		WardenArt.paint(self, p)


## The dais without its keep: three plain paper boxes the knight stands on once
## the set has burned away.
class Rostrum extends Node2D:
	const PAPER := Color("2c2336")

	func _draw() -> void:
		for i in range(STEP_HALF_WIDTHS.size()):
			var half: float = STEP_HALF_WIDTHS[i]
			var top := Content.FLOOR_Y - STEP_H * float(i + 1)
			var box := Rect2(THRONE_X - half, top, half * 2.0, STEP_H)
			draw_rect(Rect2(box.position + Vector2(2.0, 2.0), box.size), Color(VFX.VOID, 0.7))
			draw_rect(box, PAPER.lightened(0.06 * float(i)))
			draw_line(box.position, Vector2(box.end.x, box.position.y), Color(VFX.GOLD, 0.45), 1.5)


## Paper ash and cinders lifting off the burning set: 5-point scraps with a
## cooling ember edge that sway and flip as they rise. Spawned on the burn's
## front while `rate` > 0; none at all under reduced motion.
class AshField extends Node2D:
	const MAX_FLAKES := 160
	const ASH := Color("2a2230")
	const SCRAP := [Vector2(-3.0, -2.0), Vector2(1.5, -3.2), Vector2(3.4, -0.4), Vector2(1.2, 2.8), Vector2(-2.6, 2.0)]
	var rate := 0.0
	var front_center := Vector2.ZERO
	var front_radius := 0.0
	var bounds := Rect2()
	var _flakes: Array = []
	var _carry := 0.0
	var _seed := 0

	func count() -> int:
		return _flakes.size()

	## A burst of dust, as when the Warden folds flat onto the boards.
	func puff(pos: Vector2, n: int) -> void:
		for i in range(n):
			_spawn(pos + Vector2(randf_range(-40.0, 40.0), randf_range(-6.0, 0.0)), 0.3)

	func advance(dt: float) -> void:
		if Feedback.motion_reduced:
			_flakes.clear()
			queue_redraw()
			return
		_carry += rate * dt
		while _carry >= 1.0:
			_carry -= 1.0
			var a := randf() * TAU
			var p := front_center + Vector2(cos(a), sin(a)) * front_radius
			if bounds.has_point(p):
				_spawn(p, 1.0)
		for f in _flakes:
			f.vel.y = move_toward(f.vel.y, f.rise, 90.0 * dt)
			f.phase += f.spin * dt
			f.pos += Vector2(f.vel.x + sin(f.phase * 0.7) * 20.0, f.vel.y) * dt
			f.heat = maxf(0.0, f.heat - dt / 1.6)
			f.life -= dt
		_flakes = _flakes.filter(func(f): return f.life > 0.0)
		queue_redraw()

	func _spawn(pos: Vector2, heat: float) -> void:
		if _flakes.size() >= MAX_FLAKES:
			return
		_seed += 1
		_flakes.append({
			"pos": pos, "vel": Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 10.0)),
			"rise": -lerpf(60.0, 140.0, VFX.hash01(_seed, 321)), "phase": randf() * TAU,
			"spin": randf_range(2.0, 6.0), "size": randf_range(1.2, 2.6), "heat": heat, "life": randf_range(2.2, 3.4),
		})

	func _draw() -> void:
		var scrap := PackedVector2Array(SCRAP)
		for f in _flakes:
			var fade := clampf(float(f.life) / 0.6, 0.0, 1.0)
			draw_set_transform(f.pos, 0.0, Vector2(cos(f.phase), 1.0) * float(f.size))
			draw_colored_polygon(scrap, Color(ASH, 0.85 * fade))
			var edge := scrap.duplicate()
			edge.append(scrap[0])
			draw_polyline(edge, Color(VFX.EMBER.lerp(VFX.GOLD, float(f.heat)), float(f.heat) * fade), 0.6)
		draw_set_transform(Vector2.ZERO)
