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
signal vow_toggled(id: String)

const C_VOID := Color("09070f")
const C_INK := Color("100d18")
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
## Streak multiplier colour by tier, dull to blazing.
const STREAK_TIER_COLORS := [C_MUTED, C_TEXT, C_GOLD, C_EMBER_HI, C_RED]

var _root: Control
var _hud: Control

## Burning-paper veil between chambers. `progress` 0 = the frame is covered in
## soot-black paper, 1 = fully burned away. The hole opens from `origin` with a
## ragged, noise-driven edge that glows like a paper edge catching fire.
const BURN_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform float progress = 0.0;
uniform vec2 origin = vec2(0.5, 0.55);
uniform float aspect = 1.7778;
// How far the edge travels by progress 1: past the farthest corner plus the
// ragged margin, so the burn always finishes wherever it starts.
uniform float reach = 1.47;
uniform vec4 ink : source_color = vec4(0.035, 0.027, 0.06, 1.0);
uniform vec4 ember : source_color = vec4(1.0, 0.48, 0.12, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.86, 0.55, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 q = vec2((UV.x - origin.x) * aspect, UV.y - origin.y);
	float d = length(q);
	float ragged = fbm(UV * vec2(aspect, 1.0) * 7.0) * 0.22;
	// Distance past the burning edge: > 0 is burned through.
	float edge = progress * reach - (d + ragged);
	float cover = 1.0 - smoothstep(0.0, 0.004, edge);
	// The glowing rim: a hot core just inside, embers fading behind it.
	float rim = exp(-abs(edge) * 60.0);
	float char_band = smoothstep(0.045, 0.0, -edge) * cover;
	vec3 col = mix(ink.rgb, vec3(0.12, 0.05, 0.03), char_band);
	col = mix(col, ember.rgb, rim * 0.9);
	col = mix(col, hot.rgb, pow(rim, 3.0));
	float alpha = max(cover, rim * 0.95);
	COLOR = vec4(col, alpha);
}
"""

static var _burn_material: ShaderMaterial

static func burn_material() -> ShaderMaterial:
	if _burn_material == null:
		var sh := Shader.new()
		sh.code = BURN_SHADER
		_burn_material = ShaderMaterial.new()
		_burn_material.shader = sh
	return _burn_material

var _hp_bar: ProgressBar
## Pale "chip" behind a bar: what was just lost lingers, then drains away.
var _hp_trail: ProgressBar
var _boss_trail: ProgressBar
var _trail_tweens: Dictionary = {}
var _hp_value_label: Label
var _special_bar: ProgressBar
var _special_value_label: Label
## Graveflame last shown, kept so the IGNITE prompt can be repainted.
var _special_shown := Vector2(0.0, Content.P_SPECIAL_MAX)
## The Graveflame fill's own style: it breathes white while Ignite is ready.
var _special_fill: StyleBoxFlat
var _ignite_tween: Tween
var _room_label: Label
var _wave_label: Label
var _score_label: Label
var _boss_panel: Control
var _boss_bar: ProgressBar
var _boss_value_label: Label
var _boss_name_label: Label
## Whether the boss bar wears its second-phase ember colours.
var _boss_ignited := false
var _flask_container: HBoxContainer
var _flask_sigils: Array = []
var _flask_count_label: Label
## Charges and belt size last shown, kept so the key prompt can be repainted.
var _flask_shown := Vector2i(Content.FLASK_MAX, Content.FLASK_MAX)
var _cells_label: Label
var _best_label: Label

var _room_clear_banner: Control
var _room_clear_name: Label
var _room_clear_tween: Tween
const ROOM_CLEAR_TOP := 148.0

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
## The lesson as written, with {action} tokens, so a device switch can re-fill it.
var _hint_template := ""
var _hint_tween: Tween
var _boss_phase_tag: Label
var _boss_phase_tween: Tween
var _fade: ColorRect

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


func _ready() -> void:
	layer = 50
	_ensure_pad_menu_bindings()
	get_viewport().gui_focus_changed.connect(_on_focus_changed)

	_root = Control.new()
	_root.name = "InterfaceRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Rift transition veil: sits under the HUD and every screen, above the world.
	_fade = _sheet(_root, Color(C_VOID, 0.0), Control.PRESET_FULL_RECT)
	_fade.name = "RiftFade"

	_build_hud()
	_build_title()
	_build_pause()
	_build_reward()
	_build_game_over()
	_build_victory()
	_build_forge()
	_build_options()
	_build_keys()
	_refresh_prompts()

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
	# The chamber card takes the boss bar's slot, always empty outside the
	# throne, so it never covers the platforms where enemies arrive. The boss
	# card sits on the throne room's brick foundation, clear of the Warden.
	_room_intro = _build_banner("RoomIntro", 18.0, 96.0, Vector2(470, 70), 26, 11, C_EMBER, Color("14101ceb"))
	_boss_intro = _build_banner("BossIntro", 546.0, 666.0, Vector2(620, 118), 40, 14, C_RED, Color("1a0c11f0"))
	_build_hint()


## Teaching prompt: sits below the fight, clear of the fighters and the HUD.
func _build_hint() -> void:
	_hint_panel = _hud_strip("HintBanner", Control.PRESET_BOTTOM_WIDE, -112.0, -54.0)
	var panel := _passive_panel(_hint_panel, _panel_box(Color("0f0b16f2"), C_EMBER, 10, 1, 10))
	var margin := _margin_container(26, 26, 9, 9)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	# This is the one line a new player must read, so it is set a step larger
	# than the ambient HUD text rather than matching it.
	_hint_label = _make_label("", 16, C_TEXT)
	# Inside the margin, or the first glyph sits on the panel's edge.
	margin.add_child(_hint_label)
	_hint_panel.visible = false


func _build_streak_meter() -> void:
	_streak_panel = _passive_panel(_hud, _panel_box(Color("1b1624d9"), Color("715026"), 10, 1, 8))
	_streak_panel.name = "StreakMeter"
	_streak_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_streak_panel.offset_left = 16.0
	_streak_panel.offset_top = 122.0
	_streak_panel.offset_right = 216.0
	_streak_panel.offset_bottom = 166.0
	_streak_panel.pivot_offset = Vector2(0.0, 25.0)
	var stack := _padded_stack(_streak_panel, 14, 8, 3)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	head.add_child(_make_label("STREAK", 11, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_streak_kills_label = _make_label("2 KILLS", 13, C_TEXT)
	head.add_child(_streak_kills_label)
	_streak_mult_label = _make_label("x1.25", 15, C_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_streak_mult_label)
	_streak_bar = _make_bar(C_GOLD, Color("3a2c14"), 6.0)
	_streak_bar.max_value = 100.0
	_streak_bar.value = 100.0
	stack.add_child(_streak_bar)
	_streak_panel.visible = false


## Fading title card used for room entries and the boss reveal.
func _build_banner(node_name: String, top: float, bottom: float, minimum: Vector2, title_size: int, sub_size: int, accent: Color, background: Color) -> Dictionary:
	var center := _hud_strip(node_name, Control.PRESET_TOP_WIDE, top, bottom)
	var panel := _passive_panel(center, _panel_box(background, accent, 10, 1, 12), minimum)
	var stack := _padded_stack(panel, 28, 10, 1)
	var sub := _make_label("", sub_size, C_MUTED)
	stack.add_child(sub)
	var title := _make_label("", title_size, accent)
	stack.add_child(title)
	center.visible = false
	return { "root": center, "title": title, "sub": sub, "tween": null }


func _play_banner(banner: Dictionary, title: String, subtitle: String, hold: float) -> void:
	(banner.title as Label).text = title
	(banner.sub as Label).text = subtitle
	banner.tween = _flash_card(banner.root, banner.tween, 0.22, hold, 0.55)


## Cut a title card short: stop its fade and hide it.
func _hide_banner(banner: Dictionary) -> void:
	if banner.is_empty():
		return
	_kill_tween(banner.tween)
	(banner.root as Control).visible = false


## Fade `node` in, hold it, fade it out and hide it, replacing the `previous`
## run of the same card. Returns the new tween so the caller can cut it short.
func _flash_card(node: Control, previous: Tween, fade_in: float, hold: float, fade_out: float) -> Tween:
	_kill_tween(previous)
	node.visible = true
	node.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := _ui_tween()
	tween.tween_property(node, "modulate:a", 1.0, fade_in)
	tween.tween_interval(hold)
	tween.tween_property(node, "modulate:a", 0.0, fade_out)
	tween.tween_callback(node.hide)
	return tween


## A tween that keeps running while the tree is paused: the reward, pause and
## run-end screens animate over a paused game.
func _ui_tween() -> Tween:
	return create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)


## Stop a tween that may be null or already finished.
static func _kill_tween(tween: Tween) -> void:
	if tween != null and is_instance_valid(tween):
		tween.kill()


func _build_player_status() -> void:
	var panel := _passive_panel(_hud, _panel_box(Color("100c16b8"), Color("3a3048"), 8, 1, 6))
	panel.name = "PlayerStatus"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16.0
	panel.offset_top = 14.0
	panel.offset_right = 296.0
	panel.offset_bottom = 112.0
	var stack := _padded_stack(panel, 12, 8, 5)

	_hp_value_label = _make_stat_line(stack, "VITALITY", "100 / 100", C_TEXT, 11)
	var hp_pair := _trailed_bar(C_RED, Color("4a1820"), 12.0)
	stack.add_child(hp_pair.holder)
	_hp_bar = hp_pair.bar
	_hp_trail = hp_pair.trail

	_special_value_label = _make_stat_line(stack, "GRAVEFLAME", "0 / 100", C_BLUE, 10)
	_special_bar = _make_bar(C_BLUE, Color("153243"), 7.0)
	_special_bar.max_value = Content.P_SPECIAL_MAX
	_special_bar.value = 0.0
	_special_fill = _special_bar.get_theme_stylebox("fill") as StyleBoxFlat
	stack.add_child(_special_bar)
	_notch_bar(_special_bar, _lance_marks(Content.P_SPECIAL_MAX))

	var supplies := HBoxContainer.new()
	supplies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	supplies.add_theme_constant_override("separation", 8)
	stack.add_child(supplies)
	var flask_tag := _make_label("FLASK", 10, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	flask_tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	supplies.add_child(flask_tag)
	_flask_container = HBoxContainer.new()
	_flask_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flask_container.add_theme_constant_override("separation", 5)
	_flask_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	supplies.add_child(_flask_container)
	_flask_count_label = _make_label("", 10, C_MINT, HORIZONTAL_ALIGNMENT_RIGHT)
	_flask_count_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	supplies.add_child(_flask_count_label)
	_rebuild_flask_sigils(Content.FLASK_MAX)


func _build_run_status() -> void:
	var panel := _passive_panel(_hud, _panel_box(Color("100c16b8"), Color("3a3048"), 8, 1, 6))
	panel.name = "RunStatus"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -226.0
	panel.offset_top = 14.0
	panel.offset_right = -16.0
	panel.offset_bottom = 132.0
	var stack := _padded_stack(panel, 12, 8, 4)

	_room_label = _make_label("ROOM 01 / 06", 12, C_EMBER_HI, HORIZONTAL_ALIGNMENT_RIGHT)
	stack.add_child(_room_label)
	_wave_label = _make_label("", 11, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_wave_label.visible = false
	stack.add_child(_wave_label)
	stack.add_child(_separator(C_EDGE))
	_score_label = _make_stat_line(stack, "SCORE", "0", C_TEXT)
	_cells_label = _make_stat_line(stack, "CELLS", "0", C_GOLD)
	_best_label = _make_stat_line(stack, "BEST", "0", C_MUTED)


func _build_boss_status() -> void:
	_boss_panel = _hud_strip("BossStatusAnchor", Control.PRESET_TOP_WIDE, 18.0, 96.0)
	var panel := _passive_panel(_boss_panel, _panel_box(Color("221019e6"), Color("8e3c49"), 10, 1, 8), Vector2(470, 70))
	panel.name = "BossStatus"
	var stack := _padded_stack(panel, 18, 10, 4)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	_boss_name_label = _make_label("THE EMBER WARDEN", 13, Color("f2c3c6"), HORIZONTAL_ALIGNMENT_LEFT)
	head.add_child(_boss_name_label)
	_boss_value_label = _make_label("", 12, C_RED, HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_boss_value_label)
	var boss_pair := _trailed_bar(Color("b94350"), Color("41131b"), 13.0)
	stack.add_child(boss_pair.holder)
	_boss_bar = boss_pair.bar
	_boss_trail = boss_pair.trail
	# The Warden ignites at this mark, so the fight's midpoint is readable.
	_notch_bar(boss_pair.holder, [Content.BOSS_PHASE2_AT])
	_boss_panel.visible = false


func _build_boss_phase_tag() -> void:
	# Compact phase-2 callout pinned under the boss bar: never center-screen.
	_boss_phase_tag = _make_label("", 13, Color("f2c3c6"))
	_boss_phase_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_phase_tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_phase_tag.offset_left = -260.0
	_boss_phase_tag.offset_right = 260.0
	_boss_phase_tag.offset_top = 100.0
	_boss_phase_tag.offset_bottom = 124.0
	_boss_phase_tag.visible = false
	_hud.add_child(_boss_phase_tag)


func _build_room_clear_banner() -> void:
	_room_clear_banner = _hud_strip("RoomClearBanner", Control.PRESET_TOP_WIDE, ROOM_CLEAR_TOP, ROOM_CLEAR_TOP + 104.0)
	var panel := _passive_panel(_room_clear_banner, _panel_box(Color("141020eb"), C_MINT, 10, 1, 12), Vector2(490, 88))
	var stack := _padded_stack(panel, 24, 10, 1)
	stack.add_child(_make_label("CHAMBER CLEARED", 22, C_MINT))
	_room_clear_name = _make_label("PATH UNSEALED", 12, C_MUTED)
	stack.add_child(_room_clear_name)
	_room_clear_banner.visible = false


# --- Screen construction -----------------------------------------------------

func _build_title() -> void:
	var panel := _screen("title", true, C_EMBER)
	# The title is a full-scene vista: drop the generic screen header band so
	# the sky runs unbroken from the moon down to the furnace horizon.
	panel.get_node("TopBand").hide()
	panel.get_node("Horizon").hide()
	# Original menu art: the Threshold of the Descent tableau (scripts/title_tableau.gd).
	_title_tableau = TitleTableau.new()
	panel.add_child(_title_tableau)
	_title_tableau.candle_struck.connect(func() -> void: cue.emit("footlight"))
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
	var start := _title_entry(nav, "BEGIN DESCENT", "start", true, start_requested.emit)
	var forge := _title_entry(nav, "THE FORGE", "forge", false, forge_requested.emit)
	_title_controls_button = _title_entry(nav, "CONTROLS", "controls", false, _toggle_title_controls)
	# OPTIONS goes after CONTROLS so the tested BEGIN > FORGE > CONTROLS pad focus chain holds.
	var options_button := _title_entry(nav, "OPTIONS", "options", false, options_requested.emit)
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
	var button := _button(text, node_name, primary, Vector2(300, height))
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(on_press)
	if not primary:
		_title_quiet_button(button)
	nav.add_child(button)
	return button


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
	var dim := _sheet(overlay, Color(0.02, 0.015, 0.03, 0.72), Control.PRESET_FULL_RECT, true)
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
	var card := _passive_panel(center, _panel_box(Color("100d18f2"), C_EDGE, 12, 1, 14), Vector2(520, 0))
	card.name = "ControlsCard"
	var stack := _padded_stack(card, 26, 14, 3)
	stack.add_child(_make_label("CONTROLS", 20, C_TEXT))
	stack.add_child(_separator(C_EDGE))
	# Rendered from the LIVE input map, so this screen can never disagree with
	# what the game actually does -- including after a rebind.
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 12)
	stack.add_child(header)
	var corner := _make_label("", 11, C_EMBER_HI, HORIZONTAL_ALIGNMENT_LEFT)
	corner.size_flags_stretch_ratio = 1.1
	header.add_child(corner)
	for caption in ["KEYBOARD", "GAMEPAD"]:
		header.add_child(_make_label(caption, 11, C_EMBER_HI, HORIZONTAL_ALIGNMENT_RIGHT))
	var cells := {}
	for row in Content.CONTROLS_ROWS:
		var action := str(row.action)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 12)
		stack.add_child(line)
		var name_label := _make_label(str(row.label), 12, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.size_flags_stretch_ratio = 1.1
		line.add_child(name_label)
		var key_label := _make_label("", 12, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		line.add_child(key_label)
		var pad_label := _make_label("", 12, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		line.add_child(pad_label)
		cells[action] = { "key": key_label, "pad": pad_label }
	stack.add_child(_make_label(Content.CONTROLS_HINTS, 11, C_MUTED))
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
## so pad names are mapped explicitly.
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
				var code := _event_keycode(event as InputEventKey)
				if code != 0:
					keys.append(OS.get_keycode_string(code))
			elif event is InputEventJoypadButton:
				pads.append(_pad_button_name((event as InputEventJoypadButton).button_index))
			elif event is InputEventJoypadMotion:
				var motion := event as InputEventJoypadMotion
				pads.append(_pad_axis_name(motion.axis, motion.axis_value))
	return { "key": " / ".join(keys), "pad": " / ".join(pads) }


## The device the player last touched, "key" (keyboard or mouse) or "pad".
## Every prompt names that device's binding.
static var last_device := "key"


## Key cap for `action` on the device last used, such as "[F]" or "[X]", so a
## prompt names the key the player actually presses, even after a rebind.
static func prompt(action: String) -> String:
	var text := _binding_text(action)
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


## Follow the player between keyboard and pad; the prompts on screen follow.
func _track_device(event: InputEvent) -> void:
	var device := last_device
	if (event is InputEventJoypadButton and event.is_pressed()) or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		device = "pad"
	elif (event is InputEventKey and event.is_pressed()) or event is InputEventMouseButton:
		device = "key"
	if device != last_device:
		last_device = device
		_refresh_prompts()


## Repaint every visible key prompt after a device switch or a rebind.
func _refresh_prompts() -> void:
	_paint_flask_label()
	_paint_special_label()
	_paint_reward_footer()
	(_panels["pause"].get_meta("footer_label") as Label).text = "%s  resume" % prompt("pause")
	if _hint_panel.visible:
		_hint_label.text = fill_prompts(_hint_template)


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


## The key a binding stores: the physical key, or the logical one for events
## that carry no physical code.
static func _event_keycode(key: InputEventKey) -> int:
	var code := int(key.physical_keycode)
	if code == 0:
		code = int(key.keycode)
	return code


## 1..9 select the matching boon card; anything else returns -1.
static func _boon_index_for_key(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1
	return -1


## Runs before GUI navigation, so a pending rebind can take the arrow keys and
## Enter, and so a navigation press is known before focus moves.
func _input(event: InputEvent) -> void:
	_track_device(event)
	if not _listening_action.is_empty():
		if event is InputEventKey and event.pressed and not event.is_echo():
			_capture_rebind(_event_keycode(event as InputEventKey))
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_focus_hovered()
		return
	for action in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
		if event.is_action_pressed(action, true):
			_nav_frame = Engine.get_process_frames()


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
	var old_keys := _key_codes(action)
	var note := ""
	for row in Content.CONTROLS_ROWS:
		var other := str(row.action)
		var keys := _key_codes(other)
		if other == action or not keys.has(code):
			continue
		keys.erase(code)
		var kept: int = keys[0] if not keys.is_empty() else (old_keys[0] if not old_keys.is_empty() else 0)
		binding_changed.emit(other, kept)
		note = "%s gives up %s  ·  now %s" % [str(row.label), OS.get_keycode_string(code), _key_text_for(other)]
	binding_changed.emit(action, code)
	_set_keys_note(note)


## Physical keycodes bound to `action`, in binding order.
static func _key_codes(action: String) -> Array:
	var codes: Array = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			codes.append(_event_keycode(event as InputEventKey))
	return codes


## The line under the Keys heading: what a rebind just moved, in gold, or the
## instructions when nothing has.
func _set_keys_note(note: String) -> void:
	var label := (_panels["keys"] as Control).get_meta("note_label") as Label
	label.text = note if not note.is_empty() else KEYS_HELP
	label.add_theme_color_override("font_color", C_GOLD if not note.is_empty() else C_MUTED)


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
	sync_keys()
	sync_controls()
	_set_keys_note("Every key is back where the keep first set it.")


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


func _on_focus_changed(_control: Control) -> void:
	if Engine.get_process_frames() == _nav_frame:
		cue.emit("ui_move")


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


func is_panel_visible(name: String) -> bool:
	return _panels.has(name) and (_panels[name] as Control).visible


## Esc, pad B and pad START leave a settings screen through its own BACK
## button, so every screen exits one way and a paused run behind it never sees
## the press. B on the pause card resumes. Returns whether a screen took it.
func _back_out(event: InputEvent) -> bool:
	for name in ["keys", "options", "forge"]:
		if is_panel_visible(name):
			((_panels[name] as Control).get_meta("back_button") as Button).pressed.emit()
			return true
	if is_panel_visible("pause") and event.is_action_pressed("ui_cancel"):
		resume_requested.emit()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _back_out(event):
			get_viewport().set_input_as_handled()
			return
	# Boon cards print their index, so the number keys have to actually pick one.
	if event is InputEventKey and event.pressed and not event.echo:
		var reward: Control = _panels.get("reward", null)
		if reward != null and reward.visible:
			var index := _boon_index_for_key((event as InputEventKey).keycode)
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


func _build_pause() -> void:
	var panel := _screen("pause", false, C_BLUE)
	var content := _dialog(panel, Vector2(640, 0), C_BLUE, 48, 32)
	content.add_theme_constant_override("separation", 10)

	content.add_child(_make_label("DESCENT SUSPENDED", 13, C_BLUE))
	content.add_child(_make_label("PAUSED", 50, C_TEXT))
	content.add_child(_make_label("The keep will wait. Catch your breath.", 16, C_MUTED))
	content.add_child(_separator(C_EDGE))

	var actions := _button_row(content)
	var resume := _button("RESUME", "resume", true, Vector2(200, 54))
	resume.pressed.connect(resume_requested.emit)
	actions.add_child(resume)
	var options_button := _button("OPTIONS", "pause_options", false, Vector2(200, 54))
	options_button.pressed.connect(options_requested.emit)
	actions.add_child(options_button)
	_quit_button = _button("QUIT TO TITLE", "quit", false, Vector2(200, 54))
	_quit_button.pressed.connect(_on_quit_pressed)
	actions.add_child(_quit_button)

	# The descent so far: boons carried, relics, vows and the seed.
	var ledger := _padded_stack(_passive_panel(content, _panel_box(C_INK, C_EDGE, 10, 1, 0)), 22, 14, 8)
	ledger.add_child(_make_label("THIS DESCENT", 12, C_EMBER_HI, HORIZONTAL_ALIGNMENT_LEFT))
	_descent_grid = GridContainer.new()
	_descent_grid.columns = 8
	_descent_grid.add_theme_constant_override("h_separation", 8)
	_descent_grid.add_theme_constant_override("v_separation", 8)
	ledger.add_child(_descent_grid)
	_descent_detail = _make_label("", 13, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	_descent_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_descent_detail.custom_minimum_size.y = 36.0
	ledger.add_child(_descent_detail)
	_descent_relics = _make_label("", 12, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	ledger.add_child(_descent_relics)
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ledger.add_child(foot)
	_descent_vows = _make_label("", 12, C_RED, HORIZONTAL_ALIGNMENT_LEFT)
	foot.add_child(_descent_vows)
	_descent_seed = _make_label("", 12, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	foot.add_child(_descent_seed)
	set_descent({}, 0)

	var footer := _make_label("", 12, C_MUTED)
	content.add_child(footer)
	panel.set_meta("footer_label", footer)


## Fill the pause card's ledger: a medallion per boon carried (with its stack
## count), the relics owned, the vows sworn and the seed. Called as the pause
## card opens, so it always shows the descent as it stands.
func set_descent(taken: Dictionary, seed_value: int) -> void:
	_clear_children(_descent_grid)
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
			relics.append("%s %s" % [str(u.title).to_upper(), _roman(rank)])
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
		tile.add_theme_stylebox_override(state, _panel_box(Color(C_SURFACE_HI, 0.6), C_GOLD, 8, 1, 0))
	var medallion := BoonMedallion.new()
	medallion.setup(str(upgrade.id), rc, Content.upgrade_rarity(upgrade) == "epic", Vector2(52, 52))
	tile.add_child(medallion)
	medallion.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if count > 1:
		var badge := _make_label("×%d" % count, 13, C_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		badge.add_theme_constant_override("outline_size", 4)
		badge.add_theme_color_override("font_outline_color", C_VOID)
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
		quit_to_title_requested.emit()
		return
	_set_quit_warning(true)
	_quit_confirm = _ui_tween()
	_quit_confirm.tween_interval(2.0)
	_quit_confirm.tween_callback(_set_quit_warning.bind(false))


func _set_quit_warning(on: bool) -> void:
	_kill_tween(_quit_confirm)
	_quit_confirm = null
	_quit_button.text = "ABANDON DESCENT?" if on else "QUIT TO TITLE"
	_style_button(_quit_button, false)
	if on:
		for state in ["normal", "hover", "focus"]:
			_quit_button.add_theme_stylebox_override(state, _button_box(Color("3a1418"), C_RED, 2))
		_quit_button.add_theme_color_override("font_focus_color", C_RED)


## Small numbers as Roman numerals, the keep's way of counting ranks and chambers.
static func _roman(n: int) -> String:
	var out := ""
	for pair in [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]:
		while n >= int(pair[0]):
			out += str(pair[1])
			n -= int(pair[0])
	return out


func _build_reward() -> void:
	var panel := _screen("reward", false, C_GOLD)
	# No enclosing card: the boons lie on the dimmed chamber like cards dealt
	# onto a table, so the choice is the only object on screen.
	var content := _dialog(panel, Vector2(1000, 0), C_GOLD, 12, 8)
	var holder := panel.get_meta("dialog") as PanelContainer
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 6)

	content.add_child(_make_label("CHAMBER CLEARED", 13, C_MINT))
	content.add_child(_make_label("Choose a Boon", 46, C_TEXT))
	content.add_child(_make_label("Every chamber feeds the flame.", 15, C_MUTED))
	content.add_child(_ornament(C_GOLD))

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
	var footer := _make_label("", 12, C_MUTED)
	content.add_child(footer)
	panel.set_meta("footer_label", footer)


## A short rule with a lozenge at its centre, the keep's printer's mark.
func _ornament(color: Color) -> Control:
	var mark := Ornament.new()
	mark.color = color
	mark.custom_minimum_size = Vector2(0, 18)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return mark


class Ornament extends Control:
	var color := Color.WHITE
	func _draw() -> void:
		var c := size * 0.5
		var w := minf(220.0, size.x * 0.4)
		draw_line(c + Vector2(-w, 0.0), c + Vector2(-12.0, 0.0), Color(color, 0.55), 1.0)
		draw_line(c + Vector2(12.0, 0.0), c + Vector2(w, 0.0), Color(color, 0.55), 1.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -5.0), c + Vector2(6.0, 0.0), c + Vector2(0.0, 5.0), c + Vector2(-6.0, 0.0)]), color)
		draw_circle(c + Vector2(-w, 0.0), 1.5, Color(color, 0.55))
		draw_circle(c + Vector2(w, 0.0), 1.5, Color(color, 0.55))


func _build_game_over() -> void:
	# See-through: the fallen knight stays in the frame behind the verdict.
	var panel := _screen("gameover", false, C_RED)
	var content := _dialog(panel, Vector2(760, 620), C_RED, 48, 30)
	content.add_theme_constant_override("separation", 10)

	content.add_child(_make_label("THE KNIGHT FALLS", 13, C_RED))
	content.add_child(_make_label("THE FLAME FADES", 54, C_TEXT))
	var epitaph := _make_label(Content.EPITAPHS[0], 18, C_MUTED)
	content.add_child(epitaph)
	panel.set_meta("line_label", epitaph)
	content.add_child(_separator(Color("75414b")))
	var retry := _button("DESCEND AGAIN", "restart", true, Vector2(250, 56))
	_build_run_end_body(panel, content, Color("75414b"), "Return stronger, or descend again while the embers are warm.", retry)


func _build_victory() -> void:
	var panel := _screen("victory", false, C_MINT)
	var content := _dialog(panel, Vector2(760, 640), C_MINT, 48, 30)
	content.add_theme_constant_override("separation", 10)

	var kicker := _make_label("WARDEN DEFEATED", 13, C_MINT)
	content.add_child(kicker)
	panel.set_meta("kicker_label", kicker)
	content.add_child(_make_label("GRAVEFLAME ENDURES", 50, C_TEXT))
	var closing := _make_label(Content.VICTORY_LINES[0], 17, C_MUTED)
	content.add_child(closing)
	panel.set_meta("line_label", closing)
	content.add_child(_separator(C_MINT))
	var again := _button("DESCEND AGAIN", "again", true, Vector2(230, 56))
	_build_run_end_body(panel, content, Color("1f5b52"), "A brighter ember waits at the beginning.", again)
	# A first win points to the vows, just above the parting line.
	var vows := _make_label("VOWS AWAKEN AT THE FORGE.", 14, C_GOLD)
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
	content.add_child(_make_label("SCORE", 11, C_MUTED))
	var score := _make_label("0", 44, C_TEXT)
	content.add_child(score)
	var best := _make_label("BEST  0", 12, C_MUTED)
	content.add_child(best)
	panel.set_meta("score_label", score)
	panel.set_meta("best_label", best)
	var cells := _make_label("CELLS SECURED  +0", 20, C_GOLD)
	cells.visible = false
	content.add_child(cells)
	panel.set_meta("cells_label", cells)
	_build_summary(content, panel, tile_edge)
	content.add_child(_make_label(parting, 14, C_MUTED))
	var actions := _button_row(content)
	again.pressed.connect(restart_requested.emit)
	actions.add_child(again)
	var title := _button("RETURN TO TITLE", "title", false, Vector2(230, 56))
	title.pressed.connect(quit_to_title_requested.emit)
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
		var tile := _passive_panel(grid, _panel_box(C_INK, edge, 8, 1, 0), Vector2(0, 52))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var stack := _padded_stack(tile, 10, 4, 0)
		stack.add_child(_make_label(entry[1], 10, C_MUTED))
		var value := _make_label("-", 17, C_TEXT)
		stack.add_child(value)
		labels[entry[0]] = value
	panel.set_meta("summary_labels", labels)


func _build_forge() -> void:
	var panel := _screen("forge", true, C_EMBER)
	var content := _dialog(panel, Vector2(900, 650), C_EMBER, 42, 30)
	content.add_theme_constant_override("separation", 9)

	content.add_child(_make_label("BETWEEN LIVES", 12, C_EMBER_HI))
	content.add_child(_make_label("THE FORGE", 46, C_TEXT))
	content.add_child(_make_label("Temper the next life with cells carried out of the keep.", 15, C_MUTED))

	var balance_panel := PanelContainer.new()
	balance_panel.add_theme_stylebox_override("panel", _panel_box(C_INK, Color("715026"), 9, 1, 0))
	content.add_child(balance_panel)
	var balance := _make_label("AVAILABLE CELLS   0", 18, C_GOLD)
	balance.custom_minimum_size.y = 38.0
	balance_panel.add_child(balance)
	panel.set_meta("balance_label", balance)

	_forge_rows = _scroll_list(content, 350.0, 8)

	var back := _button("BACK", "back", false, Vector2(220, 50), "ui_back")
	back.pressed.connect(back_from_forge_requested.emit)
	_button_row(content).add_child(back)
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
	head.add_child(_make_label(title, 14, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	var readout := _make_label("%d%%" % roundi(value * 100.0), 12, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
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
	_paper_slider(slider)
	row.add_child(slider)
	slider.value_changed.connect(func(v: float):
		readout.text = "%d%%" % roundi(v * 100.0)
		option_value_changed.emit(key, v)
	)
	_option_sliders[key] = { "slider": slider, "readout": readout }


## Settings screen: reachable from the title and from the pause menu, so audio
## and accessibility are not locked behind starting a run.
func _build_options() -> void:
	var panel := _screen("options", true, C_EMBER)
	var content := _dialog(panel, Vector2(880, 0), C_EMBER, 44, 28)
	content.add_theme_constant_override("separation", 8)

	content.add_child(_make_label("SETTINGS", 12, C_EMBER_HI))
	content.add_child(_make_label("OPTIONS", 44, C_TEXT))
	content.add_child(_separator(C_EDGE))

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

	sound.add_child(_make_label("AUDIO", 12, C_EMBER_HI, HORIZONTAL_ALIGNMENT_LEFT))
	_slider_row(sound, "Master volume", "master", 0.9)
	_slider_row(sound, "Music", "music", 0.75)
	_slider_row(sound, "Effects", "sfx", 0.9)
	_option_check(sound, "music_on", "Score", "The procedural score and the Warden's theme.")

	seen.add_child(_make_label("DISPLAY", 12, C_EMBER_HI, HORIZONTAL_ALIGNMENT_LEFT))
	_option_check(seen, "fullscreen", "Fullscreen", "Fill the display instead of a window.")
	_option_check(seen, "vibration", "Controller vibration", "The pad rumbles with hits, parries and falls.")
	seen.add_child(_make_label("ACCESSIBILITY", 12, C_EMBER_HI, HORIZONTAL_ALIGNMENT_LEFT))
	# Shake on its own, so a player can calm the camera and keep the hit-stop
	# and slow motion that reduced motion also takes away.
	_slider_row(seen, "Screen shake", "shake", 1.0)
	_reduced_motion_check = _option_check(seen, "reduced_motion", "Reduced motion", "Disables camera shake and softens particles.")
	_option_check(seen, "reduced_flash", "Reduced flash", "Reduces high-contrast impact flashes.")

	var footer := _button_row(content)
	var keys := _button("KEYS", "options_keys", false, Vector2(200, 50))
	keys.pressed.connect(keys_requested.emit)
	footer.add_child(keys)
	var back := _button("BACK", "options_back", false, Vector2(200, 50), "ui_back")
	back.pressed.connect(back_from_options_requested.emit)
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
	for key in _option_checks:
		(_option_checks[key] as CheckBox).set_pressed_no_signal(bool(opts.get(key, false)))


## Keyboard text for one action, or a dash when nothing is bound.
static func _key_text_for(action: String) -> String:
	var text := str(_binding_text(action)["key"])
	return text if not text.is_empty() else "—"


const KEYS_HELP := "Choose a key, then press the one you want.  ESC cancels."

## Rebinding screen. Rows come from Content.CONTROLS_ROWS so this list and the
## controls reference can never disagree about what is rebindable.
func _build_keys() -> void:
	var panel := _screen("keys", true, C_EMBER)
	var content := _dialog(panel, Vector2(720, 660), C_EMBER, 44, 28)
	content.add_theme_constant_override("separation", 8)

	content.add_child(_make_label("SETTINGS", 12, C_EMBER_HI))
	content.add_child(_make_label("KEY BINDINGS", 42, C_TEXT))
	var note := _make_label(KEYS_HELP, 13, C_MUTED)
	content.add_child(note)
	panel.set_meta("note_label", note)
	content.add_child(_separator(C_EDGE))

	_key_rows = _scroll_list(content, 300.0, 5)

	content.add_child(_make_label("Gamepad bindings are fixed and always live.", 12, C_MUTED))
	var footer := _button_row(content)
	var restore := _button("RESTORE DEFAULTS", "keys_restore", false, Vector2(220, 50))
	restore.pressed.connect(_restore_default_keys)
	footer.add_child(restore)
	var back := _button("BACK", "keys_back", false, Vector2(220, 50), "ui_back")
	back.pressed.connect(func():
		_cancel_rebind()
		back_from_keys_requested.emit()
	)
	footer.add_child(back)
	panel.set_meta("back_button", back)


## Rebuild the rebinding rows, and every prompt that names a key, against the
## live input map.
func sync_keys() -> void:
	if _key_rows == null:
		return
	_refresh_prompts()
	_cancel_rebind()
	var kept := _focused_name_in(_key_rows)
	_clear_children(_key_rows)
	for row in Content.CONTROLS_ROWS:
		var action := str(row.action)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		_key_rows.add_child(line)
		var label := _make_label(str(row.label), 14, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		line.add_child(label)
		# Empty cue kind: the label changing to "PRESS A KEY" is the feedback, and
		# a confirm blip here would imply a commit that has not happened yet.
		var button := _button(_key_text_for(action), "Key_%s" % action, false, Vector2(200, 40), "")
		button.pressed.connect(_begin_rebind.bind(action, button))
		line.add_child(button)
	# A rebind rebuilds the list under the cursor: stay on the same row.
	if not kept.is_empty():
		_focus_row.call_deferred(_key_rows, kept, null)


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


## Headings share the wordmark's serif without its wide tracking, so every
## screen title reads as part of the same printed keep rather than a web form.
static var _heading: Font

static func _heading_font() -> Font:
	if _heading == null:
		var base := _title_font()
		if base is FontVariation:
			var v := FontVariation.new()
			v.base_font = (base as FontVariation).base_font
			v.spacing_glyph = 1
			_heading = v
		else:
			_heading = base
	return _heading


func _build_title_stack(text: String, size: int) -> Control:
	# Three stacked labels: void drop shadow, ember-rimmed orange core, gold face.
	# The stack takes the lettering's real width: a bare Control never grows to
	# its children, and an overflowing centred label would slide its text right.
	var stack := Control.new()
	stack.name = "TitleStack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var font := _title_font()
	var shadow := _make_label(text, size, VFX.VOID)
	shadow.add_theme_color_override("font_outline_color", VFX.VOID)
	shadow.add_theme_constant_override("outline_size", 4)
	var rim := _make_label(text, size, VFX.ORANGE)
	rim.add_theme_color_override("font_outline_color", VFX.EMBER)
	rim.add_theme_constant_override("outline_size", 2)
	# A white face tinted by self_modulate, so the flicker never restyles it.
	var face := _make_label(text, size, Color.WHITE)
	face.self_modulate = VFX.GOLD
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
	var run := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	stack.custom_minimum_size = Vector2(run.x + 8.0, maxf(font.get_height(size), float(size) * 1.2) + 8.0)
	_title_top_label = face
	return stack


func _process(delta: float) -> void:
	_poll_input_lock()
	_poll_arming()
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
		_title_top_label.self_modulate = VFX.GOLD
		return
	_title_t += delta
	var wave := 0.5 + 0.5 * sin(_title_t * 2.6)
	var flicker := 1.0 + sin(_title_t * 11.0) * 0.03 + sin(_title_t * 29.0) * 0.03
	var col := VFX.GOLD.lerp(VFX.ORANGE, wave * 0.4)
	# Modulating rather than overriding font_color avoids reshaping the wordmark every frame.
	_title_top_label.self_modulate = Color(col.r * flicker, col.g * flicker, col.b * flicker, 1.0)


# --- Responsive building blocks ---------------------------------------------

func _screen(name: String, opaque: bool, accent: Color) -> Control:
	var screen := Control.new()
	screen.name = name.capitalize() + "Screen"
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var backdrop := C_VOID if opaque else Color(0.025, 0.02, 0.04, 0.88)
	_sheet(screen, backdrop, Control.PRESET_FULL_RECT, true)

	var band_alpha := 0.075 if opaque else 0.045
	var top_band := _sheet(screen, Color(accent, band_alpha), Control.PRESET_TOP_WIDE)
	top_band.name = "TopBand"
	top_band.offset_bottom = 150.0

	var horizon := _sheet(screen, Color(accent, 0.42), Control.PRESET_TOP_WIDE)
	horizon.name = "Horizon"
	horizon.offset_bottom = 2.0

	var lower_band := _sheet(screen, Color(0.0, 0.0, 0.0, 0.2), Control.PRESET_BOTTOM_WIDE)
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


## A styled panel that lets clicks through: HUD cards must never swallow a
## click meant for the game.
func _passive_panel(parent: Control, style: StyleBox, minimum := Vector2.ZERO) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


## A vertical stack inside `panel`, padded evenly on each axis and as
## click-transparent as the panel. Returns the stack to fill.
func _padded_stack(panel: Container, pad_x: int, pad_y: int, separation: int) -> VBoxContainer:
	var margin := _margin_container(pad_x, pad_x, pad_y, pad_y)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", separation)
	margin.add_child(stack)
	return stack


## A full-width HUD strip that centres whatever card it holds. With
## PRESET_BOTTOM_WIDE, negative offsets measure up from the bottom edge.
func _hud_strip(node_name: String, preset: Control.LayoutPreset, top: float, bottom: float) -> CenterContainer:
	var center := CenterContainer.new()
	center.name = node_name
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(center)
	center.set_anchors_and_offsets_preset(preset)
	center.offset_top = top
	center.offset_bottom = bottom
	return center


## A flat sheet of colour laid over `preset`. Decorative sheets let input
## through; a backdrop that must stop clicks reaching what lies beneath passes
## blocks_input.
func _sheet(parent: Control, color: Color, preset: Control.LayoutPreset, blocks_input := false) -> ColorRect:
	var sheet := ColorRect.new()
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP if blocks_input else Control.MOUSE_FILTER_IGNORE
	sheet.color = color
	parent.add_child(sheet)
	sheet.set_anchors_and_offsets_preset(preset)
	return sheet


## A centred row of dialog buttons, spaced like every other footer.
func _button_row(parent: Container) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	return row


## A list that scrolls once it outgrows its dialog. Returns the rows container.
func _scroll_list(parent: Container, min_height: float, separation: int) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = min_height
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Pad and keyboard focus may walk below the fold; the list must follow it.
	scroll.follow_focus = true
	# A narrow ink channel with an ember grip, not the stock grey bar.
	var bar := scroll.get_v_scroll_bar()
	bar.add_theme_stylebox_override("scroll", _flat_box(C_INK, 3.0))
	bar.add_theme_stylebox_override("scroll_focus", _flat_box(C_INK, 3.0))
	bar.add_theme_stylebox_override("grabber", _flat_box(Color(C_EMBER, 0.55), 3.0))
	bar.add_theme_stylebox_override("grabber_highlight", _flat_box(C_EMBER_HI, 3.0))
	bar.add_theme_stylebox_override("grabber_pressed", _flat_box(C_GOLD, 3.0))
	parent.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", separation)
	scroll.add_child(rows)
	return rows


func _make_label(text: String, size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Compact HUD labels must keep their intrinsic width inside HBoxContainers;
	# callers that render paragraphs opt into wrapping explicitly.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("000000b0"))
	label.add_theme_constant_override("outline_size", 2 if size >= 18 else 1)
	if size >= 30:
		label.add_theme_font_override("font", _heading_font())
		label.add_theme_constant_override("outline_size", 3)
	return label


func _make_stat_line(parent: VBoxContainer, title: String, value: String, value_color: Color, value_size := 12) -> Label:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var caption := _make_label(title, 10, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	row.add_child(caption)
	var result := _make_label(value, value_size, value_color, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(result)
	return result


## A bar with a chip trail behind it. Returns { holder, bar, trail }.
func _trailed_bar(fill: Color, background: Color, height: float) -> Dictionary:
	var holder := Control.new()
	holder.custom_minimum_size.y = height
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var trail := _make_bar(Color("f4e2c8"), background, height)
	holder.add_child(trail)
	trail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bar := _make_bar(fill, Color(0.0, 0.0, 0.0, 0.0), height)
	holder.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for b in [trail, bar]:
		(b as ProgressBar).max_value = 100.0
		(b as ProgressBar).value = 100.0
	return { "holder": holder, "bar": bar, "trail": trail }

## Losses hold as a pale chip for a beat, then drain; gains fill at once.
func _set_trailed(bar: ProgressBar, trail: ProgressBar, value: float, maximum: float) -> void:
	bar.max_value = maxf(1.0, maximum)
	trail.max_value = bar.max_value
	var v := clampf(value, 0.0, bar.max_value)
	bar.value = v
	_kill_tween(_trail_tweens.get(trail))
	if v >= trail.value or Feedback.motion_reduced:
		trail.value = v
		return
	var tw := _ui_tween()
	tw.tween_interval(0.35)
	tw.tween_property(trail, "value", v, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_trail_tweens[trail] = tw


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
	box.corner_detail = 1
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
	# One-segment corners: cut with a blade, not rounded like a web card.
	box.corner_detail = 1
	box.anti_aliasing_size = 0.6
	if shadow > 0:
		# A hard, offset shadow: one sheet of paper lying on another.
		box.shadow_color = Color(0.0, 0.0, 0.0, 0.62)
		box.shadow_size = 1
		box.shadow_offset = Vector2(4, 6) if shadow >= 6 else Vector2(3, 4)
	return box


func _separator(color: Color) -> ColorRect:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size.y = 1.0
	line.color = Color(color.r, color.g, color.b, 0.55)
	return line


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
		button.pressed.connect(cue.emit.bind(cue_kind))
	_style_button(button, primary)
	return button


## The ember (primary) or quiet (secondary) look of a menu button in every state.
func _style_button(button: Button, primary: bool) -> void:
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


func _button_box(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := _panel_box(background, border, 9, border_width, 0)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box


## Toggle glyphs and slider grips, drawn procedurally like the rest of the game's art.
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
		"grip": ImageTexture.create_from_image(_lozenge_image(C_GOLD)),
		"grip_hot": ImageTexture.create_from_image(_lozenge_image(Color.WHITE.lerp(C_GOLD, 0.35))),
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


## A flat, square-cut fill padded by `margin` on every side: the ink channel
## and ember grip of scrollbars and sliders.
func _flat_box(color: Color, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(margin)
	box.set_corner_radius_all(2)
	box.corner_detail = 1
	return box


## Sliders in the keep's idiom: an ink groove filled with ember up to a gold
## lozenge grip, which brightens under focus or the cursor.
func _paper_slider(slider: HSlider) -> void:
	slider.add_theme_stylebox_override("slider", _flat_box(C_SURFACE_HI, 3.0))
	slider.add_theme_stylebox_override("grabber_area", _flat_box(C_EMBER, 3.0))
	slider.add_theme_stylebox_override("grabber_area_highlight", _flat_box(C_EMBER_HI, 3.0))
	slider.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var icons := _toggle_icons()
	slider.add_theme_icon_override("grabber", icons["grip"])
	slider.add_theme_icon_override("grabber_highlight", icons["grip_hot"])


## An 18px lozenge with a dark rim, drawn pixel by pixel like the toggles.
static func _lozenge_image(fill: Color) -> Image:
	var size := 18
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var d := absf(x - c) + absf(y - c)
			if d <= c:
				img.set_pixel(x, y, fill if d <= c - 2.0 else C_INK)
	return img


## A toggle bound to Save option `key`, registered so sync_options can
## restore it without emitting.
func _option_check(parent: Container, key: String, title: String, description: String) -> CheckBox:
	var check := _check(title, description)
	parent.add_child(check)
	_option_checks[key] = check
	check.toggled.connect(func(value: bool): option_toggled.emit(key, value))
	return check


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
	check.toggled.connect(func(_on: bool): cue.emit("ui_confirm"))
	return check


# --- Public API --------------------------------------------------------------

func show_panel(name: String, fade: float = 0.0) -> void:
	if not _panels.has(name):
		return
	var panel: Control = _panels[name]
	panel.visible = true
	panel.modulate = Color.WHITE
	if fade > 0.0 and not Feedback.motion_reduced:
		panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var tween := _ui_tween()
		tween.tween_property(panel, "modulate:a", 1.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if name == "title":
		_set_title_controls_open(false)
		# Only a real arrival replays the reveal; stepping back from a
		# title sub-screen must not grey the menu out again.
		_title_tableau.arrive(not (_last_panel in ["forge", "options", "keys"]))
		_celebrate_new_victories()
	_last_panel = name
	if name != "pause":
		hide_room_clear()
	if name == "keys":
		_set_keys_note("")
	if name == "gameover":
		var buttons: Array = panel.get_meta("buttons")
		_arm_buttons(buttons, 0.9, buttons[0])
	_focus_first_control(panel)


func hide_panel(name: String) -> void:
	if _panels.has(name):
		(_panels[name] as Control).visible = false


func hide_all_panels() -> void:
	for panel in _panels.values():
		(panel as Control).visible = false
	hide_room_clear()


## The victory card names which flame this was ("THE FOURTH FLAME") and, on the
## first win, tells the player the vows have woken in the Forge.
func set_victory_extras(ordinal: String, first: bool) -> void:
	var panel: Control = _panels["victory"]
	(panel.get_meta("kicker_label") as Label).text = "WARDEN DEFEATED  ·  " + ordinal if ordinal != "" else "WARDEN DEFEATED"
	(panel.get_meta("vows_label") as Label).visible = first


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


## Polled every frame, paused or not, ahead of the title-only work in _process.
func _poll_input_lock() -> void:
	if _input_lock.is_empty():
		return
	for action in _input_lock.actions:
		if Input.is_action_pressed(action):
			return
	var panel: Control = _panels[_input_lock.panel]
	_lift_input_lock()
	_focus_first_control(panel)


## Hand the locked panel's buttons back, whether the keys lifted or a new lock
## (or none) replaces this one.
func _lift_input_lock() -> void:
	if _input_lock.is_empty():
		return
	for button: Button in _panels[_input_lock.panel].find_children("*", "Button", true, false):
		button.disabled = false
		button.focus_mode = Control.FOCUS_ALL
	_input_lock = {}


## Show a one-time lesson. Re-showing replaces the current one rather than
## stacking, so two triggers in the same second cannot queue up noise. The
## lesson's {action} tokens become the player's live keys.
func show_hint(text: String, hold: float = 4.5) -> void:
	if _hint_panel == null:
		return
	_hint_template = text
	_hint_label.text = fill_prompts(text)
	_hint_tween = _flash_card(_hint_panel, _hint_tween, 0.25, hold, 0.5)


func hide_hint() -> void:
	_kill_tween(_hint_tween)
	if _hint_panel != null:
		_hint_panel.visible = false


func hide_banners() -> void:
	_kill_tween(_boss_phase_tween)
	if _boss_phase_tag != null:
		_boss_phase_tag.visible = false
	hide_hint()
	for banner in [_room_intro, _boss_intro]:
		_hide_banner(banner)


func set_hp(hp: float, max_hp: float) -> void:
	_set_trailed(_hp_bar, _hp_trail, hp, max_hp)
	_hp_value_label.text = "%d / %d" % [roundi(hp), roundi(max_hp)]


func set_special(value: float, maximum: float) -> void:
	_special_bar.max_value = maxf(1.0, maximum)
	_special_bar.value = clampf(value, 0.0, maximum)
	var was_ready := _special_shown.x >= _special_shown.y and _special_shown.y > 0.0
	_special_shown = Vector2(value, maximum)
	var ready := value >= maximum
	if ready != was_ready:
		_set_ignite_ready(ready)
	_paint_special_label()


## A full Graveflame names the Ignite key in gold; otherwise the count.
func _paint_special_label() -> void:
	var ready := _special_shown.x >= _special_shown.y and _special_shown.y > 0.0
	_special_value_label.text = "IGNITE  %s" % prompt("ignite") if ready else "%d / %d" % [roundi(_special_shown.x), roundi(_special_shown.y)]
	_special_value_label.add_theme_color_override("font_color", C_GOLD if ready else C_BLUE)


## While Ignite is ready the fill breathes between blue and white-hot, so a
## full bar reads as a prompt; reduced motion holds it white-hot instead.
func _set_ignite_ready(ready: bool) -> void:
	_kill_tween(_ignite_tween)
	var hot := C_BLUE.lerp(Color.WHITE, 0.75)
	_special_fill.bg_color = hot if ready else C_BLUE
	if not ready or Feedback.motion_reduced:
		return
	_ignite_tween = _ui_tween().set_loops()
	_ignite_tween.tween_property(_special_fill, "bg_color", C_BLUE, 0.42).set_trans(Tween.TRANS_SINE)
	_ignite_tween.tween_property(_special_fill, "bg_color", hot, 0.42).set_trans(Tween.TRANS_SINE)


## Notch fractions for every Lance's worth of Graveflame below a full bar.
static func _lance_marks(maximum: float) -> Array:
	var marks: Array = []
	var cost := Content.P_SPECIAL_COST
	while cost < maximum - 0.5:
		marks.append(cost / maximum)
		cost += Content.P_SPECIAL_COST
	return marks


## Lay ink notches over `bar` at each fraction in `marks`.
func _notch_bar(bar: Control, marks: Array) -> void:
	var notches := BarNotches.new()
	notches.marks = marks
	notches.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(notches)
	notches.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Thin cuts across a bar: thresholds the player spends or fights toward.
class BarNotches extends Control:
	var marks: Array = []
	func _draw() -> void:
		for mark in marks:
			var x := roundf(size.x * float(mark))
			draw_rect(Rect2(x - 1.0, -1.0, 2.0, size.y + 2.0), Color("100d18"))


## Seven chambers lead down to the throne, which is named rather than counted.
func set_room(idx: int, total: int) -> void:
	var chamber := "CHAMBER %s / %s" % [_roman(idx + 1), _roman(total - 1)]
	_room_label.text = "THE EMBER THRONE" if idx >= total - 1 else chamber


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
	_boss_bar.max_value = maxf(1.0, max_hp)
	_boss_bar.value = max_hp
	_boss_trail.max_value = _boss_bar.max_value
	_boss_trail.value = max_hp
	_boss_value_label.text = str(roundi(max_hp))
	_set_boss_ignited(false)


func update_boss_bar(hp: float) -> void:
	if not is_equal_approx(hp, _boss_bar.value):
		_set_trailed(_boss_bar, _boss_trail, hp, _boss_bar.max_value)
	_boss_value_label.text = str(maxi(0, roundi(hp)))
	if not _boss_ignited and hp <= _boss_bar.max_value * Content.BOSS_PHASE2_AT:
		_set_boss_ignited(true)


## Past the phase notch the Warden burns: its bar and name take the ember.
func _set_boss_ignited(on: bool) -> void:
	_boss_ignited = on
	_boss_bar.add_theme_stylebox_override("fill", _bar_box(C_EMBER if on else Color("b94350")))
	_boss_name_label.text = "THE EMBER WARDEN  ·  IGNITED" if on else "THE EMBER WARDEN"
	_boss_name_label.add_theme_color_override("font_color", C_EMBER_HI if on else Color("f2c3c6"))


func hide_boss_bar() -> void:
	_boss_panel.visible = false


## Phase-2 callout: a small tag under the boss bar that fades on its own.
func flash_boss_phase(text: String, hold: float = 1.7) -> void:
	_boss_phase_tag.text = text
	_boss_phase_tween = _flash_card(_boss_phase_tag, _boss_phase_tween, 0.18, hold, 0.5)


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


## A boon's sigil set in a paper medallion: an inked disc, a rarity ring, and
## for epics a slow ember breath around the ring.
class BoonMedallion extends Control:
	var boon_id := ""
	var tint := Color.WHITE
	var epic := false
	var _t := 0.0
	func setup(p_id: String, p_tint: Color, p_epic: bool, box := Vector2(0.0, 112.0)) -> void:
		boon_id = p_id
		tint = p_tint
		epic = p_epic
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = box
		set_process(epic)
		if not resized.is_connected(queue_redraw):
			resized.connect(queue_redraw)
	func _process(delta: float) -> void:
		if not Feedback.motion_reduced:
			_t += delta
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		draw_circle(c + Vector2(3.0, 4.0), r, Color(0.0, 0.0, 0.0, 0.5))
		draw_circle(c, r, Color("120e19"))
		draw_arc(c, r, 0.0, TAU, 48, Color(tint, 0.85), 2.0, true)
		draw_arc(c, r - 6.0, 0.0, TAU, 48, Color(tint, 0.25), 1.0, true)
		if epic:
			var breath := 0.5 + 0.5 * sin(_t * 2.2)
			draw_arc(c, r + 5.0, 0.0, TAU, 48, Color(tint, 0.15 + 0.25 * breath), 3.0, true)
		BoonArt.draw(self, boon_id, c, r * 0.62, tint)


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
	button.add_theme_stylebox_override("normal", _card_box(paper, rc.darkened(0.3), edge_w))
	button.add_theme_stylebox_override("hover", _card_box(paper.lightened(0.05), rc, edge_w + 1))
	button.add_theme_stylebox_override("focus", _card_box(paper.lightened(0.05), rc.lightened(0.25), edge_w + 1))
	button.add_theme_stylebox_override("pressed", _card_box(paper.lightened(0.1), C_GOLD, edge_w + 1))

	var margin := _margin_container(22, 22, 16, 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)

	# The index is a live keyboard shortcut, so printing it is not decoration.
	var key := _make_label("%d" % (index + 1), 12, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	stack.add_child(key)

	var sigil := BoonMedallion.new()
	sigil.setup(str(upgrade.get("id", "")), rc, epic)
	stack.add_child(sigil)

	var title := _make_label(str(upgrade.get("title", "Unknown Boon")), 25, C_TEXT)
	title.add_theme_font_override("font", _heading_font())
	stack.add_child(title)
	var desc := _make_label(str(upgrade.get("desc", "")), 14, C_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc.custom_minimum_size = Vector2(width - 52.0, 0)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(desc)
	# Rarity sits at the foot of the card, where a printed card keeps its set mark.
	var foot := rarity.to_upper()
	if bool(upgrade.get("unique", false)):
		foot += "  ·  ONCE PER DESCENT"
	stack.add_child(_make_label(foot, 11, rc))
	# Lift toward the hand under focus; hovering a card focuses it.
	button.focus_entered.connect(_lift_card.bind(button, true))
	button.focus_exited.connect(_lift_card.bind(button, false))
	return button


func _lift_card(button: Button, up: bool) -> void:
	if not is_instance_valid(button) or Feedback.motion_reduced:
		return
	button.pivot_offset = button.size * Vector2(0.5, 1.0)
	var t := _ui_tween()
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
		var t := _ui_tween()
		t.tween_interval(0.06 + float(i) * 0.08)
		t.set_parallel(true)
		t.tween_property(b, "modulate:a", 1.0, 0.18)
		t.tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func setup_upgrades(upgrades: Array) -> void:
	if _upgrade_row == null:
		return
	_clear_children(_upgrade_row)
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
		button.pressed.connect(upgrade_selected.emit.bind(i))
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
	var text := "%s  to take the chosen boon" % prompt("ui_accept")
	if last_device == "key":
		var count: int = (panel.get_meta("buttons", []) as Array).size()
		var keys: Array = range(1, count + 1).map(func(n: int): return str(n))
		text = "%s  or  click to take a boon" % " · ".join(keys)
	(panel.get_meta("footer_label") as Label).text = text


func set_flask(charges: int, max_charges: int) -> void:
	var safe_max := maxi(0, max_charges)
	var safe_charges := clampi(charges, 0, safe_max)
	if _flask_sigils.size() != safe_max:
		_rebuild_flask_sigils(safe_max)
	for i in range(_flask_sigils.size()):
		_fill_flask_sigil(_flask_sigils[i], i < safe_charges, i >= _flask_shown.x and i < safe_charges)
	_flask_shown = Vector2i(safe_charges, safe_max)
	_paint_flask_label()


func _paint_flask_label() -> void:
	_flask_count_label.text = "%d / %d  %s" % [_flask_shown.x, _flask_shown.y, prompt("heal")]


func set_cells(value: int) -> void:
	_cells_label.text = _format_number(value)


func set_best(value: int) -> void:
	_best_label.text = _format_number(value)


func setup_forge(cells: int) -> void:
	var panel: Control = _panels["forge"]
	var balance := panel.get_meta("balance_label") as Label
	balance.text = "AVAILABLE CELLS   %s" % _format_number(cells)
	var kept := _focused_name_in(_forge_rows)
	_clear_children(_forge_rows)

	for i in range(Content.META_UPGRADES.size()):
		var upgrade: Dictionary = Content.META_UPGRADES[i]
		var id := str(upgrade.get("id", ""))
		var rank := Save.get_meta_rank(id)
		var max_rank := Content.meta_max_rank(upgrade)
		var next_cost := Content.meta_next_cost(upgrade, rank)
		var mastered := next_cost < 0
		var edge := Color("715026") if rank > 0 else Color("3b3147")
		var line := _forge_row(68.0, edge, 8)

		var sigil := BoonSigil.new()
		# Forge rows are shorter than cards, so the sigil takes a fixed square.
		sigil.setup(id, C_GOLD if rank > 0 else C_EMBER_HI, Vector2(46.0, 46.0))
		line.add_child(sigil)

		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 1)
		line.add_child(copy)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		copy.add_child(head)
		var name_label := _make_label(str(upgrade.get("title", "Upgrade")).to_upper(), 14, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		head.add_child(name_label)
		head.add_child(_rank_pips(rank, max_rank))
		copy.add_child(_make_label(str(upgrade.get("desc", "")), 12, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))

		var buy := _button("MASTERED" if mastered else "%d CELLS" % next_cost, "Buy%d" % i, false, Vector2(132, 44), "")
		buy.disabled = mastered or cells < next_cost
		if mastered:
			buy.add_theme_color_override("font_disabled_color", C_MINT)
		else:
			buy.pressed.connect(buy_meta_requested.emit.bind(i))
		line.add_child(buy)

	_build_vow_rows()
	# A purchase or vow rebuilds every row: the cursor stays on the row it was
	# on, so a second press can never buy a relic the player did not choose.
	_focus_row.call_deferred(_forge_rows, kept, panel.get_meta("back_button") as Button)


## Name of the focused control when it sits inside `container`, so a list
## rebuilt under the cursor can hand focus back to the same row.
func _focused_name_in(container: Node) -> String:
	var owner := get_viewport().gui_get_focus_owner()
	return str(owner.name) if owner != null and container.is_ancestor_of(owner) else ""


## Focus the button named `kept` in `rows`, or the next usable one after it
## (the first usable one when nothing was kept), else `fallback`. Callers
## defer it, so a list rebuilt twice in one frame (a rebind that displaces
## another key) is searched only once it has settled.
func _focus_row(rows: Node, kept: String, fallback: Button) -> void:
	var buttons := rows.find_children("*", "Button", true, false)
	var from := 0
	for i in range(buttons.size()):
		if buttons[i].name == kept:
			from = i
	for i in range(from, buttons.size()):
		if not (buttons[i] as Button).disabled:
			(buttons[i] as Button).grab_focus()
			return
	if fallback != null:
		fallback.grab_focus()


## One ledger row in the forge; its edge colour marks what is owned or sworn.
## Returns the row's content line.
func _forge_row(height: float, edge: Color, pad_y: int) -> HBoxContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = height
	row.add_theme_stylebox_override("panel", _panel_box(C_INK, edge, 8, 1, 0))
	_forge_rows.add_child(row)
	var margin := _margin_container(16, 12, pad_y, pad_y)
	row.add_child(margin)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	margin.add_child(line)
	return line


## Vows sit under the relics: burdens rather than purchases, sworn or unsworn
## for free once the Warden has fallen, each paying out in score and cells.
func _build_vow_rows() -> void:
	var head := _make_label("VOWS", 13, C_RED, HORIZONTAL_ALIGNMENT_LEFT)
	head.custom_minimum_size.y = 34.0
	_forge_rows.add_child(head)
	if not Save.vows_unlocked():
		_forge_rows.add_child(_make_label("Defeat the Ember Warden to swear vows.", 12, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
		return
	var record := Save.load_save()
	var kept: Array = record.get("vows_kept_ever", [])
	_forge_rows.add_child(_make_label(_roll_line(record), 12, C_GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	var sworn := Save.get_vows()
	_forge_rows.add_child(_make_label("Sworn vows make the next descent harsher.  Score ×%s" % String.num(Content.vow_score_multiplier(sworn), 2), 12, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	for i in range(Content.VOWS.size()):
		var v: Dictionary = Content.VOWS[i]
		var on := sworn.has(str(v.id))
		var edge := Color("8e3c49") if on else Color("3b3147")
		var line := _forge_row(58.0, edge, 6)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 1)
		line.add_child(copy)
		copy.add_child(_make_label(str(v.title).to_upper(), 14, C_RED if on else C_TEXT, HORIZONTAL_ALIGNMENT_LEFT))
		copy.add_child(_make_label("%s   +%d%% score" % [str(v.desc), roundi(float(v.score) * 100.0)], 12, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
		if kept.has(str(v.id)):
			line.add_child(_kept_seal())
		var toggle := _button("SWORN" if on else "SWEAR", "Vow%d" % i, on, Vector2(132, 40), "")
		toggle.pressed.connect(vow_toggled.emit.bind(str(v.id)))
		line.add_child(toggle)


## The Forge's tally of every descent: flames won, knights fallen (a "+" when
## deaths from before the count began are unknown) and the hardest oath kept.
static func _roll_line(record: Dictionary) -> String:
	var flames := int(record.get("victories", 0))
	var fallen := "%d%s" % [int(record.get("falls", 0)), "+" if bool(record.get("falls_legacy", false)) else ""]
	var oath := "HIGHEST OATH %d OF %d" % [int(record.get("best_vows", 0)), Content.VOWS.size()]
	if bool(record.get("oath_kept", false)):
		oath = "THE FIVEFOLD OATH IS KEPT"
	return "THE ROLL  ·  %d %s  ·  %s FALLEN  ·  %s" % [flames, "FLAME" if flames == 1 else "FLAMES", fallen, oath]


## The seal and its word, so a kept vow never reads by colour alone.
func _kept_seal() -> Control:
	var mark := HBoxContainer.new()
	mark.add_theme_constant_override("separation", 6)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var seal := KeptSeal.new()
	seal.custom_minimum_size = Vector2(22.0, 22.0)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(seal)
	mark.add_child(_make_label("KEPT", 11, Color("c46f7b"), HORIZONTAL_ALIGNMENT_LEFT))
	return mark


## Wax pressed beside a vow that has been kept through a won descent: a
## scalloped disc with an embossed flame.
class KeptSeal extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var rim := PackedVector2Array()
		for i in range(20):
			var a := TAU * float(i) / 20.0
			rim.append(c + Vector2(cos(a), sin(a)) * (11.0 if i % 2 == 0 else 9.6))
		draw_colored_polygon(rim, Color("8e3c49"))
		draw_circle(c, 7.0, Color("a14b58"))
		VFX.draw_flame(self, c + Vector2(0.0, 5.0), 10.0, 7.0, 0.0, 0.0, Color("5c1d27"), Color("c46f7b"))


## Rank as a row of small lozenges: filled for owned, hollow for the rest.
func _rank_pips(rank: int, max_rank: int) -> Control:
	var pips := RankPips.new()
	pips.rank = rank
	pips.max_rank = max_rank
	pips.custom_minimum_size = Vector2(14.0 * float(max_rank), 14.0)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pips


class RankPips extends Control:
	var rank := 0
	var max_rank := 1
	func _draw() -> void:
		for i in range(max_rank):
			var c := Vector2(7.0 + float(i) * 14.0, size.y * 0.5)
			var pts := PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)])
			if i < rank:
				draw_colored_polygon(pts, Color("ffd166"))
			else:
				pts.append(pts[0])
				draw_polyline(pts, Color("6f6578"), 1.2, true)


func show_run_cells(cells_earned: int, panel_name: String, vows_kept: int = 0) -> void:
	var label := (_panels[panel_name] as Control).get_meta("cells_label") as Label
	label.text = "CELLS SECURED  +%s" % _format_number(cells_earned)
	if vows_kept > 0:
		var noun := "VOW" if vows_kept == 1 else "VOWS"
		label.text += "   ·   %d %s KEPT" % [vows_kept, noun]
	label.visible = true


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
	var col: Color = STREAK_TIER_COLORS[clampi(tier, 0, STREAK_TIER_COLORS.size() - 1)]
	_streak_mult_label.add_theme_color_override("font_color", col)
	_streak_bar.add_theme_stylebox_override("fill", _bar_box(col))
	if tier > _streak_tier and not Feedback.motion_reduced:
		_kill_tween(_streak_tween)
		_streak_panel.scale = Vector2(1.12, 1.12)
		_streak_tween = _ui_tween()
		_streak_tween.tween_property(_streak_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tier = tier


## The streak timer drains every frame; everything else changes only on a kill.
func set_streak_fraction(frac: float) -> void:
	_streak_bar.value = clampf(frac, 0.0, 1.0) * 100.0


func hide_streak() -> void:
	if _streak_panel != null:
		_streak_panel.visible = false
		_streak_panel.scale = Vector2.ONE
	_streak_tier = 0


func show_room_intro(idx: int, total: int, room_name: String, trial: bool = false) -> void:
	var sub := "CHAMBER %s OF %s" % [_roman(idx + 1), _roman(total - 1)]
	if trial:
		sub += "  ·  TRIAL"
	_play_banner(_room_intro, room_name.to_upper(), sub, 1.5)


var _hud_tween: Tween

## Ease the whole HUD out for a cinematic beat, or snap it back for play.
func set_hud_faded(faded: bool) -> void:
	if _hud == null:
		return
	_kill_tween(_hud_tween)
	if not faded:
		_hud.modulate = Color.WHITE
		return
	_hud_tween = _ui_tween()
	_hud_tween.tween_property(_hud, "modulate:a", 0.0, 0.5)


func show_boss_intro(boss_name: String, subtitle: String, hold: float = 2.4) -> void:
	# The boss card owns the screen: drop any chamber card still fading out,
	# and any lesson in the low strip it now covers.
	_hide_banner(_room_intro)
	hide_hint()
	_play_banner(_boss_intro, boss_name.to_upper(), subtitle.to_upper(), hold)


var _veil_tween: Tween

## Arrival in a new chamber: the black page burns away from where the knight
## stands, its edge glowing like paper catching. Reduced motion keeps a plain
## fade, since a travelling edge is exactly the motion that setting removes.
func fade_from_black(duration: float = 0.45, origin: Vector2 = Vector2(0.5, 0.55)) -> void:
	if _fade == null:
		return
	_kill_tween(_veil_tween)
	_veil_tween = _ui_tween()
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


## How far the burn's edge must travel from `origin` (in UV) to clear the
## farthest corner of the frame, plus the ragged edge's full depth.
static func burn_reach(origin: Vector2, aspect: float) -> float:
	var from := origin * Vector2(aspect, 1.0)
	var farthest := 0.0
	for corner in [Vector2.ZERO, Vector2(aspect, 0.0), Vector2(0.0, 1.0), Vector2(aspect, 1.0)]:
		farthest = maxf(farthest, from.distance_to(corner))
	return farthest + 0.24


func show_run_summary(stats: Dictionary, panel_name: String) -> void:
	var panel: Control = _panels[panel_name]
	if stats.has("line"):
		(panel.get_meta("line_label") as Label).text = str(stats.line)
	# The headline result is set before the grid so it never depends on it.
	var score_label := panel.get_meta("score_label") as Label
	score_label.text = _format_number(int(stats.get("score", 0)))
	# Set both text and colour every time: the panel is reused between runs,
	# so a previous record's gold must not persist onto a lesser run.
	var best_label := panel.get_meta("best_label") as Label
	var record := bool(stats.get("new_best", false))
	best_label.text = "NEW BEST" if record else "BEST  %s" % _format_number(int(stats.get("best", 0)))
	var best_color := C_GOLD if record else C_MUTED
	best_label.add_theme_color_override("font_color", best_color)
	var labels: Dictionary = panel.get_meta("summary_labels")
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
		(labels[key] as Label).text = str(values[key])


## The clear card lands, holds, then steps aside into a small chip in the top
## slot, so it no longer hangs over the walk to the rifts.
func show_room_clear(room_name: String) -> void:
	hide_room_clear()
	_hide_banner(_room_intro)
	_room_clear_name.text = room_name.to_upper() if not room_name.strip_edges().is_empty() else "PATH UNSEALED"
	_room_clear_banner.visible = true
	_room_clear_banner.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_room_clear_banner.pivot_offset = Vector2(_room_clear_banner.size.x * 0.5, 0.0)
	var settle := 0.0 if Feedback.motion_reduced else 0.35
	_room_clear_tween = _ui_tween()
	_room_clear_tween.tween_property(_room_clear_banner, "modulate", Color.WHITE, 0.16)
	_room_clear_tween.tween_interval(1.4)
	_room_clear_tween.tween_callback(_room_clear_to_chip)
	_room_clear_tween.tween_property(_room_clear_banner, "scale", Vector2.ONE * 0.7, settle).set_trans(Tween.TRANS_SINE)
	_room_clear_tween.parallel().tween_property(_room_clear_banner, "position:y", 12.0, settle).set_trans(Tween.TRANS_SINE)


## The chip says what to do next, set larger so it stays legible once shrunk.
func _room_clear_to_chip() -> void:
	_room_clear_name.text = "PATH UNSEALED  ·  CHOOSE A RIFT"
	_room_clear_name.add_theme_font_size_override("font_size", 16)


func hide_room_clear() -> void:
	if _room_clear_banner != null:
		_kill_tween(_room_clear_tween)
		_room_clear_banner.visible = false
		_room_clear_banner.modulate = Color.WHITE
		_room_clear_banner.scale = Vector2.ONE
		_room_clear_banner.position.y = ROOM_CLEAR_TOP
		_room_clear_name.add_theme_font_size_override("font_size", 12)


# --- Internal updates --------------------------------------------------------

## One flask sigil per charge on the belt, drawn like the Forge's flask relic.
func _rebuild_flask_sigils(count: int) -> void:
	_clear_children(_flask_container)
	_flask_sigils.clear()
	for i in range(count):
		var sigil := BoonSigil.new()
		sigil.setup("flask", C_MINT, Vector2(16.0, 18.0))
		sigil.pivot_offset = Vector2(8.0, 9.0)
		_flask_container.add_child(sigil)
		_flask_sigils.append(sigil)


## A charged flask glows mint; a spent one is a dim ghost of the glass. A
## charge that has just come back pops, so a refill is noticed mid-fight.
func _fill_flask_sigil(sigil: Control, filled: bool, refilled: bool) -> void:
	sigil.modulate = Color.WHITE if filled else Color(0.32, 0.4, 0.38, 0.55)
	if not refilled or Feedback.motion_reduced:
		return
	sigil.scale = Vector2.ONE * 1.3
	_ui_tween().tween_property(sigil, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Boon card frame: no content margins, because the card's own MarginContainer
## owns the padding and the Button only provides the border and tint.
func _card_box(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := _panel_box(background, border, 12, border_width, 6)
	# The rarity colour runs heavier along the top, like a card's printed band.
	box.border_width_top = border_width + 4
	box.content_margin_left = 0.0
	box.content_margin_right = 0.0
	box.content_margin_top = 0.0
	box.content_margin_bottom = 0.0
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


func _format_number(value: int) -> String:
	var raw := str(maxi(0, value))
	var formatted := ""
	while raw.length() > 3:
		formatted = "," + raw.right(3) + formatted
		raw = raw.left(raw.length() - 3)
	return raw + formatted
