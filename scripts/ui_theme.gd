class_name UiTheme
extends RefCounted
## Graveflame's interface tokens: colours, faces, and the StyleBoxes every
## screen is cut from. Static only, so any script can read a token without
## owning a UI.

const C_VOID := Color("09070f")
const C_INK := Color("100d18")
const C_SURFACE_HI := Color("282033")
const C_EDGE := Color("4b3e5b")
const C_TEXT := Color("eee8df")
const C_MUTED := Color("a99db2")
const C_EMBER := Color("ff7a18")
const C_EMBER_HI := Color("ffad4d")
const C_GOLD := Color("ffd166")
const C_MINT := Color("2be4c8")
const C_BLUE := Color("7fd4ff")
const C_RED := Color("dc5962")
## Streak multiplier colour by tier, dull to blazing.
const STREAK_TIER_COLORS := [C_MUTED, C_TEXT, C_GOLD, C_EMBER_HI, C_RED]


# --- Burn veil -------------------------------------------------------------------

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


# --- Faces -----------------------------------------------------------------------

## Bundled title face: Noto Serif Display Bold (SIL OFL 1.1, fonts/), loaded
## from the shipped file so the wordmark never depends on the machine's fonts.
static var _wordmark_font: Font


static func title_font() -> Font:
	if _wordmark_font == null:
		var file := FontFile.new()
		if file.load_dynamic_font("res://fonts/NotoSerifDisplay-Bold.ttf") == OK:
			var tracked := FontVariation.new()
			tracked.base_font = file
			tracked.spacing_glyph = 3
			_wordmark_font = tracked
		else:
			push_warning("Graveflame: wordmark font missing, using the theme font")
			_wordmark_font = ThemeDB.fallback_font
	return _wordmark_font


## Headings share the wordmark's serif without its wide tracking, so every
## screen title reads as part of the same printed keep rather than a web form.
static var _heading: Font

static func heading_font() -> Font:
	if _heading == null:
		var base := title_font()
		if base is FontVariation:
			var v := FontVariation.new()
			v.base_font = (base as FontVariation).base_font
			v.spacing_glyph = 1
			_heading = v
		else:
			_heading = base
	return _heading


# --- StyleBoxes ------------------------------------------------------------------

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


static func button_box(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := panel_box(background, border, 9, border_width, 0)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box


static func bar_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	box.corner_detail = 1
	return box


## A flat, square-cut fill padded by `margin` on every side: the ink channel
## and ember grip of scrollbars and sliders.
static func flat_box(color: Color, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(margin)
	box.set_corner_radius_all(2)
	box.corner_detail = 1
	return box


## Boon card frame: no content margins, because the card's own MarginContainer
## owns the padding and the Button only provides the border and tint.
static func card_box(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := panel_box(background, border, 12, border_width, 6)
	# The rarity colour runs heavier along the top, like a card's printed band.
	box.border_width_top = border_width + 4
	box.set_content_margin_all(0.0)
	return box


# --- Toggle glyphs and slider grips ----------------------------------------------

## Drawn procedurally like the rest of the game's art. The default theme's
## unchecked icon renders at the panel's own luminance (measured 0.088 against
## a 0.086 panel), so an OFF toggle showed as blank space and the player could
## not see it, or that the row was interactive at all. These carry explicit
## contrast in both states.
static var _toggle_icon_cache: Dictionary = {}

static func toggle_icons() -> Dictionary:
	if not _toggle_icon_cache.is_empty():
		return _toggle_icon_cache
	_toggle_icon_cache = {
		"unchecked": ImageTexture.create_from_image(_toggle_image(false)),
		"checked": ImageTexture.create_from_image(_toggle_image(true)),
		"grip": ImageTexture.create_from_image(_lozenge_image(C_GOLD)),
		"grip_hot": ImageTexture.create_from_image(_lozenge_image(Color.WHITE.lerp(C_GOLD, 0.35))),
	}
	return _toggle_icon_cache


static func _toggle_image(is_on: bool) -> Image:
	var size := 22
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color("c99a5e") if is_on else Color("a494bc")
	var fill := Color("ff7a18") if is_on else Color("1c1726")
	for y in range(size):
		for x in range(size):
			var on_border := x < 2 or y < 2 or x >= size - 2 or y >= size - 2
			img.set_pixel(x, y, edge if on_border else fill)
	if is_on:
		# A check stroke: a short arm down into a valley, then a long rise. The
		# two arms must meet at the bottom, or it reads as a chevron instead.
		var ink := Color("1a1010")
		for i in range(5):
			for w in range(2):
				img.set_pixel(5 + i + w, 8 + i, ink)
		for i in range(8):
			for w in range(2):
				img.set_pixel(9 + i + w, 12 - i, ink)
	return img


## An 18px lozenge with a dark rim, drawn pixel by pixel like the toggles.
static func _lozenge_image(fill: Color) -> Image:
	var size := 18
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var d := absf(x - c) + absf(y - c)
			if d <= c:
				img.set_pixel(x, y, fill if d <= c - 2.0 else C_INK)
	return img
