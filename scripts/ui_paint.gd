class_name UiPaint
extends RefCounted
## Drawing primitives for the interface's paper: blade-cut and torn outlines,
## the knight's flame, wax seals, lozenges, key caps and pad buttons. Every
## painter draws onto a canvas item RID, so the same call works inside a
## StyleBox, a kit control's _draw, or a world script's _draw
## (pass get_canvas_item()). Geometry helpers are pure and allocation-light.

const VFX := preload("res://scripts/vfx.gd")
const T := preload("res://scripts/ui_theme.gd")

## Sides of a rectangle, for choosing which edges tear.
const TOP := 1
const RIGHT := 2
const BOTTOM := 4
const LEFT := 8
const ALL_SIDES := 15
## Spacing of the torn-edge points, in pixels.
const DECKLE_STEP := 7.0


# --- Geometry ----------------------------------------------------------------------

## A rectangle with its corners cut off by `cut` px: the blade-cut paper shape,
## clockwise from the top-left.
static func cut_rect(r: Rect2, cut: float) -> PackedVector2Array:
	var c := minf(cut, minf(r.size.x, r.size.y) * 0.5)
	var p := r.position
	var e := r.end
	if c < 0.5:
		return PackedVector2Array([p, Vector2(e.x, p.y), e, Vector2(p.x, e.y)])
	return PackedVector2Array([
		Vector2(p.x + c, p.y), Vector2(e.x - c, p.y), Vector2(e.x, p.y + c), Vector2(e.x, e.y - c),
		Vector2(e.x - c, e.y), Vector2(p.x + c, e.y), Vector2(p.x, e.y - c), Vector2(p.x, p.y + c),
	])


## A ribbon: square top, a V notch cut up into the bottom edge.
static func ribbon_rect(r: Rect2, notch: float) -> PackedVector2Array:
	var p := r.position
	var e := r.end
	return PackedVector2Array([p, Vector2(e.x, p.y), e, Vector2(r.get_center().x, e.y - notch), Vector2(p.x, e.y)])


## A grave marker: a round arch over straight sides.
static func arch_rect(r: Rect2, cut: float) -> PackedVector2Array:
	var radius := minf(r.size.x * 0.5, r.size.y * 0.45)
	var top := r.position.y + radius
	var cx := r.get_center().x
	var pts := PackedVector2Array()
	for i in range(21):
		var a := PI + PI * float(i) / 20.0
		pts.append(Vector2(cx + cos(a) * r.size.x * 0.5, top + sin(a) * radius))
	var bottom := cut_rect(Rect2(r.position.x, top, r.size.x, r.end.y - top), cut)
	# Right side down, then the cut foot, then back up the left side.
	for i in [3, 4, 5, 6]:
		pts.append(bottom[i])
	return pts


## `outline` with the straight stretches of the chosen `sides` torn: points
## every DECKLE_STEP px pushed inward by up to `depth`, the same tear for the
## same `seed` every frame. Cut corners stay clean, like a trimmed sheet.
static func deckled(outline: PackedVector2Array, bounds: Rect2, depth: float, seed: int, sides: int = ALL_SIDES) -> PackedVector2Array:
	if depth <= 0.0:
		return outline
	var out := PackedVector2Array()
	var n := outline.size()
	for i in range(n):
		var a := outline[i]
		var b := outline[(i + 1) % n]
		out.append(a)
		var side := _side_of(a, b, bounds)
		if side == 0 or (sides & side) == 0:
			continue
		var d := b - a
		var inward := Vector2(-d.y, d.x).normalized()
		var steps := int(d.length() / DECKLE_STEP)
		for k in range(1, steps):
			# Two scales of tear: a slow wander and a fibrous bite.
			var slow := VFX.hash01(i * 97 + k / 4, seed)
			var bite := VFX.hash01(i * 131 + k, seed + 17)
			out.append(a + d * (float(k) / float(steps)) + inward * depth * (0.25 + 0.45 * slow + 0.3 * bite))
	return out


## Which straight side of `bounds` the edge a-b lies on (0 for a cut corner).
static func _side_of(a: Vector2, b: Vector2, bounds: Rect2) -> int:
	var p := bounds.position
	var e := bounds.end
	if is_equal_approx(a.y, p.y) and is_equal_approx(b.y, p.y):
		return TOP
	if is_equal_approx(a.x, e.x) and is_equal_approx(b.x, e.x):
		return RIGHT
	if is_equal_approx(a.y, e.y) and is_equal_approx(b.y, e.y):
		return BOTTOM
	if is_equal_approx(a.x, p.x) and is_equal_approx(b.x, p.x):
		return LEFT
	return 0


static func moved(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	return Transform2D(0.0, by) * pts


## `pts` turned by `angle` radians about `pivot`: an under-sheet laid askew.
static func turned(pts: PackedVector2Array, angle: float, pivot: Vector2) -> PackedVector2Array:
	return Transform2D(angle, pivot) * (Transform2D(0.0, -pivot) * pts)


static func closed(pts: PackedVector2Array) -> PackedVector2Array:
	var line := pts.duplicate()
	line.append(pts[0])
	return line


# --- Primitives --------------------------------------------------------------------

## A filled shape. Shapes with no area (a control not laid out yet, a meter
## at zero) are skipped: the renderer cannot triangulate them.
static func fill(ci: RID, pts: PackedVector2Array, color: Color) -> void:
	if color.a <= 0.0 or pts.size() < 3:
		return
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	if box.size.x >= 0.5 and box.size.y >= 0.5:
		RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([color]))


static func stroke(ci: RID, pts: PackedVector2Array, color: Color, width: float = 1.0) -> void:
	if color.a > 0.0 and pts.size() >= 2:
		RenderingServer.canvas_item_add_polyline(ci, closed(pts), PackedColorArray([color]), width, true)


## An ember halo around a shape: three widening strokes fading outward, so
## the light sits around the paper without covering it.
static func halo(ci: RID, pts: PackedVector2Array, color: Color) -> void:
	for ring in [[2.0, 4.0, 0.34], [4.5, 5.0, 0.16], [8.0, 6.0, 0.07]]:
		var grown := Geometry2D.offset_polygon(pts, ring[0], Geometry2D.JOIN_MITER)
		if not grown.is_empty():
			stroke(ci, grown[0], Color(color, color.a * ring[2]), ring[1])


static func lozenge(ci: RID, c: Vector2, r: float, color: Color, hollow := false) -> void:
	var pts := PackedVector2Array([c + Vector2(0.0, -r), c + Vector2(r * 0.8, 0.0), c + Vector2(0.0, r), c + Vector2(-r * 0.8, 0.0)])
	if hollow:
		stroke(ci, pts, color, 1.2)
	else:
		fill(ci, pts, color)


## The keep's printer's mark: a hairline from `a` to `b` with a lozenge at its
## middle and a dot at each end.
static func rule(ci: RID, a: Vector2, b: Vector2, color: Color, mark := true) -> void:
	var mid := (a + b) * 0.5
	var gap := 11.0 if mark else 0.0
	var dir := (b - a).normalized()
	var faint := Color(color, color.a * 0.55)
	RenderingServer.canvas_item_add_line(ci, a, mid - dir * gap, faint, 1.0, true)
	RenderingServer.canvas_item_add_line(ci, mid + dir * gap, b, faint, 1.0, true)
	RenderingServer.canvas_item_add_circle(ci, a, 1.5, faint)
	RenderingServer.canvas_item_add_circle(ci, b, 1.5, faint)
	if mark:
		lozenge(ci, mid, 5.0, color)


## The knight's flame: an ember outer tongue, a gold inner one and a
## white-hot seed. `t` drives the flicker (hold it at 0 for a still flame).
static func flame(ci: RID, base: Vector2, height: float, width: float, t: float, phase := 0.0) -> void:
	var tongues := VFX.flame_tongues(base, height, width, t, phase)
	fill(ci, moved(tongues[0], Vector2(1.0, 1.5)), Color(0.0, 0.0, 0.0, 0.45))
	fill(ci, tongues[0], T.EMBER)
	fill(ci, tongues[1], T.GOLD)
	RenderingServer.canvas_item_add_circle(ci, base + Vector2(0.0, -height * 0.16), width * 0.13, T.HOT)


## A wax seal: an uneven scalloped blob, a pressed ring and an emboss
## ("flame", "crown", "tick" or "" for plain). A seal not yet pressed is only
## a faint ring where the wax would go.
static func seal(ci: RID, c: Vector2, r: float, wax: Color, emboss := "flame", pressed := true, seed := 3) -> void:
	if not pressed:
		var ring := PackedVector2Array()
		for i in range(24):
			var a := TAU * float(i) / 24.0
			ring.append(c + Vector2(cos(a), sin(a)) * r * 0.86)
		stroke(ci, ring, Color(T.SOOT, 0.9), 1.5)
		lozenge(ci, c, r * 0.22, Color(T.SOOT, 0.7), true)
		return
	var blob := PackedVector2Array()
	for i in range(22):
		var a := TAU * float(i) / 22.0
		var bulge := 1.0 if i % 2 == 0 else 0.88
		blob.append(c + Vector2(cos(a), sin(a)) * r * bulge * (0.94 + 0.08 * VFX.hash01(i, seed)))
	fill(ci, moved(blob, Vector2(1.5, 2.0)), Color(0.0, 0.0, 0.0, 0.5))
	fill(ci, blob, wax.darkened(0.22))
	RenderingServer.canvas_item_add_circle(ci, c, r * 0.74, wax)
	RenderingServer.canvas_item_add_circle(ci, c + Vector2(-r * 0.2, -r * 0.24), r * 0.34, Color(wax.lightened(0.3), 0.35))
	var ink := wax.darkened(0.42)
	var ring := PackedVector2Array()
	for i in range(28):
		var a := TAU * float(i) / 28.0
		ring.append(c + Vector2(cos(a), sin(a)) * r * 0.6)
	stroke(ci, ring, ink, 1.2)
	match emboss:
		"flame":
			var tongues := VFX.flame_tongues(c + Vector2(0.0, r * 0.38), r * 0.72, r * 0.52, 0.0, 0.0)
			fill(ci, tongues[0], ink)
			fill(ci, tongues[1], wax.lightened(0.18))
		"crown":
			crown(ci, c + Vector2(0.0, r * 0.2), r * 0.84, ink)
		"tick":
			var tick := PackedVector2Array([c + Vector2(-r * 0.3, 0.0), c + Vector2(-r * 0.06, r * 0.24), c + Vector2(r * 0.34, -r * 0.26)])
			RenderingServer.canvas_item_add_polyline(ci, tick, PackedColorArray([ink]), maxf(2.0, r * 0.14), true)


## The knight's four-tongued crown, `w` px wide, standing on `base` (its
## foot's centre): the throne at the end of the chamber track, seal embosses.
static func crown(ci: RID, base: Vector2, w: float, color: Color) -> void:
	var h := w * 0.55
	var x := base.x - w * 0.5
	var pts := PackedVector2Array([Vector2(x, base.y)])
	for i in range(4):
		var tip := x + w * (0.125 + 0.25 * float(i))
		pts.append(Vector2(tip - w * 0.1, base.y - h * 0.45))
		pts.append(Vector2(tip, base.y - h * (1.0 if i in [1, 2] else 0.8)))
		pts.append(Vector2(tip + w * 0.1, base.y - h * 0.45))
	pts.append(Vector2(x + w, base.y))
	fill(ci, pts, color)


## Text in a type role, drawn at `pos` (baseline-left) with an optional outline.
static func text(ci: RID, pos: Vector2, s: String, role: String, color: Color, outline := 0) -> void:
	var font := T.font(role)
	var px := T.size(role)
	if outline > 0:
		font.draw_string_outline(ci, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, outline, Color(T.INK_DEEP, color.a * 0.85))
	font.draw_string(ci, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


static func text_width(s: String, role: String) -> float:
	return T.font(role).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, T.size(role)).x


## A small paper tag centred on `c` carrying `s`: world labels and flourish
## names. Returns the tag's rect.
static func tag(ci: RID, c: Vector2, s: String, paper: Color, ink: Color, role := "micro") -> Rect2:
	var w := text_width(s, role) + 18.0
	var h := float(T.size(role)) + 12.0
	var r := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	var shape := cut_rect(r, 4.0)
	fill(ci, moved(shape, Vector2(2.0, 3.0)), Color(0.0, 0.0, 0.0, 0.5))
	fill(ci, shape, paper)
	var font := T.font(role)
	text(ci, Vector2(r.position.x + 9.0, r.position.y + (h + font.get_ascent(T.size(role)) - font.get_descent(T.size(role))) * 0.5), s, role, ink)
	return r


# --- Key caps and pad buttons -------------------------------------------------------

## What a binding reads as on its cap: key names shortened to fit, arrows as
## arrowheads (returned as "<", ">", "^", "v").
static func cap_text(binding: String) -> String:
	var b := binding.to_upper()
	match b:
		"ESCAPE": return "ESC"
		"ENTER", "KP ENTER": return "ENTER"
		"BACKSPACE": return "BKSP"
		"CONTROL", "CTRL": return "CTRL"
		"PAGEUP": return "PG UP"
		"PAGEDOWN": return "PG DN"
		"LEFT", "D-PAD LEFT", "STICK LEFT": return "<"
		"RIGHT", "D-PAD RIGHT", "STICK RIGHT": return ">"
		"UP", "D-PAD UP", "STICK UP": return "^"
		"DOWN", "D-PAD DOWN", "STICK DOWN": return "v"
	return b


## Width a cap for `binding` takes at `height` on `device` ("key" or "pad").
static func cap_width(binding: String, device: String, height: float) -> float:
	var label := cap_text(binding)
	if device == "pad" and label in ["A", "B", "X", "Y"]:
		return height
	if label.length() == 1:
		return height
	return maxf(height, T.font("micro").get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _cap_px(height)).x + height * 0.6)


static func _cap_px(height: float) -> int:
	return maxi(9, roundi(height * 0.42))


## Draw the cap for `binding` with its top-left at `pos`. Keys are paper
## tiles with a lip; A/B/X/Y are inked discs ringed in their pad colour;
## bumpers, triggers, sticks and the d-pad get their own silhouettes.
## `lit` paints it ember (a pending rebind, a held prompt). Returns its width.
static func cap(ci: RID, pos: Vector2, binding: String, device: String, height: float, lit := false) -> float:
	var label := cap_text(binding)
	var w := cap_width(binding, device, height)
	var r := Rect2(pos, Vector2(w, height))
	var ink := T.INK if lit else T.BONE
	var paper := T.EMBER if lit else T.SHEET_HI
	if device == "pad" and label in ["A", "B", "X", "Y"]:
		var ring: Color = {"A": T.VERDIGRIS, "B": T.BLOOD, "X": T.SPIRIT, "Y": T.GOLD}[label]
		var c := r.get_center()
		RenderingServer.canvas_item_add_circle(ci, c + Vector2(1.0, 1.5), height * 0.5, Color(0.0, 0.0, 0.0, 0.5))
		RenderingServer.canvas_item_add_circle(ci, c, height * 0.5, ring.darkened(0.35) if not lit else T.EMBER)
		RenderingServer.canvas_item_add_circle(ci, c, height * 0.5 - 2.0, T.SHEET_LO if not lit else T.EMBER_HI)
		_cap_label(ci, r, label, ring.lightened(0.25) if not lit else T.INK, height)
		return w
	var body := r
	var lip := maxf(2.0, height * 0.12)
	body.size.y -= lip
	var shape: PackedVector2Array
	if device == "pad" and label in ["LB", "RB", "LT", "RT"]:
		# Shoulders slope toward the pad's centre: LB/LT lean right, RB/RT left.
		var lean := height * 0.3 * (1.0 if label.begins_with("L") else -1.0)
		var p := body.position
		var e := body.end
		shape = PackedVector2Array([Vector2(p.x + maxf(0.0, lean), p.y), Vector2(e.x + minf(0.0, lean), p.y), e, Vector2(p.x, e.y)])
	elif device == "pad" and label in ["<", ">", "^", "v"] and not binding.to_upper().begins_with("STICK"):
		shape = _dpad_arm(body)
	else:
		shape = cut_rect(body, height * 0.18)
	fill(ci, moved(shape, Vector2(0.0, lip)), (paper.darkened(0.45)))
	fill(ci, shape, paper)
	RenderingServer.canvas_item_add_line(ci, shape[0] + Vector2(0.0, 1.0), shape[1] + Vector2(0.0, 1.0), Color(paper.lightened(0.35), 0.8), 1.0)
	stroke(ci, shape, Color(T.HAIRLINE if not lit else T.EMBER_HI), 1.0)
	if binding.to_upper().begins_with("STICK") or binding.to_upper().begins_with("R-STICK"):
		RenderingServer.canvas_item_add_circle(ci, body.get_center(), height * 0.3, T.SHEET_LO)
	_cap_label(ci, body, label, ink, height)
	return w


## A d-pad cross with the pressed arm shown as the cap itself.
static func _dpad_arm(r: Rect2) -> PackedVector2Array:
	var c := r.get_center()
	var a := r.size.y * 0.18
	var b := r.size.y * 0.5
	return PackedVector2Array([
		c + Vector2(-a, -b), c + Vector2(a, -b), c + Vector2(a, -a), c + Vector2(b, -a), c + Vector2(b, a),
		c + Vector2(a, a), c + Vector2(a, b), c + Vector2(-a, b), c + Vector2(-a, a), c + Vector2(-b, a),
		c + Vector2(-b, -a), c + Vector2(-a, -a),
	])


static func _cap_label(ci: RID, r: Rect2, label: String, color: Color, height: float) -> void:
	var c := r.get_center()
	var s := height * 0.2
	match label:
		"<": fill(ci, PackedVector2Array([c + Vector2(-s, 0.0), c + Vector2(s * 0.7, -s), c + Vector2(s * 0.7, s)]), color)
		">": fill(ci, PackedVector2Array([c + Vector2(s, 0.0), c + Vector2(-s * 0.7, s), c + Vector2(-s * 0.7, -s)]), color)
		"^": fill(ci, PackedVector2Array([c + Vector2(0.0, -s), c + Vector2(s, s * 0.7), c + Vector2(-s, s * 0.7)]), color)
		"v": fill(ci, PackedVector2Array([c + Vector2(0.0, s), c + Vector2(-s, -s * 0.7), c + Vector2(s, -s * 0.7)]), color)
		_:
			var font := T.font("micro")
			var px := _cap_px(height)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			var base := c.y + (font.get_ascent(px) - font.get_descent(px)) * 0.5
			font.draw_string(ci, Vector2(c.x - w * 0.5, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


## The live prompt for `action`: its first binding on the device last touched
## (falling back to the other device), drawn as a cap. Returns its width.
static func prompt(ci: RID, pos: Vector2, action: String, height: float, lit := false) -> float:
	var hit := UiInput.first_binding(action)
	return cap(ci, pos, hit.name, hit.device, height, lit)


static func prompt_width(action: String, height: float) -> float:
	var hit := UiInput.first_binding(action)
	return cap_width(hit.name, hit.device, height)
