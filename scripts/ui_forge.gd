extends "res://scripts/ui_screen.gd"
## THE FORGE, between lives: two pages of one ledger. RELICS are tempered
## with cells carried out of the keep, rank by rank; VOWS are burdens sworn
## for free once the Warden has fallen, each paying in renown and cells, and
## sealed in wax when sworn. The roll of every descent is read at the foot.

## Every row of both pages (the suites read them here).
var rows: VBoxContainer
var _tabs: Kit.Tabs
var _relics: VBoxContainer
var _vows: VBoxContainer
var _balance: Label
var _roll: Label
## The accept prompt's word, which names what the open page does.
var _accept_word: Label
var _cells := 0


func build() -> void:
	veil(0.62, 0.94, T.EMBER)
	var column := sheet(Vector2(860, 640), T.EMBER, T.S7, T.S6)
	var head := HBoxContainer.new()
	column.add_child(head)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", T.S1)
	head.add_child(words)
	heading(words, "BETWEEN LIVES", "The Forge")
	var purse := HBoxContainer.new()
	purse.add_theme_constant_override("separation", T.S2)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(purse)
	purse.add_child(_cell_mark())
	_balance = Kit.label("0", T.TITLE, T.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_balance.size_flags_horizontal = Control.SIZE_SHRINK_END
	purse.add_child(_balance)
	set_meta("balance_label", _balance)

	_tabs = Kit.tabs(["RELICS", "VOWS"])
	_tabs.tab_changed.connect(_turn_to)
	column.add_child(_tabs)
	set_meta("tabs", _tabs)
	column.add_child(Kit.separator(T.HAIRLINE))
	rows = Kit.scroll_list(column, 330.0, T.S1)
	rows.name = "ForgeRows"
	_relics = VBoxContainer.new()
	_vows = VBoxContainer.new()
	for page: VBoxContainer in [_relics, _vows]:
		page.add_theme_constant_override("separation", T.S1)
		rows.add_child(page)

	column.add_child(Kit.ornament(T.GOLD))
	_roll = Kit.label("", T.VOICE, T.ASH)
	_roll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label with no width yet would ask for a tower of one-word lines.
	_roll.custom_minimum_size.x = 760.0
	column.add_child(_roll)
	var bar := footer(column, [
		["ui_accept", "Temper"],
		[[UiInput.TAB_PREV, UiInput.TAB_NEXT], "Turn the page"],
		["ui_cancel", "Back", "back", ui.back_from_forge_requested.emit],
	], "back")
	_accept_word = bar.get_child(0).find_children("*", "Label", true, false)[0]


## A cell, the forge's coin: a gold hex.
static func _cell_mark() -> Control:
	var mark := Kit.pips(1, 1, "cell", T.GOLD)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return mark


## Rebuild both pages for a purse of `cells`. A purchase or a vow rebuilds
## every row under the cursor: it stays on the row it was on, so a second
## press can never temper a relic the knight did not choose.
func setup(cells: int) -> void:
	_cells = cells
	_balance.text = Kit.format_number(cells)
	var kept := Kit.focused_name_in(rows)
	Kit.clear_children(_relics)
	for i in range(Content.META_UPGRADES.size()):
		_relics.add_child(_relic_row(i, Content.META_UPGRADES[i]))
	Kit.clear_children(_vows)
	_fill_vows()
	_roll.text = UiScreens.roll_line(Save.load_save())
	_turn_to(_tabs.current)
	if not kept.is_empty():
		(func() -> void: Kit.focus_row(rows, kept, _tabs.get_child(0))).call_deferred()


## A relic: its sigil, name and effect, the ranks tempered, and the price of
## the next rank in cells, or TEMPERED once there is none.
func _relic_row(i: int, relic: Dictionary) -> Button:
	var id := str(relic.id)
	var rank := Save.get_meta_rank(id)
	var cost := Content.meta_next_cost(relic, rank)
	var sigil := Kit.BoonSigil.new()
	sigil.setup(id, T.GOLD if rank > 0 else T.EMBER_HI, Vector2(40, 40))
	var trailing := HBoxContainer.new()
	trailing.add_theme_constant_override("separation", T.S5)
	var pips_box := HBoxContainer.new()
	pips_box.alignment = BoxContainer.ALIGNMENT_END
	pips_box.custom_minimum_size.x = 84.0
	pips_box.add_child(Kit.rank_pips(rank, Content.meta_max_rank(relic)))
	trailing.add_child(pips_box)
	var price := HBoxContainer.new()
	price.alignment = BoxContainer.ALIGNMENT_END
	price.add_theme_constant_override("separation", T.S2)
	price.custom_minimum_size.x = 104.0
	trailing.add_child(price)
	if cost < 0:
		price.add_child(Kit.label("TEMPERED", T.CAPS, T.VERDIGRIS, HORIZONTAL_ALIGNMENT_RIGHT))
	else:
		# Gold while the purse can pay, ash while it cannot.
		price.add_child(Kit.label(str(cost), T.NUMERAL, T.GOLD if _cells >= cost else T.SOOT, HORIZONTAL_ALIGNMENT_RIGHT))
		price.add_child(_cell_mark())
	var row := Kit.row("Buy%d" % i, str(relic.title).to_upper(), str(relic.desc), trailing, sigil, 58.0)
	row.pressed.connect(_temper.bind(i, cost))
	return row


## Temper a relic the purse can pay for; anything else only knocks.
func _temper(i: int, cost: int) -> void:
	if cost < 0 or _cells < cost:
		ui.cue.emit("ui_back")
		return
	ui.buy_meta_requested.emit(i)


## The vows page: what they cost and pay, then a row per vow, sealed in wax
## when sworn and marked KEPT once carried through a won descent. Before the
## Warden has fallen the page holds only a promise.
func _fill_vows() -> void:
	if not Save.vows_unlocked():
		var hush := Kit.label("Fell the Warden, and the vows will listen.", T.VOICE, T.ASH)
		hush.custom_minimum_size.y = 120.0
		_vows.add_child(hush)
		return
	var sworn := Save.get_vows()
	var kept: Array = Save.load_save().get("vows_kept_ever", [])
	var head := HBoxContainer.new()
	head.custom_minimum_size.y = 34.0
	_vows.add_child(head)
	head.add_child(Kit.label("A vow makes the keep harsher, and pays for it.", T.SMALL, T.ASH, HORIZONTAL_ALIGNMENT_LEFT))
	var worth := Kit.label("RENOWN ×%.2f" % Content.vow_score_multiplier(sworn), T.CAPS, T.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	worth.size_flags_horizontal = Control.SIZE_SHRINK_END
	head.add_child(worth)
	for i in range(Content.VOWS.size()):
		var vow: Dictionary = Content.VOWS[i]
		var on := sworn.has(str(vow.id))
		var trailing := HBoxContainer.new()
		trailing.add_theme_constant_override("separation", T.S4)
		if kept.has(str(vow.id)):
			trailing.add_child(Kit.kept_seal())
		var word := Kit.label("SWORN" if on else "SWEAR", T.CAPS, T.WAX_HI if on else T.ASH, HORIZONTAL_ALIGNMENT_RIGHT)
		word.custom_minimum_size.x = 64.0
		trailing.add_child(word)
		var caption := "%s   +%d%% renown" % [str(vow.desc), roundi(float(vow.score) * 100.0)]
		var row := Kit.row("Vow%d" % i, str(vow.title).to_upper(), caption, trailing, Kit.seal(36.0, T.WAX, "flame", on), 56.0)
		row.pressed.connect(ui.vow_toggled.emit.bind(str(vow.id)))
		_vows.add_child(row)


## Open page `index` and name what pressing does there. Focus left on the
## page now hidden follows to the new page's first row.
func _turn_to(index: int) -> void:
	_relics.visible = index == 0
	_vows.visible = index == 1
	_accept_word.text = "Temper" if index == 0 else "Swear"
	var owner := get_viewport().gui_get_focus_owner()
	if visible and (owner == null or not owner.is_visible_in_tree()):
		Kit.focus_row(_relics if index == 0 else _vows, "", _tabs.get_child(index))


## Opened: the open page's first row focused. Deferred like every page's first
## focus, so the page opened last wins.
func opened(_from: String) -> void:
	var page := _relics if _tabs.current == 0 else _vows
	(func() -> void: Kit.focus_row(page, "", _tabs.get_child(_tabs.current))).call_deferred()
	settle()
