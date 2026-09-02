extends RefCounted
## Shared procedural drawing helpers for the visual layer: additive radial lights,
## vertex-shaded silhouettes, rim edges, contact shadows and slash ribbons.
## Everything here is geometry plus tiny canvas_item shaders; no textures exist.
## Consumers preload this script as `VFX` so it never depends on the class cache.

const VOID := Color("07050b")
const NAVY := Color("130d21")
const TYRIAN := Color("221538")
const MORTAR := Color("312347")
const SLATE := Color("5e4b75")
const RIM := Color("7e639e")
const GOLD := Color("ffa827")
const ORANGE := Color("ff5500")
const EMBER := Color("ff2a00")
const HOT := Color("fff0d0")
const TEAL := Color("2be4c8")
const JOINT := Color("0e0917")

## Radial falloff driven by the primitive's UVs; the vertex COLOR carries the tint.
const RADIAL_SHADER := """
shader_type canvas_item;
render_mode blend_add, unshaded;

void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0;
	float glow = 1.0 - smoothstep(0.0, 1.0, d);
	glow *= glow;
	COLOR = vec4(COLOR.rgb, COLOR.a * glow);
}
"""

## Fullscreen edge falloff. Kept below the HUD layer so corner panels stay crisp.
const VIGNETTE_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform vec4 edge_color : source_color = vec4(0.027, 0.02, 0.043, 0.78);
uniform float inner_radius = 0.30;
uniform float outer_radius = 0.72;
uniform float power = 2.1;

void fragment() {
	float r = length(UV - vec2(0.5));
	float v = pow(smoothstep(inner_radius, outer_radius, r), power);
	COLOR = vec4(edge_color.rgb, edge_color.a * v);
}
"""

static var _radial_material: ShaderMaterial
static var _vignette_material: ShaderMaterial
static var _additive_material: CanvasItemMaterial
static var _unit_circle := PackedVector2Array()

static func radial_material() -> ShaderMaterial:
	if _radial_material == null:
		var shader := Shader.new()
		shader.code = RADIAL_SHADER
		_radial_material = ShaderMaterial.new()
		_radial_material.shader = shader
	return _radial_material

static func vignette_material() -> ShaderMaterial:
	if _vignette_material == null:
		var shader := Shader.new()
		shader.code = VIGNETTE_SHADER
		_vignette_material = ShaderMaterial.new()
		_vignette_material.shader = shader
	return _vignette_material

static func additive_material() -> CanvasItemMaterial:
	if _additive_material == null:
		_additive_material = CanvasItemMaterial.new()
		_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_material

## Deterministic 0..1 noise so backdrops and masonry never reshuffle between frames.
static func hash01(i: int, salt: int = 0) -> float:
	var x := sin(float(i) * 12.9898 + float(salt) * 78.233) * 43758.5453
	return x - floor(x)

static func unit_circle() -> PackedVector2Array:
	if _unit_circle.is_empty():
		for i in range(24):
			var a := TAU * float(i) / 24.0
			_unit_circle.append(Vector2(cos(a), sin(a)))
	return _unit_circle

static func ellipse_points(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	return Transform2D(0.0, Vector2(rx, ry), 0.0, center) * unit_circle()

## One quad through the radial shader. The owning CanvasItem must use radial_material().
static func draw_radial(ci: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0 or color.a <= 0.0:
		return
	ci.draw_primitive(
		PackedVector2Array([
			center + Vector2(-radius, -radius), center + Vector2(radius, -radius),
			center + Vector2(radius, radius), center + Vector2(-radius, radius),
		]),
		PackedColorArray([color, color, color, color]),
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])
	)

static func draw_vgradient(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
	]), PackedColorArray([top, top, bottom, bottom]))

static func draw_ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float, color: Color) -> void:
	ci.draw_colored_polygon(ellipse_points(center, rx, ry), color)

static func draw_ellipse_ring(ci: CanvasItem, center: Vector2, rx: float, ry: float, color: Color, width: float) -> void:
	var pts := ellipse_points(center, rx, ry)
	pts.append(pts[0])
	ci.draw_polyline(pts, color, width, true)

## Ground-hugging shadow. `air` is 0 while standing and 1 fully airborne; the
## ellipse shrinks and fades so actors still read as lifting off the stones.
static func draw_contact_shadow(ci: CanvasItem, foot: Vector2, width: float, height: float, air: float) -> void:
	var k := clampf(air, 0.0, 1.0)
	var alpha := lerpf(0.65, 0.16, k)
	var rx := width * 0.5 * lerpf(1.0, 0.55, k)
	var ry := height * 0.5 * lerpf(1.0, 0.6, k)
	draw_ellipse(ci, foot, rx * 1.25, ry * 1.3, Color(0.0, 0.0, 0.0, alpha * 0.3))
	draw_ellipse(ci, foot, rx, ry, Color(0.0, 0.0, 0.0, alpha))

## Per-vertex top-down shading: brighter at the head, darker toward the feet.
static func shaded_colors(pts: PackedVector2Array, base: Color, top_mul: float = 1.15, bot_mul: float = 0.75) -> PackedColorArray:
	var lo := INF
	var hi := -INF
	for p in pts:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var span := maxf(hi - lo, 0.001)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for i in range(pts.size()):
		var m := lerpf(top_mul, bot_mul, (pts[i].y - lo) / span)
		cols[i] = Color(base.r * m, base.g * m, base.b * m, base.a)
	return cols

static func draw_shaded_polygon(ci: CanvasItem, pts: PackedVector2Array, base: Color, shade: bool = true) -> void:
	if shade:
		ci.draw_polygon(pts, shaded_colors(pts, base))
	else:
		ci.draw_colored_polygon(pts, base)

## Dual rim light: edges facing `facing` catch the warm flame, edges facing away
## get a cold slate rim, and upward edges receive a faint stone catch-light.
static func draw_rim(ci: CanvasItem, pts: PackedVector2Array, facing: float, strength: float = 1.0, warm: Color = GOLD, cold: Color = SLATE) -> void:
	var n := pts.size()
	if n < 3:
		return
	var centroid := Vector2.ZERO
	for p in pts:
		centroid += p
	centroid /= float(n)
	for i in range(n):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var edge := b - a
		if edge.length_squared() < 1.0:
			continue
		var normal := Vector2(edge.y, -edge.x).normalized()
		if normal.dot((a + b) * 0.5 - centroid) < 0.0:
			normal = -normal
		var side := normal.x * facing
		if side > 0.35:
			ci.draw_line(a, b, Color(warm.r, warm.g, warm.b, 0.85 * strength * side), 1.5, true)
		elif side < -0.35:
			ci.draw_line(a, b, Color(cold.r, cold.g, cold.b, 0.45 * strength * -side), 1.5, true)
		elif -normal.y > 0.6:
			ci.draw_line(a, b, Color(RIM.r, RIM.g, RIM.b, 0.35 * strength * -normal.y), 1.0, true)

## Rim arcs for round heads: warm crescent on the facing side, cold on the back.
static func draw_rim_circle(ci: CanvasItem, center: Vector2, radius: float, facing: float, strength: float = 1.0) -> void:
	var front := 0.0 if facing >= 0.0 else PI
	ci.draw_arc(center, radius, front - 1.25, front + 1.25, 12, Color(GOLD.r, GOLD.g, GOLD.b, 0.8 * strength), 1.5, true)
	ci.draw_arc(center, radius, front + PI - 1.1, front + PI + 1.1, 10, Color(SLATE.r, SLATE.g, SLATE.b, 0.45 * strength), 1.5, true)

## Tapered crescent for sword sweeps. The head is white-hot, the middle gold, the
## tail dissolves into ember. `progress` reveals the sweep from tail to head.
static func slash_ribbon(ci: CanvasItem, origin: Vector2, radius: float, arc: float, facing: float, progress: float, thickness: float, alpha: float) -> void:
	var segs := 14
	var sweep := arc * clampf(progress, 0.06, 1.0)
	var dir := 1.0 if facing >= 0.0 else -1.0
	var start := -arc * 0.5 if facing >= 0.0 else PI + arc * 0.5
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var outer_cols := PackedColorArray()
	var inner_cols := PackedColorArray()
	for i in range(segs + 1):
		var u := float(i) / float(segs)
		var ang := start + dir * sweep * u
		var width := maxf(1.5, thickness * (0.22 + 0.78 * u))
		var ray := Vector2(cos(ang), sin(ang))
		outer.append(origin + ray * radius)
		inner.append(origin + ray * (radius - width))
		var c: Color
		if u < 0.5:
			c = Color(EMBER.r, EMBER.g, EMBER.b, 0.0).lerp(GOLD, u * 2.0)
		else:
			c = GOLD.lerp(Color.WHITE, (u - 0.5) * 2.0)
		c.a *= alpha
		outer_cols.append(c)
		inner_cols.append(Color(c.r, c.g, c.b, c.a * 0.85))
	inner.reverse()
	inner_cols.reverse()
	outer.append_array(inner)
	outer_cols.append_array(inner_cols)
	ci.draw_polygon(outer, outer_cols)

## Small emissive: soft halo, bright core and a white-hot pinpoint.
static func draw_ember_dot(ci: CanvasItem, pos: Vector2, radius: float, color: Color, intensity: float = 1.0) -> void:
	if intensity <= 0.0:
		return
	ci.draw_circle(pos, radius * 2.8, Color(color, 0.14 * intensity))
	ci.draw_circle(pos, radius * 1.6, Color(color, 0.4 * intensity))
	ci.draw_circle(pos, radius, Color(color, minf(1.0, 0.7 + 0.3 * intensity)))
	ci.draw_circle(pos + Vector2(-radius * 0.25, -radius * 0.3), radius * 0.45, Color(HOT, 0.9 * intensity))

## Two-tongue flame rising from `base`; `t` drives the flicker, `phase` desyncs neighbours.
static func draw_flame(ci: CanvasItem, base: Vector2, height: float, width: float, t: float, phase: float, outer: Color = ORANGE, inner: Color = GOLD) -> void:
	var lick := sin(t * 11.0 + phase) * 0.18 + sin(t * 17.0 + phase * 1.7) * 0.1
	var tip := base + Vector2(width * lick, -height * (1.0 + lick * 0.5))
	ci.draw_colored_polygon(PackedVector2Array([
		base + Vector2(-width * 0.5, 0.0), base + Vector2(-width * 0.3, -height * 0.45), tip,
		base + Vector2(width * 0.34, -height * 0.4), base + Vector2(width * 0.5, 0.0),
	]), outer)
	var inner_tip := base + Vector2(width * lick * 0.6, -height * 0.55 * (1.0 + lick * 0.4))
	ci.draw_colored_polygon(PackedVector2Array([
		base + Vector2(-width * 0.26, 0.0), inner_tip, base + Vector2(width * 0.26, 0.0),
	]), inner)

## Hanging chain: dashed links with a terminal ring. `sway` offsets the free end.
static func draw_chain(ci: CanvasItem, from: Vector2, length: float, sway: float, color: Color) -> void:
	var to := from + Vector2(sway, length)
	ci.draw_dashed_line(from, to, color, 2.0, 4.0)
	ci.draw_arc(to + Vector2(0.0, 3.0), 3.0, 0.0, TAU, 8, color, 1.5)

## Pose transform that scales and leans about a pivot (normally the feet) and
## mirrors on X for facing, so creature geometry can be authored facing right.
static func set_pose(ci: CanvasItem, pivot: Vector2, facing: float, scale: Vector2, lean: float) -> void:
	var xf := Transform2D(lean * signf(facing), Vector2(scale.x * signf(facing), scale.y), 0.0, Vector2.ZERO)
	xf.origin = pivot - xf * pivot
	ci.draw_set_transform_matrix(xf)

## Points transformed into a limb frame: rotated by `angle`, placed at `origin`.
static func limb(pts: PackedVector2Array, origin: Vector2, angle: float) -> PackedVector2Array:
	return Transform2D(angle, origin) * pts
