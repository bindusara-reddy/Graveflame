class_name BoonArt
extends RefCounted
## Procedural sigils for boons and forge upgrades, drawn like the rest of the
## game's art: no image assets, one silhouette per boon so a player can read a
## choice by shape before reading a word of it.
##
## Every icon is authored inside a unit box centred on `c`, extending `r` in each
## direction, so the same sigil works at card size and at forge-row size.
##
## Two rules keep the set legible at a glance and are worth preserving when
## adding an icon:
##   1. Every icon owns a distinct OUTLINE. Small interior differences vanish at
##      HUD size, so two icons must never differ only by a detail inside the
##      silhouette (three droplet icons once collided this way).
##   2. Permanent Forge upgrades are FRAMED; per-run boons are not. That is how a
##      player tells "this changes my run" from "this changes every run".

## Shared dark edge so a bright sigil still separates from a bright card.
const EDGE := Color(0, 0, 0, 0.55)

static func _p(c: Vector2, r: float, x: float, y: float) -> Vector2:
	return c + Vector2(x, y) * r


static func _poly(ci: CanvasItem, pts: Array, c: Vector2, r: float, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_p(c, r, float(p[0]), float(p[1])))
	ci.draw_colored_polygon(out, col)


static func _outlined(ci: CanvasItem, pts: Array, c: Vector2, r: float, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_p(c, r, float(p[0]), float(p[1])))
	ci.draw_colored_polygon(out, EDGE)
	var inner := PackedVector2Array()
	for p in out:
		inner.append(c + (p - c) * 0.86)
	ci.draw_colored_polygon(inner, col)


static func _stroke(ci: CanvasItem, pts: Array, c: Vector2, r: float, width: float, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_p(c, r, float(p[0]), float(p[1])))
	ci.draw_polyline(out, EDGE, width * r * 1.7)
	ci.draw_polyline(out, col, width * r)


## Sigil for a boon id or forge upgrade id. Unknown ids fall back to a rune.
static func draw(ci: CanvasItem, id: String, c: Vector2, r: float, tint: Color) -> void:
	# Forge upgrades carry the relic frame and inset the sigil inside it.
	if id.begins_with("m_"):
		_relic_frame(ci, c, r, tint)
		r *= 0.66
	match id:
		"vitality": _heart(ci, c, r, tint)
		"m_max_hp": _heart_flame(ci, c, r, tint)
		"swift": _winged_boot(ci, c, r, tint)
		"m_speed": _winged_boot(ci, c, r, tint, true)
		"power": _sword(ci, c, r, tint)
		"m_dmg": _sword(ci, c, r, tint, true)
		"edge": _razor(ci, c, r, tint)
		"magnet": _magnet(ci, c, r, tint)
		"warden": _shield(ci, c, r, tint)
		"surge": _lance(ci, c, r, tint)
		"leech": _maw(ci, c, r, tint)
		"ember": _flame(ci, c, r, tint)
		"slam": _slam(ci, c, r, tint)
		"parry": _crescent(ci, c, r, tint)
		"flask": _flask(ci, c, r, tint)
		"m_flask": _flask(ci, c, r, tint, true)
		"dashmaster": _chevrons(ci, c, r, tint, 3)
		"backdraft": _spiral(ci, c, r, tint)
		"kindling": _kindling(ci, c, r, tint)
		"momentum": _ramp(ci, c, r, tint)
		"bloodrush": _droplet_cracked(ci, c, r, tint)
		"secondwind": _feather(ci, c, r, tint)
		"executioner": _skull(ci, c, r, tint)
		"pyre": _burst(ci, c, r, tint)
		"emberwave": _wave(ci, c, r, tint)
		"thorns": _thorn(ci, c, r, tint)
		"m_special": _spark(ci, c, r, tint)
		"m_kindled": _kindling(ci, c, r, tint)
		"m_seer": _eye(ci, c, r, tint)
		"m_tithe": _cell(ci, c, r, tint)
		"cindertrail": _cinder_trail(ci, c, r, tint)
		"flareparry": _flare_parry(ci, c, r, tint)
		"twinlance": _twin_lance(ci, c, r, tint)
		"phoenix": _phoenix(ci, c, r, tint)
		"brand": _brand(ci, c, r, tint)
		"skyfall": _skyfall(ci, c, r, tint)
		# Rift markers: what waits beyond each door out of a cleared chamber.
		"rift_boon": _flame(ci, c, r, tint)
		"rift_font": _flask(ci, c, r, tint)
		"rift_cache": _cell(ci, c, r, tint)
		"rift_trial": _crossed_blades(ci, c, r, tint)
		_: _rune(ci, c, r, tint)


# --- Shared furniture ---------------------------------------------------------

## Marks a permanent Forge upgrade: a chamfered relic tablet behind the sigil.
static func _relic_frame(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_poly(ci, [
		[0.0, -1.0], [0.78, -0.62], [0.78, 0.62], [0.0, 1.0],
		[-0.78, 0.62], [-0.78, -0.62],
	], c, r, Color(EDGE, 0.75))
	_poly(ci, [
		[0.0, -0.86], [0.66, -0.53], [0.66, 0.53], [0.0, 0.86],
		[-0.66, 0.53], [-0.66, -0.53],
	], c, r, Color(tint.darkened(0.62), 0.9))


# --- Sigils -------------------------------------------------------------------

static func _heart(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [
		[0.0, 0.86], [-0.5, 0.42], [-0.78, 0.02], [-0.82, -0.34], [-0.58, -0.62],
		[-0.28, -0.62], [0.0, -0.3], [0.28, -0.62], [0.58, -0.62], [0.82, -0.34],
		[0.78, 0.02], [0.5, 0.42],
	], c, r, tint)
	ci.draw_circle(_p(c, r, -0.34, -0.3), r * 0.13, Color(1, 1, 1, 0.5))


## Ember Soul: the heart carries a flame, so it never reads as the Vitality boon.
static func _heart_flame(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [
		[0.0, 0.92], [-0.54, 0.46], [-0.82, 0.04], [-0.86, -0.34], [-0.6, -0.64],
		[-0.3, -0.64], [0.0, -0.32], [0.3, -0.64], [0.6, -0.64], [0.86, -0.34],
		[0.82, 0.04], [0.54, 0.46],
	], c, r, tint)
	_outlined(ci, [
		[0.0, -0.44], [0.2, -0.1], [0.12, 0.16], [0.26, 0.34],
		[0.1, 0.5], [-0.1, 0.5], [-0.26, 0.34], [-0.12, 0.16], [-0.2, -0.1],
	], c, r, Color(1, 0.9, 0.55, 0.92))


## A wing: one solid mass under a smooth leading edge, with three feather
## scallops along the trailing edge. Earlier attempts used thin triangles fanned
## from a shoulder, which rendered as faint slivers rather than a wing.
static func _winged_boot(ci: CanvasItem, c: Vector2, r: float, tint: Color, spurred: bool = false) -> void:
	_outlined(ci, [
		[-0.9, 0.16], [-0.45, -0.34], [0.1, -0.7], [0.88, -0.9],
		[0.46, -0.36], [0.62, -0.02], [0.2, -0.14], [0.32, 0.3],
		[-0.1, 0.1], [-0.16, 0.56], [-0.9, 0.52],
	], c, r, tint)
	# Quills radiating into each feather.
	for i in range(3):
		var t := float(i)
		ci.draw_line(
			_p(c, r, -0.5 + t * 0.2, -0.05 + t * 0.24),
			_p(c, r, 0.5 - t * 0.16, -0.06 + t * 0.2),
			Color(EDGE, 0.5), r * 0.06
		)
	if spurred:
		# Quickened: a speed stripe under the wing.
		ci.draw_line(_p(c, r, -0.84, 0.8), _p(c, r, 0.5, 0.8), Color(1, 1, 1, 0.65), r * 0.12)


static func _sword(ci: CanvasItem, c: Vector2, r: float, tint: Color, spark: bool = false) -> void:
	_outlined(ci, [[-0.12, -0.86], [0.12, -0.86], [0.16, 0.3], [0.0, 0.5], [-0.16, 0.3]], c, r, tint)
	_outlined(ci, [[-0.6, 0.24], [0.6, 0.24], [0.6, 0.44], [-0.6, 0.44]], c, r, tint.darkened(0.25))
	_outlined(ci, [[-0.14, 0.44], [0.14, 0.44], [0.1, 0.9], [-0.1, 0.9]], c, r, tint.darkened(0.45))
	ci.draw_line(_p(c, r, 0.0, -0.8), _p(c, r, 0.0, 0.22), Color(1, 1, 1, 0.42), r * 0.08)
	if spark:
		# Sharpened: a honing spark off the edge.
		for i in range(3):
			var a := -0.9 + float(i) * 0.34
			ci.draw_line(_p(c, r, 0.3, -0.5), _p(c, r, 0.3, -0.5) + Vector2(cos(a), sin(a)) * r * 0.42, Color(1, 0.92, 0.6, 0.95), r * 0.1)


## Razor Edge: a honed wedge, so it never shares the Parry crescent's language.
static func _razor(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [
		[-0.9, 0.62], [0.62, -0.9], [0.9, -0.5], [-0.5, 0.9],
	], c, r, tint)
	# Exposed bevel along the cutting edge.
	_outlined(ci, [[-0.9, 0.62], [0.62, -0.9], [0.72, -0.66], [-0.66, 0.72]], c, r, Color(1, 1, 1, 0.8))
	for i in range(3):
		var t := 0.28 + float(i) * 0.22
		ci.draw_line(
			_p(c, r, -0.9 + t * 1.5, 0.62 - t * 1.5),
			_p(c, r, -0.62 + t * 1.5, 0.34 - t * 1.5),
			Color(tint, 0.5), r * 0.08
		)


static func _magnet(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	ci.draw_arc(_p(c, r, 0.0, 0.05), r * 0.66, PI, TAU, 24, EDGE, r * 0.46, true)
	ci.draw_arc(_p(c, r, 0.0, 0.05), r * 0.66, PI, TAU, 24, tint, r * 0.3, true)
	for sx in [-1.0, 1.0]:
		ci.draw_rect(Rect2(_p(c, r, sx * 0.66, 0.05) - Vector2(r * 0.23, 0.0), Vector2(r * 0.46, r * 0.62)), EDGE)
		ci.draw_rect(Rect2(_p(c, r, sx * 0.66, 0.05) - Vector2(r * 0.16, 0.0), Vector2(r * 0.32, r * 0.42)), tint)
		ci.draw_rect(Rect2(_p(c, r, sx * 0.66, 0.47) - Vector2(r * 0.16, 0.0), Vector2(r * 0.32, r * 0.15)), tint.darkened(0.45))


static func _shield(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [
		[-0.72, -0.72], [0.72, -0.72], [0.72, 0.1], [0.42, 0.6], [0.0, 0.86],
		[-0.42, 0.6], [-0.72, 0.1],
	], c, r, tint)
	ci.draw_line(_p(c, r, 0.0, -0.56), _p(c, r, 0.0, 0.6), Color(EDGE, 0.85), r * 0.12)
	ci.draw_line(_p(c, r, -0.42, -0.2), _p(c, r, 0.42, -0.2), Color(EDGE, 0.85), r * 0.12)


static func _lance(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [[0.92, 0.0], [0.3, -0.3], [0.3, 0.3]], c, r, tint)
	ci.draw_rect(Rect2(_p(c, r, -0.86, -0.1), Vector2(r * 1.2, r * 0.2)), Color(EDGE, 0.9))
	ci.draw_rect(Rect2(_p(c, r, -0.82, -0.07), Vector2(r * 1.12, r * 0.14)), tint.darkened(0.2))
	for i in range(3):
		var y := -0.46 + float(i) * 0.46
		ci.draw_line(_p(c, r, -0.9, y), _p(c, r, -0.3, y), Color(tint, 0.55), r * 0.11)


## Leech: an open jaw — two mandibles with a gap between them and fangs above.
## A circle with a wedge cut out read as a face or an eye, so the gap is now the
## whole point of the silhouette.
static func _maw(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [
		[-0.94, -0.06], [-0.36, -0.52], [0.34, -0.6], [0.92, -0.34],
		[0.5, -0.22], [-0.08, -0.18], [-0.68, 0.06],
	], c, r, tint)
	_outlined(ci, [
		[-0.94, 0.06], [-0.36, 0.52], [0.34, 0.6], [0.92, 0.34],
		[0.5, 0.22], [-0.08, 0.18], [-0.68, -0.06],
	], c, r, tint)
	# Fangs hanging from the upper mandible into the gap.
	_poly(ci, [[-0.06, -0.44], [0.3, -0.38], [0.1, -0.04]], c, r, Color(1, 1, 1, 0.98))
	_poly(ci, [[-0.62, -0.34], [-0.28, -0.32], [-0.46, 0.02]], c, r, Color(1, 1, 1, 0.9))


## Bloodrush: a rounded blood drop with a jagged crack. Deliberately NOT the
## flame outline that Ember uses: at HUD size the two teardrop-ish shapes read as
## the same icon, and a silhouette may never be shared.
static func _droplet_cracked(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [
		[0.0, -0.92], [0.34, -0.34], [0.66, 0.16], [0.56, 0.6],
		[0.22, 0.86], [-0.22, 0.86], [-0.56, 0.6], [-0.66, 0.16], [-0.34, -0.34],
	], c, r, tint)
	_stroke(ci, [[-0.04, -0.36], [0.14, -0.06], [-0.1, 0.14], [0.06, 0.4], [-0.06, 0.68]],
			c, r, 0.12, Color(1, 0.88, 0.88, 0.95))


static func _flame(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	# A fire with two tongues: a tall inner one and a shorter outer one. Pointed,
	# asymmetric top and a wide round base, so it never reads as a teardrop.
	_outlined(ci, [
		[0.06, -0.98], [0.28, -0.46], [0.14, -0.2], [0.52, 0.08], [0.5, 0.42],
		[0.2, 0.74], [-0.24, 0.78], [-0.56, 0.5], [-0.6, 0.14], [-0.42, -0.16],
		[-0.52, -0.4], [-0.34, -0.66], [-0.24, -0.36], [-0.16, -0.6],
	], c, r, tint)
	_outlined(ci, [[0.02, -0.3], [0.22, 0.06], [0.16, 0.4], [-0.06, 0.56], [-0.26, 0.3], [-0.18, 0.0]], c, r, Color(1, 0.93, 0.62, 0.92))


static func _slam(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [[0.0, -0.9], [0.44, -0.2], [0.16, -0.2], [0.16, 0.34], [-0.16, 0.34], [-0.16, -0.2], [-0.44, -0.2]], c, r, tint)
	ci.draw_line(_p(c, r, -0.92, 0.68), _p(c, r, 0.92, 0.68), EDGE, r * 0.2)
	for i in range(4):
		var x := -0.72 + float(i) * 0.48
		ci.draw_line(_p(c, r, x, 0.68), _p(c, r, x + 0.14, 0.94), Color(tint, 0.7), r * 0.09)


static func _crescent(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	ci.draw_arc(c, r * 0.78, -2.4, 0.9, 30, EDGE, r * 0.42, true)
	ci.draw_arc(c, r * 0.78, -2.4, 0.9, 30, tint, r * 0.26, true)
	ci.draw_arc(c + Vector2(-0.1, 0.0) * r, r * 0.5, -1.9, 0.3, 20, Color(1, 1, 1, 0.5), r * 0.1, true)


static func _flask(ci: CanvasItem, c: Vector2, r: float, tint: Color, refill: bool = false) -> void:
	_outlined(ci, [[-0.14, -0.9], [0.14, -0.9], [0.14, -0.44], [0.44, 0.1], [0.5, 0.5], [0.26, 0.82], [-0.26, 0.82], [-0.5, 0.5], [-0.44, 0.1], [-0.14, -0.44]], c, r, tint)
	_outlined(ci, [[-0.4, 0.34], [0.4, 0.34], [0.4, 0.5], [0.24, 0.74], [-0.24, 0.74], [-0.4, 0.5]], c, r, Color(1, 0.86, 0.5, 0.9))
	ci.draw_rect(Rect2(_p(c, r, -0.2, -1.0), Vector2(r * 0.4, r * 0.14)), EDGE)
	if refill:
		# Potion Belt: a charge mark on the glass.
		ci.draw_rect(Rect2(_p(c, r, -0.1, 0.4), Vector2(r * 0.2, r * 0.26)), Color(1, 1, 1, 0.95))
		ci.draw_rect(Rect2(_p(c, r, -0.17, 0.47), Vector2(r * 0.34, r * 0.12)), Color(1, 1, 1, 0.95))


static func _chevrons(ci: CanvasItem, c: Vector2, r: float, tint: Color, count: int) -> void:
	for i in range(count):
		var x := -0.72 + float(i) * 0.42
		var w := 0.16 + float(i) * 0.04
		ci.draw_colored_polygon(PackedVector2Array([
			_p(c, r, x, -0.78), _p(c, r, x + 0.44, 0.0), _p(c, r, x, 0.78),
			_p(c, r, x + w, 0.78), _p(c, r, x + 0.44 + w, 0.0), _p(c, r, x + w, -0.78),
		]), tint if i == count - 1 else Color(tint, 0.45))
	# Trailing streaks, so Dashmaster reads as motion rather than a menu arrow.
	for i in range(3):
		var y := -0.5 + float(i) * 0.5
		ci.draw_line(_p(c, r, -0.95, y), _p(c, r, -0.66, y), Color(tint, 0.4), r * 0.1)


## Momentum: an ascending ramp of bars, distinct from the dash chevrons.
static func _ramp(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	var heights := [0.34, 0.56, 0.82, 1.0]
	for i in range(4):
		var x := -0.86 + float(i) * 0.46
		var h: float = float(heights[i])
		ci.draw_rect(Rect2(_p(c, r, x, 0.72 - h * 2.0), Vector2(r * 0.34, r * h * 2.0)), EDGE)
		ci.draw_rect(Rect2(_p(c, r, x + 0.05, 0.72 - h * 2.0 + 0.05), Vector2(r * 0.24, r * h * 2.0 - 0.1)), Color(tint, 0.45 + float(i) * 0.18))
	ci.draw_line(_p(c, r, -0.9, 0.78), _p(c, r, 0.9, 0.78), EDGE, r * 0.12)


static func _spiral(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(46):
		var t := float(i) / 45.0
		var a := t * TAU * 1.7
		pts.append(c + Vector2(cos(a), sin(a)) * r * (0.9 - t * 0.62))
	ci.draw_polyline(pts, EDGE, r * 0.26)
	ci.draw_polyline(pts, tint, r * 0.14)
	# A bold rebound head: the whole point of the boon is the return.
	_outlined(ci, [[0.5, -0.98], [1.0, -0.42], [0.24, -0.46]], c, r, Color(1, 0.95, 0.8, 0.95))


static func _kindling(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	ci.draw_line(_p(c, r, -0.8, 0.78), _p(c, r, 0.8, 0.5), EDGE, r * 0.26)
	ci.draw_line(_p(c, r, -0.8, 0.5), _p(c, r, 0.8, 0.78), EDGE, r * 0.26)
	ci.draw_line(_p(c, r, -0.8, 0.74), _p(c, r, 0.78, 0.47), Color("6b4326"), r * 0.16)
	ci.draw_line(_p(c, r, -0.8, 0.47), _p(c, r, 0.78, 0.74), Color("6b4326"), r * 0.16)
	_outlined(ci, [
		[0.0, -0.94], [0.3, -0.36], [0.2, -0.04], [0.42, 0.22],
		[0.18, 0.44], [-0.18, 0.44], [-0.42, 0.22], [-0.2, -0.04], [-0.3, -0.36],
	], c, r, tint)


static func _feather(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	# Phoenix quill: a pointed blade with evenly spaced barbs.
	_outlined(ci, [[0.0, -0.94], [0.4, -0.5], [0.5, 0.04], [0.34, 0.5], [0.0, 0.8],
				   [-0.34, 0.5], [-0.5, 0.04], [-0.4, -0.5]], c, r, tint)
	for i in range(4):
		var y := -0.56 + float(i) * 0.28
		var spread := 0.42 - absf(float(i) - 1.5) * 0.1
		ci.draw_line(_p(c, r, 0.0, y), _p(c, r, spread, y + 0.18), Color(EDGE, 0.75), r * 0.07)
		ci.draw_line(_p(c, r, 0.0, y), _p(c, r, -spread, y + 0.18), Color(EDGE, 0.75), r * 0.07)
	ci.draw_line(_p(c, r, 0.0, -0.78), _p(c, r, 0.0, 1.0), Color(1, 1, 1, 0.5), r * 0.07)


static func _skull(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [
		[0.0, -0.86], [0.44, -0.7], [0.68, -0.2], [0.62, 0.22], [0.34, 0.4],
		[0.36, 0.82], [-0.36, 0.82], [-0.34, 0.4], [-0.62, 0.22], [-0.68, -0.2],
		[-0.44, -0.7],
	], c, r, tint)
	# Large sockets and a mouth band that sits clearly INSIDE the jaw. The first
	# pass drew teeth that read as drips hanging below the skull.
	for sx in [-1.0, 1.0]:
		ci.draw_circle(_p(c, r, sx * 0.3, -0.26), r * 0.24, Color(EDGE, 0.95))
		ci.draw_circle(_p(c, r, sx * 0.3, -0.3), r * 0.14, Color(1, 1, 1, 0.28))
	_poly(ci, [[0.0, -0.16], [0.16, 0.16], [-0.16, 0.16]], c, r, Color(EDGE, 0.95))
	# Jaw: a dark band with pale teeth inside the silhouette.
	_poly(ci, [[-0.3, 0.4], [0.3, 0.4], [0.26, 0.72], [-0.26, 0.72]], c, r, Color(EDGE, 0.9))
	for i in range(4):
		var x := -0.22 + float(i) * 0.147
		ci.draw_rect(Rect2(_p(c, r, x - 0.028, 0.44), Vector2(r * 0.056, r * 0.22)), tint.lightened(0.35))


## Cinder Trail: three small fires stepping away along a ground line, the
## footprints of a dash. A staircase outline no other sigil has.
static func _cinder_trail(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	ci.draw_line(_p(c, r, -0.95, 0.78), _p(c, r, 0.95, 0.78), EDGE, r * 0.2)
	ci.draw_line(_p(c, r, -0.9, 0.78), _p(c, r, 0.9, 0.78), Color(tint, 0.6), r * 0.1)
	for i in range(3):
		var x := -0.58 + float(i) * 0.58
		var h := 0.5 + float(i) * 0.36
		_outlined(ci, [[x, 0.7 - h], [x + 0.22, 0.44], [x + 0.2, 0.7], [x - 0.2, 0.7], [x - 0.22, 0.44]], c, r, tint.lightened(0.1 * float(i)))

## Flare Parry: the parry crescent throwing out three flame points.
static func _flare_parry(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	for a: float in [-0.9, -0.1, 0.7]:
		var d := Vector2(cos(a), sin(a))
		var base := c + d * r * 0.62
		var n := Vector2(-d.y, d.x)
		var tip := c + d * r * 1.0
		ci.draw_colored_polygon(PackedVector2Array([base + n * r * 0.16, tip, base - n * r * 0.16]), EDGE)
		ci.draw_colored_polygon(PackedVector2Array([base + n * r * 0.1, c + d * r * 0.94, base - n * r * 0.1]), tint.lightened(0.25))
	ci.draw_arc(c + Vector2(-0.12, 0.0) * r, r * 0.56, -2.3, 1.1, 26, EDGE, r * 0.34, true)
	ci.draw_arc(c + Vector2(-0.12, 0.0) * r, r * 0.56, -2.3, 1.1, 26, tint, r * 0.2, true)

## Twin Lance: two lance heads, one above the other.
static func _twin_lance(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	for y: float in [-0.36, 0.36]:
		_outlined(ci, [[0.92, y], [0.42, y - 0.24], [0.42, y + 0.24]], c, r, tint)
		ci.draw_rect(Rect2(_p(c, r, -0.9, y - 0.08), Vector2(r * 1.34, r * 0.16)), Color(EDGE, 0.9))
		ci.draw_rect(Rect2(_p(c, r, -0.86, y - 0.05), Vector2(r * 1.3, r * 0.1)), tint.darkened(0.2))

## Phoenix Flask: the flask with a pair of flame wings.
static func _phoenix(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	for sx: float in [-1.0, 1.0]:
		_outlined(ci, [[sx * 0.3, 0.0], [sx * 0.96, -0.62], [sx * 0.78, -0.18], [sx * 0.98, -0.1], [sx * 0.62, 0.3], [sx * 0.3, 0.3]], c, r, tint.darkened(0.1))
	_outlined(ci, [[-0.1, -0.78], [0.1, -0.78], [0.1, -0.36], [0.34, 0.06], [0.38, 0.46], [0.2, 0.74], [-0.2, 0.74], [-0.38, 0.46], [-0.34, 0.06], [-0.1, -0.36]], c, r, tint)
	_outlined(ci, [[0.0, -0.06], [0.16, 0.24], [0.1, 0.56], [-0.1, 0.56], [-0.16, 0.24]], c, r, Color(1, 0.93, 0.62, 0.95))

## Ember Brand: a branding iron -- a ring on a long handle.
static func _brand(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	ci.draw_line(_p(c, r, -0.92, 0.92), _p(c, r, -0.12, 0.12), EDGE, r * 0.3)
	ci.draw_line(_p(c, r, -0.9, 0.9), _p(c, r, -0.14, 0.14), tint.darkened(0.3), r * 0.16)
	var head := _p(c, r, 0.26, -0.26)
	ci.draw_arc(head, r * 0.5, 0.0, TAU, 32, EDGE, r * 0.34, true)
	ci.draw_arc(head, r * 0.5, 0.0, TAU, 32, tint, r * 0.2, true)
	# A flame burning inside the ring: a hot brand, not a lens.
	var f := PackedVector2Array([head + Vector2(0.0, -0.3) * r, head + Vector2(0.16, 0.02) * r, head + Vector2(0.1, 0.2) * r, head + Vector2(-0.1, 0.2) * r, head + Vector2(-0.16, 0.02) * r])
	ci.draw_colored_polygon(f, Color(1.0, 0.62, 0.2))
	ci.draw_colored_polygon(PackedVector2Array([head + Vector2(0.0, -0.08) * r, head + Vector2(0.07, 0.14) * r, head + Vector2(-0.07, 0.14) * r]), Color(1.0, 0.93, 0.62))

## Skyfall: a down-strike splitting into two floor waves.
static func _skyfall(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [[0.0, 0.44], [0.4, -0.1], [0.14, -0.1], [0.14, -0.92], [-0.14, -0.92], [-0.14, -0.1], [-0.4, -0.1]], c, r, tint)
	for sx: float in [-1.0, 1.0]:
		_outlined(ci, [[sx * 0.2, 0.86], [sx * 0.5, 0.52], [sx * 0.98, 0.62], [sx * 0.6, 0.86]], c, r, tint.lightened(0.15))

## An open eye: seeing one more road than you would.
static func _eye(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [[-0.9, 0.0], [-0.45, -0.46], [0.0, -0.58], [0.45, -0.46], [0.9, 0.0], [0.45, 0.46], [0.0, 0.58], [-0.45, 0.46]], c, r, tint)
	ci.draw_circle(c, r * 0.34, Color(EDGE, 0.95))
	ci.draw_circle(c, r * 0.2, tint.lightened(0.4))
	ci.draw_circle(c + Vector2(-0.08, -0.1) * r, r * 0.07, Color(1, 1, 1, 0.8))


## A cell: the keep's currency, a faceted gem with a lit crown facet.
static func _cell(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [[0.0, -0.86], [0.62, -0.28], [0.44, 0.5], [0.0, 0.88], [-0.44, 0.5], [-0.62, -0.28]], c, r, tint)
	_poly(ci, [[0.0, -0.66], [0.4, -0.24], [0.0, -0.06], [-0.4, -0.24]], c, r, tint.lightened(0.45))
	_poly(ci, [[0.0, -0.06], [0.3, 0.44], [0.0, 0.7], [-0.3, 0.44]], c, r, Color(EDGE, 0.35))


## A trial: two blades crossed over a small skull-less boss plate.
static func _crossed_blades(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	for sx in [-1.0, 1.0]:
		_stroke(ci, [[-0.7 * sx, 0.72], [0.62 * sx, -0.74]], c, r, 0.13, tint)
		_stroke(ci, [[-0.52 * sx, 0.36], [-0.22 * sx, 0.66]], c, r, 0.1, tint.darkened(0.2))
	_outlined(ci, [[0.0, -0.2], [0.24, 0.02], [0.0, 0.26], [-0.24, 0.02]], c, r, tint.lightened(0.3))


static func _burst(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	# A fireball: thick flame tongues thrown out all round from a hot core. Thin
	# even spokes plus a ring read as a compass rose, so both are gone.
	for i in range(6):
		var a := TAU * float(i) / 6.0 - PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		var reach := 0.98 if i % 2 == 0 else 0.76
		var base := dir * r * 0.24
		var tip := dir * r * reach
		ci.draw_colored_polygon(PackedVector2Array([
			c + base + perp * r * 0.3,
			c + tip,
			c + base - perp * r * 0.3,
		]), tint if i % 2 == 0 else Color(tint.darkened(0.15), 0.85))
	# A second, smaller set of tongues between the first, for a ragged edge.
	for i in range(6):
		var a := TAU * (float(i) + 0.5) / 6.0 - PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		var tip := dir * r * 0.58
		ci.draw_colored_polygon(PackedVector2Array([
			c + dir * r * 0.2 + perp * r * 0.24,
			c + tip,
			c + dir * r * 0.2 - perp * r * 0.24,
		]), Color(tint, 0.7))
	ci.draw_circle(c, r * 0.36, Color(1, 0.93, 0.7, 1.0))
	ci.draw_circle(c, r * 0.2, Color(1, 0.99, 0.9, 1.0))


static func _wave(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	for i in range(3):
		var rad := r * (0.42 + float(i) * 0.28)
		ci.draw_arc(_p(c, r, -0.1, 0.1), rad, -1.5, 1.5, 24, EDGE, r * 0.2, true)
		ci.draw_arc(_p(c, r, -0.1, 0.1), rad, -1.5, 1.5, 24, tint if i == 0 else Color(tint, 0.55), r * 0.11, true)


static func _thorn(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	# A thick barbed stem. The first pass was thin and irregular and read as a
	# twig, so the stem is heavier and the barbs are large, even triangles.
	var stem := PackedVector2Array()
	for i in range(16):
		var t := float(i) / 15.0
		stem.append(c + Vector2(sin(t * PI * 1.05 - 0.4) * r * 0.26, -r * 0.84 + t * r * 1.68))
	ci.draw_polyline(stem, EDGE, r * 0.34)
	ci.draw_polyline(stem, tint.darkened(0.15), r * 0.22)
	for i in range(5):
		var t := 0.08 + float(i) * 0.21
		var bx := sin(t * PI * 1.05 - 0.4) * r * 0.26
		var by := -r * 0.84 + t * r * 1.68
		var dir := 1.0 if i % 2 == 0 else -1.0
		_outlined(ci, [
			[bx / r, by / r],
			[bx / r + dir * 0.52, by / r - 0.2],
			[bx / r + dir * 0.06, by / r + 0.2],
		], c, r, tint.lightened(0.2))


static func _spark(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	for i in range(4):
		var a := TAU * float(i) / 4.0
		ci.draw_colored_polygon(PackedVector2Array([
			c + Vector2(cos(a - 0.3), sin(a - 0.3)) * r * 0.2,
			c + Vector2(cos(a), sin(a)) * r * 1.0,
			c + Vector2(cos(a + 0.3), sin(a + 0.3)) * r * 0.2,
		]), tint)
	for i in range(4):
		var a := TAU * float(i) / 4.0 + PI * 0.25
		ci.draw_colored_polygon(PackedVector2Array([
			c + Vector2(cos(a - 0.3), sin(a - 0.3)) * r * 0.14,
			c + Vector2(cos(a), sin(a)) * r * 0.52,
			c + Vector2(cos(a + 0.3), sin(a + 0.3)) * r * 0.14,
		]), Color(tint, 0.65))
	ci.draw_circle(c, r * 0.16, Color(1, 1, 1, 0.9))


static func _rune(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	_outlined(ci, [[-0.62, -0.8], [0.62, -0.8], [0.62, 0.8], [-0.62, 0.8]], c, r, tint)
	ci.draw_line(_p(c, r, -0.26, -0.2), _p(c, r, 0.26, -0.2), Color(EDGE, 0.8), r * 0.11)
	ci.draw_line(_p(c, r, -0.26, 0.16), _p(c, r, 0.26, 0.16), Color(EDGE, 0.8), r * 0.11)
