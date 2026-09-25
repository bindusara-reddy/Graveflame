class_name FinaleSky
extends Node2D
## The open night above the well: the last image of GIVE THEM BACK, and the
## grey dawn that ends END IT (story spec, beat 4).
##
## Once the knight has given every flame back, the keep burns off like paper
## from the top of the frame (burn_away_material() on the world's container)
## and this is what it was hiding: the ossuary well from the title, seen now
## from its floor. Its galleries climb and lean in toward a mouth open on the
## first chamber's sky, crescent moon and all. The fallen rise up the shaft as
## small paper flames (add_rising) and settle as a circlet of new stars round
## the moon; the knight stays below, its flame the last one lit. For END IT
## nothing burns: the fires go out and `dawn` spills thin grey light down the
## same shaft.
##
## Drawn in world units on a CanvasLayer below the world viewport. The director
## gives that layer the world camera's canvas transform, so the well floor is
## the throne room's floor (Content.FLOOR_Y) and the tilt up the shaft is just
## the camera climbing to well_top().
##
## Every piece paints once through a PaperMesh, one draw call each. `reveal`,
## `dawn` and `moon_glow` light the pieces by modulation, so only the dawn's
## leading edge, a star settling in and the risers in flight ever repaint: an
## idle sky never redraws. Reduced motion snaps each riser to its star and lets
## the dawn fade in place; reduced flash dims fire, the burn's rim and blooms.

const VFX := preload("res://scripts/vfx.gd")

## Burn-away for the world viewport's container: the painted keep chars like
## paper and falls away from the top of the frame, a ragged bowl-shaped front
## with a glowing ember rim, cut edges smouldering in the char behind it, then
## holes with hot lips opening onto the sky beneath. `origin` is where the fire
## catches (UV; just above the top edge by default); sideways distance counts
## for SPREAD of vertical, so the front runs across the frame almost at once
## and then falls. `travel` 0 (reduced motion) is a still dissolve with no
## moving rim; `rim_gain` dims the glow for reduced flash. The front's reach is
## measured to the farthest corner, so progress 1 always clears the frame.
const BURN_AWAY := """
shader_type canvas_item;
render_mode unshaded;

uniform float progress = 0.0;
uniform vec2 origin = vec2(0.5, -0.04);
uniform float aspect = 1.7778;
uniform float travel = 1.0;
uniform float rim_gain = 1.0;

const vec3 EMBER = vec3(1.0, 0.48, 0.12);
const vec3 HOT = vec3(1.0, 0.86, 0.55);
const vec3 CHAR = vec3(0.06, 0.035, 0.05);
const float RAGGED = 0.24;
const float LAG = 0.34;
const float SPREAD = 0.28;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; }
	return v;
}

// Distance from where the fire caught, with sideways distance squeezed.
float front_dist(vec2 uv) {
	return length((uv - origin) * vec2(aspect * SPREAD, 1.0));
}

// The burning band: paper scorches ahead of the front, chars with ember seams
// under a hot rim, then opens into holes with glowing lips. `ahead` is how far
// the unragged front has passed this point; `edge` is the painting's local contrast.
vec4 burn(vec4 world, float edge, vec2 p, float ahead) {
	float char_edge = ahead - fbm(p * 6.0) * RAGGED;
	float hole_edge = ahead - LAG - fbm(p * 9.0 + 3.1) * 0.2;
	float charred = mix(smoothstep(0.0, 0.35, progress), smoothstep(0.0, 0.01, char_edge), travel);
	float burned = mix(smoothstep(0.45, 1.0, progress), smoothstep(0.0, 0.006, hole_edge), travel);
	float glow = travel * rim_gain;
	float rim = exp(-abs(char_edge) * 70.0) * glow;
	float hole_rim = exp(-abs(hole_edge) * 90.0) * charred * glow;
	float scorch = smoothstep(-0.12, 0.0, char_edge) * (1.0 - charred) * travel;
	// Painted cut edges keep glowing inside the char, cooling behind the front.
	float seam = smoothstep(0.035, 0.12, edge) * rim_gain;
	float cool = mix(progress, clamp(char_edge * 6.0, 0.0, 1.0), travel);
	float lum = dot(world.rgb, vec3(0.3, 0.55, 0.15));
	vec3 charcoal = mix(CHAR * (0.7 + lum * 2.2), EMBER * 1.1, seam * (1.0 - cool * 0.7));
	float speck = step(0.78, fbm(p * 40.0 + progress * 3.0)) * charred * (1.0 - burned) * glow;
	vec3 col = mix(world.rgb, world.rgb * vec3(0.9, 0.62, 0.38) + vec3(0.08, 0.03, 0.0), scorch);
	col = mix(col, charcoal, charred);
	col = mix(col, EMBER, speck * 0.8);
	col = mix(col, EMBER, min(rim * 0.95, 1.0));
	col = mix(col, HOT, min(pow(rim, 3.0), 1.0));
	col = mix(col, EMBER, min(hole_rim * 0.9, 1.0));
	return vec4(col, world.a * max(1.0 - burned, min(hole_rim * 0.9, 1.0)));
}

void fragment() {
	vec2 p = UV * vec2(aspect, 1.0);
	float reach = max(max(front_dist(vec2(0.0)), front_dist(vec2(1.0, 0.0))), max(front_dist(vec2(0.0, 1.0)), front_dist(vec2(1.0)))) + RAGGED;
	float ahead = progress * (reach + LAG) - front_dist(UV);
	// Far from both travelling fronts nothing glows, so most of the frame skips the noise.
	if (travel > 0.5 && (ahead < -0.12 || ahead > LAG + 0.3)) {
		COLOR = ahead < 0.0 ? texture(TEXTURE, UV) : vec4(0.0);
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE * 1.5;
		float lx = dot(texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb - texture(TEXTURE, UV - vec2(px.x, 0.0)).rgb, vec3(0.33));
		float ly = dot(texture(TEXTURE, UV + vec2(0.0, px.y)).rgb - texture(TEXTURE, UV - vec2(0.0, px.y)).rgb, vec3(0.33));
		COLOR = burn(texture(TEXTURE, UV), length(vec2(lx, ly)), p, ahead);
	}
}
"""

# --- The well, in world units -----------------------------------------------------
## The shaft's axis is the throne's, so the knight stands under the mouth.
const CX := 640.0
const FLOOR_Y := Content.FLOOR_Y
## The floor's cut face, as deep as the game's own floor platforms.
const FLOOR_FACE := 120.0
## Where the shaft opens onto the sky.
const RIM_Y := -700.0
## The well is drawn from the knight's eye. Ledges above it sag toward the
## viewer by SAG per unit of height, showing their undersides; the floor's
## far edge, below it, arches the other way.
const EYE_Y := 470.0
const SAG := 0.11
## Interior half-width at the floor and at the rim: the walls lean in as they
## climb, the way a shaft converges when you look up it.
const HALF_FLOOR := 740.0
const HALF_RIM := 560.0
const LEVELS := 6
## How far each ledge juts: its unlit underside shows above the wall line.
const LEDGE := 24.0
## The first chamber's moon, hung over the mouth.
const MOON := Vector2(770.0, -960.0)
const MOON_R := 64.0
## Where the new stars ring the moon: a circlet, as wide as the halo's heart.
const CIRCLET := Vector2(150.0, 118.0)
## The point the camera tilts up to: the mouth below, the moon and its circlet above.
const TOP := Vector2(CX, -800.0)
## Painted extent: wide and tall enough for a pulled-back framing at any tilt.
const EXTENT := Rect2(-1700.0, -2300.0, 4680.0, 4000.0)
const STAR_BUCKETS := 8

# --- Palette: the title's well, lit from above by the moon, from below by the knight --
const SKY_HIGH := Color("03040a")
const SKY_TOP := Color("060812")
const SKY_MID := Color("0e1526")
const SKY_LOW := Color("172238")
const DAWN_HIGH := Color("23252d")
const DAWN_LOW := Color("7d8089")
const DAWN_LIGHT := Color(0.62, 0.64, 0.7)
const MOON_COL := Color("c9d2ee")
const STAR_COL := Color(0.85, 0.88, 1.0)
const WALL_WARM := Color("3a1a1c")
const WALL_COLD := Color("1c1a36")
const MOONLIT := Color("3a4264")
const SOFFIT := Color("09060e")
const UNDERGLOW := Color("552515")
const NICHE := Color("06040c")
const EFFIGY := Color("2a2140")
const EARTH := Color("08060d")
const EARTH_JOINT := Color("130e1c")
const FLOOR_TOP := Color("2a2230")
const FLOOR_LO := Color("0c0910")
const CHAR := Color("0d0910")
const EMBER_EDGE := Color(1.0, 0.45, 0.1)
const RISER_FLAME := Color("ff7a18")
const STAR_GOLD := Color("ffd98a")
## Light on the walls with the keep's fires out, and the grey of the dawn.
const DARK := Color(0.13, 0.12, 0.15)
const DAWN_TINT := Color(0.8, 0.82, 0.88)

# --- Risers ------------------------------------------------------------------------
## World units per second a flame climbs, and the bounds on a climb's length.
const RISE_SPEED := 270.0
const RISE_MIN := 4.0
const RISE_MAX := 7.5
## A settling star pops and blooms over this long.
const SETTLE_TIME := 0.9
## Trail samples behind a flame, each this fraction of its climb earlier.
const TRAIL := 14
const TRAIL_STEP := 0.012

## 0 the well stands dark (the keep's fires are out); 1 the night is fully
## out: moonlit walls, the crescent, every star. Stars prick out as it rises.
var reveal := 0.0:
	set(value):
		reveal = clampf(value, 0.0, 1.0)
		_light()
## 0..1 thin grey dawn spilling down the well from the mouth (END IT). It
## washes out the night: stars, moon and moonlight fade as it comes.
var dawn := 0.0:
	set(value):
		dawn = clampf(value, 0.0, 1.0)
		_light()
		_spill.queue_redraw()
## The moon's halo: 1 is the first chamber's, 2 twice as bright.
var moon_glow := 1.0:
	set(value):
		moon_glow = clampf(value, 0.0, 2.0)
		_light()
## Tests turn this off and call advance() themselves.
var autostep := true

var _rings: Array[Dictionary] = []
## Flames still to settle: {from, to, t (negative while waiting), dur, seed}.
var _flying: Array[Dictionary] = []
## Settled new stars: {p, age, seed}; `age` runs to SETTLE_TIME, then holds.
var _new_stars: Array[Dictionary] = []
var _risers_drawn := false
var _clock := 0.0

var _sky: Node2D
var _dawn_sky: Node2D
var _stars: Array[Node2D] = []
var _halo: Node2D
var _moon: Node2D
var _new_glow: Node2D
var _new_body: Node2D
var _well: Node2D
var _embers: Node2D
var _moonlight: Node2D
var _spill: Node2D
var _riser_glow: Node2D
var _risers: Node2D


func _init() -> void:
	name = "FinaleSky"
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(LEVELS + 1):
		var u := 1.0 - pow(1.0 - float(i) / LEVELS, 1.3)
		var y := lerpf(FLOOR_Y, RIM_Y, u)
		_rings.append({ "y": y, "w": half_width(y), "sag": SAG * (EYE_Y - y), "v": u })
	painter(self, _draw_void)
	_sky = painter(self, _draw_sky)
	_dawn_sky = painter(self, _draw_dawn_sky)
	for b in range(STAR_BUCKETS):
		_stars.append(painter(self, _draw_stars.bind(b)))
	_halo = painter(self, _draw_halo)
	_moon = painter(self, _draw_moon)
	_new_glow = painter(self, _draw_new_glow, VFX.radial_material())
	_new_body = painter(self, _draw_new_stars)
	_well = painter(self, _draw_well)
	_embers = painter(self, _draw_embers)
	_moonlight = painter(self, _draw_moonlight, VFX.radial_material())
	_spill = painter(self, _draw_spill, VFX.additive_material())
	_riser_glow = painter(self, _draw_riser_glow, VFX.radial_material())
	_risers = painter(self, _draw_risers)
	_light()
	set_process(false)


## The burn shader compiles once; every material made from it is new.
static var _burn_shader: Shader

## A fresh burn material for the world container. Never shared: each finale
## owns its uniforms.
static func burn_away_material() -> ShaderMaterial:
	if _burn_shader == null:
		_burn_shader = Shader.new()
		_burn_shader.code = BURN_AWAY
	var mat := ShaderMaterial.new()
	mat.shader = _burn_shader
	mat.set_shader_parameter("travel", 0.0 if Feedback.motion_reduced else 1.0)
	mat.set_shader_parameter("rim_gain", 0.7 if Feedback.flash_reduced else 1.0)
	return mat


## Child canvas item painted by `paint`: splitting the sky into static and live
## children is what lets the static ones keep their recorded draw commands.
static func painter(parent: Node, paint: Callable, mat: Material = null) -> Node2D:
	var node := Node2D.new()
	node.material = mat
	node.draw.connect(paint.bind(node))
	parent.add_child(node)
	return node


## Interior half-width of the shaft at height `y`.
static func half_width(y: float) -> float:
	return lerpf(HALF_FLOOR, HALF_RIM, clampf((FLOOR_Y - y) / (FLOOR_Y - RIM_Y), 0.0, 1.0))


## Fire colours dim for reduced flash (the WardenArt convention).
static func fire(c: Color) -> Color:
	return c.darkened(0.22) if Feedback.flash_reduced else c


# --- The director's API ------------------------------------------------------------

## A fallen knight's flame leaves `from` (world) after `delay` seconds, climbs
## the well past the galleries and settles as the next star in the moon's circlet.
func add_rising(from: Vector2, delay: float) -> void:
	var n := _flying.size() + _new_stars.size()
	var to := _star_slot(n)
	var dur := clampf(from.distance_to(to) / RISE_SPEED, RISE_MIN, RISE_MAX)
	_flying.append({ "from": from, "to": to, "t": -maxf(delay, 0.0), "dur": dur, "seed": n })
	set_process(true)


## Flames not yet settled as stars, waiting ones included.
func rising_left() -> int:
	return _flying.size()


## The world point the camera tilts up to: the mouth, the moon and its circlet.
func well_top() -> Vector2:
	return TOP


func _process(delta: float) -> void:
	if autostep:
		advance(delta / maxf(Engine.time_scale, 0.001))


## Moves every riser on by `dt` real seconds, settles the ones that arrive and
## stops processing once nothing is left moving.
func advance(dt: float) -> void:
	_clock += dt
	var still := Feedback.motion_reduced
	var i := 0
	while i < _flying.size():
		var r := _flying[i]
		r.t += dt
		if r.t >= (0.0 if still else float(r.dur)):
			# Reduced motion: the star is simply there, with no pop or bloom.
			_new_stars.append({ "p": r.to, "age": SETTLE_TIME if still else 0.0, "seed": r.seed })
			_flying.remove_at(i)
			_new_body.queue_redraw()
			_new_glow.queue_redraw()
		else:
			i += 1
	var airborne := not still and _flying.any(func(f: Dictionary) -> bool: return f.t >= 0.0)
	if airborne or _risers_drawn:
		_risers.queue_redraw()
		_riser_glow.queue_redraw()
	_risers_drawn = airborne
	var settling := false
	for s in _new_stars:
		if s.age < SETTLE_TIME:
			s.age = minf(SETTLE_TIME, s.age + dt)
			settling = true
	if settling:
		_new_body.queue_redraw()
		_new_glow.queue_redraw()
	if _flying.is_empty() and not settling and not _risers_drawn:
		set_process(false)


## The n-th new star's place: once round the moon at the golden angle, so any
## number of them spreads evenly into a ring, with a little hand-set jitter.
## Past sixteen a second, wider ring begins.
func _star_slot(n: int) -> Vector2:
	var a := -PI * 0.5 + float(n) * 2.39996 + (VFX.hash01(n, 71) - 0.5) * 0.12
	var ring := 1.0 + 0.45 * floorf(n / 16.0)
	return MOON + Vector2(cos(a) * CIRCLET.x, sin(a) * CIRCLET.y) * ring * lerpf(0.94, 1.06, VFX.hash01(n, 72))


## Where riser `r` is `t` seconds into its climb: a slow lift off the head it
## leaves, a sway up the shaft that dies away, and an easy arrival at its star.
func _rise_point(r: Dictionary, t: float) -> Vector2:
	var k := clampf(t / float(r.dur), 0.0, 1.0)
	var from: Vector2 = r.from
	var to: Vector2 = r.to
	var y := lerpf(from.y, to.y, k * k * (3.0 - 2.0 * k))
	var sway := sin(k * TAU * 1.6 + float(r.seed) * 1.7) * 26.0 * sin(PI * k)
	return Vector2(lerpf(from.x, to.x, smoothstep(0.1, 0.9, k)) + sway, y)


## Things shrink as they climb away up the shaft.
static func _far_scale(y: float) -> float:
	return lerpf(1.0, 0.55, clampf((FLOOR_Y - y) / (FLOOR_Y - MOON.y), 0.0, 1.0))


# --- Light ---------------------------------------------------------------------------

## Everything `reveal`, `dawn` and `moon_glow` do is modulation of pieces that
## painted once; nothing here repaints.
func _light() -> void:
	if _well == null:
		return
	var night := smoothstep(0.0, 0.7, reveal)
	var out := 1.0 - dawn
	_sky.modulate.a = smoothstep(0.0, 0.5, reveal)
	_dawn_sky.modulate.a = dawn
	for b in range(STAR_BUCKETS):
		var from := lerpf(0.3, 0.9, float(b) / STAR_BUCKETS)
		_stars[b].modulate.a = smoothstep(from, from + 0.1, reveal) * out
	var moon := smoothstep(0.2, 0.8, reveal)
	_moon.modulate.a = moon * (1.0 - 0.5 * dawn)
	_halo.modulate.a = moon * 0.5 * moon_glow * (1.0 - 0.7 * dawn)
	for piece: Node2D in [_new_body, _new_glow]:
		piece.modulate.a = out
	var lit := DARK.lerp(Color.WHITE, night).lerp(DAWN_TINT, dawn * (1.0 - night))
	_well.modulate = Color(lit, 1.0)
	_embers.modulate.a = minf(1.0, reveal * 4.0) * out
	_moonlight.modulate.a = smoothstep(0.4, 1.0, reveal) * out


# --- Sky -----------------------------------------------------------------------------

## Opaque black under everything, so a hole burnt before the night is out
## shows the dark, not the clear colour.
func _draw_void(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	m.rect(EXTENT, VFX.VOID)
	m.commit(ci)


## The crypt's night, void aloft and its navy low over the rim (Content.MOODS "crypt").
func _draw_sky(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	var x := EXTENT.position.x
	var w := EXTENT.size.x
	m.gradient(Rect2(x, EXTENT.position.y, w, -1900.0 - EXTENT.position.y), SKY_HIGH, SKY_HIGH)
	m.gradient(Rect2(x, -1900.0, w, 650.0), SKY_HIGH, SKY_TOP)
	m.gradient(Rect2(x, -1250.0, w, 550.0), SKY_TOP, SKY_MID)
	m.gradient(Rect2(x, RIM_Y, w, 260.0), SKY_MID, SKY_LOW)
	m.commit(ci)


func _draw_dawn_sky(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	var x := EXTENT.position.x
	var w := EXTENT.size.x
	m.gradient(Rect2(x, EXTENT.position.y, w, -1300.0 - EXTENT.position.y), DAWN_HIGH.darkened(0.4), DAWN_HIGH)
	m.gradient(Rect2(x, -1300.0, w, 860.0), DAWN_HIGH, DAWN_LOW)
	m.commit(ci)


## The first chamber's stars, scattered over the whole night and dealt into
## buckets that prick out one after another as `reveal` rises.
func _draw_stars(ci: CanvasItem, bucket: int) -> void:
	var m := PaperMesh.new()
	for i in range(bucket, 1100, STAR_BUCKETS):
		var p := Vector2(lerpf(EXTENT.position.x, EXTENT.end.x, VFX.hash01(i, 51)), lerpf(EXTENT.position.y, RIM_Y - 30.0, pow(VFX.hash01(i, 52), 0.85)))
		if p.distance_to(MOON) < MOON_R + 10.0:
			continue
		var h := VFX.hash01(i, 53)
		m.circle(p, 1.0 + h * 1.4, Color(STAR_COL, 0.25 + 0.5 * VFX.hash01(i, 54)), 6)
		if h > 0.96:
			# The odd bright one catches a glint.
			m.line(p - Vector2(5.0, 0.0), p + Vector2(5.0, 0.0), Color(STAR_COL, 0.3), 1.0)
			m.line(p - Vector2(0.0, 5.0), p + Vector2(0.0, 5.0), Color(STAR_COL, 0.3), 1.0)
	m.commit(ci)


## The first chamber's halo: flat paper rings, not a gradient. Laid as annuli
## rather than stacked discs, so fading the node dims them evenly.
func _draw_halo(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	var clear := 1.0
	for i in range(1, 6):
		clear *= 1.0 - 0.032 * float(6 - i)
		var outer := MOON_R + float(6 - i) * 30.0
		m.annulus(MOON, outer - 30.0, outer, Color(MOON_COL, 1.0 - clear))
	m.commit(ci)


## The crescent itself, cut out rather than bitten with a sky-coloured disc,
## so it fades cleanly; its craters are clipped to what is left.
func _draw_moon(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	for crescent in Geometry2D.clip_polygons(_disc(MOON, MOON_R), _disc(MOON + Vector2(31.0, -20.0), 59.0)):
		m.polygon(crescent, VFX.shaded_colors(crescent, Color(MOON_COL, 0.95), 1.06, 0.9))
		for i in range(6):
			var off := Vector2(VFX.hash01(i, 61) - 0.5, VFX.hash01(i, 62) - 0.5) * 85.0
			var r := 4.0 + VFX.hash01(i, 63) * 11.0
			for crater in Geometry2D.intersect_polygons(VFX.ellipse_points(MOON + off, r, r), crescent):
				m.fill(crater, Color(MOON_COL.darkened(0.28), 0.5))
	m.commit(ci)


## A 64-point circle, finer than VFX's 24, so the crescent's horns stay sharp.
static func _disc(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(64):
		pts.append(c + Vector2(r, 0.0).rotated(TAU * float(i) / 64.0))
	return pts


# --- The well ------------------------------------------------------------------------

## Point on ring `r` at angle `a` (0 right, PI/2 the far middle, PI left):
## `inset` pulls it toward the axis, `lift` raises the far side (a ledge's lip).
func _ring_point(r: Dictionary, a: float, inset := 0.0, lift := 0.0) -> Vector2:
	return Vector2(CX + (float(r.w) - inset) * cos(a), float(r.y) + (float(r.sag) - lift) * sin(a))


func _arc(r: Dictionary, inset: float, lift: float, steps := 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		pts.append(_ring_point(r, PI * float(i) / steps, inset, lift))
	return pts


## How much of ledge `r`'s underside shows at the far middle.
static func _soffit(r: Dictionary) -> float:
	return 10.0 + 0.25 * float(r.sag)


func _draw_well(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	for i in range(LEVELS):
		_paint_level(m, i)
	for i in range(1, LEVELS + 1):
		_paint_ledge(m, i)
	_paint_remnants(m, false)
	_paint_earth(m)
	_paint_floor(m)
	_paint_remnants(m, true)
	m.commit(ci)


## One gallery: the far wall between ledge `i` and ledge `i + 1`, warm near
## the knight, cold and moonlit near the mouth, each face shadowed under the
## ledge above it; then its niches, pilasters and courses.
func _paint_level(m: PaperMesh, i: int) -> void:
	var low: Dictionary = _rings[i]
	var high: Dictionary = _rings[i + 1]
	var v := (float(low.v) + float(high.v)) * 0.5
	var face := WALL_WARM.lerp(WALL_COLD, v).lerp(MOONLIT, 0.45 * v * v)
	var top := _arc(high, 0.0, 0.0)
	var bottom := _arc(low, 0.0, 0.0)
	m.band(top, bottom, flat(face.darkened(0.45), top.size()), flat(face, bottom.size()))
	# Masonry courses: thin broken lines following the curve.
	for c in range(1, 3):
		var f := float(c) / 3.0
		for j in range(0, top.size() - 1, 2):
			if VFX.hash01(i * 100 + c * 10 + j, 5) < 0.5:
				m.line(bottom[j].lerp(top[j], f), bottom[j + 1].lerp(top[j + 1], f), Color(VFX.RIM, 0.06 + 0.08 * v), 1.0)
	# Niches stand on the lip of the ledge below (the floor, for the lowest).
	var sill := 0.0 if i == 0 else _soffit(low)
	var count := 5 + i
	for j in range(count):
		var seed := i * 17 + j
		var a := PI * (float(j) + 0.5 + (VFX.hash01(seed, 8) - 0.5) * 0.4) / float(count)
		var foot := _ring_point(low, a, 0.0, sill)
		var crown := _ring_point(high, a)
		var nh := (foot.y - crown.y) * (0.36 + VFX.hash01(seed, 6) * 0.26)
		foot.y -= (foot.y - crown.y) * 0.12
		# Seen round the curve, a niche near the sides turns away and narrows.
		_paint_niche(m, foot, nh, nh * 0.56 * lerpf(0.3, 1.0, sin(a)), VFX.hash01(seed, 7), face, v, seed)
		if j < count - 1:
			_paint_pilaster(m, low, high, PI * (float(j) + 1.0) / float(count), sill, face, v)


## A rib dividing the arcade, lit on its moonward side.
func _paint_pilaster(m: PaperMesh, low: Dictionary, high: Dictionary, a: float, sill: float, face: Color, v: float) -> void:
	var wdt := (7.0 - 3.0 * v) * lerpf(0.4, 1.0, sin(a))
	var p0 := _ring_point(high, a)
	var p1 := _ring_point(low, a, 0.0, sill)
	var rib := PackedVector2Array([p0 + Vector2(-wdt, 0.0), p0 + Vector2(wdt, 0.0), p1 + Vector2(wdt * 1.2, 0.0), p1 + Vector2(-wdt * 1.2, 0.0)])
	m.polygon(rib, PackedColorArray([face.darkened(0.7), face.darkened(0.4), face.darkened(0.1), face.darkened(0.45)]))
	m.line(p0 + Vector2(wdt * 0.6, 0.0), p1 + Vector2(wdt * 0.7, 0.0), Color(VFX.SLATE, 0.1 + 0.1 * v), 1.0)


## An arched recess, as the title cuts them: collapsed, sealed with paler
## stone, or open and dark, a few still holding a hooded effigy.
func _paint_niche(m: PaperMesh, foot: Vector2, nh: float, nw: float, kind: float, face: Color, v: float, seed: int) -> void:
	if nh < 10.0 or nw < 4.0:
		return
	var ink := Color(NICHE, 0.88 - 0.3 * v)
	if kind < 0.14:
		m.fill(PackedVector2Array([foot + Vector2(-nw * 0.6, 0.0), foot + Vector2(-nw * 0.45, -nh * 0.5), foot + Vector2(-nw * 0.1, -nh * 0.8),
			foot + Vector2(nw * 0.3, -nh * 0.55), foot + Vector2(nw * 0.55, -nh * 0.15), foot + Vector2(nw * 0.6, 0.0)]), ink)
		return
	var arch := PackedVector2Array([foot + Vector2(-nw * 0.5, 0.0), foot + Vector2(-nw * 0.5, -nh * 0.62)])
	for q in range(9):
		var ang := PI + PI * float(q) / 8.0
		arch.append(foot + Vector2(cos(ang) * nw * 0.5, -nh * 0.62 + sin(ang) * nh * 0.38))
	arch.append(foot + Vector2(nw * 0.5, 0.0))
	if kind < 0.26:
		m.fill(arch, face.lightened(0.08))
		m.stroke(arch, Color(NICHE, 0.7), 1.0, true)
		return
	m.fill(arch, ink)
	# Moonlight catches the inside of the arch's head, from above.
	m.stroke(arch.slice(2, 8), Color(VFX.RIM, 0.12 + 0.2 * v), 1.0)
	if kind > 0.84 and nh > 40.0:
		var eh := nh * 0.62
		var ew := nw * 0.34
		var eb := foot + Vector2(0.0, -2.0)
		m.fill(PackedVector2Array([eb + Vector2(-ew * 0.5, 0.0), eb + Vector2(-ew * 0.36, -eh * 0.62), eb + Vector2(0.0, -eh),
			eb + Vector2(ew * 0.36, -eh * 0.62), eb + Vector2(ew * 0.5, 0.0)]), Color(EFFIGY, 0.9 - 0.3 * v))
	m.line(foot + Vector2(-nw * 0.5, 0.0), foot + Vector2(nw * 0.5, 0.0), Color(VFX.RIM, 0.1 + 0.15 * v), 1.0)
	if VFX.hash01(seed, 9) > 0.7:
		# A bone on the sill.
		m.circle(foot + Vector2(nw * 0.18, -2.0), 2.2, face.lightened(0.15), 6)


## A ledge seen from below: its dark underside shows as a crescent over the
## wall line, warmed by the knight's flame low down, with a moonlit lip. A few
## runs have fallen away. The top ring is the rim, backlit by the sky.
func _paint_ledge(m: PaperMesh, i: int) -> void:
	var r: Dictionary = _rings[i]
	var v := float(r.v)
	var rim := i == LEVELS
	var under := SOFFIT.lerp(UNDERGLOW, 0.55 * pow(1.0 - v, 2.0))
	var junction := _arc(r, 0.0, 0.0)
	var lip := _arc(r, LEDGE, _soffit(r))
	var seg := 0
	while seg < junction.size() - 1:
		var end := mini(seg + 3 + int(VFX.hash01(i * 50 + seg, 15) * 6.0), junction.size() - 1)
		if rim or VFX.hash01(i * 50 + seg, 16) > 0.16:
			var edge := lip.slice(seg, end + 1)
			m.band(edge, junction.slice(seg, end + 1), flat(under, edge.size()), flat(under.darkened(0.3), edge.size()))
			m.stroke(edge, Color(VFX.RIM, 0.55 if rim else 0.22 + 0.3 * v), 2.0 if rim else 1.5)
		seg = end


## The earth the shaft is sunk in, cut away like a stage set: dark coursed
## stone either side of the well and under its floor, a moonlit bevel on
## the cut and along the ground at the rim.
func _paint_earth(m: PaperMesh) -> void:
	var bottom := FLOOR_Y + FLOOR_FACE
	for side: float in [-1.0, 1.0]:
		var rim := Vector2(CX + side * HALF_RIM, RIM_Y)
		var foot := Vector2(CX + side * half_width(bottom), bottom)
		var outer := EXTENT.position.x if side < 0.0 else EXTENT.end.x
		m.fill(PackedVector2Array([Vector2(outer, RIM_Y), rim, foot, Vector2(foot.x, EXTENT.end.y), Vector2(outer, EXTENT.end.y)]), EARTH)
		# Courses near the cut.
		for k in range(1, 30):
			var y := RIM_Y + float(k) * 46.0
			if y >= bottom:
				break
			var edge_x := CX + side * half_width(y)
			m.line(Vector2(edge_x, y), Vector2(edge_x + side * 420.0, y), EARTH_JOINT, 1.5)
			var jx := edge_x + side * (40.0 + 60.0 * VFX.hash01(k, 31 + int(side)))
			m.line(Vector2(jx, y), Vector2(jx, y + 46.0), EARTH_JOINT, 1.5)
		m.line(rim, foot, Color(VFX.RIM, 0.28), 1.5)
		m.line(Vector2(outer, RIM_Y), rim, Color(VFX.RIM, 0.4), 1.5)
	m.rect(Rect2(EXTENT.position.x, bottom, EXTENT.size.x, EXTENT.end.y - bottom), EARTH)


## The well floor: a sliver of flagstones up to the far wall's foot, then the
## cut face the knight stands on, jointed like the game's own floors.
func _paint_floor(m: PaperMesh) -> void:
	var r: Dictionary = _rings[0]
	var far := _arc(r, 0.0, 0.0)
	var w := float(r.w)
	var near := PackedVector2Array()
	for p in far:
		near.append(Vector2(p.x, FLOOR_Y))
	m.band(far, near, flat(FLOOR_TOP.darkened(0.3), far.size()), flat(FLOOR_TOP, near.size()))
	m.gradient(Rect2(CX - w, FLOOR_Y, w * 2.0, FLOOR_FACE), FLOOR_TOP.darkened(0.35), FLOOR_LO)
	for k in range(int(w * 2.0 / 64.0) + 1):
		var x := CX - w + float(k) * 64.0
		m.line(Vector2(x, FLOOR_Y + 2.0), Vector2(x, FLOOR_Y + 40.0), Color(FLOOR_LO, 0.9), 1.0)
	m.line(Vector2(CX - w, FLOOR_Y + 40.0), Vector2(CX + w, FLOOR_Y + 40.0), Color(FLOOR_LO, 0.7), 1.0)
	m.line(Vector2(CX - w, FLOOR_Y + 1.0), Vector2(CX + w, FLOOR_Y + 1.0), Color(VFX.RIM, 0.35), 1.5)


## What the fire left of the keep, black paper against the sky: small snapped
## posts on the far rim (`near` false), and on the cut either side the root of
## the vault's rib and two pillar stumps. Each is {shape, burnt}: its outline
## and the ragged edge where the fire stopped.
func _remnants(near: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not near:
		var top: Dictionary = _rings[LEVELS]
		for k in range(4):
			var a: float = [0.42, 1.05, 1.95, 2.55][k]
			var base := _ring_point(top, a, LEDGE, _soffit(top))
			out.append(_post(base, 7.0 + 5.0 * VFX.hash01(k, 82), 30.0 + 40.0 * VFX.hash01(k, 81), k))
		return out
	# The vault's rib springs from the left cut and snapped a third of the way
	# over the well, tapering from its root to the burnt end.
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var span := Vector2(HALF_RIM + 70.0, 560.0)
	for k in range(15):
		var f := float(k) / 14.0
		var dir := Vector2(cos(PI - 0.95 * f), -sin(PI - 0.95 * f))
		outer.append(Vector2(CX, RIM_Y) + dir * span)
		inner.append(Vector2(CX, RIM_Y) + dir * (span - Vector2.ONE * lerpf(64.0, 38.0, f)))
	var burnt := _ragged(outer[14], inner[14], 5, 3)
	inner.reverse()
	var rib := outer.duplicate()
	rib.append_array(burnt.slice(1, burnt.size() - 1))
	rib.append_array(inner)
	out.append({ "shape": rib, "burnt": burnt })
	out.append(_post(Vector2(CX + HALF_RIM + 90.0, RIM_Y), 70.0, 210.0, 5))
	out.append(_post(Vector2(CX + HALF_RIM + 210.0, RIM_Y), 48.0, 118.0, 6))
	return out


## A stump `w` wide standing `h` tall on `base`, its top burnt ragged.
func _post(base: Vector2, w: float, h: float, seed: int) -> Dictionary:
	var burnt := _ragged(base + Vector2(-w * 0.5, -h), base + Vector2(w * 0.5, -h * lerpf(0.75, 0.95, VFX.hash01(seed, 83))), maxi(3, int(w / 9.0)), seed)
	var shape := PackedVector2Array([base + Vector2(-w * 0.5, 0.0)])
	shape.append_array(burnt)
	shape.append(base + Vector2(w * 0.5, 0.0))
	return { "shape": shape, "burnt": burnt }


## A burnt edge from `a` to `b`: `n` teeth of charred paper standing proud of it.
static func _ragged(a: Vector2, b: Vector2, n: int, seed: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var across := (b - a).orthogonal().normalized()
	for k in range(n * 2 + 1):
		var tooth := (VFX.hash01(k + seed * 13, 84) * 0.8 + 0.2) * 8.0 * float(k % 2)
		pts.append(a.lerp(b, float(k) / float(n * 2)) + across * tooth)
	return pts


func _paint_remnants(m: PaperMesh, near: bool) -> void:
	for piece in _remnants(near):
		m.cutout(piece.shape, CHAR, Vector2(3.0, 4.0))


## The burnt edges still smoulder.
func _draw_embers(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	for near: bool in [false, true]:
		for piece in _remnants(near):
			m.stroke(piece.burnt, Color(fire(EMBER_EDGE), 0.8), 1.5)
			m.stroke(piece.burnt, Color(fire(VFX.GOLD), 0.5), 0.8)
	m.commit(ci)


## Cold moonlight falling from the mouth to the knight, its pool on the
## floor, and the last warm light of the knight's own flame on the lowest walls.
func _draw_moonlight(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	var mouth := RIM_Y + float(_rings[LEVELS].sag)
	m.beam(Vector2(CX + 30.0, mouth), Vector2(CX + 250.0, mouth), Vector2(CX - 200.0, FLOOR_Y), Vector2(CX + 120.0, FLOOR_Y), Color(MOON_COL, 0.12), Color(MOON_COL, 0.07))
	m.glow(Vector2(CX + 130.0, mouth + 30.0), 260.0, Color(MOON_COL, 0.1))
	m.glow_ellipse(Vector2(CX - 40.0, FLOOR_Y + 2.0), Vector2(250.0, 36.0), Color(MOON_COL, 0.16))
	m.glow_ellipse(Vector2(CX, FLOOR_Y - 40.0), Vector2(520.0, 320.0), Color(VFX.ORANGE, 0.08))
	m.commit(ci)


## Thin grey dawn: light filling the shaft from the mouth down to its leading
## edge, which falls as `dawn` rises. Reduced motion fills the whole shaft at
## once and fades it in instead.
func _draw_spill(ci: CanvasItem) -> void:
	if dawn <= 0.0:
		return
	var still := Feedback.motion_reduced
	var bottom := FLOOR_Y + FLOOR_FACE
	var front := bottom + 240.0 if still else lerpf(RIM_Y, bottom + 240.0, 1.0 - pow(1.0 - dawn, 1.6))
	var strength := dawn if still else minf(1.0, dawn * 2.5)
	var m := PaperMesh.new()
	var rows := 24
	var prev := PackedVector2Array()
	var prev_cols := PackedColorArray()
	for k in range(rows + 1):
		var y := lerpf(RIM_Y, minf(front, bottom), float(k) / rows)
		var w := half_width(y)
		var row := PackedVector2Array([Vector2(CX - w, y), Vector2(CX + w, y)])
		var c := Color(DAWN_LIGHT, 0.2 * strength * (1.0 - smoothstep(front - 340.0, front, y)))
		var cols := PackedColorArray([c, c])
		if k > 0:
			m.band(prev, row, prev_cols, cols)
		prev = row
		prev_cols = cols
	# Over the rim the grey light meets the sky's.
	m.gradient(Rect2(CX - HALF_RIM, RIM_Y - 200.0, HALF_RIM * 2.0, 200.0), Color(DAWN_LIGHT, 0.0), Color(DAWN_LIGHT, 0.2 * strength))
	m.commit(ci)


# --- The fallen, rising ----------------------------------------------------------------

## Each climbing flame: the fallen's four-tongue crown, small and shrinking as
## it rises, a gold trail behind it, turning into its star as it arrives.
func _draw_risers(ci: CanvasItem) -> void:
	if not _risers_drawn:
		return
	var m := PaperMesh.new()
	for r in _flying:
		var t := float(r.t)
		if t < 0.0:
			continue
		var head := _rise_point(r, t)
		var sc := _far_scale(head.y)
		var trail := PackedVector2Array()
		var widths := PackedFloat32Array()
		var cols := PackedColorArray()
		for j in range(TRAIL, -1, -1):
			var f := 1.0 - float(j) / TRAIL
			trail.append(_rise_point(r, maxf(0.0, t - float(j) * TRAIL_STEP * float(r.dur))))
			widths.append(4.0 * sc * f)
			cols.append(Color(fire(VFX.GOLD), 0.55 * f * f))
		m.ribbon(trail, widths, cols)
		# Sparks shed along the trail, drifting as they fall behind.
		for j in range(3):
			var drift := Vector2(sin(_clock * 5.0 + float(j * 3 + int(r.seed))) * 5.0, 6.0 + 9.0 * float(j))
			m.circle(trail[TRAIL - 3 - j * 3] + drift * sc, 1.4 * sc, Color(fire(VFX.ORANGE), 0.7 - 0.2 * float(j)), 6)
		var become := smoothstep(0.82, 1.0, t / float(r.dur))
		m.crown(head + Vector2(0.0, 6.0 * sc), sc * (1.0 - become), _clock * 1.3 + float(r.seed), fire(RISER_FLAME), fire(VFX.GOLD))
		m.star(head, 8.0 * become * _far_scale(MOON.y), STAR_GOLD, VFX.HOT)
	m.commit(ci)


func _draw_riser_glow(ci: CanvasItem) -> void:
	if not _risers_drawn:
		return
	var m := PaperMesh.new()
	var k := 0.75 if Feedback.flash_reduced else 1.0
	for r in _flying:
		if float(r.t) >= 0.0:
			var head := _rise_point(r, float(r.t))
			m.glow(head, 42.0 * _far_scale(head.y), Color(VFX.GOLD, 0.4 * k))
	m.commit(ci)


## The fallen as stars: small gold four-point cut-outs, each popping in with a
## bloom when it arrives, then still.
func _draw_new_stars(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	for s in _new_stars:
		var k := float(s.age) / SETTLE_TIME
		# Past full size and back: the star catches.
		var pop := 1.0 + 0.35 * sin(PI * minf(1.0, k * 1.4)) * (1.0 - k)
		m.star(s.p, 8.0 * _far_scale(MOON.y) * pop, STAR_GOLD, VFX.HOT)
	m.commit(ci)


func _draw_new_glow(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	var k := 0.4 if Feedback.flash_reduced else 1.0
	for s in _new_stars:
		var p: Vector2 = s.p
		var age := float(s.age) / SETTLE_TIME
		m.glow(p, 26.0, Color(VFX.GOLD, 0.3))
		if age < 1.0:
			m.glow(p, lerpf(16.0, 90.0, age), Color(VFX.HOT, 0.6 * (1.0 - age) * k))
	m.commit(ci)


static func flat(c: Color, n: int) -> PackedColorArray:
	var cols := PackedColorArray()
	cols.resize(n)
	cols.fill(c)
	return cols


static func box(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Paper shapes gathered into one vertex-coloured triangle list and handed to
## the canvas as a single command. The GL Compatibility renderer gives every
## polygon, circle and antialiased line a draw call of its own (a smooth line
## takes three), so a well painted shape by shape costs hundreds of calls;
## through a PaperMesh it costs one. Strokes feather their sides over a pixel,
## standing in for the renderer's antialiasing. Every vertex carries a UV, so
## on a radial-material painter glow() quads fall off softly while flat shapes
## (UV at the centre) stay solid.
class PaperMesh extends RefCounted:
	const FEATHER := 1.0
	const SOLID := Vector2(0.5, 0.5)
	const QUAD_UV := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	var _points := PackedVector2Array()
	var _colors := PackedColorArray()
	var _uvs := PackedVector2Array()
	var _indices := PackedInt32Array()

	## Hands everything gathered so far to `ci` as one draw command.
	func commit(ci: CanvasItem) -> void:
		if not _indices.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _indices, _points, _colors, _uvs)

	## A polygon with a colour per point (see VFX.shaded_colors).
	func polygon(pts: PackedVector2Array, cols: PackedColorArray) -> void:
		var tris := Geometry2D.triangulate_polygon(pts)
		var base := _points.size()
		_points.append_array(pts)
		_colors.append_array(cols)
		_solid(pts.size())
		for i in range(tris.size()):
			tris[i] += base
		_indices.append_array(tris)

	func fill(pts: PackedVector2Array, color: Color) -> void:
		polygon(pts, FinaleSky.flat(color, pts.size()))

	func rect(r: Rect2, color: Color) -> void:
		fill(FinaleSky.box(r), color)

	## `r` shaded from `top` down to `bottom`.
	func gradient(r: Rect2, top: Color, bottom: Color) -> void:
		polygon(FinaleSky.box(r), PackedColorArray([top, top, bottom, bottom]))

	func circle(c: Vector2, r: float, color: Color, sides := 24) -> void:
		var pts := PackedVector2Array()
		for i in range(sides):
			pts.append(c + Vector2(r, 0.0).rotated(TAU * float(i) / sides))
		fill(pts, color)

	## A flat ring between radii `r0` and `r1`.
	func annulus(c: Vector2, r0: float, r1: float, color: Color) -> void:
		var inner := PackedVector2Array()
		var outer := PackedVector2Array()
		for i in range(65):
			var dir := Vector2.RIGHT.rotated(TAU * float(i) / 64.0)
			inner.append(c + dir * r0)
			outer.append(c + dir * r1)
		band(outer, inner, FinaleSky.flat(color, 65), FinaleSky.flat(color, 65))

	## Quads between two matching rows of points: faces, bands and washes.
	func band(a: PackedVector2Array, b: PackedVector2Array, a_cols: PackedColorArray, b_cols: PackedColorArray) -> void:
		var base := _points.size()
		var n := a.size()
		_points.append_array(a)
		_points.append_array(b)
		_colors.append_array(a_cols)
		_colors.append_array(b_cols)
		_solid(n * 2)
		for i in range(base, base + n - 1):
			_indices.append_array(PackedInt32Array([i, i + 1, i + n + 1, i, i + n + 1, i + n]))

	## A line `width` wide along `pts`, mitred at the joints, its sides fading
	## to clear over FEATHER. Hairlines stay a pixel wide and fade instead.
	func stroke(pts: PackedVector2Array, color: Color, width: float, closed := false) -> void:
		var count := pts.size() + int(closed)
		var halves := PackedFloat32Array()
		halves.resize(count)
		halves.fill(maxf(width, 1.0) * 0.5)
		_columns(pts, halves, FinaleSky.flat(Color(color, color.a * minf(width, 1.0)), count), closed)

	func line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
		stroke(PackedVector2Array([a, b]), color, width)

	## A tapering stroke with a width and a colour per point (a riser's trail).
	func ribbon(pts: PackedVector2Array, widths: PackedFloat32Array, cols: PackedColorArray) -> void:
		var halves := PackedFloat32Array()
		for w in widths:
			halves.append(w * 0.5)
		_columns(pts, halves, cols, false)

	## Paper cut-out: a soft offset shadow, a top-lit fill and a pale bevel on its upper edges.
	func cutout(pts: PackedVector2Array, fill_color: Color, shadow := Vector2(4.0, 5.0)) -> void:
		fill(Transform2D(0.0, shadow) * pts, Color(0.0, 0.0, 0.0, 0.4 * fill_color.a))
		polygon(pts, VFX.shaded_colors(pts, fill_color, 1.18, 0.78))
		bevel(pts, 0.8 * fill_color.a)

	## The catch-light a paper edge takes from above, on its upward-facing edges.
	func bevel(pts: PackedVector2Array, strength: float) -> void:
		var centre := Vector2.ZERO
		for p in pts:
			centre += p
		centre /= float(pts.size())
		for i in range(pts.size()):
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			if a.distance_squared_to(b) < 1.0:
				continue
			var normal := (b - a).orthogonal().normalized()
			if normal.dot((a + b) * 0.5 - centre) < 0.0:
				normal = -normal
			if -normal.y > 0.6:
				line(a, b, Color(VFX.RIM, 0.35 * strength * -normal.y), 1.0)

	## The knight's four-tongue crown (the finale actors' draw_crown), batched,
	## `size` 1 being a knight's own.
	func crown(base: Vector2, size: float, t: float, outer: Color, inner: Color) -> void:
		if size <= 0.02:
			return
		for i in range(4):
			var foot := base + Vector2((-9.0 + float(i) * 6.0) * size, 0.0)
			var tip := (12.0 + sin(t * 10.0 + float(i) * 1.7) * 4.0) * size
			fill(PackedVector2Array([foot - Vector2(4.0 * size, 0.0), foot + Vector2(0.0, -tip), foot + Vector2(4.0 * size, -size)]), outer)
		for i in [1, 2]:
			var foot := base + Vector2((-9.0 + float(i) * 6.0) * size, -size)
			var tip := (8.0 + sin(t * 13.0 + float(i) * 2.3) * 2.5) * size
			fill(PackedVector2Array([foot - Vector2(2.0 * size, 0.0), foot + Vector2(0.0, -tip), foot + Vector2(2.0 * size, 0.0)]), inner)

	## A four-point paper star: `outer` arms `r` long round a hot `inner` heart.
	func star(c: Vector2, r: float, outer: Color, inner: Color) -> void:
		if r <= 0.1:
			return
		for layer in [[r, 0.28, outer], [r * 0.55, 0.3, inner]]:
			var pts := PackedVector2Array()
			for i in range(8):
				var reach: float = layer[0] * (1.0 if i % 2 == 0 else layer[1])
				pts.append(c + Vector2(0.0, -reach).rotated(PI * 0.25 * float(i)))
			fill(pts, layer[2])

	## A soft round light: one quad whose UVs drive the radial falloff.
	func glow(c: Vector2, r: float, color: Color) -> void:
		glow_ellipse(c, Vector2(r, r), color)

	func glow_ellipse(c: Vector2, radii: Vector2, color: Color) -> void:
		if radii.x <= 0.0 or color.a <= 0.0:
			return
		var base := _points.size()
		for uv: Vector2 in QUAD_UV:
			_points.append(c + (uv * 2.0 - Vector2.ONE) * radii)
			_colors.append(color)
			_uvs.append(uv)
		_indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	## A shaft of light, soft at both sides: three columns, the outer ones on
	## the radial falloff's rim.
	func beam(top_l: Vector2, top_r: Vector2, bot_l: Vector2, bot_r: Vector2, top: Color, bottom: Color) -> void:
		var base := _points.size()
		for row in [[top_l, top_r, top], [bot_l, bot_r, bottom]]:
			for u: float in [0.0, 0.5, 1.0]:
				_points.append((row[0] as Vector2).lerp(row[1], u))
				_colors.append(row[2])
				_uvs.append(Vector2(u, 0.5))
		_indices.append_array(PackedInt32Array([base, base + 1, base + 4, base, base + 4, base + 3, base + 1, base + 2, base + 5, base + 1, base + 5, base + 4]))

	## The body of stroke() and ribbon(): four vertices per point (feather,
	## edge, edge, feather), `halves` the half-width at each.
	func _columns(pts: PackedVector2Array, halves: PackedFloat32Array, cols: PackedColorArray, closed: bool) -> void:
		var n := pts.size()
		if n < 2:
			return
		var count := n + int(closed)
		var base := _points.size()
		for i in range(count):
			var p := pts[i % n]
			var side := _miter(pts, i % n, closed)
			var half := halves[i]
			_points.append_array(PackedVector2Array([p + side * (half + FEATHER), p + side * half, p - side * half, p - side * (half + FEATHER)]))
			_colors.append_array(PackedColorArray([Color(cols[i], 0.0), cols[i], cols[i], Color(cols[i], 0.0)]))
		_solid(count * 4)
		for a in range(base, base + (count - 1) * 4, 4):
			_indices.append_array(PackedInt32Array([a, a + 1, a + 5, a, a + 5, a + 4,
				a + 1, a + 2, a + 6, a + 1, a + 6, a + 5, a + 2, a + 3, a + 7, a + 2, a + 7, a + 6]))

	## Unit side offset at point `i`, lengthened at a corner so both edges keep their width.
	static func _miter(pts: PackedVector2Array, i: int, closed: bool) -> Vector2:
		var n := pts.size()
		var prev := pts[(i + n - 1) % n] if closed or i > 0 else pts[i]
		var next := pts[(i + 1) % n] if closed or i < n - 1 else pts[i]
		var dir_in := (pts[i] - prev).normalized()
		var dir_out := (next - pts[i]).normalized()
		var along := dir_out if dir_out != Vector2.ZERO else dir_in
		var tangent := (dir_in + dir_out).normalized()
		if tangent == Vector2.ZERO:
			tangent = along
		var normal := tangent.orthogonal()
		return normal / maxf(normal.dot(along.orthogonal()), 0.3)

	func _solid(n: int) -> void:
		for i in range(n):
			_uvs.append(SOLID)
