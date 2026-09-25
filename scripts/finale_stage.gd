class_name FinaleStage
extends Node2D
## The bare stage the keep was always painted on, revealed when the victory
## fire burns the set off its frame ("Strike the Set", ending spec §2 Acts III-V).
##
## Everything is drawn in world units so the director can give each CanvasLayer
## the world camera's canvas transform and the theatre lines up with the room it
## replaces: the stage floor is the room floor (Content.FLOOR_Y), so actors keep
## their feet through the burn.
##
## This file holds four pieces, each a plain drawing with no timeline of its own;
## the Finale director tweens their public vars:
##   FinaleStage   (layer -1) back wall, battens with charred remnants, ropes,
##                 the crimson traveler curtain (`closed`), floor and pit.
##   FinaleFront   (layer 11) proscenium, keystone and vow sockets (`vow_lit`),
##                 main curtain (`main_drop`), footlights (`lamps`), follow-spot
##                 (`spot`), the house and its audience (`house_count`, `rise`).
##   Playbill      (layer 11) the paper bill lowered on cords (`drop`, `rows`,
##                 `revealed`).
##   PlaybillText  (text layer) the bill's type, drawn in screen space so the
##                 serif stays crisp at any camera zoom.
## Each piece paints through a PaperMesh, one draw call however many shapes it
## holds. Each animated var's setter queues a redraw of only the node it
## affects; static geometry lives on nodes that paint once, so an idle theatre
## never repaints. Reduced motion turns travelling curtains and the lowering
## bill into fades and freezes every flicker clock; reduced flash darkens fire
## and dims halos.

const VFX := preload("res://scripts/vfx.gd")

## Burn-away for the world viewport container: the painted keep chars like paper
## held to a candle from `origin`, every cut edge glowing, then holes open onto
## the stage beneath. `travel` 0 (reduced motion) is a still dissolve with no
## moving rim; `rim_gain` dims the glow for reduced flash. The front's reach is
## measured to the farthest corner, so progress 1 always clears the whole frame.
const BURN_AWAY := """
shader_type canvas_item;
render_mode unshaded;

uniform float progress = 0.0;
uniform vec2 origin = vec2(0.5, 0.6);
uniform float aspect = 1.7778;
uniform float travel = 1.0;
uniform float rim_gain = 1.0;

const vec3 EMBER = vec3(1.0, 0.48, 0.12);
const vec3 HOT = vec3(1.0, 0.86, 0.55);
const vec3 CHAR = vec3(0.06, 0.035, 0.05);
const float RAGGED = 0.3;
const float LAG = 0.46;

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

// The burning band: paper scorches ahead of the front, chars with ember seams
// under a hot rim, then opens into holes with glowing lips. `ahead` is how far
// the unragged front has passed this point; `edge` is the painting's local contrast.
vec4 burn(vec4 world, float edge, vec2 p, float ahead) {
	float char_edge = ahead - fbm(p * 6.0) * RAGGED;
	float hole_edge = ahead - LAG - fbm(p * 9.0 + 3.1) * 0.22;
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
	vec2 o = origin * vec2(aspect, 1.0);
	float reach = max(max(length(o), distance(o, vec2(aspect, 0.0))), max(distance(o, vec2(0.0, 1.0)), distance(o, vec2(aspect, 1.0)))) + RAGGED;
	float ahead = progress * (reach + LAG) - distance(p, o);
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

# --- Stage geometry (world units) ------------------------------------------------
const FLOOR_Y := 600.0
const APRON_Y := 640.0
const CENTER_X := 640.0
const OPEN_L := 40.0
const OPEN_R := 1240.0
## Arch springing line and rise: y(x) = SPRING_Y - ARCH_RISE * (1 - |u|)^0.32.
const SPRING_Y := 60.0
const ARCH_RISE := 130.0
const ARCH_STEPS := 64
const PLEATS := 22
const BATTEN_YS := [-40.0, 30.0, 100.0, 170.0]
const TRAVELER_TOP := -160.0

const WALL_TOP := Color("08050c")
const WALL_BOTTOM := Color("1a0f1c")
const CHARCOAL := Color("1c1016")
const ASH_EDGE := Color("3a2a30")
const PIPE := Color("2a1d2a")
const ROPE := Color("3a2c3a")
const SANDBAG := Color("2a1f26")
const VELVET_LO := Color("3a0b16")
const VELVET_HI := Color("7a1a2a")
const BOARD := Color("24151d")
const GILT := Color("b8873a")
const GILT_HI := Color("f2cf7c")
const GILT_LO := Color("5c3e1c")
const EMBER_EDGE := Color(1.0, 0.45, 0.1)
const LAMP_FIRE := Color("ff7a18")
const SHADOW := Color(0.0, 0.0, 0.0, 0.4)

## Open-curtain inner edge travels this far from centre; closed pleats overlap a little.
const TRAVELER_OPEN := 620.0
const TRAVELER_OVERLAP := 8.0

## Traveler curtain, 0 = gathered behind the posts, 1 = closed across the stage.
## Once closed it hides the back wall, so that stops rendering.
var closed := 0.0:
	set(value):
		closed = value
		_traveler.queue_redraw()
		_back.visible = closed < 1.0
## Ember glow on the burnt remnants' edges, 1 = just burnt, 0 = cold ash. The
## embers fade over the ash edges, so cooling never repaints.
var remnant_heat := 1.0:
	set(value):
		remnant_heat = value
		var glow := Color(1.0, 1.0, 1.0, clampf(value, 0.0, 1.0))
		_embers.modulate = glow
		_sparks.modulate = glow

var _back: Node2D
var _embers: Node2D
var _sparks: Node2D
var _traveler: Node2D
var _remnants: Array[PackedVector2Array] = []


func _init() -> void:
	name = "FinaleStage"
	for b in range(BATTEN_YS.size()):
		_remnants.append(_remnant_edge(b))
	_back = painter(self, _draw_back)
	_embers = painter(_back, _draw_embers)
	_sparks = painter(_back, _draw_sparks, VFX.radial_material())
	_traveler = painter(self, _draw_traveler)
	painter(self, _draw_floor)


## A fresh burn material for the world container. Never shared: the chamber
## veil's UI.burn_material() may be mid-use, and each finale owns its uniforms.
static func burn_away_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = BURN_AWAY
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("travel", 0.0 if Feedback.motion_reduced else 1.0)
	mat.set_shader_parameter("rim_gain", 0.7 if Feedback.flash_reduced else 1.0)
	return mat


## Child canvas item painted by `paint`: splitting a piece into static and live
## children is what lets the static ones keep their recorded draw commands.
static func painter(parent: Node, paint: Callable, mat: Material = null) -> Node2D:
	var node := Node2D.new()
	node.material = mat
	node.draw.connect(paint.bind(node))
	parent.add_child(node)
	return node


static func arch_y(x: float) -> float:
	var u := clampf((x - CENTER_X) / (CENTER_X - OPEN_L), -1.0, 1.0)
	return SPRING_Y - ARCH_RISE * pow(1.0 - absf(u), 0.32)


## The proscenium opening's edge, `inset` world px inside it (negative = out onto
## the frame): up the left post, over the arch, down the right post. Samples
## crowd toward the springing, where the Tudor curve turns steep.
static func opening_edge(inset: float, foot_y: float = APRON_Y) -> PackedVector2Array:
	var half := CENTER_X - OPEN_L - inset
	var pts := PackedVector2Array([Vector2(CENTER_X - half, foot_y)])
	for i in range(ARCH_STEPS + 1):
		var s := lerpf(-1.0, 1.0, float(i) / ARCH_STEPS)
		var x := CENTER_X + half * signf(s) * (1.0 - pow(1.0 - absf(s), 3.0))
		pts.append(Vector2(x, arch_y(x) + inset))
	pts.append(Vector2(CENTER_X + half, foot_y))
	return pts


## Fire colours dim for reduced flash (the WardenArt convention).
static func fire(c: Color) -> Color:
	return c.darkened(0.22) if Feedback.flash_reduced else c


static func flat(c: Color, n: int) -> PackedColorArray:
	var cols := PackedColorArray()
	cols.resize(n)
	cols.fill(c)
	return cols


static func box(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Ragged lower edge of the painted drop that burnt off batten `b`.
func _remnant_edge(b: int) -> PackedVector2Array:
	var y: float = BATTEN_YS[b]
	var pts := PackedVector2Array()
	for i in range(64):
		var tatter := VFX.hash01(i * 7 + b, 3) * (0.35 + 0.65 * VFX.hash01(i, b + 11))
		# Now and then a long tongue of scorched cloth survived.
		if VFX.hash01(i, b + 21) > 0.82:
			tatter += 0.9
		pts.append(Vector2(lerpf(-420.0, 1700.0, float(i) / 63.0), y + 8.0 + tatter * 30.0))
	return pts


func _draw_back(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	m.gradient(Rect2(-700.0, -900.0, 2680.0, 1600.0), WALL_TOP, WALL_BOTTOM)
	# Battens hung with what the fire left of the painted drops.
	for b in range(BATTEN_YS.size()):
		var y: float = BATTEN_YS[b]
		var hang := PackedVector2Array([Vector2(-420.0, y)])
		hang.append_array(_remnants[b])
		hang.append(Vector2(1700.0, y))
		m.fill(hang, CHARCOAL.lightened(0.04 * float(b)))
		m.stroke(_remnants[b], Color(ASH_EDGE, 0.55), 1.5)
		m.line(Vector2(-420.0, y), Vector2(1700.0, y), PIPE, 6.0)
		m.line(Vector2(-420.0, y - 2.0), Vector2(1700.0, y - 2.0), Color(VFX.RIM, 0.25), 1.0)
	# Fly lines with their sandbags, kept clear of the rostrum.
	for r in range(6):
		var x := 90.0 + float(r) * 222.0 + (40.0 if r >= 3 else 0.0)
		var bag := Vector2(x, 341.0 + float(r % 3) * 70.0)
		m.line(Vector2(x, -900.0), bag - Vector2(0.0, 11.0), ROPE, 1.5)
		m.fill(VFX.ellipse_points(bag, 8.0, 12.0), SANDBAG)
		m.arc(bag, 8.0, PI * 1.1, PI * 1.9, Color(VFX.RIM, 0.3), 1.2)
	m.commit(ci)


## The still-burning edges of the remnants, laid over their ash edges.
func _draw_embers(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	for pts in _remnants:
		m.stroke(pts, Color(fire(EMBER_EDGE), 0.85), 1.5)
		m.stroke(pts, Color(fire(VFX.GOLD), 0.6), 0.8)
	m.commit(ci)


## Sparks caught in the tatters, cooling with the edges they hang on.
func _draw_sparks(ci: CanvasItem) -> void:
	for pts in _remnants:
		for i in range(0, pts.size(), 5):
			VFX.draw_radial(ci, pts[i], 6.0, Color(fire(VFX.ORANGE), 0.7))
			VFX.draw_radial(ci, pts[i], 2.5, Color(VFX.HOT, 0.8))


func _draw_traveler(ci: CanvasItem) -> void:
	if closed <= 0.0:
		return
	# Reduced motion: the curtain fades in where it hangs instead of travelling.
	var still := Feedback.motion_reduced
	var amount := 1.0 if still else clampf(closed, 0.0, 1.0)
	var alpha := clampf(closed, 0.0, 1.0) if still else 1.0
	var m := PaperMesh.new()
	for side: float in [-1.0, 1.0]:
		var inner := CENTER_X + side * (TRAVELER_OPEN * (1.0 - amount) - TRAVELER_OVERLAP * amount)
		var outer := CENTER_X + side * (CENTER_X + 20.0)
		# The leading hem trails the track while the curtain runs.
		var trail := 0.0 if still else side * 18.0 * sin(PI * amount)
		var tops := PackedVector2Array()
		var hems := PackedVector2Array()
		var shade := PackedColorArray()
		var lit := PackedColorArray()
		for i in range(PLEATS + 1):
			var u := float(i) / PLEATS
			var x := lerpf(inner, outer, u)
			var c := Color(VELVET_LO.lerp(VELVET_HI, 0.5 + 0.5 * cos(u * PLEATS * PI)), alpha)
			tops.append(Vector2(x, TRAVELER_TOP))
			hems.append(Vector2(x + trail * (1.0 - u), FLOOR_Y))
			shade.append(c.darkened(0.45))
			lit.append(c)
		m.band(tops, hems, shade, lit)
		m.line(tops[0], hems[0], Color(VELVET_HI.lightened(0.25), 0.6 * alpha), 1.5)
		m.line(hems[0] + Vector2(0.0, -10.0), Vector2(outer, FLOOR_Y - 10.0), Color(GILT_LO, 0.8 * alpha), 2.0)
	m.commit(ci)


## Stage floor in front of the traveler: plank face under a gilt lip, the pit below.
func _draw_floor(ci: CanvasItem) -> void:
	var m := PaperMesh.new()
	for i in range(58):
		var x := -700.0 + float(i) * 48.0
		m.rect(Rect2(x, FLOOR_Y, 48.0, APRON_Y - FLOOR_Y), BOARD.lightened(0.04 * VFX.hash01(i, 9)))
		m.line(Vector2(x, FLOOR_Y), Vector2(x, APRON_Y), Color("120a10"), 1.0)
	m.line(Vector2(-700.0, FLOOR_Y + 3.0), Vector2(1980.0, FLOOR_Y + 3.0), Color(0.0, 0.0, 0.0, 0.5), 3.0)
	m.line(Vector2(-700.0, FLOOR_Y), Vector2(1980.0, FLOOR_Y), Color(GILT, 0.8), 2.0)
	m.gradient(Rect2(-700.0, APRON_Y, 2680.0, 500.0), Color("0c070c"), Color("030204"))
	m.commit(ci)


## Paper shapes gathered into one vertex-coloured triangle list and handed to
## the canvas as a single command. The GL Compatibility renderer gives every
## polygon, circle and antialiased line a draw call of its own (a smooth line
## takes three), so a proscenium painted shape by shape costs hundreds of calls
## a frame; painted through a PaperMesh it costs one. Strokes feather their
## sides over a pixel, standing in for the renderer's antialiasing.
class PaperMesh extends RefCounted:
	const FEATHER := 1.0
	var _points := PackedVector2Array()
	var _colors := PackedColorArray()
	var _indices := PackedInt32Array()

	## Hands everything gathered so far to `ci` as one draw command.
	func commit(ci: CanvasItem) -> void:
		if not _indices.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _indices, _points, _colors)

	## A polygon with a colour per point (see VFX.shaded_colors).
	func polygon(pts: PackedVector2Array, cols: PackedColorArray) -> void:
		_add(pts, cols, Geometry2D.triangulate_polygon(pts))

	func fill(pts: PackedVector2Array, color: Color) -> void:
		polygon(pts, FinaleStage.flat(color, pts.size()))

	func rect(r: Rect2, color: Color) -> void:
		fill(FinaleStage.box(r), color)

	## `r` shaded from `top` down to `bottom`.
	func gradient(r: Rect2, top: Color, bottom: Color) -> void:
		polygon(FinaleStage.box(r), PackedColorArray([top, top, bottom, bottom]))

	func circle(c: Vector2, r: float, color: Color) -> void:
		fill(VFX.ellipse_points(c, r, r), color)

	## Quads between two matching rows of points: pleats, bands and washes.
	func band(a: PackedVector2Array, b: PackedVector2Array, a_cols: PackedColorArray, b_cols: PackedColorArray) -> void:
		var base := _points.size()
		var n := a.size()
		_points.append_array(a)
		_points.append_array(b)
		_colors.append_array(a_cols)
		_colors.append_array(b_cols)
		for i in range(base, base + n - 1):
			_indices.append_array(PackedInt32Array([i, i + 1, i + n + 1, i, i + n + 1, i + n]))

	## A line `width` wide along `pts`, mitred at the joints, its sides fading
	## to clear over FEATHER. Hairlines stay a pixel wide and fade instead.
	## Each point becomes a column of four vertices: feather, edge, edge, feather.
	func stroke(pts: PackedVector2Array, color: Color, width: float, closed := false) -> void:
		var n := pts.size()
		if n < 2:
			return
		var ink := Color(color, color.a * minf(width, 1.0))
		var column := PackedColorArray([Color(ink, 0.0), ink, ink, Color(ink, 0.0)])
		var half := maxf(width, 1.0) * 0.5
		var base := _points.size()
		var count := n + int(closed)
		for i in range(count):
			var p := pts[i % n]
			var side := _miter(pts, i % n, closed)
			_points.append_array(PackedVector2Array([p + side * (half + FEATHER), p + side * half, p - side * half, p - side * (half + FEATHER)]))
			_colors.append_array(column)
		for a in range(base, base + (count - 1) * 4, 4):
			_indices.append_array(PackedInt32Array([a, a + 1, a + 5, a, a + 5, a + 4,
				a + 1, a + 2, a + 6, a + 1, a + 6, a + 5, a + 2, a + 3, a + 7, a + 2, a + 7, a + 6]))

	func line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
		stroke(PackedVector2Array([a, b]), color, width)

	## An arc about `c` from angle `from` to `to`; a full turn closes on itself.
	func arc(c: Vector2, r: float, from: float, to: float, color: Color, width: float) -> void:
		var full := absf(to - from) >= TAU - 0.001
		var steps := maxi(6, ceili(absf(to - from) / TAU * 40.0))
		var pts := PackedVector2Array()
		for i in range(steps if full else steps + 1):
			pts.append(c + Vector2(r, 0.0).rotated(lerpf(from, to, float(i) / steps)))
		stroke(pts, color, width, full)

	## Paper cut-out: a soft offset shadow, a top-lit fill and a pale bevel on its upper edges.
	func cutout(pts: PackedVector2Array, fill_color: Color, shadow := Vector2(4.0, 5.0)) -> void:
		fill(Transform2D(0.0, shadow) * pts, Color(SHADOW, SHADOW.a * fill_color.a))
		polygon(pts, VFX.shaded_colors(pts, fill_color, 1.18, 0.78))
		bevel(pts, 0.8 * fill_color.a)

	## The catch-light a paper edge takes from above: VFX.draw_rim's upward
	## edges, with no side light (the stage is lit from the front).
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

	## VFX.draw_flame, batched.
	func flame(base: Vector2, height: float, width: float, t: float, phase: float, outer: Color, inner: Color) -> void:
		var tongues := VFX.flame_tongues(base, height, width, t, phase)
		fill(tongues[0], outer)
		fill(tongues[1], inner)

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

	func _add(pts: PackedVector2Array, cols: PackedColorArray, tris: PackedInt32Array) -> void:
		var base := _points.size()
		_points.append_array(pts)
		_colors.append_array(cols)
		for i in range(tris.size()):
			tris[i] += base
		_indices.append_array(tris)


## Everything in front of the actors: the gilt proscenium, its main curtain, the
## footlights on the apron and the house. The frame paints once; the lamps
## repaint only while one is burning and the audience's crowns while it sits
## (every flicker clock stops under reduced motion). The footlights are the
## house's only light: the frame, curtain and audience come up as they kindle
## and go black as they gutter, by modulation, with no repaint. `lamps` and
## `vow_lit` may be edited in place: any change is picked up next frame.
class FinaleFront extends Node2D:
	const LAMPS := 18
	const LAMP_X0 := 80.0
	const LAMP_STEP := 66.0
	const LAMP_Y := 606.0
	const VOWS := 5
	const KEYSTONE := Vector2(640.0, -88.0)
	const SWAGS := 12
	const TIE_Y := 300.0
	## Main curtain hem when flown (hidden behind the frame's head) and when down.
	const DROP_UP := -150.0
	const DROP_HEM := FLOOR_Y + 2.0
	const DROP_FOLDS := 30
	## The curtain's embroidered crest sits this far above its hem, clear of
	## where the knight's last flame comes to rest.
	const CREST_RISE := 400.0
	## Seat rows: floor y, seats, seat-back width. Past victors fill them centre-out.
	const SEAT_ROWS := [[655.0, 11, 70.0], [685.0, 12, 78.0]]
	const SEAT_PITCH := 104.0
	const SEAT_HEIGHT := 0.4
	const RISE_PX := 14.0
	## The follow-spot lands on the rostrum's top step, where the knight bows.
	const SPOT_FOOT := 560.0
	## How much of the house stays visible with every footlight out.
	const UNLIT := 0.2
	const FRAME := Color("1c1024")
	const LACQUER := Color("2e1c38")
	const TRACERY := Color("0a0610")
	const MAIN_HI := Color("8c2234")
	const MAIN_LO := Color("40101c")
	const TIN := Color("3c3844")
	const SEAT := Color("0d0911")
	const PATRON := Color("120c18")
	const SOCKET := Color("3a2a44")
	const SOCKET_LIT := Color("ffd166")
	const BEAM := Color(1.0, 0.9, 0.72)
	const QUAD_UV := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]

	## Footlight brightness 0..1, index 0 at stage left.
	var lamps: Array[float] = []
	## One keystone socket per vow, in Content.VOWS order.
	var vow_lit: Array[bool] = []
	## Great curtain, 0 = flown, 1 = down on the stage (a little past 1 reads as
	## its bounce). It is painted once, hanging, and flown by moving it; reduced
	## motion fades it in where it hangs instead.
	var main_drop := 0.0:
		set(value):
			main_drop = value
			var still := Feedback.motion_reduced
			_drop.visible = value > 0.0
			_drop.position.y = 0.0 if still else (DROP_UP - DROP_HEM) * (1.0 - value)
			_drop.modulate.a = clampf(value, 0.0, 1.0) if still else 1.0
	## Follow-spot strength 0..1 and the x it points at.
	var spot := 0.0:
		set(value):
			spot = value
			_beam.queue_redraw()
			_glow.queue_redraw()
	var spot_x := CENTER_X:
		set(value):
			spot_x = value
			_beam.queue_redraw()
			_glow.queue_redraw()
	## Past victors seated in the house (0..23) and how far they have stood (0..1).
	var house_count := 0:
		set(value):
			house_count = value
			_house.queue_redraw()
			_crowns.queue_redraw()
	var rise := 0.0:
		set(value):
			rise = value
			_house.queue_redraw()
			_crowns.queue_redraw()

	var _t := 0.0
	var _drawn_lamps: Array[float] = []
	var _drawn_vows: Array[bool] = []
	var _seats: Array[Rect2] = []
	## Each seat's place in the centre-out fill order.
	var _fill_rank: Array[int] = []
	var _drop: Node2D
	var _frame: Node2D
	var _flames: Node2D
	var _lamps: Node2D
	var _glow: Node2D
	var _beam: Node2D
	var _house: Node2D
	var _crowns: Node2D

	func _init() -> void:
		name = "FinaleFront"
		lamps.resize(LAMPS)
		lamps.fill(0.0)
		vow_lit.resize(VOWS)
		vow_lit.fill(false)
		for row in SEAT_ROWS:
			var n: int = row[1]
			var w: float = row[2]
			for i in range(n):
				var x := CENTER_X + (float(i) - float(n - 1) * 0.5) * SEAT_PITCH
				_seats.append(Rect2(x - w * 0.5, float(row[0]) - w * SEAT_HEIGHT, w, w * SEAT_HEIGHT))
		# Centre-out, nearer the stage first on a tie, so the first watcher sits below the bow.
		var order := range(_seats.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			return _seat_rank(a) < _seat_rank(b))
		_fill_rank.resize(_seats.size())
		for place in range(order.size()):
			_fill_rank[order[place]] = place
		_drop = FinaleStage.painter(self, _draw_drop)
		_drop.visible = false
		_frame = FinaleStage.painter(self, _draw_frame)
		_flames = FinaleStage.painter(self, _draw_flames)
		_lamps = FinaleStage.painter(self, _draw_lamps)
		_glow = FinaleStage.painter(self, _draw_glow, VFX.radial_material())
		_beam = FinaleStage.painter(self, _draw_beam, VFX.additive_material())
		_house = FinaleStage.painter(self, _draw_house)
		_crowns = FinaleStage.painter(self, _draw_crowns)

	func _seat_rank(i: int) -> float:
		return absf(_seats[i].get_center().x - CENTER_X) + float(i) * 0.01

	func _seated(i: int) -> bool:
		return _fill_rank[i] < house_count

	func _process(delta: float) -> void:
		var changed := lamps != _drawn_lamps or vow_lit != _drawn_vows
		var flicker := not Feedback.motion_reduced
		var burning := flicker and lamps.any(func(l: float) -> bool: return l > 0.0)
		var crowned := flicker and house_count > 0
		if burning or crowned:
			_t += delta
		if changed:
			_drawn_lamps = lamps.duplicate()
			_drawn_vows = vow_lit.duplicate()
			_lamps.queue_redraw()
			_beam.queue_redraw()
			_light_house()
		if changed or burning:
			_flames.queue_redraw()
			_glow.queue_redraw()
		if crowned:
			_crowns.queue_redraw()

	## The frame, the curtain and the audience take their light from the lamps.
	func _light_house() -> void:
		var sum := 0.0
		for l in lamps:
			sum += clampf(l, 0.0, 1.0)
		var k := lerpf(UNLIT, 1.0, sum / float(LAMPS))
		for piece: Node2D in [_drop, _frame, _house]:
			piece.modulate = Color(k, k, k, piece.modulate.a)

	func _clock() -> float:
		return 0.0 if Feedback.motion_reduced else _t

	func _lamp_base(i: int) -> Vector2:
		return Vector2(LAMP_X0 + LAMP_STEP * float(i), LAMP_Y)

	## Sockets ride the gilt band either side of the keystone; the middle one hangs as its pendant.
	func _socket(v: int) -> Vector2:
		if v == VOWS / 2:
			return KEYSTONE + Vector2(0.0, 60.0)
		var x := CENTER_X + float(v - VOWS / 2) * 78.0
		return Vector2(x, FinaleStage.arch_y(x) - 3.5)

	func _halo_scale() -> float:
		return 0.75 if Feedback.flash_reduced else 1.0

	# --- Main curtain ------------------------------------------------------------

	func _draw_drop(ci: CanvasItem) -> void:
		var hem := DROP_HEM
		var m := FinaleStage.PaperMesh.new()
		var tops := PackedVector2Array()
		var hems := PackedVector2Array()
		var shade := PackedColorArray()
		var lit := PackedColorArray()
		for i in range(DROP_FOLDS + 1):
			var u := float(i) / DROP_FOLDS
			var x := lerpf(OPEN_L - 20.0, OPEN_R + 20.0, u)
			var fold := 0.5 + 0.5 * cos(u * DROP_FOLDS * PI)
			var c := MAIN_LO.lerp(MAIN_HI, fold)
			tops.append(Vector2(x, hem - 1300.0))
			hems.append(Vector2(x, hem + 4.0 * fold))
			shade.append(c.darkened(0.5))
			lit.append(c)
		m.band(tops, hems, shade, lit)
		# Embroidered border, bullion fringe and the gilt flame crest at the centre.
		m.stroke(Transform2D(0.0, Vector2(0.0, -34.0)) * hems, GILT, 3.0)
		m.stroke(Transform2D(0.0, Vector2(0.0, -26.0)) * hems, GILT_LO, 1.5)
		_fringe(m, hems, 8, 10.0)
		var crest := Vector2(CENTER_X, hem - CREST_RISE)
		m.circle(crest, 46.0, MAIN_LO.darkened(0.35))
		m.arc(crest, 46.0, 0.0, TAU, GILT, 3.0)
		m.arc(crest, 39.0, 0.0, TAU, GILT_LO, 1.5)
		for s in range(16):
			m.circle(crest + Vector2(53.0, 0.0).rotated(TAU * float(s) / 16.0), 2.5, GILT)
		# The knight's flame crown, worked in gold thread.
		for k in range(4):
			var x := (float(k) - 1.5) * 10.0
			m.flame(crest + Vector2(x, 14.0), 36.0 - absf(x) * 0.7, 11.0, 0.0, float(k) * 2.1, GILT, GILT_HI)
		m.rect(Rect2(crest + Vector2(-22.0, 14.0), Vector2(44.0, 7.0)), GILT)
		m.commit(ci)

	## Bullion fringe hung under `line`: `per` straight threads per segment, alternating gold and shadow.
	func _fringe(m: FinaleStage.PaperMesh, line: PackedVector2Array, per: int, length: float) -> void:
		for i in range(line.size() - 1):
			for j in range(per):
				var p := line[i].lerp(line[i + 1], float(j) / float(per))
				m.rect(Rect2(p.x - 0.9, p.y, 1.8, length), GILT if j % 2 == 0 else GILT_LO)

	# --- Proscenium (static) -----------------------------------------------------

	func _draw_frame(ci: CanvasItem) -> void:
		var m := FinaleStage.PaperMesh.new()
		# The frame's own shadow on the stage, just inside the opening.
		var lip := FinaleStage.opening_edge(0.0, FLOOR_Y)
		m.band(lip, FinaleStage.opening_edge(34.0, FLOOR_Y), FinaleStage.flat(SHADOW, lip.size()), FinaleStage.flat(Color(SHADOW, 0.0), lip.size()))
		# Posts and head: lacquered board, lit a little from the footlights below.
		for x in [-700.0, OPEN_R]:
			var post := FinaleStage.box(Rect2(x, -400.0, 740.0, 1300.0))
			m.polygon(post, VFX.shaded_colors(post, FRAME, 0.8, 1.25))
		var arch := FinaleStage.opening_edge(0.0).slice(1, ARCH_STEPS + 2)
		arch.reverse()
		var head := PackedVector2Array([Vector2(OPEN_L, -900.0), Vector2(OPEN_R, -900.0)])
		head.append_array(arch)
		m.fill(head, FRAME.darkened(0.2))
		# Bevel bands: outer gilt rim, lacquer, then the bright gilt moulding at the opening.
		m.stroke(FinaleStage.opening_edge(-22.0), Color(GILT_LO, 0.9), 2.0)
		m.stroke(FinaleStage.opening_edge(-13.0), LACQUER, 10.0)
		m.stroke(FinaleStage.opening_edge(-3.5), GILT, 7.0)
		m.stroke(FinaleStage.opening_edge(-6.5), Color(GILT_HI, 0.8), 1.2)
		m.stroke(FinaleStage.opening_edge(-0.5), GILT_LO, 1.2)
		# Pierced quatrefoils in the spandrels; the ninth frames the keystone's sigil.
		for k in range(1, 5):
			for side: float in [-1.0, 1.0]:
				var x := CENTER_X + side * 130.0 * float(k)
				_quatrefoil(m, Vector2(x, FinaleStage.arch_y(x) - 44.0), 11.0)
		_draw_swags(m)
		_draw_keystone(m)
		for v in range(VOWS):
			m.circle(_socket(v), 7.5, GILT_LO)
			m.arc(_socket(v), 7.5, 0.0, TAU, GILT, 1.5)
		for side: float in [-1.0, 1.0]:
			_draw_side_drape(m, side)
			_draw_pilaster(m, side)
		# Plinths fall away into the dark house; the footlight trough runs along the apron.
		for x in [-700.0, OPEN_R]:
			m.gradient(Rect2(x, FLOOR_Y, 740.0, 300.0), LACQUER, VFX.VOID)
			m.line(Vector2(x, FLOOR_Y), Vector2(x + 740.0, FLOOR_Y), GILT, 2.0)
		m.cutout(FinaleStage.box(Rect2(OPEN_L, 604.0, OPEN_R - OPEN_L, 16.0)), LACQUER.darkened(0.2), Vector2(0.0, 4.0))
		m.line(Vector2(OPEN_L, 604.0), Vector2(OPEN_R, 604.0), GILT, 2.0)
		m.commit(ci)

	## A gilt-edged pilaster on each post with a lancet recess, so the frame reads carved.
	func _draw_pilaster(m: FinaleStage.PaperMesh, side: float) -> void:
		var cx := OPEN_L - 46.0 if side < 0.0 else OPEN_R + 46.0
		var shaft := Rect2(cx - 28.0, 96.0, 56.0, FLOOR_Y - 96.0)
		m.cutout(FinaleStage.box(shaft), LACQUER, Vector2(-side * 5.0, 5.0))
		m.stroke(FinaleStage.box(shaft.grow(-4.0)), Color(GILT_LO, 0.9), 1.5, true)
		# Pointed lancet: two arcs struck from the opposite springing points.
		var lancet := PackedVector2Array([Vector2(cx - 15.0, 560.0)])
		for j in range(7):
			var a := PI - float(j) / 6.0 * PI / 3.0
			lancet.append(Vector2(cx + 15.0 + 30.0 * cos(a), 160.0 - 30.0 * sin(a)))
		for j in range(1, 7):
			var a := float(6 - j) / 6.0 * PI / 3.0
			lancet.append(Vector2(cx - 15.0 + 30.0 * cos(a), 160.0 - 30.0 * sin(a)))
		lancet.append(Vector2(cx + 15.0, 560.0))
		m.fill(lancet, TRACERY)
		m.stroke(lancet, GILT, 1.5, true)
		m.line(Vector2(cx, 172.0), Vector2(cx, 548.0), Color(GILT_LO, 0.8), 1.5)
		for y: float in [76.0, FLOOR_Y - 20.0]:
			m.cutout(FinaleStage.box(Rect2(cx - 36.0, y, 72.0, 20.0)), GILT_LO, Vector2(-side * 3.0, 4.0))
			m.line(Vector2(cx - 36.0, y + 1.0), Vector2(cx + 36.0, y + 1.0), GILT_HI, 1.5)

	func _quatrefoil(m: FinaleStage.PaperMesh, c: Vector2, r: float) -> void:
		for a in range(4):
			m.circle(c + Vector2(r, 0.0).rotated(float(a) * PI * 0.5), r * 0.86, TRACERY)
		for a in range(4):
			var turn := float(a) * PI * 0.5
			m.arc(c + Vector2(r, 0.0).rotated(turn), r * 0.86 + 1.0, turn - 1.9, turn + 1.9, Color(GILT, 0.75), 1.5)
		m.arc(c, r * 2.25, 0.0, TAU, Color(GILT_LO, 0.9), 1.5)

	func _draw_swags(m: FinaleStage.PaperMesh) -> void:
		var step := (OPEN_R - OPEN_L) / float(SWAGS)
		var hem := PackedVector2Array()
		for i in range(SWAGS):
			var x0 := OPEN_L + step * float(i)
			var top := PackedVector2Array()
			var sag := PackedVector2Array()
			for j in range(13):
				var x := x0 + step * float(j) / 12.0
				top.append(Vector2(x, FinaleStage.arch_y(x) + 4.0))
				sag.append(Vector2(x, FinaleStage.arch_y(x) + 26.0 + sin(float(j) / 12.0 * PI) * 26.0))
			var body := top.duplicate()
			var under := sag.duplicate()
			under.reverse()
			body.append_array(under)
			m.cutout(body, VELVET_HI, Vector2(0.0, 6.0))
			# Two folds echo the sag.
			for f: float in [0.45, 0.75]:
				var fold := PackedVector2Array()
				for j in range(1, 12):
					fold.append(top[j].lerp(sag[j], f))
				m.stroke(fold, Color(VELVET_LO, 0.7), 2.0)
			hem.append_array(sag)
		_fringe(m, hem, 3, 6.0)
		# Gilt rosettes and tassels where the swags meet.
		for i in range(1, SWAGS):
			var x := OPEN_L + step * float(i)
			var knot := Vector2(x, FinaleStage.arch_y(x) + 30.0)
			m.fill(PackedVector2Array([knot, knot + Vector2(-5.0, 18.0), knot + Vector2(5.0, 18.0)]), GILT_LO)
			m.circle(knot, 5.0, GILT)
			m.circle(knot + Vector2(-1.5, -1.5), 1.8, GILT_HI)

	func _draw_keystone(m: FinaleStage.PaperMesh) -> void:
		var k := KEYSTONE
		var stone := PackedVector2Array([k + Vector2(-46.0, -46.0), k + Vector2(46.0, -46.0), k + Vector2(32.0, 44.0), k + Vector2(0.0, 58.0), k + Vector2(-32.0, 44.0)])
		m.cutout(stone, LACQUER, Vector2(3.0, 6.0))
		m.stroke(stone, GILT, 2.5, true)
		var c := k + Vector2(0.0, 2.0)
		_quatrefoil(m, c, 13.0)
		# The throne's ember sigil, carved and painted rather than burning.
		m.arc(c, 17.0, 0.0, TAU, Color(FinaleStage.fire(VFX.ORANGE), 0.45), 1.5)
		m.flame(c + Vector2(0.0, 12.0), 30.0, 17.0, 0.0, 0.4, FinaleStage.fire(LAMP_FIRE), FinaleStage.fire(VFX.GOLD))

	func _draw_side_drape(m: FinaleStage.PaperMesh, side: float) -> void:
		var post := OPEN_L if side < 0.0 else OPEN_R
		var into := -side
		var top_y := FinaleStage.arch_y(post + into * 150.0) + 18.0
		var inner := PackedVector2Array()
		var outer := PackedVector2Array()
		for j in range(17):
			var y := lerpf(top_y, FLOOR_Y, float(j) / 16.0)
			var reach: float
			if y < TIE_Y:
				reach = lerpf(150.0, 62.0, ease((y - top_y) / (TIE_Y - top_y), 0.6))
			else:
				reach = lerpf(62.0, 96.0, ease((y - TIE_Y) / (FLOOR_Y - TIE_Y), 1.8))
			inner.append(Vector2(post + into * reach, y))
			outer.append(Vector2(post - into * 4.0, y))
		# Four pleats, each a lit ridge falling into shadow.
		var ridge := FinaleStage.flat(VELVET_HI.darkened(0.15), inner.size())
		var hollow := FinaleStage.flat(VELVET_LO.lerp(VELVET_HI, 0.25), inner.size())
		for p in range(4):
			var a := PackedVector2Array()
			var b := PackedVector2Array()
			for j in range(inner.size()):
				a.append(outer[j].lerp(inner[j], float(p) / 4.0))
				b.append(outer[j].lerp(inner[j], float(p + 1) / 4.0))
			m.band(a, b, ridge, hollow)
		m.stroke(inner, Color(VELVET_HI.lightened(0.3), 0.8), 1.5)
		# Gilt tie-back rope and its tassel.
		var tie := Vector2(post + into * 66.0, TIE_Y - 2.0)
		m.line(Vector2(post, TIE_Y - 4.0), tie, GILT, 5.0)
		m.line(Vector2(post, TIE_Y - 5.5), tie - Vector2(0.0, 1.5), Color(GILT_HI, 0.7), 1.2)
		var tassel := Vector2(post + into * 12.0, TIE_Y)
		m.fill(PackedVector2Array([tassel, tassel + Vector2(-7.0, 30.0), tassel + Vector2(7.0, 30.0)]), GILT_LO)
		_fringe(m, PackedVector2Array([tassel + Vector2(-6.0, 14.0), tassel + Vector2(6.0, 14.0)]), 5, 16.0)
		m.circle(tassel + Vector2(0.0, 3.0), 5.0, GILT)

	# --- Footlights, sockets, glow and the follow-spot ---------------------------

	## The footlights' flames, the only part of them that flickers.
	func _draw_flames(ci: CanvasItem) -> void:
		var m := FinaleStage.PaperMesh.new()
		var t := _clock()
		for i in range(LAMPS):
			var l := clampf(lamps[i], 0.0, 1.0)
			if l > 0.0:
				m.flame(_lamp_base(i), 22.0 * l, 8.0 * (0.6 + 0.4 * l), t, float(i) * 1.7, FinaleStage.fire(LAMP_FIRE), FinaleStage.fire(VFX.GOLD))
		m.commit(ci)

	## The lamps' tin and the keystone's gems, repainted only when one changes.
	func _draw_lamps(ci: CanvasItem) -> void:
		var m := FinaleStage.PaperMesh.new()
		for i in range(LAMPS):
			var base := _lamp_base(i)
			var l := clampf(lamps[i], 0.0, 1.0)
			if l <= 0.0:
				m.line(base, base + Vector2(0.0, -8.0), ASH_EDGE, 1.5)
			# A scallop-shell reflector turns its back to the house and hides
			# the wick; its ribs and lip catch the flame behind it.
			var hinge := base + Vector2(0.0, 5.0)
			var shell := PackedVector2Array([base + Vector2(8.0, 13.0), base + Vector2(-8.0, 13.0)])
			for k in range(9):
				shell.append(hinge + Vector2(-12.0, 0.0).rotated(float(k) / 8.0 * PI))
			m.polygon(shell, VFX.shaded_colors(shell, TIN, 1.0, 0.55))
			for k in range(1, 8, 2):
				m.line(base + Vector2(0.0, 10.0), hinge + Vector2(-11.0, 0.0).rotated(float(k) / 8.0 * PI), Color(VFX.VOID, 0.5), 1.0)
			m.stroke(shell.slice(2), Color(GILT_HI, 0.15 + 0.75 * l), 1.5)
		for v in range(VOWS):
			var p := _socket(v)
			var gem := PackedVector2Array([p + Vector2(0.0, -5.0), p + Vector2(4.0, 0.0), p + Vector2(0.0, 5.0), p + Vector2(-4.0, 0.0)])
			m.fill(gem, SOCKET_LIT if vow_lit[v] else SOCKET)
			if vow_lit[v]:
				m.circle(p + Vector2(-1.2, -1.6), 1.3, VFX.HOT)
		m.commit(ci)

	func _draw_glow(ci: CanvasItem) -> void:
		var k := _halo_scale()
		var t := _clock()
		for i in range(LAMPS):
			var l := clampf(lamps[i], 0.0, 1.0)
			var breathe := 1.0 + 0.05 * sin(t * 9.0 + float(i) * 1.3)
			VFX.draw_radial(ci, _lamp_base(i) + Vector2(0.0, -10.0), 46.0 * (0.5 + 0.5 * l) * breathe, Color(VFX.GOLD, 0.3 * l * k))
		for v in range(VOWS):
			if vow_lit[v]:
				VFX.draw_radial(ci, _socket(v), 20.0, Color(SOCKET_LIT, 0.55 * k))
		if spot > 0.0:
			# The spot's pool where the beam lands on the rostrum: a flattened radial.
			var pool := Vector2(spot_x, SPOT_FOOT)
			ci.draw_primitive(Transform2D(0.0, Vector2(240.0, 48.0), 0.0, pool - Vector2(120.0, 24.0)) * PackedVector2Array(QUAD_UV),
				FinaleStage.flat(Color(VFX.HOT, 0.32 * spot * k), 4), PackedVector2Array(QUAD_UV))

	func _draw_beam(ci: CanvasItem) -> void:
		var k := _halo_scale()
		var m := FinaleStage.PaperMesh.new()
		# Footlight wash climbing the curtain, fed by each lamp so it grows as they kindle.
		if lamps.any(func(l: float) -> bool: return l > 0.0):
			var tops := PackedVector2Array()
			var feet := PackedVector2Array()
			var warm := PackedColorArray()
			for i in range(LAMPS):
				tops.append(Vector2(_lamp_base(i).x, 380.0))
				feet.append(_lamp_base(i))
				warm.append(Color(VFX.GOLD, 0.07 * clampf(lamps[i], 0.0, 1.0) * k))
			m.band(tops, feet, FinaleStage.flat(Color(VFX.GOLD, 0.0), LAMPS), warm)
		if spot > 0.0:
			# Follow-spot from the booth: an even shaft, brighter where it lands, with feathered sides.
			var clear := Color(BEAM, 0.0)
			var high := Color(BEAM, 0.06 * spot * k)
			var low := Color(BEAM, 0.12 * spot * k)
			m.band(PackedVector2Array([Vector2(spot_x - 48.0, -100.0), Vector2(spot_x - 30.0, -100.0), Vector2(spot_x + 30.0, -100.0), Vector2(spot_x + 48.0, -100.0)]),
				PackedVector2Array([Vector2(spot_x - 112.0, SPOT_FOOT), Vector2(spot_x - 80.0, SPOT_FOOT), Vector2(spot_x + 80.0, SPOT_FOOT), Vector2(spot_x + 112.0, SPOT_FOOT)]),
				PackedColorArray([clear, high, high, clear]), PackedColorArray([clear, low, low, clear]))
		m.commit(ci)

	# --- The house -----------------------------------------------------------------

	func _draw_house(ci: CanvasItem) -> void:
		var m := FinaleStage.PaperMesh.new()
		var first := 0
		for row in SEAT_ROWS:
			var count: int = row[1]
			# Each row's patrons sit behind their own seat-backs and in front of the row before.
			for i in range(first, first + count):
				if _seated(i):
					_draw_patron(m, _seats[i])
			for i in range(first, first + count):
				var r := _seats[i]
				var dome := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.5)
				var back := PackedVector2Array([r.position + Vector2(0.0, r.size.y + 60.0)])
				for a in range(9):
					back.append(dome + Vector2(-r.size.x * 0.5, 0.0).rotated(float(a) / 8.0 * PI) * Vector2(1.0, r.size.y / r.size.x))
				back.append(r.position + Vector2(r.size.x, r.size.y + 60.0))
				m.polygon(back, VFX.shaded_colors(back, SEAT, 1.5, 0.6))
				m.stroke(back.slice(1, 10), Color(VFX.GOLD, 0.35), 1.2)
			first += count
		m.commit(ci)

	## Where a past victor's head sits in its seat, risen by `rise`.
	func _head(seat: Rect2) -> Vector2:
		return Vector2(seat.get_center().x, seat.position.y - RISE_PX * rise - 24.0 * seat.size.x / 70.0)

	## A past victor seen from behind: shoulders and head, rimmed by the stage light.
	func _draw_patron(m: FinaleStage.PaperMesh, seat: Rect2) -> void:
		var sc := seat.size.x / 70.0
		var head := _head(seat)
		var top := head + Vector2(0.0, 24.0) * sc
		var body := PackedVector2Array([top + Vector2(-27.0, 20.0) * sc, top + Vector2(-24.0, -4.0) * sc, top + Vector2(-12.0, -12.0) * sc,
			top + Vector2(12.0, -12.0) * sc, top + Vector2(24.0, -4.0) * sc, top + Vector2(27.0, 20.0) * sc])
		m.fill(body, PATRON)
		m.circle(head, 13.0 * sc, PATRON)
		var rim := Color(VFX.GOLD, 0.5)
		m.arc(head, 13.0 * sc, PI * 1.2, PI * 1.8, rim, 1.5)
		m.stroke(body.slice(1, 5), rim, 1.2)

	## Each past victor's small lit crown; from the tenth victory they flare as the house stands.
	func _draw_crowns(ci: CanvasItem) -> void:
		var m := FinaleStage.PaperMesh.new()
		var t := _clock()
		var flare := 1.0 + 0.7 * rise
		for i in range(_seats.size()):
			if not _seated(i):
				continue
			var sc := _seats[i].size.x / 70.0
			var head := _head(_seats[i])
			for k in range(3):
				m.flame(head + Vector2(float(k - 1) * 5.0, -11.0) * sc, (6.0 + 3.0 * float(k == 1)) * sc * flare, 4.5 * sc, t, float(i * 3 + k),
					FinaleStage.fire(VFX.GOLD), FinaleStage.fire(VFX.HOT))
		m.commit(ci)


## The paper bill lowered from the flies on two cords at the curtain call. It
## hangs from the grid like a pendulum: lowering it kicks a small swing that
## decays on its own. The sheet grows to fit its rows; PlaybillText sets the type.
## `rows` are "ROLE — gloss" Strings or {"sigils": [boon ids]} for the run's
## boon sigils; the first `revealed` rows are inked in.
class Playbill extends Node2D:
	const WIDTH := 640.0
	## Sheet top to the first row (title, subtitle, rule), the row leading and the foot, in world units.
	const HEADER := 86.0
	const LINE := 22.0
	const FOOTER := 24.0
	const SIGIL_LINES := 1.6
	## The theatre framing's scale: type is sized so it reads at this zoom.
	const REF_SCALE := 0.86
	const SIDE_INSET := 26.0
	## The grid the cords hang from, and how far below it the sheet's top rests (world y 10).
	const GRID := Vector2(640.0, -420.0)
	const LOWERED := 430.0
	const CORD_X := 280.0
	const CHAMFER := 12.0
	const PAPER := Color("e6d8bc")
	const PAPER_EDGE := Color("b09a78")
	const INK_RED := Color("7a1a2a")
	const CORD := Color("8a7a5a")
	## Pendulum: natural frequency (rad/s), damping ratio, kick per unit change of drop speed.
	const SWING_RATE := 3.9
	const SWING_DAMP := 0.3
	const SWING_KICK := 0.08
	const SWING_MAX := 0.06

	## 0 = flown out of sight, 1 = hanging in place (TRANS_BACK overshoot is fine).
	var drop := 0.0:
		set(value):
			drop = value
			queue_redraw()
			set_process(true)
	var title := "THE DESCENT":
		set(value):
			title = value
			version += 1
	var subtitle := "IN EIGHT CHAMBERS · EVERY KNIGHT REMEMBERED":
		set(value):
			subtitle = value
			version += 1
	var rows: Array = []:
		set(value):
			rows = value
			_measure_rows()
	var revealed := 0:
		set(value):
			revealed = value
			version += 1
	## Bumped on every text change so PlaybillText knows to set its type again.
	var version := 0
	## Lines each row takes and the sheet they make, fixed per `rows` so the
	## layout never shifts while the camera zooms.
	var row_lines: Array[float] = []
	var sheet := Vector2(WIDTH, HEADER + FOOTER)

	var _last_drop := 0.0
	var _drop_speed := 0.0
	var _swing_speed := 0.0

	func _init() -> void:
		name = "Playbill"
		position = GRID

	func _measure_rows() -> void:
		row_lines.clear()
		var lines := 0.0
		for row in rows:
			var n := SIGIL_LINES if row is Dictionary else 1.0
			row_lines.append(n)
			lines += n
		sheet.y = HEADER + FOOTER + LINE * lines
		version += 1
		queue_redraw()

	func _process(delta: float) -> void:
		if delta <= 0.0:
			return
		var speed := (drop - _last_drop) / delta
		if Feedback.motion_reduced:
			rotation = 0.0
			_swing_speed = 0.0
		else:
			_swing_speed += (speed - _drop_speed) * SWING_KICK
			_swing_speed -= (SWING_RATE * SWING_RATE * rotation + 2.0 * SWING_DAMP * SWING_RATE * _swing_speed) * delta
			rotation = clampf(rotation + _swing_speed * delta, -SWING_MAX, SWING_MAX)
		_drop_speed = speed
		_last_drop = drop
		if speed == 0.0 and absf(rotation) < 0.0005 and absf(_swing_speed) < 0.0005:
			rotation = 0.0
			_swing_speed = 0.0
			set_process(false)

	func _sheet_top() -> float:
		return LOWERED * (1.0 if Feedback.motion_reduced else drop)

	## Reduced motion fades the bill in already hanging.
	func ink_alpha() -> float:
		if not is_visible_in_tree() or drop <= 0.0:
			return 0.0
		return modulate.a * (clampf(drop, 0.0, 1.0) if Feedback.motion_reduced else 1.0)

	## Canvas transform of the sheet's top-left corner, swing included.
	func sheet_transform() -> Transform2D:
		return get_global_transform_with_canvas() * Transform2D(0.0, Vector2(-WIDTH * 0.5, _sheet_top()))

	## The sheet in screen pixels, before its swing: where PlaybillText sets the type.
	func screen_rect() -> Rect2:
		var xf := sheet_transform()
		return Rect2(xf.origin, sheet * xf.get_scale())

	func _outline(inset: float, top: float) -> PackedVector2Array:
		var r := Rect2(-WIDTH * 0.5 + inset, top + inset, WIDTH - inset * 2.0, sheet.y - inset * 2.0)
		var c := CHAMFER
		return PackedVector2Array([r.position + Vector2(c, 0.0), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c), Vector2(r.end.x, r.end.y - c),
			r.end - Vector2(c, 0.0), Vector2(r.position.x + c, r.end.y), Vector2(r.position.x, r.end.y - c), r.position + Vector2(0.0, c)])

	func _draw() -> void:
		var a := ink_alpha() / maxf(modulate.a, 0.001)
		if a <= 0.0:
			return
		var top := _sheet_top()
		var m := FinaleStage.PaperMesh.new()
		for side: float in [-1.0, 1.0]:
			m.line(Vector2(side * CORD_X, -400.0 - top), Vector2(side * CORD_X, top + 12.0), Color(CORD, a), 1.5)
		var paper := _outline(0.0, top)
		m.cutout(paper, Color(PAPER, a), Vector2(10.0, 12.0))
		m.stroke(paper, Color(PAPER_EDGE, a), 2.0, true)
		for inset: float in [12.0, 17.0]:
			m.stroke(_outline(inset, top), Color(INK_RED, a), 2.0 if inset < 15.0 else 1.0, true)
		for side: float in [-1.0, 1.0]:
			var eye := Vector2(side * CORD_X, top + 12.0)
			m.circle(eye, 4.0, Color(PAPER_EDGE.darkened(0.3), a))
			m.arc(eye, 4.0, 0.0, TAU, Color(GILT, a), 1.5)
		m.commit(self)


## The bill's type, set in screen space on the text layer whenever the sheet
## moves, so the serif never blurs through the camera zoom. Sizes are authored
## at the theatre framing and scale with the sheet, never below 14 px.
class PlaybillText extends Control:
	const TITLE_PX := 30.0
	const SUB_PX := 15.0
	const ROLE_PX := 14.0
	const GLOSS_PX := 16.0
	const MIN_PX := 14
	const SIGIL_R := 11.0
	const FADE := 0.4
	## Baselines of the title and subtitle and the rule under them, in world units from the sheet top.
	const TITLE_Y := 52.0
	const SUB_Y := 72.0
	const RULE_Y := 81.0
	const INK := Color("2a1410")
	const INK_RED := Color("7a1a2a")
	const MEDAL := Color("2a1a24")

	var bill: Playbill
	var _xf := Transform2D()
	var _row_alpha: Array[float] = []
	var _version := -1
	var _ink := -1.0

	func _init(for_bill: Playbill = null) -> void:
		name = "PlaybillText"
		bill = for_bill
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if bill == null or not is_instance_valid(bill):
			return
		var changed := bill.version != _version
		_version = bill.version
		_row_alpha.resize(bill.rows.size())
		for i in range(_row_alpha.size()):
			var target := 1.0 if i < bill.revealed else 0.0
			if _row_alpha[i] != target:
				_row_alpha[i] = move_toward(_row_alpha[i], target, delta / FADE)
				changed = true
		var xf := bill.sheet_transform()
		var ink := bill.ink_alpha()
		if changed or xf != _xf or ink != _ink:
			_xf = xf
			_ink = ink
			position = xf.origin
			rotation = xf.get_rotation()
			# A Control is culled by its own rect, so it must cover the sheet.
			size = bill.sheet * xf.get_scale()
			queue_redraw()

	func _draw() -> void:
		if _ink <= 0.0 or bill.row_lines.size() != bill.rows.size():
			return
		var font := UI._heading_font()
		var s := _xf.get_scale().x
		var k := s / Playbill.REF_SCALE
		var w := size.x
		_line(font, [[bill.title, TITLE_PX * k, INK]], TITLE_Y * s, w, 1.0)
		_line(font, [[bill.subtitle, SUB_PX * k, INK_RED]], SUB_Y * s, w, 1.0)
		var rule := RULE_Y * s
		var d := 4.0 * k
		draw_line(Vector2(w * 0.3, rule), Vector2(w * 0.7, rule), Color(INK_RED, _ink * 0.8), 1.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, rule - d), Vector2(w * 0.5 + d, rule), Vector2(w * 0.5, rule + d), Vector2(w * 0.5 - d, rule)]), Color(INK_RED, _ink))
		var y := Playbill.HEADER
		for i in range(bill.rows.size()):
			var row = bill.rows[i]
			var h := Playbill.LINE * bill.row_lines[i]
			if _row_alpha[i] > 0.0:
				if row is Dictionary:
					_sigils(row.get("sigils", []), (y + h * 0.5) * s, w, k, _row_alpha[i])
				else:
					_row(font, str(row), (y + Playbill.LINE * 0.5 + 5.5) * s, w, k, _row_alpha[i])
			y += h

	## "ROLE — gloss": the role in red, the gloss in ink.
	func _row(font: Font, text: String, baseline: float, w: float, k: float, alpha: float) -> void:
		var parts := text.split(" — ", true, 1)
		_line(font, [[parts[0], ROLE_PX * k, INK_RED], ["  —  ", ROLE_PX * k, Color(INK, 0.5)], [parts[1], GLOSS_PX * k, INK]], baseline, w, alpha)

	## Centred run of spans [text, px, colour]. Too wide for the sheet, it
	## shrinks to fit, but never under MIN_PX.
	func _line(font: Font, spans: Array, baseline: float, w: float, alpha: float) -> void:
		var room := w - Playbill.SIDE_INSET * 2.0 * _xf.get_scale().x
		var fit := minf(1.0, room / maxf(_span_width(font, spans, 1.0), 1.0))
		var x := (w - _span_width(font, spans, fit)) * 0.5
		for span in spans:
			var px := _px(span[1] * fit)
			var c: Color = span[2]
			draw_string(font, Vector2(x, baseline), span[0], HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(c, c.a * alpha * _ink))
			x += font.get_string_size(span[0], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x

	func _span_width(font: Font, spans: Array, fit: float) -> float:
		var total := 0.0
		for span in spans:
			total += font.get_string_size(span[0], HORIZONTAL_ALIGNMENT_LEFT, -1, _px(span[1] * fit)).x
		return total

	static func _px(size: float) -> int:
		return maxi(MIN_PX, roundi(size))

	## The run's boons pinned under the knight as small medallions, in pick order.
	func _sigils(ids: Array, cy: float, w: float, k: float, alpha: float) -> void:
		var n := mini(ids.size(), 8)
		var r := SIGIL_R * k
		var a := alpha * _ink
		for j in range(n):
			var c := Vector2(w * 0.5 + (float(j) - float(n - 1) * 0.5) * r * 2.8, cy)
			draw_circle(c, r + 3.0 * k, Color(MEDAL, a))
			draw_arc(c, r + 3.0 * k, 0.0, TAU, 20, Color(GILT, a), 1.5, true)
			draw_circle(c + Vector2(0.0, -r - 3.0 * k), 2.2 * k, Color(GILT_HI, a))
			BoonArt.draw(self, str(ids[j]), c, r * 0.8, Color(_sigil_tint(str(ids[j])), a))

	static func _sigil_tint(id: String) -> Color:
		for u in Content.UPGRADES:
			if u.id == id:
				return Content.rarity_color(Content.upgrade_rarity(u))
		return Content.rarity_color("common")
