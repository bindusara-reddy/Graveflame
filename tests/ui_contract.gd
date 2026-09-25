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
	await _test_rebind_conflicts()
	await _test_reward_cards()
	await _test_gameover_arming()
	await _test_prompts()
	await _test_pause_ledger()
	await _test_chamber_banners()
	await _test_story_lines()
	await _test_burn_veil()
	await _test_title_return()
	_test_hud_affordances()
	_test_shake_slider()
	await _test_threat_pips()
	await finish("UI_CONTRACT")


## A foe winding up beyond the frame gets a pip on the edge nearest it; one
## in view does not.
func _test_threat_pips() -> void:
	await start_run(20)
	var foe: Enemy = game.room.enemies.filter(func(e): return is_instance_valid(e))[0]
	var view := game.world_view.get_canvas_transform()
	foe.global_position = view.affine_inverse() * Vector2(1500.0, 360.0)
	foe.state = Enemy.EState.WINDUP
	game.ui.track_threats([foe], view)
	var pips: Array = game.ui._threat_pips._pips
	check(pips.size() == 1 and pips[0].at.x > 1200.0 and absf(pips[0].angle) < 0.1, "a windup beyond the right edge gets a pip there, pointing out")
	foe.global_position = view.affine_inverse() * Vector2(640.0, 360.0)
	game.ui.track_threats([foe], view)
	check(game.ui._threat_pips._pips.is_empty(), "a foe in view needs no pip")
	game.ui.quit_to_title_requested.emit()
	await ticks(3)


## Screen shake has its own strength, saved and applied as it moves.
func _test_shake_slider() -> void:
	var slider: HSlider = game.ui._option_sliders["shake"]["slider"]
	slider.value = 0.35
	check(is_equal_approx(Feedback.shake_scale, 0.35), "the shake slider scales the camera shake")
	check(is_equal_approx(float(Save.get_options().shake), 0.35), "the shake strength is saved")
	slider.value = 1.0


## The HUD marks what a resource buys: Lance notches, a gold IGNITE prompt,
## a sigil per flask charge, and the Warden's phase notch and ignition.
func _test_hud_affordances() -> void:
	var ui: UI = game.ui
	var notches := ui._special_bar.find_children("*", "Control", false, false).filter(func(c): return c is UI.BarNotches)
	check(notches.size() == 1 and notches[0].marks == [0.4, 0.8], "the Graveflame bar is notched at each Lance's cost")
	ui.set_special(100.0, 100.0)
	check(ui._special_value_label.text == "IGNITE  " + UI.prompt("ignite"), "a full bar names the Ignite key (got %s)" % ui._special_value_label.text)
	ui.set_special(40.0, 100.0)
	check(ui._special_value_label.text == "40 / 100", "spending it restores the count")
	ui.set_flask(1, 3)
	var sigils: Array = ui._flask_sigils
	check(sigils.size() == 3 and sigils[0].modulate == Color.WHITE and sigils[2].modulate.a < 1.0, "one flask sigil per charge, spent ones dimmed")
	ui.show_boss_bar(1000.0)
	ui.update_boss_bar(400.0)
	check(ui._boss_ignited and ui._boss_name_label.text.ends_with("IGNITED"), "past the phase notch the Warden's bar ignites")
	ui.show_boss_bar(1000.0)
	check(not ui._boss_ignited, "a fresh boss bar starts unlit")
	ui.hide_boss_bar()


## The story contracts: an inscription speaks line by line over the chamber
## (the last line in gold) and fades on its own; the litany sits under the
## clear card, and leaves with it.
func _test_story_lines() -> void:
	game.ui.show_inscription(["They light a flame on every knight's grave.", "Yours got up."])
	var lines: Array = game.ui.hud._inscription.get_children().filter(func(c): return c is Label)
	check(lines.size() == 2 and lines[0].text.begins_with("They light") and lines[1].text == "Yours got up.", "the inscription sets one line per entry")
	check(lines[1].get_theme_color("font_color") == UiTheme.GOLD, "the inscription's last line is gold")
	await _wait_real(2.6)
	var holder: Control = game.ui.hud._inscription.get_parent()
	check(holder.is_visible_in_tree() and lines[1].modulate.a > 0.9, "both lines are up within the first seconds")
	var box := holder.get_global_rect()
	check(box.position.y >= 100.0 and box.end.y <= 320.0, "the inscription sits above the combat plane (got %s)" % box)
	await _wait_real(5.2)
	check(not holder.visible, "the inscription fades on its own")
	game.ui.show_room_clear("Ashen Cells")
	game.ui.show_litany("A flame is lit on every knight's grave.")
	await _wait_real(2.2)
	var litany: Label = game.ui.hud._litany
	var clear: Control = game.ui._room_clear_banner
	check(litany.is_visible_in_tree() and litany.modulate.a > 0.9 and litany.text == "A flame is lit on every knight's grave.", "the litany shows on the clear card")
	check(clear.scale == Vector2.ONE and clear.is_ancestor_of(litany), "the card stands full size while its litany is read")
	await _wait_real(2.4)
	check(clear.visible and clear.scale.x < 0.8 and not litany.visible, "the card then steps aside into its chip without the litany")
	game.ui.show_room_clear("Ashen Cells")
	game.ui.show_litany("Some of them get up.")
	game.ui.hide_room_clear()
	check(not litany.is_visible_in_tree(), "hiding the clear card takes the litany with it")


## The chamber veil burns fully open from any arrival point and leaves nothing.
func _test_burn_veil() -> void:
	var aspect := 1280.0 / 720.0
	var origin := Vector2(0.216, 0.596)
	var corner := (Vector2(aspect, 0.0) - origin * Vector2(aspect, 1.0)).length()
	check(UI.burn_reach(origin, aspect) >= corner + 0.22, "the burn reaches the farthest corner past its ragged edge")
	game.ui.fade_from_black(0.45, Vector2(0.02, 0.02))
	await _wait_real(1.0)
	var veil: ColorRect = game.ui._fade
	check(veil.material == null and is_zero_approx(veil.color.a), "a finished burn leaves no veil or shader behind")


## Stepping back to the title from a sub-screen does not replay the reveal.
func _test_title_return() -> void:
	game.ui.quit_to_title_requested.emit()
	await _wait_real(2.5)
	game.ui.options_requested.emit()
	await ticks(2)
	game.ui.back_from_options_requested.emit()
	await ticks(2)
	check(is_equal_approx(game.ui._title_holder.modulate.a, 1.0), "the title menu is fully lit after BACK from options")


## The HUD counts chambers and names the throne; the clear card steps aside.
func _test_chamber_banners() -> void:
	game.ui.set_room(3, 8)
	check(game.ui._room_label.text == "CHAMBER IV / VII", "the HUD counts chambers (got %s)" % game.ui._room_label.text)
	game.ui.set_room(7, 8)
	check(game.ui._room_label.text == "THE EMBER THRONE", "the throne is named, not counted")
	game.ui.show_room_clear("Ashen Cells")
	await _wait_real(2.2)
	var banner: Control = game.ui._room_clear_banner
	check(banner.visible and banner.scale.x < 0.8 and banner.position.y < 40.0, "the clear card shrinks into the top slot")
	game.ui.hide_room_clear()
	check(not banner.visible and banner.scale == Vector2.ONE, "hiding the clear card resets it")


## The pause card shows the build, and quitting asks before abandoning it.
func _test_pause_ledger() -> void:
	await start_run(20)
	game.run.apply_upgrade(upgrade("power"))
	game.run.apply_upgrade(upgrade("power"))
	game.run.apply_upgrade(upgrade("leech"))
	await tap_key(KEY_ESCAPE)
	var grid: GridContainer = game.ui._descent_grid
	check(grid.get_child_count() == 2, "one ledger tile per boon taken (got %d)" % grid.get_child_count())
	var power := grid.get_node("Taken_power") as Button
	check(power.find_children("*", "Label", true, false).any(func(l: Label): return l.text == "×2"), "a stacked boon shows its count")
	power.grab_focus()
	await ticks(1)
	check(game.ui._descent_detail.text.contains("+20% melee damage"), "focusing a tile reads out its effect")
	check(game.ui._descent_seed.text.contains(str(game._seed)), "the seed is shown")
	var quits := [0]
	game.ui.quit_to_title_requested.connect(func(): quits[0] += 1)
	game.ui._quit_button.pressed.emit()
	check(quits[0] == 0 and game.ui._quit_button.text == "ABANDON DESCENT?", "the first QUIT press only asks")
	game.ui._quit_button.pressed.emit()
	await ticks(2)
	check(quits[0] == 1 and game.state == Game.GState.TITLE, "a second press abandons the descent")


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


func _rebind(action: String, key: Key) -> void:
	_focus_button("Key_" + action, "keys").pressed.emit()
	await ticks(1)
	await tap_key(key)


## A key taken from another action never leaves two actions on it or one
## on none, and RESTORE DEFAULTS puts every key and the save back.
func _test_rebind_conflicts() -> void:
	game.ui.keys_requested.emit()
	await ticks(3)
	_focus_button("keys_restore", "keys").pressed.emit()
	await ticks(2)
	check(UI._key_codes("parry") == [KEY_S] and UI._key_codes("move_down") == [KEY_DOWN], "restoring defaults returns every key")
	check(Save.get_bindings().is_empty(), "restoring defaults forgets the saved rebinds")
	await _rebind("attack", KEY_S)
	check(UI._key_codes("attack") == [KEY_S] and UI._key_codes("parry") == [KEY_J], "taking parry's only key hands it blade's old one")
	await _rebind("attack", KEY_A)
	check(UI._key_codes("move_left") == [KEY_LEFT], "taking one of two keys leaves the other")
	var note: Label = _panel("keys").get_meta("note_label")
	check(note.text.begins_with("MOVE LEFT gives up A"), "the screen says what moved (got %s)" % note.text)
	check(int(Save.get_bindings().get("move_left", 0)) == KEY_LEFT, "the displaced action's key is saved")
	_focus_button("keys_restore", "keys").pressed.emit()
	await ticks(2)
	game.ui.back_from_keys_requested.emit()
	await ticks(2)


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
