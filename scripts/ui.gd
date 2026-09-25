class_name UI
extends CanvasLayer
## The interface facade game.gd and the finale talk to. It stacks three layers
## over the world (the rift veil, the HUD, the screens), routes input to them,
## and keeps one public API while the work lives in its modules:
##   ui_theme.gd   tokens, faces, StyleBoxes, the burn shader   (UiTheme)
##   ui_input.gd   bindings, prompts, the device last touched     (UiInput)
##   ui_kit.gd     the reusable components every screen is cut from (UiKit)
##   ui_hud.gd     the HUD and every pop-up over a live fight     (UiHud)
##   ui_screens.gd the title, pause, boon deal, results, Forge,
##                 options and key bindings                       (UiScreens)

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
## names a sound directly. Kit controls reach it through UiKit.emit_cue.
signal cue(kind: String)
signal options_requested
signal back_from_options_requested
## Continuous controls (volumes) report here; toggles keep option_toggled.
signal option_value_changed(key: String, value: float)
signal keys_requested
signal back_from_keys_requested
signal binding_changed(action: String, keycode: int)
signal vow_toggled(id: String)

## Tokens other scripts read through UI (the finale's cards and prompts).
const C_VOID := UiTheme.C_VOID
const C_INK := UiTheme.C_INK
const C_EDGE := UiTheme.C_EDGE
const C_TEXT := UiTheme.C_TEXT
const C_MUTED := UiTheme.C_MUTED
const C_EMBER := UiTheme.C_EMBER
const C_GOLD := UiTheme.C_GOLD
const BarNotches := UiKit.BarNotches
const KeptSeal := UiKit.KeptSeal

var hud: UiHud
var screens: UiScreens
var _root: Control
## Rift transition veil: under the HUD and every screen, above the world.
var _fade: ColorRect
var _veil_tween: Tween


func _ready() -> void:
	layer = 50
	UiInput.ensure_menu_bindings()

	_root = Control.new()
	_root.name = "InterfaceRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_fade = UiKit.backdrop(_root, Color(C_VOID, 0.0), Control.PRESET_FULL_RECT)
	_fade.name = "RiftFade"
	hud = UiHud.new()
	_layer(hud, "HUD")
	hud.build()
	screens = UiScreens.new()
	_layer(screens, "Screens")
	screens.build(self)
	UiKit.focus_flame(_root)
	get_viewport().gui_focus_changed.connect(screens.on_focus_changed)
	_refresh_prompts()

	hide_all_panels()
	show_panel("title")


## Stack a full-frame layer on the interface root.
func _layer(node: Control, node_name: String) -> void:
	node.name = node_name
	_root.add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _input(event: InputEvent) -> void:
	if UiInput.track_device(event):
		_refresh_prompts()
	screens.handle_input(event)


func _unhandled_input(event: InputEvent) -> void:
	screens.handle_unhandled_input(event)


func _process(delta: float) -> void:
	screens.tick(delta)


## Repaint every visible key prompt after a device switch or a rebind.
func _refresh_prompts() -> void:
	UiInput.refresh_prompts(self)


# --- Screens -----------------------------------------------------------------------

func show_panel(panel_name: String, fade: float = 0.0) -> void:
	if screens.show_panel(panel_name, fade) and panel_name != "pause":
		hud.hide_room_clear()


func hide_panel(panel_name: String) -> void:
	screens.hide_panel(panel_name)


func hide_all_panels() -> void:
	screens.hide_all_panels()
	hud.hide_room_clear()


func is_panel_visible(panel_name: String) -> bool:
	return screens.is_panel_visible(panel_name)


func lock_until_released(panel_name: String, actions: Array) -> void:
	screens.lock_until_released(panel_name, actions)


func set_victory_extras(ordinal: String, first: bool) -> void:
	screens.set_victory_extras(ordinal, first)


func show_run_cells(cells_earned: int, panel_name: String, vows_kept: int = 0) -> void:
	screens.show_run_cells(cells_earned, panel_name, vows_kept)


func show_run_summary(stats: Dictionary, panel_name: String) -> void:
	screens.show_run_summary(stats, panel_name)


func set_descent(taken: Dictionary, seed_value: int) -> void:
	screens.set_descent(taken, seed_value)


func setup_upgrades(upgrades: Array) -> void:
	screens.setup_upgrades(upgrades)


func setup_forge(cells: int) -> void:
	screens.setup_forge(cells)


func sync_options(opts: Dictionary) -> void:
	screens.sync_options(opts)


## Rebuild the rebinding rows, and every prompt that names a key, against the
## live input map.
func sync_keys() -> void:
	_refresh_prompts()
	screens.sync_keys()


func sync_controls() -> void:
	screens.sync_controls()


# --- HUD ---------------------------------------------------------------------------

func set_hp(hp: float, max_hp: float) -> void:
	hud.set_hp(hp, max_hp)


func set_special(value: float, maximum: float) -> void:
	hud.set_special(value, maximum)


func set_flask(charges: int, max_charges: int) -> void:
	hud.set_flask(charges, max_charges)


func set_room(idx: int, total: int) -> void:
	hud.set_room(idx, total)


func set_wave(current: int, total: int) -> void:
	hud.set_wave(current, total)


func hide_wave() -> void:
	hud.hide_wave()


func set_score(score: int) -> void:
	hud.set_score(score)


func set_cells(value: int) -> void:
	hud.set_cells(value)


func set_best(value: int) -> void:
	hud.set_best(value)


func track_threats(enemies: Array, view: Transform2D) -> void:
	hud.track_threats(enemies, view)


func set_hud_faded(faded: bool) -> void:
	if hud != null:
		hud.set_hud_faded(faded)


func show_boss_bar(max_hp: float) -> void:
	hud.show_boss_bar(max_hp)


func update_boss_bar(hp: float) -> void:
	hud.update_boss_bar(hp)


func hide_boss_bar() -> void:
	hud.hide_boss_bar()


func flash_boss_phase(text: String, hold: float = 1.7) -> void:
	hud.flash_boss_phase(text, hold)


func show_boss_intro(boss_name: String, subtitle: String, hold: float = 2.4) -> void:
	hud.show_boss_intro(boss_name, subtitle, hold)


func set_streak(kills: int, frac: float, mult: float) -> void:
	hud.set_streak(kills, frac, mult)


func set_streak_fraction(frac: float) -> void:
	hud.set_streak_fraction(frac)


func hide_streak() -> void:
	hud.hide_streak()


func show_room_intro(idx: int, total: int, room_name: String, trial: bool = false) -> void:
	hud.show_room_intro(idx, total, room_name, trial)


func show_room_clear(room_name: String) -> void:
	hud.show_room_clear(room_name)


func hide_room_clear() -> void:
	hud.hide_room_clear()


func show_hint(text: String, hold: float = 4.5) -> void:
	hud.show_hint(text, hold)


func hide_hint() -> void:
	hud.hide_hint()


func hide_banners() -> void:
	hud.hide_banners()


# --- Rift veil ---------------------------------------------------------------------

## Arrival in a new chamber: the black page burns away from where the knight
## stands, its edge glowing like paper catching. Reduced motion keeps a plain
## fade, since a travelling edge is exactly the motion that setting removes.
func fade_from_black(duration: float = 0.45, origin: Vector2 = Vector2(0.5, 0.55)) -> void:
	if _fade == null:
		return
	UiKit.kill_tween(_veil_tween)
	_veil_tween = UiKit.tween(self)
	_fade.color = Color(C_VOID, 1.0)
	if Feedback.motion_reduced:
		_fade.material = null
		_veil_tween.tween_property(_fade, "color:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		return
	var mat := burn_material()
	_fade.material = mat
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(1.0, vs.y)
	mat.set_shader_parameter("aspect", aspect)
	mat.set_shader_parameter("origin", origin)
	mat.set_shader_parameter("reach", burn_reach(origin, aspect))
	mat.set_shader_parameter("progress", 0.0)
	_veil_tween.tween_method(func(v: float): mat.set_shader_parameter("progress", v), 0.0, 1.0, duration * 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# The shader paints its own colour, so the veil is gone only once the
	# material is: clearing the alpha alone would leave the burn's last frame.
	_veil_tween.tween_callback(func():
		_fade.material = null
		_fade.color = Color(C_VOID, 0.0)
	)


# --- Static helpers other scripts call through UI ----------------------------------

static func burn_material() -> ShaderMaterial:
	return UiTheme.burn_material()


static func burn_reach(origin: Vector2, aspect: float) -> float:
	return UiTheme.burn_reach(origin, aspect)


static func prompt(action: String) -> String:
	return UiInput.prompt(action)


static func fill_prompts(template: String) -> String:
	return UiInput.fill_prompts(template)


static func _binding_text(action: String) -> Dictionary:
	return UiInput.binding_text(action)


static func _key_codes(action: String) -> Array:
	return UiInput.key_codes(action)


static func _heading_font() -> Font:
	return UiTheme.heading_font()


static func _roll_line(record: Dictionary) -> String:
	return UiScreens.roll_line(record)


# --- Handles the contract suites reach into ----------------------------------------
## Kept so every suite (and the streams merging beside this one) compiles across
## the split. The HUD and screen rebuilds retire each handle with its widget.

## Dynamic lookups (ui.get("_name")) fall through to the module that owns the name.
func _get(property: StringName) -> Variant:
	for module: Node in [hud, screens]:
		if module != null and property in module:
			return module.get(property)
	return null


func _toggle_title_controls() -> void:
	screens.toggle_title_controls()

var _panels: Dictionary:
	get: return screens._panels
var _reduced_motion_check: CheckBox:
	get: return screens._reduced_motion_check
var _option_sliders: Dictionary:
	get: return screens._option_sliders
var _quit_button: Button:
	get: return screens._quit_button
var _title_top_label: Label:
	get: return screens._title_top_label
var _title_tableau: Control:
	get: return screens._title_tableau
var _title_holder: Control:
	get: return screens._title_holder
var _title_controls: Control:
	get: return screens._title_controls
var _key_rows: VBoxContainer:
	get: return screens._key_rows
var _forge_rows: VBoxContainer:
	get: return screens._forge_rows
var _descent_grid: GridContainer:
	get: return screens._descent_grid
var _descent_detail: Label:
	get: return screens._descent_detail
var _descent_seed: Label:
	get: return screens._descent_seed
var _wave_label: Label:
	get: return hud._wave_label
var _room_label: Label:
	get: return hud._room_label
var _special_bar: ProgressBar:
	get: return hud._special_bar
var _special_value_label: Label:
	get: return hud._special_value_label
var _flask_sigils: Array:
	get: return hud._flask_sigils
var _flask_count_label: Label:
	get: return hud._flask_count_label
var _boss_ignited: bool:
	get: return hud._boss_ignited
var _boss_name_label: Label:
	get: return hud._boss_name_label
var _boss_intro: Dictionary:
	get: return hud._boss_intro
var _room_clear_banner: Control:
	get: return hud._room_clear_banner
var _hint_panel: Control:
	get: return hud._hint_panel
var _hint_label: Label:
	get: return hud._hint_label
var _threat_pips: UiHud.ThreatPips:
	get: return hud._threat_pips
