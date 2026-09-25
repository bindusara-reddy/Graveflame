extends Control
## Original menu art: "The Threshold of the Descent". A title-only tableau of
## the flame-headed knight standing on a broken stair landing inside the mouth
## of a colossal ossuary shaft, looking down into the furnace light far below.
## Everything is authored vector drawing in the game's own crypt palette; the
## knight uses the gameplay figure's exact geometry and colours, only presented
## larger. Nothing here is a gameplay screenshot and nothing touches gameplay.
##
## Layers (back to front): Depth (sky, far galleries, walls, bridge, landing),
## Glow (additive furnace, niche torches, knight halo), Votives (victory candles
## and the drifting shaft mist, behind the knight), Knight, Fog (chains, lip mist,
## arrival veil) and Embers (particles, hidden under reduced motion).
##
## The keep remembers: every won descent lights a candle in a niche, nearest the
## knight first, and the knight's own crown burns gold once the Warden has
## fallen. It remembers how the last one ended, too: after the crown was taken
## the landing stands empty and a small red throne glows far below; after the
## flames were given back the knight is home and a new star hangs over the
## well; and once the keep has been put out, a cold dawn stays in the vault.

const VFX := preload("res://scripts/vfx.gd")
const KnightArt := preload("res://scripts/knight_art.gd")
const Cast := preload("res://scripts/finale_actors.gd")

## Seconds for the arrival reveal: the furnace rises and the galleries emerge.
const REVEAL_TIME := 1.6
const RINGS := 7
## Gameplay figure height (Content.P_BODY_H) reproduced, never altered.
const BODY_H := 54.0
const KNIGHT_SCALE := 2.0
## Victory candle wax: a plain win, a win under any vow, the Fivefold Oath.
const WAX_PLAIN := Color("d8cfc0")
const WAX_VOWED := Color("a0303a")
const WAX_OATH := Color("e8c77a")
## Once the niches are full, later wins stand votives on the landing treads:
## [tread index, votives], the tread nearest the knight first.
const TREAD_VOTIVES := [[1, 4], [0, 3]]
## New candles strike as the reveal lifts and catch in half a second.
const STRIKE_DELAY := 1.2
const STRIKE_CATCH := 0.5
const STRIKE_FLASH := 0.25
const DAWN := Color("c9d2ee")

## The moment new victory candles strike on the title.
signal candle_struck

var time := 0.0
var reveal := 1.0
## What the save remembers, read once per arrival and never while drawing:
## `ending` is Save.get_last_ending(), `dawn` whether the keep was ever put out.
var legacy := {"victories": 0, "roll": [], "celebrated": 0, "ending": "", "dawn": false}

var _depth: Control
var _glow: Control
var _votives: Control
var _knight: Control
var _fog: Control
var _embers: CPUParticles2D
var _rings: Array = []
var _torches: Array = []
var _niches: Array = []
var _candle_slots: Array = []
var _exclusions: Array = []
var _celebrate_from := -1
var _celebrate_t := 0.0
var _last_reveal_drawn := -1.0


func _ready() -> void:
	name = "TitleTableau"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_depth = _layer("Depth", _draw_depth, null)
	_glow = _layer("Glow", _draw_glow, VFX.radial_material())
	_votives = _layer("Votives", _draw_votives, null)
	_knight = _layer("Knight", _draw_knight, null)
	_fog = _layer("Fog", _draw_fog, null)
	_embers = CPUParticles2D.new()
	_embers.name = "Embers"
	_embers.amount = 44
	_embers.lifetime = 7.0
	_embers.preprocess = 4.0
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.local_coords = true
	_embers.direction = Vector2(0.0, -1.0)
	_embers.spread = 22.0
	_embers.gravity = Vector2.ZERO
	_embers.initial_velocity_min = 40.0
	_embers.initial_velocity_max = 110.0
	_embers.tangential_accel_min = -18.0
	_embers.tangential_accel_max = 18.0
	_embers.scale_amount_min = 1.2
	_embers.scale_amount_max = 2.8
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(VFX.GOLD, 0.0), Color(VFX.GOLD, 0.85), Color(VFX.ORANGE, 0.5), Color(VFX.EMBER, 0.0)])
	_embers.color_ramp = ramp
	_embers.material = VFX.additive_material()
	add_child(_embers)
	resized.connect(_relayout)
	_relayout()


func _layer(layer_name: String, painter: Callable, mat: Material) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if mat != null:
		layer.material = mat
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Nothing to paint until the tableau has been laid out at a real size.
	layer.draw.connect(func() -> void:
		if layer.size.x > 0.0 and layer.size.y > 0.0 and not _rings.is_empty():
			painter.call(layer)
	)
	return layer


## Called whenever the title is (re)entered. A reveal only plays when motion
## is allowed; the menu stays focusable and actionable throughout.
func arrive(with_reveal: bool) -> void:
	reveal = 0.0 if (with_reveal and not Feedback.motion_reduced) else 1.0
	legacy = _read_legacy()
	_redraw_all()


## The save's victory record in one read. A win from before the roll of vows was
## kept has no known wax, so it burns plain.
static func _read_legacy() -> Dictionary:
	var d := Save.load_save()
	var roll: Variant = d.get("roll", [])
	return {
		"victories": int(d.get("victories", 0)),
		"roll": roll if roll is Array else [],
		"celebrated": int(d.get("last_celebrated", 0)),
		"ending": Save.get_last_ending(),
		"dawn": Save.ended_ever(),
	}


## Strike the candles of wins numbered `from` onward (0-based) together, as the
## reveal lifts. Reduced motion shows them already burning.
func celebrate(from: int) -> void:
	if from >= _lit_count():
		return
	_celebrate_from = maxi(0, from)
	_celebrate_t = 0.0
	if Feedback.motion_reduced:
		_end_celebration()
		candle_struck.emit()
	_redraw_all()


## Leave every candle burning, as the next arrival will show them.
func _end_celebration() -> void:
	_celebrate_from = -1
	_votives.queue_redraw()
	_glow.queue_redraw()


## UI rectangles (global) whose area must stay clear of candles: the wordmark
## band and the menu column. Candles there would read as stray title ink.
func set_exclusions(rects: Array) -> void:
	var to_local := get_global_transform().affine_inverse()
	_exclusions = rects.map(func(r: Rect2) -> Rect2: return to_local * r)
	_refresh_candle_slots()
	_redraw_all()


## Animated parameters, for stillness contracts: identical while reduced motion holds.
func motion_signature() -> Array:
	return [snappedf(time, 0.0001), snappedf(reveal, 0.0001), snappedf(_celebrate_t, 0.0001)]


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var reduced := Feedback.motion_reduced
	if _embers.visible == reduced:
		_embers.visible = not reduced
		_embers.emitting = not reduced
	if reduced:
		if reveal < 1.0:
			reveal = 1.0
			_redraw_all()
		if _celebrate_from >= 0:
			_end_celebration()
		return
	time += delta
	reveal = minf(1.0, reveal + delta / REVEAL_TIME)
	if _celebrate_from >= 0:
		_step_celebration(delta)
	# The far shaft is static once revealed; the near layers breathe every frame.
	if not is_equal_approx(reveal, _last_reveal_drawn):
		_depth.queue_redraw()
	_glow.queue_redraw()
	_votives.queue_redraw()
	_knight.queue_redraw()
	_fog.queue_redraw()


## Advance the strike clock, voicing the strike once, and stop when the new
## flames have grown in.
func _step_celebration(delta: float) -> void:
	var before := _celebrate_t
	_celebrate_t += delta
	if before < STRIKE_DELAY and _celebrate_t >= STRIKE_DELAY:
		candle_struck.emit()
	if _celebrate_t >= STRIKE_DELAY + STRIKE_CATCH:
		_end_celebration()


## Candles showing: one per victory, as many as there are stands.
func _lit_count() -> int:
	return mini(int(legacy.victories), _candle_slots.size())


## Seconds since the new candles struck; negative while they wait.
func _since_strike(n: int) -> float:
	if _celebrate_from < 0 or n < _celebrate_from:
		return INF
	return _celebrate_t - STRIKE_DELAY


## How far candle `n` has caught: 0 still unlit, 1 burning.
func _kindled(n: int) -> float:
	return clampf(_since_strike(n) / STRIKE_CATCH, 0.0, 1.0)


func _redraw_all() -> void:
	_depth.queue_redraw()
	_glow.queue_redraw()
	_votives.queue_redraw()
	_knight.queue_redraw()
	_fog.queue_redraw()


# --- Layout ------------------------------------------------------------------

func _k() -> float:
	return size.y / 720.0


## The knight's feet: the lip of the broken landing, lower-left third.
func knight_foot() -> Vector2:
	return Vector2(size.x * 0.235, size.y * 0.735)


## Global bounds of the knight silhouette (cape to sword tip, flame to boots).
func knight_rect() -> Rect2:
	var sc := KNIGHT_SCALE * _k()
	var foot := knight_foot()
	var origin := foot + Vector2(0.0, -BODY_H * 0.5) * sc
	var local := Rect2(origin + Vector2(-27.0, -50.0) * sc, Vector2(53.0, 78.0) * sc)
	var xf := get_global_transform()
	return Rect2(xf * local.position, local.size * xf.get_scale())


## Global point inside the brightest flame tongue, for render checks.
func knight_flame_point() -> Vector2:
	var sc := KNIGHT_SCALE * _k()
	var head := knight_foot() + Vector2(0.0, -BODY_H * 0.5 - BODY_H * 0.52) * sc
	return get_global_transform() * (head + Vector2(3.0, -10.0) * sc)


func _relayout() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	_rings.clear()
	_torches.clear()
	var vp := Vector2(s.x * 0.60, s.y * 0.905)
	var mouth := Vector2(s.x * 0.62, s.y * 0.06)
	for i in range(RINGS + 1):
		var t := float(i) / float(RINGS)
		var u := 1.0 - pow(1.0 - t, 1.55)
		var c := mouth.lerp(vp, u)
		var rx := lerpf(s.x * 0.78, s.x * 0.075, u)
		_rings.append({ "c": c, "rx": rx, "ry": rx * 0.26, "u": u })
	# Niche torches: a few dying lights along the middle galleries.
	for i in range(1, RINGS - 1):
		var ring: Dictionary = _rings[i]
		var count := maxi(3, int(ring.rx / (170.0 * _k())))
		for j in range(count):
			if VFX.hash01(i * 31 + j, 9) < 0.72:
				continue
			var a := lerpf(PI + 0.25, TAU - 0.25, (float(j) + 0.5) / float(count))
			var p := _on_ring(ring, a)
			_torches.append({ "p": p + Vector2(0.0, 10.0 * _k()), "u": ring.u, "seed": i * 7 + j })
	_niches = _niche_records()
	_refresh_candle_slots()
	_embers.position = Vector2(s.x * 0.60, s.y * 0.93)
	_embers.emission_rect_extents = Vector2(s.x * 0.16, 8.0)
	_redraw_all()


## Point on a ring's ledge ellipse at the given angle.
func _on_ring(ring: Dictionary, angle: float) -> Vector2:
	return Vector2(ring.c.x + cos(angle) * ring.rx, ring.c.y + sin(angle) * ring.ry)


## Arched recesses of uneven size along each gallery, one Array per ring. The
## Depth painter cuts them and the victory candles stand on their sills, so a
## candle always sits in a niche that is really drawn.
func _niche_records() -> Array:
	var k := _k()
	var out: Array = []
	for i in range(RINGS):
		var top: Dictionary = _rings[i]
		var bot: Dictionary = _rings[i + 1]
		var ring: Array = []
		var count := maxi(6, int(top.rx / (95.0 * k)))
		if i == 0:
			count = maxi(4, count / 2)
		for j in range(count):
			var seed := i * 17 + j
			var a := lerpf(PI + 0.12, TAU - 0.12, (float(j) + 0.5 + (VFX.hash01(seed, 8) - 0.5) * 0.5) / float(count))
			var base := _on_ring(bot, a)
			var crown := _on_ring(top, a)
			var h := (base - crown).length()
			if h < 8.0:
				continue
			var nh := h * (0.30 + VFX.hash01(seed, 6) * 0.28)
			var kind := VFX.hash01(seed, 7)
			ring.append({
				"seed": seed, "nh": nh, "kind": kind,
				"nw": minf(nh * 0.62, top.rx * 0.7 / float(count)),
				"foot": base.lerp(crown, 0.16),
				"effigy": kind > 0.84 and i > 0 and i < 5 and nh > 26.0 * k,
			})
		out.append(ring)
	return out


## The near enclosure in front of the galleries: the vault walls, the broken
## bridge and the landing with its lit treads. Shared by the Depth painter and
## the candle placement, so no candle burns on stone the viewer cannot see.
func _foreground(s: Vector2) -> Dictionary:
	var k := _k()
	var by := s.y * 0.20
	var foot := knight_foot()
	return {
		"walls": [
			PackedVector2Array([
				Vector2(0.0, 0.0), Vector2(s.x * 0.20, 0.0), Vector2(s.x * 0.15, s.y * 0.20),
				Vector2(s.x * 0.12, s.y * 0.44), Vector2(s.x * 0.06, s.y * 0.62), Vector2(0.0, s.y * 0.70),
			]),
			PackedVector2Array([
				Vector2(s.x, 0.0), Vector2(s.x * 0.86, 0.0), Vector2(s.x * 0.90, s.y * 0.16),
				Vector2(s.x * 0.94, s.y * 0.34), Vector2(s.x, s.y * 0.44),
			]),
		],
		"bridge": PackedVector2Array([
			Vector2(s.x, by - 18.0 * k), Vector2(s.x * 0.905, by - 16.0 * k), Vector2(s.x * 0.83, by - 12.0 * k),
			Vector2(s.x * 0.765, by - 2.0 * k), Vector2(s.x * 0.78, by + 14.0 * k), Vector2(s.x * 0.76, by + 30.0 * k),
			Vector2(s.x * 0.79, by + 44.0 * k), Vector2(s.x * 0.86, by + 50.0 * k), Vector2(s.x, by + 46.0 * k),
		]),
		"landing": PackedVector2Array([
			Vector2(0.0, s.y), Vector2(0.0, s.y * 0.60), Vector2(s.x * 0.05, s.y * 0.62),
			Vector2(s.x * 0.08, s.y * 0.66), Vector2(s.x * 0.13, s.y * 0.68), Vector2(s.x * 0.17, s.y * 0.715),
			Vector2(foot.x - 30.0 * k, foot.y), Vector2(foot.x + 44.0 * k, foot.y + 2.0 * k),
			Vector2(foot.x + 62.0 * k, foot.y + 22.0 * k), Vector2(foot.x + 50.0 * k, foot.y + 60.0 * k),
			Vector2(foot.x + 70.0 * k, foot.y + 110.0 * k), Vector2(foot.x + 40.0 * k, s.y),
		]),
		"treads": [
			[Vector2(s.x * 0.05, s.y * 0.62), Vector2(s.x * 0.08, s.y * 0.66)],
			[Vector2(s.x * 0.13, s.y * 0.68), Vector2(s.x * 0.17, s.y * 0.715)],
			[Vector2(foot.x - 30.0 * k, foot.y), Vector2(foot.x + 44.0 * k, foot.y + 2.0 * k)],
		],
	}


## Where the victory candles stand, first win first: open niche sills nearest
## the knight, so the keep is lit outward from where it stands, then votives on
## the two treads behind it. A sill is skipped when its candle would be hidden
## by the near stone or would sit under the wordmark, the menu or the knight.
func _refresh_candle_slots() -> void:
	_candle_slots.clear()
	if _niches.is_empty():
		return
	var k := _k()
	var near := _foreground(size)
	var hiding: Array = near.walls + [near.bridge, near.landing]
	var clear: Array = _exclusions + [get_global_transform().affine_inverse() * knight_rect().grow(6.0 * k)]
	var frame := Rect2(Vector2.ZERO, size)
	var stand := knight_foot()
	var sills: Array = []
	for i in range(1, RINGS):
		for niche in _niches[i]:
			if niche.kind < 0.26:
				continue # collapsed or sealed
			var h := clampf(float(niche.nh) * 0.24, 4.0 * k, 15.0 * k)
			var p: Vector2 = niche.foot + Vector2(float(niche.nw) * 0.3 if niche.effigy else 0.0, 0.0)
			var tip := p + Vector2(0.0, -h * 2.2)
			var body := Rect2(tip, Vector2.ZERO).expand(p).grow(h * 0.5)
			if not frame.encloses(body) or _covered(p, hiding) or _covered(tip, hiding) or _touches_any(body, clear):
				continue
			sills.append({ "p": p, "h": h, "d": p.distance_squared_to(stand) })
	sills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	_candle_slots = sills
	for tread in TREAD_VOTIVES:
		var pair: Array = near.treads[tread[0]]
		for n in range(tread[1]):
			_candle_slots.append({ "p": pair[1].lerp(pair[0], (float(n) + 0.5) / float(tread[1])), "h": 9.0 * k })


static func _covered(p: Vector2, polys: Array) -> bool:
	for poly in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


static func _touches_any(box: Rect2, rects: Array) -> bool:
	for r in rects:
		if (r as Rect2).intersects(box):
			return true
	return false


func _arc(ring: Dictionary, from: float, to: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var a := lerpf(from, to, float(i) / float(steps))
		pts.append(_on_ring(ring, a))
	return pts


func _ease(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


# --- Depth: sky, galleries, walls, bridge, landing --------------------------

func _draw_depth(ci: Control) -> void:
	var s := ci.size
	var k := _k()
	_last_reveal_drawn = reveal
	var e := _ease(reveal)
	# Sealed vault: void above, deep navy where the shaft opens.
	VFX.draw_vgradient(ci, Rect2(Vector2.ZERO, s), Color("04030a"), Color("100b1f"))
	# Pit floor: the furnace basin, painted dark warm so the additive pool has body,
	# with molten seams that the glow layer will bloom.
	var last: Dictionary = _rings[RINGS]
	ci.draw_colored_polygon(_arc(last, PI, TAU, 24) + PackedVector2Array([last.c + Vector2(last.rx, last.ry * 2.6), last.c + Vector2(-last.rx, last.ry * 2.6)]), Color("2a0d0c"))
	for j in range(5):
		var a := lerpf(PI * 1.15, PI * 1.85, float(j) / 4.0)
		var p0: Vector2 = last.c + Vector2(cos(a) * last.rx * 0.55, sin(a) * last.ry * 0.55 + last.ry * 0.9)
		var p1: Vector2 = last.c + Vector2(cos(a) * last.rx * 1.3, sin(a) * last.ry * 1.3 + last.ry * 2.2)
		ci.draw_line(p0, p1, Color(VFX.GOLD, 0.5), 1.5 * k, true)
	if legacy.ending == "crown":
		_draw_far_throne(ci, last.c, k)
	# Galleries: back-wall faces between consecutive ledge arcs. Cold and in the
	# vault's shadow at the top, hazed and warmed toward the furnace.
	for i in range(RINGS):
		var top: Dictionary = _rings[i]
		var bot: Dictionary = _rings[i + 1]
		var u: float = bot.u
		var face := Color("1a1230").lerp(Color("3a1a1c"), u)
		face = face.lerp(Color("141a30"), 0.32 * u)
		if i == 0:
			face = face.darkened(0.6)
		var lower := face.darkened(0.35)
		var arc_top := _arc(top, PI, TAU, 48)
		var arc_bot := _arc(bot, PI, TAU, 48)
		var poly := PackedVector2Array(arc_top)
		var rev := PackedVector2Array(arc_bot)
		rev.reverse()
		poly.append_array(rev)
		var cols := PackedColorArray()
		for j in range(arc_top.size()):
			cols.append(face)
		for j in range(arc_bot.size()):
			cols.append(lower)
		ci.draw_polygon(poly, cols)
		# Masonry courses: thin broken lines following the arc.
		var courses := 3 if i < 4 else 2
		for c in range(1, courses + 1):
			var f := float(c) / float(courses + 1)
			var line := PackedVector2Array()
			for j in range(arc_top.size()):
				line.append(arc_top[j].lerp(arc_bot[j], f))
			for j in range(0, line.size() - 1, 2):
				if VFX.hash01(i * 100 + c * 10 + j, 5) < 0.5:
					ci.draw_line(line[j], line[j + 1], Color(VFX.RIM, 0.08 + 0.10 * (1.0 - u)), 1.0 * k)
		# Niches: arched recesses of uneven size; some collapsed, some sealed,
		# a few still holding a hooded effigy.
		for niche in _niches[i]:
			var seed: int = niche.seed
			var nh: float = niche.nh
			var nw: float = niche.nw
			var foot: Vector2 = niche.foot
			var kind: float = niche.kind
			var ink := Color("06040c", 0.84 - 0.36 * u)
			if kind < 0.14 and i > 0:
				# Collapsed: a jagged bite out of the wall with rubble at the sill.
				var bite := PackedVector2Array([foot + Vector2(-nw * 0.6, 0.0), foot + Vector2(-nw * 0.45, -nh * 0.5), foot + Vector2(-nw * 0.1, -nh * 0.8), foot + Vector2(nw * 0.3, -nh * 0.55), foot + Vector2(nw * 0.55, -nh * 0.15), foot + Vector2(nw * 0.6, 0.0)])
				ci.draw_colored_polygon(bite, ink)
				for r in range(3):
					ci.draw_circle(foot + Vector2((VFX.hash01(seed + r, 12) - 0.5) * nw, -VFX.hash01(seed + r, 13) * nh * 0.12), (1.5 + VFX.hash01(seed + r, 14) * 2.0) * k, face.darkened(0.5))
				continue
			var arch := PackedVector2Array([foot + Vector2(-nw * 0.5, 0.0), foot + Vector2(-nw * 0.5, -nh * 0.62)])
			for q in range(7):
				var ang := PI + PI * float(q) / 6.0
				arch.append(foot + Vector2(cos(ang) * nw * 0.5, -nh * 0.62 + sin(ang) * nh * 0.38))
			arch.append(foot + Vector2(nw * 0.5, 0.0))
			if kind < 0.26:
				# Sealed with newer, paler stone.
				ci.draw_colored_polygon(arch, face.lightened(0.10))
				ci.draw_polyline(arch, Color("06040c", 0.7), 1.0 * k)
				continue
			ci.draw_colored_polygon(arch, ink)
			if niche.effigy:
				# Hooded effigy standing in the dark.
				var eh := nh * 0.62
				var ew := nw * 0.34
				var eb := foot + Vector2(0.0, -2.0 * k)
				ci.draw_colored_polygon(PackedVector2Array([eb + Vector2(-ew * 0.5, 0.0), eb + Vector2(-ew * 0.36, -eh * 0.62), eb + Vector2(0.0, -eh), eb + Vector2(ew * 0.36, -eh * 0.62), eb + Vector2(ew * 0.5, 0.0)]), Color("2a2140", 0.9 - 0.3 * u))
				ci.draw_line(eb + Vector2(-ew * 0.5, 0.0), eb + Vector2(ew * 0.5, 0.0), Color(VFX.SLATE, 0.3), 1.0 * k)
			ci.draw_line(foot + Vector2(-nw * 0.5, 0.0), foot + Vector2(nw * 0.5, 0.0), Color(VFX.RIM, 0.22 * (1.0 - u)), 1.0 * k)
		# Pilasters dividing the arcade: solid, shaded, kept inside their face.
		var ribs := maxi(3, int(top.rx / (300.0 * k))) + (i % 2)
		var shift := (VFX.hash01(i, 33) - 0.5) * 0.5 / float(ribs)
		for j in range(ribs):
			var a := lerpf(PI + 0.16, TAU - 0.16, (float(j) + 0.5) / float(ribs) + shift)
			var p0 := _on_ring(top, a)
			var p1 := _on_ring(bot, a)
			var wdt := (7.0 - 4.0 * u) * k
			var rib := PackedVector2Array([p0 + Vector2(-wdt, 0.0), p0 + Vector2(wdt, 0.0), p1 + Vector2(wdt * 0.7, 0.0), p1 + Vector2(-wdt * 0.7, 0.0)])
			ci.draw_polygon(rib, PackedColorArray([face.darkened(0.55), face.darkened(0.2), lower.darkened(0.2), lower.darkened(0.55)]))
			ci.draw_line(p0 + Vector2(wdt * 0.6, 0.0), p1 + Vector2(wdt * 0.4, 0.0), Color(VFX.SLATE, 0.14 * (1.0 - u)), 1.0 * k)
		# Ledge lip: a cold catch-light, broken where the gallery has fallen away.
		var seg := 0
		while seg < arc_top.size() - 1:
			var run := 2 + int(VFX.hash01(i * 50 + seg, 15) * 5.0)
			var gap := VFX.hash01(i * 50 + seg, 16) < 0.18
			if not gap:
				var part := PackedVector2Array()
				for q in range(seg, mini(seg + run + 1, arc_top.size())):
					part.append(arc_top[q])
				if part.size() >= 2:
					ci.draw_polyline(part, Color(VFX.RIM, 0.32 - 0.2 * u), 1.5 * k, true)
			elif i > 0:
				var q := mini(seg + 1, arc_top.size() - 1)
				var drop := (10.0 + VFX.hash01(seg, 17) * 16.0) * k * (1.0 - 0.5 * u)
				# Straight drops: skewing the lower corners inward bow-ties the quad
				# (and fails triangulation) wherever two arc points sit close together.
				if arc_top[seg].distance_to(arc_top[q]) > 1.0:
					ci.draw_colored_polygon(PackedVector2Array([arc_top[seg], arc_top[q], arc_top[q] + Vector2(0.0, drop), arc_top[seg] + Vector2(0.0, drop * 0.6)]), face.darkened(0.6))
			seg += run
	# Near vault and walls: the enclosure we stand inside, near-black with ribs.
	var near := _foreground(s)
	for wall in near.walls:
		ci.draw_colored_polygon(wall, Color("07050c"))
	for j in range(3):
		var x0 := s.x * (0.04 + 0.05 * float(j))
		ci.draw_line(Vector2(x0, 0.0), Vector2(x0 - s.x * 0.02, s.y * (0.55 - 0.1 * float(j))), Color(VFX.SLATE, 0.10), 2.0 * k)
	# Broken bridge high on the right: the crossing that no longer exists.
	var by := s.y * 0.20
	var bridge: PackedVector2Array = near.bridge
	ci.draw_polygon(bridge, VFX.shaded_colors(bridge, Color("120c1c"), 1.6, 0.6))
	ci.draw_polyline(bridge.slice(0, 4), Color(VFX.SLATE, 0.55), 2.0 * k, true)
	for j in range(4):
		var px := s.x * (0.80 + 0.05 * float(j))
		ci.draw_line(Vector2(px, by - 16.0 * k), Vector2(px + 2.0 * k, by + 46.0 * k), Color("05040a", 0.7), 3.0 * k)
	for j in range(3):
		var px := s.x * (0.83 + 0.055 * float(j))
		ci.draw_rect(Rect2(px, by - 40.0 * k, 9.0 * k, 24.0 * k), Color("0d0915"))
		ci.draw_line(Vector2(px, by - 40.0 * k), Vector2(px + 9.0 * k, by - 40.0 * k), Color(VFX.SLATE, 0.4), 1.5 * k)
	# A hanging cage swings under the broken end.
	var cage := Vector2(s.x * 0.775, by + 50.0 * k)
	ci.draw_line(cage, cage + Vector2(0.0, 34.0 * k), Color("2a2038"), 1.5 * k)
	ci.draw_rect(Rect2(cage + Vector2(-9.0 * k, 34.0 * k), Vector2(18.0 * k, 26.0 * k)), Color("0a0712"))
	ci.draw_rect(Rect2(cage + Vector2(-9.0 * k, 34.0 * k), Vector2(18.0 * k, 26.0 * k)), Color(VFX.SLATE, 0.35), false, 1.0 * k)
	# The landing: broken stair in near-black silhouette, catch-light on each tread.
	var foot := knight_foot()
	ci.draw_colored_polygon(near.landing, Color("05040a"))
	for pair in near.treads:
		ci.draw_line(pair[0], pair[1], Color(VFX.SLATE, 0.5), 2.0 * k, true)
	ci.draw_line(Vector2(foot.x + 44.0 * k, foot.y + 2.0 * k), Vector2(foot.x + 62.0 * k, foot.y + 22.0 * k), Color(VFX.RIM, 0.35), 1.5 * k, true)
	for j in range(6):
		var rp := foot + Vector2((-20.0 + VFX.hash01(j, 21) * 70.0) * k, (4.0 + VFX.hash01(j, 22) * 10.0) * k)
		ci.draw_circle(rp, (2.0 + VFX.hash01(j, 23) * 4.0) * k, Color("15101f"))
	# Vault shadow closes the top of the frame.
	VFX.draw_vgradient(ci, Rect2(Vector2.ZERO, Vector2(s.x, s.y * 0.38)), Color("03020a", 0.9), Color("03020a", 0.0))
	# Arrival veil: the shaft is dark until the furnace rises.
	if e < 1.0:
		ci.draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.005, 0.02, (1.0 - e) * 0.82))


## The Ember Throne at the bottom of the well, small with distance: a black
## paper seat with its crown of blades, its edges lit the Warden's red.
func _draw_far_throne(ci: Control, base: Vector2, k: float) -> void:
	var back := PackedVector2Array([base + Vector2(-7.0, 0.0) * k, base + Vector2(-7.0, -22.0) * k, base + Vector2(7.0, -22.0) * k, base + Vector2(7.0, 0.0) * k])
	ci.draw_colored_polygon(back, Color("0b0507"))
	for i in range(5):
		var x := -6.0 + 3.0 * float(i)
		var h := 5.0 + (3.0 if i == 2 else (1.5 if i % 2 == 0 else 0.0))
		ci.draw_colored_polygon(PackedVector2Array([base + Vector2(x - 1.2, -22.0) * k, base + Vector2(x, -22.0 - h) * k, base + Vector2(x + 1.2, -22.0) * k]), Color("0b0507"))
	ci.draw_rect(Rect2(base + Vector2(-10.0, -8.0) * k, Vector2(20.0, 8.0) * k), Color("0b0507"))
	ci.draw_polyline(back, Color(Cast.WARDEN_RED, 0.8), 1.0 * k, true)


# --- Glow: additive light -----------------------------------------------------

func _draw_glow(ci: Control) -> void:
	var s := ci.size
	var k := _k()
	var e := _ease(reveal)
	var t := time
	var breath := 1.0 + sin(t * 0.9) * 0.05
	# The furnace far below: a wide ember pool climbing the lowest galleries.
	# Once the keep has been put out it banks low under the dawn.
	var furnace := e * (0.3 if legacy.dawn else 1.0)
	var last: Dictionary = _rings[RINGS]
	var origin: Vector2 = last.c + Vector2(0.0, s.y * 0.06)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.0, 1.0))
	VFX.draw_radial(ci, Vector2(origin.x * 0.5, origin.y), s.y * 0.62 * breath, Color(VFX.EMBER, 0.70 * furnace))
	VFX.draw_radial(ci, Vector2(origin.x * 0.5, origin.y + 10.0 * k), s.y * 0.34 * breath, Color(VFX.ORANGE, 0.55 * furnace))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	VFX.draw_radial(ci, origin, s.y * 0.16, Color(VFX.GOLD, 0.6 * furnace))
	if legacy.dawn:
		_draw_dawn(ci, s, e)
	match str(legacy.ending):
		"crown":
			# The knight sits below now: the throne's red glow at the bottom of the well.
			VFX.draw_radial(ci, last.c + Vector2(0.0, -6.0 * k), 34.0 * k * breath, Color(Cast.WARDEN_RED, 0.55 * e))
		"given":
			_draw_new_star(ci, s, e, t)
	# Dying torches in the niches.
	for torch in _torches:
		var flick := 0.75 + 0.25 * sin(t * 6.0 + float(torch.seed) * 1.3) * sin(t * 2.3 + float(torch.seed))
		var reach := lerpf(1.0, 0.45, float(torch.u))
		VFX.draw_radial(ci, torch.p, 46.0 * k * reach, Color(VFX.GOLD, 0.34 * flick * e))
		VFX.draw_radial(ci, torch.p, 12.0 * k * reach, Color(VFX.HOT, 0.6 * flick * e))
	# Victory candles: each lends its niche a small warm pool.
	for n in range(_lit_count()):
		var slot: Dictionary = _candle_slots[n]
		var flick := 0.85 + 0.15 * sin(t * 7.0 + float(n) * 1.9)
		var pool := 0.28 * flick * e * _kindled(n) * (1.0 - _vault_shade(slot.p.y, s.y))
		VFX.draw_radial(ci, slot.p + Vector2(0.0, -float(slot.h) * 1.3), float(slot.h) * 3.2, Color(VFX.GOLD, pool))
	# The knight's own light: the only lamp on the landing, warm on the treads.
	# A knight who has felled the Warden carries a brighter ember.
	if legacy.ending == "crown":
		return
	var sc := KNIGHT_SCALE * k
	var foot := knight_foot()
	var head := foot + Vector2(0.0, -BODY_H * 0.5 - BODY_H * 0.52) * sc
	var halo := 0.92 + sin(t * 9.0) * 0.05 + sin(t * 23.0) * 0.03
	var ember := halo * (1.15 if int(legacy.victories) > 0 else 1.0)
	VFX.draw_radial(ci, head + Vector2(0.0, -8.0 * sc), 120.0 * k * ember, Color(VFX.ORANGE, 0.34))
	VFX.draw_radial(ci, head + Vector2(0.0, -10.0 * sc), 48.0 * k * ember, Color(VFX.GOLD, 0.5))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.4, 1.0))
	VFX.draw_radial(ci, Vector2(foot.x / 2.4, foot.y + 4.0 * k), 34.0 * k, Color(VFX.ORANGE, 0.22 * halo))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One new star over the well, for the flames given back: a white-gold point
## with a slow four-way glint, high in the open mouth.
func _draw_new_star(ci: Control, s: Vector2, e: float, t: float) -> void:
	var k := _k()
	var p := Vector2(s.x * 0.655, s.y * 0.085)
	var glint := 0.85 + 0.15 * sin(t * 1.3)
	VFX.draw_radial(ci, p, 22.0 * k * glint, Color(VFX.GOLD, 0.35 * e))
	VFX.draw_radial(ci, p, 5.0 * k, Color(VFX.HOT, 0.9 * e))
	for arm: Vector2 in [Vector2(1.0, 0.0), Vector2(0.0, 1.0)]:
		ci.draw_line(p - arm * 11.0 * k * glint, p + arm * 11.0 * k * glint, Color(VFX.HOT, 0.5 * e), 1.0 * k)


## The keep's permanent dawn, once it has been put out: pale light at the
## vault mouth and a cold shaft falling into the pit. Kept right of 0.2w so the
## near vault stays dark.
func _draw_dawn(ci: Control, s: Vector2, e: float) -> void:
	VFX.draw_radial(ci, Vector2(s.x * 0.62, s.y * 0.02), s.y * 0.5, Color(DAWN, 0.45 * e))
	# The radial shader fades across U, so the shaft is soft at both edges.
	ci.draw_polygon(PackedVector2Array([
		Vector2(s.x * 0.59, 0.0), Vector2(s.x * 0.65, 0.0),
		Vector2(s.x * 0.66, s.y * 0.95), Vector2(s.x * 0.54, s.y * 0.95),
	]), PackedColorArray([Color(DAWN, 0.16 * e), Color(DAWN, 0.16 * e), Color(DAWN, 0.05 * e), Color(DAWN, 0.05 * e)]),
		PackedVector2Array([Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(1.0, 0.5), Vector2(0.0, 0.5)]))


# --- Votives: victory candles, then the shaft mist, all behind the knight -------

func _draw_votives(ci: Control) -> void:
	var s := ci.size
	var k := _k()
	var t := 0.0 if Feedback.motion_reduced else time
	var e := _ease(reveal)
	for n in range(_lit_count()):
		_draw_candle(ci, n, e, t)
	# Low mist across the shaft: two drifting bands, thin enough to keep the
	# galleries. They pass behind the knight so they never veil its flame.
	for band in range(2):
		var y := s.y * (0.58 + 0.13 * float(band))
		var drift := t * (6.0 + 4.0 * float(band)) * k
		for j in range(7):
			var cx := fposmod(s.x * (0.1 + 0.16 * float(j)) + drift * (1.0 if band == 0 else -1.0), s.x * 1.4) - s.x * 0.2
			var rx := s.x * (0.14 + VFX.hash01(j, 51 + band) * 0.08)
			var ry := s.y * (0.024 + VFX.hash01(j, 53 + band) * 0.018)
			VFX.draw_ellipse(ci, Vector2(cx, y + sin(t * 0.5 + float(j)) * 3.0 * k), rx, ry, Color("4a4f7a", (0.10 + 0.04 * float(band)) * e))


## One victory candle, cut from paper: a wax stub with a lit bevel toward the
## knight, a rim of melt and its flame. A new candle strikes white-hot before it
## catches. Under the vault's shadow it burns as dimly as the stone around it.
func _draw_candle(ci: Control, n: int, e: float, t: float) -> void:
	var slot: Dictionary = _candle_slots[n]
	var p: Vector2 = slot.p
	var h: float = slot.h
	var w := h * 0.42
	var dark := _vault_shade(p.y, ci.size.y)
	var wax := _wax(n).lerp(VFX.VOID, dark)
	ci.draw_rect(Rect2(p.x - w * 0.5, p.y - h, w, h), wax.darkened(0.35))
	ci.draw_rect(Rect2(p.x - w * 0.5, p.y - h, w * 0.4, h), wax)
	ci.draw_rect(Rect2(p.x - w * 0.6, p.y - h, w * 1.2, maxf(1.0, h * 0.12)), wax.lightened(0.15))
	var catch := _kindled(n)
	if catch > 0.0:
		var outer := Color(VFX.GOLD.lerp(VFX.VOID, dark), e)
		VFX.draw_flame(ci, p + Vector2(0.0, -h), h * 1.1 * catch, w * 1.3 * catch, t, float(n) * 1.7, outer, Color(VFX.HOT, e * (1.0 - dark)))
	var strike := _strike_flash(n)
	if strike > 0.0:
		ci.draw_circle(p + Vector2(0.0, -h * 1.3), h * 0.9, Color(VFX.HOT, strike))


## Wax for the candle of win `n`: plain, red under any vow, gilt for the Oath.
func _wax(n: int) -> Color:
	var roll: Array = legacy.roll
	var vows := int(roll[n]) if n < roll.size() else 0
	if vows >= Content.VOWS.size():
		return WAX_OATH
	return WAX_VOWED if vows > 0 else WAX_PLAIN


## White-hot strike of a new candle, fading over STRIKE_FLASH. Never under
## reduced flash.
func _strike_flash(n: int) -> float:
	var since := _since_strike(n)
	if Feedback.flash_reduced or since < 0.0 or since >= STRIKE_FLASH:
		return 0.0
	return 1.0 - since / STRIKE_FLASH


## How much of the Depth layer's vault shadow falls at height `y` (0 in the
## open shaft), so a candle high in the vault is no brighter than its stone.
static func _vault_shade(y: float, height: float) -> float:
	return 0.9 * clampf(1.0 - y / (height * 0.38), 0.0, 1.0)


# --- Knight: the gameplay figure's geometry, presented on the landing -----------

func _draw_knight(ci: Control) -> void:
	# After the crown was taken the landing is empty: the knight is below.
	if legacy.ending == "crown":
		return
	var h := BODY_H
	var facing := 1.0
	var sc := KNIGHT_SCALE * _k()
	var still := Feedback.motion_reduced
	var anim := 0.0 if still else time
	var body_col: Color = Content.PAL.player
	var origin := knight_foot() + Vector2(0.0, -h * 0.5) * sc
	ci.draw_set_transform(origin, 0.0, Vector2(sc, sc))
	VFX.draw_ellipse(ci, Vector2(0.0, h * 0.5 + 1.0), 17.0, 3.6, Color(0.0, 0.0, 0.0, 0.35))
	# The same jointed puppet the knight plays as, at rest on the landing: it
	# breathes, and the updraft out of the drop lifts the cape.
	var pose: Dictionary = KnightArt.REST.duplicate()
	pose.breath = sin(anim * 1.9) * 0.018
	pose.arm_f = 1.14 + sin(anim * 1.9 + 0.6) * 0.03
	pose.cape = 0.18 + sin(anim * 1.7) * 0.12
	pose.flutter = 0.45
	# Under the dawn, or with a new star over the well, the knight looks up.
	pose.head = -0.22 if legacy.dawn or legacy.ending == "given" else -0.04
	# A knight that has felled the Warden wears the brighter, golden ember.
	var won := int(legacy.victories) > 0
	if won:
		pose.flame = 1.15
	KnightArt.paint(ci, origin, pose, facing, {
		"coat": body_col, "t": anim, "scale": sc, "flame_mode": won,
		"blink": 1.0 if fmod(anim, 4.3) > 4.18 else 0.0,
	})
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Fog: mist, chains, foreground -------------------------------------------

func _draw_fog(ci: Control) -> void:
	var s := ci.size
	var k := _k()
	var still := Feedback.motion_reduced
	var t := 0.0 if still else time
	var e := _ease(reveal)
	# Chains from the near vault, swaying a hair in the updraft.
	for i in range(3):
		var x: float = s.x * [0.47, 0.585, 0.72][i]
		var length: float = s.y * [0.34, 0.22, 0.42][i]
		var sway := (0.0 if still else sin(t * 0.7 + float(i) * 2.1) * 5.0 * k)
		VFX.draw_chain(ci, Vector2(x, -4.0), length, sway, Color("2a2038", 0.9))
		VFX.draw_chain(ci, Vector2(x + 2.0 * k, -4.0), length - 6.0 * k, sway, Color(VFX.SLATE, 0.25))
	# Mist spilling off the landing lip into the drop.
	var foot := knight_foot()
	for j in range(4):
		var mp := foot + Vector2((30.0 + 40.0 * float(j) + sin(t * 0.4 + float(j)) * 6.0) * k, (14.0 + 12.0 * float(j)) * k)
		VFX.draw_ellipse(ci, mp, (40.0 + 12.0 * float(j)) * k, (7.0 + 3.0 * float(j)) * k, Color("3a3f66", 0.13 * e))
	# Foreground mist pooling below the landing, hiding the true depth of the drop.
	VFX.draw_vgradient(ci, Rect2(Vector2(0.0, s.y * 0.80), Vector2(s.x, s.y * 0.20)), Color("0e1024", 0.0), Color("0e1024", 0.55))
	# Edge darkening so the frame closes in around the well.
	VFX.draw_vgradient(ci, Rect2(Vector2.ZERO, Vector2(s.x, s.y * 0.22)), Color("03020a", 0.55), Color("03020a", 0.0))
