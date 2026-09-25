extends RefCounted
## The finale's cast, all procedural paper: the Warden's split costume, the
## burnt-out knight who knelt inside it and the crown it leaves on the floor,
## the knight's stand-in, the fallen that fold up out of the floor, their
## crowns, the hoard of flames, the streams that carry fire between them, what
## stands of the dais and the throne once the keep is gone, and the ash.
## The director (Finale) advances every actor from its own clock, so a test
## that steps the director steps the whole hall, and nothing here keeps a
## static or runs a _process of its own.

const VFX := preload("res://scripts/vfx.gd")
const KnightArt := preload("res://scripts/knight_art.gd")
const WardenArt := preload("res://scripts/warden_art.gd")
const Severed := preload("res://scripts/severed.gd")

## Held gestures, as pose keys laid over the knight's idle. They live here so
## the gameplay painter stays untouched. `raise` is the IGNITE gesture; `sit`
## lets the legs hang (ground 0) so the director can set the body on the seat.
const GESTURES := {
	"raise": { "arm_f": -1.9, "sword": -0.2, "arm_b": -1.2 + TAU, "head": -0.25, "torso": -0.12 },
	"thrust": { "arm_f": -0.55, "sword": -0.25, "torso": 0.18, "head": 0.05, "hip_f": 0.45, "knee_f": 0.35, "hip_b": -0.4, "knee_b": 0.1, "arm_b": 2.2 },
	"reach": { "torso": 0.75, "head": 0.35, "hip_f": 0.9, "knee_f": 1.2, "hip_b": -0.2, "knee_b": 0.9, "arm_f": 1.35, "sword": -0.35, "arm_b": 1.3 },
	"kneel": { "torso": 0.35, "head": 0.4, "hip_f": 1.45, "knee_f": 1.45, "hip_b": -0.15, "knee_b": 1.7, "arm_f": 1.35, "sword": 0.2, "arm_b": 1.6 },
	"sit": { "torso": -0.04, "head": 0.05, "hip_f": 1.5, "knee_f": 1.35, "hip_b": 1.35, "knee_b": 1.15, "arm_f": 0.7, "sword": 0.75, "arm_b": 1.3, "ground": 0.0 },
	"look_up": { "head": -0.5, "torso": -0.08 },
}
const THRONE_X := 640.0
## The dais is decor on a flat boss floor: three 14 px steps, 300/240/180 wide.
const STEP_H := 14.0
const STEP_HALF_WIDTHS := [150.0, 120.0, 90.0]
const EMBER_INK := Color("5e4b75")
## The Warden's own fire, which the knight's crown burns in once it sits.
const WARDEN_RED := Color("d42a3c")
const WARDEN_CORE := Color("ff7048")

## Feet height at x, counting the dais steps the feet stand over.
static func stage_floor(x: float) -> float:
	var y := Content.FLOOR_Y
	for half: float in STEP_HALF_WIDTHS:
		if absf(x - THRONE_X) < half:
			y -= STEP_H
	return y

## The knight's four-tongue crown with its two hot inner tongues, as a free
## flame: `base` is the tongues' base line (KnightArt.head_point), `amt` the
## flame size, `tilt` leans the whole crown. Every finale flame is drawn here,
## so reduced flash darkens fire here once (the WardenArt convention).
static func draw_crown(ci: CanvasItem, base: Vector2, size: float, amt: float, tilt: float, t: float, outer: Color, inner: Color) -> void:
	if amt <= 0.02:
		return
	if Feedback.flash_reduced:
		outer = outer.darkened(0.22)
		inner = inner.darkened(0.22)
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

## A knight's pose at rest with `gesture` laid over it.
static func held(gesture: String) -> Dictionary:
	return KnightArt.REST.merged(GESTURES[gesture], true)


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


## The knight's stand-in: takes the player's exact pose, then walks, climbs the
## dais, stoops for the crown, raises the blade, sits and looks up. Origin at
## the body centre, like the player, so the swap at the take-over is invisible.
class FinaleKnight extends Node2D:
	const G := preload("res://scripts/finale_actors.gd")
	var proxy := KnightProxy.new()
	var pose: Dictionary = {}
	var facing := 1.0
	## A GESTURES key held over the idle pose ("" for none) and the blend rate
	## toward it; a rate of 0 keeps the gameplay rates, as the walk needs.
	var gesture := ""
	var gesture_rate := 0.0
	## Flame size the crown settles toward; `gold` burns it in the Graveflame
	## colour, `red` (0..1) in the Warden's.
	var crown := 1.0
	var gold := false
	var red := 0.0
	## Off the floor (seated): the director places the body and the legs hang.
	var grounded := true
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

	## Stand at `x` at once (a dip-cut hides the jump).
	func place(x: float, face: float) -> void:
		position = Vector2(x, G.stage_floor(x) - KnightArt.FOOT_Y)
		facing = face
		grounded = true
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

	## The sword hand, where a lifted crown is held.
	func hand_point() -> Vector2:
		var shoulder: Vector2 = KnightArt.torso_xform(pose) * KnightArt.SHOULDER_F
		var hand := shoulder + Vector2.from_angle(float(pose.arm_f)) * KnightArt.ARM_F
		return position + KnightArt.body_xform(pose, facing) * hand

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
		if grounded:
			_settle_height(ground_before, dt)
		proxy.facing = facing
		var want: Dictionary = KnightArt.target(proxy)
		var target: Dictionary = want.pose
		var rate := float(want.rate)
		if not gesture.is_empty():
			target.merge(GESTURES[gesture], true)
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

	## The gameplay puppet; once the knight has taken the crown its own flame
	## crossfades into the Warden's red.
	func _draw() -> void:
		if grounded:
			VFX.draw_contact_shadow(self, Vector2(0.0, KnightArt.FOOT_Y + 1.0), 36.0, 8.0, 0.0)
		var t := G.flicker_t(proxy._anim_time)
		var look := pose
		if red > 0.0:
			look = pose.duplicate()
			look.flame = float(pose.flame) * (1.0 - red)
		KnightArt.paint(self, Vector2.ZERO, look, facing, {
			"coat": Content.PAL.player, "flame_mode": gold, "t": t,
			"blink": 1.0 if fmod(t, 3.7) > 3.58 else 0.0,
		})
		if red > 0.0:
			var tilt := (float(pose.torso) + float(pose.head)) * facing
			G.draw_crown(self, KnightArt.head_point(Vector2.ZERO, pose, facing), 1.0, float(pose.flame) * red, tilt, t, WARDEN_RED, WARDEN_CORE)


## The knight who won the throne before: found kneeling inside the Warden, in
## charred ink and ash (in the knight's own colours after a crown ending, for
## it was the knight who sat), its flame burned down to the spark its crown
## still holds. It crumbles to ash from the crown down.
class BurntKnight extends Node2D:
	const G := preload("res://scripts/finale_actors.gd")
	const ASH := Color("8c8088")
	const CHARRED := Color(0.5, 0.44, 0.47)
	## Discards the figure above a front that falls from the crown to the feet,
	## with an ember lip; under reduced motion it fades whole instead.
	const CRUMBLE := """
shader_type canvas_item;
uniform float progress = 0.0;
uniform float travel = 1.0;
uniform float rim_gain = 1.0;
varying vec2 local;
void vertex() { local = VERTEX; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float front = mix(-46.0, 32.0, progress) + (hash(floor(local * 0.7)) - 0.5) * 9.0;
	float past = local.y - front;
	if (travel > 0.5 && past < 0.0) discard;
	float lip = travel * rim_gain * (1.0 - smoothstep(0.0, 4.0, past));
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0, 0.45, 0.12), lip);
	COLOR.a *= mix(1.0 - progress, 1.0, travel);
}
"""
	var pose: Dictionary = G.held("kneel")
	var facing := 1.0
	var ours := false
	var crumble := 0.0:
		set(value):
			crumble = value
			(material as ShaderMaterial).set_shader_parameter("progress", value)

	func _init() -> void:
		var shader := Shader.new()
		shader.code = CRUMBLE
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("travel", 0.0 if Feedback.motion_reduced else 1.0)
		mat.set_shader_parameter("rim_gain", 0.6 if Feedback.flash_reduced else 1.0)
		material = mat
		pose.flame = 0.0
		pose.flutter = 0.0

	## Kneels at `x` on the floor (or the dais step there), facing `face`.
	func setup(x: float, face: float, in_our_colours: bool) -> void:
		position = Vector2(x, G.stage_floor(x) - KnightArt.FOOT_Y)
		facing = face
		ours = in_our_colours
		self_modulate = Color.WHITE if ours else CHARRED

	## Where its crown sits.
	func crown_point() -> Vector2:
		return position + KnightArt.head_point(Vector2.ZERO, pose, facing)

	func advance(_dt: float) -> void:
		pass

	func _draw() -> void:
		VFX.draw_contact_shadow(self, Vector2(0.0, KnightArt.FOOT_Y + 1.0), 40.0, 8.0, 0.0)
		KnightArt.paint(self, Vector2.ZERO, pose, facing, { "coat": Content.PAL.player if ours else ASH, "blink": 1.0 })


## The four-tongue crown the burnt-out knight wore: charred tongues on a band,
## a flame burned down to a spark (`burn`). It outlasts its wearer on the floor,
## cracks (`crack`) to let the hoard out, and is what the throne offers.
## `position` is the band's base line.
class RelicCrown extends Node2D:
	const G := preload("res://scripts/finale_actors.gd")
	const IRON := Color("2a1f2c")
	var burn := 0.3
	var crack := 0.0
	var tilt := 0.0
	var _t := 0.0

	func _ready() -> void:
		material = VFX.unshaded_material()

	func advance(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var t := G.flicker_t(_t)
		draw_set_transform(Vector2.ZERO, tilt)
		var ember := Color(VFX.EMBER, 0.5 + 0.5 * burn)
		draw_rect(Rect2(-11.0, -3.0, 22.0, 4.0), IRON)
		for i in range(4):
			var x := -9.0 + float(i) * 6.0
			var h := 9.0 + float(i % 2) * 3.0
			var tongue := PackedVector2Array([Vector2(x - 3.0, -3.0), Vector2(x + 0.5, -3.0 - h), Vector2(x + 3.0, -3.0)])
			draw_colored_polygon(tongue, IRON)
			draw_polyline(PackedVector2Array([tongue[0], tongue[1], tongue[2]]), ember, 0.8, true)
		G.draw_crown(self, Vector2(0.0, -3.0), 0.8, burn, 0.0, t, Color(KnightArt.FLAME, 0.85), Color(VFX.GOLD, 0.85))
		if crack > 0.0:
			var seam := PackedVector2Array([Vector2(1.0, 1.0), Vector2(-1.5, -4.0), Vector2(1.0, -8.0), Vector2(-0.5, -14.0)])
			draw_polyline(seam, Color(VFX.HOT, crack), 1.0 + 1.5 * crack, true)
		draw_set_transform(Vector2.ZERO)


## The Warden split open like a paper costume: two halves hinged at the feet
## tip away outward (`open` 0..1), each clipped along the seam by Severed's
## half-plane mask with a singed cut edge, and drop out of sight once flat.
## Under reduced motion the halves stay put and simply fade.
class WardenShell extends Node2D:
	const FEET := 58.0
	var open := 0.0
	var _hinges: Array[Node2D] = []
	var _edges: Array = []

	## `boss_pose` is the Warden's pose as it split; its crown has gone with the
	## knight inside, so the costume keeps only charred stubs.
	func setup(boss_pose: Dictionary, face: float, anim_t: float) -> void:
		var frozen := boss_pose.duplicate()
		frozen["jitter"] = Vector2.ZERO
		frozen["spent"] = true
		for side: float in [-1.0, 1.0]:
			var hinge := Node2D.new()
			hinge.position = Vector2(side * 46.0, FEET)
			var mask := Severed.HalfMask.new()
			mask.normal = Vector2(side, 0.0)
			mask.position = -hinge.position
			var puppet := WardenPuppet.new()
			puppet.frozen = frozen
			puppet.facing = face
			puppet._anim_t = anim_t
			mask.add_child(puppet)
			var edge := Severed.CutEdge.new()
			edge.tangent = Vector2.UP
			edge.reach = 80.0
			edge.position = Vector2(0.0, -14.0)
			mask.add_child(edge)
			hinge.add_child(mask)
			add_child(hinge)
			_hinges.append(hinge)
			_edges.append(edge)

	func advance(dt: float) -> void:
		for i in range(_hinges.size()):
			var side := -1.0 if i == 0 else 1.0
			_hinges[i].rotation = 0.0 if Feedback.motion_reduced else side * 1.5 * open
			var edge: Severed.CutEdge = _edges[i]
			edge.heat = maxf(0.0, edge.heat - dt / 1.2)
			edge.queue_redraw()


## The Boss fields WardenArt.pose() and paint() read, held still in the pose
## the Warden split in: no hurt flash, off the floor (which fades the contact
## shadow).
class WardenPuppet extends Node2D:
	var frozen: Dictionary = {}
	var _anim_t := 0.0
	var facing := -1.0
	var _hurt_flash := 0.0
	var velocity := Vector2.ZERO
	var action_idx := 0
	var _air_time := 1.0

	func is_on_floor() -> bool:
		return false

	func _draw() -> void:
		WardenArt.paint(self, frozen)


## A black paper knight that hinges up out of the floor like a pop-up-book
## page. Origin at the feet; the hinge is the node's own scale and skew, so the
## body only repaints while its pose (a kneel) is still moving.
class FinaleFallen extends Node2D:
	const BEVEL := Color("5a3040")
	const INK := Color("140d1a")
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

	## Stands at a station with seeded variation, turned toward the throne.
	func setup(station: Dictionary, seed: int) -> void:
		position = Vector2(float(station.x), Content.FLOOR_Y)
		size = float(station.scale) * lerpf(0.93, 1.05, VFX.hash01(seed, 301))
		facing = signf(THRONE_X - position.x)
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

	func crown_point() -> Vector2:
		return transform * KnightArt.head_point(_body_origin(), pose, facing, size)

	## Where the crown will sit once the page stands fully up.
	func crown_at_rest() -> Vector2:
		return position + KnightArt.head_point(_body_origin(), _rest, facing, size)

	func advance(dt: float) -> void:
		var target := _rest if gesture.is_empty() else _rest.merged(GESTURES[gesture], true)
		for key in target:
			if absf(float(pose[key]) - float(target[key])) > 0.002:
				pose = KnightArt.blend(pose, target, 6.0, dt)
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
## between the two.
class CrownField extends Node2D:
	const G := preload("res://scripts/finale_actors.gd")
	var fallen: Array = []
	## Per fallen: -1 no crown, 1 burning, 0 a charred stub.
	var _lit: Array[float] = []
	var _lit_to: Array[float] = []
	var _lit_rate: Array[float] = []
	var _t := 0.0

	func add(f: Node2D) -> void:
		fallen.append(f)
		_lit.append(-1.0)
		_lit_to.append(-1.0)
		_lit_rate.append(0.0)

	## Set a crown burning (1), charred (0) or gone (-1), crossfading over
	## `dur` seconds between burning and charred.
	func set_lit(i: int, value: float, dur: float = 0.0) -> void:
		if dur <= 0.0 or _lit[i] < 0.0 or value < 0.0:
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
		for i in range(fallen.size()):
			var f: Node2D = fallen[i]
			if _lit[i] < 0.0 or not is_instance_valid(f) or not f.visible:
				continue
			var fade := f.modulate.a
			var base: Vector2 = f.crown_point()
			var size: float = f.size * 0.9
			if _lit[i] < 1.0:
				_draw_stub(base, size, (1.0 - _lit[i]) * fade)
			G.draw_crown(self, base, size, _lit[i], 0.0, t + float(i), Color(KnightArt.FLAME, fade), Color(VFX.GOLD, fade))

	## What the throne left them: three charred stubs, ember-tipped.
	func _draw_stub(base: Vector2, size: float, alpha: float) -> void:
		for fx: float in [-6.0, 0.0, 6.0]:
			var foot := base + Vector2(fx * size, 0.0)
			draw_colored_polygon(PackedVector2Array([foot - Vector2(2.5 * size, 0.0), foot - Vector2(0.0, 5.0 * size), foot + Vector2(2.5 * size, 0.0)]), Color(EMBER_INK, alpha))
			draw_circle(foot - Vector2(0.0, 5.0 * size), 0.9 * size, Color(VFX.EMBER, 0.7 * alpha))


## The hoard: one flame for every knight the throne took, poured out of the
## cracked crown in a fountain that settles into a slow ring over the hall
## (`ring_center`, `ring_rx`, `ring_ry`, which the director tightens as the
## throne calls). From there each flame is sent on to wherever the ending
## takes it: home to its knight, into the throne, or up and out.
class HoardField extends Node2D:
	const G := preload("res://scripts/finale_actors.gd")
	var ring_center := Vector2(640.0, 300.0)
	var ring_rx := 300.0
	var ring_ry := 80.0
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

	## Pour `count` flames out of `from`, one every `stagger` seconds. Under
	## reduced motion each fades in at its ring slot instead of flying.
	func pour(from: Vector2, count: int, stagger: float) -> void:
		_count = count
		var still := Feedback.motion_reduced
		for i in range(count):
			var a := -PI * 0.5 + (VFX.hash01(i, 311) - 0.5) * 1.1
			_flames.append({
				"i": i, "mode": "wait", "wait": stagger * float(i), "age": 0.0, "alpha": 0.0,
				"pos": slot_point(i) if still else from,
				"vel": Vector2.from_angle(a) * lerpf(240.0, 380.0, VFX.hash01(i, 312)),
			})

	func count() -> int:
		return _flames.size()

	func slot_point(i: int) -> Vector2:
		var a := TAU * float(i) / float(maxi(_count, 1)) + _ring_t * 0.15
		return ring_center + Vector2(cos(a) * ring_rx, sin(a) * ring_ry)

	## Send flame i along an arc to `to` over `dur`, then call `on_land`; with
	## `fade` it thins away as it goes. Under reduced motion it fades out where
	## it hangs instead.
	func send(i: int, to: Vector2, dur: float, on_land: Callable = Callable(), fade: bool = false) -> void:
		for f in _flames:
			if int(f.i) == i:
				f.mode = "fade" if Feedback.motion_reduced else "send"
				f.from = f.pos
				f.to = to
				f.t = 0.0
				f.dur = dur
				f.thin = fade
				f.on_land = on_land

	func advance(dt: float) -> void:
		_t += dt
		if not Feedback.motion_reduced:
			_ring_t += dt
		var i := 0
		while i < _flames.size():
			var f: Dictionary = _flames[i]
			match str(f.mode):
				"wait":
					f.wait -= dt
					if f.wait <= 0.0:
						f.mode = "ring" if Feedback.motion_reduced else "burst"
						f.alpha = 0.0 if Feedback.motion_reduced else 1.0
				"burst":
					f.age += dt
					f.vel *= exp(-2.4 * dt)
					f.pos += f.vel * dt
					if f.age >= 0.7:
						f.mode = "ring"
				"ring":
					f.pos += (slot_point(int(f.i)) - f.pos) * (1.0 - exp(-2.0 * dt))
					f.alpha = minf(1.0, f.alpha + dt * 2.0)
				"send", "fade":
					f.t += dt
					var k := minf(1.0, float(f.t) / float(f.dur))
					var mid: Vector2 = (f.from + f.to) * 0.5 + Vector2(0.0, -60.0)
					if f.mode == "send":
						f.pos = (f.from as Vector2).bezier_interpolate(f.from.lerp(mid, 0.67), mid.lerp(f.to, 0.33), f.to, k)
					if f.mode == "fade" or f.thin:
						f.alpha = 1.0 - k * k
					if k >= 1.0:
						if (f.on_land as Callable).is_valid():
							(f.on_land as Callable).call()
						_flames.remove_at(i)
						continue
			i += 1
		queue_redraw()
		_halo.queue_redraw()

	func _bob(f: Dictionary) -> Vector2:
		if Feedback.motion_reduced or f.mode == "send":
			return Vector2.ZERO
		return Vector2(0.0, sin(_t * 2.4 + float(f.i) * 1.3) * 4.0)

	func _draw() -> void:
		var t := G.flicker_t(_t)
		for f in _flames:
			var a := float(f.alpha)
			G.draw_crown(self, f.pos + _bob(f), 0.9, 1.0, 0.0, t + float(f.i), Color(KnightArt.FLAME, a), Color(VFX.GOLD, a))

	func _draw_halo() -> void:
		var gain := 0.75 if Feedback.flash_reduced else 1.0
		for f in _flames:
			VFX.draw_radial(_halo, f.pos + _bob(f) + Vector2(0.0, -8.0), 30.0, Color(VFX.GOLD, 0.22 * float(f.alpha) * gain))


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


## What is left of the dais when the keep burns away: three paper boxes for
## the knight to stand on, under the open sky.
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


## The throne as its room paints it, on the actor layer: once END IT has put
## the keep out, the broken seat and its dais stay in the dawn.
class ThroneProxy extends Node2D:
	var room: Room

	func _draw() -> void:
		room.paint_throne(self, Vector2(THRONE_X, Content.FLOOR_Y), room.mood)


## Paper ash and cinders: 5-point scraps with a cooling ember edge that sway
## and flip as they rise. While `rate` > 0 they break off along the burn's
## front (a line at `front_y` across `bounds`); puff() sheds a handful where
## something crumbles. None at all under reduced motion.
class AshField extends Node2D:
	const MAX_FLAKES := 160
	const ASH := Color("2a2230")
	const SCRAP := [Vector2(-3.0, -2.0), Vector2(1.5, -3.2), Vector2(3.4, -0.4), Vector2(1.2, 2.8), Vector2(-2.6, 2.0)]
	var rate := 0.0
	var heat := 1.0
	var front_y := 0.0
	var bounds := Rect2()
	var _flakes: Array = []
	var _carry := 0.0
	var _seed := 0

	func count() -> int:
		return _flakes.size()

	## `n` scraps from around `pos`, within `spread`.
	func puff(pos: Vector2, n: int, spread: Vector2, puff_heat: float = 0.4) -> void:
		for i in range(n):
			_spawn(pos + Vector2(randf_range(-spread.x, spread.x), randf_range(-spread.y, spread.y)), puff_heat)

	func advance(dt: float) -> void:
		if Feedback.motion_reduced:
			_flakes.clear()
			queue_redraw()
			return
		_carry += rate * dt
		while _carry >= 1.0:
			_carry -= 1.0
			_spawn(Vector2(randf_range(bounds.position.x, bounds.end.x), front_y), heat)
		for f in _flakes:
			f.vel.y = move_toward(f.vel.y, f.rise, 90.0 * dt)
			f.phase += f.spin * dt
			f.pos += Vector2(f.vel.x + sin(f.phase * 0.7) * 20.0, f.vel.y) * dt
			f.heat = maxf(0.0, f.heat - dt / 1.6)
			f.life -= dt
		_flakes = _flakes.filter(func(f): return f.life > 0.0)
		queue_redraw()

	func _spawn(pos: Vector2, flake_heat: float) -> void:
		if _flakes.size() >= MAX_FLAKES:
			return
		_seed += 1
		_flakes.append({
			"pos": pos, "vel": Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 10.0)),
			"rise": -lerpf(40.0, 120.0, VFX.hash01(_seed, 321)), "phase": randf() * TAU,
			"spin": randf_range(2.0, 6.0), "size": randf_range(1.2, 2.6), "heat": flake_heat, "life": randf_range(2.2, 3.4),
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
