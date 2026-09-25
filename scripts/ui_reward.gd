extends "res://scripts/ui_screen.gd"
## THE FLAME OFFERS: the boons a cleared chamber deals, laid on the dimmed
## chamber floor like cards on a table, with no sheet around them so the
## choice is the only thing on screen. Rarity reads from the printed band,
## the medallion ring and the foot line, never colour alone. The number on
## each card is a live key; the deal arms only once it has landed and every
## key mashed through the rift has been let go.

const GAP := 26.0

## The dealt cards.
var row: HBoxContainer
var _numbers: HBoxContainer


func build() -> void:
	veil(0.72, 0.88, T.GOLD)
	var column := Kit.dialog(self, Vector2(1000, 0), T.GOLD, T.S3, T.S2)
	(get_meta("dialog") as PanelContainer).add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	frame = (get_meta("dialog") as Control).get_parent()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", T.S1)
	column.add_child(Kit.label("THE WAY OPENS", T.CAPS, T.VERDIGRIS))
	column.add_child(Kit.label("The Flame Offers", T.TITLE, T.BONE))
	column.add_child(Kit.label("Every chamber feeds the flame.", T.VOICE, T.ASH))
	column.add_child(Kit.ornament(T.GOLD))
	gap(column, T.S3)
	row = HBoxContainer.new()
	row.name = "UpgradeChoices"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(GAP))
	column.add_child(row)
	gap(column, T.S5)
	var bar := footer(column, [["ui_accept", "Take"]])
	# The number keys lead the bar while the keyboard is in hand.
	_numbers = HBoxContainer.new()
	_numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_numbers.add_theme_constant_override("separation", T.S1 + 2)
	bar.add_child(_numbers)
	bar.move_child(_numbers, 0)


## Deal `upgrades` face up. Three cards keep the full width; the Seer's Eye
## fourth narrows them all so the row still fits the frame.
func deal(upgrades: Array) -> void:
	Kit.clear_children(row)
	Kit.clear_children(_numbers)
	var buttons: Array = []
	var count := upgrades.size()
	var width := minf(292.0, (1180.0 - GAP * float(count - 1)) / float(maxi(1, count)))
	for i in range(count):
		var card := _card(i, upgrades[i], width)
		card.pressed.connect(ui.upgrade_selected.emit.bind(i))
		row.add_child(card)
		buttons.append(card)
		var cap := Kit.glyph_for(str(i + 1), "key")
		cap.key_only = true
		_numbers.add_child(cap)
	set_meta("buttons", buttons)
	_deal_in(buttons)
	# The cards arm once the deal has landed, so a jump pressed on the way
	# through the rift cannot take a boon unread.
	if not buttons.is_empty():
		stage.arm_buttons(buttons, 0.35 if T.still() else 0.36 + 0.08 * float(count - 1), buttons[0])


## One boon: the kit's dealt card around the boon's medallion. Resting
## cards fan a little; the chosen one turns square and lifts toward the hand.
func _card(i: int, upgrade: Dictionary, width: float) -> Button:
	var rarity := Content.upgrade_rarity(upgrade)
	var tint: Color = Content.rarity_color(rarity)
	var epic := rarity == "epic"
	var medallion := Kit.BoonMedallion.new()
	medallion.setup(str(upgrade.get("id", "")), tint, epic)
	var foot := rarity.to_upper()
	if bool(upgrade.get("unique", false)):
		foot += "  ·  ONCE PER DESCENT"
	var card := Kit.card("Boon%d" % i, str(upgrade.get("title", "A Nameless Boon")), str(upgrade.get("desc", "")), foot, tint, medallion, Vector2(width, 318), epic, str(i + 1))
	card.focus_entered.connect(_lift.bind(card, true))
	card.focus_exited.connect(_lift.bind(card, false))
	return card


## The lean a resting card keeps in the fan: outer cards turned outward.
func _fan(card: Control) -> float:
	var n := row.get_child_count()
	return (float(card.get_index()) - float(n - 1) * 0.5) * 0.012


func _lift(card: Button, up: bool) -> void:
	if not is_instance_valid(card) or T.still():
		return
	card.pivot_offset = card.size * Vector2(0.5, 1.0)
	var t := Kit.tween(card)
	t.set_parallel(true)
	t.tween_property(card, "scale", Vector2.ONE * (1.04 if up else 1.0), T.FAST).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(card, "rotation", 0.0 if up else _fan(card), T.FAST).set_trans(Tween.TRANS_SINE)


## Deal the cards in one after another, each turning into the fan as it lands.
func _deal_in(cards: Array) -> void:
	if T.still():
		return
	for i in range(cards.size()):
		var card: Button = cards[i]
		card.modulate.a = 0.0
		card.scale = Vector2.ONE * 0.9
		card.rotation = (float(i) - float(cards.size() - 1) * 0.5) * 0.09
		card.pivot_offset = card.custom_minimum_size * Vector2(0.5, 1.0)
		var t := Kit.tween(card)
		t.tween_interval(0.06 + float(i) * 0.08)
		t.set_parallel(true)
		t.tween_property(card, "modulate:a", 1.0, 0.18)
		t.tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(card, "rotation", _fan(card), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Opened: the deal arms itself (see deal), so nothing takes focus early.
func opened(_from: String) -> void:
	settle()


## Take the card a number key names, once the deal is armed. Returns whether
## the key named a card.
func take_by_key(keycode: int) -> bool:
	var index := UiInput.boon_index_for_key(keycode)
	var cards: Array = get_meta("buttons", [])
	if index < 0 or index >= cards.size() or stage.awaiting_arm(cards[index]):
		return false
	(cards[index] as Button).pressed.emit()
	return true
