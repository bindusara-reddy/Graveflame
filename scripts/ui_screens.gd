class_name UiScreens
extends Control
## Every full screen: the title and its controls card, pause with the ledger
## of this descent, the boon deal, the fall and the victory results, the Forge,
## options and key bindings. Owns menu navigation (focus, back-out, arming,
## rebinding). Raises the facade's signals, so game.gd listens in one place.

const VFX := preload("res://scripts/vfx.gd")
const TitleTableau := preload("res://scripts/title_tableau.gd")
const Kit := preload("res://scripts/ui_kit.gd")
const T := preload("res://scripts/ui_theme.gd")

## The facade whose signals every screen raises.
var ui: UI

var _panels: Dictionary = {}
## { panel, actions } while a results panel waits for held keys to lift.
var _input_lock: Dictionary = {}
var _quit_button: Button
## Running while QUIT TO TITLE waits for its confirming second press.
var _quit_confirm: Tween
## The pause card's ledger of the descent so far (see set_descent).
var _descent_grid: GridContainer
var _descent_detail: Label
var _descent_relics: Label
var _descent_vows: Label
var _descent_seed: Label
var _upgrade_row: HBoxContainer
var _forge_rows: VBoxContainer
## The options screen's reduced-motion box; the menu contracts toggle it.
var _reduced_motion_check: CheckBox
## Save option key -> the CheckBox on the options screen that shows it.
var _option_checks: Dictionary = {}
## key -> { slider, readout } for every volume control on the options screen.
var _option_sliders: Dictionary = {}
## Rebinding: the rows container and whichever action is awaiting a keypress.
var _key_rows: VBoxContainer
var _listening_action := ""
var _listening_button: Button

var _title_top_label: Label
var _title_tableau: Control
var _title_holder: Control
var _title_t := 0.0
var _last_panel := ""
var _title_controls: Control
var _title_controls_button: Button
var _title_nav_buttons: Array = []
## Frame of the player's last navigation press or hover. Focus that moves in
## that frame was moved by the player and ticks; focus grabbed by code (a
## screen opening, a list rebuilding) stays silent.
var _nav_frame := -1
## Actions that must be let go before a result screen arms: jump and attack
## get mashed through the transition, and pad A is also ui_accept.
const ARM_RELEASE_ACTIONS := ["ui_accept", "jump", "attack", "interact"]
## Buttons waiting to arm: { buttons, at_ms, focus }, empty when none are.
var _arming: Dictionary = {}

## Screens the title opens. Opened from the title they lie on its tableau,
## veiled, instead of replacing it.
const TITLE_SUBSCREENS := ["forge", "options", "keys"]
## Whether the title is showing beneath a sub-screen.
var _title_under := false

const KEYS_HELP := "Choose a key, then press the one you want.  ESC cancels."


## Build every screen, hidden. `facade` is the UI whose signals they raise.
func build(facade: UI) -> void:
	ui = facade
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(UiInput.PROMPT_GROUP)
	_build_title()
	_build_pause()
	_build_reward()
	_build_game_over()
	_build_victory()
	_build_forge()
	_build_options()
	_build_keys()


# --- Panels ------------------------------------------------------------------------

## A full-frame screen that stops clicks reaching the game, backed by a torn
## paper veil. `opaque` screens (the title's own sub-screens) dim what lies
## beneath harder than the in-descent screens, which keep the chamber in view.
func _screen(screen_name: String, opaque: bool, accent: Color) -> Control:
	var screen := Control.new()
	screen.name = screen_name.capitalize() + "Screen"
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := Kit.PaperVeil.new()
	veil.name = "Veil"
	# Over a paused chamber the margins stay nearly as dark as the sheet, so
	# the HUD under the tear reads as one dimmed layer, not two.
	veil.dim = Color(T.C_VOID, 0.62 if opaque else 0.72)
	veil.sheet = Color(T.C_INK, 0.94 if opaque else 0.88)
	veil.rim = Color(accent, 0.35)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panels[screen_name] = screen
	return screen


func is_panel_visible(panel_name: String) -> bool:
	return _panels.has(panel_name) and (_panels[panel_name] as Control).visible


## Show a screen, fading it in over `fade` seconds. Returns false for an
## unknown name, so the facade leaves the HUD alone.
func show_panel(panel_name: String, fade: float = 0.0) -> bool:
	if not _panels.has(panel_name):
		return false
	var panel: Control = _panels[panel_name]
	panel.visible = true
	panel.modulate = Color.WHITE
	# Settings screens settle onto the veil rather than cutting in.
	if panel_name in TITLE_SUBSCREENS:
		fade = maxf(fade, 0.2)
	if fade > 0.0 and not Feedback.motion_reduced:
		panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var t := Kit.tween(self)
		t.tween_property(panel, "modulate:a", 1.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if panel_name == "title":
		_set_title_controls_open(false)
		# Only a real arrival replays the reveal; stepping back from a
		# title sub-screen must not grey the menu out again.
		_title_tableau.arrive(not (_last_panel in TITLE_SUBSCREENS))
		_celebrate_new_victories()
	_underlay_title(panel_name in TITLE_SUBSCREENS and (_last_panel == "title" or _title_under))
	_last_panel = panel_name
	if panel_name == "keys":
		_set_keys_note("")
	if panel_name == "gameover":
		var buttons: Array = panel.get_meta("buttons")
		_arm_buttons(buttons, 0.9, buttons[0])
	Kit.focus_first_control(panel)
	return true


## Keep the title's tableau up beneath a sub-screen with its menu hidden, so
## nothing under the veil can take focus; or give the title its menu back.
func _underlay_title(under: bool) -> void:
	_title_under = under
	_title_holder.visible = not under
	if under:
		(_panels["title"] as Control).visible = true


func hide_panel(panel_name: String) -> void:
	if _panels.has(panel_name):
		(_panels[panel_name] as Control).visible = false


func hide_all_panels() -> void:
	for panel in _panels.values():
		(panel as Control).visible = false


## Repaint the key prompts in the screen footers (see UiInput.PROMPT_GROUP).
func refresh_prompts() -> void:
	_paint_reward_footer()
	(_panels["pause"].get_meta("footer_label") as Label).text = "%s  resume" % UiInput.prompt("pause")


# --- Navigation --------------------------------------------------------------------

## Runs before GUI navigation (the facade's _input), so a pending rebind can
## take the arrow keys and Enter, and so a navigation press is known before
## focus moves.
func handle_input(event: InputEvent) -> void:
	if not _listening_action.is_empty():
		if event is InputEventKey and event.pressed and not event.is_echo():
			_capture_rebind(UiInput.event_keycode(event as InputEventKey))
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_focus_hovered()
		return
	for action in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
		if event.is_action_pressed(action, true):
			_nav_frame = Engine.get_process_frames()


## Hovering a button or slider focuses it, so the mouse and the pad never
## light two controls at once.
func _focus_hovered() -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null or hovered.has_focus() or hovered.focus_mode == Control.FOCUS_NONE:
		return
	if not (hovered is BaseButton or hovered is Slider):
		return
	if hovered is BaseButton and (hovered as BaseButton).disabled:
		return
	_nav_frame = Engine.get_process_frames()
	hovered.grab_focus()


func on_focus_changed(_control: Control) -> void:
	if Engine.get_process_frames() == _nav_frame:
		ui.cue.emit("ui_move")


## Esc, pad B and pad START leave a settings screen through its own BACK
## button, so every screen exits one way and a paused run behind it never sees
## the press. B on the pause card resumes. Returns whether a screen took it.
func _back_out(event: InputEvent) -> bool:
	for panel_name in ["keys", "options", "forge"]:
		if is_panel_visible(panel_name):
			((_panels[panel_name] as Control).get_meta("back_button") as Button).pressed.emit()
			return true
	if is_panel_visible("pause") and event.is_action_pressed("ui_cancel"):
		ui.resume_requested.emit()
		return true
	return false


func handle_unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _back_out(event):
			get_viewport().set_input_as_handled()
			return
	# Boon cards print their index, so the number keys have to actually pick one.
	if event is InputEventKey and event.pressed and not event.echo:
		var reward: Control = _panels.get("reward", null)
		if reward != null and reward.visible:
			var index := UiInput.boon_index_for_key((event as InputEventKey).keycode)
			var buttons = reward.get_meta("buttons", [])
			if index >= 0 and index < buttons.size() and not _awaiting_arm(buttons[index]):
				(buttons[index] as Button).pressed.emit()
				get_viewport().set_input_as_handled()
				return
	# Esc / pad B closes the controls card and only that; the run never starts
	# from a cancel, and focus returns to the CONTROLS entry.
	if _title_controls == null or not _title_controls.visible:
		return
	var title_panel: Control = _panels.get("title", null)
	if title_panel == null or not title_panel.visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_set_title_controls_open(false)
		get_viewport().set_input_as_handled()


## Per-frame upkeep, paused or not (driven by the facade's _process): lifts
## input locks, arms waiting buttons, and flickers the title.
func tick(delta: float) -> void:
	_poll_input_lock()
	_poll_arming()
	_animate_title(delta)


## Hold `buttons` inert (unfocusable, unclickable) until `delay` real seconds
## have passed and no confirm-capable action is held, then focus `focus`. A
## jump or attack mashed through a transition can then never pick a boon or
## restart the descent before the screen has been read.
func _arm_buttons(buttons: Array, delay: float, focus: Control) -> void:
	_restore_armed()
	for button: Control in buttons:
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arming = { "buttons": buttons, "at_ms": Time.get_ticks_msec() + roundi(delay * 1000.0), "focus": focus }


func _awaiting_arm(button: Control) -> bool:
	return (_arming.get("buttons", []) as Array).has(button)


## Polled every frame: arms the waiting buttons once their delay has passed
## and every confirm-capable action has been let go.
func _poll_arming() -> void:
	if _arming.is_empty() or Time.get_ticks_msec() < int(_arming.at_ms):
		return
	for action in ARM_RELEASE_ACTIONS:
		if Input.is_action_pressed(action):
			return
	var focus: Control = _arming.focus
	_restore_armed()
	if is_instance_valid(focus) and focus.is_visible_in_tree():
		focus.grab_focus()


## Give the waiting buttons back their focus and clicks, without focusing any.
func _restore_armed() -> void:
	for button in _arming.get("buttons", []):
		if is_instance_valid(button):
			(button as Control).focus_mode = Control.FOCUS_ALL
			(button as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	_arming = {}


## Keys still held from the ending (a gather, a skip) must not press a results
## button: the panel's buttons stay disabled until none of `actions` is held,
## then its first button takes focus. An empty panel name lifts any lock.
func lock_until_released(panel_name: String, actions: Array) -> void:
	_lift_input_lock()
	if not _panels.has(panel_name):
		return
	_input_lock = { "panel": panel_name, "actions": actions }
	for button: Button in _panels[panel_name].find_children("*", "Button", true, false):
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE


## Polled every frame, paused or not, ahead of the title-only work.
func _poll_input_lock() -> void:
	if _input_lock.is_empty():
		return
	for action in _input_lock.actions:
		if Input.is_action_pressed(action):
			return
	var panel: Control = _panels[_input_lock.panel]
	_lift_input_lock()
	Kit.focus_first_control(panel)


## Hand the locked panel's buttons back, whether the keys lifted or a new lock
## (or none) replaces this one.
func _lift_input_lock() -> void:
	if _input_lock.is_empty():
		return
	for button: Button in _panels[_input_lock.panel].find_children("*", "Button", true, false):
		button.disabled = false
		button.focus_mode = Control.FOCUS_ALL
	_input_lock = {}


# --- Title -------------------------------------------------------------------------

func _build_title() -> void:
	var panel := _screen("title", true, T.C_EMBER)
	# The title is a full-scene vista: no veil, so the sky runs unbroken from
	# the moon down to the furnace horizon.
	panel.get_node("Veil").hide()
	# Original menu art: the Threshold of the Descent tableau (scripts/title_tableau.gd).
	_title_tableau = TitleTableau.new()
	panel.add_child(_title_tableau)
	_title_tableau.candle_struck.connect(func() -> void: ui.cue.emit("footlight"))
	# No opaque modal card: a borderless, transparent holder lets the furnace
	# horizon, battlements and rising embers breathe around the menu.
	var content := Kit.dialog(panel, Vector2(440, 0), T.C_EMBER, 12, 20)
	var holder := panel.get_meta("dialog") as PanelContainer
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# The wordmark and entries share the frame's centre line; the knight and
	# landing sit in the left third, clear of the group.
	_title_holder = holder
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 0)

	# Wordmark alone carries the identity; bindings live behind CONTROLS.
	var stack := _build_title_stack("GRAVEFLAME", 70)
	content.add_child(stack)
	var breath := Control.new()
	breath.mouse_filter = Control.MOUSE_FILTER_IGNORE
	breath.custom_minimum_size = Vector2(0.0, 26.0)
	content.add_child(breath)

	# One focused column: a single ember call to action over two quiet entries.
	var nav := VBoxContainer.new()
	nav.name = "TitleNav"
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 8)
	content.add_child(nav)
	var start := _title_entry(nav, "BEGIN DESCENT", "start", true, ui.start_requested.emit)
	var forge := _title_entry(nav, "THE FORGE", "forge", false, ui.forge_requested.emit)
	_title_controls_button = _title_entry(nav, "CONTROLS", "controls", false, toggle_title_controls)
	# OPTIONS goes after CONTROLS so the tested BEGIN > FORGE > CONTROLS pad focus chain holds.
	var options_button := _title_entry(nav, "OPTIONS", "options", false, ui.options_requested.emit)
	_title_nav_buttons = [start, forge, _title_controls_button, options_button]

	_build_title_controls_overlay(panel)
	# Victory candles keep clear of the lettering and the menu wherever layout
	# settles them: after each sort of the menu, and whenever the card moves.
	var sync := _sync_title_exclusions.bind(stack, _title_nav_buttons)
	holder.item_rect_changed.connect(sync)
	content.sort_children.connect(sync)
	nav.sort_children.connect(sync)


## One title menu entry. BEGIN is the bright ember button; the others get the
## quiet glass restyle below.
func _title_entry(nav: VBoxContainer, text: String, node_name: String, primary: bool, on_press: Callable) -> Button:
	var height := 54.0 if primary else 46.0
	var button := Kit.button(text, node_name, primary, Vector2(300, height))
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(on_press)
	if not primary:
		_title_quiet_button(button)
	nav.add_child(button)
	return button


## Title-only restyle: secondary entries sit on the vista as thin-edged glass so
## the ember BEGIN button is the single bright element. Focus stays a gold ring.
func _title_quiet_button(button: Button) -> void:
	var glass := Color(T.C_INK.r, T.C_INK.g, T.C_INK.b, 0.42)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", T.button_box(glass, Color(T.C_EDGE, 0.7), 1))
	button.add_theme_stylebox_override("hover", T.button_box(Color(T.C_SURFACE_HI, 0.75), T.C_EMBER_HI, 1))
	button.add_theme_stylebox_override("pressed", T.button_box(Color(T.C_SURFACE_HI, 0.85), T.C_GOLD, 2))
	button.add_theme_stylebox_override("focus", T.button_box(Color(T.C_SURFACE_HI, 0.6), T.C_GOLD, 2))
	button.add_theme_color_override("font_color", T.C_MUTED)


## Compact CONTROLS overlay: hidden by default, toggled by the CONTROLS button,
## closed by ui_cancel (Esc / pad B). While open it is modal: the title buttons
## lose focus eligibility so keyboard and pad navigation cannot leave the card.
func _build_title_controls_overlay(panel: Control) -> void:
	var overlay := Control.new()
	overlay.name = "ControlsOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	var dim := Kit.sheet(overlay, Color(0.02, 0.015, 0.03, 0.72), Control.PRESET_FULL_RECT, true)
	dim.name = "Dim"
	var center := CenterContainer.new()
	center.name = "ControlsCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 24.0
	center.offset_top = 20.0
	center.offset_right = -24.0
	center.offset_bottom = -20.0
	var card := Kit.passive_panel(center, T.panel_box(Color("100d18f2"), T.C_EDGE, 12, 1, 14), Vector2(520, 0))
	card.name = "ControlsCard"
	var stack := Kit.padded_stack(card, 26, 14, 3)
	stack.add_child(Kit.label("CONTROLS", 30, T.C_TEXT))
	stack.add_child(Kit.ornament(T.C_EMBER))
	# Rendered from the LIVE input map, so this screen can never disagree with
	# what the game actually does -- including after a rebind.
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 12)
	stack.add_child(header)
	var corner := Kit.label("", 11, T.C_EMBER_HI, HORIZONTAL_ALIGNMENT_LEFT)
	corner.size_flags_stretch_ratio = 1.1
	header.add_child(corner)
	for caption in ["KEYBOARD", "GAMEPAD"]:
		header.add_child(Kit.label(caption, 11, T.C_EMBER_HI, HORIZONTAL_ALIGNMENT_RIGHT))
	var cells := {}
	for row in Content.CONTROLS_ROWS:
		var action := str(row.action)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 12)
		stack.add_child(line)
		var name_label := Kit.label(str(row.label), 12, T.C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.size_flags_stretch_ratio = 1.1
		line.add_child(name_label)
		var key_label := Kit.label("", 12, T.C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		line.add_child(key_label)
		var pad_label := Kit.label("", 12, T.C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		line.add_child(pad_label)
		cells[action] = { "key": key_label, "pad": pad_label }
	stack.add_child(Kit.label(Content.CONTROLS_HINTS, 11, T.C_MUTED))
	overlay.set_meta("control_cells", cells)
	var close := Kit.button("CLOSE", "close_controls", false, Vector2(200, 46))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.visible = false
	close.pressed.connect(toggle_title_controls)
	stack.add_child(close)
	# Focus trap: every neighbour of CLOSE is CLOSE itself.
	var self_path := close.get_path_to(close)
	close.focus_neighbor_top = self_path
	close.focus_neighbor_bottom = self_path
	close.focus_neighbor_left = self_path
	close.focus_neighbor_right = self_path
	close.focus_next = self_path
	close.focus_previous = self_path
	overlay.set_meta("close_button", close)
	_title_controls = overlay
	# Assigned before syncing: the refresh reads the cells off the overlay meta.
	sync_controls()


## Repaint the controls card from the live input map. Called whenever a binding
## changes, so the reference screen is never stale.
func sync_controls() -> void:
	if _title_controls == null:
		return
	var cells = _title_controls.get_meta("control_cells", null)
	if not (cells is Dictionary):
		return
	for action in cells:
		var text := UiInput.binding_text(str(action))
		var pair: Dictionary = cells[action]
		(pair["key"] as Label).text = str(text["key"])
		(pair["pad"] as Label).text = str(text["pad"])


func toggle_title_controls() -> void:
	if _title_controls == null:
		return
	_set_title_controls_open(not _title_controls.visible)


func _set_title_controls_open(open: bool) -> void:
	if _title_controls == null:
		return
	_title_controls.visible = open
	var close := _title_controls.get_meta("close_button", null) as Button
	if close != null:
		close.visible = open
	for button in _title_nav_buttons:
		if is_instance_valid(button):
			(button as Button).focus_mode = Control.FOCUS_NONE if open else Control.FOCUS_ALL
	if open:
		if close != null:
			close.grab_focus.call_deferred()
	elif is_instance_valid(_title_controls_button):
		_title_controls_button.grab_focus.call_deferred()


## The wordmark's whole band and the column of menu buttons, in global space: a
## candle flame in the lettering's rows would read as stray title ink.
func _sync_title_exclusions(stack: Control, buttons: Array) -> void:
	var frame := (_panels["title"] as Control).get_global_rect()
	var band := stack.get_global_rect().grow(8.0)
	var menu: Rect2 = (buttons[0] as Control).get_global_rect()
	for button: Control in buttons:
		menu = menu.merge(button.get_global_rect())
	_title_tableau.set_exclusions([
		Rect2(frame.position.x, band.position.y, frame.size.x, band.size.y),
		menu.grow(12.0),
	])


## A win since the title last showed strikes its candle once; the save then
## remembers it, so later arrivals find it already burning.
func _celebrate_new_victories() -> void:
	var legacy: Dictionary = _title_tableau.legacy
	var seen := int(legacy.celebrated)
	if int(legacy.victories) <= seen:
		return
	_title_tableau.celebrate(seen)
	var save_api: Script = Save
	if save_api.has_method("set_last_celebrated"):
		save_api.call("set_last_celebrated", int(legacy.victories))


func _build_title_stack(text: String, size_px: int) -> Control:
	# Three stacked labels: void drop shadow, ember-rimmed orange core, gold face.
	# The stack takes the lettering's real width: a bare Control never grows to
	# its children, and an overflowing centred label would slide its text right.
	var stack := Control.new()
	stack.name = "TitleStack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var font := T.title_font()
	var shadow := Kit.label(text, size_px, VFX.VOID)
	shadow.add_theme_color_override("font_outline_color", VFX.VOID)
	shadow.add_theme_constant_override("outline_size", 4)
	var rim := Kit.label(text, size_px, VFX.ORANGE)
	rim.add_theme_color_override("font_outline_color", VFX.EMBER)
	rim.add_theme_constant_override("outline_size", 2)
	# A white face tinted by self_modulate, so the flicker never restyles it.
	var face := Kit.label(text, size_px, Color.WHITE)
	face.self_modulate = VFX.GOLD
	face.add_theme_constant_override("outline_size", 0)
	var offsets := [5.0, 2.0, 0.0]
	var layers := [shadow, rim, face]
	for i in range(layers.size()):
		var layer_label: Label = layers[i]
		layer_label.add_theme_font_override("font", font)
		stack.add_child(layer_label)
		layer_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer_label.offset_top = offsets[i]
		layer_label.offset_bottom = offsets[i]
	# Measure the run on the font itself: a label outside the tree has no theme
	# context yet, so its minimum size cannot be trusted here.
	var run := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px)
	stack.custom_minimum_size = Vector2(run.x + 8.0, maxf(font.get_height(size_px), float(size_px) * 1.2) + 8.0)
	_title_top_label = face
	return stack


## Firelight wobble on the title face and the menu fade-up during the tableau
## reveal; both frozen under reduced motion (the tableau hides its own embers).
func _animate_title(delta: float) -> void:
	if _title_top_label == null:
		return
	var title_panel: Control = _panels.get("title", null)
	if title_panel == null or not title_panel.visible:
		return
	var still := Feedback.motion_reduced
	var reveal := 1.0 if _title_tableau == null else float(_title_tableau.reveal)
	if _title_holder != null:
		var fade := 1.0 if still else clampf(0.35 + 0.65 * (reveal - 0.2) / 0.7, 0.35, 1.0)
		_title_holder.modulate = Color(1.0, 1.0, 1.0, fade)
	if still:
		_title_top_label.self_modulate = VFX.GOLD
		return
	_title_t += delta
	var wave := 0.5 + 0.5 * sin(_title_t * 2.6)
	var flicker := 1.0 + sin(_title_t * 11.0) * 0.03 + sin(_title_t * 29.0) * 0.03
	var col := VFX.GOLD.lerp(VFX.ORANGE, wave * 0.4)
	# Modulating rather than overriding font_color avoids reshaping the wordmark every frame.
	_title_top_label.self_modulate = Color(col.r * flicker, col.g * flicker, col.b * flicker, 1.0)


# --- Pause -------------------------------------------------------------------------

func _build_pause() -> void:
	var panel := _screen("pause", false, T.C_BLUE)
	var content := Kit.dialog(panel, Vector2(640, 0), T.C_BLUE, 48, 32)
	content.add_theme_constant_override("separation", 10)

	content.add_child(Kit.label("DESCENT SUSPENDED", 13, T.C_BLUE))
	content.add_child(Kit.label("PAUSED", 50, T.C_TEXT))
	content.add_child(Kit.label("The keep will wait. Catch your breath.", 16, T.C_MUTED))
	content.add_child(Kit.separator(T.C_EDGE))

	var actions := Kit.button_row(content)
	var resume := Kit.button("RESUME", "resume", true, Vector2(200, 54))
	resume.pressed.connect(ui.resume_requested.emit)
	actions.add_child(resume)
	var options_button := Kit.button("OPTIONS", "pause_options", false, Vector2(200, 54))
	options_button.pressed.connect(ui.options_requested.emit)
	actions.add_child(options_button)
	_quit_button = Kit.button("QUIT TO TITLE", "quit", false, Vector2(200, 54))
	_quit_button.pressed.connect(_on_quit_pressed)
	actions.add_child(_quit_button)

	# The descent so far: boons carried, relics, vows and the seed.
	var ledger := Kit.padded_stack(Kit.passive_panel(content, T.panel_box(T.C_INK, T.C_EDGE, 10, 1, 0)), 22, 14, 8)
	ledger.add_child(Kit.label("THIS DESCENT", 12, T.C_EMBER_HI, HORIZONTAL_ALIGNMENT_LEFT))
	_descent_grid = GridContainer.new()
	_descent_grid.columns = 8
	_descent_grid.add_theme_constant_override("h_separation", 8)
	_descent_grid.add_theme_constant_override("v_separation", 8)
	ledger.add_child(_descent_grid)
	_descent_detail = Kit.label("", 13, T.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	_descent_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_descent_detail.custom_minimum_size.y = 36.0
	ledger.add_child(_descent_detail)
	_descent_relics = Kit.label("", 12, T.C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	ledger.add_child(_descent_relics)
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ledger.add_child(foot)
	_descent_vows = Kit.label("", 12, T.C_RED, HORIZONTAL_ALIGNMENT_LEFT)
	foot.add_child(_descent_vows)
	_descent_seed = Kit.label("", 12, T.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	foot.add_child(_descent_seed)
	set_descent({}, 0)

	var footer := Kit.label("", 12, T.C_MUTED)
	content.add_child(footer)
	panel.set_meta("footer_label", footer)


## Fill the pause card's ledger: a medallion per boon carried (with its stack
## count), the relics owned, the vows sworn and the seed. Called as the pause
## card opens, so it always shows the descent as it stands.
func set_descent(taken: Dictionary, seed_value: int) -> void:
	Kit.clear_children(_descent_grid)
	var defs := {}
	for u in Content.UPGRADES:
		defs[u.id] = u
	for id in taken:
		if defs.has(id):
			_descent_grid.add_child(_descent_tile(defs[id], int(taken[id])))
	_descent_detail.text = "No boons yet. The first chamber waits." if taken.is_empty() else "Focus a boon to read it."
	var relics: Array = []
	for u in Content.META_UPGRADES:
		var rank := Save.get_meta_rank(str(u.id))
		if rank > 0:
			relics.append("%s %s" % [str(u.title).to_upper(), Kit.roman(rank)])
	_descent_relics.text = "RELICS   " + ("  ·  ".join(relics) if not relics.is_empty() else "none yet")
	var vows: Array = []
	if Save.vows_unlocked():
		for v in Content.VOWS:
			if Save.get_vows().has(v.id):
				vows.append(str(v.title).trim_prefix("Vow of ").to_upper())
	_descent_vows.text = ("SWORN   " + "  ·  ".join(vows)) if not vows.is_empty() else ""
	_descent_seed.text = ("SEED  %d" % seed_value) if seed_value != 0 else ""


## One boon in the ledger: a focusable medallion with a ×N badge for stacks.
## Focusing or hovering it writes its name and effect under the grid, so the
## ledger reads the same on a pad as with a mouse.
func _descent_tile(upgrade: Dictionary, count: int) -> Button:
	var rc := Content.rarity_color(Content.upgrade_rarity(upgrade))
	var tile := Button.new()
	tile.name = "Taken_%s" % upgrade.id
	tile.custom_minimum_size = Vector2(56, 56)
	tile.focus_mode = Control.FOCUS_ALL
	tile.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	for state in ["hover", "focus", "pressed"]:
		tile.add_theme_stylebox_override(state, T.panel_box(Color(T.C_SURFACE_HI, 0.6), T.C_GOLD, 8, 1, 0))
	var medallion := Kit.BoonMedallion.new()
	medallion.setup(str(upgrade.id), rc, Content.upgrade_rarity(upgrade) == "epic", Vector2(52, 52))
	tile.add_child(medallion)
	medallion.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if count > 1:
		var badge := Kit.label("×%d" % count, 13, T.C_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		badge.add_theme_constant_override("outline_size", 4)
		badge.add_theme_color_override("font_outline_color", T.C_VOID)
		tile.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -30.0
		badge.offset_top = -20.0
	var stack := "  ×%d" % count if count > 1 else ""
	var line := "%s%s  —  %s" % [str(upgrade.title).to_upper(), stack, str(upgrade.desc)]
	tile.focus_entered.connect(func(): _descent_detail.text = line)
	return tile


## QUIT TO TITLE abandons the descent, so the first press only asks: the
## button reads ABANDON DESCENT? in red for two seconds, and a second press
## within them quits.
func _on_quit_pressed() -> void:
	if _quit_confirm != null and _quit_confirm.is_valid():
		_set_quit_warning(false)
		ui.quit_to_title_requested.emit()
		return
	_set_quit_warning(true)
	_quit_confirm = Kit.tween(self)
	_quit_confirm.tween_interval(2.0)
	_quit_confirm.tween_callback(_set_quit_warning.bind(false))


func _set_quit_warning(on: bool) -> void:
	Kit.kill_tween(_quit_confirm)
	_quit_confirm = null
	_quit_button.text = "ABANDON DESCENT?" if on else "QUIT TO TITLE"
	Kit.style_button(_quit_button, false)
	if on:
		for state in ["normal", "hover", "focus"]:
			_quit_button.add_theme_stylebox_override(state, T.button_box(Color("3a1418"), T.C_RED, 2))
		_quit_button.add_theme_color_override("font_focus_color", T.C_RED)


# --- The boon deal -----------------------------------------------------------------

func _build_reward() -> void:
	var panel := _screen("reward", false, T.C_GOLD)
	# No enclosing card: the boons lie on the dimmed chamber like cards dealt
	# onto a table, so the choice is the only object on screen.
	var content := Kit.dialog(panel, Vector2(1000, 0), T.C_GOLD, 12, 8)
	var holder := panel.get_meta("dialog") as PanelContainer
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 6)

	content.add_child(Kit.label("CHAMBER CLEARED", 13, T.C_MINT))
	content.add_child(Kit.label("Choose a Boon", 46, T.C_TEXT))
	content.add_child(Kit.label("Every chamber feeds the flame.", 15, T.C_MUTED))
	content.add_child(Kit.ornament(T.C_GOLD))

	_upgrade_row = HBoxContainer.new()
	_upgrade_row.name = "UpgradeChoices"
	_upgrade_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_upgrade_row.add_theme_constant_override("separation", 26)
	content.add_child(_upgrade_row)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(gap)
	var footer := Kit.label("", 12, T.C_MUTED)
	content.add_child(footer)
	panel.set_meta("footer_label", footer)


## One boon card. The Button IS the card frame, so focus, hover and click stay a
## single control; the children are plain labels. Rarity is carried by the
## coloured top edge, border weight and medallion ring, not by text alone.
func _upgrade_card(index: int, upgrade: Dictionary, rarity: String, rc: Color, width: float) -> Button:
	var epic := rarity == "epic"
	var edge_w := 3 if epic else 2
	var paper := Color("1c1725")
	var button := Button.new()
	button.custom_minimum_size = Vector2(width, 318)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", T.card_box(paper, rc.darkened(0.3), edge_w))
	button.add_theme_stylebox_override("hover", T.card_box(paper.lightened(0.05), rc, edge_w + 1))
	button.add_theme_stylebox_override("focus", T.card_box(paper.lightened(0.05), rc.lightened(0.25), edge_w + 1))
	button.add_theme_stylebox_override("pressed", T.card_box(paper.lightened(0.1), T.C_GOLD, edge_w + 1))

	var margin := Kit.margin(22, 22, 16, 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)

	# The index is a live keyboard shortcut, so printing it is not decoration.
	var key := Kit.label("%d" % (index + 1), 12, T.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	stack.add_child(key)

	var sigil := Kit.BoonMedallion.new()
	sigil.setup(str(upgrade.get("id", "")), rc, epic)
	stack.add_child(sigil)

	var title := Kit.label(str(upgrade.get("title", "Unknown Boon")), 25, T.C_TEXT)
	title.add_theme_font_override("font", T.heading_font())
	stack.add_child(title)
	var desc := Kit.label(str(upgrade.get("desc", "")), 14, T.C_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc.custom_minimum_size = Vector2(width - 52.0, 0)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(desc)
	# Rarity sits at the foot of the card, where a printed card keeps its set mark.
	var foot := rarity.to_upper()
	if bool(upgrade.get("unique", false)):
		foot += "  ·  ONCE PER DESCENT"
	stack.add_child(Kit.label(foot, 11, rc))
	# Lift toward the hand under focus; hovering a card focuses it.
	button.focus_entered.connect(_lift_card.bind(button, true))
	button.focus_exited.connect(_lift_card.bind(button, false))
	return button


func _lift_card(button: Button, up: bool) -> void:
	if not is_instance_valid(button) or Feedback.motion_reduced:
		return
	button.pivot_offset = button.size * Vector2(0.5, 1.0)
	var t := Kit.tween(self)
	t.tween_property(button, "scale", Vector2.ONE * (1.035 if up else 1.0), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Deal the offered cards in, one after another, turning flat as they land.
func _deal_cards(buttons: Array) -> void:
	if Feedback.motion_reduced:
		return
	for i in range(buttons.size()):
		var b: Button = buttons[i]
		b.modulate = Color(1.0, 1.0, 1.0, 0.0)
		b.scale = Vector2.ONE * 0.9
		b.rotation = (float(i) - float(buttons.size() - 1) * 0.5) * 0.09
		b.pivot_offset = b.custom_minimum_size * Vector2(0.5, 1.0)
		var t := Kit.tween(self)
		t.tween_interval(0.06 + float(i) * 0.08)
		t.set_parallel(true)
		t.tween_property(b, "modulate:a", 1.0, 0.18)
		t.tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func setup_upgrades(upgrades: Array) -> void:
	if _upgrade_row == null:
		return
	Kit.clear_children(_upgrade_row)
	var buttons: Array = []
	var count := upgrades.size()
	# Three cards keep the full width; the Seer's Eye fourth narrows them all
	# so the row still fits the frame.
	var width := minf(292.0, (1180.0 - 26.0 * float(count - 1)) / float(maxi(1, count)))
	for i in range(count):
		var upgrade: Dictionary = upgrades[i]
		var rarity := Content.upgrade_rarity(upgrade)
		var rc: Color = Content.rarity_color(rarity)
		var button := _upgrade_card(i, upgrade, rarity, rc, width)
		button.name = "Boon%d" % i
		button.pressed.connect(ui.upgrade_selected.emit.bind(i))
		_upgrade_row.add_child(button)
		buttons.append(button)
	(_panels["reward"] as Control).set_meta("buttons", buttons)
	_paint_reward_footer()
	_deal_cards(buttons)
	# The cards arm once the deal has landed, so a jump pressed on the way
	# through the rift cannot take a boon unread.
	var deal := 0.35 if Feedback.motion_reduced else 0.36 + 0.08 * float(count - 1)
	if not buttons.is_empty():
		_arm_buttons(buttons, deal, buttons[0])


## Keyboard players pick a card by its number or a click; a pad player
## confirms the focused card.
func _paint_reward_footer() -> void:
	var panel: Control = _panels["reward"]
	var text := "%s  to take the chosen boon" % UiInput.prompt("ui_accept")
	if UiInput.last_device == "key":
		var count: int = (panel.get_meta("buttons", []) as Array).size()
		var keys: Array = range(1, count + 1).map(func(n: int): return str(n))
		text = "%s  or  click to take a boon" % " · ".join(keys)
	(panel.get_meta("footer_label") as Label).text = text


# --- The fall and the victory ------------------------------------------------------

func _build_game_over() -> void:
	# See-through: the fallen knight stays in the frame behind the verdict.
	var panel := _screen("gameover", false, T.C_RED)
	var content := Kit.dialog(panel, Vector2(760, 620), T.C_RED, 48, 30)
	content.add_theme_constant_override("separation", 10)

	content.add_child(Kit.label("THE KNIGHT FALLS", 13, T.C_RED))
	content.add_child(Kit.label("THE FLAME FADES", 54, T.C_TEXT))
	var epitaph := Kit.label(Content.EPITAPHS[0], 18, T.C_MUTED)
	content.add_child(epitaph)
	panel.set_meta("line_label", epitaph)
	content.add_child(Kit.separator(Color("75414b")))
	var retry := Kit.button("DESCEND AGAIN", "restart", true, Vector2(250, 56))
	_build_run_end_body(panel, content, Color("75414b"), "Return stronger, or descend again while the embers are warm.", retry)


func _build_victory() -> void:
	var panel := _screen("victory", false, T.C_MINT)
	var content := Kit.dialog(panel, Vector2(760, 640), T.C_MINT, 48, 30)
	content.add_theme_constant_override("separation", 10)

	var kicker := Kit.label("WARDEN DEFEATED", 13, T.C_MINT)
	content.add_child(kicker)
	panel.set_meta("kicker_label", kicker)
	content.add_child(Kit.label("GRAVEFLAME ENDURES", 50, T.C_TEXT))
	var closing := Kit.label("", 17, T.C_MUTED)
	content.add_child(closing)
	panel.set_meta("line_label", closing)
	content.add_child(Kit.separator(T.C_MINT))
	var again := Kit.button("DESCEND AGAIN", "again", true, Vector2(230, 56))
	_build_run_end_body(panel, content, Color("1f5b52"), "A brighter ember waits at the beginning.", again)
	# A first win points to the vows, just above the parting line.
	var vows := Kit.label("VOWS AWAKEN AT THE FORGE.", 14, T.C_GOLD)
	vows.visible = false
	content.add_child(vows)
	content.move_child(vows, content.get_child_count() - 3)
	panel.set_meta("vows_label", vows)


## Everything below the verdict on the game-over and victory screens. The
## headline result leads: the score and the standing best give it context, so
## a personal record is obvious at a glance instead of buried in the grid with
## six equally weighted tiles. Then the cells banked, the run's statistics, a
## parting line, and `again` (which restarts) beside RETURN TO TITLE.
func _build_run_end_body(panel: Control, content: VBoxContainer, tile_edge: Color, parting: String, again: Button) -> void:
	content.add_child(Kit.label("SCORE", 11, T.C_MUTED))
	var score := Kit.label("0", 44, T.C_TEXT)
	content.add_child(score)
	var best := Kit.label("BEST  0", 12, T.C_MUTED)
	content.add_child(best)
	panel.set_meta("score_label", score)
	panel.set_meta("best_label", best)
	var cells := Kit.label("CELLS SECURED  +0", 20, T.C_GOLD)
	cells.visible = false
	content.add_child(cells)
	panel.set_meta("cells_label", cells)
	_build_summary(content, panel, tile_edge)
	content.add_child(Kit.label(parting, 14, T.C_MUTED))
	var actions := Kit.button_row(content)
	again.pressed.connect(ui.restart_requested.emit)
	actions.add_child(again)
	var title := Kit.button("RETURN TO TITLE", "title", false, Vector2(230, 56))
	title.pressed.connect(ui.quit_to_title_requested.emit)
	actions.add_child(title)
	panel.set_meta("buttons", [again, title])
	# Centred in the fixed-height card, so the spare room frames the result
	# instead of pooling under the buttons.
	content.alignment = BoxContainer.ALIGNMENT_CENTER


## Six run statistics in a compact grid; filled by show_run_summary.
func _build_summary(content: VBoxContainer, panel: Control, edge: Color) -> void:
	var grid := GridContainer.new()
	grid.name = "RunSummary"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	var labels := {}
	for entry in [["time", "TIME"], ["kills", "KILLS"], ["elites", "ELITES"], ["streak", "BEST STREAK"], ["damage", "DAMAGE DEALT"], ["rooms", "CHAMBERS"]]:
		var tile := Kit.passive_panel(grid, T.panel_box(T.C_INK, edge, 8, 1, 0), Vector2(0, 52))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var stack := Kit.padded_stack(tile, 10, 4, 0)
		stack.add_child(Kit.label(entry[1], 10, T.C_MUTED))
		var value := Kit.label("-", 17, T.C_TEXT)
		stack.add_child(value)
		labels[entry[0]] = value
	panel.set_meta("summary_labels", labels)


## The victory card names which flame this was ("THE FOURTH FLAME") and, on the
## first win, tells the player the vows have woken in the Forge.
func set_victory_extras(ordinal: String, first: bool) -> void:
	var panel: Control = _panels["victory"]
	(panel.get_meta("kicker_label") as Label).text = "WARDEN DEFEATED  ·  " + ordinal if ordinal != "" else "WARDEN DEFEATED"
	(panel.get_meta("vows_label") as Label).visible = first


func show_run_cells(cells_earned: int, panel_name: String, vows_kept: int = 0) -> void:
	var cells_label := (_panels[panel_name] as Control).get_meta("cells_label") as Label
	cells_label.text = "CELLS SECURED  +%s" % Kit.format_number(cells_earned)
	if vows_kept > 0:
		var noun := "VOW" if vows_kept == 1 else "VOWS"
		cells_label.text += "   ·   %d %s KEPT" % [vows_kept, noun]
	cells_label.visible = true


func show_run_summary(stats: Dictionary, panel_name: String) -> void:
	var panel: Control = _panels[panel_name]
	if stats.has("line"):
		(panel.get_meta("line_label") as Label).text = str(stats.line)
	# The headline result is set before the grid so it never depends on it.
	var score_label := panel.get_meta("score_label") as Label
	score_label.text = Kit.format_number(int(stats.get("score", 0)))
	# Set both text and colour every time: the panel is reused between runs,
	# so a previous record's gold must not persist onto a lesser run.
	var best_label := panel.get_meta("best_label") as Label
	var record := bool(stats.get("new_best", false))
	best_label.text = "NEW BEST" if record else "BEST  %s" % Kit.format_number(int(stats.get("best", 0)))
	var best_color := T.C_GOLD if record else T.C_MUTED
	best_label.add_theme_color_override("font_color", best_color)
	var labels: Dictionary = panel.get_meta("summary_labels")
	var seconds := int(float(stats.get("time", 0.0)))
	var values := {
		"time": "%d:%02d" % [seconds / 60, seconds % 60],
		"kills": Kit.format_number(int(stats.get("kills", 0))),
		"elites": Kit.format_number(int(stats.get("elites", 0))),
		"streak": "x%d" % int(stats.get("best_streak", 0)),
		"damage": Kit.format_number(int(stats.get("damage_dealt", 0.0))),
		"rooms": "%d / %d" % [int(stats.get("rooms", 0)), int(stats.get("rooms_total", 0))],
	}
	for key in values:
		(labels[key] as Label).text = str(values[key])


# --- The Forge ---------------------------------------------------------------------

func _build_forge() -> void:
	var panel := _screen("forge", true, T.C_EMBER)
	var content := Kit.dialog(panel, Vector2(900, 650), T.C_EMBER, 42, 30)
	content.add_theme_constant_override("separation", 9)

	content.add_child(Kit.label("BETWEEN LIVES", 12, T.C_EMBER_HI))
	content.add_child(Kit.label("THE FORGE", 46, T.C_TEXT))
	content.add_child(Kit.label("Temper the next life with cells carried out of the keep.", 15, T.C_MUTED))

	var balance_panel := PanelContainer.new()
	balance_panel.add_theme_stylebox_override("panel", T.panel_box(T.C_INK, Color("715026"), 9, 1, 0))
	content.add_child(balance_panel)
	var balance := Kit.label("AVAILABLE CELLS   0", 18, T.C_GOLD)
	balance.custom_minimum_size.y = 38.0
	balance_panel.add_child(balance)
	panel.set_meta("balance_label", balance)

	_forge_rows = Kit.scroll_list(content, 350.0, 8)

	var back := Kit.button("BACK", "back", false, Vector2(220, 50), "ui_back")
	back.pressed.connect(ui.back_from_forge_requested.emit)
	Kit.button_row(content).add_child(back)
	panel.set_meta("back_button", back)


func setup_forge(cells: int) -> void:
	var panel: Control = _panels["forge"]
	var balance := panel.get_meta("balance_label") as Label
	balance.text = "AVAILABLE CELLS   %s" % Kit.format_number(cells)
	var kept := Kit.focused_name_in(_forge_rows)
	Kit.clear_children(_forge_rows)

	for i in range(Content.META_UPGRADES.size()):
		var upgrade: Dictionary = Content.META_UPGRADES[i]
		var id := str(upgrade.get("id", ""))
		var rank := Save.get_meta_rank(id)
		var max_rank := Content.meta_max_rank(upgrade)
		var next_cost := Content.meta_next_cost(upgrade, rank)
		var mastered := next_cost < 0
		var edge := Color("715026") if rank > 0 else Color("3b3147")
		var line := _forge_row(68.0, edge, 8)

		var sigil := Kit.BoonSigil.new()
		# Forge rows are shorter than cards, so the sigil takes a fixed square.
		sigil.setup(id, T.C_GOLD if rank > 0 else T.C_EMBER_HI, Vector2(46.0, 46.0))
		line.add_child(sigil)

		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 1)
		line.add_child(copy)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		copy.add_child(head)
		var name_label := Kit.label(str(upgrade.get("title", "Upgrade")).to_upper(), 14, T.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		head.add_child(name_label)
		head.add_child(Kit.rank_pips(rank, max_rank))
		copy.add_child(Kit.label(str(upgrade.get("desc", "")), 12, T.C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))

		var buy := Kit.button("MASTERED" if mastered else "%d CELLS" % next_cost, "Buy%d" % i, false, Vector2(132, 44), "")
		buy.disabled = mastered or cells < next_cost
		if mastered:
			buy.add_theme_color_override("font_disabled_color", T.C_MINT)
		else:
			buy.pressed.connect(ui.buy_meta_requested.emit.bind(i))
		line.add_child(buy)

	_build_vow_rows()
	# A purchase or vow rebuilds every row: the cursor stays on the row it was
	# on, so a second press can never buy a relic the player did not choose.
	var back := panel.get_meta("back_button") as Button
	(func() -> void: Kit.focus_row(_forge_rows, kept, back)).call_deferred()


## One ledger row in the forge; its edge colour marks what is owned or sworn.
## Returns the row's content line.
func _forge_row(height: float, edge: Color, pad_y: int) -> HBoxContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = height
	row.add_theme_stylebox_override("panel", T.panel_box(T.C_INK, edge, 8, 1, 0))
	_forge_rows.add_child(row)
	var margin := Kit.margin(16, 12, pad_y, pad_y)
	row.add_child(margin)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	margin.add_child(line)
	return line


## Vows sit under the relics: burdens rather than purchases, sworn or unsworn
## for free once the Warden has fallen, each paying out in score and cells.
func _build_vow_rows() -> void:
	var head := Kit.label("VOWS", 13, T.C_RED, HORIZONTAL_ALIGNMENT_LEFT)
	head.custom_minimum_size.y = 34.0
	_forge_rows.add_child(head)
	if not Save.vows_unlocked():
		_forge_rows.add_child(Kit.label("Defeat the Ember Warden to swear vows.", 12, T.C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
		return
	var record := Save.load_save()
	var kept: Array = record.get("vows_kept_ever", [])
	_forge_rows.add_child(Kit.label(roll_line(record), 12, T.C_GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	var sworn := Save.get_vows()
	_forge_rows.add_child(Kit.label("Sworn vows make the next descent harsher.  Score ×%s" % String.num(Content.vow_score_multiplier(sworn), 2), 12, T.C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	for i in range(Content.VOWS.size()):
		var v: Dictionary = Content.VOWS[i]
		var on := sworn.has(str(v.id))
		var edge := Color("8e3c49") if on else Color("3b3147")
		var line := _forge_row(58.0, edge, 6)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 1)
		line.add_child(copy)
		copy.add_child(Kit.label(str(v.title).to_upper(), 14, T.C_RED if on else T.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT))
		copy.add_child(Kit.label("%s   +%d%% score" % [str(v.desc), roundi(float(v.score) * 100.0)], 12, T.C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
		if kept.has(str(v.id)):
			line.add_child(Kit.kept_seal())
		var toggle := Kit.button("SWORN" if on else "SWEAR", "Vow%d" % i, on, Vector2(132, 40), "")
		toggle.pressed.connect(ui.vow_toggled.emit.bind(str(v.id)))
		line.add_child(toggle)


## The Forge's tally of every descent: flames won, knights fallen (a "+" when
## deaths from before the count began are unknown) and the hardest oath kept.
static func roll_line(record: Dictionary) -> String:
	var flames := int(record.get("victories", 0))
	var fallen := "%d%s" % [int(record.get("falls", 0)), "+" if bool(record.get("falls_legacy", false)) else ""]
	var oath := "HIGHEST OATH %d OF %d" % [int(record.get("best_vows", 0)), Content.VOWS.size()]
	if bool(record.get("oath_kept", false)):
		oath = "THE FIVEFOLD OATH IS KEPT"
	return "THE ROLL  ·  %d %s  ·  %s FALLEN  ·  %s" % [flames, "FLAME" if flames == 1 else "FLAMES", fallen, oath]


# --- Options -----------------------------------------------------------------------

## Settings screen: reachable from the title and from the pause menu, so audio
## and accessibility are not locked behind starting a run.
func _build_options() -> void:
	var panel := _screen("options", true, T.C_EMBER)
	var content := Kit.dialog(panel, Vector2(880, 0), T.C_EMBER, 44, 28)
	content.add_theme_constant_override("separation", 8)

	content.add_child(Kit.label("SETTINGS", 12, T.C_EMBER_HI))
	content.add_child(Kit.label("OPTIONS", 44, T.C_TEXT))
	content.add_child(Kit.separator(T.C_EDGE))

	# Two columns, so the screen has room to grow without scrolling.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	content.add_child(columns)
	var sound := VBoxContainer.new()
	var seen := VBoxContainer.new()
	for column in [sound, seen]:
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 8)
		columns.add_child(column)

	sound.add_child(Kit.label("AUDIO", 12, T.C_EMBER_HI, HORIZONTAL_ALIGNMENT_LEFT))
	_slider_row(sound, "Master volume", "master", 0.9)
	_slider_row(sound, "Music", "music", 0.75)
	_slider_row(sound, "Effects", "sfx", 0.9)
	_option_check(sound, "music_on", "Score", "The procedural score and the Warden's theme.")

	seen.add_child(Kit.label("DISPLAY", 12, T.C_EMBER_HI, HORIZONTAL_ALIGNMENT_LEFT))
	_option_check(seen, "fullscreen", "Fullscreen", "Fill the display instead of a window.")
	_option_check(seen, "vibration", "Controller vibration", "The pad rumbles with hits, parries and falls.")
	seen.add_child(Kit.label("ACCESSIBILITY", 12, T.C_EMBER_HI, HORIZONTAL_ALIGNMENT_LEFT))
	# Shake on its own, so a player can calm the camera and keep the hit-stop
	# and slow motion that reduced motion also takes away.
	_slider_row(seen, "Screen shake", "shake", 1.0)
	_reduced_motion_check = _option_check(seen, "reduced_motion", "Reduced motion", "Disables camera shake and softens particles.")
	_option_check(seen, "reduced_flash", "Reduced flash", "Reduces high-contrast impact flashes.")

	var footer := Kit.button_row(content)
	var keys := Kit.button("KEYS", "options_keys", false, Vector2(200, 50))
	keys.pressed.connect(ui.keys_requested.emit)
	footer.add_child(keys)
	var back := Kit.button("BACK", "options_back", false, Vector2(200, 50), "ui_back")
	back.pressed.connect(ui.back_from_options_requested.emit)
	footer.add_child(back)
	panel.set_meta("back_button", back)


## Volume row: a caption, a live percentage readout and the slider itself.
## Registered by key so sync_options can restore it without emitting signals.
func _slider_row(parent: VBoxContainer, title: String, key: String, value: float) -> void:
	var row := VBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 1)
	parent.add_child(row)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(head)
	head.add_child(Kit.label(title, 14, T.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	var readout := Kit.label("%d%%" % roundi(value * 100.0), 12, T.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	readout.size_flags_horizontal = Control.SIZE_SHRINK_END
	head.add_child(readout)
	var slider := HSlider.new()
	slider.name = "Opt_%s" % key
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 20)
	slider.focus_mode = Control.FOCUS_ALL
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Kit.paper_slider(slider)
	row.add_child(slider)
	slider.value_changed.connect(func(v: float):
		readout.text = "%d%%" % roundi(v * 100.0)
		ui.option_value_changed.emit(key, v)
	)
	_option_sliders[key] = { "slider": slider, "readout": readout }


## A toggle bound to Save option `key`, registered so sync_options can
## restore it without emitting.
func _option_check(parent: Container, key: String, title: String, description: String) -> CheckBox:
	var box := Kit.check(title, description)
	parent.add_child(box)
	_option_checks[key] = box
	box.toggled.connect(func(value: bool): ui.option_toggled.emit(key, value))
	return box


## Reflect the persisted options onto the controls without re-emitting signals,
## so opening the screen can never overwrite a setting with a stale widget.
func sync_options(opts: Dictionary) -> void:
	for key in _option_sliders:
		var entry: Dictionary = _option_sliders[key]
		var slider: HSlider = entry["slider"]
		var value := clampf(float(opts.get(key, slider.value)), 0.0, 1.0)
		slider.set_value_no_signal(value)
		(entry["readout"] as Label).text = "%d%%" % roundi(value * 100.0)
	for key in _option_checks:
		(_option_checks[key] as CheckBox).set_pressed_no_signal(bool(opts.get(key, false)))


# --- Key bindings ------------------------------------------------------------------

## Rebinding screen. Rows come from Content.CONTROLS_ROWS so this list and the
## controls reference can never disagree about what is rebindable.
func _build_keys() -> void:
	var panel := _screen("keys", true, T.C_EMBER)
	var content := Kit.dialog(panel, Vector2(720, 660), T.C_EMBER, 44, 28)
	content.add_theme_constant_override("separation", 8)

	content.add_child(Kit.label("SETTINGS", 12, T.C_EMBER_HI))
	content.add_child(Kit.label("KEY BINDINGS", 42, T.C_TEXT))
	var note := Kit.label(KEYS_HELP, 13, T.C_MUTED)
	content.add_child(note)
	panel.set_meta("note_label", note)
	content.add_child(Kit.separator(T.C_EDGE))

	_key_rows = Kit.scroll_list(content, 300.0, 5)

	content.add_child(Kit.label("Gamepad bindings are fixed and always live.", 12, T.C_MUTED))
	var footer := Kit.button_row(content)
	var restore := Kit.button("RESTORE DEFAULTS", "keys_restore", false, Vector2(220, 50))
	restore.pressed.connect(_restore_default_keys)
	footer.add_child(restore)
	var back := Kit.button("BACK", "keys_back", false, Vector2(220, 50), "ui_back")
	back.pressed.connect(func():
		_cancel_rebind()
		ui.back_from_keys_requested.emit()
	)
	footer.add_child(back)
	panel.set_meta("back_button", back)


## Rebuild the rebinding rows against the live input map. The facade repaints
## every prompt first.
func sync_keys() -> void:
	if _key_rows == null:
		return
	_cancel_rebind()
	var kept := Kit.focused_name_in(_key_rows)
	Kit.clear_children(_key_rows)
	for row in Content.CONTROLS_ROWS:
		var action := str(row.action)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		_key_rows.add_child(line)
		var row_label := Kit.label(str(row.label), 14, T.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		line.add_child(row_label)
		# Empty cue kind: the label changing to "PRESS A KEY" is the feedback, and
		# a confirm blip here would imply a commit that has not happened yet.
		var button := Kit.button(UiInput.key_text_for(action), "Key_%s" % action, false, Vector2(200, 40), "")
		button.pressed.connect(_begin_rebind.bind(action, button))
		line.add_child(button)
	# A rebind rebuilds the list under the cursor: stay on the same row.
	if not kept.is_empty():
		(func() -> void: Kit.focus_row(_key_rows, kept, null)).call_deferred()


func _begin_rebind(action: String, button: Button) -> void:
	_cancel_rebind()
	_listening_action = action
	_listening_button = button
	button.text = "PRESS A KEY…"


func _cancel_rebind() -> void:
	if not _listening_action.is_empty() and _listening_button != null and is_instance_valid(_listening_button):
		_listening_button.text = UiInput.key_text_for(_listening_action)
	_listening_action = ""
	_listening_button = null


## The pending rebind takes this key; Escape stays reserved for cancelling.
## A key another action already holds is taken from it: that action keeps
## its other keys, or, when this was its only one, takes the rebound
## action's old key, so no action is ever left unbound or doubled.
func _capture_rebind(code: int) -> void:
	if code == KEY_ESCAPE:
		_cancel_rebind()
		return
	if code == 0:
		return
	var action := _listening_action
	_listening_action = ""
	_listening_button = null
	var old_keys := UiInput.key_codes(action)
	var note := ""
	for row in Content.CONTROLS_ROWS:
		var other := str(row.action)
		var keys := UiInput.key_codes(other)
		if other == action or not keys.has(code):
			continue
		keys.erase(code)
		var kept: int = keys[0] if not keys.is_empty() else (old_keys[0] if not old_keys.is_empty() else 0)
		ui.binding_changed.emit(other, kept)
		note = "%s gives up %s  ·  now %s" % [str(row.label), OS.get_keycode_string(code), UiInput.key_text_for(other)]
	ui.binding_changed.emit(action, code)
	_set_keys_note(note)


## The line under the Keys heading: what a rebind just moved, in gold, or the
## instructions when nothing has.
func _set_keys_note(note: String) -> void:
	var note_label := (_panels["keys"] as Control).get_meta("note_label") as Label
	note_label.text = note if not note.is_empty() else KEYS_HELP
	note_label.add_theme_color_override("font_color", T.C_GOLD if not note.is_empty() else T.C_MUTED)


## Put every rebindable action back on the project's default keys and forget
## the saved rebinds. Pad buttons are never rebound, so they are left alone.
func _restore_default_keys() -> void:
	_cancel_rebind()
	Save.clear_bindings()
	for row in Content.CONTROLS_ROWS:
		var action := str(row.action)
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		var setting: Dictionary = ProjectSettings.get_setting("input/" + action, {})
		for event in setting.get("events", []):
			if event is InputEventKey:
				InputMap.action_add_event(action, event)
	UiInput.refresh_prompts(self)
	sync_keys()
	sync_controls()
	_set_keys_note("Every key is back where the keep first set it.")
