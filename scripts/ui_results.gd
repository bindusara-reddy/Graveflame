extends "res://scripts/ui_screen.gd"
## How a descent ended, as a ledger the keep keeps. One page, two stones:
##   the grave ("gameover"): an arched grave sheet to the right of the fallen
##     knight, who stays in view under a thin veil. The epitaph, how many
##     flames the Warden now holds, and the tally.
##   the crown ("victory"): a clean-cut sheet under a gold wax seal pressed
##     with the crown. Which flame this was and how the throne was left, the
##     last word, the tally, and on a first win a slip: the vows awaken.
## The tally's numbers roll up as the sheet settles; DESCEND AGAIN and TO THE
## LANDING arm only once the page has been read.

const P := preload("res://scripts/ui_paint.gd")
## How the throne was left, as the crown's kicker names it (Save.get_last_ending()).
const ENDINGS := {
	"": ["WARDEN DEFEATED", T.VERDIGRIS],
	"crown": ["THE CROWN IS TAKEN", T.WARDEN],
	"given": ["THE FLAMES ARE GIVEN BACK", T.GOLD],
	"ended": ["THE THRONE IS BROKEN", T.DAWN],
}
## The tally: [key, caption] in reading order, down the left column then the right.
const TALLY := [
	["time", "HOURS BELOW"], ["kills", "FELLED"], ["elites", "CHAMPIONS"],
	["streak", "HIGHEST FURY"], ["damage", "WOUNDS DEALT"], ["rooms", "CHAMBERS"],
]

var _crown := false
## key -> [value label, target number, how the number is written].
var _figures := {}
var _hoard: Label
var _vows_kept: Control
var _vows_slip: Control


func build() -> void:
	_crown = panel_id == "victory"
	var accent := T.GOLD if _crown else T.BLOOD
	# Over the grave the veil stays thin: the fallen knight is part of the page.
	veil(0.72 if _crown else 0.4, 0.88 if _crown else 0.5, accent)
	var column := sheet(Vector2(600, 0) if _crown else Vector2(520, 650), accent, T.S7 - 4, T.S6)
	var paper := get_meta("dialog") as PanelContainer
	if _crown:
		_press_crest(paper)
	else:
		_cut_grave(paper)
		# To the right of the fallen knight, who lies near the frame's centre.
		frame.anchor_left = 0.5

	var kicker := Kit.label(ENDINGS[""][0] if _crown else "THE KNIGHT FALLS", T.CAPS, ENDINGS[""][1] if _crown else T.BLOOD)
	column.add_child(kicker)
	set_meta("kicker_label", kicker)
	column.add_child(Kit.label("The Graveflame Endures" if _crown else "The Flame Fades", T.TITLE, T.BONE))
	var line := Kit.label("", T.VOICE, T.ASH)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(line)
	set_meta("line_label", line)
	if not _crown:
		_hoard = Kit.label("", T.VOICE, T.GOLD)
		column.add_child(_hoard)
	column.add_child(Kit.ornament(accent))
	_ledger(column)
	if _crown:
		_vows_slip = _vows_awaken(column)
	# Spare room on the grave pools above the choices, which stand at its foot.
	gap(column, T.S2).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var actions := Kit.button_row(column)
	var again := Kit.button("DESCEND AGAIN", "again" if _crown else "restart", Kit.PRIMARY, Vector2(208, 52))
	again.pressed.connect(ui.restart_requested.emit)
	actions.add_child(again)
	var landing := Kit.button("TO THE LANDING", "title", Kit.SECONDARY, Vector2(208, 52))
	landing.pressed.connect(ui.quit_to_title_requested.emit)
	actions.add_child(landing)
	set_meta("buttons", [again, landing])


## The tally: renown large and alone, the standing height under it, the
## cells carried out (and vows kept), then six figures in two columns.
func _ledger(column: VBoxContainer) -> void:
	var renown := Kit.stat("RENOWN", "0")
	(renown.get_meta("value") as Label).add_theme_font_size_override("font_size", 30)
	column.add_child(renown)
	_figure("score", renown, 0.0, Kit.format_number)
	var best := Kit.label("", T.MICRO, T.ASH, HORIZONTAL_ALIGNMENT_RIGHT)
	column.add_child(best)
	set_meta("best_label", best)
	var cells := Kit.stat("CELLS CARRIED OUT", "+0", T.GOLD)
	column.add_child(cells)
	set_meta("cells_label", cells.get_meta("value"))
	_figure("cells", cells, 0.0, func(v: float) -> String: return "+" + Kit.format_number(roundi(v)))
	_vows_kept = Kit.stat("VOWS KEPT", "0", T.WAX_HI)
	_vows_kept.visible = false
	column.add_child(_vows_kept)
	_figure("vows", _vows_kept, 0.0, func(v: float) -> String: return str(roundi(v)))
	gap(column, T.S1)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", T.S5)
	column.add_child(split)
	var labels := {}
	for half in [TALLY.slice(0, 3), TALLY.slice(3)]:
		var side := VBoxContainer.new()
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.add_theme_constant_override("separation", T.S1)
		split.add_child(side)
		for entry: Array in half:
			var line := Kit.stat(str(entry[1]), "-")
			side.add_child(line)
			labels[entry[0]] = line.get_meta("value")
	set_meta("summary_labels", labels)


## Remember the figure `key` shows in `line`'s value, to roll up when read.
func _figure(key: String, line: Control, to: float, shown: Callable) -> void:
	_figures[key] = [line.get_meta("value") as Label, to, shown]


## The grave: an arch-topped sheet torn at its foot, a printed arch inside it,
## and a wax seal pressed at the apex.
func _cut_grave(paper: PanelContainer) -> void:
	var stone := T.sheet_style(T.BLOOD.darkened(0.35), 7).with({
		"shape": T.PaperStyle.Shape.ARCH, "rule": Color(0, 0, 0, 0), "fibres": 0.0, "deckle_sides": P.BOTTOM,
	})
	paper.add_theme_stylebox_override("panel", stone)
	var inner := ArchRule.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(inner)
	paper.move_child(inner, 0)
	var margin := paper.get_child(1) as MarginContainer
	margin.add_theme_constant_override("margin_top", 34)
	var column := margin.get_child(0) as VBoxContainer
	var apex := Kit.seal(46.0, T.WAX, "flame")
	apex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(apex)


## The crown: a gold wax seal pressed over the sheet's top edge, half on the
## paper and half above it.
func _press_crest(paper: PanelContainer) -> void:
	var crest := Control.new()
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(crest)
	var seal := Kit.seal(68.0, T.GOLD.darkened(0.3), "crown")
	crest.add_child(seal)
	crest.resized.connect(func() -> void: seal.position = Vector2(crest.size.x * 0.5 - 34.0, -30.0))
	var margin := paper.get_child(0) as MarginContainer
	margin.add_theme_constant_override("margin_top", 52)


## A first win's slip: the vows have woken in the Forge.
func _vows_awaken(column: VBoxContainer) -> Control:
	var slip := Kit.sheet(column, "slip", T.GOLD)
	slip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", T.S3)
	slip.add_child(line)
	line.add_child(Kit.seal(22.0, T.GOLD.darkened(0.35), "flame"))
	var words := Kit.label("The vows awaken at the Forge.", T.BODY, T.BONE, HORIZONTAL_ALIGNMENT_LEFT)
	line.add_child(words)
	set_meta("vows_label", words)
	slip.visible = false
	words.visible = false
	return slip


## The crown's kicker names which flame this was and how the throne was left;
## on the first win the slip points to the vows.
func set_extras(ordinal: String, first: bool) -> void:
	var save_api: Script = Save
	var ending := str(save_api.call("get_last_ending")) if save_api.has_method("get_last_ending") else ""
	var said: Array = ENDINGS.get(ending, ENDINGS[""])
	var kicker := get_meta("kicker_label") as Label
	kicker.text = str(said[0]) + ("  ·  " + ordinal if ordinal != "" else "")
	kicker.add_theme_color_override("font_color", said[1])
	(get_meta("vows_label") as Label).visible = first
	_vows_slip.visible = first


func show_cells(cells: int, vows_kept: int) -> void:
	_figures.cells[1] = float(cells)
	_figures.vows[1] = float(vows_kept)
	_vows_kept.visible = vows_kept > 0
	_write_figures(false)


## Take the descent's figures. The panel is reused between descents, so every
## label is set every time: a past record's gold must not linger.
func show_summary(stats: Dictionary) -> void:
	var line := get_meta("line_label") as Label
	var said := str(stats.get("line", ""))
	# The grave's line is carved as a quote; the crown's is the keep's own.
	line.text = said if _crown or said.is_empty() else "“%s”" % said
	line.visible = not said.is_empty()
	if _hoard != null:
		_hoard.text = str(stats.get("hoard_line", ""))
		_hoard.visible = not _hoard.text.is_empty()
	var best := get_meta("best_label") as Label
	var record := bool(stats.get("new_best", false))
	best.text = "A NEW HEIGHT" if record else "HIGHEST RENOWN  %s" % Kit.format_number(int(stats.get("best", 0)))
	best.add_theme_color_override("font_color", T.GOLD if record else T.ASH)
	var rooms_total := int(stats.get("rooms_total", 0))
	_figures.score[1] = float(stats.get("score", 0))
	var labels: Dictionary = get_meta("summary_labels")
	var targets := {
		"time": [float(stats.get("time", 0.0)), func(v: float) -> String: return "%d:%02d" % [int(v) / 60, int(v) % 60]],
		"kills": [float(stats.get("kills", 0)), func(v: float) -> String: return Kit.format_number(roundi(v))],
		"elites": [float(stats.get("elites", 0)), func(v: float) -> String: return Kit.format_number(roundi(v))],
		"streak": [float(stats.get("best_streak", 0)), func(v: float) -> String: return "×%d" % roundi(v)],
		"damage": [float(stats.get("damage_dealt", 0.0)), func(v: float) -> String: return Kit.format_number(roundi(v))],
		"rooms": [float(stats.get("rooms", 0)), func(v: float) -> String: return "%d / %d" % [roundi(v), rooms_total]],
	}
	for key: String in targets:
		_figures[key] = [labels[key], targets[key][0], targets[key][1]]
	_write_figures(visible)


## Write every figure: rolled up from nothing when `roll`, else at once.
func _write_figures(roll: bool) -> void:
	var order := ["score", "cells", "vows", "time", "kills", "elites", "streak", "damage", "rooms"]
	for i in range(order.size()):
		var figure: Array = _figures.get(order[i], [])
		if figure.is_empty():
			continue
		var value_label: Label = figure[0]
		if roll:
			Kit.roll_number(value_label, figure[1], figure[2], 0.25 + 0.07 * float(i))
		else:
			value_label.text = figure[2].call(figure[1])


## Opened: the sheet settles, the tally rolls up, and the choices arm once the
## page has been read (the crown's are held by lock_until_released instead).
func opened(_from: String) -> void:
	settle()
	_write_figures(true)
	var buttons: Array = get_meta("buttons")
	if not _crown:
		stage.arm_buttons(buttons, 0.9, buttons[0])
		return
	var again: Button = buttons[0]
	(func() -> void:
		if again.focus_mode != Control.FOCUS_NONE and not again.disabled:
			again.grab_focus()
	).call_deferred()


## The printed arch inside the grave sheet, with lozenges at its foot.
class ArchRule extends Control:
	func _init() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var inner := Rect2(Vector2.ZERO, size).grow(-11.0)
		if inner.size.x <= 0.0 or inner.size.y <= 0.0:
			return
		var arch := UiPaint.arch_rect(inner, 8.0)
		UiPaint.stroke(get_canvas_item(), arch, Color(UiTheme.GOLD, 0.22), 1.0)
		for corner in [Vector2(inner.position.x, inner.end.y), inner.end]:
			UiPaint.lozenge(get_canvas_item(), corner, 3.0, Color(UiTheme.GOLD, 0.22))
