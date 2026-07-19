class_name UI
extends CanvasLayer
## HUD plus title/pause/reward/game-over/victory panels, built programmatically.

signal start_requested
signal resume_requested
signal restart_requested
signal quit_to_title_requested
signal upgrade_selected(idx: int)
signal option_toggled(key: String, value: bool)
signal forge_requested
signal buy_meta_requested(idx: int)
signal back_from_forge_requested

var _hud: Control
var _hp_bar: ProgressBar
var _special_bar: ProgressBar
var _room_label: Label
var _score_label: Label
var _boss_bar: ProgressBar
var _boss_label: Label
var _flask_container: HBoxContainer
var _flask_dots: Array = []
var _cells_label: Label
var _best_label: Label
var _panels: Dictionary = {}
var _root: Control
var _font: Font
var _reduced_motion_check: CheckBox
var _reduced_flash_check: CheckBox

func _ready() -> void:
	layer = 50
	_font = null
	_build_hud()
	_build_title()
	_build_pause()
	_build_reward()
	_build_game_over()
	_build_victory()
	_build_forge()
	hide_all_panels()
	show_panel("title")

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	# HP bar
	_hp_bar = ProgressBar.new()
	_hp_bar.position = Vector2(24, 20)
	_hp_bar.size = Vector2(280, 22)
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	_hp_bar.show_percentage = false
	_style_bar(_hp_bar, Color("c43838"), Color("3a1414"))
	_hud.add_child(_hp_bar)
	_label(Vector2(24, 2), "HP", _hud)
	# Special bar
	_special_bar = ProgressBar.new()
	_special_bar.position = Vector2(24, 52)
	_special_bar.size = Vector2(280, 14)
	_special_bar.min_value = 0.0
	_special_bar.max_value = 100.0
	_special_bar.value = 0.0
	_special_bar.show_percentage = false
	_style_bar(_special_bar, Color("7fd4ff"), Color("143044"))
	_hud.add_child(_special_bar)
	_label(Vector2(312, 52), "SP", _hud, 12)
	# Flask charges — row of dots below special bar
	_flask_container = HBoxContainer.new()
	_flask_container.position = Vector2(24, 72)
	_flask_container.add_theme_constant_override("separation", 6)
	_hud.add_child(_flask_container)
	for i in range(Content.FLASK_MAX):
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(14, 14)
		d.color = Color("5fe8a8")
		_flask_container.add_child(d)
		_flask_dots.append(d)
	_label(Vector2(24 + Content.FLASK_MAX * 20 + 8, 74), "FLASK (F)", _hud, 11)
	# Room + score
	_room_label = _label(Vector2(24, 92), "ROOM 1/5", _hud, 16)
	_score_label = _label(Vector2(24, 112), "SCORE 0", _hud, 16)
	# Cells + best score (top-right)
	_cells_label = _label(Vector2(0, 20), "CELLS 0", _hud, 18)
	_cells_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT
	_cells_label.position = Vector2(-140, 20)
	_cells_label.size = Vector2(120, 24)
	_best_label = _label(Vector2(0, 44), "BEST 0", _hud, 14)
	_best_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT
	_best_label.position = Vector2(-140, 44)
	_best_label.size = Vector2(120, 20)
	_best_label.add_theme_color_override("font_color", Content.PAL.text_dim)
	# Boss bar (hidden by default)
	_boss_bar = ProgressBar.new()
	_boss_bar.position = Vector2(440, 28)
	_boss_bar.size = Vector2(400, 18)
	_boss_bar.min_value = 0.0
	_boss_bar.max_value = 100.0
	_boss_bar.value = 100.0
	_boss_bar.show_percentage = false
	_boss_bar.visible = false
	_style_bar(_boss_bar, Color("8a2f3d"), Color("2a0e12"))
	_hud.add_child(_boss_bar)
	_boss_label = _label(Vector2(440, 8), "THE EMBER WARDEN", _hud, 18)
	_boss_label.visible = false

func _style_bar(bar: ProgressBar, fg: Color, bg: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("background", sb)
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = fg
	sbf.corner_radius_top_left = 4
	sbf.corner_radius_top_right = 4
	sbf.corner_radius_bottom_left = 4
	sbf.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("fill", sbf)

func _label(pos: Vector2, text: String, parent: Node, size: int = 14) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Content.PAL.text)
	parent.add_child(l)
	return l

func _build_title() -> void:
	var p := _panel("title", true)
	_title(p, "GRAVEFLAME", 84, Vector2(0, -180))
	_subtitle(p, "an action-roguelite", 20, Vector2(0, -110))
	_hint(p, "Move: A/D or Arrows    Jump: W/Space    Attack: J", -30)
	_hint(p, "Special: K    Dash: Shift/L    Parry: S    Flask: F", -6)
	_hint(p, "Down-slam: attack while airborne. Wall-jump off walls.", 18)
	_hint(p, "Heal with the flask between rooms. Choose a boon each clear.", 36)
	_button(p, "BEGIN", "start", Vector2(0, 96), true).pressed.connect(func(): emit_signal("start_requested"))
	_button(p, "FORGE", "forge", Vector2(0, 164), false).pressed.connect(func(): emit_signal("forge_requested"))

func _build_pause() -> void:
	var p := _panel("pause", true)
	_title(p, "PAUSED", 64, Vector2(0, -120))
	_button(p, "RESUME", "resume", Vector2(0, -10), true).pressed.connect(func(): emit_signal("resume_requested"))
	_button(p, "QUIT TO TITLE", "quit", Vector2(0, 60), false).pressed.connect(func(): emit_signal("quit_to_title_requested"))
	# options
	_reduced_motion_check = _check(p, "Reduced motion", Vector2(0, 130))
	_reduced_flash_check = _check(p, "Reduced flash", Vector2(0, 160))
	_reduced_motion_check.toggled.connect(func(v): emit_signal("option_toggled", "reduced_motion", v))
	_reduced_flash_check.toggled.connect(func(v): emit_signal("option_toggled", "reduced_flash", v))

func _build_reward() -> void:
	var p := _panel("reward", true)
	_title(p, "CHOOSE", 56, Vector2(0, -200))
	_subtitle(p, "You cleared the room. Pick a boon.", 18, Vector2(0, -150))
	# three upgrade buttons created dynamically via setup_upgrades
	p.set_meta("buttons", [])

func _build_victory() -> void:
	var p := _panel("victory", true)
	_title(p, "VICTORY", 72, Vector2(0, -120))
	_subtitle(p, "The Warden falls. Graveflame endures.", 20, Vector2(0, -60))
	p.set_meta("cells_label", null)
	_button(p, "RUN AGAIN", "again", Vector2(0, 30), true).pressed.connect(func(): emit_signal("restart_requested"))
	_button(p, "TITLE", "title2", Vector2(0, 100), false).pressed.connect(func(): emit_signal("quit_to_title_requested"))

func _build_forge() -> void:
	var p := _panel("forge", true)
	_title(p, "THE FORGE", 56, Vector2(0, -260))
	_subtitle(p, "Spend cells on permanent upgrades.", 18, Vector2(0, -210))
	# Cells balance label (updated dynamically)
	var bal := _label(Vector2(0, -170), "CELLS: 0", p, 22)
	bal.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	bal.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.set_meta("balance_label", bal)
	# container for upgrade rows (rebuilt on show)
	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.position = Vector2(-220, -120)
	rows.size = Vector2(440, 340)
	rows.add_theme_constant_override("separation", 10)
	p.add_child(rows)
	p.set_meta("rows", rows)
	# back button
	_button(p, "BACK", "back", Vector2(0, 250), false).pressed.connect(func(): emit_signal("back_from_forge_requested"))

func _build_game_over() -> void:
	var p := _panel("gameover", true)
	_title(p, "YOU FELL", 72, Vector2(0, -160))
	p.set_meta("cells_label", null)
	_button(p, "TRY AGAIN", "restart", Vector2(0, 40), true).pressed.connect(func(): emit_signal("restart_requested"))
	_button(p, "TITLE", "title", Vector2(0, 110), false).pressed.connect(func(): emit_signal("quit_to_title_requested"))

func _panel(name: String, dim: bool) -> Control:
	var p := Control.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	if dim:
		var bg := ColorRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.color = Color(0, 0, 0, 0.6)
		p.add_child(bg)
	add_child(p)
	_panels[name] = p
	return p

func _title(parent: Control, text: String, size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Content.PAL.player_accent)
	l.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.position = pos
	parent.add_child(l)
	return l

func _subtitle(parent: Control, text: String, size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Content.PAL.text_dim)
	l.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.position = pos
	parent.add_child(l)
	return l

func _hint(parent: Control, text: String, y: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Content.PAL.text)
	l.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.position = Vector2(0, y)
	parent.add_child(l)
	return l

func _button(parent: Control, text: String, name: String, pos: Vector2, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.name = name
	b.custom_minimum_size = Vector2(240, 56)
	b.position = pos - b.custom_minimum_size * 0.5
	b.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Content.PAL.player_accent if primary else Color("2b2436")
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb.duplicate())
	b.add_theme_stylebox_override("pressed", sb.duplicate())
	b.add_theme_stylebox_override("focus", sb.duplicate())
	parent.add_child(b)
	return b

func _check(parent: Control, text: String, pos: Vector2) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.add_theme_font_size_override("font_size", 16)
	c.add_theme_color_override("font_color", Content.PAL.text)
	c.position = pos - Vector2(120, 0)
	c.size = Vector2(240, 30)
	parent.add_child(c)
	return c

# --- Public API ---
func show_panel(name: String) -> void:
	if _panels.has(name):
		_panels[name].visible = true
		for child in _panels[name].get_children():
			if child is Button:
				child.grab_focus.call_deferred()
				break

func hide_panel(name: String) -> void:
	if _panels.has(name):
		_panels[name].visible = false

func hide_all_panels() -> void:
	for p in _panels.values():
		p.visible = false

func set_hp(hp: float, max_hp: float) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp

func set_special(v: float, maxv: float) -> void:
	_special_bar.max_value = maxv
	_special_bar.value = v

func set_room(idx: int, total: int) -> void:
	_room_label.text = "ROOM %d/%d" % [idx + 1, total]

func set_score(s: int) -> void:
	_score_label.text = "SCORE %d" % s

func show_boss_bar(max_hp: float) -> void:
	_boss_bar.visible = true
	_boss_label.visible = true
	_boss_bar.max_value = max_hp
	_boss_bar.value = max_hp

func update_boss_bar(hp: float) -> void:
	_boss_bar.value = hp

func hide_boss_bar() -> void:
	_boss_bar.visible = false
	_boss_label.visible = false

func setup_upgrades(upgrades: Array) -> void:
	var p: Control = _panels["reward"]
	# remove old buttons
	var btns: Array = p.get_meta("buttons", [])
	for b in btns:
		if is_instance_valid(b): b.queue_free()
	btns.clear()
	var n := upgrades.size()
	for i in range(n):
		var u: Dictionary = upgrades[i]
		var b := Button.new()
		b.text = "%s\n%s" % [u.title, u.desc]
		b.custom_minimum_size = Vector2(300, 110)
		b.position = Vector2(float(i) - (float(n) - 1.0) * 0.5, 0) * 320.0 - Vector2(150, 55)
		b.add_theme_font_size_override("font_size", 18)
		b.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("2b2436")
		sb.border_color = Content.PAL.player_accent
		sb.border_width_bottom = 4
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb.duplicate())
		b.add_theme_stylebox_override("pressed", sb.duplicate())
		b.add_theme_stylebox_override("focus", sb.duplicate())
		p.add_child(b)
		b.pressed.connect(func(): emit_signal("upgrade_selected", i))
		btns.append(b)
	p.set_meta("buttons", btns)
	if btns.size() > 0:
		(btns[0] as Button).grab_focus.call_deferred()

# --- Flask / cells / best score / forge ---

func set_flask(charges: int, max_charges: int) -> void:
	# Rebuild dots if max changed
	if _flask_dots.size() != max_charges:
		for d in _flask_dots:
			if is_instance_valid(d): d.queue_free()
		_flask_dots.clear()
		for i in range(max_charges):
			var d := ColorRect.new()
			d.custom_minimum_size = Vector2(14, 14)
			d.color = Color("5fe8a8")
			_flask_container.add_child(d)
			_flask_dots.append(d)
	for i in range(_flask_dots.size()):
		if is_instance_valid(_flask_dots[i]):
			if i < charges:
				_flask_dots[i].color = Color("5fe8a8")
			else:
				_flask_dots[i].color = Color("2a3a30")

func set_cells(n: int) -> void:
	_cells_label.text = "CELLS %d" % n

func set_best(n: int) -> void:
	_best_label.text = "BEST %d" % n

func setup_forge(cells: int) -> void:
	var p: Control = _panels["forge"]
	var bal: Label = p.get_meta("balance_label")
	if bal != null:
		bal.text = "CELLS: %d" % cells
	var rows: VBoxContainer = p.get_meta("rows")
	if rows == null: return
	# Clear old rows
	for c in rows.get_children():
		c.queue_free()
	var purchased: Array = Save.get_purchased_meta()
	for i in range(Content.META_UPGRADES.size()):
		var u: Dictionary = Content.META_UPGRADES[i]
		var owned := purchased.has(u.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.text = "%s\n%s" % [u.title, u.desc]
		label.custom_minimum_size = Vector2(300, 56)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Content.PAL.text)
		row.add_child(label)
		var btn := Button.new()
		if owned:
			btn.text = "OWNED"
			btn.disabled = true
		else:
			btn.text = "%d cells" % int(u.cost)
			btn.disabled = (cells < int(u.cost))
		btn.custom_minimum_size = Vector2(110, 40)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(func(): emit_signal("buy_meta_requested", i))
		row.add_child(btn)
		rows.add_child(row)

func show_run_cells(cells_earned: int, panel_name: String) -> void:
	var p: Control = _panels[panel_name]
	if p == null: return
	var old: Label = p.get_meta("cells_label")
	if old != null and is_instance_valid(old):
		old.queue_free()
	var cl := _label(Vector2(0, -40), "CELLS EARNED: +%d" % cells_earned, p, 22)
	cl.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	cl.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_theme_color_override("font_color", Color("ffd23f"))
	p.set_meta("cells_label", cl)

