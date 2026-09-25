extends Control
## One full screen: a panel the stage (UiScreens) shows and hides, with the
## parts every page shares cut from the kit: the torn veil behind it, the sheet,
## its heading and the prompt footer. Each page (ui_title.gd, ui_pause.gd...)
## extends this, fills build(), and hears opened() each time it is shown.
## Key caps name the device last touched on their own (Kit.Glyph), so a page
## never repaints its prompts.

const Kit := preload("res://scripts/ui_kit.gd")
const T := preload("res://scripts/ui_theme.gd")

## The stage every page shares: arming, routing, the way back out.
var stage: UiScreens
## The facade whose signals a page raises, so game.gd listens in one place.
var ui: UI
## The box centring the page's sheet; settle() lays it down on arrival.
var frame: Control
## The panel name the stage knows the page by ("gameover", "keys"...).
var panel_id := ""


## Called once by the stage after the page is in the tree.
func mount(p_stage: UiScreens, panel_name: String) -> void:
	stage = p_stage
	ui = p_stage.ui
	panel_id = panel_name
	name = panel_name.capitalize() + "Screen"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build()


## Build the page, hidden. Every page overrides it.
func build() -> void:
	pass


## The page has just been shown; `from` is the panel shown before it. By
## default the first control takes focus and the sheet settles in.
func opened(_from: String) -> void:
	Kit.focus_first_control(self)
	settle()


# --- Parts every page shares -------------------------------------------------------

## The torn ink veil behind the page: `dim` darkens the world above and below
## the tear, `ink` is the tear's own opacity, `accent` its rim.
func veil(dim: float, ink: float, accent: Color) -> void:
	var v := Kit.PaperVeil.new()
	v.name = "Veil"
	v.dim = Color(T.INK_DEEP, dim)
	v.sheet = Color(T.INK, ink)
	v.rim = Color(accent, 0.35)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The page's sheet, centred, holding a padded column (returned). The sheet is
## the "dialog" meta the layout checks read.
func sheet(minimum: Vector2, accent: Color, pad_x := T.S7, pad_y := T.S6) -> VBoxContainer:
	var column := Kit.dialog(self, minimum, accent, pad_x, pad_y)
	column.add_theme_constant_override("separation", T.S2)
	frame = (get_meta("dialog") as Control).get_parent()
	return column


## Kicker and title, left-aligned like a ledger's head. Returns the kicker.
func heading(column: Container, kicker_text: String, title_text: String, kicker_color := T.EMBER_HI) -> Label:
	var kicker := Kit.label(kicker_text, T.CAPS, kicker_color, HORIZONTAL_ALIGNMENT_LEFT)
	column.add_child(kicker)
	column.add_child(Kit.label(title_text, T.TITLE, T.BONE, HORIZONTAL_ALIGNMENT_LEFT))
	return kicker


## The prompt bar a page ends with: `entries` are [actions, words] or, for a
## link the mouse can press too, [actions, words, node_name, on_press].
## Returns the bar; the link named `back_name` is the page's back_button.
func footer(column: Container, entries: Array, back_name := "") -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "Prompts"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", T.S6)
	column.add_child(bar)
	for entry: Array in entries:
		var link := Kit.prompt_link(entry[0], str(entry[1]), str(entry[2]) if entry.size() > 2 else "")
		if entry.size() > 3:
			link.pressed.connect(entry[3])
		bar.add_child(link)
		if not back_name.is_empty() and link.name == back_name:
			link.pressed.connect(ui.cue.emit.bind("ui_back"))
			set_meta("back_button", link)
	set_meta("footer", bar)
	return bar


## A press that cannot be undone asks first: `button` turns to wax and reads
## `ask` for two seconds, and only a second press within them runs `act`.
## `kind` is the button's own dress, put back when it stops asking.
func confirm_twice(button: Button, ask: String, kind: int, act: Callable) -> void:
	var rest := button.text
	button.pressed.connect(func() -> void:
		var asking: Tween = button.get_meta("asking") if button.has_meta("asking") else null
		if asking != null and asking.is_valid():
			_stop_asking(button, rest, kind)
			act.call()
			return
		button.text = ask
		Kit.style_button(button, Kit.DANGER)
		asking = Kit.tween(button)
		asking.tween_interval(2.0)
		asking.tween_callback(_stop_asking.bind(button, rest, kind))
		button.set_meta("asking", asking)
	)


func _stop_asking(button: Button, rest: String, kind: int) -> void:
	if button.has_meta("asking"):
		Kit.kill_tween(button.get_meta("asking"))
		button.remove_meta("asking")
	button.text = rest
	Kit.style_button(button, kind)


## A breathing space of `height` px in a column.
func gap(column: Container, height: float) -> Control:
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.custom_minimum_size = Vector2(0.0, height)
	column.add_child(space)
	return space


## A spring in a row: it pushes whatever follows to the row's far end.
func spring(row: HBoxContainer) -> void:
	var push := Control.new()
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(push)


## Lay the sheet down (see Kit.settle_in).
func settle() -> void:
	if frame != null:
		Kit.settle_in(frame)


## "MOVE LEFT" as the keep says it in a sentence: "Move left".
static func sentence(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1).to_lower()
