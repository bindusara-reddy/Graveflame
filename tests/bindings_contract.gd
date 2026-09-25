extends "res://tests/harness.gd"
## Key-binding contracts. Three silent failure modes are pinned here:
## a rebind that saves but never reaches InputMap, one that also strips the
## gamepad binding for that action, and a controls screen that lies about the
## live bindings (it used to be a hardcoded table that could drift from reality).

func key_codes(action: String) -> Array:
	var out: Array = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			out.append(int((event as InputEventKey).physical_keycode))
	return out

func pad_count(action: String) -> int:
	var n := 0
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			n += 1
	return n

func press(keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await ticks(2)

func cell(action: String, column: String) -> String:
	var cells = game.ui._title_controls.get_meta("control_cells")
	return (cells[action][column] as Label).text

func run() -> void:
	use_scratch_save("bindings_contract")
	await load_main_scene(8)

	# --- The reference card must describe what the game actually does ---
	for row in Content.CONTROLS_ROWS:
		var action := str(row.action)
		var live := UI._binding_text(action)
		check(cell(action, "key") == str(live["key"]), "controls card key for %s matches the input map" % action)
		check(cell(action, "pad") == str(live["pad"]), "controls card pad for %s matches the input map" % action)
	check(cell("jump", "pad") == "A", "the pad column still names buttons (got %s)" % cell("jump", "pad"))

	# Every listed action must be reachable on both devices, or it is unusable
	# for whoever is holding the other one.
	for row in Content.CONTROLS_ROWS:
		var action := str(row.action)
		check(not key_codes(action).is_empty(), "%s has a keyboard binding" % action)
		check(pad_count(action) > 0, "%s has a gamepad binding" % action)

	# Dash shipped bound to PageDown while the README documented Shift, so the
	# documented key did nothing. The two must agree; this pins that.
	check(key_codes("dash").has(KEY_SHIFT), "dash is bound to the documented Shift key (got %s)" % str(key_codes("dash")))
	check(not key_codes("dash").has(KEY_PAGEDOWN), "dash is not bound to the stray PageDown code")

	# D-pad down used to drink a flask, so a D-pad player could never air-slam
	# (DOWN + BLADE). It is DOWN now, and the flask sits on the left trigger.
	var dpad_down := InputEventJoypadButton.new()
	dpad_down.button_index = JOY_BUTTON_DPAD_DOWN
	dpad_down.pressed = true
	check(InputMap.event_is_action(dpad_down, "move_down"), "D-pad down is DOWN, so it can aim an air slam")
	check(not InputMap.event_is_action(dpad_down, "heal"), "D-pad down no longer drinks a flask")
	check(cell("heal", "pad") == "LT", "the flask is on the left trigger (got %s)" % cell("heal", "pad"))

	# --- Rebinding ---
	game.ui.keys_requested.emit()
	await ticks(4)
	check((game.ui._panels["keys"] as Control).visible, "the key bindings panel opens")
	check(key_codes("attack").has(KEY_J), "blade starts on its shipped key")

	# Find the BLADE row and rebind it.
	var blade_button: Button = null
	for row in game.ui._key_rows.get_children():
		var label := row.get_child(0) as Label
		if label != null and label.text == "BLADE":
			blade_button = row.get_child(1) as Button
	check(blade_button != null, "the BLADE row is listed")
	if blade_button != null:
		var pads_before := pad_count("attack")
		blade_button.pressed.emit()
		await ticks(2)
		check(blade_button.text.contains("PRESS"), "the row waits for a keypress")
		await press(KEY_ESCAPE)
		await ticks(2)
		check(key_codes("attack").has(KEY_J), "ESC cancels the rebind and keeps the old key")
		blade_button.pressed.emit()
		await ticks(2)
		await press(KEY_H)
		await ticks(3)
		check(key_codes("attack") == [KEY_H], "the action is rebound to the new key alone (got %s)" % str(key_codes("attack")))
		check(pad_count("attack") == pads_before, "the gamepad binding survives a keyboard rebind")
		check(int(Save.get_bindings().get("attack", 0)) == KEY_H, "the rebind is persisted")
		check(cell("attack", "key") == "H", "the controls card reflects the rebind at once")

	# --- The rebound key must actually play ---
	game.ui.back_from_keys_requested.emit()
	await ticks(2)
	check((game.ui._panels["options"] as Control).visible, "BACK from keys returns to options")
	game.ui.hide_all_panels()
	game.ui.start_requested.emit()
	await ticks(20)
	await press(KEY_H)
	await ticks(2)
	check(game.player.state == Player.State.ATTACK, "the rebound key performs the action in play")

	# --- A relaunch honours it, and a hand-edited save cannot invent an action ---
	await free_game()
	await ticks(3)
	await load_main_scene(8)
	check(key_codes("attack") == [KEY_H], "the rebind survives a relaunch")
	var data := Save.load_save()
	var bindings = data.get("bindings", {})
	bindings["not_an_action"] = KEY_Z
	data["bindings"] = bindings
	Save.save_save(data)
	check(not Save.get_bindings().has("not_an_action"), "an unknown action in the save is ignored")

	await finish("BINDINGS")
