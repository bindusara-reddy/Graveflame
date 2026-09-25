extends "res://tests/harness.gd"
## Menu and HUD contracts: every screen backs out one way, lists keep the
## cursor where the player left it, and nothing a player mashes through a
## transition can pick for them. Headless; uses a scratch save.


func _panel(name: String) -> Control:
	return game.ui._panels[name] as Control


func _focus_button(node_name: String, panel: String) -> Button:
	var button := _panel(panel).find_child(node_name, true, false) as Button
	if button != null:
		button.grab_focus()
	return button


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await ticks(2)


func run() -> void:
	use_scratch_save("ui_contract")
	Save.add_cells(900)
	Save.add_victory(0)
	await load_main_scene(6)
	await _test_back_routing()
	await _test_forge_focus()
	await _test_rebind_capture()
	await _test_reward_cards()
	await _test_gameover_arming()
	await _test_prompts()
	await finish("UI_CONTRACT")


func _stick(axis: JoyAxis, value: float) -> void:
	for axis_value in [value, 0.0]:
		var event := InputEventJoypadMotion.new()
		event.axis = axis
		event.axis_value = axis_value
		Input.parse_input_event(event)
		await ticks(2)


## Prompts name the live binding on the device last touched.
func _test_prompts() -> void:
	game.ui.binding_changed.emit("heal", KEY_H)
	await ticks(2)
	var flask: Label = game.ui._flask_count_label
	check(flask.text.ends_with("[H]"), "the flask counter follows a rebind (got %s)" % flask.text)
	await _stick(JOY_AXIS_RIGHT_Y, 0.9)
	var pad_cap := str(UI._binding_text("heal")["pad"]).get_slice(" / ", 0)
	check(flask.text.ends_with("[%s]" % pad_cap), "touching the pad switches prompts to pad buttons (got %s)" % flask.text)
	var pause_footer: Label = _panel("pause").get_meta("footer_label")
	check(pause_footer.text.begins_with("[START]"), "the pause footer names the pad's pause button (got %s)" % pause_footer.text)
	await tap_key(KEY_SHIFT)
	check(flask.text.ends_with("[H]"), "a keypress switches prompts back to keys")


func _wait_real(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


## Seer's Eye deals four cards that still fit the frame, and a held jump
## cannot take one before the deal lands and the key is let go.
func _test_reward_cards() -> void:
	var picks := [0]
	game.ui.upgrade_selected.connect(func(_i: int): picks[0] += 1)
	Input.action_press("jump")
	game.ui.hide_all_panels()
	game.ui.setup_upgrades(Content.UPGRADES.slice(0, 4))
	game.ui.show_panel("reward")
	await ticks(3)
	var frame: Rect2 = game.ui._root.get_global_rect()
	var cards: Array = _panel("reward").get_meta("buttons")
	check(cards.all(func(c: Control): return frame.encloses(c.get_global_rect())), "four boon cards fit inside the frame")
	var footer: Label = _panel("reward").get_meta("footer_label")
	check(footer.text.begins_with("1 · 2 · 3 · 4 "), "the footer lists every card's key (got %s)" % footer.text)
	await tap_key(KEY_1)
	check(picks[0] == 0 and not focus_name().begins_with("Boon"), "a card cannot be taken while the deal lands")
	await _wait_real(1.0)
	check(not focus_name().begins_with("Boon"), "the cards stay inert while jump is still held")
	Input.action_release("jump")
	await ticks(2)
	check(focus_name() == "Boon0", "letting go of jump arms the cards (got %s)" % focus_name())
	game.ui.hide_all_panels()


## The death screen ignores a confirm mashed through its fade.
func _test_gameover_arming() -> void:
	var restarts := [0]
	game.ui.restart_requested.connect(func(): restarts[0] += 1)
	game.ui.show_panel("gameover", 0.6)
	await ticks(2)
	await tap_key(KEY_ENTER)
	check(restarts[0] == 0, "a confirm during the fade does not restart the descent")
	await _wait_real(1.0)
	check(focus_name() == "restart", "DESCEND AGAIN takes focus once armed (got %s)" % focus_name())
	game.ui.hide_all_panels()


## Esc never unpauses a run from inside a sub-screen, and pad B leaves the Forge.
func _test_back_routing() -> void:
	game.ui.forge_requested.emit()
	await ticks(3)
	await _pad(JOY_BUTTON_B)
	check(game.ui.is_panel_visible("title") and not game.ui.is_panel_visible("forge"), "pad B backs out of the Forge to the title")
	await start_run(20)
	await tap_key(KEY_ESCAPE)
	check(game.ui.is_panel_visible("pause") and paused, "Esc pauses the run")
	game.ui.options_requested.emit()
	await ticks(3)
	await tap_key(KEY_ESCAPE)
	check(game.ui.is_panel_visible("pause") and not game.ui.is_panel_visible("options"), "Esc on options-from-pause returns to the pause card")
	check(paused and game.paused, "Esc inside options never unpauses the run")
	game.ui.options_requested.emit()
	await ticks(2)
	game.ui.keys_requested.emit()
	await ticks(2)
	await tap_key(KEY_ESCAPE)
	check(game.ui.is_panel_visible("options") and paused, "Esc on keys steps back to options, still paused")
	await tap_key(KEY_ESCAPE)
	await tap_key(KEY_ESCAPE)
	check(not paused and not game.ui.is_panel_visible("pause"), "Esc on the pause card resumes")
	game.ui.quit_to_title_requested.emit()
	await ticks(3)


## A purchase or vow toggle rebuilds the Forge without moving the cursor.
func _test_forge_focus() -> void:
	var moves := [0]
	game.ui.cue.connect(func(kind: String): moves[0] += int(kind == "ui_move"))
	game.ui.forge_requested.emit()
	await ticks(3)
	check(moves[0] == 0, "focus placed by a screen opening is silent")
	await tap_key(KEY_DOWN)
	check(moves[0] == 1, "moving focus with the keys ticks once (got %d)" % moves[0])
	var buy := _focus_button("Buy1", "forge")
	await ticks(1)
	buy.pressed.emit()
	await ticks(3)
	check(focus_name() == "Buy1", "buying keeps focus on the bought row (got %s)" % focus_name())
	var vow := _focus_button("Vow3", "forge")
	await ticks(1)
	vow.pressed.emit()
	await ticks(3)
	check(focus_name() == "Vow3", "swearing a vow keeps focus on that vow (got %s)" % focus_name())
	var scroll := _panel("forge").find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
	check(scroll.follow_focus and scroll.scroll_vertical > 0, "the Forge list scrolls to follow focus below the fold")
	game.ui.back_from_forge_requested.emit()
	await ticks(2)


## The rebind listener hears the arrow keys before menu navigation does, and
## the rebuilt list keeps the cursor on the row that was rebound.
func _test_rebind_capture() -> void:
	game.ui.keys_requested.emit()
	await ticks(3)
	var row := _focus_button("Key_parry", "keys")
	await ticks(1)
	row.pressed.emit()
	await ticks(1)
	await tap_key(KEY_DOWN)
	var codes: Array = InputMap.action_get_events("parry").filter(func(e): return e is InputEventKey).map(func(e): return int(e.physical_keycode))
	check(codes == [KEY_DOWN], "an arrow key can be bound (got %s)" % str(codes))
	check(focus_name() == "Key_parry", "focus stays on the rebound row (got %s)" % focus_name())
	game.ui.back_from_keys_requested.emit()
	await ticks(2)
