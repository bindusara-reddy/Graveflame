class_name UI
extends CanvasLayer
## Responsive HUD and atmospheric screen overlays, built with Godot-native controls.

const VFX := preload("res://scripts/vfx.gd")

signal start_requested
signal resume_requested
signal restart_requested
signal quit_to_title_requested
signal upgrade_selected(idx: int)
signal option_toggled(key: String, value: bool)
signal forge_requested
signal buy_meta_requested(idx: int)
signal back_from_forge_requested

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
var _fade: ColorRect
var _music_check: CheckBox

var _panels: Dictionary = {}
var _upgrade_row: HBoxContainer
var _forge_rows: VBoxContainer
var _reduced_motion_check: CheckBox
var _reduced_flash_check: CheckBox

var _title_top_label: Label
var _title_embers: CPUParticles2D
var _title_masonry: Control
var _title_t := 0.0


func _ready() -> void:
	layer = 50

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

	hide_all_panels()
	show_panel("title")


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
	_build_room_clear_banner()
	_room_intro = _build_banner("RoomIntro", 176.0, 258.0, Vector2(420, 70), 26, 11, C_EMBER, Color("14101ceb"))
	_boss_intro = _build_banner("BossIntro", 236.0, 372.0, Vector2(620, 118), 40, 14, C_RED, Color("1a0c11f0"))


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
	panel.offset_bottom = 112.0

	var margin := _margin_container(12, 12, 8, 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)

	_room_label = _make_label("ROOM 01 / 06", 12, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
	stack.add_child(_room_label)
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
	_build_title_scene(panel)
	var content := _dialog(panel, Vector2(920, 640), C_EMBER, 46, 40)
	# Slightly translucent card so the furnace horizon bleeds through.
	(panel.get_meta("dialog") as PanelContainer).add_theme_stylebox_override("panel", _panel_box(Color("14101cd2"), C_EMBER.darkened(0.35), 14, 1, 18))
	content.add_theme_constant_override("separation", 10)

	content.add_child(_make_label("AN ORIGINAL ACTION-ROGUELITE", 13, C_EMBER_HI, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_build_title_stack("GRAVEFLAME", 74))
	content.add_child(_make_label("Descend. Adapt. Burn brighter.", 18, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_separator(C_EMBER))

	var lore := _make_label(
		"Beneath the ruined keep, a borrowed flame refuses to die.\nCarve a path through the wardens and carry its memory home.",
		16,
		C_TEXT,
		HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	)
	lore.custom_minimum_size.y = 48.0
	content.add_child(lore)

	var keys := GridContainer.new()
	keys.columns = 3
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.add_theme_constant_override("h_separation", 8)
	keys.add_theme_constant_override("v_separation", 8)
	content.add_child(keys)
	_add_key_card(keys, "MOVE + JUMP", "A / D   |   W / SPACE")
	_add_key_card(keys, "BLADE", "J")
	_add_key_card(keys, "DASH", "SHIFT / L")
	_add_key_card(keys, "GRAVEFLAME", "K LANCE  |  Q IGNITE")
	_add_key_card(keys, "PARRY", "S")
	_add_key_card(keys, "FLASK", "F")

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	var start := _button("BEGIN DESCENT", "start", true, Vector2(260, 56))
	start.pressed.connect(func(): emit_signal("start_requested"))
	actions.add_child(start)
	var forge := _button("THE FORGE", "forge", false, Vector2(220, 56))
	forge.pressed.connect(func(): emit_signal("forge_requested"))
	actions.add_child(forge)

	content.add_child(_make_label("Wall-jump from vertical surfaces. Air-attack to slam. E / Up enters an unsealed rift.", 12, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))


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
	var content := _dialog(panel, Vector2(1140, 520), C_GOLD, 38, 34)
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
	var content := _dialog(panel, Vector2(760, 520), C_RED, 48, 30)
	content.add_theme_constant_override("separation", 10)

	content.add_child(_make_label("RUN ENDED", 13, C_RED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("THE FLAME FADES", 54, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("Ash remembers every attempt.", 18, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_separator(Color("75414b")))
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
	var content := _dialog(panel, Vector2(760, 540), C_MINT, 48, 30)
	content.add_theme_constant_override("separation", 10)

	content.add_child(_make_label("WARDEN DEFEATED", 13, C_MINT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("GRAVEFLAME ENDURES", 50, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_make_label("The keep falls silent, but the descent is never the same twice.", 17, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_separator(C_MINT))
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
	var back := _button("BACK", "back", false, Vector2(220, 50))
	back.pressed.connect(func(): emit_signal("back_from_forge_requested"))
	footer.add_child(back)
	panel.set_meta("back_button", back)


# --- Title scene ---------------------------------------------------------------

func _build_title_scene(panel: Control) -> void:
	# Furnace horizon, silhouetted battlements and rising embers behind the dialog.
	var scene := Control.new()
	scene.name = "TitleScene"
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var glow := Control.new()
	glow.name = "FurnaceGlow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.material = VFX.radial_material()
	scene.add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.draw.connect(_draw_title_glow.bind(glow))
	glow.resized.connect(glow.queue_redraw)

	var masonry := Control.new()
	masonry.name = "Battlements"
	masonry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(masonry)
	masonry.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	masonry.draw.connect(_draw_title_masonry.bind(masonry))
	masonry.resized.connect(masonry.queue_redraw)
	_title_masonry = masonry

	_title_embers = CPUParticles2D.new()
	_title_embers.name = "TitleEmbers"
	_title_embers.amount = 80
	_title_embers.lifetime = 5.0
	_title_embers.preprocess = 3.0
	_title_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_title_embers.local_coords = true
	_title_embers.direction = Vector2(0.0, -1.0)
	_title_embers.spread = 14.0
	_title_embers.gravity = Vector2.ZERO
	_title_embers.initial_velocity_min = 80.0
	_title_embers.initial_velocity_max = 180.0
	_title_embers.tangential_accel_min = -24.0
	_title_embers.tangential_accel_max = 24.0
	_title_embers.scale_amount_min = 2.0
	_title_embers.scale_amount_max = 5.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.1, 0.55, 1.0])
	ramp.colors = PackedColorArray([Color(VFX.GOLD, 0.0), Color(VFX.GOLD, 0.9), Color(VFX.ORANGE, 0.6), Color(VFX.EMBER, 0.0)])
	_title_embers.color_ramp = ramp
	_title_embers.material = VFX.additive_material()
	scene.add_child(_title_embers)
	scene.resized.connect(_fit_title_embers.bind(scene))
	_fit_title_embers(scene)


func _fit_title_embers(scene: Control) -> void:
	var s := scene.size
	_title_embers.position = Vector2(s.x * 0.5, s.y + 10.0)
	_title_embers.emission_rect_extents = Vector2(maxf(s.x * 0.5, 1.0), 6.0)


func _draw_title_glow(ci: Control) -> void:
	# Horizon furnace: bottom-anchored radial stretched wide so it reads past the
	# dialog card and above the battlement line.
	var s := ci.size
	var stretch := 2.4
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch, 1.0))
	var origin := Vector2(s.x * 0.5 / stretch, s.y * 0.92)
	VFX.draw_radial(ci, origin, maxf(s.y * 0.8, 580.0), Color(VFX.EMBER, 0.9))
	VFX.draw_radial(ci, origin + Vector2(0.0, 30.0), s.y * 0.5, Color(VFX.ORANGE, 0.5))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_title_masonry(ci: Control) -> void:
	var s := ci.size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var still := Feedback.motion_reduced
	var t := 0.0 if still else _title_t
	# A cold moon high on the left, behind everything.
	var moon := Vector2(s.x * 0.075, s.y * 0.15)
	for i in range(5, 0, -1):
		ci.draw_circle(moon, 62.0 + float(i) * 30.0, Color("c9d2ee", 0.014 * float(6 - i)))
	ci.draw_circle(moon, 62.0, Color("c9d2ee", 0.9))
	for i in range(5):
		var off := Vector2(VFX.hash01(i, 61) - 0.5, VFX.hash01(i, 62) - 0.5) * 84.0
		ci.draw_circle(moon + off, 4.0 + VFX.hash01(i, 63) * 10.0, Color("9aa3c4", 0.5))
	ci.draw_circle(moon + Vector2(30.0, -20.0), 58.0, Color(VFX.VOID, 0.88))
	# Midground pillars in mortar, then ruined battlements in void along the bottom.
	var pillar := Color(VFX.MORTAR, 0.6)
	var count := int(s.x / 150.0) + 1
	for i in range(count):
		var px := float(i) * 150.0 + 40.0 + VFX.hash01(i, 1) * 50.0
		var top := s.y * (0.32 + VFX.hash01(i, 2) * 0.22)
		ci.draw_rect(Rect2(px, top, 34.0, s.y - top), pillar)
		ci.draw_rect(Rect2(px - 7.0, top, 48.0, 12.0), Color(VFX.MORTAR, 0.8))
		ci.draw_line(Vector2(px + 34.0, top), Vector2(px + 34.0, s.y), Color(VFX.RIM, 0.25), 1.5)
	var wall_top := s.y * 0.84
	var pts := PackedVector2Array([Vector2(0.0, s.y + 2.0)])
	var x := 0.0
	var seg_i := 0
	var up := true
	while x < s.x:
		var seg := 42.0 + VFX.hash01(seg_i, 3) * 34.0
		var y := wall_top - (26.0 if up else 0.0) - VFX.hash01(seg_i, 4) * 10.0
		pts.append(Vector2(x, y))
		pts.append(Vector2(minf(x + seg, s.x), y))
		x += seg
		seg_i += 1
		up = not up
	pts.append(Vector2(s.x, s.y + 2.0))
	ci.draw_colored_polygon(pts, VFX.VOID)
	ci.draw_line(Vector2(0.0, wall_top + 1.0), Vector2(s.x, wall_top + 1.0), Color(VFX.RIM, 0.12), 1.0)


func _build_title_stack(text: String, size: int) -> Control:
	# Three stacked labels: void drop shadow, ember-rimmed orange core, gold face.
	var stack := Control.new()
	stack.name = "TitleStack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var shadow := _make_label(text, size, VFX.VOID, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	shadow.add_theme_color_override("font_outline_color", VFX.VOID)
	shadow.add_theme_constant_override("outline_size", 6)
	var rim := _make_label(text, size, VFX.ORANGE, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	rim.add_theme_color_override("font_outline_color", VFX.EMBER)
	rim.add_theme_constant_override("outline_size", 2)
	var face := _make_label(text, size, VFX.GOLD, HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	face.add_theme_constant_override("outline_size", 0)
	var offsets := [8.0, 3.0, 0.0]
	var layers := [shadow, rim, face]
	for i in range(layers.size()):
		var label: Label = layers[i]
		stack.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_top = offsets[i]
		label.offset_bottom = offsets[i]
	stack.custom_minimum_size = Vector2(0.0, maxf(face.get_minimum_size().y, float(size) * 1.2) + 8.0)
	_title_top_label = face
	return stack


func _process(delta: float) -> void:
	# Firelight wobble on the title face; frozen (and embers hidden) under reduced motion.
	if _title_top_label == null:
		return
	var title_panel: Control = _panels.get("title", null)
	if title_panel == null or not title_panel.visible:
		return
	var still := Feedback.motion_reduced
	if _title_embers != null and _title_embers.visible == still:
		_title_embers.visible = not still
		_title_embers.emitting = not still
	if still:
		_title_top_label.add_theme_color_override("font_color", VFX.GOLD)
		return
	_title_t += delta
	if _title_masonry != null:
		_title_masonry.queue_redraw()
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
	top_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_band.color = Color(accent.r, accent.g, accent.b, 0.075 if opaque else 0.045)
	screen.add_child(top_band)
	top_band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_band.offset_bottom = 150.0

	var horizon := ColorRect.new()
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


func _button(text: String, node_name: String, primary: bool, minimum: Vector2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = minimum
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_constant_override("outline_size", 1)
	button.add_theme_color_override("font_outline_color", Color("00000080"))

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


func _check(title: String, description: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = "%s\n%s" % [title, description]
	check.custom_minimum_size.y = 54.0
	check.focus_mode = Control.FOCUS_ALL
	check.add_theme_font_size_override("font_size", 14)
	check.add_theme_color_override("font_color", C_TEXT)
	check.add_theme_color_override("font_hover_color", C_EMBER_HI)
	check.add_theme_color_override("font_focus_color", C_GOLD)
	return check


# --- Public API --------------------------------------------------------------

func show_panel(name: String) -> void:
	if not _panels.has(name):
		return
	var panel: Control = _panels[name]
	panel.visible = true
	panel.modulate = Color.WHITE
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


func hide_banners() -> void:
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


func setup_upgrades(upgrades: Array) -> void:
	if _upgrade_row == null:
		return
	_clear_children(_upgrade_row)
	var buttons: Array = []
	var count := upgrades.size()
	for i in range(count):
		var upgrade: Dictionary = upgrades[i]
		var title := str(upgrade.get("title", "UNKNOWN BOON"))
		var description := str(upgrade.get("desc", ""))
		var rarity := Content.upgrade_rarity(upgrade)
		var rc: Color = Content.rarity_color(rarity)
		var tag := rarity.to_upper()
		if bool(upgrade.get("unique", false)):
			tag += "  \u00b7  ONCE PER RUN"
		var button := _button(
			"%s\n\n%02d  %s\n\n%s" % [tag, i + 1, title.to_upper(), description],
			"Boon%d" % i,
			false,
			Vector2(0, 200)
		)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 16)
		var edge_w := 2 if rarity == "epic" else 1
		var tint := Color(rc.r, rc.g, rc.b, 0.10 if rarity == "epic" else 0.05)
		button.add_theme_stylebox_override("normal", _upgrade_box(C_SURFACE.blend(tint), rc.darkened(0.25), edge_w))
		button.add_theme_stylebox_override("hover", _upgrade_box(C_SURFACE_HI.blend(tint), rc, 2))
		button.add_theme_stylebox_override("pressed", _upgrade_box(Color("332333"), C_GOLD, 2))
		button.add_theme_stylebox_override("focus", _upgrade_box(Color("302337").blend(tint), rc.lightened(0.2), 2))
		button.add_theme_color_override("font_hover_color", rc.lightened(0.2))
		button.add_theme_color_override("font_focus_color", C_TEXT)
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

		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 1)
		line.add_child(copy)
		copy.add_child(_make_label(str(upgrade.get("title", "Upgrade")).to_upper(), 14, C_TEXT, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))
		copy.add_child(_make_label(str(upgrade.get("desc", "")), 12, C_MUTED, HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT))

		var buy := _button("OWNED" if owned else "%d CELLS" % int(upgrade.get("cost", 0)), "Buy%d" % i, false, Vector2(132, 44))
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
