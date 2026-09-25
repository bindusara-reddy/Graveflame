class_name UiHud
extends Control
## The in-descent overlay, cut from the kit's paper (ui_design.md §10.1-10.5):
## the knight's slip (the flame portrait, vitality, the Graveflame and the
## flasks), the fury slip, the chamber track with cells and renown, the
## Warden's strip, and every pop-up that plays over a live fight (chamber and
## Warden cards, the clear card and its chip, lessons, the phase tag, the
## inscription, threat pips). It hugs the frame's edges and the upper strip,
## so the fight is never covered. Nothing here redraws while the descent is
## idle: meters and flames animate only while they carry news. Built once by
## the UI facade and driven through it.

const Kit := preload("res://scripts/ui_kit.gd")
const T := preload("res://scripts/ui_theme.gd")
const P := preload("res://scripts/ui_paint.gd")

## Below this share of vitality the knight's flame gutters: the line the red
## vignette starts at (game.gd).
const LOW_VITALITY := 0.34
## Fury tiers by name, one per Content.STREAK_TIERS threshold.
const FURY_NAMES := ["FURY", "WRATH", "RAPTURE", "INFERNO"]
## Where the Warden's fight turns, as shares of its vitality: it ignites,
## then burns its Last Ember. Each is a wax seal on its strip.
const WARDEN_TURNS := [Content.BOSS_PHASE2_AT, Boss.LAST_EMBER_AT]
## How long the clear card stands before it steps aside into its chip, and
## how much longer while it carries a litany line to read.
const CLEAR_HOLD := 1.4
const LITANY_HOLD := 2.6

# The knight's slip.
var _flame: Kit.VitalFlame
var _vitality: Kit.Meter
var _vitality_value: Label
var _graveflame: Kit.Meter
## The Ignite key beside the Graveflame: dim until the flame is full.
var _ignite: Kit.Glyph
var _ignite_ready := false
var _flasks: Kit.Pips
var _heal: Kit.Glyph
# The fury slip.
var _fury: PanelContainer
var _fury_name: Label
var _fury_pips: Kit.Pips
var _fury_mult: Label
var _fury_wick: Kit.Wick
var _fury_tier := 0
# The chamber track.
var _track: Kit.Pips
var _chamber: Label
var _waves: Kit.Pips
var _cells: Label
var _renown: Label
var _renown_value := 0
var _best := 0
# The Warden.
var _warden: Control
var _warden_name: Label
var _warden_value: Label
var _warden_meter: Kit.Meter
var _warden_seals: Array = []
var _boss_ignited := false
var _phase_tag: Control
var _phase_text: Label
# Cards: banners unrolled over the top and foot of the frame.
var _room_intro: Kit.Banner
var _trial_seal: Kit.Seal
var _boss_intro: Kit.Banner
var _clear: Kit.Banner
## The chamber the clear card names; empty while no card is up.
var _clear_name := ""
var _chip: Control
var _litany_tween: Tween
# Notes and the keep's voice.
var _hint: Control
var _hint_stack: VBoxContainer
## The lesson on show, its {action} tokens drawn as live caps.
var _hint_line: Kit.PromptLine
var _inscription: VBoxContainer
var _inscription_tween: Tween
## Paper arrows at the frame's edge for threats beyond it (see track_threats).
var _threat_pips: ThreatPips
var _hud_tween: Tween
## The wave on the HUD as (current, total); zero when the chamber has none.
var _wave_shown := Vector2i.ZERO
## The tween moving each note or popping each slip now, so a new showing
## replaces the last one instead of fighting it.
var _motion: Dictionary = {}


## Lay out every HUD element. Called once the HUD fills the frame.
func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := _column(Control.PRESET_TOP_LEFT, Control.GROW_DIRECTION_END)
	_build_knight_slip(left)
	_build_fury(left)
	_build_chamber_track(_column(Control.PRESET_TOP_RIGHT, Control.GROW_DIRECTION_BEGIN))
	_build_warden()
	# The chamber card takes the Warden's slot, empty outside the throne, so it
	# never covers the platforms where foes arrive. The Warden's card lies on
	# the throne room's brick foundation, clear of the Warden.
	_room_intro = _card("ChamberCard", T.EMBER, 10.0, 104.0, T.HEADLINE, T.BONE)
	_trial_seal = _pin_seal(_room_intro, "tick")
	_boss_intro = _card("WardenCard", T.WARDEN, 546.0, 666.0, T.TITLE, T.WARDEN)
	_build_clear()
	_build_hint()
	_build_inscription()
	_threat_pips = ThreatPips.new()
	_threat_pips.name = "ThreatPips"
	_threat_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_threat_pips)
	_threat_pips.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for meter in [_vitality, _graveflame, _warden_meter]:
		_animate(meter, false)
	set_hp(Content.P_MAX_HP, Content.P_MAX_HP)


## A column of slips hugging one top corner of the frame; each slip keeps its
## own width, lined up on that corner's edge.
func _column(preset: Control.LayoutPreset, grow: Control.GrowDirection) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", T.S2 - 2)
	add_child(col)
	col.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, T.S4)
	col.offset_top = 14.0
	col.grow_horizontal = grow
	return col


## A card: a banner strip across the band `top`..`bottom` that burns open
## from its centre when it plays.
func _card(node_name: String, accent: Color, top: float, bottom: float, title_role: String, title_color: Color) -> Kit.Banner:
	var card := Kit.banner(self, accent, top, bottom, title_role, title_color)
	card.name = node_name
	Kit.ember_edges(card)
	return card


## A slip of paper in `col`, lined up on the column's edge.
func _slip(col: VBoxContainer, node_name: String, accent := T.HAIRLINE) -> PanelContainer:
	var slip := Kit.sheet(col, "slip", accent)
	slip.name = node_name
	var left := col.grow_horizontal == Control.GROW_DIRECTION_END
	slip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if left else Control.SIZE_SHRINK_END
	return slip


## A row that lets clicks through, spaced on the grid.
static func _row(separation := T.S2) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", separation)
	return row


## A full-width band of the frame that centres whatever note it holds. With
## PRESET_BOTTOM_WIDE, negative offsets measure up from the bottom edge. The
## band remembers where it rests, so a note that slid or folded goes back.
func _band(node_name: String, preset: Control.LayoutPreset, top: float, bottom: float) -> CenterContainer:
	var band := CenterContainer.new()
	band.name = node_name
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	band.set_anchors_and_offsets_preset(preset)
	band.offset_top = top
	band.offset_bottom = bottom
	band.set_meta("rest", Vector2(top, bottom))
	band.visible = false
	return band


# --- The knight's slip -------------------------------------------------------------

## The flame portrait, then three lines: vitality with its numeral, the
## Graveflame notched at each Lance's cost with the Ignite key, and the flasks
## with the Flask key. Both meters end at the same x.
func _build_knight_slip(col: VBoxContainer) -> void:
	var row := _row(T.S3)
	_slip(col, "KnightSlip").add_child(row)
	_flame = Kit.vital_flame(60.0)
	row.add_child(_flame)
	var gauges := VBoxContainer.new()
	gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauges.custom_minimum_size.x = 206.0
	gauges.alignment = BoxContainer.ALIGNMENT_CENTER
	gauges.add_theme_constant_override("separation", T.S1 + 1)
	row.add_child(gauges)
	_vitality = Kit.meter(T.BLOOD, 12.0)
	_vitality_value = Kit.label("", T.NUMERAL, T.BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	_vitality_value.add_theme_font_size_override("font_size", 18)
	_gauge(gauges, _vitality, _vitality_value)
	_graveflame = Kit.meter(T.SPIRIT, 8.0, _lance_marks(Content.P_SPECIAL_MAX))
	_ignite = Kit.glyph("ignite", 18.0)
	_gauge(gauges, _graveflame, _ignite)
	var belt := _row()
	gauges.add_child(belt)
	_flasks = Kit.pips(Content.FLASK_MAX, Content.FLASK_MAX, "flame")
	_flasks.spacing = 14.0
	belt.add_child(_flasks)
	_heal = Kit.glyph("heal", 18.0)
	belt.add_child(_heal)
	_paint_ignite(false)


## One gauge line: the meter fills the width and its mark stands in a fixed
## slot after it, so a longer numeral never shortens the meter.
func _gauge(gauges: VBoxContainer, meter: Kit.Meter, mark: Control) -> void:
	var line := _row()
	gauges.add_child(line)
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(meter)
	var slot := _row(0)
	slot.alignment = BoxContainer.ALIGNMENT_END
	slot.custom_minimum_size.x = 34.0
	line.add_child(slot)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_END
	slot.add_child(mark)


## Kit meters flicker their burning tip every frame. The HUD lets a meter
## flicker only while it carries news (Ignite ready, vitality low, the Warden
## burning) and otherwise holds its tip still, so an idle HUD never redraws.
static func _animate(meter: Kit.Meter, on: bool) -> void:
	meter.set_process(on)


func set_hp(hp: float, max_hp: float) -> void:
	_vitality.set_value(hp, max_hp)
	_vitality_value.text = str(maxi(0, roundi(hp)))
	var share := clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	var low := share <= LOW_VITALITY
	_flame.vitality = share
	if _flame.guttering != low:
		_flame.guttering = low
		_animate(_vitality, low)
		_vitality_value.add_theme_color_override("font_color", T.BLOOD if low else T.BONE)


func set_special(value: float, maximum: float) -> void:
	_graveflame.set_value(value, maximum)
	var ready := maximum > 0.0 and value >= maximum
	if ready != _ignite_ready:
		_paint_ignite(ready)


## A full Graveflame is a prompt: the meter breathes white-hot, the Ignite key
## lights in ember and the knight's flame roars. Otherwise the key waits dim.
func _paint_ignite(ready: bool) -> void:
	_ignite_ready = ready
	_graveflame.hot = ready
	_graveflame.queue_redraw()
	_animate(_graveflame, ready)
	_ignite.lit = ready
	_ignite.modulate.a = 1.0 if ready else 0.4
	_flame.roaring = ready


## Notch fractions for every Lance's worth of Graveflame below a full bar.
static func _lance_marks(maximum: float) -> Array:
	var marks: Array = []
	var cost := Content.P_SPECIAL_COST
	while cost < maximum - 0.5:
		marks.append(cost / maximum)
		cost += Content.P_SPECIAL_COST
	return marks


## A lit flame per charge on the belt, a snuffed wick per spent one. A charge
## that comes back pops the belt, so a refill is noticed mid-fight.
func set_flask(charges: int, max_charges: int) -> void:
	var belt := maxi(0, max_charges)
	var lit := clampi(charges, 0, belt)
	var refilled := lit > _flasks.filled and belt == _flasks.count
	_flasks.count = belt
	_flasks.filled = lit
	_heal.modulate.a = 1.0 if lit > 0 else 0.4
	if refilled:
		_pop(_flasks, 1.3, Vector2(0.0, 0.5))


## Paper that just changed swells and settles. Reduced motion keeps it still.
## `pivot` is the point it swells from, as a share of its size.
func _pop(node: Control, swell: float, pivot: Vector2) -> void:
	Kit.kill_tween(_motion.get(node))
	node.scale = Vector2.ONE
	if T.still():
		return
	node.pivot_offset = node.size * pivot
	node.scale = Vector2.ONE * swell
	var t := Kit.tween(node)
	t.tween_property(node, "scale", Vector2.ONE, T.MED).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motion[node] = t


# --- Fury --------------------------------------------------------------------------

## A slim slip under the knight's: the tier's name, its pips, the multiplier
## and a wick that burns down with the window to keep the fury alive.
func _build_fury(col: VBoxContainer) -> void:
	_fury = _slip(col, "Fury", T.GOLD)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	_fury.add_child(stack)
	var head := _row()
	head.custom_minimum_size.x = 150.0
	stack.add_child(head)
	_fury_name = Kit.label("", T.CAPS, T.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_fury_name.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	head.add_child(_fury_name)
	_fury_pips = Kit.pips(FURY_NAMES.size(), 1, "lozenge")
	_fury_pips.spacing = 13.0
	_fury_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_fury_pips)
	_fury_mult = Kit.label("", T.NUMERAL, T.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_fury_mult.add_theme_font_size_override("font_size", 22)
	head.add_child(_fury_mult)
	_fury_wick = Kit.wick()
	stack.add_child(_fury_wick)
	_fury.visible = false


func set_streak(kills: int, frac: float, mult: float) -> void:
	if kills < 2:
		hide_streak()
		return
	var tier := clampi(Content.streak_tier(kills), 1, FURY_NAMES.size())
	if tier != _fury_tier:
		var color: Color = T.STREAK_TIER_COLORS[tier]
		_fury_name.text = FURY_NAMES[tier - 1]
		_fury_pips.color = color
		_fury_pips.filled = tier
		_fury_wick.color = color
		for word in [_fury_name, _fury_mult]:
			word.add_theme_color_override("font_color", color)
		_fury.add_theme_stylebox_override("panel", T.slip_style(color))
		_fury.visible = true
		if tier > _fury_tier:
			_pop(_fury, 1.12, Vector2(0.0, 0.5))
		_fury_tier = tier
	_fury_mult.text = "×" + String.num(mult, 2)
	_fury_wick.fraction = frac


## The window drains every frame; everything else changes only on a kill.
func set_streak_fraction(frac: float) -> void:
	_fury_wick.fraction = frac


func hide_streak() -> void:
	Kit.kill_tween(_motion.get(_fury))
	_fury.visible = false
	_fury.scale = Vector2.ONE
	_fury_tier = 0


# --- Chamber track, cells, renown --------------------------------------------------

## Top right: the descent as pips (cleared chambers gold, the current one a
## flame, the throne a crown), the chamber by numeral and name, the waves of
## this chamber, the cells carried, and renown, quieter below.
func _build_chamber_track(col: VBoxContainer) -> void:
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 1)
	_slip(col, "ChamberTrack").add_child(stack)
	_track = Kit.pips(8, 0)
	_track.crowned = true
	_track.size_flags_horizontal = Control.SIZE_SHRINK_END
	stack.add_child(_track)
	_chamber = Kit.label("", T.CAPS, T.BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	stack.add_child(_chamber)
	var purse := _row()
	stack.add_child(purse)
	_waves = Kit.pips(0, 0, "lozenge", T.EMBER_HI)
	_waves.spacing = 13.0
	_waves.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_waves.visible = false
	purse.add_child(_waves)
	var cell := Kit.pips(1, 1, "cell")
	cell.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	purse.add_child(cell)
	_cells = Kit.label("0", T.NUMERAL, T.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_cells.add_theme_font_size_override("font_size", 22)
	_cells.size_flags_horizontal = Control.SIZE_SHRINK_END
	purse.add_child(_cells)
	var fame := _row()
	stack.add_child(fame)
	fame.add_child(Kit.label("RENOWN", T.MICRO, T.ASH, HORIZONTAL_ALIGNMENT_LEFT))
	_renown = Kit.label("0", T.CAPS, T.ASH, HORIZONTAL_ALIGNMENT_RIGHT)
	fame.add_child(_renown)


## Seven chambers lead down to the throne, which is named rather than counted.
## The chamber's own name joins its numeral when its card is dealt.
func set_room(idx: int, total: int) -> void:
	var throne := idx >= total - 1
	_track.count = total
	_track.filled = total if throne else idx
	_track.current = -1 if throne else idx
	_chamber.text = "THE EMBER THRONE" if throne else "CHAMBER %s" % Kit.roman(idx + 1)


## Waves in the current chamber, so the fight has a visible end: one pip per
## wave, lit up to the one being fought.
func set_wave(current: int, total: int) -> void:
	_waves.count = total
	_waves.filled = current
	_waves.visible = true
	_wave_shown = Vector2i(current, total)


func hide_wave() -> void:
	_waves.visible = false
	_wave_shown = Vector2i.ZERO


func set_score(score: int) -> void:
	_renown_value = score
	_paint_renown()


func set_cells(value: int) -> void:
	_cells.text = Kit.format_number(value)


func set_best(value: int) -> void:
	_best = value
	_paint_renown()


## Renown turns gold once this descent climbs past the highest ever reached.
func _paint_renown() -> void:
	_renown.text = Kit.format_number(_renown_value)
	var height := _best > 0 and _renown_value > _best
	_renown.add_theme_color_override("font_color", T.GOLD if height else T.ASH)


## Ease the whole HUD out for a cinematic beat, or snap it back for play.
func set_hud_faded(faded: bool) -> void:
	Kit.kill_tween(_hud_tween)
	if not faded:
		modulate = Color.WHITE
		return
	_hud_tween = Kit.tween(self)
	_hud_tween.tween_property(self, "modulate:a", 0.0, 0.5)


# --- Threats -----------------------------------------------------------------------

## Called every frame of play with the chamber's enemies and the camera's
## world-to-screen transform. A foe winding up beyond the frame, or one of
## the last two of the final wave hiding beyond it, gets a pip on the edge
## nearest it, so no strike and no straggler comes from nowhere.
func track_threats(enemies: Array, view: Transform2D) -> void:
	var alive := enemies.filter(func(e): return is_instance_valid(e) and not e.dead)
	var stragglers := _wave_shown.x > 0 and _wave_shown.x >= _wave_shown.y and alive.size() <= 2
	var frame := Rect2(Vector2.ZERO, size)
	var pips: Array = []
	for foe in alive:
		var winding: bool = foe.state == Enemy.EState.WINDUP
		var at: Vector2 = view * foe.global_position
		if frame.has_point(at) or not (winding or stragglers):
			continue
		var edge := at.clamp(Vector2.ONE * ThreatPips.INSET, frame.size - Vector2.ONE * ThreatPips.INSET)
		var color: Color = Content.ELITE_COLOR if foe.elite else foe.data.color
		pips.append({ "at": edge, "angle": (at - edge).angle(), "color": color, "winding": winding })
	_threat_pips.show_pips(pips)


## Small cut-paper arrowheads at the frame's edge, each pointing at a foe
## beyond it in that foe's colour. A foe winding up gets a larger arrow in an
## ember halo that throbs (steady under reduced motion); a straggler's is
## small and still. Repaints only when a pip moves or throbs.
class ThreatPips extends Control:
	const INSET := 22.0
	var _pips: Array = []

	func show_pips(pips: Array) -> void:
		var throbbing := pips.any(func(p): return p.winding) and not T.still()
		if pips == _pips and not throbbing:
			return
		_pips = pips
		queue_redraw()

	func _draw() -> void:
		var ci := get_canvas_item()
		var t := Time.get_ticks_msec() * 0.001
		for pip in _pips:
			var span := 14.0 if pip.winding else 9.0
			if pip.winding and not T.still():
				span *= 1.0 + 0.16 * sin(t * 14.0)
			# A notched arrowhead, tip first, pointing along +x.
			var head := Transform2D(float(pip.angle), pip.at) * PackedVector2Array([
				Vector2(span, 0.0), Vector2(-0.7 * span, -0.75 * span),
				Vector2(-0.35 * span, 0.0), Vector2(-0.7 * span, 0.75 * span),
			])
			P.fill(ci, P.moved(head, Vector2(2.0, 3.0)), Color(0.0, 0.0, 0.0, 0.55))
			if pip.winding:
				P.halo(ci, head, Color(T.EMBER, 0.9))
			P.fill(ci, head, pip.color)
			P.stroke(ci, head, T.INK, 1.5)


# --- The Warden --------------------------------------------------------------------

## A torn strip in the Warden's red across the top: its name, its vitality,
## and a wax seal at each turn of the fight, broken as the fight passes it.
## The phase tag hangs under it on a slip of its own.
func _build_warden() -> void:
	_warden = _band("Warden", Control.PRESET_TOP_WIDE, 10.0, 94.0)
	var strip := Kit.sheet(_warden, "strip", T.WARDEN, Vector2(480.0, 0.0))
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", T.S1)
	strip.add_child(stack)
	var head := _row()
	stack.add_child(head)
	_warden_name = Kit.label("The Ember Warden", T.SUBHEAD, T.BONE, HORIZONTAL_ALIGNMENT_LEFT)
	head.add_child(_warden_name)
	_warden_value = Kit.label("", T.CAPS, T.WAX_HI, HORIZONTAL_ALIGNMENT_RIGHT)
	_warden_value.size_flags_horizontal = Control.SIZE_SHRINK_END
	head.add_child(_warden_value)
	_warden_meter = Kit.meter(T.WARDEN, 12.0, WARDEN_TURNS)
	stack.add_child(_warden_meter)
	for turn in WARDEN_TURNS:
		_warden_seals.append(Kit.meter_seal(_warden_meter, turn, 26.0))
	_phase_tag = _band("WardenPhase", Control.PRESET_TOP_WIDE, 94.0, 130.0)
	var tag := Kit.caption("", T.WARDEN)
	_phase_tag.add_child(tag)
	_phase_text = tag.get_child(0) as Label
	_phase_text.add_theme_font_override("font", T.font(T.CAPS))
	_phase_text.add_theme_font_size_override("font_size", T.size(T.CAPS))
	_phase_text.add_theme_color_override("font_color", T.EMBER_HI)


func show_boss_bar(max_hp: float) -> void:
	_warden.visible = true
	_warden_meter.set_value(max_hp, max_hp)
	_warden_value.text = str(roundi(max_hp))
	for seal in _warden_seals:
		seal.broken = false
	_set_boss_ignited(false)


## Called every frame of the throne fight; repaints only when the Warden's
## vitality moves. Each turn of the fight it passes breaks its seal.
func update_boss_bar(hp: float) -> void:
	if is_equal_approx(hp, _warden_meter.value):
		return
	_warden_meter.set_value(hp, _warden_meter.max_value)
	_warden_value.text = str(maxi(0, roundi(hp)))
	var share := hp / _warden_meter.max_value
	for i in range(WARDEN_TURNS.size()):
		if share <= WARDEN_TURNS[i] and not _warden_seals[i].broken:
			_warden_seals[i].broken = true
			_pop(_warden_seals[i], 1.6, Vector2(0.5, 0.5))
	if not _boss_ignited and share <= Content.BOSS_PHASE2_AT:
		_set_boss_ignited(true)


## Past its first seal the Warden burns: its meter takes the ember and its
## leading edge flickers for the rest of the fight.
func _set_boss_ignited(on: bool) -> void:
	_boss_ignited = on
	_warden_meter.fill = T.EMBER if on else T.WARDEN
	_warden_meter.queue_redraw()
	_animate(_warden_meter, on)


func hide_boss_bar() -> void:
	_warden.visible = false
	_animate(_warden_meter, false)


## The phase callout: a small slip hung under the Warden's strip, never over
## the fighters. It drops in, holds and folds away on its own.
func flash_boss_phase(text: String, hold: float = 1.7) -> void:
	_phase_text.text = text.to_upper()
	_note(_phase_tag, Vector2(0.0, -8.0), hold)


func show_boss_intro(boss_name: String, subtitle: String, hold: float = 2.4) -> void:
	# The Warden's card owns the frame: drop any chamber card still folding,
	# and any lesson in the low band it now covers.
	_room_intro.stop()
	hide_hint()
	_warden_name.text = boss_name
	_boss_intro.play(subtitle.to_upper(), boss_name, "", hold)


# --- Chamber cards -----------------------------------------------------------------

## A wax seal pinned over the left end of a banner's strip, riding its
## unroll: the Trial's mark on the chamber card.
static func _pin_seal(banner: Kit.Banner, emboss: String) -> Kit.Seal:
	var pin := Control.new()
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.strip.add_child(pin)
	var seal := Kit.seal(40.0, T.WAX, emboss)
	pin.add_child(seal)
	seal.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	seal.offset_left = -T.S6 - 20.0
	seal.offset_right = -T.S6 + 20.0
	seal.offset_top = -20.0
	seal.offset_bottom = 20.0
	seal.visible = false
	return seal


func show_room_intro(idx: int, total: int, room_name: String, trial: bool = false) -> void:
	var numeral := Kit.roman(idx + 1)
	_chamber.text = "%s · %s" % [numeral, room_name.to_upper()]
	var kicker := "CHAMBER %s OF %s" % [numeral, Kit.roman(total - 1)]
	if trial:
		kicker += "  ·  TRIAL"
	_trial_seal.visible = trial
	_room_intro.play(kicker, room_name.to_lower().capitalize(), "", 1.5)


## The clear card (a strip in verdigris under the Warden's slot) and the chip
## it steps aside into: a slip in the top slot that stays until a rift is
## taken, saying only where to go.
func _build_clear() -> void:
	_clear = _card("ClearCard", T.VERDIGRIS, 100.0, 216.0, T.HEADLINE, T.VERDIGRIS)
	_chip =_band("ClearChip", Control.PRESET_TOP_WIDE, 14.0, 54.0)
	var line := _row()
	Kit.sheet(_chip, "slip", T.VERDIGRIS).add_child(line)
	line.add_child(Kit.seal(20.0, T.VERDIGRIS.darkened(0.5), "tick"))
	line.add_child(Kit.label("THE WAY OPENS", T.CAPS, T.VERDIGRIS, HORIZONTAL_ALIGNMENT_LEFT))
	line.add_child(Kit.label("·", T.CAPS, T.SOOT))
	line.add_child(Kit.label("CHOOSE A RIFT", T.CAPS, T.BONE, HORIZONTAL_ALIGNMENT_LEFT))


func show_room_clear(room_name: String) -> void:
	hide_room_clear()
	_room_intro.stop()
	_hide_inscription()
	_clear_name = room_name.strip_edges().to_upper()
	_play_clear("")


## A litany line printed on the clear card: it fades in just after the card
## lands, the card stands longer so it can be read, and it leaves with the
## card when the card steps aside into its chip. Call it with or after
## show_room_clear; after the card has stepped aside, the card comes back
## to carry it.
func show_litany(text: String) -> void:
	if not _clear_name.is_empty():
		_play_clear(text)


## Unroll the clear card naming the chamber (and its litany when there is
## one), hold it long enough to read, then fold it away into the chip.
func _play_clear(litany: String) -> void:
	_drop(_chip)
	var hold := CLEAR_HOLD + (0.0 if litany.is_empty() else LITANY_HOLD)
	_clear.play(_clear_name, "The Way Opens", litany, hold).tween_callback(_note.bind(_chip, Vector2(0.0, 14.0), -1.0))
	Kit.kill_tween(_litany_tween)
	if litany.is_empty():
		return
	_clear.line.modulate.a = 0.0
	_litany_tween = Kit.tween(_clear.line)
	_litany_tween.tween_interval(0.4)
	_litany_tween.tween_property(_clear.line, "modulate:a", 1.0, 0.15 if T.still() else 0.6)


func hide_room_clear() -> void:
	_clear_name = ""
	_clear.stop()
	Kit.kill_tween(_litany_tween)
	_drop(_chip)


# --- Notes: lessons, the phase tag, the chip ---------------------------------------

## Lay a note down: it slides in from `from` and settles, holds `hold`
## seconds and folds away; a negative hold keeps it until it is dropped.
## Showing a note again replaces its last showing.
func _note(note: Control, from: Vector2, hold: float) -> void:
	_drop(note)
	var t := Kit.slide_in(note, from)
	if hold >= 0.0:
		t.tween_interval(hold)
		t.tween_callback(func() -> void: _motion[note] = Kit.fold_out(note))
	_motion[note] = t


## Take a note off the frame at once and set it back where it rests.
func _drop(note: Control) -> void:
	Kit.kill_tween(_motion.get(note))
	note.visible = false
	note.scale = Vector2.ONE
	note.modulate = Color.WHITE
	var rest: Vector2 = note.get_meta("rest")
	note.offset_top = rest.x
	note.offset_bottom = rest.y


## Lessons sit in the low band, under the fight and clear of the HUD.
func _build_hint() -> void:
	_hint = _band("Lesson", Control.PRESET_BOTTOM_WIDE, -118.0, -58.0)
	_hint_stack = Kit.padded_stack(Kit.sheet(_hint, "slip", T.EMBER), T.S1, 0, 0)


## Show a one-time lesson. Re-showing replaces the current one rather than
## stacking, so two triggers in the same second cannot queue up noise. The
## lesson's {action} tokens become the player's live key caps.
func show_hint(text: String, hold: float = 4.5) -> void:
	Kit.clear_children(_hint_stack)
	_hint_line = Kit.prompt_line(text)
	_hint_stack.add_child(_hint_line)
	_note(_hint, Vector2(0.0, 12.0), hold)


func hide_hint() -> void:
	_drop(_hint)


# --- The keep's voice --------------------------------------------------------------

## The inscription carries no paper: only the keep's voice, ink-haloed so it
## holds over a lit chamber, placed above the fight.
func _build_inscription() -> void:
	var holder := _band("Inscription", Control.PRESET_TOP_WIDE, 150.0, 290.0)
	_inscription = VBoxContainer.new()
	_inscription.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inscription.add_theme_constant_override("separation", T.S2)
	holder.add_child(_inscription)


## The keep speaks over a chamber: each line surfaces in turn (the last in
## gold) with an ornament between, the lines hold, then all fade together.
## Replaces any inscription still showing; never takes input.
func show_inscription(lines: Array) -> void:
	Kit.kill_tween(_inscription_tween)
	Kit.clear_children(_inscription)
	var holder := _inscription.get_parent() as Control
	holder.visible = true
	holder.modulate = Color.WHITE
	_inscription_tween = Kit.tween(self)
	for i in range(lines.size()):
		if i > 0:
			var mark := Kit.ornament(T.GOLD)
			mark.modulate.a = 0.0
			_inscription.add_child(mark)
			_inscription_tween.tween_interval(0.5)
			_inscription_tween.tween_property(mark, "modulate:a", 1.0, 0.3)
		var last := i == lines.size() - 1 and i > 0
		_surface(_voice_line(str(lines[i]), T.GOLD if last else T.BONE), 0.9)
	_inscription_tween.tween_interval(3.5)
	_inscription_tween.tween_property(holder, "modulate:a", 0.0, 0.9)
	_inscription_tween.tween_callback(holder.hide)


## A line of the keep's voice in a slot of its own size, so the words can
## rise inside it while the column around them keeps still.
func _voice_line(text: String, color: Color) -> Label:
	var line := Kit.outlined(Kit.label(text, T.VOICE, color), 5)
	line.add_theme_font_size_override("font_size", 24)
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = line.get_combined_minimum_size()
	slot.add_child(line)
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.modulate.a = 0.0
	_inscription.add_child(slot)
	return line


## The line's turn: it fades up while rising a few pixels into place. Reduced
## motion keeps only the fade.
func _surface(line: Label, duration: float) -> void:
	var slot := line.get_parent() as Control
	_inscription_tween.tween_property(slot, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_SINE)
	if not T.still():
		_inscription_tween.parallel().tween_property(line, "position:y", 0.0, duration).from(10.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _hide_inscription() -> void:
	Kit.kill_tween(_inscription_tween)
	_inscription.get_parent().visible = false


func hide_banners() -> void:
	_hide_inscription()
	_threat_pips.show_pips([])
	_drop(_phase_tag)
	hide_hint()
	_room_intro.stop()
	_boss_intro.stop()
