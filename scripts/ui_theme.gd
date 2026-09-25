class_name UiTheme
extends RefCounted
## Graveflame's interface tokens and materials: the ink-and-ember palette, the
## two faces and their type roles, the spacing grid, motion timings, and
## PaperStyle, the StyleBox every sheet, slip, card and button is cut from.
## Static only, so any script can read a token without owning a UI. The
## design language these encode is in the UI design doc (ui_design.md).

const VFX := preload("res://scripts/vfx.gd")

# --- Colour --------------------------------------------------------------------------
# Ground: ink-violet paper, dark to light.
const INK_DEEP := Color("09070f")
const INK := Color("100d18")
const SHEET_LO := Color("130f1b")
const SHEET := Color("1b1624")
const SHEET_HI := Color("282033")
const HAIRLINE_DIM := Color("30293a")
const HAIRLINE := Color("4b3e5b")
# Parchment: the text.
const BONE := Color("eee8df")
const ASH := Color("a99db2")
const SOOT := Color("6f6578")
# Light, used only where attention is due.
const EMBER := Color("ff7a18")
const EMBER_HI := Color("ffad4d")
const CINDER := Color("a8400f")
const GOLD := Color("ffd166")
const HOT := Color("fff0d0")
# Meaning.
const BLOOD := Color("dc5962")
const WARDEN := Color("b94350")
const WAX := Color("8e3c49")
const WAX_HI := Color("c46f7b")
const SPIRIT := Color("7fd4ff")
const VERDIGRIS := Color("2be4c8")
const DAWN := Color("c9d2ee")

# Legacy names the pre-kit screens still use; each is an alias of a token.
const C_VOID := INK_DEEP
const C_INK := INK
const C_SURFACE_HI := SHEET_HI
const C_EDGE := HAIRLINE
const C_TEXT := BONE
const C_MUTED := ASH
const C_EMBER := EMBER
const C_EMBER_HI := EMBER_HI
const C_GOLD := GOLD
const C_MINT := VERDIGRIS
const C_BLUE := SPIRIT
const C_RED := BLOOD
## Streak multiplier colour by tier, dull to blazing.
const STREAK_TIER_COLORS := [ASH, BONE, GOLD, EMBER_HI, BLOOD]

# --- Space and time ------------------------------------------------------------------
## The 4 px grid.
const S1 := 4
const S2 := 8
const S3 := 12
const S4 := 16
const S5 := 24
const S6 := 32
const S7 := 48
## Motion timings in seconds: a focus hop, paper sliding, a screen arriving.
const FAST := 0.12
const MED := 0.24
const SLOW := 0.42


## True while reduced motion is on: animations become short fades or cuts.
static func still() -> bool:
	return Feedback.motion_reduced


# --- Type --------------------------------------------------------------------------
## Type roles: [face, pixel size, tracking]. "serif" is the keep's voice (Noto
## Serif Display Bold, fonts/); "sans" is the reading face (Open Sans SemiBold,
## Godot's built-in font). Tracked sans is only ever set in capitals.
const WORDMARK := "wordmark"
const TITLE := "title"
const HEADLINE := "headline"
const SUBHEAD := "subhead"
const VOICE := "voice"
const NUMERAL := "numeral"
const BODY := "body"
const SMALL := "small"
const CAPS := "caps"
const MICRO := "micro"
const BUTTON := "button"
const ROLES := {
	"wordmark": ["serif", 72, 3],
	"title": ["serif", 44, 1],
	"headline": ["serif", 30, 1],
	"subhead": ["serif", 22, 1],
	"voice": ["serif", 18, 0],
	"numeral": ["serif", 26, 1],
	"body": ["sans", 15, 0],
	"small": ["sans", 13, 0],
	"caps": ["sans", 12, 2],
	"micro": ["sans", 10, 2],
	"button": ["serif", 16, 1],
}

static var _serif: Font
static var _faces: Dictionary = {}


## The face for a type role, tracked as the role asks. Cached per face and
## tracking, so every label in a role shares one font resource.
static func font(role: String) -> Font:
	var spec: Array = ROLES.get(role, ROLES[BODY])
	var key := "%s:%d" % [spec[0], spec[2]]
	if not _faces.has(key):
		var tracked := FontVariation.new()
		tracked.base_font = _serif_file() if spec[0] == "serif" else ThemeDB.fallback_font
		tracked.spacing_glyph = int(spec[2])
		_faces[key] = tracked
	return _faces[key]


static func size(role: String) -> int:
	return int((ROLES.get(role, ROLES[BODY]) as Array)[1])


## Noto Serif Display Bold (SIL OFL 1.1), loaded from the shipped file so the
## keep's voice never depends on the machine's fonts.
static func _serif_file() -> Font:
	if _serif == null:
		var file := FontFile.new()
		if file.load_dynamic_font("res://fonts/NotoSerifDisplay-Bold.ttf") == OK:
			_serif = file
		else:
			push_warning("Graveflame: serif face missing, using the theme font")
			_serif = ThemeDB.fallback_font
	return _serif


## The wordmark's widely tracked serif (legacy name).
static func title_font() -> Font:
	return font(WORDMARK)


## Screen headings' serif (legacy name, also read by the finale).
static func heading_font() -> Font:
	return font(TITLE)


# --- Paper -------------------------------------------------------------------------

## The paper material. One StyleBox draws a whole piece of cut paper, back to
## front: an under-sheet laid askew, the hard shadow, an ember halo, the sheet
## itself, a printed colour band, the top catch light, an inner printed rule
## and the cut edge. Shapes: blade-cut corners, a ribbon with a notched foot,
## or a grave's arch; any straight side can be torn (deckle). Deterministic,
## so paper never shimmers.
class PaperStyle extends StyleBox:
	enum Shape { CUT, RIBBON, ARCH }
	var shape := Shape.CUT
	var fill := Color("1b1624")
	## Hairline around the cut; clear for none.
	var edge := Color(0, 0, 0, 0)
	var edge_width := 1.0
	## Corner bevel (CUT, ARCH foot) or notch depth (RIBBON), in px.
	var cut := 6.0
	## Torn-edge depth in px, on the UiPaint side mask `deckle_sides`.
	var deckle := 0.0
	var deckle_sides := 15
	var shadow := Color(0, 0, 0, 0.6)
	var shadow_offset := Vector2(3, 4)
	## Alpha of the one-pixel catch light along the top edge.
	var light := 0.0
	## A printed band of colour along the top (card rarity, boss red).
	var band := Color(0, 0, 0, 0)
	var band_height := 0.0
	## An inner printed rule, inset from the edge, with lozenge corner marks.
	var rule := Color(0, 0, 0, 0)
	var rule_inset := 6.0
	## Ember halo around the paper (focus); clear for none.
	var glow := Color(0, 0, 0, 0)
	## A second sheet beneath, turned `under_turn` radians and offset.
	var under := Color(0, 0, 0, 0)
	var under_turn := 0.0
	var under_offset := Vector2(3, 4)
	## Paper thickness: a lighter band just inside every edge, the torn core
	## catching light; clear for none.
	var rim := Color(0, 0, 0, 0)
	## The whole piece shifted: lifted toward the eye (-y) or pressed (+).
	var lift := Vector2.ZERO
	## A tooltip's pointer: a notch rising from the top edge's middle.
	var pointer := 0.0
	## A darker lip along the foot: the tile's own thickness (buttons, caps).
	var lip := 0.0
	var lip_color := Color(0, 0, 0, 0.35)
	## Paper grain: faint fibres per 100x100 px of paper.
	var fibres := 0.0
	var seed := 1

	func _draw(ci: RID, rect: Rect2) -> void:
		var r := Rect2(rect.position + lift, rect.size)
		var body := outline(r)
		if under.a > 0.0:
			var askew := UiPaint.turned(outline(rect, seed + 11), under_turn, rect.get_center())
			UiPaint.fill(ci, UiPaint.moved(askew, under_offset), under)
		if shadow.a > 0.0:
			UiPaint.fill(ci, UiPaint.moved(body, shadow_offset), shadow)
		if glow.a > 0.0:
			UiPaint.halo(ci, body, glow)
		if rim.a > 0.0:
			UiPaint.fill(ci, body, rim)
			for inner in Geometry2D.offset_polygon(body, -1.5, Geometry2D.JOIN_MITER):
				UiPaint.fill(ci, inner, fill)
		else:
			UiPaint.fill(ci, body, fill)
		if fibres > 0.0:
			_draw_fibres(ci, r)
		if lip > 0.0:
			var foot := UiPaint.cut_rect(Rect2(r.position.x, r.end.y - lip, r.size.x, lip), 0.0)
			for part in Geometry2D.intersect_polygons(body, foot):
				UiPaint.fill(ci, part, lip_color)
		if band.a > 0.0 and band_height > 0.0:
			var strip := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + band_height), Vector2(r.position.x, r.position.y + band_height)])
			for part in Geometry2D.intersect_polygons(body, strip):
				UiPaint.fill(ci, part, band)
		if light > 0.0:
			RenderingServer.canvas_item_add_line(ci, body[0] + Vector2(0.0, 1.0), body[1] + Vector2(0.0, 1.0), Color(fill.lightened(0.45), light), 1.0)
		if rule.a > 0.0:
			var inner := r.grow(-rule_inset)
			var ruled := UiPaint.cut_rect(inner, maxf(2.0, cut - rule_inset * 0.4))
			UiPaint.stroke(ci, ruled, rule, 1.0)
			for corner in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
				UiPaint.lozenge(ci, corner, 3.0, rule)
		if edge.a > 0.0:
			UiPaint.stroke(ci, body, edge, edge_width)

	## Faint short strokes laid mostly along the grain, the same every frame.
	func _draw_fibres(ci: RID, r: Rect2) -> void:
		var inner := r.grow(-8.0)
		if inner.size.x <= 0.0 or inner.size.y <= 0.0:
			return
		var grain := Color(fill.lightened(0.14), 0.3)
		var count := int(inner.size.x * inner.size.y * fibres / 10000.0)
		for i in range(count):
			var at := inner.position + Vector2(VFX.hash01(i, seed + 101), VFX.hash01(i, seed + 211)) * inner.size
			var run := Vector2.from_angle((VFX.hash01(i, seed + 307) - 0.5) * 0.6) * (5.0 + 12.0 * VFX.hash01(i, seed + 401))
			var end := (at + run).clamp(inner.position, inner.end)
			RenderingServer.canvas_item_add_line(ci, at, end, grain, 1.0)

	## The paper's outline for `r`, torn where asked. `tear_seed` lets the
	## under-sheet tear differently from the sheet above it.
	func outline(r: Rect2, tear_seed := -1) -> PackedVector2Array:
		var pts: PackedVector2Array
		match shape:
			Shape.RIBBON:
				pts = UiPaint.ribbon_rect(r, cut)
			Shape.ARCH:
				pts = UiPaint.arch_rect(r, cut)
			_:
				pts = UiPaint.cut_rect(r, cut)
				if pointer > 0.0:
					var c := r.get_center().x
					pts.insert(1, Vector2(c - pointer, r.position.y))
					pts.insert(2, Vector2(c, r.position.y - pointer))
					pts.insert(3, Vector2(c + pointer, r.position.y))
		return UiPaint.deckled(pts, r, deckle, seed if tear_seed < 0 else tear_seed, deckle_sides)

	## A copy with a few fields changed: the states of one button share a cut.
	## Copied field by field, since Resource.duplicate() skips script members.
	func with(changes: Dictionary) -> PaperStyle:
		var copy := PaperStyle.new()
		for prop in get_property_list():
			var usage: int = prop.usage
			if usage & (PROPERTY_USAGE_SCRIPT_VARIABLE | PROPERTY_USAGE_STORAGE) and not prop.name in ["script", "resource_path"]:
				copy.set(prop.name, get(prop.name))
		for key in changes:
			copy.set(key, changes[key])
		return copy


## Content padding on every side of a style.
static func _pad(style: StyleBox, x: float, y: float) -> StyleBox:
	style.content_margin_left = x
	style.content_margin_right = x
	style.content_margin_top = y
	style.content_margin_bottom = y
	return style


## A screen's sheet: torn top and bottom, a gold rule inside, an under-sheet
## askew beneath and a heavy shadow. `accent` tints the hairline edge.
static func sheet_style(accent := HAIRLINE, seed := 1) -> PaperStyle:
	var s := PaperStyle.new()
	s.fill = SHEET
	s.rim = SHEET.lightened(0.16)
	s.edge = Color(accent, 0.5)
	s.cut = 12.0
	s.deckle = 5.0
	s.deckle_sides = UiPaint.TOP | UiPaint.BOTTOM
	s.shadow = Color(0.0, 0.0, 0.0, 0.62)
	s.shadow_offset = Vector2(6, 8)
	s.rule = Color(GOLD, 0.22)
	s.rule_inset = 10.0
	s.under = Color("221a2b")
	s.under_turn = -0.018
	s.under_offset = Vector2(5, 6)
	s.fibres = 0.7
	s.seed = seed
	return s


## A slip: small clean-cut paper for HUD groups, hints, captions and toasts.
static func slip_style(accent := HAIRLINE, seed := 5) -> PaperStyle:
	var s := PaperStyle.new()
	s.fill = Color(INK, 0.94)
	s.rim = Color(INK.lightened(0.14), 0.94)
	s.edge = Color(accent, 0.75)
	s.cut = 5.0
	s.shadow = Color(0.0, 0.0, 0.0, 0.55)
	s.shadow_offset = Vector2(3, 4)
	s.light = 0.3
	s.seed = seed
	return _pad(s, S3, S2)


## A strip: long banner paper torn on every side, lit by its accent rim.
static func strip_style(accent := EMBER, seed := 9) -> PaperStyle:
	var s := PaperStyle.new()
	s.fill = Color(INK_DEEP, 0.94)
	s.edge = Color(accent, 0.55)
	s.cut = 0.0
	s.deckle = 4.0
	s.shadow = Color(0.0, 0.0, 0.0, 0.5)
	s.shadow_offset = Vector2(4, 6)
	s.seed = seed
	return _pad(s, S6, S3)


## A well: paper pressed into the sheet, for grooves and inset readouts.
static func well_style() -> PaperStyle:
	var s := PaperStyle.new()
	s.fill = SHEET_LO
	s.edge = Color(0.0, 0.0, 0.0, 0.5)
	s.cut = 3.0
	s.shadow = Color(0, 0, 0, 0)
	return _pad(s, S2, S1)


## A dealt card's rest, raised and pressed states: sheet paper with a printed
## band of `tint` along the top and a rule inside. Epic cards carry a wider
## band and a faint ember halo even at rest.
static func card_styles(tint: Color, epic := false, seed := 21) -> Dictionary:
	var rest := PaperStyle.new()
	rest.fill = SHEET
	rest.rim = SHEET.lightened(0.14)
	rest.edge = Color(tint.darkened(0.25), 0.9)
	rest.cut = 10.0
	rest.band = tint.darkened(0.15)
	rest.band_height = 9.0 if epic else 6.0
	rest.rule = Color(tint, 0.18)
	rest.rule_inset = 8.0
	rest.shadow = Color(0.0, 0.0, 0.0, 0.62)
	rest.shadow_offset = Vector2(5, 7)
	rest.light = 0.2
	rest.fibres = 0.8
	rest.seed = seed
	if epic:
		rest.glow = Color(tint, 0.35)
	var raised := rest.with({ "fill": SHEET.lightened(0.04), "rim": SHEET.lightened(0.2), "edge": tint.lightened(0.2), "edge_width": 2.0, "band": tint, "glow": Color(EMBER, 0.9), "rule": Color(tint, 0.3) })
	var pressed := rest.with({ "fill": SHEET.lightened(0.07), "rim": SHEET.lightened(0.2), "edge": GOLD, "edge_width": 2.0, "band": GOLD, "lift": Vector2(1, 2), "shadow_offset": Vector2(3, 4) })
	return { "rest": rest, "raised": raised, "pressed": pressed, "disabled": rest.with({ "fill": SHEET_LO, "band": HAIRLINE_DIM, "edge": HAIRLINE_DIM, "glow": Color(0, 0, 0, 0) }) }


## Button kinds (UiKit.button): ember call to action, ink slip, bare text
## that takes paper only under focus, and wax for what cannot be undone.
enum Kind { PRIMARY, SECONDARY, QUIET, DANGER }


## The paper states of a button of `kind`: rest, raised (focus and hover),
## pressed and disabled, plus its text colours.
static func button_styles(kind: int) -> Dictionary:
	var rest := PaperStyle.new()
	rest.cut = 7.0
	rest.shadow = Color(0.0, 0.0, 0.0, 0.55)
	rest.shadow_offset = Vector2(3, 4)
	rest.light = 0.35
	rest.lip = 3.0
	rest.seed = 31 + kind
	var ink := BONE
	var ink_hot := BONE
	match kind:
		Kind.PRIMARY:
			rest.fill = EMBER
			rest.edge = CINDER
			rest.lip_color = Color(CINDER, 0.75)
			ink = INK
			ink_hot = INK
		Kind.DANGER:
			rest.fill = WAX
			rest.edge = WAX_HI.darkened(0.2)
		Kind.QUIET:
			rest.fill = Color(INK, 0.0)
			rest.shadow = Color(0, 0, 0, 0)
			rest.light = 0.0
			rest.lip = 0.0
			ink = ASH
		_:
			rest.fill = SHEET_HI
			rest.edge = HAIRLINE
	var raised_fill := rest.fill.lightened(0.1) if kind != Kind.QUIET else Color(SHEET_HI, 0.92)
	var raised := rest.with({
		"fill": raised_fill, "edge": GOLD, "edge_width": 1.5, "glow": Color(EMBER, 0.85),
		"lift": Vector2(-1, -2), "shadow": Color(0, 0, 0, 0.6), "shadow_offset": Vector2(5, 7), "light": 0.45,
	})
	var pressed := rest.with({
		"fill": rest.fill.darkened(0.12) if kind != Kind.QUIET else SHEET_HI, "edge": GOLD,
		"lift": Vector2(1, 2), "shadow_offset": Vector2(1, 2), "shadow": Color(0, 0, 0, 0.5), "lip": 0.0,
	})
	var disabled := rest.with({ "fill": Color(SHEET_LO, 0.9) if kind != Kind.QUIET else Color(0, 0, 0, 0), "edge": HAIRLINE_DIM, "shadow": Color(0, 0, 0, 0), "light": 0.0, "lip": 0.0 })
	for style in [rest, raised, pressed, disabled]:
		_pad(style, S4 + 2, S2 + 2)
	return {
		"rest": rest, "raised": raised, "pressed": pressed, "disabled": disabled,
		"ink": ink, "ink_hot": ink_hot if kind != Kind.QUIET else BONE, "ink_disabled": SOOT,
	}


## A bookmark ribbon for tabs: hanging paper with a notched foot, ember when
## it is the open page.
static func ribbon_styles() -> Dictionary:
	var rest := PaperStyle.new()
	rest.shape = PaperStyle.Shape.RIBBON
	rest.fill = SHEET_HI
	rest.edge = HAIRLINE
	rest.cut = 7.0
	rest.shadow = Color(0.0, 0.0, 0.0, 0.5)
	rest.shadow_offset = Vector2(2, 3)
	_pad(rest, S4, S2)
	rest.content_margin_bottom = S2 + 7.0
	var open := rest.with({ "fill": EMBER, "edge": CINDER, "light": 0.4 })
	var raised := rest.with({ "edge": GOLD, "glow": Color(EMBER, 0.8), "fill": SHEET_HI.lightened(0.08) })
	var open_raised := open.with({ "edge": GOLD, "glow": Color(EMBER, 0.8) })
	return { "rest": rest, "open": open, "raised": raised, "open_raised": open_raised }


# --- Burn veil -------------------------------------------------------------------------

## Burning-paper veil between chambers. `progress` 0 = the frame is covered in
## soot-black paper, 1 = fully burned away. The hole opens from `origin` with a
## ragged, noise-driven edge that glows like a paper edge catching fire.
const BURN_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform float progress = 0.0;
uniform vec2 origin = vec2(0.5, 0.55);
uniform float aspect = 1.7778;
// How far the edge travels by progress 1: past the farthest corner plus the
// ragged margin, so the burn always finishes wherever it starts.
uniform float reach = 1.47;
uniform vec4 ink : source_color = vec4(0.035, 0.027, 0.06, 1.0);
uniform vec4 ember : source_color = vec4(1.0, 0.48, 0.12, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.86, 0.55, 1.0);

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

void fragment() {
	vec2 q = vec2((UV.x - origin.x) * aspect, UV.y - origin.y);
	float d = length(q);
	float ragged = fbm(UV * vec2(aspect, 1.0) * 7.0) * 0.22;
	// Distance past the burning edge: > 0 is burned through.
	float edge = progress * reach - (d + ragged);
	float cover = 1.0 - smoothstep(0.0, 0.004, edge);
	// The glowing rim: a hot core just inside, embers fading behind it.
	float rim = exp(-abs(edge) * 60.0);
	float char_band = smoothstep(0.045, 0.0, -edge) * cover;
	vec3 col = mix(ink.rgb, vec3(0.12, 0.05, 0.03), char_band);
	col = mix(col, ember.rgb, rim * 0.9);
	col = mix(col, hot.rgb, pow(rim, 3.0));
	float alpha = max(cover, rim * 0.95);
	COLOR = vec4(col, alpha);
}
"""

static var _burn_material: ShaderMaterial

static func burn_material() -> ShaderMaterial:
	if _burn_material == null:
		var sh := Shader.new()
		sh.code = BURN_SHADER
		_burn_material = ShaderMaterial.new()
		_burn_material.shader = sh
	return _burn_material


## How far the burn's edge must travel from `origin` (in UV) to clear the
## farthest corner of the frame, plus the ragged edge's full depth.
static func burn_reach(origin: Vector2, aspect: float) -> float:
	var from := origin * Vector2(aspect, 1.0)
	var farthest := 0.0
	for corner in [Vector2.ZERO, Vector2(aspect, 0.0), Vector2(0.0, 1.0), Vector2(aspect, 1.0)]:
		farthest = maxf(farthest, from.distance_to(corner))
	return farthest + 0.24


# --- Flat boxes (the HUD until its rebuild) ------------------------------------------

static func panel_box(background: Color, border: Color, radius: int, border_width: int, shadow: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	# One-segment corners: cut with a blade, not rounded like a web card.
	box.corner_detail = 1
	box.anti_aliasing_size = 0.6
	if shadow > 0:
		# A hard, offset shadow: one sheet of paper lying on another.
		box.shadow_color = Color(0.0, 0.0, 0.0, 0.62)
		box.shadow_size = 1
		box.shadow_offset = Vector2(4, 6) if shadow >= 6 else Vector2(3, 4)
	return box


static func bar_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	box.corner_detail = 1
	return box


## A flat, square-cut fill padded by `margin` on every side: the ink channel
## and ember grip of scrollbars.
static func flat_box(color: Color, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(margin)
	box.set_corner_radius_all(2)
	box.corner_detail = 1
	return box
