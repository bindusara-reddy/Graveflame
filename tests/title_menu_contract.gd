extends SceneTree
## Title-menu contract on the REAL presented window: layout bounds at three
## viewport sizes, keyboard + gamepad navigation through viewport input events,
## controls-overlay focus trap, cancel/close without launching a run, focus
## restoration, reduced-motion stillness, and the real start/forge paths.
## Needs a display:
##   godot4 --path . --audio-driver Dummy --script res://tests/title_menu_contract.gd

var checks := 0
var failures := 0
var game: Game
var ui: UI
var starts := 0
var forges := 0


func _init() -> void:
	call_deferred("_run")


func check(cond: bool, message: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + message)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _key(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func _pad(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func _stick(axis: JoyAxis, value: float) -> void:
	var push := InputEventJoypadMotion.new()
	push.axis = axis
	push.axis_value = value
	Input.parse_input_event(push)
	await _frames(2)
	var rest := InputEventJoypadMotion.new()
	rest.axis = axis
	rest.axis_value = 0.0
	Input.parse_input_event(rest)
	await _frames(2)


func _focus_name() -> String:
	var owner := root.gui_get_focus_owner()
	return owner.name if owner != null else "<none>"


func _title_button(node_name: String) -> Button:
	return (ui._panels["title"] as Control).find_child(node_name, true, false) as Button


func _labels(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Label and (child as Label).is_visible_in_tree():
			out.append((child as Label).text)
		_labels(child, out)


func _inside(rect: Rect2, bounds: Rect2) -> bool:
	return bounds.grow(0.5).encloses(rect)


func _set_viewport(size: Vector2i, fullscreen: bool) -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# Keep clear of the desktop's top bar so the window manager honours the size.
		DisplayServer.window_set_position(Vector2i(160, 120))
		DisplayServer.window_set_size(size)
	await _frames(8)
	# Leaving fullscreen can hand back a maximised window; re-apply until it takes.
	var tries := 0
	while root.size != size and not fullscreen and tries < 6:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_position(Vector2i(160, 120))
		DisplayServer.window_set_size(size)
		await _frames(10)
		tries += 1
	check(root.size == size, "presented viewport is %s (got %s)" % [size, root.size])


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
	await _frames(3)
	var card := title.find_child("ControlsCard", true, false) as Control
	check(card != null and card.is_visible_in_tree() and _inside(card.get_global_rect(), bounds), "%s: controls card on-screen (card %s)" % [label, card.get_global_rect() if card != null else null])
	ui._toggle_title_controls()
	await _frames(2)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("TITLE_MENU requires a real display")
		quit(2)
		return
	Save.path = "user://title_menu_contract.json"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	await _set_viewport(Vector2i(1280, 720), false)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await _frames(6)
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
	await _frames(2)
	overlay_texts.clear()
	_labels(overlay, overlay_texts)
	check(overlay_texts.has("KEYBOARD") and overlay_texts.has("GAMEPAD"), "controls overlay lists keyboard and gamepad columns")
	check(overlay_texts.has("START") and overlay_texts.has("ESC"), "controls overlay shows real pause bindings")
	ui._toggle_title_controls()
	await _frames(2)

	# --- Layout at three presented sizes ---
	await _check_layout("1280x720")
	await _set_viewport(Vector2i(960, 540), false)
	await _check_layout("960x540")
	await _set_viewport(Vector2i(1920, 1080), true)
	await _check_layout("1920x1080")
	await _set_viewport(Vector2i(1280, 720), false)

	# --- Keyboard through the viewport ---
	ui.hide_all_panels()
	ui.show_panel("title")
	await _frames(3)
	check(_focus_name() == "start", "keyboard: title focuses BEGIN first (got %s)" % _focus_name())
	await _key(KEY_DOWN)
	check(_focus_name() == "forge", "keyboard: Down moves to forge (got %s)" % _focus_name())
	await _key(KEY_DOWN)
	check(_focus_name() == "controls", "keyboard: Down moves to controls (got %s)" % _focus_name())
	await _key(KEY_ENTER)
	check(overlay.visible, "keyboard: Enter opens controls")
	check(_focus_name() == "close_controls", "keyboard: overlay takes focus (got %s)" % _focus_name())
	await _key(KEY_DOWN)
	await _key(KEY_UP)
	await _key(KEY_TAB)
	check(_focus_name() == "close_controls", "keyboard: focus trapped inside overlay (got %s)" % _focus_name())
	await _key(KEY_ESCAPE)
	check(not overlay.visible, "keyboard: Escape closes controls")
	check(_focus_name() == "controls", "keyboard: focus restored to CONTROLS (got %s)" % _focus_name())
	check(game.state == Game.GState.TITLE and starts == 0, "keyboard: Escape never starts a run")
	await _key(KEY_ENTER)
	check(overlay.visible, "keyboard: reopen controls")
	await _key(KEY_ENTER)
	check(not overlay.visible and _focus_name() == "controls", "keyboard: Enter on CLOSE closes and restores focus (got %s)" % _focus_name())
	check(game.state == Game.GState.TITLE and starts == 0, "keyboard: closing never starts a run")
	await _key(KEY_ESCAPE)
	check(game.state == Game.GState.TITLE and not overlay.visible, "keyboard: Escape with overlay closed is inert")
	await _key(KEY_UP)
	await _key(KEY_UP)
	check(_focus_name() == "start", "keyboard: Up returns to BEGIN (got %s)" % _focus_name())

	# --- Gamepad through the viewport ---
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _stick(JOY_AXIS_LEFT_Y, 1.0)
	check(_focus_name() == "controls", "pad: d-pad + stick reach CONTROLS (got %s)" % _focus_name())
	await _pad(JOY_BUTTON_A)
	check(overlay.visible and _focus_name() == "close_controls", "pad: A opens controls with focus (got %s)" % _focus_name())
	await _pad(JOY_BUTTON_DPAD_UP)
	await _stick(JOY_AXIS_LEFT_Y, -1.0)
	check(_focus_name() == "close_controls", "pad: focus trapped inside overlay (got %s)" % _focus_name())
	await _pad(JOY_BUTTON_B)
	check(not overlay.visible and _focus_name() == "controls", "pad: B closes controls and restores focus (got %s)" % _focus_name())
	check(game.state == Game.GState.TITLE and starts == 0, "pad: B never starts a run")
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	check(not overlay.visible and _focus_name() == "controls" and starts == 0, "pad: A on CLOSE closes without starting")
	await _stick(JOY_AXIS_LEFT_Y, -1.0)
	check(_focus_name() == "forge", "pad: stick up reaches THE FORGE (got %s)" % _focus_name())
	await _pad(JOY_BUTTON_A)
	check(forges == 1 and (ui._panels["forge"] as Control).visible, "pad: A opens the forge")
	ui.back_from_forge_requested.emit()
	await _frames(3)
	check((ui._panels["title"] as Control).visible and _focus_name() == "start", "forge back returns to title with BEGIN focused (got %s)" % _focus_name())

	# --- Reduced motion keeps the title still ---
	ui._reduced_motion_check.button_pressed = true
	await _frames(3)
	check(Feedback.motion_reduced, "reduced motion option reaches Feedback")
	check(ui._title_embers != null and not ui._title_embers.visible, "reduced motion hides title embers")
	var face_a: Color = ui._title_top_label.get_theme_color("font_color")
	await _frames(6)
	var face_b: Color = ui._title_top_label.get_theme_color("font_color")
	check(face_a == face_b, "reduced motion freezes the wordmark flicker")
	ui._reduced_motion_check.button_pressed = false
	await _frames(3)
	check(not Feedback.motion_reduced and ui._title_embers.visible, "motion restored re-enables embers")

	# --- Real start ---
	check(_focus_name() == "start", "BEGIN focused before start (got %s)" % _focus_name())
	await _key(KEY_ENTER)
	await _frames(4)
	check(starts == 1 and game.state == Game.GState.PLAYING, "keyboard: Enter on BEGIN starts a run")

	print("TITLE_MENU_RESULT: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
