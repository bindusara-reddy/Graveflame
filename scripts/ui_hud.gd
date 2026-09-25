class_name UiHud
extends Control
## The in-descent overlay: the knight's vitality, Graveflame and flasks, the
## chamber track and cells, the Warden's bar, and every pop-up that plays over
## a live fight (chamber and boss cards, the clear card, lessons, the streak,
## threat pips). Built once by the UI facade and driven through it.

const Kit := preload("res://scripts/ui_kit.gd")
const T := preload("res://scripts/ui_theme.gd")

var _hp_bar: ProgressBar
## Pale "chip" behind a bar: what was just lost lingers, then drains away.
var _hp_trail: ProgressBar
var _boss_trail: ProgressBar
var _trail_tweens: Dictionary = {}
var _hp_value_label: Label
var _special_bar: ProgressBar
var _special_value_label: Label
## Graveflame last shown, kept so the IGNITE prompt can be repainted.
var _special_shown := Vector2(0.0, Content.P_SPECIAL_MAX)
## The Graveflame fill's own style: it breathes white while Ignite is ready.
var _special_fill: StyleBoxFlat
var _ignite_tween: Tween
var _room_label: Label
var _wave_label: Label
## The wave on the HUD as (current, total); zero when the chamber has none.
var _wave_shown := Vector2i.ZERO
## Paper arrows at the frame's edge for threats beyond it (see track_threats).
var _threat_pips: ThreatPips
var _score_label: Label
var _boss_panel: Control
var _boss_bar: ProgressBar
var _boss_value_label: Label
var _boss_name_label: Label
## Whether the boss bar wears its second-phase ember colours.
var _boss_ignited := false
var _flask_container: HBoxContainer
var _flask_sigils: Array = []
var _flask_count_label: Label
## Charges and belt size last shown, kept so the key prompt can be repainted.
var _flask_shown := Vector2i(Content.FLASK_MAX, Content.FLASK_MAX)
var _cells_label: Label
var _best_label: Label

var _room_clear_banner: Control
var _room_clear_name: Label
var _room_clear_tween: Tween
const ROOM_CLEAR_TOP := 148.0

var _streak_panel: PanelContainer
var _streak_kills_label: Label
var _streak_mult_label: Label
var _streak_bar: ProgressBar
var _streak_tier := 0
var _streak_tween: Tween

var _room_intro: Dictionary = {}
var _boss_intro: Dictionary = {}
## One-time contextual lesson, shown low and out of the play space.
var _hint_panel: Control
var _hint_label: Label
## The lesson as written, with {action} tokens, so a device switch can re-fill it.
var _hint_template := ""
var _hint_tween: Tween
var _boss_phase_tag: Label
var _boss_phase_tween: Tween
var _hud_tween: Tween


## Lay out every HUD element. Called once the HUD fills the frame.
func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(UiInput.PROMPT_GROUP)
	_build_player_status()
	_build_streak_meter()
	_build_run_status()
	_build_boss_status()
	_build_boss_phase_tag()
	_build_room_clear_banner()
	# The chamber card takes the boss bar's slot, always empty outside the
	# throne, so it never covers the platforms where enemies arrive. The boss
	# card sits on the throne room's brick foundation, clear of the Warden.
	_room_intro = _build_banner("RoomIntro", 18.0, 96.0, Vector2(470, 70), 26, 11, T.C_EMBER, Color("14101ceb"))
	_boss_intro = _build_banner("BossIntro", 546.0, 666.0, Vector2(620, 118), 40, 14, T.C_RED, Color("1a0c11f0"))
	_build_hint()
	_threat_pips = ThreatPips.new()
	_threat_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_threat_pips)
	_threat_pips.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Teaching prompt: sits below the fight, clear of the fighters and the HUD.
func _build_hint() -> void:
	_hint_panel = _hud_strip("HintBanner", Control.PRESET_BOTTOM_WIDE, -112.0, -54.0)
	var panel := Kit.passive_panel(_hint_panel, T.panel_box(Color("0f0b16f2"), T.C_EMBER, 10, 1, 10))
	var margin := Kit.margin(26, 26, 9, 9)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	# This is the one line a new player must read, so it is set a step larger
	# than the ambient HUD text rather than matching it.
	_hint_label = Kit.label("", 16, T.C_TEXT)
	# Inside the margin, or the first glyph sits on the panel's edge.
	margin.add_child(_hint_label)
	_hint_panel.visible = false


func _build_streak_meter() -> void:
	_streak_panel = Kit.passive_panel(self, T.panel_box(Color("1b1624d9"), Color("715026"), 10, 1, 8))
	_streak_panel.name = "StreakMeter"
	_streak_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_streak_panel.offset_left = 16.0
	_streak_panel.offset_top = 122.0
	_streak_panel.offset_right = 216.0
	_streak_panel.offset_bottom = 166.0
	_streak_panel.pivot_offset = Vector2(0.0, 25.0)
	var stack := Kit.padded_stack(_streak_panel, 14, 8, 3)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	head.add_child(Kit.label("STREAK", 11, T.C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_streak_kills_label = Kit.label("2 KILLS", 13, T.C_TEXT)
	head.add_child(_streak_kills_label)
	_streak_mult_label = Kit.label("x1.25", 15, T.C_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_streak_mult_label)
	_streak_bar = Kit.bar(T.C_GOLD, Color("3a2c14"), 6.0)
	_streak_bar.max_value = 100.0
	_streak_bar.value = 100.0
	stack.add_child(_streak_bar)
	_streak_panel.visible = false


## Fading title card used for room entries and the boss reveal.
func _build_banner(node_name: String, top: float, bottom: float, minimum: Vector2, title_size: int, sub_size: int, accent: Color, background: Color) -> Dictionary:
	var center := _hud_strip(node_name, Control.PRESET_TOP_WIDE, top, bottom)
	var panel := Kit.passive_panel(center, T.panel_box(background, accent, 10, 1, 12), minimum)
	var stack := Kit.padded_stack(panel, 28, 10, 1)
	var sub := Kit.label("", sub_size, T.C_MUTED)
	stack.add_child(sub)
	var title := Kit.label("", title_size, accent)
	stack.add_child(title)
	center.visible = false
	return { "root": center, "title": title, "sub": sub, "tween": null }


func _play_banner(banner: Dictionary, title: String, subtitle: String, hold: float) -> void:
	(banner.title as Label).text = title
	(banner.sub as Label).text = subtitle
	banner.tween = Kit.flash_card(banner.root, banner.tween, 0.22, hold, 0.55)


## Cut a title card short: stop its fade and hide it.
func _hide_banner(banner: Dictionary) -> void:
	if banner.is_empty():
		return
	Kit.kill_tween(banner.tween)
	(banner.root as Control).visible = false


func _build_player_status() -> void:
	var panel := Kit.passive_panel(self, T.panel_box(Color("100c16b8"), Color("3a3048"), 8, 1, 6))
	panel.name = "PlayerStatus"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16.0
	panel.offset_top = 14.0
	panel.offset_right = 296.0
	panel.offset_bottom = 112.0
	var stack := Kit.padded_stack(panel, 12, 8, 5)

	_hp_value_label = Kit.stat_line(stack, "VITALITY", "100 / 100", T.C_TEXT, 11)
	var hp_pair := Kit.trailed_bar(T.C_RED, Color("4a1820"), 12.0)
	stack.add_child(hp_pair.holder)
	_hp_bar = hp_pair.bar
	_hp_trail = hp_pair.trail

	_special_value_label = Kit.stat_line(stack, "GRAVEFLAME", "0 / 100", T.C_BLUE, 10)
	_special_bar = Kit.bar(T.C_BLUE, Color("153243"), 7.0)
	_special_bar.max_value = Content.P_SPECIAL_MAX
	_special_bar.value = 0.0
	_special_fill = _special_bar.get_theme_stylebox("fill") as StyleBoxFlat
	stack.add_child(_special_bar)
	Kit.notch_bar(_special_bar, _lance_marks(Content.P_SPECIAL_MAX))

	var supplies := HBoxContainer.new()
	supplies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	supplies.add_theme_constant_override("separation", 8)
	stack.add_child(supplies)
	var flask_tag := Kit.label("FLASK", 10, T.C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	flask_tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	supplies.add_child(flask_tag)
	_flask_container = HBoxContainer.new()
	_flask_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flask_container.add_theme_constant_override("separation", 5)
	_flask_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	supplies.add_child(_flask_container)
	_flask_count_label = Kit.label("", 10, T.C_MINT, HORIZONTAL_ALIGNMENT_RIGHT)
	_flask_count_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	supplies.add_child(_flask_count_label)
	_rebuild_flask_sigils(Content.FLASK_MAX)


func _build_run_status() -> void:
	var panel := Kit.passive_panel(self, T.panel_box(Color("100c16b8"), Color("3a3048"), 8, 1, 6))
	panel.name = "RunStatus"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -226.0
	panel.offset_top = 14.0
	panel.offset_right = -16.0
	panel.offset_bottom = 132.0
	var stack := Kit.padded_stack(panel, 12, 8, 4)

	_room_label = Kit.label("ROOM 01 / 06", 12, T.C_EMBER_HI, HORIZONTAL_ALIGNMENT_RIGHT)
	stack.add_child(_room_label)
	_wave_label = Kit.label("", 11, T.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_wave_label.visible = false
	stack.add_child(_wave_label)
	stack.add_child(Kit.separator(T.C_EDGE))
	_score_label = Kit.stat_line(stack, "SCORE", "0", T.C_TEXT)
	_cells_label = Kit.stat_line(stack, "CELLS", "0", T.C_GOLD)
	_best_label = Kit.stat_line(stack, "BEST", "0", T.C_MUTED)


func _build_boss_status() -> void:
	_boss_panel = _hud_strip("BossStatusAnchor", Control.PRESET_TOP_WIDE, 18.0, 96.0)
	var panel := Kit.passive_panel(_boss_panel, T.panel_box(Color("221019e6"), Color("8e3c49"), 10, 1, 8), Vector2(470, 70))
	panel.name = "BossStatus"
	var stack := Kit.padded_stack(panel, 18, 10, 4)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	_boss_name_label = Kit.label("THE EMBER WARDEN", 13, Color("f2c3c6"), HORIZONTAL_ALIGNMENT_LEFT)
	head.add_child(_boss_name_label)
	_boss_value_label = Kit.label("", 12, T.C_RED, HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_boss_value_label)
	var boss_pair := Kit.trailed_bar(Color("b94350"), Color("41131b"), 13.0)
	stack.add_child(boss_pair.holder)
	_boss_bar = boss_pair.bar
	_boss_trail = boss_pair.trail
	# The Warden ignites at this mark, so the fight's midpoint is readable.
	Kit.notch_bar(boss_pair.holder, [Content.BOSS_PHASE2_AT])
	_boss_panel.visible = false


func _build_boss_phase_tag() -> void:
	# Compact phase-2 callout pinned under the boss bar: never center-screen.
	_boss_phase_tag = Kit.label("", 13, Color("f2c3c6"))
	_boss_phase_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_phase_tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_phase_tag.offset_left = -260.0
	_boss_phase_tag.offset_right = 260.0
	_boss_phase_tag.offset_top = 100.0
	_boss_phase_tag.offset_bottom = 124.0
	_boss_phase_tag.visible = false
	add_child(_boss_phase_tag)


func _build_room_clear_banner() -> void:
	_room_clear_banner = _hud_strip("RoomClearBanner", Control.PRESET_TOP_WIDE, ROOM_CLEAR_TOP, ROOM_CLEAR_TOP + 104.0)
	var panel := Kit.passive_panel(_room_clear_banner, T.panel_box(Color("141020eb"), T.C_MINT, 10, 1, 12), Vector2(490, 88))
	var stack := Kit.padded_stack(panel, 24, 10, 1)
	stack.add_child(Kit.label("CHAMBER CLEARED", 22, T.C_MINT))
	_room_clear_name = Kit.label("PATH UNSEALED", 12, T.C_MUTED)
	stack.add_child(_room_clear_name)
	_room_clear_banner.visible = false


## A full-width HUD strip that centres whatever card it holds. With
## PRESET_BOTTOM_WIDE, negative offsets measure up from the bottom edge.
func _hud_strip(node_name: String, preset: Control.LayoutPreset, top: float, bottom: float) -> CenterContainer:
	var center := CenterContainer.new()
	center.name = node_name
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(preset)
	center.offset_top = top
	center.offset_bottom = bottom
	return center


# --- Prompts -----------------------------------------------------------------------

## Repaint every key prompt the HUD shows (see UiInput.PROMPT_GROUP).
func refresh_prompts() -> void:
	_paint_flask_label()
	_paint_special_label()
	if _hint_panel.visible:
		_hint_label.text = UiInput.fill_prompts(_hint_template)


# --- Vitality, Graveflame, flasks --------------------------------------------------

func set_hp(hp: float, max_hp: float) -> void:
	_set_trailed(_hp_bar, _hp_trail, hp, max_hp)
	_hp_value_label.text = "%d / %d" % [roundi(hp), roundi(max_hp)]


## Losses hold as a pale chip for a beat, then drain; gains fill at once.
func _set_trailed(front: ProgressBar, trail: ProgressBar, value: float, maximum: float) -> void:
	front.max_value = maxf(1.0, maximum)
	trail.max_value = front.max_value
	var v := clampf(value, 0.0, front.max_value)
	front.value = v
	Kit.kill_tween(_trail_tweens.get(trail))
	if v >= trail.value or Feedback.motion_reduced:
		trail.value = v
		return
	var tw := Kit.tween(self)
	tw.tween_interval(0.35)
	tw.tween_property(trail, "value", v, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_trail_tweens[trail] = tw


func set_special(value: float, maximum: float) -> void:
	_special_bar.max_value = maxf(1.0, maximum)
	_special_bar.value = clampf(value, 0.0, maximum)
	var was_ready := _ignite_ready()
	_special_shown = Vector2(value, maximum)
	if _ignite_ready() != was_ready:
		_set_ignite_ready(_ignite_ready())
	_paint_special_label()


## Whether the Graveflame on the HUD is full, which is what Ignite spends.
func _ignite_ready() -> bool:
	return _special_shown.x >= _special_shown.y


## A full Graveflame names the Ignite key in gold; otherwise the count.
func _paint_special_label() -> void:
	var lit := _ignite_ready()
	if lit:
		_special_value_label.text = "IGNITE  %s" % UiInput.prompt("ignite")
	else:
		_special_value_label.text = "%d / %d" % [roundi(_special_shown.x), roundi(_special_shown.y)]
	_special_value_label.add_theme_color_override("font_color", T.C_GOLD if lit else T.C_BLUE)


## While Ignite is ready the fill breathes between blue and white-hot, so a
## full bar reads as a prompt; reduced motion holds it white-hot instead.
func _set_ignite_ready(lit: bool) -> void:
	Kit.kill_tween(_ignite_tween)
	var hot := T.C_BLUE.lerp(Color.WHITE, 0.75)
	_special_fill.bg_color = hot if lit else T.C_BLUE
	if not lit or Feedback.motion_reduced:
		return
	_ignite_tween = Kit.tween(self).set_loops()
	_ignite_tween.tween_property(_special_fill, "bg_color", T.C_BLUE, 0.42).set_trans(Tween.TRANS_SINE)
	_ignite_tween.tween_property(_special_fill, "bg_color", hot, 0.42).set_trans(Tween.TRANS_SINE)


## Notch fractions for every Lance's worth of Graveflame below a full bar.
static func _lance_marks(maximum: float) -> Array:
	var marks: Array = []
	var cost := Content.P_SPECIAL_COST
	while cost < maximum - 0.5:
		marks.append(cost / maximum)
		cost += Content.P_SPECIAL_COST
	return marks


func set_flask(charges: int, max_charges: int) -> void:
	var safe_max := maxi(0, max_charges)
	var safe_charges := clampi(charges, 0, safe_max)
	if _flask_sigils.size() != safe_max:
		_rebuild_flask_sigils(safe_max)
	for i in range(_flask_sigils.size()):
		_fill_flask_sigil(_flask_sigils[i], i < safe_charges, i >= _flask_shown.x and i < safe_charges)
	_flask_shown = Vector2i(safe_charges, safe_max)
	_paint_flask_label()


func _paint_flask_label() -> void:
	_flask_count_label.text = "%d / %d  %s" % [_flask_shown.x, _flask_shown.y, UiInput.prompt("heal")]


## One flask sigil per charge on the belt, drawn like the Forge's flask relic.
func _rebuild_flask_sigils(count: int) -> void:
	Kit.clear_children(_flask_container)
	_flask_sigils.clear()
	for i in range(count):
		var sigil := Kit.BoonSigil.new()
		sigil.setup("flask", T.C_MINT, Vector2(16.0, 18.0))
		sigil.pivot_offset = Vector2(8.0, 9.0)
		_flask_container.add_child(sigil)
		_flask_sigils.append(sigil)


## A charged flask glows mint; a spent one is a dim ghost of the glass. A
## charge that has just come back pops, so a refill is noticed mid-fight.
func _fill_flask_sigil(sigil: Control, filled: bool, refilled: bool) -> void:
	sigil.modulate = Color.WHITE if filled else Color(0.32, 0.4, 0.38, 0.55)
	if not refilled or Feedback.motion_reduced:
		return
	sigil.scale = Vector2.ONE * 1.3
	Kit.tween(self).tween_property(sigil, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- Chamber track, score, cells ---------------------------------------------------

## Seven chambers lead down to the throne, which is named rather than counted.
func set_room(idx: int, total: int) -> void:
	var chamber := "CHAMBER %s / %s" % [Kit.roman(idx + 1), Kit.roman(total - 1)]
	_room_label.text = "THE EMBER THRONE" if idx >= total - 1 else chamber


## Waves remaining in the current chamber, so the fight has a visible end.
func set_wave(current: int, total: int) -> void:
	_wave_label.text = "WAVE %d / %d" % [current, total]
	_wave_label.visible = true
	_wave_shown = Vector2i(current, total)


func hide_wave() -> void:
	_wave_label.visible = false
	_wave_shown = Vector2i.ZERO


func set_score(score: int) -> void:
	_score_label.text = Kit.format_number(score)


func set_cells(value: int) -> void:
	_cells_label.text = Kit.format_number(value)


func set_best(value: int) -> void:
	_best_label.text = Kit.format_number(value)


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
## beyond it in that foe's colour. A foe winding up gets a larger arrow that
## throbs (steady under reduced motion); a straggler's is small and still.
class ThreatPips extends Control:
	const INSET := 22.0
	var _pips: Array = []

	func show_pips(pips: Array) -> void:
		if pips.is_empty() and _pips.is_empty():
			return
		_pips = pips
		queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() * 0.001
		for pip in _pips:
			var span := 13.0 if pip.winding else 9.0
			if pip.winding and not Feedback.motion_reduced:
				span *= 1.0 + 0.18 * sin(t * 14.0)
			draw_set_transform(pip.at, float(pip.angle))
			# A notched arrowhead, tip first, pointing along +x.
			var head := PackedVector2Array([
				Vector2(span, 0.0), Vector2(-0.7 * span, -0.75 * span),
				Vector2(-0.35 * span, 0.0), Vector2(-0.7 * span, 0.75 * span),
			])
			var shadow := head.duplicate()
			for i in range(shadow.size()):
				shadow[i] += Vector2(2.0, 3.0).rotated(-float(pip.angle))
			draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.55))
			draw_colored_polygon(head, pip.color)
			head.append(head[0])
			draw_polyline(head, Color("100d18"), 1.5)
		draw_set_transform(Vector2.ZERO)


# --- The Warden --------------------------------------------------------------------

func show_boss_bar(max_hp: float) -> void:
	_boss_panel.visible = true
	_boss_bar.max_value = maxf(1.0, max_hp)
	_boss_bar.value = max_hp
	_boss_trail.max_value = _boss_bar.max_value
	_boss_trail.value = max_hp
	_boss_value_label.text = str(roundi(max_hp))
	_set_boss_ignited(false)


func update_boss_bar(hp: float) -> void:
	if not is_equal_approx(hp, _boss_bar.value):
		_set_trailed(_boss_bar, _boss_trail, hp, _boss_bar.max_value)
	_boss_value_label.text = str(maxi(0, roundi(hp)))
	if not _boss_ignited and hp <= _boss_bar.max_value * Content.BOSS_PHASE2_AT:
		_set_boss_ignited(true)


## Past the phase notch the Warden burns: its bar and name take the ember.
func _set_boss_ignited(on: bool) -> void:
	_boss_ignited = on
	_boss_bar.add_theme_stylebox_override("fill", T.bar_box(T.C_EMBER if on else Color("b94350")))
	_boss_name_label.text = "THE EMBER WARDEN  ·  IGNITED" if on else "THE EMBER WARDEN"
	_boss_name_label.add_theme_color_override("font_color", T.C_EMBER_HI if on else Color("f2c3c6"))


func hide_boss_bar() -> void:
	_boss_panel.visible = false


## Phase-2 callout: a small tag under the boss bar that fades on its own.
func flash_boss_phase(text: String, hold: float = 1.7) -> void:
	_boss_phase_tag.text = text
	_boss_phase_tween = Kit.flash_card(_boss_phase_tag, _boss_phase_tween, 0.18, hold, 0.5)


func show_boss_intro(boss_name: String, subtitle: String, hold: float = 2.4) -> void:
	# The boss card owns the screen: drop any chamber card still fading out,
	# and any lesson in the low strip it now covers.
	_hide_banner(_room_intro)
	hide_hint()
	_play_banner(_boss_intro, boss_name.to_upper(), subtitle.to_upper(), hold)


# --- Streak ------------------------------------------------------------------------

func set_streak(kills: int, frac: float, mult: float) -> void:
	if _streak_panel == null:
		return
	if kills < 2:
		hide_streak()
		return
	_streak_panel.visible = true
	_streak_kills_label.text = "%d KILLS" % kills
	_streak_mult_label.text = "x" + String.num(mult, 2)
	_streak_bar.value = clampf(frac, 0.0, 1.0) * 100.0
	var tier := Content.streak_tier(kills)
	var col: Color = T.STREAK_TIER_COLORS[clampi(tier, 0, T.STREAK_TIER_COLORS.size() - 1)]
	_streak_mult_label.add_theme_color_override("font_color", col)
	_streak_bar.add_theme_stylebox_override("fill", T.bar_box(col))
	if tier > _streak_tier and not Feedback.motion_reduced:
		Kit.kill_tween(_streak_tween)
		_streak_panel.scale = Vector2(1.12, 1.12)
		_streak_tween = Kit.tween(self)
		_streak_tween.tween_property(_streak_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tier = tier


## The streak timer drains every frame; everything else changes only on a kill.
func set_streak_fraction(frac: float) -> void:
	_streak_bar.value = clampf(frac, 0.0, 1.0) * 100.0


func hide_streak() -> void:
	if _streak_panel != null:
		_streak_panel.visible = false
		_streak_panel.scale = Vector2.ONE
	_streak_tier = 0


# --- Chamber cards and lessons -----------------------------------------------------

func show_room_intro(idx: int, total: int, room_name: String, trial: bool = false) -> void:
	var sub := "CHAMBER %s OF %s" % [Kit.roman(idx + 1), Kit.roman(total - 1)]
	if trial:
		sub += "  ·  TRIAL"
	_play_banner(_room_intro, room_name.to_upper(), sub, 1.5)


## The clear card lands, holds, then steps aside into a small chip in the top
## slot, so it no longer hangs over the walk to the rifts.
func show_room_clear(room_name: String) -> void:
	hide_room_clear()
	_hide_banner(_room_intro)
	_room_clear_name.text = room_name.to_upper() if not room_name.strip_edges().is_empty() else "PATH UNSEALED"
	_room_clear_banner.visible = true
	_room_clear_banner.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_room_clear_banner.pivot_offset = Vector2(_room_clear_banner.size.x * 0.5, 0.0)
	var settle := 0.0 if Feedback.motion_reduced else 0.35
	_room_clear_tween = Kit.tween(self)
	_room_clear_tween.tween_property(_room_clear_banner, "modulate", Color.WHITE, 0.16)
	_room_clear_tween.tween_interval(1.4)
	_room_clear_tween.tween_callback(_room_clear_to_chip)
	_room_clear_tween.tween_property(_room_clear_banner, "scale", Vector2.ONE * 0.7, settle).set_trans(Tween.TRANS_SINE)
	_room_clear_tween.parallel().tween_property(_room_clear_banner, "position:y", 12.0, settle).set_trans(Tween.TRANS_SINE)


## The chip says what to do next, set larger so it stays legible once shrunk.
func _room_clear_to_chip() -> void:
	_room_clear_name.text = "PATH UNSEALED  ·  CHOOSE A RIFT"
	_room_clear_name.add_theme_font_size_override("font_size", 16)


func hide_room_clear() -> void:
	if _room_clear_banner != null:
		Kit.kill_tween(_room_clear_tween)
		_room_clear_banner.visible = false
		_room_clear_banner.modulate = Color.WHITE
		_room_clear_banner.scale = Vector2.ONE
		_room_clear_banner.position.y = ROOM_CLEAR_TOP
		_room_clear_name.add_theme_font_size_override("font_size", 12)


## Show a one-time lesson. Re-showing replaces the current one rather than
## stacking, so two triggers in the same second cannot queue up noise. The
## lesson's {action} tokens become the player's live keys.
func show_hint(text: String, hold: float = 4.5) -> void:
	if _hint_panel == null:
		return
	_hint_template = text
	_hint_label.text = UiInput.fill_prompts(text)
	_hint_tween = Kit.flash_card(_hint_panel, _hint_tween, 0.25, hold, 0.5)


func hide_hint() -> void:
	Kit.kill_tween(_hint_tween)
	if _hint_panel != null:
		_hint_panel.visible = false


func hide_banners() -> void:
	_threat_pips.show_pips([])
	Kit.kill_tween(_boss_phase_tween)
	if _boss_phase_tag != null:
		_boss_phase_tag.visible = false
	hide_hint()
	for banner in [_room_intro, _boss_intro]:
		_hide_banner(banner)
