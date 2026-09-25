extends "res://tests/harness.gd"
## Title-menu contract on the REAL presented window: layout bounds at three
## viewport sizes, keyboard + gamepad navigation through viewport input events,
## controls-overlay focus trap, cancel/close without launching a run, focus
## restoration, reduced-motion stillness, and the real start/forge paths.
## Needs a display:
##   godot4 --path . --audio-driver Dummy --script res://tests/title_menu_contract.gd

var ui: UI
var starts := 0
var forges := 0


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await ticks(2)


func _stick(axis: JoyAxis, value: float) -> void:
	for axis_value in [value, 0.0]:
		var event := InputEventJoypadMotion.new()
		event.axis = axis
		event.axis_value = axis_value
		Input.parse_input_event(event)
		await ticks(2)


func _title_button(node_name: String) -> Button:
	return (ui._panels["title"] as Control).find_child(node_name, true, false) as Button


func _labels(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Label and (child as Label).is_visible_in_tree():
			out.append((child as Label).text)
		_labels(child, out)


func _inside(rect: Rect2, bounds: Rect2) -> bool:
	return bounds.grow(0.5).encloses(rect)


func _check_layout(label: String) -> void:
	# canvas_items stretch keeps the canvas at the design size and scales it to
	# the window, so on-screen means inside the visible rect in canvas units.
	var bounds := root.get_visible_rect()
	var title: Control = ui._panels["title"]
	var dialog: Control = title.get_meta("dialog")
	check(_inside(dialog.get_global_rect(), bounds), "%s: title dialog on-screen" % label)
	for node_name in ["start", "forge", "controls"]:
		var button := _title_button(node_name)
		check(button != null and _inside(button.get_global_rect(), bounds), "%s: %s button on-screen" % [label, node_name])
	var wordmark := title.find_child("TitleStack", true, false) as Control
	check(wordmark != null and _inside(wordmark.get_global_rect(), bounds), "%s: wordmark on-screen" % label)
	var forge := _title_button("forge")
	check(wordmark != null and forge != null and wordmark.get_global_rect().end.y <= forge.get_global_rect().position.y, "%s: wordmark sits above the navigation" % label)
	ui._toggle_title_controls()
	await ticks(3)
	var card := title.find_child("ControlsCard", true, false) as Control
	check(card != null and card.is_visible_in_tree() and _inside(card.get_global_rect(), bounds), "%s: controls card on-screen (card %s)" % [label, card.get_global_rect() if card != null else null])
	ui._toggle_title_controls()
	await ticks(2)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("TITLE_MENU requires a real display")
		quit(2)
		return
	use_scratch_save("title_menu_contract")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	await set_window_size(Vector2i(1280, 720))
	await load_main_scene(6)
	ui = game.ui
	ui.start_requested.connect(func(): starts += 1)
	ui.forge_requested.connect(func(): forges += 1)
	check(game.state == Game.GState.TITLE, "boots to the title")

	# --- Presentation: no redundant copy, bindings live behind CONTROLS only ---
	var texts: Array = []
	_labels(ui._panels["title"], texts)
	var clutter := texts.filter(func(t: String): return t.begins_with("AN ORIGINAL") or t.begins_with("Descend.") or t.contains("SPACE JUMP"))
	check(clutter.is_empty(), "title has no genre eyebrow, slogan or binding strip (found %s)" % [clutter])
	check(texts.has("GRAVEFLAME"), "wordmark present")
	var overlay: Control = ui._title_controls
	check(overlay != null and not overlay.visible, "controls overlay starts hidden")
	var overlay_texts: Array = []
	_labels(overlay, overlay_texts)
	ui._toggle_title_controls()
	await ticks(2)
	overlay_texts.clear()
	_labels(overlay, overlay_texts)
	check(overlay_texts.has("KEYBOARD") and overlay_texts.has("GAMEPAD"), "controls overlay lists keyboard and gamepad columns")
	# Asserted against the live map rather than a hand-typed abbreviation, so the
	# check stays about "shows real bindings" and not about exact wording.
	var pause_key := str(UI._binding_text("pause")["key"])
	check(overlay_texts.has("START") and overlay_texts.has(pause_key), "controls overlay shows real pause bindings (looked for %s)" % pause_key)
	ui._toggle_title_controls()
	await ticks(2)

	# --- Layout at three presented sizes ---
	await _check_layout("1280x720")
	await set_window_size(Vector2i(960, 540))
	await _check_layout("960x540")
	await set_window_size(Vector2i(1920, 1080), true)
	await _check_layout("1920x1080")
	await set_window_size(Vector2i(1280, 720))

	# --- Keyboard through the viewport ---
	ui.hide_all_panels()
	ui.show_panel("title")
	await ticks(3)
	check(focus_name() == "start", "keyboard: title focuses BEGIN first (got %s)" % focus_name())
	await tap_key(KEY_DOWN)
	check(focus_name() == "forge", "keyboard: Down moves to forge (got %s)" % focus_name())
	await tap_key(KEY_DOWN)
	check(focus_name() == "controls", "keyboard: Down moves to controls (got %s)" % focus_name())
	await tap_key(KEY_ENTER)
	check(overlay.visible, "keyboard: Enter opens controls")
	check(focus_name() == "close_controls", "keyboard: overlay takes focus (got %s)" % focus_name())
	await tap_key(KEY_DOWN)
	await tap_key(KEY_UP)
	await tap_key(KEY_TAB)
	check(focus_name() == "close_controls", "keyboard: focus trapped inside overlay (got %s)" % focus_name())
	await tap_key(KEY_ESCAPE)
	check(not overlay.visible, "keyboard: Escape closes controls")
	check(focus_name() == "controls", "keyboard: focus restored to CONTROLS (got %s)" % focus_name())
	check(game.state == Game.GState.TITLE and starts == 0, "keyboard: Escape never starts a run")
	await tap_key(KEY_ENTER)
	check(overlay.visible, "keyboard: reopen controls")
	await tap_key(KEY_ENTER)
	check(not overlay.visible and focus_name() == "controls", "keyboard: Enter on CLOSE closes and restores focus (got %s)" % focus_name())
	check(game.state == Game.GState.TITLE and starts == 0, "keyboard: closing never starts a run")
	await tap_key(KEY_ESCAPE)
	check(game.state == Game.GState.TITLE and not overlay.visible, "keyboard: Escape with overlay closed is inert")
	await tap_key(KEY_UP)
	await tap_key(KEY_UP)
	check(focus_name() == "start", "keyboard: Up returns to BEGIN (got %s)" % focus_name())

	# --- Gamepad through the viewport ---
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _stick(JOY_AXIS_LEFT_Y, 1.0)
	check(focus_name() == "controls", "pad: d-pad + stick reach CONTROLS (got %s)" % focus_name())
	await _pad(JOY_BUTTON_A)
	check(overlay.visible and focus_name() == "close_controls", "pad: A opens controls with focus (got %s)" % focus_name())
	await _pad(JOY_BUTTON_DPAD_UP)
	await _stick(JOY_AXIS_LEFT_Y, -1.0)
	check(focus_name() == "close_controls", "pad: focus trapped inside overlay (got %s)" % focus_name())
	await _pad(JOY_BUTTON_B)
	check(not overlay.visible and focus_name() == "controls", "pad: B closes controls and restores focus (got %s)" % focus_name())
	check(game.state == Game.GState.TITLE and starts == 0, "pad: B never starts a run")
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	check(not overlay.visible and focus_name() == "controls" and starts == 0, "pad: A on CLOSE closes without starting")
	await _stick(JOY_AXIS_LEFT_Y, -1.0)
	check(focus_name() == "forge", "pad: stick up reaches THE FORGE (got %s)" % focus_name())
	await _pad(JOY_BUTTON_A)
	check(forges == 1 and (ui._panels["forge"] as Control).visible, "pad: A opens the forge")
	ui.back_from_forge_requested.emit()
	await ticks(3)
	check((ui._panels["title"] as Control).visible and focus_name() == "start", "forge back returns to title with BEGIN focused (got %s)" % focus_name())

	# --- Reduced motion keeps the title still ---
	ui._reduced_motion_check.button_pressed = true
	await ticks(3)
	check(Feedback.motion_reduced, "reduced motion option reaches Feedback")
	var embers := ui._title_tableau.get_node("Embers") as CPUParticles2D
	check(embers != null and not embers.visible, "reduced motion hides title embers")
	var face_a: Color = ui._title_top_label.get_theme_color("font_color")
	await ticks(6)
	var face_b: Color = ui._title_top_label.get_theme_color("font_color")
	check(face_a == face_b, "reduced motion freezes the wordmark flicker")
	ui._reduced_motion_check.button_pressed = false
	await ticks(3)
	check(not Feedback.motion_reduced and embers.visible, "motion restored re-enables embers")

	# --- Real start ---
	check(focus_name() == "start", "BEGIN focused before start (got %s)" % focus_name())
	await tap_key(KEY_ENTER)
	await ticks(4)
	check(starts == 1 and game.state == Game.GState.PLAYING, "keyboard: Enter on BEGIN starts a run")

	await finish("TITLE_MENU")
