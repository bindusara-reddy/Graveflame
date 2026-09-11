class_name UI
extends CanvasLayer
## Responsive HUD and atmospheric screen overlays, built with Godot-native controls.

const VFX := preload("res://scripts/vfx.gd")
const TitleTableau := preload("res://scripts/title_tableau.gd")

signal start_requested
signal resume_requested
signal restart_requested
signal quit_to_title_requested
signal upgrade_selected(idx: int)
signal option_toggled(key: String, value: bool)
signal forge_requested
signal buy_meta_requested(idx: int)
signal back_from_forge_requested
## Menu feedback. Resolved to a synthesized cue by the game, so the UI never
## names a sound directly.
signal cue(kind: String)
signal options_requested
signal back_from_options_requested
## Continuous controls (volumes) report here; toggles keep option_toggled.
signal option_value_changed(key: String, value: float)
signal keys_requested
signal back_from_keys_requested
signal binding_changed(action: String, keycode: int)

const C_VOID := Color("09070f")
const C_INK := Color("100d18")
const C_SURFACE := Color("1b1624")
const C_SURFACE_HI := Color("282033")
const C_EDGE := Color("4b3e5b")
const C_TEXT := Color("eee8df")
const C_MUTED := Color("a99db2")
const C_EMBER := Color("ff7a18")
const C_EMBER_HI := Color("ffad4d")
const C_GOLD := Color("ffd166")
const C_MINT := Color("2be4c8")
const C_BLUE := Color("7fd4ff")
const C_RED := Color("dc5962")

var _root: Control
var _hud: Control

var _hp_bar: ProgressBar
var _hp_value_label: Label
var _special_bar: ProgressBar
var _special_value_label: Label
var _room_label: Label
var _wave_label: Label
var _score_label: Label
var _boss_panel: Control
var _boss_bar: ProgressBar
var _boss_label: Label
var _boss_value_label: Label
var _flask_container: HBoxContainer
var _flask_dots: Array = []
var _flask_count_label: Label
var _cells_label: Label
var _best_label: Label

var _room_clear_banner: Control
var _room_clear_name: Label

var _streak_panel: PanelContainer
var _streak_kills_label: Label
var _streak_mult_label: Label
var _streak_bar: ProgressBar
var _streak_tier := 0
var _streak_tween: Tween

var _room_intro: Dictionary = {}
var _boss_intro: Dictionary = {}
## One-time contextual lesson, shown low and out of the play space.
var _hint_panel: Control
var _hint_label: Label
var _hint_tween: Tween
var _boss_phase_tag: Label
var _boss_phase_tween: Tween
var _fade: ColorRect
var _music_check: CheckBox

var _panels: Dictionary = {}
var _upgrade_row: HBoxContainer
var _forge_rows: VBoxContainer
var _reduced_motion_check: CheckBox
var _reduced_flash_check: CheckBox
var _fullscreen_check: CheckBox
## key -> { slider, readout } for every volume control on the options screen.
var _option_sliders: Dictionary = {}
## Rebinding: the rows container and whichever action is awaiting a keypress.
var _key_rows: VBoxContainer
var _listening_action := ""
var _listening_button: Button

var _title_top_label: Label
var _title_embers: CPUParticles2D
var _title_tableau: Control
var _title_holder: Control
var _title_t := 0.0
var _last_panel := ""
var _title_controls: Control
var _title_controls_button: Button
var _title_nav_buttons: Array = []


func _ready() -> void:
	layer = 50
	_ensure_pad_menu_bindings()

	_root = Control.new()
	_root.name = "InterfaceRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Rift transition veil: sits under the HUD and every screen, above the world.
	_fade = ColorRect.new()
	_fade.name = "RiftFade"
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(C_VOID, 0.0)
	_root.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_hud()
	_build_title()
	_build_pause()
	_build_reward()
	_build_game_over()
	_build_victory()
	_build_forge()
	_build_options()
	_build_keys()

	hide_all_panels()
	show_panel("title")


## Godot's built-in ui_accept / ui_cancel ship keyboard-only here, so a pad
## could navigate menus but never activate or back out. Register A / B at
## runtime without touching the project input map or any gameplay action.
func _ensure_pad_menu_bindings() -> void:
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


# --- HUD ---------------------------------------------------------------------

func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "HUD"
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_player_status()
	_build_streak_meter()
	_build_run_status()
	_build_boss_status()
	_build_boss_phase_tag()
	_build_room_clear_banner()
	_room_intro = _build_banner("RoomIntro", 176.0, 258.0, Vector2(420, 70), 26, 11, C_EMBER, Color("14101ceb"))
	_boss_intro = _build_banner("BossIntro", 236.0, 372.0, Vector2(620, 118), 40, 14, C_RED, Color("1a0c11f0"))
	_build_hint()


## Teaching prompt: sits below the fight, clear of the fighters and the HUD.
func _build_hint() -> void:
	var center := CenterContainer.new()
	center.name = "HintBanner"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	center.offset_top = -112.0
	center.offset_bottom = -54.0
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_box(Color("0f0b16f2"), C_EMBER, 10, 1, 10))
	center.add_child(panel)
	var margin := _margin_container(26, 26, 9, 9)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	# This is the one line a new player must read, so it is set a step larger
	# than the ambient HUD text rather than matching it.
	_hint_label = _make_label("", 16, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	panel.add_child(_hint_label)
	_hint_panel = center
	_hint_panel.visible = false


func _build_streak_meter() -> void:
	_streak_panel = PanelContainer.new()
	_streak_panel.name = "StreakMeter"
	_streak_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streak_panel.add_theme_stylebox_override("panel", _panel_box(Color("1b1624d9"), Color("715026"), 10, 1, 8))
	_hud.add_child(_streak_panel)
	_streak_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_streak_panel.offset_left = 16.0
	_streak_panel.offset_top = 122.0
	_streak_panel.offset_right = 216.0
	_streak_panel.offset_bottom = 166.0
	_streak_panel.pivot_offset = Vector2(0.0, 25.0)
	var margin := _margin_container(14, 14, 8, 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streak_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 3)
	margin.add_child(stack)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	head.add_child(_make_label("STREAK", 11, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))
	_streak_kills_label = _make_label("2 KILLS", 13, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	head.add_child(_streak_kills_label)
	_streak_mult_label = _make_label("x1.25", 15, C_GOLD, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_streak_mult_label)
	_streak_bar = _make_bar(C_GOLD, Color("3a2c14"), 6.0)
	_streak_bar.max_value = 100.0
	_streak_bar.value = 100.0
	stack.add_child(_streak_bar)
	_streak_panel.visible = false


## Fading title card used for room entries and the boss reveal.
func _build_banner(node_name: String, top: float, bottom: float, minimum: Vector2, title_size: int, sub_size: int, accent: Color, background: Color) -> Dictionary:
	var center := CenterContainer.new()
	center.name = node_name
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = top
	center.offset_bottom = bottom
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_box(background, accent, 10, 1, 12))
	center.add_child(panel)
	var margin := _margin_container(28, 28, 10, 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 1)
	margin.add_child(stack)
	var sub := _make_label("", sub_size, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	stack.add_child(sub)
	var title := _make_label("", title_size, accent, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	stack.add_child(title)
	center.visible = false
	return { "root": center, "title": title, "sub": sub, "tween": null }


func _play_banner(banner: Dictionary, title: String, subtitle: String, hold: float) -> void:
	var root: Control = banner.root
	(banner.title as Label).text = title
	(banner.sub as Label).text = subtitle
	if banner.tween != null and is_instance_valid(banner.tween):
		(banner.tween as Tween).kill()
	root.visible = true
	root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(root, "modulate:a", 1.0, 0.22)
	tween.tween_interval(hold)
	tween.tween_property(root, "modulate:a", 0.0, 0.55)
	tween.tween_callback(func(): root.visible = false)
	banner.tween = tween


func _build_player_status() -> void:
	var panel := PanelContainer.new()
	panel.name = "PlayerStatus"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_box(Color("100c16b8"), Color("3a3048"), 8, 1, 6))
	_hud.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16.0
	panel.offset_top = 14.0
	panel.offset_right = 296.0
	panel.offset_bottom = 112.0

	var margin := _margin_container(12, 12, 8, 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)

	var hp_head := HBoxContainer.new()
	hp_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(hp_head)
	hp_head.add_child(_make_label("VITALITY", 10, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))
	_hp_value_label = _make_label("100 / 100", 11, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
	hp_head.add_child(_hp_value_label)
	_hp_bar = _make_bar(C_RED, Color("4a1820"), 12.0)
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	stack.add_child(_hp_bar)

	var sp_head := HBoxContainer.new()
	sp_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(sp_head)
	sp_head.add_child(_make_label("GRAVEFLAME", 10, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))
	_special_value_label = _make_label("0 / 100", 10, C_BLUE, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
	sp_head.add_child(_special_value_label)
	_special_bar = _make_bar(C_BLUE, Color("153243"), 7.0)
	_special_bar.max_value = 100.0
	_special_bar.value = 0.0
	stack.add_child(_special_bar)

	var supplies := HBoxContainer.new()
	supplies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	supplies.add_theme_constant_override("separation", 8)
	stack.add_child(supplies)
	var flask_tag := _make_label("FLASK", 10, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	flask_tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	supplies.add_child(flask_tag)
	_flask_container = HBoxContainer.new()
	_flask_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flask_container.add_theme_constant_override("separation", 5)
	_flask_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	supplies.add_child(_flask_container)
	_flask_count_label = _make_label("3 / 3  [F]", 10, C_MINT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
	_flask_count_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	supplies.add_child(_flask_count_label)
	_rebuild_flask_dots(Content.FLASK_MAX)


func _build_run_status() -> void:
	var panel := PanelContainer.new()
	panel.name = "RunStatus"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_box(Color("100c16b8"), Color("3a3048"), 8, 1, 6))
	_hud.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -226.0
	panel.offset_top = 14.0
	panel.offset_right = -16.0
	panel.offset_bottom = 132.0

	var margin := _margin_container(12, 12, 8, 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)

	_room_label = _make_label("ROOM 01 / 06", 12, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
	stack.add_child(_room_label)
	_wave_label = _make_label("", 11, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
	_wave_label.visible = false
	stack.add_child(_wave_label)
	stack.add_child(_separator(C_EDGE))
	_score_label = _make_stat_line(stack, "RUN SCORE", "0", C_TEXT)
	_cells_label = _make_stat_line(stack, "CELLS", "0", C_GOLD)
	_best_label = _make_stat_line(stack, "BEST", "0", C_MUTED)


func _build_boss_status() -> void:
	var center := CenterContainer.new()
	center.name = "BossStatusAnchor"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 18.0
	center.offset_bottom = 96.0

	var panel := PanelContainer.new()
	panel.name = "BossStatus"
	panel.custom_minimum_size = Vector2(470, 70)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_box(Color("221019e6"), Color("8e3c49"), 10, 1, 8))
	center.add_child(panel)
	_boss_panel = center

	var margin := _margin_container(18, 18, 10, 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	_boss_label = _make_label("THE EMBER WARDEN", 13, Color("f2c3c6"), HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	head.add_child(_boss_label)
	_boss_value_label = _make_label("420", 12, C_RED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_boss_value_label)
	_boss_bar = _make_bar(Color("b94350"), Color("41131b"), 13.0)
	_boss_bar.max_value = Content.BOSS_HP
	_boss_bar.value = Content.BOSS_HP
	stack.add_child(_boss_bar)
	_boss_panel.visible = false


func _build_boss_phase_tag() -> void:
	# Compact phase-2 callout pinned under the boss bar: never center-screen.
	_boss_phase_tag = _make_label("", 13, Color("f2c3c6"), HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	_boss_phase_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_phase_tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_phase_tag.offset_left = -260.0
	_boss_phase_tag.offset_right = 260.0
	_boss_phase_tag.offset_top = 100.0
	_boss_phase_tag.offset_bottom = 124.0
	_boss_phase_tag.visible = false
	_hud.add_child(_boss_phase_tag)


func _build_room_clear_banner() -> void:
	var center := CenterContainer.new()
	center.name = "RoomClearBanner"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 148.0
	center.offset_bottom = 252.0
	_room_clear_banner = center

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(490, 88)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_box(Color("141020eb"), C_MINT, 10, 1, 12))
	center.add_child(panel)
	var margin := _margin_container(24, 24, 10, 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 1)
	margin.add_child(stack)
	stack.add_child(_make_label("ROOM CLEARED", 22, C_MINT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	_room_clear_name = _make_label("PATH UNSEALED", 12, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	stack.add_child(_room_clear_name)
	_room_clear_banner.visible = false


# --- Screen construction -----------------------------------------------------

func _build_title() -> void:
	var panel := _screen("title", true, C_EMBER)
	# The title is a full-scene vista: drop the generic screen header band so
	# the sky runs unbroken from the moon down to the furnace horizon.
	for band_name in ["TopBand", "Horizon"]:
		var band := panel.get_node_or_null(band_name)
		if band != null:
			band.visible = false
	_build_title_scene(panel)
	# No opaque modal card: a borderless, transparent holder lets the furnace
	# horizon, battlements and rising embers breathe around the menu.
	var content := _dialog(panel, Vector2(440, 0), C_EMBER, 12, 20)
	var holder := panel.get_meta("dialog") as PanelContainer
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# The wordmark and entries share the frame's centre line; the knight and
	# landing sit in the left third, clear of the group.
	_title_holder = holder
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 0)

	# Wordmark alone carries the identity; bindings live behind CONTROLS.
	content.add_child(_build_title_stack("GRAVEFLAME", 70))
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
	var start := _button("BEGIN DESCENT", "start", true, Vector2(300, 54))
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(func(): emit_signal("start_requested"))
	nav.add_child(start)
	var forge := _button("THE FORGE", "forge", false, Vector2(300, 46))
	forge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	forge.pressed.connect(func(): emit_signal("forge_requested"))
	_title_quiet_button(forge)
	nav.add_child(forge)
	_title_controls_button = _button("CONTROLS", "controls", false, Vector2(300, 46))
	_title_controls_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_controls_button.pressed.connect(_toggle_title_controls)
	_title_quiet_button(_title_controls_button)
	nav.add_child(_title_controls_button)
	# Appended after CONTROLS so the existing pad focus chain is untouched.
	var options_button := _button("OPTIONS", "options", false, Vector2(300, 46))
	options_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options_button.pressed.connect(func(): emit_signal("options_requested"))
	_title_quiet_button(options_button)
	nav.add_child(options_button)
	_title_nav_buttons = [start, forge, _title_controls_button, options_button]

	_build_title_controls_overlay(panel)


## Title-only restyle: secondary entries sit on the vista as thin-edged glass so
## the ember BEGIN button is the single bright element. Focus stays a gold ring.
func _title_quiet_button(button: Button) -> void:
	var glass := Color(C_INK.r, C_INK.g, C_INK.b, 0.42)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _button_box(glass, Color(C_EDGE, 0.7), 1))
	button.add_theme_stylebox_override("hover", _button_box(Color(C_SURFACE_HI, 0.75), C_EMBER_HI, 1))
	button.add_theme_stylebox_override("pressed", _button_box(Color(C_SURFACE_HI, 0.85), C_GOLD, 2))
	button.add_theme_stylebox_override("focus", _button_box(Color(C_SURFACE_HI, 0.6), C_GOLD, 2))
	button.add_theme_color_override("font_color", C_MUTED)


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
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.color = Color(0.02, 0.015, 0.03, 0.72)
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.name = "ControlsCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 24.0
	center.offset_top = 20.0
	center.offset_right = -24.0
	center.offset_bottom = -20.0
	var card := PanelContainer.new()
	card.name = "ControlsCard"
	card.custom_minimum_size = Vector2(520, 0)
	card.add_theme_stylebox_override("panel", _panel_box(Color("100d18f2"), C_EDGE, 12, 1, 14))
	center.add_child(card)
	var margin := _margin_container(26, 26, 14, 14)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	margin.add_child(stack)
	stack.add_child(_make_label("CONTROLS", 20, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	stack.add_child(_separator(C_EDGE))
	# Rendered from the LIVE input map, so this screen can never disagree with
	# what the game actually does -- including after a rebind.
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 12)
	stack.add_child(header)
	var corner := _make_label("", 11, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	corner.size_flags_stretch_ratio = 1.1
	header.add_child(corner)
	for caption in ["KEYBOARD", "GAMEPAD"]:
		header.add_child(_make_label(caption, 11, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT))
	var cells := {}
	for row in Content.CONTROLS_ROWS:
		var action := str(row.action)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 12)
		stack.add_child(line)
		var name_label := _make_label(str(row.label), 12, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
		name_label.size_flags_stretch_ratio = 1.1
		line.add_child(name_label)
		var key_label := _make_label("", 12, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
		line.add_child(key_label)
		var pad_label := _make_label("", 12, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
		line.add_child(pad_label)
		cells[action] = { "key": key_label, "pad": pad_label }
	stack.add_child(_make_label(Content.CONTROLS_HINTS, 11, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	overlay.set_meta("control_cells", cells)
	var close := _button("CLOSE", "close_controls", false, Vector2(200, 46))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.visible = false
	close.pressed.connect(_toggle_title_controls)
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


## Godot 4 exposes no joypad-to-string API (only OS.get_keycode_string for keys),
## so pad names are mapped explicitly. These match the vocabulary the controls
## screen has always shown.
static func _pad_button_name(index: int) -> String:
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


static func _pad_axis_name(axis: int, value: float) -> String:
	match axis:
		JOY_AXIS_LEFT_X: return "STICK RIGHT" if value > 0.0 else "STICK LEFT"
		JOY_AXIS_LEFT_Y: return "STICK DOWN" if value > 0.0 else "STICK UP"
		JOY_AXIS_RIGHT_X: return "R-STICK RIGHT" if value > 0.0 else "R-STICK LEFT"
		JOY_AXIS_RIGHT_Y: return "R-STICK DOWN" if value > 0.0 else "R-STICK UP"
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
	return "AXIS %d" % axis


## Human-readable text for an action's live bindings, split by device.
static func _binding_text(action: String) -> Dictionary:
	var keys: Array = []
	var pads: Array = []
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key := event as InputEventKey
				var code := int(key.physical_keycode)
				if code == 0:
					code = int(key.keycode)
				if code != 0:
					keys.append(OS.get_keycode_string(code))
			elif event is InputEventJoypadButton:
				pads.append(_pad_button_name((event as InputEventJoypadButton).button_index))
			elif event is InputEventJoypadMotion:
				var motion := event as InputEventJoypadMotion
				pads.append(_pad_axis_name(motion.axis, motion.axis_value))
	return { "key": " / ".join(keys), "pad": " / ".join(pads) }


## Repaint the controls card from the live input map. Called whenever a binding
## changes, so the reference screen is never stale.
func sync_controls() -> void:
	if _title_controls == null:
		return
	var cells = _title_controls.get_meta("control_cells", null)
	if not (cells is Dictionary):
		return
	for action in cells:
		var text := _binding_text(str(action))
		var pair: Dictionary = cells[action]
		(pair["key"] as Label).text = str(text["key"])
		(pair["pad"] as Label).text = str(text["pad"])


func _toggle_title_controls() -> void:
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


## 1..9 select the matching boon card; anything else returns -1.
static func _boon_index_for_key(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1
	return -1


func _unhandled_input(event: InputEvent) -> void:
	# A pending rebind consumes the very next keypress, whatever it is.
	if not _listening_action.is_empty():
		if event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
			var key := event as InputEventKey
			var code := int(key.physical_keycode)
			if code == 0:
				code = int(key.keycode)
			if code == KEY_ESCAPE:
				_cancel_rebind()
			elif code != 0:
				var action := _listening_action
				_listening_action = ""
				_listening_button = null
				emit_signal("binding_changed", action, code)
			get_viewport().set_input_as_handled()
		return
	# Boon cards print their index, so the number keys have to actually pick one.
	if event is InputEventKey and event.pressed and not event.echo:
		var reward: Control = _panels.get("reward", null)
		if reward != null and reward.visible:
			var index := _boon_index_for_key((event as InputEventKey).keycode)
			var buttons = reward.get_meta("buttons", [])
			if index >= 0 and index < buttons.size():
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


func _build_pause() -> void:
	var panel := _screen("pause", false, C_BLUE)
	var content := _dialog(panel, Vector2(640, 600), C_BLUE, 48, 32)
	content.add_theme_constant_override("separation", 10)

	content.add_child(_make_label("RUN SUSPENDED", 13, C_BLUE, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("PAUSED", 54, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("The keep will wait. Catch your breath.", 16, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_separator(C_EDGE))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	var resume := _button("RESUME", "resume", true, Vector2(230, 54))
	resume.pressed.connect(func(): emit_signal("resume_requested"))
	actions.add_child(resume)
	var quit := _button("QUIT TO TITLE", "quit", false, Vector2(230, 54))
	quit.pressed.connect(func(): emit_signal("quit_to_title_requested"))
	actions.add_child(quit)
	var options_button := _button("OPTIONS", "pause_options", false, Vector2(230, 54))
	options_button.pressed.connect(func(): emit_signal("options_requested"))
	actions.add_child(options_button)

	var options_panel := PanelContainer.new()
	options_panel.add_theme_stylebox_override("panel", _panel_box(C_INK, C_EDGE, 10, 1, 0))
	content.add_child(options_panel)
	var options_margin := _margin_container(22, 22, 16, 16)
	options_panel.add_child(options_margin)
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 10)
	options_margin.add_child(options)
	options.add_child(_make_label("ACCESSIBILITY", 12, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))
	_reduced_motion_check = _check("Reduced motion", "Disables camera shake and softens particles.")
	_reduced_flash_check = _check("Reduced flash", "Reduces high-contrast impact flashes.")
	options.add_child(_reduced_motion_check)
	options.add_child(_reduced_flash_check)
	_reduced_motion_check.toggled.connect(func(value: bool): emit_signal("option_toggled", "reduced_motion", value))
	_reduced_flash_check.toggled.connect(func(value: bool): emit_signal("option_toggled", "reduced_flash", value))
	options.add_child(_make_label("SOUND", 12, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))
	_music_check = _check("Music", "Procedural ambient score and boss theme.")
	_music_check.button_pressed = true
	options.add_child(_music_check)
	_music_check.toggled.connect(func(value: bool): emit_signal("option_toggled", "music", value))

	content.add_child(_make_label("ESC  resume", 12, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))


func _build_reward() -> void:
	var panel := _screen("reward", false, C_GOLD)
	var content := _dialog(panel, Vector2(1140, 580), C_GOLD, 38, 34)
	content.add_theme_constant_override("separation", 11)

	content.add_child(_make_label("ROOM CLEARED", 13, C_MINT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("CHOOSE YOUR BOON", 42, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("The Graveflame changes with every victory.", 16, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_separator(C_GOLD))

	_upgrade_row = HBoxContainer.new()
	_upgrade_row.name = "UpgradeChoices"
	_upgrade_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_upgrade_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_upgrade_row.add_theme_constant_override("separation", 14)
	content.add_child(_upgrade_row)
	panel.set_meta("buttons", [])
	panel.set_meta("upgrade_row", _upgrade_row)

	content.add_child(_make_label("Select one boon to continue the descent.", 12, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))


func _build_game_over() -> void:
	var panel := _screen("gameover", true, C_RED)
	var content := _dialog(panel, Vector2(760, 620), C_RED, 48, 30)
	content.add_theme_constant_override("separation", 10)

	content.add_child(_make_label("RUN ENDED", 13, C_RED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("THE FLAME FADES", 54, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("Ash remembers every attempt.", 18, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_separator(Color("75414b")))
	_build_run_result(content, panel)
	var cells := _make_label("CELLS SECURED  +0", 20, C_GOLD, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	cells.visible = false
	content.add_child(cells)
	panel.set_meta("cells_label", cells)
	_build_summary(content, panel, Color("75414b"))
	content.add_child(_make_label("Return stronger, or descend again while the embers are warm.", 14, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	var retry := _button("DESCEND AGAIN", "restart", true, Vector2(250, 56))
	retry.pressed.connect(func(): emit_signal("restart_requested"))
	actions.add_child(retry)
	var title := _button("RETURN TO TITLE", "title", false, Vector2(230, 56))
	title.pressed.connect(func(): emit_signal("quit_to_title_requested"))
	actions.add_child(title)


func _build_victory() -> void:
	var panel := _screen("victory", true, C_MINT)
	var content := _dialog(panel, Vector2(760, 640), C_MINT, 48, 30)
	content.add_theme_constant_override("separation", 10)

	content.add_child(_make_label("WARDEN DEFEATED", 13, C_MINT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("GRAVEFLAME ENDURES", 50, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("The keep falls silent, but the descent is never the same twice.", 17, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_separator(C_MINT))
	_build_run_result(content, panel)
	var cells := _make_label("CELLS SECURED  +0", 20, C_GOLD, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	cells.visible = false
	content.add_child(cells)
	panel.set_meta("cells_label", cells)
	_build_summary(content, panel, Color("1f5b52"))
	content.add_child(_make_label("A brighter ember waits at the beginning.", 14, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	var again := _button("NEW RUN", "again", true, Vector2(230, 56))
	again.pressed.connect(func(): emit_signal("restart_requested"))
	actions.add_child(again)
	var title := _button("RETURN TO TITLE", "title", false, Vector2(230, 56))
	title.pressed.connect(func(): emit_signal("quit_to_title_requested"))
	actions.add_child(title)


## Headline result: the score leads the screen and the standing best gives it
## context, so a personal record is obvious at a glance instead of buried in
## the grid with six equally weighted tiles.
func _build_run_result(content: VBoxContainer, panel: Control) -> void:
	content.add_child(_make_label("RUN SCORE", 11, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	var score := _make_label("0", 44, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(score)
	var best := _make_label("BEST  0", 12, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(best)
	panel.set_meta("score_label", score)
	panel.set_meta("best_label", best)


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
		var tile := PanelContainer.new()
		tile.custom_minimum_size = Vector2(0, 52)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_theme_stylebox_override("panel", _panel_box(C_INK, edge, 8, 1, 0))
		grid.add_child(tile)
		var margin := _margin_container(10, 10, 4, 4)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(margin)
		var stack := VBoxContainer.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_theme_constant_override("separation", 0)
		margin.add_child(stack)
		stack.add_child(_make_label(entry[1], 10, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
		var value := _make_label("-", 17, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
		stack.add_child(value)
		labels[entry[0]] = value
	panel.set_meta("summary_labels", labels)


func _build_forge() -> void:
	var panel := _screen("forge", true, C_EMBER)
	var content := _dialog(panel, Vector2(900, 650), C_EMBER, 42, 30)
	content.add_theme_constant_override("separation", 9)

	content.add_child(_make_label("PERMANENT UPGRADES", 12, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("THE FORGE", 46, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("Temper the next life with cells carried out of the keep.", 15, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))

	var balance_panel := PanelContainer.new()
	balance_panel.add_theme_stylebox_override("panel", _panel_box(C_INK, Color("715026"), 9, 1, 0))
	content.add_child(balance_panel)
	var balance := _make_label("AVAILABLE CELLS   0", 18, C_GOLD, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	balance.custom_minimum_size.y = 38.0
	balance_panel.add_child(balance)
	panel.set_meta("balance_label", balance)

	var scroll := ScrollContainer.new()
	scroll.name = "ForgeScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 350.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_forge_rows = VBoxContainer.new()
	_forge_rows.name = "ForgeRows"
	_forge_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_forge_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_forge_rows)
	panel.set_meta("rows", _forge_rows)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(footer)
	var back := _button("BACK", "back", false, Vector2(220, 50), "ui_back")
	back.pressed.connect(func(): emit_signal("back_from_forge_requested"))
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
	head.add_child(_make_label(title, 14, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))
	var readout := _make_label("%d%%" % roundi(value * 100.0), 12, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
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
	row.add_child(slider)
	slider.value_changed.connect(func(v: float):
		readout.text = "%d%%" % roundi(v * 100.0)
		emit_signal("option_value_changed", key, v)
	)
	_option_sliders[key] = { "slider": slider, "readout": readout }


## Settings screen: reachable from the title and from the pause menu, so audio
## and accessibility are not locked behind starting a run.
func _build_options() -> void:
	var panel := _screen("options", true, C_EMBER)
	var content := _dialog(panel, Vector2(680, 620), C_EMBER, 48, 30)
	content.add_theme_constant_override("separation", 8)

	content.add_child(_make_label("SETTINGS", 12, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("OPTIONS", 44, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_separator(C_EDGE))

	content.add_child(_make_label("AUDIO", 12, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))
	_slider_row(content, "Master volume", "master", 0.9)
	_slider_row(content, "Music", "music", 0.75)
	_slider_row(content, "Effects", "sfx", 0.9)

	content.add_child(_make_label("DISPLAY", 12, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))
	_fullscreen_check = _check("Fullscreen", "Fill the display instead of running in a window.")
	content.add_child(_fullscreen_check)
	_fullscreen_check.toggled.connect(func(value: bool): emit_signal("option_toggled", "fullscreen", value))

	content.add_child(_make_label("ACCESSIBILITY", 12, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))
	_reduced_motion_check = _check("Reduced motion", "Disables camera shake and softens particles.")
	_reduced_flash_check = _check("Reduced flash", "Reduces high-contrast impact flashes.")
	content.add_child(_reduced_motion_check)
	content.add_child(_reduced_flash_check)
	_reduced_motion_check.toggled.connect(func(value: bool): emit_signal("option_toggled", "reduced_motion", value))
	_reduced_flash_check.toggled.connect(func(value: bool): emit_signal("option_toggled", "reduced_flash", value))

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)
	var keys := _button("KEYS", "options_keys", false, Vector2(200, 50))
	keys.pressed.connect(func(): emit_signal("keys_requested"))
	footer.add_child(keys)
	var back := _button("BACK", "options_back", false, Vector2(200, 50), "ui_back")
	back.pressed.connect(func(): emit_signal("back_from_options_requested"))
	footer.add_child(back)
	panel.set_meta("back_button", back)


## Reflect the persisted options onto the controls without re-emitting signals,
## so opening the screen can never overwrite a setting with a stale widget.
func sync_options(opts: Dictionary) -> void:
	for key in _option_sliders:
		var entry: Dictionary = _option_sliders[key]
		var slider: HSlider = entry["slider"]
		var value := clampf(float(opts.get(key, slider.value)), 0.0, 1.0)
		slider.set_value_no_signal(value)
		(entry["readout"] as Label).text = "%d%%" % roundi(value * 100.0)
	if _fullscreen_check != null:
		_fullscreen_check.set_pressed_no_signal(bool(opts.get("fullscreen", false)))
	if _reduced_motion_check != null:
		_reduced_motion_check.set_pressed_no_signal(bool(opts.get("reduced_motion", false)))
	if _reduced_flash_check != null:
		_reduced_flash_check.set_pressed_no_signal(bool(opts.get("reduced_flash", false)))
	if _music_check != null:
		_music_check.set_pressed_no_signal(bool(opts.get("music_on", true)))


## Keyboard text for one action, or a dash when nothing is bound.
static func _key_text_for(action: String) -> String:
	var text := str(_binding_text(action)["key"])
	return text if not text.is_empty() else "—"


## Rebinding screen. Rows come from Content.CONTROLS_ROWS so this list and the
## controls reference can never disagree about what is rebindable.
func _build_keys() -> void:
	var panel := _screen("keys", true, C_EMBER)
	var content := _dialog(panel, Vector2(720, 660), C_EMBER, 44, 28)
	content.add_theme_constant_override("separation", 8)

	content.add_child(_make_label("SETTINGS", 12, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("KEY BINDINGS", 42, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("Choose a key, then press the one you want.  ESC cancels.", 13, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_separator(C_EDGE))

	var scroll := ScrollContainer.new()
	scroll.name = "KeysScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 300.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_key_rows = VBoxContainer.new()
	_key_rows.name = "KeyRows"
	_key_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_rows.add_theme_constant_override("separation", 5)
	scroll.add_child(_key_rows)

	content.add_child(_make_label("Gamepad bindings are fixed and always live.", 12, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(footer)
	var back := _button("BACK", "keys_back", false, Vector2(220, 50), "ui_back")
	back.pressed.connect(func():
		_cancel_rebind()
		emit_signal("back_from_keys_requested")
	)
	footer.add_child(back)
	panel.set_meta("back_button", back)


## Rebuild the rebinding rows against the live input map.
func sync_keys(_bindings: Dictionary) -> void:
	if _key_rows == null:
		return
	_cancel_rebind()
	_clear_children(_key_rows)
	for row in Content.CONTROLS_ROWS:
		var action := str(row.action)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		_key_rows.add_child(line)
		var label := _make_label(str(row.label), 14, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
		line.add_child(label)
		# Empty cue kind: the label changing to "PRESS A KEY" is the feedback, and
		# a confirm blip here would imply a commit that has not happened yet.
		var button := _button(_key_text_for(action), "Key_%s" % action, false, Vector2(200, 40), "")
		button.pressed.connect(_begin_rebind.bind(action, button))
		line.add_child(button)


func _begin_rebind(action: String, button: Button) -> void:
	_cancel_rebind()
	_listening_action = action
	_listening_button = button
	button.text = "PRESS A KEY…"


func _cancel_rebind() -> void:
	if not _listening_action.is_empty() and _listening_button != null and is_instance_valid(_listening_button):
		_listening_button.text = _key_text_for(_listening_action)
	_listening_action = ""
	_listening_button = null


# --- Title scene ---------------------------------------------------------------

func _build_title_scene(panel: Control) -> void:
	# Original menu art: the Threshold of the Descent tableau (scripts/title_tableau.gd).
	_title_tableau = TitleTableau.new()
	panel.add_child(_title_tableau)
	_title_embers = _title_tableau.get_node("Embers") as CPUParticles2D


## Bundled title face: Noto Serif Display Bold (SIL OFL 1.1, fonts/), loaded
## from the shipped file so the wordmark never depends on the machine's fonts.
static var _wordmark_font: Font


static func _title_font() -> Font:
	if _wordmark_font == null:
		var file := FontFile.new()
		if file.load_dynamic_font("res://fonts/NotoSerifDisplay-Bold.ttf") == OK:
			var tracked := FontVariation.new()
			tracked.base_font = file
			tracked.spacing_glyph = 3
			_wordmark_font = tracked
		else:
			push_warning("Graveflame: wordmark font missing, using the theme font")
			_wordmark_font = ThemeDB.fallback_font
	return _wordmark_font


func _build_title_stack(text: String, size: int) -> Control:
	# Three stacked labels: void drop shadow, ember-rimmed orange core, gold face.
	# The stack takes the lettering's real width: a bare Control never grows to
	# its children, and an overflowing centred label would slide its text right.
	var stack := Control.new()
	stack.name = "TitleStack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var font := _title_font()
	var shadow := _make_label(text, size, VFX.VOID, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	shadow.add_theme_color_override("font_outline_color", VFX.VOID)
	shadow.add_theme_constant_override("outline_size", 4)
	var rim := _make_label(text, size, VFX.ORANGE, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	rim.add_theme_color_override("font_outline_color", VFX.EMBER)
	rim.add_theme_constant_override("outline_size", 2)
	var face := _make_label(text, size, VFX.GOLD, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	face.add_theme_constant_override("outline_size", 0)
	var offsets := [5.0, 2.0, 0.0]
	var layers := [shadow, rim, face]
	for i in range(layers.size()):
		var label: Label = layers[i]
		label.add_theme_font_override("font", font)
		stack.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_top = offsets[i]
		label.offset_bottom = offsets[i]
	# Measure the run on the font itself: a label outside the tree has no theme
	# context yet, so its minimum size cannot be trusted here.
	var run := font.get_string_size(text, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	stack.custom_minimum_size = Vector2(run.x + 8.0, maxf(font.get_height(size), float(size) * 1.2) + 8.0)
	_title_top_label = face
	return stack


func _process(delta: float) -> void:
	# Firelight wobble on the title face and the menu fade-up during the tableau
	# reveal; both frozen under reduced motion (the tableau hides its own embers).
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
		_title_top_label.add_theme_color_override("font_color", VFX.GOLD)
		return
	_title_t += delta
	var wave := 0.5 + 0.5 * sin(_title_t * 2.6)
	var flicker := 1.0 + sin(_title_t * 11.0) * 0.03 + sin(_title_t * 29.0) * 0.03
	var col := VFX.GOLD.lerp(VFX.ORANGE, wave * 0.4)
	_title_top_label.add_theme_color_override("font_color", Color(col.r * flicker, col.g * flicker, col.b * flicker, 1.0))


# --- Responsive building blocks ---------------------------------------------

func _screen(name: String, opaque: bool, accent: Color) -> Control:
	var screen := Control.new()
	screen.name = name.capitalize() + "Screen"
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.color = C_VOID if opaque else Color(0.025, 0.02, 0.04, 0.88)
	screen.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var top_band := ColorRect.new()
	top_band.name = "TopBand"
	top_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_band.color = Color(accent.r, accent.g, accent.b, 0.075 if opaque else 0.045)
	screen.add_child(top_band)
	top_band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_band.offset_bottom = 150.0

	var horizon := ColorRect.new()
	horizon.name = "Horizon"
	horizon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizon.color = Color(accent.r, accent.g, accent.b, 0.42)
	screen.add_child(horizon)
	horizon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	horizon.offset_top = 0.0
	horizon.offset_bottom = 2.0

	var lower_band := ColorRect.new()
	lower_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lower_band.color = Color(0.0, 0.0, 0.0, 0.2)
	screen.add_child(lower_band)
	lower_band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	lower_band.offset_top = -92.0

	_panels[name] = screen
	return screen


func _dialog(parent: Control, minimum: Vector2, accent: Color, margin_x: int, margin_y: int) -> VBoxContainer:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 24.0
	center.offset_top = 20.0
	center.offset_right = -24.0
	center.offset_bottom = -20.0

	var card := PanelContainer.new()
	card.name = "Dialog"
	card.custom_minimum_size = minimum
	card.add_theme_stylebox_override("panel", _panel_box(Color("1a1522f0"), accent.darkened(0.35), 14, 1, 18))
	center.add_child(card)
	parent.set_meta("dialog", card)

	var margin := _margin_container(margin_x, margin_x, margin_y, margin_y)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	return content


func _margin_container(left: int, right: int, top: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin


func _make_label(text: String, size: int, color: Color, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = alignment
	label.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_CENTER
	# Compact HUD labels must keep their intrinsic width inside HBoxContainers;
	# callers that render paragraphs opt into wrapping explicitly.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("000000b0"))
	label.add_theme_constant_override("outline_size", 2 if size >= 18 else 1)
	return label


func _make_stat_line(parent: VBoxContainer, title: String, value: String, value_color: Color) -> Label:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var caption := _make_label(title, 10, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	row.add_child(caption)
	var result := _make_label(value, 12, value_color, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(result)
	return result


func _make_bar(fill: Color, background: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size.y = height
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _bar_box(background))
	bar.add_theme_stylebox_override("fill", _bar_box(fill))
	return bar


func _bar_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_left = 4
	box.corner_radius_bottom_right = 4
	return box


func _panel_box(background: Color, border: Color, radius: int, border_width: int, shadow: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	if shadow > 0:
		box.shadow_color = Color(0.0, 0.0, 0.0, 0.58)
		box.shadow_size = shadow
		box.shadow_offset = Vector2(0, 6)
	return box


func _separator(color: Color) -> ColorRect:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size.y = 1.0
	line.color = Color(color.r, color.g, color.b, 0.55)
	return line


func _add_key_card(parent: GridContainer, title: String, key: String) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 54)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _panel_box(C_INK, C_EDGE, 8, 1, 0))
	parent.add_child(card)
	var margin := _margin_container(10, 10, 5, 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	margin.add_child(stack)
	stack.add_child(_make_label(title, 10, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	stack.add_child(_make_label(key, 13, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))


func _button(text: String, node_name: String, primary: bool, minimum: Vector2, cue_kind: String = "ui_confirm") -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = minimum
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_constant_override("outline_size", 1)
	button.add_theme_color_override("font_outline_color", Color("00000080"))
	if not cue_kind.is_empty():
		button.pressed.connect(func(): emit_signal("cue", cue_kind))

	var normal_bg := C_EMBER if primary else C_SURFACE_HI
	var normal_border := C_EMBER_HI if primary else C_EDGE
	var normal_text := C_INK if primary else C_TEXT
	button.add_theme_stylebox_override("normal", _button_box(normal_bg, normal_border, 1))
	button.add_theme_stylebox_override("hover", _button_box(normal_bg.lightened(0.12), C_EMBER_HI, 2))
	button.add_theme_stylebox_override("pressed", _button_box(normal_bg.darkened(0.12), C_GOLD, 2))
	button.add_theme_stylebox_override("focus", _button_box(Color(normal_bg.r, normal_bg.g, normal_bg.b, 0.35), C_GOLD, 2))
	button.add_theme_stylebox_override("disabled", _button_box(Color("17131d"), Color("30293a"), 1))
	button.add_theme_color_override("font_color", normal_text)
	button.add_theme_color_override("font_hover_color", C_TEXT if primary else C_EMBER_HI)
	button.add_theme_color_override("font_pressed_color", C_TEXT)
	button.add_theme_color_override("font_focus_color", C_TEXT)
	button.add_theme_color_override("font_disabled_color", Color("6f6578"))
	return button


func _button_box(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := _panel_box(background, border, 9, border_width, 0)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box


## Toggle glyphs, drawn procedurally like the rest of the game's art.
## The default theme's unchecked icon renders at the panel's own luminance
## (measured 0.088 against a 0.086 panel), so an OFF toggle showed as blank space
## and the player could not see it, or that the row was interactive at all.
## These carry explicit contrast in both states.
static var _toggle_icon_cache: Dictionary = {}

static func _toggle_icons() -> Dictionary:
	if not _toggle_icon_cache.is_empty():
		return _toggle_icon_cache
	_toggle_icon_cache = {
		"unchecked": ImageTexture.create_from_image(_toggle_image(false)),
		"checked": ImageTexture.create_from_image(_toggle_image(true)),
	}
	return _toggle_icon_cache


static func _toggle_image(is_on: bool) -> Image:
	var size := 22
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color("c99a5e") if is_on else Color("a494bc")
	var fill := Color("ff7a18") if is_on else Color("1c1726")
	for y in range(size):
		for x in range(size):
			var on_border := x < 2 or y < 2 or x >= size - 2 or y >= size - 2
			img.set_pixel(x, y, edge if on_border else fill)
	if is_on:
		# A check stroke: a short arm down into a valley, then a long rise. The
		# two arms must meet at the bottom, or it reads as a chevron instead.
		var ink := Color("1a1010")
		for i in range(5):
			for w in range(2):
				img.set_pixel(5 + i + w, 8 + i, ink)
		for i in range(8):
			for w in range(2):
				img.set_pixel(9 + i + w, 12 - i, ink)
	return img


func _check(title: String, description: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = "%s\n%s" % [title, description]
	check.custom_minimum_size.y = 54.0
	check.focus_mode = Control.FOCUS_ALL
	check.add_theme_font_size_override("font_size", 14)
	check.add_theme_color_override("font_color", C_TEXT)
	check.add_theme_color_override("font_hover_color", C_EMBER_HI)
	check.add_theme_color_override("font_focus_color", C_GOLD)
	var icons := _toggle_icons()
	check.add_theme_icon_override("checked", icons["checked"])
	check.add_theme_icon_override("unchecked", icons["unchecked"])
	check.add_theme_icon_override("checked_disabled", icons["unchecked"])
	check.add_theme_icon_override("unchecked_disabled", icons["unchecked"])
	check.add_theme_constant_override("h_separation", 10)
	check.add_theme_constant_override("icon_max_width", 22)
	check.toggled.connect(func(_on: bool): emit_signal("cue", "ui_confirm"))
	return check


# --- Public API --------------------------------------------------------------

func show_panel(name: String) -> void:
	if not _panels.has(name):
		return
	var panel: Control = _panels[name]
	panel.visible = true
	panel.modulate = Color.WHITE
	if name == "title" and _title_controls != null:
		_set_title_controls_open(false)
	if name == "title" and _title_tableau != null:
		_title_tableau.arrive(_last_panel != "forge")
	_last_panel = name
	if name != "pause":
		hide_room_clear()
	_focus_first_control(panel)


func hide_panel(name: String) -> void:
	if _panels.has(name):
		(_panels[name] as Control).visible = false


func hide_all_panels() -> void:
	for panel in _panels.values():
		(panel as Control).visible = false
	hide_room_clear()


## Show a one-time lesson. Re-showing replaces the current one rather than
## stacking, so two triggers in the same second cannot queue up noise.
func show_hint(text: String, hold: float = 4.5) -> void:
	if _hint_panel == null:
		return
	_hint_label.text = text
	if _hint_tween != null and is_instance_valid(_hint_tween):
		_hint_tween.kill()
	_hint_panel.visible = true
	_hint_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_hint_panel, "modulate:a", 1.0, 0.25)
	tween.tween_interval(hold)
	tween.tween_property(_hint_panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): _hint_panel.visible = false)
	_hint_tween = tween


func hide_hint() -> void:
	if _hint_tween != null and is_instance_valid(_hint_tween):
		_hint_tween.kill()
	if _hint_panel != null:
		_hint_panel.visible = false


func hide_banners() -> void:
	if _boss_phase_tween != null and is_instance_valid(_boss_phase_tween):
		(_boss_phase_tween as Tween).kill()
	if _boss_phase_tag != null:
		_boss_phase_tag.visible = false
	hide_hint()
	for banner in [_room_intro, _boss_intro]:
		if banner.is_empty():
			continue
		if banner.tween != null and is_instance_valid(banner.tween):
			(banner.tween as Tween).kill()
		(banner.root as Control).visible = false


func set_hp(hp: float, max_hp: float) -> void:
	_hp_bar.max_value = maxf(1.0, max_hp)
	_hp_bar.value = clampf(hp, 0.0, max_hp)
	_hp_value_label.text = "%d / %d" % [roundi(hp), roundi(max_hp)]


func set_special(value: float, maximum: float) -> void:
	_special_bar.max_value = maxf(1.0, maximum)
	_special_bar.value = clampf(value, 0.0, maximum)
	_special_value_label.text = "%d / %d" % [roundi(value), roundi(maximum)]


func set_room(idx: int, total: int) -> void:
	_room_label.text = "ROOM %02d / %02d" % [idx + 1, total]


## Waves remaining in the current chamber, so the fight has a visible end.
func set_wave(current: int, total: int) -> void:
	_wave_label.text = "WAVE %d / %d" % [current, total]
	_wave_label.visible = true


func hide_wave() -> void:
	_wave_label.visible = false


func set_score(score: int) -> void:
	_score_label.text = _format_number(score)


func show_boss_bar(max_hp: float) -> void:
	_boss_panel.visible = true
	_boss_bar.visible = true
	_boss_label.visible = true
	_boss_bar.max_value = maxf(1.0, max_hp)
	_boss_bar.value = max_hp
	_boss_value_label.text = str(roundi(max_hp))


func update_boss_bar(hp: float) -> void:
	_boss_bar.value = clampf(hp, 0.0, _boss_bar.max_value)
	_boss_value_label.text = str(maxi(0, roundi(hp)))


func hide_boss_bar() -> void:
	_boss_panel.visible = false
	_boss_bar.visible = false
	_boss_label.visible = false


## Phase-2 callout: a small tag under the boss bar that fades on its own.
func flash_boss_phase(text: String, hold: float = 1.7) -> void:
	if _boss_phase_tween != null and is_instance_valid(_boss_phase_tween):
		(_boss_phase_tween as Tween).kill()
	_boss_phase_tag.text = text
	_boss_phase_tag.visible = true
	_boss_phase_tag.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_boss_phase_tween = create_tween()
	_boss_phase_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_boss_phase_tween.tween_property(_boss_phase_tag, "modulate:a", 1.0, 0.18)
	_boss_phase_tween.tween_interval(hold)
	_boss_phase_tween.tween_property(_boss_phase_tag, "modulate:a", 0.0, 0.5)
	_boss_phase_tween.tween_callback(func(): _boss_phase_tag.visible = false)


## Draws one boon sigil. A Control so it lays out inside a card; the drawing
## itself lives in BoonArt with every other procedural art in the game.
class BoonSigil extends Control:
	var boon_id := ""
	var tint := Color.WHITE

	## `box` is the minimum size: a wide band on a boon card, a square in a row.
	## It must be set here rather than by the caller, or setup() would overwrite a
	## caller-assigned size and draw the sigil at zero width.
	func setup(p_id: String, p_tint: Color, box: Vector2 = Vector2(0.0, 58.0)) -> void:
		boon_id = p_id
		tint = p_tint
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = box
		# The sigil is sized from the control's box, so it must repaint when the
		# card is laid out or resized rather than only when setup() runs.
		if not resized.is_connected(queue_redraw):
			resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		BoonArt.draw(self, boon_id, size * 0.5, minf(size.x, size.y) * 0.46, tint)


## One boon card. The Button IS the card frame, so focus, hover and click stay a
## single control; the children are plain labels. Rarity is carried by border
## weight, frame tint and a coloured chip rather than by text alone, which was
## invisible at a 5% tint on a 1280x720 frame.
func _upgrade_card(index: int, upgrade: Dictionary, rarity: String, rc: Color) -> Button:
	var epic := rarity == "epic"
	var edge_w := 3 if epic else 2
	var tint := Color(rc.r, rc.g, rc.b, 0.22 if epic else (0.14 if rarity == "rare" else 0.07))
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 220)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _card_box(C_SURFACE.blend(tint), rc.darkened(0.2), edge_w))
	button.add_theme_stylebox_override("hover", _card_box(C_SURFACE_HI.blend(tint), rc, edge_w + 1))
	button.add_theme_stylebox_override("focus", _card_box(C_SURFACE_HI.blend(tint), rc.lightened(0.3), edge_w + 1))
	button.add_theme_stylebox_override("pressed", _card_box(Color("332333"), C_GOLD, edge_w + 1))

	var margin := _margin_container(18, 18, 16, 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	var chip := _make_label(rarity.to_upper(), 12, rc, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	head.add_child(chip)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	if bool(upgrade.get("unique", false)):
		var once := _make_label("ONCE PER RUN", 10, C_GOLD, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
		once.size_flags_horizontal = Control.SIZE_SHRINK_END
		head.add_child(once)
	# The index is a live keyboard shortcut, so printing it is not decoration.
	var key := _make_label("[%d]" % (index + 1), 11, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
	key.size_flags_horizontal = Control.SIZE_SHRINK_END
	head.add_child(key)

	var sigil := BoonSigil.new()
	sigil.setup(str(upgrade.get("id", "")), rc)
	stack.add_child(sigil)

	var title := _make_label(str(upgrade.get("title", "UNKNOWN BOON")).to_upper(), 21, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	stack.add_child(title)
	var desc := _make_label(str(upgrade.get("desc", "")), 13, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_TOP
	stack.add_child(desc)
	return button


func setup_upgrades(upgrades: Array) -> void:
	if _upgrade_row == null:
		return
	_clear_children(_upgrade_row)
	var buttons: Array = []
	var count := upgrades.size()
	for i in range(count):
		var upgrade: Dictionary = upgrades[i]
		var rarity := Content.upgrade_rarity(upgrade)
		var rc: Color = Content.rarity_color(rarity)
		var button := _upgrade_card(i, upgrade, rarity, rc)
		button.name = "Boon%d" % i
		button.pressed.connect(_on_upgrade_pressed.bind(i))
		_upgrade_row.add_child(button)
		buttons.append(button)
	(_panels["reward"] as Control).set_meta("buttons", buttons)
	if not buttons.is_empty():
		(buttons[0] as Button).grab_focus.call_deferred()


func set_flask(charges: int, max_charges: int) -> void:
	var safe_max := maxi(0, max_charges)
	var safe_charges := clampi(charges, 0, safe_max)
	if _flask_dots.size() != safe_max:
		_rebuild_flask_dots(safe_max)
	for i in range(_flask_dots.size()):
		_style_flask_dot(_flask_dots[i] as PanelContainer, i < safe_charges)
	_flask_count_label.text = "%d / %d  [F]" % [safe_charges, safe_max]


func set_cells(value: int) -> void:
	_cells_label.text = _format_number(value)


func set_best(value: int) -> void:
	_best_label.text = _format_number(value)


func setup_forge(cells: int) -> void:
	var panel: Control = _panels.get("forge")
	if panel == null:
		return
	var balance = panel.get_meta("balance_label", null)
	if balance is Label:
		(balance as Label).text = "AVAILABLE CELLS   %s" % _format_number(cells)
	if _forge_rows == null:
		return
	_clear_children(_forge_rows)

	var purchased: Array = Save.get_purchased_meta()
	var focus_target: Button = null
	for i in range(Content.META_UPGRADES.size()):
		var upgrade: Dictionary = Content.META_UPGRADES[i]
		var owned := purchased.has(upgrade.get("id", ""))
		var row := PanelContainer.new()
		row.custom_minimum_size.y = 68.0
		row.add_theme_stylebox_override("panel", _panel_box(C_INK, Color("3b3147"), 8, 1, 0))
		_forge_rows.add_child(row)
		var margin := _margin_container(16, 12, 8, 8)
		row.add_child(margin)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		margin.add_child(line)

		var sigil := BoonSigil.new()
		# Forge rows are shorter than cards, so the sigil takes a fixed square.
		sigil.setup(str(upgrade.get("id", "")), C_GOLD if owned else C_EMBER_HI, Vector2(46.0, 46.0))
		line.add_child(sigil)

		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 1)
		line.add_child(copy)
		copy.add_child(_make_label(str(upgrade.get("title", "Upgrade")).to_upper(), 14, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))
		copy.add_child(_make_label(str(upgrade.get("desc", "")), 12, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))

		var buy := _button("OWNED" if owned else "%d CELLS" % int(upgrade.get("cost", 0)), "Buy%d" % i, false, Vector2(132, 44), "")
		buy.disabled = owned or cells < int(upgrade.get("cost", 0))
		if owned:
			buy.add_theme_color_override("font_disabled_color", C_MINT)
		else:
			buy.pressed.connect(_on_buy_meta_pressed.bind(i))
		line.add_child(buy)
		if focus_target == null and not buy.disabled:
			focus_target = buy

	if focus_target == null:
		var back = panel.get_meta("back_button", null)
		if back is Button:
			focus_target = back as Button
	if focus_target != null:
		focus_target.grab_focus.call_deferred()


func show_run_cells(cells_earned: int, panel_name: String) -> void:
	if not _panels.has(panel_name):
		return
	var panel: Control = _panels[panel_name]
	var label = panel.get_meta("cells_label", null)
	if label is Label:
		(label as Label).text = "CELLS SECURED  +%s" % _format_number(cells_earned)
		(label as Label).visible = true


func set_streak(kills: int, frac: float, mult: float) -> void:
	if _streak_panel == null:
		return
	if kills < 2:
		hide_streak()
		return
	_streak_panel.visible = true
	_streak_kills_label.text = "%d KILLS" % kills
	_streak_mult_label.text = "x" + String.num(mult, 2)
	_streak_bar.value = clampf(frac, 0.0, 1.0) * 100.0
	var tier := Content.streak_tier(kills)
	var tier_colors := [C_MUTED, C_TEXT, C_GOLD, C_EMBER_HI, C_RED]
	var col: Color = tier_colors[clampi(tier, 0, tier_colors.size() - 1)]
	_streak_mult_label.add_theme_color_override("font_color", col)
	_streak_bar.add_theme_stylebox_override("fill", _bar_box(col))
	if tier > _streak_tier and not Feedback.motion_reduced:
		if _streak_tween != null and is_instance_valid(_streak_tween):
			_streak_tween.kill()
		_streak_panel.scale = Vector2(1.12, 1.12)
		_streak_tween = create_tween()
		_streak_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_streak_tween.tween_property(_streak_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tier = tier


func hide_streak() -> void:
	if _streak_panel != null:
		_streak_panel.visible = false
		_streak_panel.scale = Vector2.ONE
	_streak_tier = 0


func show_room_intro(idx: int, total: int, room_name: String) -> void:
	_play_banner(_room_intro, room_name.to_upper(), "CHAMBER %02d OF %02d" % [idx + 1, total], 1.5)


func show_boss_intro(boss_name: String, subtitle: String, hold: float = 2.4) -> void:
	# The boss card owns the screen: drop any chamber card still fading out.
	if not _room_intro.is_empty():
		if _room_intro.tween != null and is_instance_valid(_room_intro.tween):
			(_room_intro.tween as Tween).kill()
		(_room_intro.root as Control).visible = false
	_play_banner(_boss_intro, boss_name.to_upper(), subtitle.to_upper(), hold)


## Veil that lifts on arrival in a new chamber.
func fade_from_black(duration: float = 0.45) -> void:
	if _fade == null:
		return
	_fade.color = Color(C_VOID, 1.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade, "color:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func show_run_summary(stats: Dictionary, panel_name: String) -> void:
	if not _panels.has(panel_name):
		return
	var panel: Control = _panels[panel_name]
	# The headline result is set before the grid so it never depends on it.
	var score_label = panel.get_meta("score_label", null)
	if score_label is Label:
		(score_label as Label).text = _format_number(int(stats.get("score", 0)))
	var best_label = panel.get_meta("best_label", null)
	if best_label is Label:
		# Set both text and colour every time: the panel is reused between runs,
		# so a previous record's gold must not persist onto a lesser run.
		var record := bool(stats.get("new_best", false))
		(best_label as Label).text = "NEW BEST" if record else "BEST  %s" % _format_number(int(stats.get("best", 0)))
		(best_label as Label).add_theme_color_override("font_color", C_GOLD if record else C_MUTED)
	var labels = panel.get_meta("summary_labels", null)
	if not (labels is Dictionary):
		return
	var seconds := int(float(stats.get("time", 0.0)))
	var values := {
		"time": "%d:%02d" % [seconds / 60, seconds % 60],
		"kills": _format_number(int(stats.get("kills", 0))),
		"elites": _format_number(int(stats.get("elites", 0))),
		"streak": "x%d" % int(stats.get("best_streak", 0)),
		"damage": _format_number(int(stats.get("damage_dealt", 0.0))),
		"rooms": "%d / %d" % [int(stats.get("rooms", 0)), int(stats.get("rooms_total", 0))],
	}
	for key in values:
		if labels.has(key):
			(labels[key] as Label).text = str(values[key])


func show_room_clear(room_name: String) -> void:
	_room_clear_name.text = room_name.to_upper() if not room_name.strip_edges().is_empty() else "PATH UNSEALED"
	_room_clear_banner.visible = true
	_room_clear_banner.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_room_clear_banner, "modulate", Color.WHITE, 0.16)


func hide_room_clear() -> void:
	if _room_clear_banner != null:
		_room_clear_banner.visible = false
		_room_clear_banner.modulate = Color.WHITE


# --- Internal updates --------------------------------------------------------

func _rebuild_flask_dots(count: int) -> void:
	_clear_children(_flask_container)
	_flask_dots.clear()
	for i in range(count):
		var dot := PanelContainer.new()
		dot.custom_minimum_size = Vector2(16, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flask_container.add_child(dot)
		_flask_dots.append(dot)
		_style_flask_dot(dot, true)


func _style_flask_dot(dot: PanelContainer, filled: bool) -> void:
	var color := C_MINT if filled else Color("26332f")
	var edge := Color("98ffd0") if filled else Color("3b4944")
	dot.add_theme_stylebox_override("panel", _panel_box(color, edge, 3, 1, 0))


## Boon card frame: no content margins, because the card's own MarginContainer
## owns the padding and the Button only provides the border and tint.
func _card_box(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := _panel_box(background, border, 12, border_width, 6)
	box.content_margin_left = 0.0
	box.content_margin_right = 0.0
	box.content_margin_top = 0.0
	box.content_margin_bottom = 0.0
	return box


func _upgrade_box(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := _panel_box(background, border, 12, border_width, 5)
	box.content_margin_left = 22.0
	box.content_margin_right = 22.0
	box.content_margin_top = 18.0
	box.content_margin_bottom = 18.0
	return box


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _focus_first_control(root: Node) -> bool:
	for child in root.get_children():
		if child is Control:
			var control := child as Control
			if control.visible and control.focus_mode != Control.FOCUS_NONE:
				if not (control is BaseButton) or not (control as BaseButton).disabled:
					control.grab_focus.call_deferred()
					return true
		if _focus_first_control(child):
			return true
	return false


func _on_upgrade_pressed(index: int) -> void:
	emit_signal("upgrade_selected", index)


func _on_buy_meta_pressed(index: int) -> void:
	emit_signal("buy_meta_requested", index)


func _format_number(value: int) -> String:
	var raw := str(maxi(0, value))
	var formatted := ""
	while raw.length() > 3:
		formatted = "," + raw.right(3) + formatted
		raw = raw.left(raw.length() - 3)
	return raw + formatted
