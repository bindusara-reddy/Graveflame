class_name UiKit
extends RefCounted
## The components every Graveflame screen is cut from (see ui_design.md,
## "The kit"). Static builders return plain Godot controls (Button, CheckBox,
## HSlider, PanelContainer...) dressed in UiTheme paper, so focus, signals and
## the contract suites keep working. Every animated piece obeys reduced motion
## (UiTheme.still) and sounds through emit_cue, so it needs no UI reference.

const T := preload("res://scripts/ui_theme.gd")
const P := preload("res://scripts/ui_paint.gd")

## Button kinds: ember call to action, ink slip, bare text until focused, wax.
const PRIMARY := T.Kind.PRIMARY
const SECONDARY := T.Kind.SECONDARY
const QUIET := T.Kind.QUIET
const DANGER := T.Kind.DANGER


# --- Motion ----------------------------------------------------------------------

## A tween that keeps running while the tree is paused: the reward, pause and
## run-end screens animate over a paused game.
static func tween(node: Node) -> Tween:
	return node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)


## Stop a tween that may be null or already finished.
static func kill_tween(t: Tween) -> void:
	if t != null and is_instance_valid(t):
		t.kill()


## Fade `node` in, hold it, fade it out and hide it, replacing the `previous`
## run of the same card. Returns the new tween so the caller can cut it short.
static func flash_card(node: Control, previous: Tween, fade_in: float, hold: float, fade_out: float) -> Tween:
	kill_tween(previous)
	node.visible = true
	node.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var t := tween(node)
	t.tween_property(node, "modulate:a", 1.0, fade_in)
	t.tween_interval(hold)
	t.tween_property(node, "modulate:a", 0.0, fade_out)
	t.tween_callback(node.hide)
	return t


## Lay paper down: it slides in from `from` (px, relative) and settles with a
## little overshoot. Reduced motion keeps only a short fade.
static func slide_in(node: Control, from := Vector2(0.0, 16.0), duration := T.MED) -> Tween:
	node.visible = true
	node.modulate.a = 0.0
	var t := tween(node)
	if T.still():
		t.tween_property(node, "modulate:a", 1.0, 0.15)
		return t
	var rest := node.position
	node.position = rest + from
	t.set_parallel(true)
	t.tween_property(node, "modulate:a", 1.0, duration * 0.6)
	t.tween_property(node, "position", rest, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.set_parallel(false)
	return t


## Fold paper away toward its top edge, then hide it (or free it with
## `free_after`). Reduced motion keeps only a short fade.
static func fold_out(node: Control, duration := T.MED, free_after := false) -> Tween:
	var t := tween(node)
	if T.still():
		t.tween_property(node, "modulate:a", 0.0, 0.15)
	else:
		node.pivot_offset = Vector2(node.size.x * 0.5, 0.0)
		t.set_parallel(true)
		t.tween_property(node, "scale:y", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.tween_property(node, "modulate:a", 0.0, duration)
		t.set_parallel(false)
	t.tween_callback(node.queue_free if free_after else node.hide)
	return t


## Menu feedback travels up to the nearest node that declares a `cue` signal
## (the UI), so kit controls sound wherever they are built without holding a
## reference to it; a control outside any UI stays silent.
static func emit_cue(from: Node, kind: String) -> void:
	var node := from
	while node != null and not node.has_signal("cue"):
		node = node.get_parent()
	if node != null:
		node.emit_signal("cue", kind)


# --- Text --------------------------------------------------------------------------

## A label in a type role (UiTheme.TITLE, BODY, CAPS...). A bare pixel size
## still works for the screens not yet rebuilt: sans below 30 px, the heading
## serif from 30, outlined for reading over the world.
static func label(text: String, role: Variant = T.BODY, color: Color = T.BONE, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = alignment
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Compact HUD labels must keep their intrinsic width inside HBoxContainers;
	# callers that render paragraphs opt into wrapping explicitly.
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_color_override("font_color", color)
	if role is String:
		l.add_theme_font_override("font", T.font(role))
		l.add_theme_font_size_override("font_size", T.size(role))
		return l
	var px := int(role)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_outline_color", Color("000000b0"))
	l.add_theme_constant_override("outline_size", 2 if px >= 18 else 1)
	if px >= 30:
		l.add_theme_font_override("font", T.heading_font())
		l.add_theme_constant_override("outline_size", 3)
	return l


## Give text laid straight over the world an ink outline so it holds against
## bright torches; text on paper never needs one.
static func outlined(l: Label, px := 2) -> Label:
	l.add_theme_color_override("font_outline_color", Color(T.INK_DEEP, 0.85))
	l.add_theme_constant_override("outline_size", px)
	return l


## A caption on the left and its value on the right. Returns the value label.
static func stat_line(parent: VBoxContainer, title: String, value: String, value_color: Color, value_size := 12) -> Label:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	row.add_child(label(title, 10, T.ASH, HORIZONTAL_ALIGNMENT_LEFT))
	var result := label(value, value_size, value_color, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(result)
	return result


## A ledger line, `CHAMBERS ........ 7 / 8`: caption, dotted leader, value.
## The value label is the row's "value" meta.
static func stat(caption_text: String, value: String, value_color := T.BONE) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", T.S2)
	var name_label := label(caption_text, T.CAPS, T.ASH, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.add_child(name_label)
	var leader := Leader.new()
	leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(leader)
	var value_label := label(value, T.NUMERAL, value_color, HORIZONTAL_ALIGNMENT_RIGHT)
	value_label.add_theme_font_size_override("font_size", 20)
	value_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	line.add_child(value_label)
	line.set_meta("value", value_label)
	return line


## The dotted leader of a ledger line, sitting near the text's baseline.
class Leader extends Control:
	func _draw() -> void:
		var y := size.y * 0.5 + 5.0
		var x := 2.0
		while x < size.x - 2.0:
			draw_rect(Rect2(x, y, 1.5, 1.5), Color(T.SOOT, 0.9))
			x += 6.0


## Small numbers as Roman numerals, the keep's way of counting ranks and chambers.
static func roman(n: int) -> String:
	var out := ""
	for pair in [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]:
		while n >= int(pair[0]):
			out += str(pair[1])
			n -= int(pair[0])
	return out


static func format_number(value: int) -> String:
	var raw := str(maxi(0, value))
	var formatted := ""
	while raw.length() > 3:
		formatted = "," + raw.right(3) + formatted
		raw = raw.left(raw.length() - 3)
	return raw + formatted


# --- Paper and layout --------------------------------------------------------------

static func margin(left: int, right: int, top: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_bottom", bottom)
	return m


## A styled panel that lets clicks through: HUD cards must never swallow a
## click meant for the game.
static func passive_panel(parent: Control, style: StyleBox, minimum := Vector2.ZERO) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


## A piece of paper on `parent`: "sheet" (a screen's torn ledger page),
## "slip" (HUD groups, hints), "strip" (banners) or "well" (inset readouts).
## Clicks pass through it. Fill it with padded_stack.
static func sheet(parent: Control, kind := "sheet", accent := T.HAIRLINE, minimum := Vector2.ZERO) -> PanelContainer:
	var style: StyleBox
	match kind:
		"slip": style = T.slip_style(accent)
		"strip": style = T.strip_style(accent)
		"well": style = T.well_style()
		_: style = T.sheet_style(accent)
	return passive_panel(parent, style, minimum)


## A vertical stack inside `panel`, padded evenly on each axis and as
## click-transparent as the panel. Returns the stack to fill.
static func padded_stack(panel: Container, pad_x: int, pad_y: int, separation: int) -> VBoxContainer:
	var m := margin(pad_x, pad_x, pad_y, pad_y)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(m)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", separation)
	m.add_child(stack)
	return stack


## A flat sheet of colour laid over `preset` (a dimmer, the rift veil).
## Decorative ones let input through; a backdrop that must stop clicks
## reaching what lies beneath passes blocks_input.
static func backdrop(parent: Control, color: Color, preset: Control.LayoutPreset, blocks_input := false) -> ColorRect:
	var s := ColorRect.new()
	s.mouse_filter = Control.MOUSE_FILTER_STOP if blocks_input else Control.MOUSE_FILTER_IGNORE
	s.color = color
	parent.add_child(s)
	s.set_anchors_and_offsets_preset(preset)
	return s


## A centred paper sheet on `parent` holding a padded column; the sheet is
## stored as the parent's "dialog" meta. Returns the column to fill.
static func dialog(parent: Control, minimum: Vector2, accent: Color, margin_x: int, margin_y: int) -> VBoxContainer:
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
	card.add_theme_stylebox_override("panel", T.sheet_style(accent.darkened(0.2), parent.get_index() + 1))
	center.add_child(card)
	parent.set_meta("dialog", card)

	var m := margin(margin_x, margin_x, margin_y, margin_y)
	card.add_child(m)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.add_child(content)
	return content


## A centred row of dialog buttons, spaced like every other footer.
static func button_row(parent: Container) -> HBoxContainer:
	var row_box := HBoxContainer.new()
	row_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row_box.add_theme_constant_override("separation", T.S3)
	parent.add_child(row_box)
	return row_box


## A list that scrolls once it outgrows its dialog. Returns the rows container.
static func scroll_list(parent: Container, min_height: float, separation: int) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = min_height
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Pad and keyboard focus may walk below the fold; the list must follow it.
	scroll.follow_focus = true
	# A narrow ink channel with an ember grip, not the stock grey bar.
	var track := scroll.get_v_scroll_bar()
	track.add_theme_stylebox_override("scroll", T.flat_box(T.INK, 3.0))
	track.add_theme_stylebox_override("scroll_focus", T.flat_box(T.INK, 3.0))
	track.add_theme_stylebox_override("grabber", T.flat_box(Color(T.EMBER, 0.55), 3.0))
	track.add_theme_stylebox_override("grabber_highlight", T.flat_box(T.EMBER_HI, 3.0))
	track.add_theme_stylebox_override("grabber_pressed", T.flat_box(T.GOLD, 3.0))
	parent.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", separation)
	scroll.add_child(rows)
	return rows


static func separator(color: Color) -> ColorRect:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size.y = 1.0
	line.color = Color(color.r, color.g, color.b, 0.55)
	return line


## A short rule with a lozenge at its centre, the keep's printer's mark.
static func ornament(color: Color) -> Control:
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
		P.rule(get_canvas_item(), c - Vector2(w, 0.0), c + Vector2(w, 0.0), color)


## A torn sheet of ink laid across the frame behind a screen: the scene shows
## dimmed above and below it; its ragged top and bottom edges carry a thin
## accent rim, the same paper-on-paper cut as the sheets and cards.
class PaperVeil extends Control:
	const INSET := 40.0
	const TEAR := 11.0
	var dim := Color.BLACK
	var sheet := Color.BLACK
	var rim := Color.WHITE

	func _init() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var ci := get_canvas_item()
		draw_rect(Rect2(Vector2.ZERO, size), dim)
		# Wider than the frame, so only the torn top and bottom ever show.
		var band := Rect2(-24.0, INSET - TEAR * 0.5, size.x + 48.0, size.y - INSET * 2.0 + TEAR)
		var paper := P.deckled(P.cut_rect(band, 0.0), band, TEAR, 41, P.TOP | P.BOTTOM)
		P.fill(ci, P.moved(paper, Vector2(4.0, 7.0)), Color(0.0, 0.0, 0.0, 0.45))
		P.fill(ci, paper, sheet)
		P.stroke(ci, paper, rim, 1.0)


# --- Buttons -----------------------------------------------------------------------

## A paper button of `kind` (PRIMARY, SECONDARY, QUIET, DANGER). It lifts
## toward the eye under focus or hover and presses in when taken; the kit's
## FocusFlame marks it too. `cue_kind` "" keeps it silent.
static func button(text: String, node_name: String, kind: int = SECONDARY, minimum := Vector2(0.0, 44.0), cue_kind: String = "ui_confirm") -> Button:
	var b := PaperButton.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = minimum
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", T.font(T.BUTTON))
	b.add_theme_font_size_override("font_size", T.size(T.BUTTON))
	if not cue_kind.is_empty():
		b.pressed.connect(func() -> void: emit_cue(b, cue_kind))
	style_button(b, kind)
	return b


## Dress `b` as a button of `kind` in every state (also used to turn a
## button to DANGER while it waits for a confirming press).
static func style_button(b: Button, kind: int) -> void:
	var styles := T.button_styles(kind)
	if b is PaperButton:
		(b as PaperButton).set_paper(styles.rest, styles.raised, styles.pressed, styles.disabled)
	else:
		b.add_theme_stylebox_override("normal", styles.rest)
		b.add_theme_stylebox_override("hover", styles.raised)
		b.add_theme_stylebox_override("pressed", styles.pressed)
		b.add_theme_stylebox_override("disabled", styles.disabled)
	b.add_theme_color_override("font_color", styles.ink)
	b.add_theme_color_override("font_disabled_color", styles.ink_disabled)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, styles.ink_hot)
	# Quiet words stand on the world itself, so they carry an ink halo.
	b.add_theme_color_override("font_outline_color", Color(T.INK_DEEP, 0.8))
	b.add_theme_constant_override("outline_size", 4 if kind == QUIET else 0)


## A Button whose paper lifts while it holds focus, not only under the mouse:
## Godot draws "focus" as an overlay, so the lift swaps the resting style.
class PaperButton extends Button:
	var _rest: StyleBox
	var _raised: StyleBox

	func set_paper(rest: StyleBox, raised: StyleBox, pressed: StyleBox, disabled: StyleBox) -> void:
		_rest = rest
		_raised = raised
		add_theme_stylebox_override("hover", raised)
		add_theme_stylebox_override("pressed", pressed)
		add_theme_stylebox_override("hover_pressed", pressed)
		add_theme_stylebox_override("disabled", disabled)
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_sync()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
			_sync()

	func _sync() -> void:
		if _rest != null:
			add_theme_stylebox_override("normal", _raised if has_focus() else _rest)


## A dealt card: a PaperButton in card paper banded with `tint`, holding
## `emblem` (a medallion), a serif title, the body text and a foot line.
## `key` prints the keyboard shortcut in the corner as a key cap (hidden
## while a pad is in use). The FocusFlame rides above it.
static func card(node_name: String, title: String, body: String, foot: String, tint: Color, emblem: Control = null, minimum := Vector2(280.0, 318.0), epic := false, key := "") -> Button:
	var b := PaperButton.new()
	b.name = node_name
	b.custom_minimum_size = minimum
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.set_meta("flame_at", "top")
	var styles := T.card_styles(tint, epic, absi(node_name.hash()) % 97)
	b.set_paper(styles.rest, styles.raised, styles.pressed, styles.disabled)

	var m := margin(T.S5, T.S5, T.S5, T.S5 - 4)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", T.S2)
	m.add_child(stack)
	if emblem != null:
		stack.add_child(emblem)
	stack.add_child(label(title, T.SUBHEAD, T.BONE))
	var text := label(body, T.BODY, T.ASH)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text.custom_minimum_size = Vector2(minimum.x - 2.0 * T.S5, 0.0)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(text)
	stack.add_child(label(foot, T.CAPS, tint))
	if not key.is_empty():
		var cap := glyph_for(key, "key", 20.0)
		cap.key_only = true
		b.add_child(cap)
		cap.position = Vector2(minimum.x - 36.0, 16.0)
	return b


# --- Settings controls -------------------------------------------------------------

## A paper switch, optionally with a title and a caption beside it. The knob
## slides from the ash side to the ember side and carries a small flame when
## lit, so its state reads by position and shape, never colour alone.
static func toggle(title := "", caption_text := "") -> CheckBox:
	var t := PaperToggle.new()
	t.title = title
	t.caption = caption_text
	# Button sizes itself from its own text, never a script's
	# _get_minimum_size, so the painted words claim their room here.
	t.custom_minimum_size = t.measure()
	t.toggled.connect(func(_on: bool) -> void: emit_cue(t, "ui_confirm"))
	return t


class PaperToggle extends CheckBox:
	const TRACK := Vector2(46.0, 24.0)
	var title := ""
	var caption := ""
	## Knob position, 0 (dark) to 1 (lit), eased between states.
	var _knob := 0.0
	var _knob_tween: Tween
	var _t := 0.0

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var blank := UiKit.blank_icon(TRACK)
		for icon in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
			add_theme_icon_override(icon, blank)
		toggled.connect(_on_toggled)
		for sig in [focus_entered, focus_exited, mouse_entered, mouse_exited]:
			sig.connect(queue_redraw)
		set_process(false)

	func _on_toggled(on: bool) -> void:
		UiKit.kill_tween(_knob_tween)
		set_process(on and not T.still())
		if T.still() or not is_inside_tree():
			_knob = 1.0 if on else 0.0
			queue_redraw()
			return
		_knob_tween = UiKit.tween(self)
		_knob_tween.tween_method(_set_knob, _knob, 1.0 if on else 0.0, T.FAST).set_trans(Tween.TRANS_SINE)

	func _set_knob(k: float) -> void:
		_knob = k
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		if is_visible_in_tree():
			queue_redraw()

	## The room the switch and its painted title and caption need.
	func measure() -> Vector2:
		var w := TRACK.x
		var h := TRACK.y + 4.0
		if not title.is_empty():
			w += T.S3 + maxf(P.text_width(title, T.BODY), P.text_width(caption, T.SMALL))
			h = maxf(h, 46.0 if not caption.is_empty() else 30.0)
		return Vector2(w, h)

	func _draw() -> void:
		var ci := get_canvas_item()
		# A state set without a signal (synced from the save) shows at once.
		var moving := _knob_tween != null and _knob_tween.is_valid()
		var knob := _knob if moving else (1.0 if button_pressed else 0.0)
		var hot := has_focus() or is_hovered()
		var track := Rect2(Vector2(0.0, (size.y - TRACK.y) * 0.5), TRACK)
		var groove := P.cut_rect(track, 5.0)
		if hot:
			P.halo(ci, groove, Color(T.EMBER, 0.8))
		P.fill(ci, groove, T.SHEET_LO)
		var kx := lerpf(track.position.x + 12.0, track.end.x - 12.0, knob)
		if knob > 0.0:
			var lit := Rect2(track.position, Vector2(kx - track.position.x, track.size.y))
			for part in Geometry2D.intersect_polygons(groove, P.cut_rect(lit, 0.0)):
				P.fill(ci, part, T.EMBER.lerp(T.CINDER, 1.0 - knob))
		P.stroke(ci, groove, T.GOLD if hot else T.HAIRLINE, 1.5 if hot else 1.0)
		var kc := Vector2(kx, track.get_center().y)
		var cap := P.cut_rect(Rect2(kc - Vector2(9.0, 9.0), Vector2(18.0, 18.0)), 4.0)
		P.fill(ci, P.moved(cap, Vector2(1.0, 2.0)), Color(0.0, 0.0, 0.0, 0.5))
		P.fill(ci, cap, T.SOOT.lerp(T.GOLD, knob))
		if knob >= 1.0:
			P.flame(ci, kc + Vector2(0.0, 5.0), 14.0, 9.0, 0.0 if T.still() else _t)
		else:
			P.lozenge(ci, kc, 3.0, T.INK)
		if title.is_empty():
			return
		var x := TRACK.x + T.S3
		var has_caption := not caption.is_empty()
		var title_y := size.y * 0.5 + (-3.0 if has_caption else 5.0)
		P.text(ci, Vector2(x, title_y), title, T.BODY, T.GOLD if hot else T.BONE)
		if has_caption:
			P.text(ci, Vector2(x, title_y + 18.0), caption, T.SMALL, T.ASH)


## A transparent texture of `box` size: reserves a control's icon space so the
## kit can paint its own glyph there.
static func blank_icon(box: Vector2) -> Texture2D:
	var img := Image.create_empty(int(box.x), int(box.y), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


## A 0..1 slider: an ink groove filled with ember, tick cuts every tenth and a
## gold lozenge grip that heats under focus.
static func slider(node_name: String, value: float, step := 0.05) -> HSlider:
	var s := PaperSlider.new()
	s.name = node_name
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0.0, 26.0)
	s.focus_mode = Control.FOCUS_ALL
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return s


class PaperSlider extends HSlider:
	const GRIP := 18.0
	var _hovered := false

	func _init() -> void:
		for state in ["slider", "grabber_area", "grabber_area_highlight", "focus"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var blank := UiKit.blank_icon(Vector2(GRIP, GRIP))
		for icon in ["grabber", "grabber_highlight", "grabber_disabled", "tick"]:
			add_theme_icon_override(icon, blank)
		value_changed.connect(func(_v: float) -> void: queue_redraw())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		mouse_entered.connect(_set_hovered.bind(true))
		mouse_exited.connect(_set_hovered.bind(false))

	func _set_hovered(on: bool) -> void:
		_hovered = on
		queue_redraw()

	func _draw() -> void:
		var ci := get_canvas_item()
		var hot := has_focus() or _hovered
		var y := size.y * 0.5
		var groove := Rect2(GRIP * 0.5, y - 3.0, size.x - GRIP, 6.0)
		var ratio := (value - min_value) / maxf(0.001, max_value - min_value)
		var x := groove.position.x + groove.size.x * ratio
		P.fill(ci, P.cut_rect(groove.grow(1.0), 2.0), Color(0.0, 0.0, 0.0, 0.45))
		P.fill(ci, P.cut_rect(groove, 2.0), T.SHEET_LO)
		if x - groove.position.x > 1.0:
			P.fill(ci, P.cut_rect(Rect2(groove.position, Vector2(x - groove.position.x, 6.0)), 1.0), T.EMBER)
			RenderingServer.canvas_item_add_line(ci, groove.position + Vector2(0.0, 1.0), Vector2(x, groove.position.y + 1.0), T.EMBER_HI, 1.0)
		for i in range(1, 10):
			var tx := groove.position.x + groove.size.x * float(i) / 10.0
			RenderingServer.canvas_item_add_line(ci, Vector2(tx, y + 5.0), Vector2(tx, y + 8.0), T.HAIRLINE, 1.0)
		var c := Vector2(x, y)
		if hot:
			P.halo(ci, PackedVector2Array([c + Vector2(0, -9), c + Vector2(7.5, 0), c + Vector2(0, 9), c + Vector2(-7.5, 0)]), Color(T.EMBER, 0.8))
		P.lozenge(ci, c + Vector2(1.0, 2.0), 9.5, Color(0.0, 0.0, 0.0, 0.5))
		P.lozenge(ci, c, 9.5, T.INK)
		P.lozenge(ci, c, 7.5, T.GOLD.lerp(T.HOT, 0.45) if hot else T.GOLD)


## A settings line: title and caption on the left, `control` on the right.
static func setting_row(title: String, caption_text: String, control: Control) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", T.S5)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	words.add_child(label(title, T.BODY, T.BONE, HORIZONTAL_ALIGNMENT_LEFT))
	if not caption_text.is_empty():
		words.add_child(label(caption_text, T.SMALL, T.ASH, HORIZONTAL_ALIGNMENT_LEFT))
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(control)
	return line


## A focusable ledger row: an optional `leading` emblem, title (and caption),
## then `trailing` (a price, a seal, a key cap) on the right. Quiet at rest;
## a slip of paper lifts under it with focus. Its children never take clicks.
static func row(node_name: String, title: String, caption_text := "", trailing: Control = null, leading: Control = null, height := 52.0) -> Button:
	var b := PaperButton.new()
	b.name = node_name
	b.custom_minimum_size = Vector2(0.0, height)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var styles := T.button_styles(QUIET)
	b.set_paper(styles.rest, styles.raised, styles.pressed, styles.disabled)
	var m := margin(T.S6, T.S4, 0, 0)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", T.S4)
	m.add_child(line)
	if leading != null:
		leading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		leading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(leading)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	line.add_child(words)
	words.add_child(label(title, T.BODY, T.BONE, HORIZONTAL_ALIGNMENT_LEFT))
	if not caption_text.is_empty():
		words.add_child(label(caption_text, T.SMALL, T.ASH, HORIZONTAL_ALIGNMENT_LEFT))
	if trailing != null:
		trailing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		trailing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(trailing)
	return b


## Ribbon tabs: bookmarks hanging from a sheet's top edge; the open page is
## ember. LB/RB, PageUp/PageDown and [ ] turn pages while it is on screen.
static func tabs(names: Array) -> Tabs:
	var strip := Tabs.new()
	strip.setup(names)
	return strip


class Tabs extends HBoxContainer:
	signal tab_changed(index: int)
	var current := 0
	var _buttons: Array = []
	var _styles := T.ribbon_styles()

	func setup(names: Array) -> void:
		add_theme_constant_override("separation", T.S2)
		for i in range(names.size()):
			var b := PaperButton.new()
			b.name = "Tab%d" % i
			b.text = str(names[i])
			b.focus_mode = Control.FOCUS_ALL
			b.custom_minimum_size = Vector2(104.0, 42.0)
			b.add_theme_font_override("font", T.font(T.CAPS))
			b.add_theme_font_size_override("font_size", T.size(T.CAPS))
			b.pressed.connect(select.bind(i))
			add_child(b)
			_buttons.append(b)
		select(0, false)

	## Open page `index`; `announce` emits tab_changed and sounds a page turn.
	func select(index: int, announce := true) -> void:
		current = wrapi(index, 0, maxi(1, _buttons.size()))
		for i in range(_buttons.size()):
			var b: PaperButton = _buttons[i]
			var open := i == current
			b.set_paper(_styles.open if open else _styles.rest, _styles.open_raised if open else _styles.raised, _styles.open, _styles.rest)
			b.add_theme_color_override("font_color", T.INK if open else T.ASH)
			for state in ["font_hover_color", "font_focus_color", "font_pressed_color"]:
				b.add_theme_color_override(state, T.INK if open else T.BONE)
		if announce:
			UiKit.emit_cue(self, "ui_move")
			tab_changed.emit(current)

	func _unhandled_input(event: InputEvent) -> void:
		if not is_visible_in_tree():
			return
		for pair in [[UiInput.TAB_PREV, -1], [UiInput.TAB_NEXT, 1]]:
			if event.is_action_pressed(pair[0]):
				select(current + int(pair[1]))
				get_viewport().set_input_as_handled()


# --- Meters and pips ---------------------------------------------------------------

## A meter: a paper band in an inked well. Losses linger as a pale chip that
## drains after a beat; the leading edge burns; `notches` cut thresholds;
## `hot` makes the band breathe white-hot (a full Graveflame).
static func meter(fill_color: Color, height := 10.0, notches: Array = []) -> Meter:
	var m := Meter.new()
	m.fill = fill_color
	m.notches = notches
	m.custom_minimum_size = Vector2(0.0, height)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


class Meter extends Control:
	var value := 1.0
	var max_value := 1.0
	var fill := T.BLOOD
	var notches: Array = []
	var hot := false
	## Whether the leading edge carries an ember.
	var burning := true
	var _trail := 1.0
	var _trail_tween: Tween
	var _t := 0.0

	func _ready() -> void:
		resized.connect(queue_redraw)

	## Show `v` of `maximum`. Losses hold as a pale chip, then drain; gains
	## fill at once. Reduced motion drops the chip at once.
	func set_value(v: float, maximum: float) -> void:
		var span_before := value / max_value
		max_value = maxf(1.0, maximum)
		var next := clampf(v, 0.0, max_value)
		UiKit.kill_tween(_trail_tween)
		if next >= value or T.still() or not is_inside_tree():
			_trail = next
		else:
			_trail = maxf(_trail, span_before * max_value)
			_trail_tween = UiKit.tween(self)
			_trail_tween.tween_interval(0.35)
			_trail_tween.tween_method(_set_trail, _trail, next, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		value = next
		queue_redraw()

	func _set_trail(v: float) -> void:
		_trail = v
		queue_redraw()

	func _process(delta: float) -> void:
		if (hot or burning) and not T.still():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var ci := get_canvas_item()
		var r := Rect2(Vector2.ZERO, size)
		var well := P.cut_rect(r, minf(4.0, size.y * 0.4))
		P.fill(ci, P.moved(well, Vector2(0.0, 1.0)), Color(0.0, 0.0, 0.0, 0.5))
		P.fill(ci, well, T.SHEET_LO)
		var span := size.x / max_value
		if _trail > value:
			_band(ci, well, _trail * span, Color("f4e2c8"))
		var band := fill
		if hot:
			band = fill.lerp(T.HOT, 0.4 + 0.25 * sin(_t * 7.5))
		var x := value * span
		_band(ci, well, x, band)
		if x > 2.0:
			RenderingServer.canvas_item_add_line(ci, Vector2(1.0, 1.0), Vector2(x - 1.0, 1.0), Color(band.lightened(0.4), 0.8), 1.0)
		for mark in notches:
			var nx := roundf(size.x * float(mark))
			RenderingServer.canvas_item_add_rect(ci, Rect2(nx - 1.0, -1.0, 2.0, size.y + 2.0), T.INK_DEEP)
		if burning and x > 2.0 and x < size.x - 1.0:
			var flick := sin(_t * 23.0) * 0.5 + sin(_t * 37.0) * 0.5
			RenderingServer.canvas_item_add_circle(ci, Vector2(x, size.y * 0.5), size.y * (0.75 + 0.1 * flick), Color(T.EMBER, 0.3))
			RenderingServer.canvas_item_add_rect(ci, Rect2(x - 1.5, 0.0, 2.0, size.y), T.HOT)
		P.stroke(ci, well, Color(0.0, 0.0, 0.0, 0.55), 1.0)

	func _band(ci: RID, well: PackedVector2Array, x: float, color: Color) -> void:
		if x <= 0.0:
			return
		for part in Geometry2D.intersect_polygons(well, P.cut_rect(Rect2(0.0, 0.0, x, size.y), 0.0)):
			P.fill(ci, part, color)


## A row of `count` pips, the first `filled` lit: "lozenge" (ranks, fury
## tiers), "flame" (flasks: a lit flame or a snuffed wick) or "cell". Setting
## `current` crowns one pip with a flame (the chamber the knight stands in).
static func pips(count: int, filled: int, shape := "lozenge", color := T.GOLD) -> Pips:
	var p := Pips.new()
	p.shape = shape
	p.color = color
	p.count = count
	p.filled = filled
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


class Pips extends Control:
	var count := 3:
		set(v):
			count = v
			update_minimum_size()
			queue_redraw()
	var filled := 0:
		set(v):
			filled = v
			queue_redraw()
	var current := -1:
		set(v):
			current = v
			queue_redraw()
	var shape := "lozenge"
	var color := T.GOLD
	var spacing := 16.0
	## The last pip is the throne: a crown instead of a pip.
	var crowned := false

	func _get_minimum_size() -> Vector2:
		return Vector2(spacing * float(count), 24.0 if shape == "flame" or current >= 0 else 16.0)

	func _draw() -> void:
		var ci := get_canvas_item()
		for i in range(count):
			var c := Vector2(spacing * (float(i) + 0.5), size.y * 0.5)
			var lit := i < filled
			if i == current:
				P.flame(ci, c + Vector2(0.0, 7.0), 18.0, 10.0, 0.0, float(i))
				continue
			if crowned and i == count - 1:
				P.crown(ci, c + Vector2(0.0, 5.0), 14.0, color if lit else T.WARDEN)
				continue
			match shape:
				"flame":
					if lit:
						P.flame(ci, c + Vector2(0.0, 9.0), 17.0, 10.0, 0.0, float(i))
					else:
						RenderingServer.canvas_item_add_line(ci, c + Vector2(0.0, 8.0), c + Vector2(0.0, 1.0), T.SOOT, 1.5)
						RenderingServer.canvas_item_add_circle(ci, c + Vector2(0.0, 0.5), 1.8, Color(T.SOOT, 0.8))
				"cell":
					var hex := PackedVector2Array()
					for k in range(6):
						hex.append(c + Vector2.from_angle(TAU * float(k) / 6.0 + PI / 6.0) * 6.0)
					if lit:
						P.fill(ci, hex, color)
					else:
						P.stroke(ci, hex, T.SOOT, 1.2)
				_:
					P.lozenge(ci, c, 6.0, color if lit else T.SOOT, not lit)


# --- Prompts -----------------------------------------------------------------------

## The key cap or pad button for `action` on the device last touched. It
## repaints itself whenever the device or a binding changes.
static func glyph(action: String, height := 22.0) -> Glyph:
	var g := Glyph.new()
	g.action = action
	g.height = height
	return g


## A cap for one fixed binding on one device (a table of both devices, the
## number on a card).
static func glyph_for(binding: String, device: String, height := 22.0) -> Glyph:
	var g := Glyph.new()
	g.binding = binding
	g.device = device
	g.height = height
	return g


class Glyph extends Control:
	var action := ""
	var binding := ""
	var device := "key"
	var height := 22.0
	## Painted ember: a rebind waiting for its key, a prompt being held.
	var lit := false:
		set(v):
			lit = v
			queue_redraw()
	## Shown only while the keyboard is the device in use.
	var key_only := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_to_group(UiInput.PROMPT_GROUP)
		refresh_prompts()

	func refresh_prompts() -> void:
		var w := P.prompt_width(action, height) if not action.is_empty() else P.cap_width(binding, device, height)
		custom_minimum_size = Vector2(w, height)
		size = custom_minimum_size
		if key_only:
			visible = UiInput.last_device == "key"
		queue_redraw()

	func _draw() -> void:
		var at := Vector2(0.0, (size.y - height) * 0.5)
		if action.is_empty():
			P.cap(get_canvas_item(), at, binding, device, height, lit)
		else:
			P.prompt(get_canvas_item(), at, action, height, lit)


## A footer of prompts: [[action, "Take"], ["ui_cancel", "Back"]] as caps
## with their words, in the device last touched.
static func prompt_bar(entries: Array) -> HBoxContainer:
	var bar_box := HBoxContainer.new()
	bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bar_box.add_theme_constant_override("separation", T.S2)
	for i in range(entries.size()):
		if i > 0:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(T.S4, 0.0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar_box.add_child(gap)
		bar_box.add_child(glyph(str(entries[i][0])))
		var words := label(str(entries[i][1]), T.CAPS, T.ASH, HORIZONTAL_ALIGNMENT_LEFT)
		words.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bar_box.add_child(words)
	return bar_box


# --- Notes: captions, toasts, banners, seals -----------------------------------------

## A small slip with a pointer rising from its top: tooltips and readouts
## hung under what they describe.
static func caption(text: String, tint := T.HAIRLINE) -> PanelContainer:
	var style := T.slip_style(tint, 13)
	style.pointer = 6.0
	var slip := PanelContainer.new()
	slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slip.add_theme_stylebox_override("panel", style)
	slip.add_child(label(text, T.SMALL, T.BONE))
	return slip


## A slip that slides up at the foot of `parent`, holds `hold` seconds and
## folds away, freeing itself: rebind notes, "the vows awaken".
static func toast(parent: Control, text: String, tint := T.GOLD, hold := 2.4) -> PanelContainer:
	var slip := passive_panel(parent, T.slip_style(tint, 17))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", T.S3)
	slip.add_child(line)
	line.add_child(seal(22.0, tint.darkened(0.35), "flame"))
	line.add_child(label(text, T.BODY, T.BONE, HORIZONTAL_ALIGNMENT_LEFT))
	slip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 72)
	slip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	slip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var t := slide_in(slip)
	t.tween_interval(hold)
	t.tween_callback(func() -> void: fold_out(slip, T.MED, true))
	return slip


## A banner strip across `parent`, centred in the band `top`..`bottom`:
## kicker, title and an optional line, unrolled from its centre by play().
static func banner(parent: Control, accent: Color, top: float, bottom: float, title_role := T.HEADLINE, title_color := T.BONE) -> Banner:
	var b := Banner.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	b.offset_top = top
	b.offset_bottom = bottom
	b.setup(accent, title_role, title_color)
	return b


class Banner extends CenterContainer:
	var strip: PanelContainer
	var kicker: Label
	var title: Label
	var line: Label
	var _tween: Tween

	func setup(accent: Color, title_role: String, title_color: Color) -> void:
		strip = UiKit.passive_panel(self, T.strip_style(accent, 23))
		strip.custom_minimum_size = Vector2(460.0, 0.0)
		strip.resized.connect(func() -> void: strip.pivot_offset = strip.size * 0.5)
		var stack := VBoxContainer.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_theme_constant_override("separation", 0)
		strip.add_child(stack)
		kicker = UiKit.label("", T.CAPS, T.ASH)
		title = UiKit.label("", title_role, title_color)
		line = UiKit.label("", T.VOICE, T.ASH)
		for part in [kicker, title, line]:
			stack.add_child(part)
		visible = false

	## Unroll the strip, hold it `hold` seconds, fold it away. Returns the
	## tween so a caller can chain after it.
	func play(kicker_text: String, title_text: String, line_text := "", hold := 1.6) -> Tween:
		UiKit.kill_tween(_tween)
		kicker.text = kicker_text
		title.text = title_text
		line.text = line_text
		line.visible = not line_text.is_empty()
		visible = true
		modulate.a = 0.0
		strip.scale = Vector2.ONE
		_tween = UiKit.tween(self)
		if T.still():
			_tween.tween_property(self, "modulate:a", 1.0, 0.15)
			_tween.tween_interval(hold)
			_tween.tween_property(self, "modulate:a", 0.0, 0.15)
		else:
			strip.scale = Vector2(0.04, 1.0)
			_tween.set_parallel(true)
			_tween.tween_property(self, "modulate:a", 1.0, T.FAST)
			_tween.tween_property(strip, "scale:x", 1.0, T.SLOW).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_tween.set_parallel(false)
			_tween.tween_interval(hold)
			_tween.tween_property(strip, "scale:y", 0.0, T.MED).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			_tween.parallel().tween_property(self, "modulate:a", 0.0, T.MED)
		_tween.tween_callback(hide)
		return _tween

	func stop() -> void:
		UiKit.kill_tween(_tween)
		visible = false


## A wax seal `diameter` px across: pressed wax with an emboss ("flame",
## "crown", "tick", ""), or the faint ring of an oath not yet sworn.
static func seal(diameter: float, wax := T.WAX, emboss := "flame", pressed := true) -> Seal:
	var s := Seal.new()
	s.wax = wax
	s.emboss = emboss
	s.pressed = pressed
	s.custom_minimum_size = Vector2(diameter, diameter)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


class Seal extends Control:
	var wax := T.WAX
	var emboss := "flame"
	var pressed := true:
		set(v):
			pressed = v
			queue_redraw()

	func _draw() -> void:
		P.seal(get_canvas_item(), size * 0.5, minf(size.x, size.y) * 0.5 - 1.0, wax, emboss, pressed)


# --- Focus -------------------------------------------------------------------------

## The knight's flame beside whatever holds focus inside `root`: the one
## focus marker every screen shares. It hops between controls (snaps under
## reduced motion) and sits above a control marked with meta flame_at="top"
## (cards). A control with meta no_flame is left unmarked.
static func focus_flame(root: Control) -> FocusFlame:
	var f := FocusFlame.new()
	f.name = "FocusFlame"
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(f)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return f


class FocusFlame extends Control:
	var _at := Vector2.ZERO
	var _shown := false
	var _t := 0.0

	func _process(delta: float) -> void:
		var want: Variant = _anchor(get_viewport().gui_get_focus_owner())
		if want == null:
			if _shown:
				_shown = false
				queue_redraw()
			return
		var target: Vector2 = get_global_transform().affine_inverse() * (want as Vector2)
		if not _shown or T.still():
			_at = target
		else:
			_at = _at.lerp(target, 1.0 - exp(-delta * 24.0))
			_t += delta
		_shown = true
		queue_redraw()

	## Where the flame stands for `owner`, in global space, or null for none.
	func _anchor(owner: Control) -> Variant:
		if owner == null or not owner.is_visible_in_tree() or owner.has_meta("no_flame"):
			return null
		if not get_parent().is_ancestor_of(owner):
			return null
		var r := owner.get_global_rect()
		if owner.get_meta("flame_at", "") == "top":
			return Vector2(r.get_center().x, r.position.y - 4.0)
		# Beside the control on the left, or on its right when the frame's
		# edge leaves no room.
		var x := r.position.x - 17.0 if r.position.x > 40.0 else r.end.x + 17.0
		return Vector2(x, r.get_center().y + 10.0)

	func _draw() -> void:
		if not _shown:
			return
		var ci := get_canvas_item()
		# Its own small light on the paper, then the flame.
		RenderingServer.canvas_item_add_circle(ci, _at + Vector2(0.0, -9.0), 16.0, Color(T.EMBER, 0.08))
		RenderingServer.canvas_item_add_circle(ci, _at + Vector2(0.0, -8.0), 9.0, Color(T.EMBER, 0.14))
		P.flame(ci, _at, 26.0, 15.0, _t)


# --- Lists and focus plumbing ------------------------------------------------------

static func clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


static func focus_first_control(root: Node) -> bool:
	for child in root.get_children():
		if child is Control:
			var control := child as Control
			if control.visible and control.focus_mode != Control.FOCUS_NONE:
				if not (control is BaseButton) or not (control as BaseButton).disabled:
					control.grab_focus.call_deferred()
					return true
		if focus_first_control(child):
			return true
	return false


## Name of the focused control when it sits inside `container`, so a list
## rebuilt under the cursor can hand focus back to the same row.
static func focused_name_in(container: Node) -> String:
	var owner := container.get_viewport().gui_get_focus_owner()
	return str(owner.name) if owner != null and container.is_ancestor_of(owner) else ""


## Focus the button named `kept` in `rows`, or the next usable one after it
## (the first usable one when nothing was kept), else `fallback`. Callers
## defer it, so a list rebuilt twice in one frame (a rebind that displaces
## another key) is searched only once it has settled.
static func focus_row(rows: Node, kept: String, fallback: Button) -> void:
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


# --- Emblems -----------------------------------------------------------------------

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
		draw_circle(c, r, T.SHEET_LO)
		draw_arc(c, r, 0.0, TAU, 48, Color(tint, 0.85), 2.0, true)
		draw_arc(c, r - 6.0, 0.0, TAU, 48, Color(tint, 0.25), 1.0, true)
		if epic:
			var breath := 0.5 + 0.5 * sin(_t * 2.2)
			draw_arc(c, r + 5.0, 0.0, TAU, 48, Color(tint, 0.15 + 0.25 * breath), 3.0, true)
		BoonArt.draw(self, boon_id, c, r * 0.62, tint)


## The seal and its word, so a kept vow never reads by colour alone.
static func kept_seal() -> Control:
	var mark := HBoxContainer.new()
	mark.add_theme_constant_override("separation", 6)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := KeptSeal.new()
	s.custom_minimum_size = Vector2(22.0, 22.0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(s)
	mark.add_child(label("KEPT", T.MICRO, T.WAX_HI, HORIZONTAL_ALIGNMENT_LEFT))
	return mark


## Wax pressed beside a vow that has been kept through a won descent.
class KeptSeal extends Control:
	func _draw() -> void:
		P.seal(get_canvas_item(), size * 0.5, 10.5, T.WAX, "flame")


## Rank as a row of small lozenges: filled for owned, hollow for the rest.
static func rank_pips(rank: int, max_rank: int) -> Control:
	var p := RankPips.new()
	p.rank = rank
	p.max_rank = max_rank
	p.custom_minimum_size = Vector2(14.0 * float(max_rank), 14.0)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


class RankPips extends Control:
	var rank := 0
	var max_rank := 1
	func _draw() -> void:
		for i in range(max_rank):
			P.lozenge(get_canvas_item(), Vector2(7.0 + float(i) * 14.0, size.y * 0.5), 5.5, T.GOLD if i < rank else T.SOOT, i >= rank)


# --- The HUD's legacy bars (until the HUD rebuild moves to Meter) ------------------

static func bar(fill_color: Color, background: Color, height: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.custom_minimum_size.y = height
	b.show_percentage = false
	b.add_theme_stylebox_override("background", T.bar_box(background))
	b.add_theme_stylebox_override("fill", T.bar_box(fill_color))
	return b


## A bar with a chip trail behind it. Returns { holder, bar, trail }.
static func trailed_bar(fill_color: Color, background: Color, height: float) -> Dictionary:
	var holder := Control.new()
	holder.custom_minimum_size.y = height
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var trail := bar(Color("f4e2c8"), background, height)
	holder.add_child(trail)
	trail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var front := bar(fill_color, Color(0.0, 0.0, 0.0, 0.0), height)
	holder.add_child(front)
	front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for b in [trail, front]:
		(b as ProgressBar).max_value = 100.0
		(b as ProgressBar).value = 100.0
	return { "holder": holder, "bar": front, "trail": trail }


## Lay ink notches over `target` at each fraction in `marks`.
static func notch_bar(target: Control, marks: Array) -> void:
	var notches := BarNotches.new()
	notches.marks = marks
	notches.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(notches)
	notches.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Thin cuts across a bar: thresholds the player spends or fights toward.
class BarNotches extends Control:
	var marks: Array = []
	func _draw() -> void:
		for mark in marks:
			var x := roundf(size.x * float(mark))
			draw_rect(Rect2(x - 1.0, -1.0, 2.0, size.y + 2.0), T.INK)


# --- Screens additions -------------------------------------------------------------
# Pieces the full screens (ui_screens.gd and its pages) are cut from, added after
# the foundation so its builders stay exactly as they were.

## Lay a page down: it rises `rise` px into place and turns flat from a slight
## angle, the way paper settles on paper. Only for controls no container
## positions (a screen's centring box): a container would re-sort it
## mid-flight. Reduced motion keeps a short fade.
static func settle_in(node: Control, rise := 18.0, turn := 0.018) -> Tween:
	var rest: Vector2 = node.get_meta("rest", node.position)
	node.set_meta("rest", rest)
	kill_tween(node.get_meta("settling", null))
	var t := tween(node)
	node.set_meta("settling", t)
	node.position = rest
	node.rotation = 0.0
	node.modulate.a = 0.0
	if T.still():
		t.tween_property(node, "modulate:a", 1.0, 0.15)
		return t
	node.pivot_offset = node.size * 0.5
	node.position = rest + Vector2(0.0, rise)
	node.rotation = turn
	t.set_parallel(true)
	t.tween_property(node, "modulate:a", 1.0, T.MED)
	t.tween_property(node, "position", rest, T.SLOW).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "rotation", 0.0, T.SLOW).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return t


## A prompt as a flat link: the cap for each of `actions` (one action or an
## Array) and a word, in the device last touched. A named link takes mouse
## clicks (a screen's BACK), an unnamed one only reads. Never in the focus
## chain: keys and pads press the cap itself.
static func prompt_link(actions: Variant, words: String, node_name := "") -> Button:
	var b := Button.new()
	b.name = node_name if not node_name.is_empty() else "Prompt"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE if node_name.is_empty() else Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", T.S2)
	b.add_child(line)
	for action in (actions as Array if actions is Array else [actions]):
		line.add_child(glyph(str(action)))
	var word := label(words, T.CAPS, T.ASH, HORIZONTAL_ALIGNMENT_LEFT)
	word.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.add_child(word)
	# A Button measures only its own text, so the painted caps claim their room.
	line.minimum_size_changed.connect(func() -> void: b.custom_minimum_size = line.get_combined_minimum_size())
	b.mouse_entered.connect(func() -> void: word.add_theme_color_override("font_color", T.GOLD))
	b.mouse_exited.connect(func() -> void: word.add_theme_color_override("font_color", T.ASH))
	return b


## The caps for several bindings on one device, side by side: a cell of a
## bindings table. Its "bindings" meta holds the names " / " joined, the way
## UiInput.binding_text writes them, so the cell can be read back.
static func caps(names: Array, device: String, height := 22.0) -> HBoxContainer:
	var cell := HBoxContainer.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.alignment = BoxContainer.ALIGNMENT_END
	cell.add_theme_constant_override("separation", T.S1 + 2)
	for binding in names:
		cell.add_child(glyph_for(str(binding), device, height))
	cell.set_meta("bindings", " / ".join(names))
	return cell


## Count `l` up from nothing to `to`, writing each step through `shown` (a
## number to its text), so a result arrives like a tally read aloud. Reduced
## motion writes the final figure at once (and returns null).
static func roll_number(l: Label, to: float, shown: Callable, delay := 0.0, duration := 0.9) -> Tween:
	kill_tween(l.get_meta("rolling", null))
	if T.still() or to <= 0.0:
		l.text = shown.call(to)
		return null
	l.text = shown.call(0.0)
	var t := tween(l)
	l.set_meta("rolling", t)
	t.tween_interval(delay)
	t.tween_method(func(v: float) -> void: l.text = shown.call(v), 0.0, to, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	return t
