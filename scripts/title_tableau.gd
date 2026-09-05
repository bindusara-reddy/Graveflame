extends Control
## Original menu art: "The Threshold of the Descent". A title-only tableau of
## the flame-headed knight standing on a broken stair landing inside the mouth
## of a colossal ossuary shaft, looking down into the furnace light far below.
## Everything is authored vector drawing in the game's own crypt palette; the
## knight uses the gameplay figure's exact geometry and colours, only presented
## larger. Nothing here is a gameplay screenshot and nothing touches gameplay.
##
## Layers (back to front): Depth (sky, far galleries, walls, bridge, landing),
## Glow (additive furnace, niche torches, knight halo), Knight, Fog (mist,
## chains, arrival veil) and Embers (particles, hidden under reduced motion).

const VFX := preload("res://scripts/vfx.gd")

## Seconds for the arrival reveal: the furnace rises and the galleries emerge.
const REVEAL_TIME := 1.6
const RINGS := 7
## Gameplay figure size (Content.P_BODY_W/H) reproduced, never altered.
const BODY_W := 26.0
const BODY_H := 54.0
const KNIGHT_SCALE := 2.0

var time := 0.0
var reveal := 1.0

var _depth: Control
var _glow: Control
var _knight: Control
var _fog: Control
var _embers: CPUParticles2D
var _rings: Array = []
var _torches: Array = []
var _last_reveal_drawn := -1.0


func _ready() -> void:
	name = "TitleTableau"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_depth = _layer("Depth", _draw_depth, null)
	_glow = _layer("Glow", _draw_glow, VFX.radial_material())
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
	set_process(true)


func _layer(layer_name: String, painter: Callable, mat: Material) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if mat != null:
		layer.material = mat
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.draw.connect(painter.bind(layer))
	return layer


## Called whenever the title is (re)entered. A reveal only plays when motion
## is allowed; the menu stays focusable and actionable throughout.
func arrive(with_reveal: bool) -> void:
	reveal = 0.0 if (with_reveal and not Feedback.motion_reduced) else 1.0
	_redraw_all()


## Animated parameters, for stillness contracts: identical while reduced motion holds.
func motion_signature() -> Array:
	return [snappedf(time, 0.0001), snappedf(reveal, 0.0001)]


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
		return
	time += delta
	reveal = minf(1.0, reveal + delta / REVEAL_TIME)
	# The far shaft is static once revealed; the near layers breathe every frame.
	if not is_equal_approx(reveal, _last_reveal_drawn):
		_depth.queue_redraw()
	_glow.queue_redraw()
	_knight.queue_redraw()
	_fog.queue_redraw()


func _redraw_all() -> void:
	_depth.queue_redraw()
	_glow.queue_redraw()
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
			var p: Vector2 = ring.c + Vector2(cos(a) * ring.rx, sin(a) * ring.ry)
			_torches.append({ "p": p + Vector2(0.0, 10.0 * _k()), "u": ring.u, "seed": i * 7 + j })
	_embers.position = Vector2(s.x * 0.60, s.y * 0.93)
	_embers.emission_rect_extents = Vector2(s.x * 0.16, 8.0)
	_redraw_all()


func _arc(ring: Dictionary, from: float, to: float, steps: int, y_off: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var a := lerpf(from, to, float(i) / float(steps))
		pts.append(Vector2(ring.c.x + cos(a) * ring.rx, ring.c.y + sin(a) * ring.ry + y_off))
	return pts


func _ease(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


# --- Depth: sky, galleries, walls, bridge, landing --------------------------

func _draw_depth(ci: Control) -> void:
	var s := ci.size
	if s.x <= 0.0 or s.y <= 0.0 or _rings.is_empty():
		return
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
		var count := maxi(6, int(top.rx / (95.0 * k)))
		if i == 0:
			count = maxi(4, count / 2)
		for j in range(count):
			var seed := i * 17 + j
			var a := lerpf(PI + 0.12, TAU - 0.12, (float(j) + 0.5 + (VFX.hash01(seed, 8) - 0.5) * 0.5) / float(count))
			var base := Vector2(bot.c.x + cos(a) * bot.rx, bot.c.y + sin(a) * bot.ry)
			var crown := Vector2(top.c.x + cos(a) * top.rx, top.c.y + sin(a) * top.ry)
			var h := (base - crown).length()
			if h < 8.0:
				continue
			var nh := h * (0.30 + VFX.hash01(seed, 6) * 0.28)
			var nw := minf(nh * 0.62, top.rx * 0.7 / float(count))
			var foot := base.lerp(crown, 0.16)
			var kind := VFX.hash01(seed, 7)
			var ink := Color("06040c", 0.84 - 0.36 * u)
			if kind < 0.14 and i > 0:
				# Collapsed: a jagged bite out of the wall with rubble at the sill.
				var bite := PackedVector2Array([foot + Vector2(-nw * 0.6, 0.0), foot + Vector2(-nw * 0.45, -nh * 0.5), foot + Vector2(-nw * 0.1, -nh * 0.8), foot + Vector2(nw * 0.3, -nh * 0.55), foot + Vector2(nw * 0.55, -nh * 0.15), foot + Vector2(nw * 0.6, 0.0)])
				ci.draw_colored_polygon(bite, ink)
				for r in range(3):
					ci.draw_circle(foot + Vector2((VFX.hash01(seed + r, 12) - 0.5) * nw, -VFX.hash01(seed + r, 13) * nh * 0.12), (1.5 + VFX.hash01(seed + r, 14) * 2.0) * k, face.darkened(0.5))
				continue
			var niche := PackedVector2Array([foot + Vector2(-nw * 0.5, 0.0), foot + Vector2(-nw * 0.5, -nh * 0.62)])
			for q in range(7):
				var ang := PI + PI * float(q) / 6.0
				niche.append(foot + Vector2(cos(ang) * nw * 0.5, -nh * 0.62 + sin(ang) * nh * 0.38))
			niche.append(foot + Vector2(nw * 0.5, 0.0))
			if kind < 0.26:
				# Sealed with newer, paler stone.
				ci.draw_colored_polygon(niche, face.lightened(0.10))
				ci.draw_polyline(niche, Color("06040c", 0.7), 1.0 * k)
				continue
			ci.draw_colored_polygon(niche, ink)
			if kind > 0.84 and i > 0 and i < 5 and nh > 26.0 * k:
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
			var p0 := Vector2(top.c.x + cos(a) * top.rx, top.c.y + sin(a) * top.ry)
			var p1 := Vector2(bot.c.x + cos(a) * bot.rx, bot.c.y + sin(a) * bot.ry)
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
				ci.draw_colored_polygon(PackedVector2Array([arc_top[seg], arc_top[q], arc_top[q] + Vector2(-2.0 * k, drop), arc_top[seg] + Vector2(3.0 * k, drop * 0.6)]), face.darkened(0.6))
			seg += run
	# Near vault and walls: the enclosure we stand inside, near-black with ribs.
	var wall := Color("07050c")
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(s.x * 0.20, 0.0), Vector2(s.x * 0.15, s.y * 0.20),
		Vector2(s.x * 0.12, s.y * 0.44), Vector2(s.x * 0.06, s.y * 0.62), Vector2(0.0, s.y * 0.70),
	]), wall)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(s.x, 0.0), Vector2(s.x * 0.86, 0.0), Vector2(s.x * 0.90, s.y * 0.16),
		Vector2(s.x * 0.94, s.y * 0.34), Vector2(s.x, s.y * 0.44),
	]), wall)
	for j in range(3):
		var x0 := s.x * (0.04 + 0.05 * float(j))
		ci.draw_line(Vector2(x0, 0.0), Vector2(x0 - s.x * 0.02, s.y * (0.55 - 0.1 * float(j))), Color(VFX.SLATE, 0.10), 2.0 * k)
	# Broken bridge high on the right: the crossing that no longer exists.
	var by := s.y * 0.20
	var bridge := PackedVector2Array([
		Vector2(s.x, by - 18.0 * k), Vector2(s.x * 0.905, by - 16.0 * k), Vector2(s.x * 0.83, by - 12.0 * k),
		Vector2(s.x * 0.765, by - 2.0 * k), Vector2(s.x * 0.78, by + 14.0 * k), Vector2(s.x * 0.76, by + 30.0 * k),
		Vector2(s.x * 0.79, by + 44.0 * k), Vector2(s.x * 0.86, by + 50.0 * k), Vector2(s.x, by + 46.0 * k),
	])
	ci.draw_polygon(bridge, VFX.shaded_colors(bridge, Color("120c1c"), 1.6, 0.6))
	ci.draw_polyline(PackedVector2Array([Vector2(s.x, by - 18.0 * k), Vector2(s.x * 0.905, by - 16.0 * k), Vector2(s.x * 0.83, by - 12.0 * k), Vector2(s.x * 0.765, by - 2.0 * k)]), Color(VFX.SLATE, 0.55), 2.0 * k, true)
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
	var landing := PackedVector2Array([
		Vector2(0.0, s.y), Vector2(0.0, s.y * 0.60), Vector2(s.x * 0.05, s.y * 0.62),
		Vector2(s.x * 0.08, s.y * 0.66), Vector2(s.x * 0.13, s.y * 0.68), Vector2(s.x * 0.17, s.y * 0.715),
		Vector2(foot.x - 30.0 * k, foot.y), Vector2(foot.x + 44.0 * k, foot.y + 2.0 * k),
		Vector2(foot.x + 62.0 * k, foot.y + 22.0 * k), Vector2(foot.x + 50.0 * k, foot.y + 60.0 * k),
		Vector2(foot.x + 70.0 * k, foot.y + 110.0 * k), Vector2(foot.x + 40.0 * k, s.y),
	])
	ci.draw_colored_polygon(landing, Color("05040a"))
	var treads := [
		[Vector2(s.x * 0.05, s.y * 0.62), Vector2(s.x * 0.08, s.y * 0.66)],
		[Vector2(s.x * 0.13, s.y * 0.68), Vector2(s.x * 0.17, s.y * 0.715)],
		[Vector2(foot.x - 30.0 * k, foot.y), Vector2(foot.x + 44.0 * k, foot.y + 2.0 * k)],
	]
	for pair in treads:
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


# --- Glow: additive light -----------------------------------------------------

func _draw_glow(ci: Control) -> void:
	var s := ci.size
	if s.x <= 0.0 or s.y <= 0.0 or _rings.is_empty():
		return
	var k := _k()
	var e := _ease(reveal)
	var t := time
	var breath := 1.0 + sin(t * 0.9) * 0.05
	# The furnace far below: a wide ember pool climbing the lowest galleries.
	var last: Dictionary = _rings[RINGS]
	var origin: Vector2 = last.c + Vector2(0.0, s.y * 0.06)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.0, 1.0))
	VFX.draw_radial(ci, Vector2(origin.x * 0.5, origin.y), s.y * 0.62 * breath, Color(VFX.EMBER, 0.70 * e))
	VFX.draw_radial(ci, Vector2(origin.x * 0.5, origin.y + 10.0 * k), s.y * 0.34 * breath, Color(VFX.ORANGE, 0.55 * e))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	VFX.draw_radial(ci, origin, s.y * 0.16, Color(VFX.GOLD, 0.6 * e))
	# Dying torches in the niches.
	for torch in _torches:
		var flick := 0.75 + 0.25 * sin(t * 6.0 + float(torch.seed) * 1.3) * sin(t * 2.3 + float(torch.seed))
		var reach := lerpf(1.0, 0.45, float(torch.u))
		VFX.draw_radial(ci, torch.p, 46.0 * k * reach, Color(VFX.GOLD, 0.34 * flick * e))
		VFX.draw_radial(ci, torch.p, 12.0 * k * reach, Color(VFX.HOT, 0.6 * flick * e))
	# The knight's own light: the only lamp on the landing, warm on the treads.
	var sc := KNIGHT_SCALE * k
	var foot := knight_foot()
	var head := foot + Vector2(0.0, -BODY_H * 0.5 - BODY_H * 0.52) * sc
	var halo := 0.92 + sin(t * 9.0) * 0.05 + sin(t * 23.0) * 0.03
	VFX.draw_radial(ci, head + Vector2(0.0, -8.0 * sc), 120.0 * k * halo, Color(VFX.ORANGE, 0.34))
	VFX.draw_radial(ci, head + Vector2(0.0, -10.0 * sc), 48.0 * k * halo, Color(VFX.GOLD, 0.5))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.4, 1.0))
	VFX.draw_radial(ci, Vector2(foot.x / 2.4, foot.y + 4.0 * k), 34.0 * k, Color(VFX.ORANGE, 0.22 * halo))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Knight: the gameplay figure's geometry, presented on the landing -----------

func _draw_knight(ci: Control) -> void:
	var s := ci.size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var w := BODY_W
	var h := BODY_H
	var facing := 1.0
	var sc := KNIGHT_SCALE * _k()
	var still := Feedback.motion_reduced
	var anim := 0.0 if still else time
	var body_col: Color = Content.PAL.player
	var origin := knight_foot() + Vector2(0.0, -h * 0.5) * sc
	ci.draw_set_transform(origin, 0.0, Vector2(sc, sc))
	VFX.draw_ellipse(ci, Vector2(0.0, h * 0.5 + 1.0), 17.0, 3.6, Color(0.0, 0.0, 0.0, 0.35))
	# Tattered scarf/cape trails opposite the facing direction, lifted by the draft.
	var lift := sin(anim * 1.7) * 1.5
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-facing * 7.0, -h * 0.3),
		Vector2(-facing * 25.0, -h * 0.08 - lift),
		Vector2(-facing * 12.0, h * 0.24),
	]), Color("c94a28"))
	ci.draw_line(Vector2(-7.0, h * 0.12), Vector2(-8.0, h * 0.48), Color("17131f"), 8.0, true)
	ci.draw_line(Vector2(7.0, h * 0.12), Vector2(8.0, h * 0.48), Color("221a2c"), 8.0, true)
	var coat := PackedVector2Array([
		Vector2(-w * 0.48, -h * 0.28), Vector2(w * 0.42, -h * 0.32),
		Vector2(w * 0.52, h * 0.24), Vector2(0.0, h * 0.36),
		Vector2(-w * 0.56, h * 0.20),
	])
	VFX.draw_shaded_polygon(ci, coat, body_col, true)
	VFX.draw_rim(ci, coat, facing, 1.0)
	ci.draw_line(Vector2(-facing * 7.0, -h * 0.24), Vector2(facing * 8.0, h * 0.24), Content.PAL.player_accent, 4.0, true)
	var head_pos := Vector2(0.0, -h * 0.52)
	ci.draw_circle(head_pos, w * 0.40, Color("211828"))
	VFX.draw_rim_circle(ci, head_pos, w * 0.40, facing, 0.9)
	var flame_col := Color("ff7a18")
	for i in range(4):
		var fx := -9.0 + float(i) * 6.0
		var tip := 9.0 + sin(anim * 10.0 + float(i) * 1.7) * 4.0
		ci.draw_colored_polygon(PackedVector2Array([
			head_pos + Vector2(fx - 4.0, -4.0),
			head_pos + Vector2(fx, -tip - 7.0),
			head_pos + Vector2(fx + 4.0, -3.0),
		]), flame_col)
	ci.draw_circle(head_pos + Vector2(facing * 4.0, -1.0), 2.8, Color("ffe8a3"))
	ci.draw_line(Vector2(facing * 10.0, -4.0), Vector2(facing * 25.0, 13.0), Color("aab4c4"), 3.0, true)
	ci.draw_line(Vector2(facing * 7.0, 0.0), Vector2(facing * 14.0, -7.0), Color("f0b45a"), 3.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Fog: mist, chains, foreground -------------------------------------------

func _draw_fog(ci: Control) -> void:
	var s := ci.size
	if s.x <= 0.0 or s.y <= 0.0:
		return
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
	# Low mist across the shaft: two drifting bands, thin enough to keep the galleries.
	for band in range(2):
		var y := s.y * (0.58 + 0.13 * float(band))
		var drift := t * (6.0 + 4.0 * float(band)) * k
		for j in range(7):
			var cx := fposmod(s.x * (0.1 + 0.16 * float(j)) + drift * (1.0 if band == 0 else -1.0), s.x * 1.4) - s.x * 0.2
			var rx := s.x * (0.14 + VFX.hash01(j, 51 + band) * 0.08)
			var ry := s.y * (0.024 + VFX.hash01(j, 53 + band) * 0.018)
			VFX.draw_ellipse(ci, Vector2(cx, y + sin(t * 0.5 + float(j)) * 3.0 * k), rx, ry, Color("4a4f7a", (0.10 + 0.04 * float(band)) * e))
	# Mist spilling off the landing lip into the drop.
	var foot := knight_foot()
	for j in range(4):
		var mp := foot + Vector2((30.0 + 40.0 * float(j) + sin(t * 0.4 + float(j)) * 6.0) * k, (14.0 + 12.0 * float(j)) * k)
		VFX.draw_ellipse(ci, mp, (40.0 + 12.0 * float(j)) * k, (7.0 + 3.0 * float(j)) * k, Color("3a3f66", 0.13 * e))
	# Foreground mist pooling below the landing, hiding the true depth of the drop.
	VFX.draw_vgradient(ci, Rect2(Vector2(0.0, s.y * 0.80), Vector2(s.x, s.y * 0.20)), Color("0e1024", 0.0), Color("0e1024", 0.55))
	# Edge darkening so the frame closes in around the well.
	VFX.draw_vgradient(ci, Rect2(Vector2.ZERO, Vector2(s.x, s.y * 0.22)), Color("03020a", 0.55), Color("03020a", 0.0))
