extends "res://scripts/ui_screen.gd"
## SENSES: what the knight hears, sees and holds, three pages of one ledger
## (HEARING · SIGHT · HAND) turned by ribbon tabs. Each setting is a row: its
## name in the keep's words over a plain caption on the left, its control in
## a column on the right. Reachable from the landing and from the pause, so
## sound and comfort never wait behind a descent.

## Width of the controls' column; every control starts at its left edge, so
## the focus flame runs down one line.
const SLOT_W := 300.0

## The Stillness switch (reduced motion); the menu contracts press it.
var reduced_motion: CheckBox
## key -> { slider, readout } for every level.
var sliders := {}
## Save option key -> its switch.
var checks := {}
var _tabs: Kit.Tabs
var _pages: Array = []


func build() -> void:
	veil(0.62, 0.94, T.EMBER)
	var column := sheet(Vector2(780, 0), T.EMBER, T.S7, T.S6)
	heading(column, "BY EAR, EYE AND HAND", "Senses")
	gap(column, T.S1)
	_tabs = Kit.tabs(["HEARING", "SIGHT", "HAND"])
	_tabs.tab_changed.connect(_turn_to)
	column.add_child(_tabs)
	column.add_child(Kit.separator(T.HAIRLINE))
	gap(column, T.S2)

	var pages := VBoxContainer.new()
	# As tall as the fullest page, so turning a page never jumps the sheet.
	pages.custom_minimum_size.y = 4.0 * 56.0
	column.add_child(pages)
	var hearing := _page(pages)
	_slider(hearing, "master", "The whole keep", "Master volume", 0.9)
	_slider(hearing, "music", "Hymns and dirges", "Music volume", 0.75)
	_slider(hearing, "sfx", "Blades and bones", "Effects volume", 0.9)
	_check(hearing, "music_on", "The keep's music", "The hymns and the Warden's theme.")
	var sight := _page(pages)
	_check(sight, "fullscreen", "The whole sight", "Fullscreen: fill the display, not a window.")
	# Shake on its own, so the camera can calm and keep the hit-stop and
	# slow motion that Stillness also takes away.
	_slider(sight, "shake", "The keep trembles", "Screen shake", 1.0)
	reduced_motion = _check(sight, "reduced_motion", "Stillness", "Reduced motion: a calm camera, softer embers.")
	_check(sight, "reduced_flash", "Soft light", "Reduced flash: tamer impact flashes.")
	var hand := _page(pages)
	_check(hand, "vibration", "The pad's pulse", "Vibration with hits, parries and falls.")
	var open := Kit.button("OPEN", "options_keys", Kit.SECONDARY, Vector2(120, 40))
	open.pressed.connect(ui.keys_requested.emit)
	_setting(hand, "The Forms", "Every key and pad button; change the keys.", open)
	_show_page(0)

	gap(column, T.S2)
	column.add_child(Kit.ornament(T.GOLD))
	footer(column, [
		[[UiInput.TAB_PREV, UiInput.TAB_NEXT], "Turn the page"],
		["ui_cancel", "Back", "options_back", ui.back_from_options_requested.emit],
	], "options_back")


func _page(pages: VBoxContainer) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", T.S2)
	pages.add_child(page)
	_pages.append(page)
	return page


## A setting's row: words on the left, `control` at the head of the controls'
## column. The words warm to gold while the control holds focus.
func _setting(page: VBoxContainer, title: String, caption: String, control: Control) -> void:
	var slot := HBoxContainer.new()
	slot.custom_minimum_size = Vector2(SLOT_W, 48.0)
	slot.add_theme_constant_override("separation", T.S3)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(control)
	var line := Kit.setting_row(title, caption, slot)
	page.add_child(line)
	var name_label := line.get_child(0).get_child(0) as Label
	control.focus_entered.connect(func() -> void: name_label.add_theme_color_override("font_color", T.GOLD))
	control.focus_exited.connect(func() -> void: name_label.add_theme_color_override("font_color", T.BONE))


## A level with its live percentage. Registered by key so sync can restore
## it without raising the signal.
func _slider(page: VBoxContainer, key: String, title: String, caption: String, value: float) -> void:
	var slider := Kit.slider("Opt_%s" % key, value)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var readout := Kit.label("%d%%" % roundi(value * 100.0), T.SMALL, T.ASH, HORIZONTAL_ALIGNMENT_RIGHT)
	readout.custom_minimum_size.x = 44.0
	readout.size_flags_horizontal = Control.SIZE_SHRINK_END
	_setting(page, title, caption, slider)
	slider.get_parent().add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = "%d%%" % roundi(v * 100.0)
		ui.option_value_changed.emit(key, v)
	)
	sliders[key] = { "slider": slider, "readout": readout }


## A switch bound to Save option `key`, registered so sync can restore it
## without raising the signal.
func _check(page: VBoxContainer, key: String, title: String, caption: String) -> CheckBox:
	var box := Kit.toggle()
	box.name = "Opt_%s" % key
	_setting(page, title, caption, box)
	box.toggled.connect(func(on: bool) -> void: ui.option_toggled.emit(key, on))
	checks[key] = box
	return box


func _show_page(index: int) -> void:
	for i in range(_pages.size()):
		(_pages[i] as Control).visible = i == index


## A page turned by the tabs. Focus left on the page now hidden follows to
## the new page's first control; focus on the tabs stays there.
func _turn_to(index: int) -> void:
	_show_page(index)
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null or not owner.is_visible_in_tree():
		Kit.focus_first_control(_pages[index])


## Opened: the page it was left on, its first control focused.
func opened(_from: String) -> void:
	Kit.focus_first_control(_pages[_tabs.current])
	settle()


## Reflect the saved options onto the controls without raising a signal, so
## opening the page can never overwrite a setting with a stale control.
func sync(opts: Dictionary) -> void:
	for key: String in sliders:
		var entry: Dictionary = sliders[key]
		var value := clampf(float(opts.get(key, (entry.slider as HSlider).value)), 0.0, 1.0)
		(entry.slider as HSlider).set_value_no_signal(value)
		(entry.readout as Label).text = "%d%%" % roundi(value * 100.0)
	for key: String in checks:
		(checks[key] as CheckBox).set_pressed_no_signal(bool(opts.get(key, false)))
