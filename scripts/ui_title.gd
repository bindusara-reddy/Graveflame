extends "res://scripts/ui_screen.gd"
## The landing: the Threshold tableau is the whole screen, and the interface
## only whispers over it. The wordmark and a printer's rule, one ember call to
## action over three quiet entries that take paper only under focus, a prompt
## in the corner and, once the keep has something to tell, the roll of flames
## carried out and knights fallen.

const VFX := preload("res://scripts/vfx.gd")
const TitleTableau := preload("res://scripts/title_tableau.gd")

var tableau: Control
## The menu's borderless holder (the "dialog" meta); hidden while a sub-screen
## lies on the tableau, so nothing under the veil can take focus.
var holder: PanelContainer
## The wordmark's gold face, flickered by self_modulate.
var face: Label
## THE FORMS entry, which the Forms hand focus back to.
var forms_entry: Button
var _entries: Array = []
var _prompt: Control
var _roll: Label
var _t := 0.0


func build() -> void:
	# A full-scene vista: no veil, so the sky runs unbroken from the moon down
	# to the furnace horizon.
	tableau = TitleTableau.new()
	add_child(tableau)
	tableau.candle_struck.connect(func() -> void: ui.cue.emit("footlight"))
	# No opaque card: a borderless holder lets the furnace horizon and the
	# rising embers breathe around the menu, on the frame's centre line.
	var column := Kit.dialog(self, Vector2(440, 0), T.EMBER, T.S3, T.S5)
	holder = get_meta("dialog") as PanelContainer
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)

	var wordmark := _wordmark("GRAVEFLAME", 70)
	column.add_child(wordmark)
	var rule := Kit.ornament(T.GOLD)
	rule.custom_minimum_size = Vector2(0.0, 22.0)
	column.add_child(rule)
	gap(column, T.S4)

	var nav := VBoxContainer.new()
	nav.name = "TitleNav"
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", T.S1)
	column.add_child(nav)
	# The tested pad chain runs BEGIN > FORGE > FORMS, so SENSES comes last.
	_entry(nav, "BEGIN DESCENT", "start", ui.start_requested.emit)
	_entry(nav, "THE FORGE", "forge", ui.forge_requested.emit)
	forms_entry = _entry(nav, "THE FORMS", "controls", stage.toggle_title_controls)
	_entry(nav, "SENSES", "options", ui.options_requested.emit)

	_corner_notes()
	# Victory candles keep clear of the lettering, the menu and the roll
	# wherever layout settles them: after each sort, and whenever they move.
	var sync := _sync_exclusions.bind(wordmark)
	holder.item_rect_changed.connect(sync)
	column.sort_children.connect(sync)
	nav.sort_children.connect(sync)
	_roll.item_rect_changed.connect(sync)


## One entry. BEGIN is the ember slip; the rest are quiet words on the vista
## that take paper only under focus, so the call to action stays the single
## bright thing on the landing.
func _entry(nav: VBoxContainer, text: String, node_name: String, on_press: Callable) -> Button:
	var primary := _entries.is_empty()
	var button := Kit.button(text, node_name, Kit.PRIMARY if primary else Kit.QUIET, Vector2(300, 54 if primary else 46))
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(on_press)
	nav.add_child(button)
	if primary:
		gap(nav, T.S2)
	_entries.append(button)
	return button


## The prompt at the lower left and the roll at the lower right, small and in
## ink-haloed words, so the tableau stays the hero.
func _corner_notes() -> void:
	_prompt = Kit.prompt_link("ui_accept", "Choose")
	add_child(_prompt)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, T.S5)
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_roll = Kit.outlined(Kit.label("", T.VOICE, T.ASH, HORIZONTAL_ALIGNMENT_RIGHT), 4)
	_roll.name = "Roll"
	add_child(_roll)
	_roll.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, T.S5)
	_roll.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_roll.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Show the menu and its corner notes, or put them away while a sub-screen
## lies on the tableau (nothing under the veil may take focus or talk).
func show_menu(shown: bool) -> void:
	for part: Control in [holder, _prompt, _roll]:
		part.visible = shown


## Arrival: only a real arrival replays the tableau's reveal; stepping back
## from a sub-screen must not grey the menu out again.
func opened(from: String) -> void:
	tableau.arrive(not (from in UiScreens.TITLE_SUBSCREENS))
	_celebrate_new_victories()
	_roll.text = UiScreens.roll_line(Save.load_save(), false)
	Kit.focus_first_control(self)


## A win since the title last showed strikes its candle once; the save then
## remembers it, so later arrivals find it already burning.
func _celebrate_new_victories() -> void:
	var legacy: Dictionary = tableau.legacy
	var seen := int(legacy.celebrated)
	if int(legacy.victories) <= seen:
		return
	tableau.celebrate(seen)
	var save_api: Script = Save
	if save_api.has_method("set_last_celebrated"):
		save_api.call("set_last_celebrated", int(legacy.victories))


## The wordmark's whole band, the menu and the roll, in global space: a candle
## flame in the lettering's rows would read as stray title ink.
func _sync_exclusions(wordmark: Control) -> void:
	var frame_rect := get_global_rect()
	var band := wordmark.get_global_rect().grow(8.0)
	var menu: Rect2 = (_entries[0] as Control).get_global_rect()
	for entry: Control in _entries:
		menu = menu.merge(entry.get_global_rect())
	tableau.set_exclusions([
		Rect2(frame_rect.position.x, band.position.y, frame_rect.size.x, band.size.y),
		menu.grow(12.0),
		_roll.get_global_rect().grow(6.0),
	])


## Three stacked labels: a void drop shadow, an ember-rimmed orange core and
## a gold face. The stack takes the lettering's real width: a bare Control
## never grows to its children, and an overflowing centred label would slide
## its text right.
func _wordmark(text: String, size_px: int) -> Control:
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
	face = Kit.label(text, size_px, Color.WHITE)
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
	# Measured on the font itself: a label outside the tree has no theme
	# context yet, so its minimum size cannot be trusted here.
	var run := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px)
	stack.custom_minimum_size = Vector2(run.x + 8.0, maxf(font.get_height(size_px), float(size_px) * 1.2) + 8.0)
	return stack


## Firelight on the wordmark's face and the menu fading up through the
## tableau's reveal; both still under reduced motion (the tableau hides its
## own embers).
func tick(delta: float) -> void:
	if not visible:
		return
	var still := T.still()
	var reveal := float(tableau.reveal)
	var lit := 1.0 if still else clampf(0.35 + 0.65 * (reveal - 0.2) / 0.7, 0.35, 1.0)
	for part: Control in [holder, _prompt, _roll]:
		part.modulate.a = lit
	if still:
		face.self_modulate = VFX.GOLD
		return
	_t += delta
	var wave := 0.5 + 0.5 * sin(_t * 2.6)
	var flicker := 1.0 + sin(_t * 11.0) * 0.03 + sin(_t * 29.0) * 0.03
	var col := VFX.GOLD.lerp(VFX.ORANGE, wave * 0.4)
	# Modulating rather than overriding font_color avoids reshaping the wordmark every frame.
	face.self_modulate = Color(col.r * flicker, col.g * flicker, col.b * flicker, 1.0)
