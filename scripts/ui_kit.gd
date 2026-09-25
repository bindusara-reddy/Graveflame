class_name UiKit
extends RefCounted
## The reusable pieces every Graveflame screen is built from. Static builders
## return plain Godot controls, so a screen stays a readable list of calls.

const VFX := preload("res://scripts/vfx.gd")
const T := preload("res://scripts/ui_theme.gd")


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

static func label(text: String, size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = alignment
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Compact HUD labels must keep their intrinsic width inside HBoxContainers;
	# callers that render paragraphs opt into wrapping explicitly.
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("000000b0"))
	l.add_theme_constant_override("outline_size", 2 if size >= 18 else 1)
	if size >= 30:
		l.add_theme_font_override("font", T.heading_font())
		l.add_theme_constant_override("outline_size", 3)
	return l


## A caption on the left and its value on the right. Returns the value label.
static func stat_line(parent: VBoxContainer, title: String, value: String, value_color: Color, value_size := 12) -> Label:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	row.add_child(label(title, 10, T.C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	var result := label(value, value_size, value_color, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(result)
	return result


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


# --- Layout ------------------------------------------------------------------------

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


## A flat sheet of colour laid over `preset`. Decorative sheets let input
## through; a backdrop that must stop clicks reaching what lies beneath passes
## blocks_input.
static func sheet(parent: Control, color: Color, preset: Control.LayoutPreset, blocks_input := false) -> ColorRect:
	var s := ColorRect.new()
	s.mouse_filter = Control.MOUSE_FILTER_STOP if blocks_input else Control.MOUSE_FILTER_IGNORE
	s.color = color
	parent.add_child(s)
	s.set_anchors_and_offsets_preset(preset)
	return s


## A centred card on `parent` holding a padded column; the card is stored as
## the parent's "dialog" meta. Returns the column to fill.
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
	card.add_theme_stylebox_override("panel", T.panel_box(Color("1a1522f0"), accent.darkened(0.35), 14, 1, 18))
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
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	return row


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
	track.add_theme_stylebox_override("scroll", T.flat_box(T.C_INK, 3.0))
	track.add_theme_stylebox_override("scroll_focus", T.flat_box(T.C_INK, 3.0))
	track.add_theme_stylebox_override("grabber", T.flat_box(Color(T.C_EMBER, 0.55), 3.0))
	track.add_theme_stylebox_override("grabber_highlight", T.flat_box(T.C_EMBER_HI, 3.0))
	track.add_theme_stylebox_override("grabber_pressed", T.flat_box(T.C_GOLD, 3.0))
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
		draw_line(c + Vector2(-w, 0.0), c + Vector2(-12.0, 0.0), Color(color, 0.55), 1.0)
		draw_line(c + Vector2(12.0, 0.0), c + Vector2(w, 0.0), Color(color, 0.55), 1.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -5.0), c + Vector2(6.0, 0.0), c + Vector2(0.0, 5.0), c + Vector2(-6.0, 0.0)]), color)
		draw_circle(c + Vector2(-w, 0.0), 1.5, Color(color, 0.55))
		draw_circle(c + Vector2(w, 0.0), 1.5, Color(color, 0.55))


## A torn sheet of ink laid across the frame behind a screen's card: the scene
## shows dimmed above and below it, and its ragged top and bottom edges carry
## a thin accent rim, the same sheet-on-sheet cut as the dialogs and cards.
class PaperVeil extends Control:
	const INSET := 40.0
	const TEAR := 9.0
	const POINTS := 64
	var dim := Color.BLACK
	var sheet := Color.BLACK
	var rim := Color.WHITE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), dim)
		var top := _torn_edge(INSET, 1)
		var bottom := _torn_edge(size.y - INSET, 2)
		var outline := top.duplicate()
		for i in range(bottom.size() - 1, -1, -1):
			outline.append(bottom[i])
		var shadow := outline.duplicate()
		for i in range(shadow.size()):
			shadow[i] += Vector2(4.0, 6.0)
		draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.45))
		draw_colored_polygon(outline, sheet)
		draw_polyline(top, rim, 1.0)
		draw_polyline(bottom, rim, 1.0)

	## A ragged line across the frame at height `y`, the same tear every draw.
	func _torn_edge(y: float, salt: int) -> PackedVector2Array:
		var edge := PackedVector2Array()
		for i in range(POINTS + 1):
			var jag := (VFX.hash01(i, salt) - 0.5) * 2.0 * TEAR
			edge.append(Vector2(size.x * float(i) / float(POINTS), y + jag))
		return edge


# --- Meters ------------------------------------------------------------------------

static func bar(fill: Color, background: Color, height: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.custom_minimum_size.y = height
	b.show_percentage = false
	b.add_theme_stylebox_override("background", T.bar_box(background))
	b.add_theme_stylebox_override("fill", T.bar_box(fill))
	return b


## A bar with a chip trail behind it. Returns { holder, bar, trail }.
static func trailed_bar(fill: Color, background: Color, height: float) -> Dictionary:
	var holder := Control.new()
	holder.custom_minimum_size.y = height
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var trail := bar(Color("f4e2c8"), background, height)
	holder.add_child(trail)
	trail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var front := bar(fill, Color(0.0, 0.0, 0.0, 0.0), height)
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
			draw_rect(Rect2(x - 1.0, -1.0, 2.0, size.y + 2.0), Color("100d18"))


## Rank as a row of small lozenges: filled for owned, hollow for the rest.
static func rank_pips(rank: int, max_rank: int) -> Control:
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


# --- Controls ----------------------------------------------------------------------

static func button(text: String, node_name: String, primary: bool, minimum: Vector2, cue_kind: String = "ui_confirm") -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = minimum
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_constant_override("outline_size", 1)
	b.add_theme_color_override("font_outline_color", Color("00000080"))
	if not cue_kind.is_empty():
		b.pressed.connect(func() -> void: emit_cue(b, cue_kind))
	style_button(b, primary)
	return b


## The ember (primary) or quiet (secondary) look of a menu button in every state.
static func style_button(b: Button, primary: bool) -> void:
	var normal_bg := T.C_EMBER if primary else T.C_SURFACE_HI
	var normal_border := T.C_EMBER_HI if primary else T.C_EDGE
	var normal_text := T.C_INK if primary else T.C_TEXT
	b.add_theme_stylebox_override("normal", T.button_box(normal_bg, normal_border, 1))
	b.add_theme_stylebox_override("hover", T.button_box(normal_bg.lightened(0.12), T.C_EMBER_HI, 2))
	b.add_theme_stylebox_override("pressed", T.button_box(normal_bg.darkened(0.12), T.C_GOLD, 2))
	b.add_theme_stylebox_override("focus", T.button_box(Color(normal_bg.r, normal_bg.g, normal_bg.b, 0.35), T.C_GOLD, 2))
	b.add_theme_stylebox_override("disabled", T.button_box(Color("17131d"), Color("30293a"), 1))
	b.add_theme_color_override("font_color", normal_text)
	b.add_theme_color_override("font_hover_color", T.C_TEXT if primary else T.C_EMBER_HI)
	b.add_theme_color_override("font_pressed_color", T.C_TEXT)
	b.add_theme_color_override("font_focus_color", T.C_TEXT)
	b.add_theme_color_override("font_disabled_color", Color("6f6578"))


## Sliders in the keep's idiom: an ink groove filled with ember up to a gold
## lozenge grip, which brightens under focus or the cursor.
static func paper_slider(slider: HSlider) -> void:
	slider.add_theme_stylebox_override("slider", T.flat_box(T.C_SURFACE_HI, 3.0))
	slider.add_theme_stylebox_override("grabber_area", T.flat_box(T.C_EMBER, 3.0))
	slider.add_theme_stylebox_override("grabber_area_highlight", T.flat_box(T.C_EMBER_HI, 3.0))
	slider.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var icons := T.toggle_icons()
	slider.add_theme_icon_override("grabber", icons["grip"])
	slider.add_theme_icon_override("grabber_highlight", icons["grip_hot"])


static func check(title: String, description: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = "%s\n%s" % [title, description]
	c.custom_minimum_size.y = 54.0
	c.focus_mode = Control.FOCUS_ALL
	c.add_theme_font_size_override("font_size", 14)
	c.add_theme_color_override("font_color", T.C_TEXT)
	c.add_theme_color_override("font_hover_color", T.C_EMBER_HI)
	c.add_theme_color_override("font_focus_color", T.C_GOLD)
	var icons := T.toggle_icons()
	c.add_theme_icon_override("checked", icons["checked"])
	c.add_theme_icon_override("unchecked", icons["unchecked"])
	c.add_theme_icon_override("checked_disabled", icons["unchecked"])
	c.add_theme_icon_override("unchecked_disabled", icons["unchecked"])
	c.add_theme_constant_override("h_separation", 10)
	c.add_theme_constant_override("icon_max_width", 22)
	c.toggled.connect(func(_on: bool) -> void: emit_cue(c, "ui_confirm"))
	return c


# --- Focus -------------------------------------------------------------------------

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
		draw_circle(c, r, Color("120e19"))
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
	var seal := KeptSeal.new()
	seal.custom_minimum_size = Vector2(22.0, 22.0)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(seal)
	mark.add_child(label("KEPT", 11, Color("c46f7b"), HORIZONTAL_ALIGNMENT_LEFT))
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
