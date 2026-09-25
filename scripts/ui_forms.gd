extends "res://scripts/ui_screen.gd"
## THE FORMS: every stroke and guard, with the key and the pad button that
## make it, drawn as caps from the live input map so the page can never
## disagree with what the knight's hands actually do. Choosing a row listens
## for a new key; a key another form holds is traded, never doubled or lost.
## The pad's buttons are fixed, so their column only reads. The landing opens
## this page as its reference card and SENSES opens it to change keys: one
## page serves both.

const HELP := "Air slam: drop and blade in the air.  The gamepad is always ready."
## Width of the keyboard and gamepad cells, so both columns line up.
const KEY_W := 150.0
const PAD_W := 108.0

## Opened from the landing: its way back returns there, not to SENSES.
var from_title := false
## The rows' container (both columns and their heads).
var rows: VBoxContainer
## The form waiting for a keypress, "" when none is.
var listening_action := ""
var _note: Label
## action -> { key, pad }: the fixed-width holders of each form's caps.
var _cells := {}
## action -> { key, pad }: the caps cells now in those holders (the
## "control_cells" meta), each carrying its bindings as it reads them.
var _caps := {}
var _pulse: Tween


func build() -> void:
	veil(0.62, 0.94, T.EMBER)
	var column := sheet(Vector2(1100, 0), T.EMBER, T.S7, T.S5 + 4)
	heading(column, "EVERY STROKE, EVERY GUARD", "The Forms")
	column.add_child(Kit.separator(T.HAIRLINE))
	gap(column, T.S1)

	rows = VBoxContainer.new()
	rows.name = "KeyRows"
	column.add_child(rows)
	var table := HBoxContainer.new()
	table.add_theme_constant_override("separation", T.S7)
	rows.add_child(table)
	var half := ceili(Content.CONTROLS_ROWS.size() / 2.0)
	for part in [Content.CONTROLS_ROWS.slice(0, half), Content.CONTROLS_ROWS.slice(half)]:
		table.add_child(_column(part))
	set_meta("control_cells", _caps)

	gap(column, T.S1)
	column.add_child(Kit.separator(T.HAIRLINE))
	_note = Kit.label(HELP, T.SMALL, T.ASH)
	_note.custom_minimum_size.y = 30.0
	column.add_child(_note)
	set_meta("note_label", _note)

	var foot := HBoxContainer.new()
	column.add_child(foot)
	var restore := Kit.button("RESTORE EVERY KEY", "keys_restore", Kit.SECONDARY, Vector2(236, 44))
	confirm_twice(restore, "EVERY KEY, AS FIRST SET?", Kit.SECONDARY, _restore_default_keys)
	foot.add_child(restore)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(spacer)
	footer(foot, [["ui_accept", "Set a key"], ["ui_cancel", "Back", "keys_back", back]], "keys_back")
	repaint()


## One column of forms under its own KEYBOARD and GAMEPAD heads.
func _column(forms: Array) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", T.S1)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", T.S3)
	column.add_child(head)
	var lead := Control.new()
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(lead)
	for pair in [["KEYBOARD", KEY_W], ["GAMEPAD", PAD_W + T.S4]]:
		var caption := Kit.label(str(pair[0]), T.MICRO, T.EMBER_HI, HORIZONTAL_ALIGNMENT_RIGHT)
		caption.custom_minimum_size.x = float(pair[1])
		caption.size_flags_horizontal = Control.SIZE_SHRINK_END
		head.add_child(caption)
	for form: Dictionary in forms:
		column.add_child(_row(str(form.action), str(form.label)))
	return column


## A form: its name, then its keyboard caps and its gamepad caps. Choosing it
## listens for a new key. Empty cue: the lit cap is the feedback, and a
## confirm blip would imply a key taken before one has been pressed.
func _row(action: String, form_name: String) -> Button:
	var trailing := HBoxContainer.new()
	trailing.add_theme_constant_override("separation", T.S3)
	var cells := {}
	for pair in [["key", KEY_W], ["pad", PAD_W]]:
		var holder := HBoxContainer.new()
		holder.alignment = BoxContainer.ALIGNMENT_END
		holder.custom_minimum_size = Vector2(float(pair[1]), 26.0)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		trailing.add_child(holder)
		cells[pair[0]] = holder
	_cells[action] = cells
	_caps[action] = {}
	var row := Kit.row("Key_%s" % action, sentence(form_name), "", trailing, null, 44.0)
	row.pressed.connect(_begin_rebind.bind(action))
	return row


## Opened: the note goes back to the help, the first form takes focus.
func opened(_from: String) -> void:
	_set_note("")
	Kit.focus_first_control(rows)
	settle()


## Its one way back: to the landing when the landing opened it, else to SENSES.
func back() -> void:
	cancel_rebind()
	if from_title:
		stage.close_forms_to_title()
	else:
		ui.back_from_keys_requested.emit()


## Repaint every cell from the live input map, ending any rebind first.
func sync() -> void:
	cancel_rebind()
	repaint()


## Repaint every cell from the live input map. The rows stay, so focus never moves.
func repaint() -> void:
	for action: String in _cells:
		var text := UiInput.binding_text(action)
		for device in ["key", "pad"]:
			var holder: HBoxContainer = _cells[action][device]
			Kit.clear_children(holder)
			var cell := Kit.caps(Array(str(text[device]).split(" / ", false)), device)
			holder.add_child(cell)
			_caps[action][device] = cell


# --- Rebinding ---------------------------------------------------------------------

func listening() -> bool:
	return not listening_action.is_empty()


func _begin_rebind(action: String) -> void:
	cancel_rebind()
	listening_action = action
	var holder: HBoxContainer = _cells[action]["key"]
	Kit.clear_children(holder)
	var ask := Kit.label("PRESS A KEY", T.MICRO, T.EMBER_HI, HORIZONTAL_ALIGNMENT_RIGHT)
	holder.add_child(ask)
	var cap := Kit.glyph_for("?", "key")
	cap.lit = true
	holder.add_child(cap)
	# The waiting cap breathes, like a coal blown on; still under reduced motion.
	if not T.still():
		_pulse = Kit.tween(self).set_loops()
		_pulse.tween_property(holder, "modulate:a", 0.55, 0.45).set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(holder, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)


func cancel_rebind() -> void:
	Kit.kill_tween(_pulse)
	if listening():
		(_cells[listening_action]["key"] as Control).modulate.a = 1.0
		listening_action = ""
		repaint()


## A press while listening (the stage hands it over before menu navigation):
## a key is taken, Escape or any pad button gives up. Returns whether it was
## consumed.
func hear(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.is_echo():
		_capture_rebind(UiInput.event_keycode(event as InputEventKey))
		return true
	if event is InputEventJoypadButton and event.pressed:
		cancel_rebind()
		return true
	return false


## The pending rebind takes this key; Escape stays reserved for giving up.
## A key another form already holds is taken from it: that form keeps its
## other keys or, when this was its only one, takes the rebound form's old
## key, so no form is ever left without a key or sharing one.
func _capture_rebind(code: int) -> void:
	if code == KEY_ESCAPE:
		cancel_rebind()
		return
	if code == 0:
		return
	var action := listening_action
	Kit.kill_tween(_pulse)
	(_cells[action]["key"] as Control).modulate.a = 1.0
	listening_action = ""
	var old_keys := UiInput.key_codes(action)
	var note := ""
	for form: Dictionary in Content.CONTROLS_ROWS:
		var other := str(form.action)
		var keys := UiInput.key_codes(other)
		if other == action or not keys.has(code):
			continue
		keys.erase(code)
		var kept: int = keys[0] if not keys.is_empty() else (old_keys[0] if not old_keys.is_empty() else 0)
		ui.binding_changed.emit(other, kept)
		note = "%s gives up %s  ·  it keeps %s" % [sentence(str(form.label)), OS.get_keycode_string(code), UiInput.key_text_for(other)]
	ui.binding_changed.emit(action, code)
	ui.cue.emit("ui_confirm")
	repaint()
	_set_note(note)


## The line under the table: what a rebind just moved, in gold, or the help
## when nothing has.
func _set_note(note: String) -> void:
	_note.text = note if not note.is_empty() else HELP
	_note.add_theme_color_override("font_color", T.GOLD if not note.is_empty() else T.ASH)


## Put every form back on the keep's first keys and forget the saved ones.
## Pad buttons are never rebound, so they are left alone.
func _restore_default_keys() -> void:
	cancel_rebind()
	Save.clear_bindings()
	for form: Dictionary in Content.CONTROLS_ROWS:
		var action := str(form.action)
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		var setting: Dictionary = ProjectSettings.get_setting("input/" + action, {})
		for event in setting.get("events", []):
			if event is InputEventKey:
				InputMap.action_add_event(action, event)
	UiInput.refresh_prompts(self)
	ui.cue.emit("ui_confirm")
	repaint()
	_set_note("Every key is back where the keep first set it.")
