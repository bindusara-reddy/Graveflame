extends "res://tests/harness.gd"
## Persistent legacy contract (headless): the title's victory candles and their
## celebration, the victory card's ordinal and vow line, the results input lock,
## the Forge roll and kept seals, and the throne room's finale hooks.
const VFX := preload("res://scripts/vfx.gd")

func run() -> void:
	use_scratch_save("legacy_contract")
	Save.save_save({"cells": 0, "best_score": 0, "meta": [], "learned": [], "victories": 3, "best_vows": 5,
		"roll": [0, 2, 5], "oath_kept": true, "last_celebrated": 2, "falls": 47, "falls_legacy": true, "vows_kept_ever": ["v_embers"]})
	await load_main_scene(4)
	var ui := game.ui
	await _check_title(ui)
	_check_victory_card(ui)
	await _check_input_lock(ui)
	_check_forge(ui)
	await _check_throne()
	await finish("LEGACY")

func _check_title(ui: UI) -> void:
	var tableau = ui._title_tableau
	check(tableau.legacy.victories == 3 and tableau.legacy.oath, "the title reads the victory record on arrival")
	check(tableau._wax(0) == tableau.WAX_PLAIN and tableau._wax(1) == tableau.WAX_VOWED and tableau._wax(2) == tableau.WAX_OATH, "wax follows the vows each win was kept under")
	check(tableau._exclusions.size() == 2, "the title passes its wordmark band and menu column to the tableau")
	var near: Dictionary = tableau._foreground(tableau.size)
	var last_d := -1.0
	for slot in tableau._candle_slots.filter(func(sill: Dictionary) -> bool: return sill.has("d")):
		var p: Vector2 = slot.p
		check(tableau._touches_any(Rect2(p, Vector2.ONE), tableau._exclusions) == false, "no candle stands in the wordmark band or the menu (%s)" % p)
		check(not tableau._covered(p, near.walls + [near.bridge, near.landing]), "no candle hides behind the near stone (%s)" % p)
		check(float(slot.d) >= last_d, "candles fill outward from the knight")
		last_d = float(slot.d)
	# The third win is new: it strikes once as the reveal lifts, then burns.
	var strikes := [0]
	tableau.candle_struck.connect(func() -> void: strikes[0] += 1)
	check(tableau._kindled(2) == 0.0 and tableau._kindled(1) == 1.0, "only the new candle waits to strike")
	for i in range(5):
		tableau._process(0.5)
	check(strikes[0] == 1 and tableau._kindled(2) == 1.0, "the new candle strikes once and catches (strikes %d)" % strikes[0])

func _check_victory_card(ui: UI) -> void:
	var panel: Control = ui._panels["victory"]
	ui.set_victory_extras("THE FOURTH FLAME", true)
	check((panel.get_meta("kicker_label") as Label).text == "WARDEN DEFEATED  ·  THE FOURTH FLAME", "the kicker names which flame this was")
	check((panel.get_meta("vows_label") as Label).visible, "a first victory points to the vows")
	ui.set_victory_extras("THE FIFTH FLAME", false)
	check(not (panel.get_meta("vows_label") as Label).visible, "later victories leave the vow line out")

func _check_input_lock(ui: UI) -> void:
	var again := ui._panels["victory"].find_child("again", true, false) as Button
	ui.hide_all_panels()
	ui.show_panel("victory")
	Input.action_press("jump")
	ui.lock_until_released("victory", ["jump", "ui_accept"])
	await ticks(3)
	check(again.disabled and again.focus_mode == Control.FOCUS_NONE, "a held key cannot press NEW RUN")
	Input.action_release("jump")
	await ticks(3)
	check(not again.disabled and again.has_focus(), "releasing every key restores the buttons and focuses NEW RUN")
	ui.hide_all_panels()

func _check_forge(ui: UI) -> void:
	check(UI._roll_line({"victories": 4, "falls": 47, "falls_legacy": true, "best_vows": 3}) == "THE ROLL  ·  4 FLAMES  ·  47+ FALLEN  ·  HIGHEST OATH 3 OF 5", "the roll counts flames, the fallen and the hardest oath")
	check(UI._roll_line({"victories": 1, "falls": 2, "oath_kept": true}).ends_with("1 FLAME  ·  2 FALLEN  ·  THE FIVEFOLD OATH IS KEPT"), "the roll honours the kept Oath")
	ui.setup_forge(0)
	var seals := ui._forge_rows.find_children("*", "Control", true, false).filter(func(node: Node) -> bool: return node is UI.KeptSeal)
	check(seals.size() == 1, "one seal beside each vow kept through a win")

func _check_throne() -> void:
	Save.save_save(Save.load_save().merged({"victories": 15}, true))
	await start_run(0)
	game.run.room_index = game.run.rooms_total() - 2
	game._advance_room()
	await ticks(3)
	var room := game.room
	check(room.victory_candles == Room.MAX_DAIS_CANDLES and room.props.is_empty(), "the throne dais holds one candle per victory (capped) and no breakables")
	check(game.torch_positions() == game._apse_sconces(), "the throne's torch lights hang on its columns")
	room.fire_heat = 0.35
	room.sigil_gold = 1.0
	var boss_lights: Array = room.light_points().slice(0, 3)
	check(is_equal_approx(float(boss_lights[0].alpha), 0.36 * 0.35), "brazier light sinks with the fires")
	check((boss_lights[2].color as Color).is_equal_approx(VFX.GOLD), "the relit sigil lights the hall gold")
	room.sigil_heat = 1.4
	Feedback.flash_reduced = true
	check(is_equal_approx(room.sigil_flare(), 1.2), "reduced flash caps the sigil flare")
	Feedback.flash_reduced = false
	game.sconce_heat = 0.0
	await ticks(2)
	for light in game._lights._torches:
		check(not light.enabled or is_zero_approx(light.energy), "cold sconces cast no light")
	game.sconce_heat = 1.0
