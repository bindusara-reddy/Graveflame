extends "res://scripts/ui_screen.gd"
## THE KEEP WAITS: the pause, a torn ledger page laid down on the left of the
## held chamber. A quiet column of what the knight can do (rise, the senses,
## back to the landing) beside the ledger of this descent: a medallion per
## boon carried, the relics as framed sigils, the vows as wax seals, and the
## seed printed small like a folio number. Every mark in the ledger can take
## focus and reads itself aloud underneath, so a pad reads it as a mouse does.

const LINE := "Catch your breath. Nothing below will move."
const EMPTY := "No boons yet. The first chamber waits."

## TO THE LANDING, which asks before it abandons the descent.
var quit_button: Button
## The boon medallions (only boons: the suites count them).
var boons: GridContainer
## The readout under the ledger, written by whichever mark holds focus.
var detail: Label
var seed_label: Label
var _kicker: Label
var _relics: HBoxContainer
var _vows: HBoxContainer
var _vows_line: Control


func build() -> void:
	veil(0.72, 0.88, T.SPIRIT)
	var column := sheet(Vector2(740, 0), T.SPIRIT, T.S7, T.S6)
	# The sheet lies on the left of the frame; the held chamber stays in
	# view on the right.
	frame.anchor_right = 0.7
	frame.offset_left = T.S7
	frame.offset_right = -T.S5
	_kicker = heading(column, "", "The Keep Waits", T.SPIRIT)
	column.add_child(Kit.label(LINE, T.VOICE, T.ASH, HORIZONTAL_ALIGNMENT_LEFT))
	gap(column, T.S1)
	column.add_child(Kit.ornament(T.GOLD))
	gap(column, T.S1)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", T.S5)
	column.add_child(body)
	body.add_child(_actions())
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(1.0, 0.0)
	rule.color = Color(T.HAIRLINE, 0.7)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rule)
	body.add_child(_ledger())

	gap(column, T.S2)
	var foot := HBoxContainer.new()
	column.add_child(foot)
	footer(foot, [["pause", "Rise", "rise_prompt", ui.resume_requested.emit]])
	spring(foot)
	seed_label = Kit.label("", T.MICRO, T.SOOT, HORIZONTAL_ALIGNMENT_RIGHT)
	seed_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	foot.add_child(seed_label)
	set_descent({}, 0)


## RISE on ember paper, then two quiet words: one bright thing per region.
func _actions() -> VBoxContainer:
	var actions := VBoxContainer.new()
	# Wide enough for ABANDON THE DESCENT?, so asking never shifts the ledger.
	actions.custom_minimum_size.x = 272.0
	actions.add_theme_constant_override("separation", T.S1)
	var rise := Kit.button("RISE", "resume", Kit.PRIMARY, Vector2(220, 52))
	rise.pressed.connect(ui.resume_requested.emit)
	var senses := Kit.button("SENSES", "pause_options", Kit.QUIET, Vector2(220, 44))
	senses.pressed.connect(ui.options_requested.emit)
	quit_button = Kit.button("TO THE LANDING", "quit", Kit.QUIET, Vector2(220, 44), "")
	confirm_twice(quit_button, "ABANDON THE DESCENT?", Kit.QUIET, ui.quit_to_title_requested.emit)
	for button: Button in [rise, senses, quit_button]:
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		actions.add_child(button)
	return actions


func _ledger() -> VBoxContainer:
	var ledger := VBoxContainer.new()
	ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ledger.add_theme_constant_override("separation", T.S2)
	ledger.add_child(Kit.label("THIS DESCENT", T.CAPS, T.EMBER_HI, HORIZONTAL_ALIGNMENT_LEFT))
	# Headroom for the flame that stands over a focused medallion.
	gap(ledger, T.S3)
	boons = GridContainer.new()
	boons.columns = 6
	boons.add_theme_constant_override("h_separation", T.S2)
	boons.add_theme_constant_override("v_separation", T.S3)
	ledger.add_child(boons)
	detail = Kit.label("", T.SMALL, T.BONE, HORIZONTAL_ALIGNMENT_LEFT)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(380.0, 40.0)
	ledger.add_child(detail)
	_relics = _mark_line(ledger, "RELICS")
	_vows = _mark_line(ledger, "VOWS")
	_vows_line = _vows.get_parent()
	return ledger


## A captioned line of marks (relic sigils, vow seals). Returns the marks' row.
func _mark_line(ledger: VBoxContainer, caption: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", T.S3)
	ledger.add_child(line)
	var head := Kit.label(caption, T.MICRO, T.ASH, HORIZONTAL_ALIGNMENT_LEFT)
	head.custom_minimum_size.x = 56.0
	head.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.add_child(head)
	var marks := HBoxContainer.new()
	marks.add_theme_constant_override("separation", T.S2)
	line.add_child(marks)
	return marks


## Fill the ledger: a medallion per boon carried (with its stack count), the
## relics owned, the vows sworn, the seed, and the chamber as `chamber`
## ({ index, total, name }) names it. Called as the pause opens, so it
## always shows the descent as it stands.
func set_descent(taken: Dictionary, seed_value: int, chamber: Dictionary = {}) -> void:
	_kicker.text = _chamber_line(chamber)
	Kit.clear_children(boons)
	for u: Dictionary in Content.UPGRADES:
		if taken.has(u.id):
			boons.add_child(_boon_tile(u, int(taken[u.id])))
	detail.text = EMPTY if taken.is_empty() else "Choose a mark to read it."
	Kit.clear_children(_relics)
	for u: Dictionary in Content.META_UPGRADES:
		var rank := Save.get_meta_rank(str(u.id))
		if rank > 0:
			var sigil := Kit.BoonSigil.new()
			sigil.setup(str(u.id), T.GOLD, Vector2(34, 34))
			var line := "%s %s  —  %s" % [str(u.title).to_upper(), Kit.roman(rank), str(u.desc)]
			_relics.add_child(_tile("Relic_%s" % u.id, sigil, Kit.roman(rank), line, 44.0))
	if _relics.get_child_count() == 0:
		_relics.add_child(Kit.label("None tempered yet.", T.SMALL, T.SOOT, HORIZONTAL_ALIGNMENT_LEFT))
	Kit.clear_children(_vows)
	if Save.vows_unlocked():
		for v: Dictionary in Content.VOWS:
			if Save.get_vows().has(v.id):
				var line := "%s  —  %s" % [str(v.title).to_upper(), str(v.desc)]
				_vows.add_child(_tile("Vow_%s" % v.id, Kit.seal(30.0, T.WAX, "flame"), "", line, 40.0))
	_vows_line.visible = _vows.get_child_count() > 0
	seed_label.text = "SEED  %d" % seed_value if seed_value != 0 else ""


## "CHAMBER IV OF VII  ·  ASHEN CELLS", or the throne by its name.
static func _chamber_line(chamber: Dictionary) -> String:
	if chamber.is_empty():
		return "THE DESCENT, HELD"
	var index := int(chamber.get("index", 0))
	var total := int(chamber.get("total", 0))
	if index >= total - 1:
		return "THE EMBER THRONE"
	return "CHAMBER %s OF %s  ·  %s" % [Kit.roman(index + 1), Kit.roman(total - 1), str(chamber.get("name", "")).to_upper()]


## One boon: its medallion, with a ×N badge for stacks.
func _boon_tile(u: Dictionary, count: int) -> Button:
	var rarity := Content.upgrade_rarity(u)
	var medallion := Kit.BoonMedallion.new()
	medallion.setup(str(u.id), Content.rarity_color(rarity), rarity == "epic", Vector2(48, 48))
	var stack := "  ×%d" % count if count > 1 else ""
	var line := "%s%s  —  %s" % [str(u.title).to_upper(), stack, str(u.desc)]
	return _tile("Taken_%s" % u.id, medallion, "×%d" % count if count > 1 else "", line, 52.0)


## A mark on the ledger holding `emblem`: paper lifts under it with focus, and
## focusing (or hovering) it writes `line` into the readout.
func _tile(node_name: String, emblem: Control, badge: String, line: String, side: float) -> Button:
	var tile := Kit.PaperButton.new()
	tile.name = node_name
	tile.custom_minimum_size = Vector2(side, side)
	tile.focus_mode = Control.FOCUS_ALL
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.set_meta("flame_at", "top")
	var paper := T.button_styles(Kit.QUIET)
	tile.set_paper(StyleBoxEmpty.new(), paper.raised, paper.pressed, StyleBoxEmpty.new())
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(emblem)
	if not badge.is_empty():
		var mark := Kit.outlined(Kit.label(badge, T.SMALL, T.GOLD, HORIZONTAL_ALIGNMENT_RIGHT), 4)
		tile.add_child(mark)
		mark.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, -2)
		mark.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		mark.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tile.focus_entered.connect(func() -> void: detail.text = line)
	return tile
