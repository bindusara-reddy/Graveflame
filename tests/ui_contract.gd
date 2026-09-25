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
	await _test_page_turns()
	await _test_still_pages()
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
	var pips: Array = game.ui.hud._threat_pips._pips
	check(pips.size() == 1 and pips[0].at.x > 1200.0 and absf(pips[0].angle) < 0.1, "a windup beyond the right edge gets a pip there, pointing out")
	foe.global_position = view.affine_inverse() * Vector2(640.0, 360.0)
	game.ui.track_threats([foe], view)
	check(game.ui.hud._threat_pips._pips.is_empty(), "a foe in view needs no pip")
	game.ui.quit_to_title_requested.emit()
	await ticks(3)


## Screen shake has its own strength, saved and applied as it moves.
func _test_shake_slider() -> void:
	var slider: HSlider = game.ui._option_sliders["shake"]["slider"]
	slider.value = 0.35
	check(is_equal_approx(Feedback.shake_scale, 0.35), "the shake slider scales the camera shake")
	check(is_equal_approx(float(Save.get_options().shake), 0.35), "the shake strength is saved")
	slider.value = 1.0


## The HUD marks what a resource buys: Lance notches, a lit Ignite key, a
## flame per flask charge, and the Warden's seals and ignition. An idle HUD
## holds its meters and the knight's flame still.
func _test_hud_affordances() -> void:
	var ui: UI = game.ui
	var hud: UiHud = ui.hud
	check(hud._graveflame.notches == [0.4, 0.8], "the Graveflame is notched at each Lance's cost")
	ui.set_special(100.0, 100.0)
	check(hud._graveflame.hot and hud._ignite.lit and hud._ignite.action == "ignite" and hud._flame.roaring, "a full Graveflame lights the Ignite key and the knight's flame roars")
	ui.set_special(40.0, 100.0)
	check(not hud._graveflame.hot and not hud._ignite.lit and hud._ignite.modulate.a < 1.0, "spending it dims the key again")
	ui.set_flask(1, 3)
	check(hud._flasks.count == 3 and hud._flasks.filled == 1, "one flame per flask on the belt, spent ones snuffed")
	ui.set_hp(20.0, 100.0)
	check(hud._flame.guttering and hud._vitality_value.text == "20", "low vitality gutters the knight's flame")
	ui.set_hp(100.0, 100.0)
	var idle := [hud._vitality, hud._graveflame, hud._flame].all(func(n: Node): return not n.is_processing())
	check(idle, "an idle HUD holds its meters and the knight's flame still")
	ui.show_boss_bar(1000.0)
	ui.update_boss_bar(400.0)
	check(hud._boss_ignited and hud._warden_seals[0].broken and not hud._warden_seals[1].broken, "past its first seal the Warden's strip ignites")
	ui.show_boss_bar(1000.0)
	check(not hud._boss_ignited and not hud._warden_seals[0].broken, "a fresh Warden's strip starts sealed and unlit")
	ui.hide_boss_bar()


## The story contracts: an inscription speaks line by line over the chamber
## (the last line in gold) and fades on its own; the litany sits on the
## clear card, and leaves with it.
func _test_story_lines() -> void:
	var hud: UiHud = game.ui.hud
	game.ui.show_inscription(["They light a flame on every knight's grave.", "Yours got up."])
	var lines: Array = hud._inscription.find_children("*", "Label", true, false)
	check(lines.size() == 2 and lines[0].text.begins_with("They light") and lines[1].text == "Yours got up.", "the inscription sets one line per entry")
	check(lines[1].get_theme_color("font_color") == UiTheme.GOLD, "the inscription's last line is gold")
	await _wait_real(2.6)
	var holder: Control = hud._inscription.get_parent()
	check(holder.is_visible_in_tree() and lines[1].get_parent().modulate.a > 0.9, "both lines are up within the first seconds")
	var box := holder.get_global_rect()
	check(box.position.y >= 100.0 and box.end.y <= 320.0, "the inscription sits above the combat plane (got %s)" % box)
	await _wait_real(5.2)
	check(not holder.visible, "the inscription fades on its own")
	game.ui.show_room_clear("Ashen Cells")
	game.ui.show_litany("A flame is lit on every knight's grave.")
	await _wait_real(2.2)
	var card: UiKit.Banner = hud._clear
	var litany: Label = card.line
	check(litany.is_visible_in_tree() and litany.modulate.a > 0.9 and litany.text == "A flame is lit on every knight's grave.", "the litany shows on the clear card")
	check(card.strip.scale == Vector2.ONE and card.is_ancestor_of(litany), "the card stands full size while its litany is read")
	await _wait_real(2.8)
	check(hud._chip.visible and not litany.is_visible_in_tree(), "the card then steps aside into its chip without the litany")
	game.ui.show_room_clear("Ashen Cells")
	game.ui.show_litany("Some of them get up.")
	game.ui.hide_room_clear()
	check(not litany.is_visible_in_tree() and not hud._chip.visible, "hiding the clear card takes the litany with it")


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


## The track marks the chamber by numeral and name and crowns the throne;
## the chamber card counts chambers; the clear card steps aside into a chip.
func _test_chamber_banners() -> void:
	var hud: UiHud = game.ui.hud
	game.ui.set_room(3, 8)
	check(hud._track.current == 3 and hud._track.filled == 3 and hud._chamber.text == "CHAMBER IV", "the track marks the chamber the knight stands in (got %s)" % hud._chamber.text)
	game.ui.show_room_intro(3, 8, "ASHEN CELLS")
	check(hud._room_intro.kicker.text == "CHAMBER IV OF VII" and hud._room_intro.title.text == "Ashen Cells", "the chamber card counts chambers and names this one")
	check(hud._chamber.text == "IV · ASHEN CELLS", "the track takes the chamber's name from its card (got %s)" % hud._chamber.text)
	game.ui.set_room(7, 8)
	check(hud._chamber.text == "THE EMBER THRONE" and hud._track.current == -1 and hud._track.filled == 8, "the throne is named, not counted")
	game.ui.show_room_clear("Ashen Cells")
	await _wait_real(2.5)
	var chip: Control = hud._chip
	check(not hud._clear.visible and chip.visible and chip.get_global_rect().position.y < 40.0, "the clear card steps aside into a chip in the top slot")
	game.ui.hide_room_clear()
	check(not chip.visible and not hud._clear.visible, "hiding the clear card takes its chip")


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
	check(quits[0] == 0 and game.ui._quit_button.text == "ABANDON THE DESCENT?", "the first press on TO THE LANDING only asks")
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
	var flask: UiKit.Glyph = game.ui.hud._heal
	check(flask.action == "heal" and flask.is_in_group(UiInput.PROMPT_GROUP), "the flask cap is the live Flask glyph")
	check(UiInput.first_binding("heal").name == "H", "the flask cap follows a rebind (got %s)" % UiInput.first_binding("heal"))
	await _stick(JOY_AXIS_RIGHT_Y, 0.9)
	var pad_cap := str(UI._binding_text("heal")["pad"]).get_slice(" / ", 0)
	check(UiInput.first_binding("heal") == { "name": pad_cap, "device": "pad" }, "touching the pad switches caps to pad buttons (got %s)" % UiInput.first_binding("heal"))
	var rise: Array = (_panel("pause").get_meta("footer") as Control).find_children("*", "Control", true, false).filter(func(c): return c is UiKit.Glyph)
	check(rise.size() == 1 and rise[0].action == "pause" and UI.prompt("pause") == "[START]", "the pause footer's cap is the pad's pause button (got %s)" % UI.prompt("pause"))
	await tap_key(KEY_SHIFT)
	check(UiInput.first_binding("heal") == { "name": "H", "device": "key" }, "a keypress switches caps back to keys")


func _wait_real(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _rebind(action: String, key: Key) -> void:
	_focus_button("Key_" + action, "keys").pressed.emit()
	await ticks(1)
	await tap_key(key)


## RESTORE asks before it forgets every rebind: two presses.
func _restore_keys() -> void:
	var restore := _panel("keys").find_child("keys_restore", true, false) as Button
	restore.pressed.emit()
	restore.pressed.emit()


## A key taken from another action never leaves two actions on it or one
## on none, and RESTORE EVERY KEY puts every key and the save back.
func _test_rebind_conflicts() -> void:
	game.ui.keys_requested.emit()
	await ticks(3)
	_restore_keys()
	await ticks(2)
	check(UI._key_codes("parry") == [KEY_S] and UI._key_codes("move_down") == [KEY_DOWN], "restoring defaults returns every key")
	check(Save.get_bindings().is_empty(), "restoring defaults forgets the saved rebinds")
	await _rebind("attack", KEY_S)
	check(UI._key_codes("attack") == [KEY_S] and UI._key_codes("parry") == [KEY_J], "taking parry's only key hands it blade's old one")
	await _rebind("attack", KEY_A)
	check(UI._key_codes("move_left") == [KEY_LEFT], "taking one of two keys leaves the other")
	var note: Label = _panel("keys").get_meta("note_label")
	check(note.text.begins_with("Move left gives up A"), "the screen says what moved (got %s)" % note.text)
	check(int(Save.get_bindings().get("move_left", 0)) == KEY_LEFT, "the displaced action's key is saved")
	var restore := _panel("keys").find_child("keys_restore", true, false) as Button
	restore.pressed.emit()
	check(UI._key_codes("attack") == [KEY_A], "one press on RESTORE only asks")
	restore.pressed.emit()
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
	var numbers: Array = (_panel("reward").get_meta("footer") as Control).find_children("*", "Control", true, false).filter(func(c): return c is UiKit.Glyph and not c.binding.is_empty())
	check(numbers.map(func(g): return g.binding) == ["1", "2", "3", "4"], "the footer prints every card's key")
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
	var scroll := _panel("forge").find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
	_focus_button("Buy7", "forge")
	await ticks(3)
	check(scroll.follow_focus and scroll.scroll_vertical > 0, "the Forge list scrolls to follow focus below the fold")
	(_panel("forge").get_meta("tabs") as UiKit.Tabs).select(1)
	await ticks(2)
	check(focus_name() == "Vow0", "turning to the vows page brings focus with it (got %s)" % focus_name())
	var vow := _focus_button("Vow3", "forge")
	await ticks(1)
	vow.pressed.emit()
	await ticks(3)
	check(focus_name() == "Vow3", "swearing a vow keeps focus on that vow (got %s)" % focus_name())
	game.ui.back_from_forge_requested.emit()
	await ticks(2)


## Tabbed pages turn with PageDown (LB/RB on a pad) and bring focus onto the
## new page; the Forms' Back prompt takes a click like Esc does.
func _test_page_turns() -> void:
	game.ui.options_requested.emit()
	await ticks(3)
	check(focus_name() == "Opt_master", "SENSES opens on its first level (got %s)" % focus_name())
	await tap_key(KEY_PAGEDOWN)
	check(focus_name() == "Opt_fullscreen", "PageDown turns to SIGHT and its first switch (got %s)" % focus_name())
	await tap_key(KEY_PAGEUP)
	game.ui.keys_requested.emit()
	await ticks(3)
	(_panel("keys").get_meta("back_button") as Button).pressed.emit()
	await ticks(2)
	check(game.ui.is_panel_visible("options"), "the Forms' Back prompt returns to SENSES")
	game.ui.back_from_options_requested.emit()
	await ticks(2)


## Under reduced motion a page is simply there: it neither rises nor turns.
func _test_still_pages() -> void:
	game.ui._reduced_motion_check.button_pressed = true
	game.ui.forge_requested.emit()
	await ticks(1)
	var frame: Control = _panel("forge").get("frame")
	check(frame.rotation == 0.0 and is_equal_approx(frame.offset_top, (frame.get_meta("rest") as Vector2).x), "reduced motion lays the Forge down without a rise or a turn")
	game.ui.back_from_forge_requested.emit()
	game.ui._reduced_motion_check.button_pressed = false
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
