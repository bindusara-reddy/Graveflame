class_name UiInput
extends RefCounted
## What the player presses, in words: live binding names per device, the key
## cap a prompt shows, and which device the player last touched. Static, so
## the HUD, the screens, the rooms and the finale all name keys the same way.

## Group of nodes that repaint their key prompts when the device or a
## binding changes; each implements refresh_prompts().
const PROMPT_GROUP := "ui_prompts"

## The device the player last touched, "key" (keyboard or mouse) or "pad".
## Every prompt names that device's binding.
static var last_device := "key"


## Godot's built-in ui_accept / ui_cancel ship keyboard-only here, so a pad
## could navigate menus but never activate or back out. Register A / B at
## runtime without touching the project input map or any gameplay action.
static func ensure_pad_menu_bindings() -> void:
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var action: String = pair[0]
		var button: int = pair[1]
		if not InputMap.has_action(action):
			continue
		var bound := false
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
				bound = true
		if not bound:
			var pad := InputEventJoypadButton.new()
			pad.button_index = button as JoyButton
			InputMap.action_add_event(action, pad)


## Godot 4 exposes no joypad-to-string API (only OS.get_keycode_string for keys),
## so pad names are mapped explicitly.
static func pad_button_name(index: int) -> String:
	match index:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_BACK: return "BACK"
		JOY_BUTTON_START: return "START"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "D-PAD UP"
		JOY_BUTTON_DPAD_DOWN: return "D-PAD DOWN"
		JOY_BUTTON_DPAD_LEFT: return "D-PAD LEFT"
		JOY_BUTTON_DPAD_RIGHT: return "D-PAD RIGHT"
	return "PAD %d" % index


static func pad_axis_name(axis: int, value: float) -> String:
	match axis:
		JOY_AXIS_LEFT_X: return "STICK RIGHT" if value > 0.0 else "STICK LEFT"
		JOY_AXIS_LEFT_Y: return "STICK DOWN" if value > 0.0 else "STICK UP"
		JOY_AXIS_RIGHT_X: return "R-STICK RIGHT" if value > 0.0 else "R-STICK LEFT"
		JOY_AXIS_RIGHT_Y: return "R-STICK DOWN" if value > 0.0 else "R-STICK UP"
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
	return "AXIS %d" % axis


## Human-readable text for an action's live bindings, split by device.
static func binding_text(action: String) -> Dictionary:
	var keys: Array = []
	var pads: Array = []
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				var code := event_keycode(event as InputEventKey)
				if code != 0:
					keys.append(OS.get_keycode_string(code))
			elif event is InputEventJoypadButton:
				pads.append(pad_button_name((event as InputEventJoypadButton).button_index))
			elif event is InputEventJoypadMotion:
				var motion := event as InputEventJoypadMotion
				pads.append(pad_axis_name(motion.axis, motion.axis_value))
	return { "key": " / ".join(keys), "pad": " / ".join(pads) }


## Key cap for `action` on the device last used, such as "[F]" or "[X]", so a
## prompt names the key the player actually presses, even after a rebind.
static func prompt(action: String) -> String:
	var text := binding_text(action)
	var names := str(text[last_device])
	if names.is_empty():
		names = str(text["pad" if last_device == "key" else "key"])
	return "[%s]" % names.get_slice(" / ", 0).to_upper()


## Fill each {action} token in `template` with that action's live prompt.
static func fill_prompts(template: String) -> String:
	var caps := {}
	for row in Content.CONTROLS_ROWS:
		caps[str(row.action)] = prompt(str(row.action))
	return template.format(caps)


## Follow the player between keyboard and pad. Returns whether the device
## changed, so the caller can repaint the prompts on screen.
static func track_device(event: InputEvent) -> bool:
	var device := last_device
	if (event is InputEventJoypadButton and event.is_pressed()) or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		device = "pad"
	elif (event is InputEventKey and event.is_pressed()) or event is InputEventMouseButton:
		device = "key"
	if device == last_device:
		return false
	last_device = device
	return true


## Repaint every key prompt under `node`'s tree (see PROMPT_GROUP).
static func refresh_prompts(node: Node) -> void:
	if node.is_inside_tree():
		node.get_tree().call_group(PROMPT_GROUP, "refresh_prompts")


## The key a binding stores: the physical key, or the logical one for events
## that carry no physical code.
static func event_keycode(key: InputEventKey) -> int:
	var code := int(key.physical_keycode)
	if code == 0:
		code = int(key.keycode)
	return code


## Physical keycodes bound to `action`, in binding order.
static func key_codes(action: String) -> Array:
	var codes: Array = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			codes.append(event_keycode(event as InputEventKey))
	return codes


## Keyboard text for one action, or a dash when nothing is bound.
static func key_text_for(action: String) -> String:
	var text := str(binding_text(action)["key"])
	return text if not text.is_empty() else "—"


## 1..9 select the matching boon card; anything else returns -1.
static func boon_index_for_key(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1
	return -1
