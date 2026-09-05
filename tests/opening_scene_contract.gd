extends SceneTree
## Opening-scene contract on the REAL presented window and the real main.tscn:
## a purpose-built title tableau exists and fills the native viewport, the knight
## silhouette is framed away from the menu column, the arrival reveal never blocks
## input, the tableau lives only while the title is shown, the gameplay actor stays
## the untouched Player, reduced motion is static, and repeated returns to the
## title never leak scene nodes. Needs a display:
##   godot4 --path . --audio-driver Dummy --script res://tests/opening_scene_contract.gd

var checks := 0
var failures := 0
var game: Game
var ui: UI
var starts := 0


func _init() -> void:
	call_deferred("_run")


func check(cond: bool, message: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + message)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _focus_name() -> String:
	var owner := root.gui_get_focus_owner()
	return owner.name if owner != null else "<none>"


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total


func _find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var hit := _find_type(child, type_name)
		if hit != null:
			return hit
	return null


func _set_viewport(size: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_position(Vector2i(160, 120))
	DisplayServer.window_set_size(size)
	await _frames(8)
	check(root.size == size, "presented viewport is %s (got %s)" % [size, root.size])


func _tableau() -> Control:
	return (ui._panels["title"] as Control).get_node_or_null("TitleTableau") as Control


func _check_framing(label: String) -> void:
	var tableau := _tableau()
	if tableau == null:
		check(false, "%s: tableau missing" % label)
		return
	# canvas_items stretch keeps the canvas at the design size; the visible
	# rect is the native framing in canvas units.
	var bounds := root.get_visible_rect()
	check(tableau.get_global_rect() == bounds, "%s: tableau fills the native framing %s (got %s)" % [label, bounds, tableau.get_global_rect()])
	var knight: Rect2 = tableau.knight_rect()
	check(bounds.encloses(knight), "%s: knight silhouette fully in frame (%s)" % [label, knight])
	check(knight.get_center().x < bounds.size.x * 0.45, "%s: knight stands in the left third (%s)" % [label, knight])
	check(knight.end.y > bounds.size.y * 0.55 and knight.end.y < bounds.size.y * 0.95, "%s: knight stands on the lower landing (%s)" % [label, knight])
	var rel := knight.size.y / bounds.size.y
	check(rel > 0.12 and rel < 0.26, "%s: knight reads small against the shaft (%.2f of height)" % [label, rel])
	var title: Control = ui._panels["title"]
	var dialog: Control = title.get_meta("dialog")
	check(not dialog.get_global_rect().intersects(knight), "%s: menu column never covers the knight" % label)
	for node_name in ["start", "forge", "controls"]:
		var button := title.find_child(node_name, true, false) as Button
		check(button != null and not button.get_global_rect().intersects(knight), "%s: %s button clear of the knight" % [label, node_name])
	var wordmark := title.find_child("TitleStack", true, false) as Control
	check(wordmark != null and not wordmark.get_global_rect().intersects(knight), "%s: wordmark clear of the knight" % label)
	# Alignment: the wordmark and every entry sit on the canvas centre line, and
	# the entries share the wordmark's centre, so the group never reads off-centre.
	var centre_x := bounds.get_center().x
	var wm_centre := wordmark.get_global_rect().get_center().x
	check(absf(wm_centre - centre_x) <= 1.0, "%s: wordmark centred in the frame (centre %.1f vs %.1f)" % [label, wm_centre, centre_x])
	check(absf(dialog.get_global_rect().get_center().x - centre_x) <= 1.0, "%s: menu group centred in the frame (centre %.1f vs %.1f)" % [label, dialog.get_global_rect().get_center().x, centre_x])
	for node_name in ["start", "forge", "controls"]:
		var button := title.find_child(node_name, true, false) as Button
		var bc := button.get_global_rect().get_center().x
		check(absf(bc - wm_centre) <= 1.0, "%s: %s shares the wordmark centre (%.1f vs %.1f)" % [label, node_name, bc, wm_centre])
	# Lettering: every title label must fit its stack (a bare Control never grows
	# to its children, so an overflowing label slides its centred text right) and
	# the text run itself must be centred on the BEGIN entry.
	var begin_centre := (title.find_child("start", true, false) as Control).get_global_rect().get_center().x
	for child in wordmark.get_children():
		var text_label := child as Label
		if text_label == null:
			continue
		var lr := text_label.get_global_rect()
		check(lr.size.x <= wordmark.get_global_rect().size.x + 1.0, "%s: title label fits its stack (%.0f in %.0f)" % [label, lr.size.x, wordmark.get_global_rect().size.x])
		var font := text_label.get_theme_font("font")
		var run_w := font.get_string_size(text_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_label.get_theme_font_size("font_size")).x
		var run_centre := lr.position.x + (lr.size.x - run_w) * 0.5 + run_w * 0.5
		check(absf(run_centre - begin_centre) <= 1.0, "%s: title text run centred on BEGIN (%.1f vs %.1f)" % [label, run_centre, begin_centre])
		check(font.get_font_name().begins_with("Noto Serif Display"), "%s: wordmark uses the bundled display serif (got %s)" % [label, font.get_font_name()])


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("OPENING_SCENE requires a real display")
		quit(2)
		return
	Save.path = "user://opening_scene_contract.json"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	await _set_viewport(Vector2i(1280, 720))
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await _frames(6)
	ui = game.ui
	ui.start_requested.connect(func(): starts += 1)
	check(game.state == Game.GState.TITLE, "boots to the title")
	var title: Control = ui._panels["title"]

	# --- Purpose-built scene, menu-specific script, old vista retired ---
	var tableau := _tableau()
	check(tableau != null, "purpose-built TitleTableau lives under the title screen")
	if tableau == null:
		print("OPENING_SCENE_RESULT: FAIL (%d checks, %d failures)" % [checks, failures])
		quit(1)
		return
	var script := tableau.get_script() as Script
	check(script != null and script.resource_path == "res://scripts/title_tableau.gd", "tableau is the menu-specific title_tableau.gd")
	for layer in ["Depth", "Glow", "Knight", "Fog", "Embers"]:
		check(tableau.get_node_or_null(layer) != null, "tableau has a %s layer" % layer)
	check(title.find_child("Battlements", true, false) == null and title.find_child("FurnaceGlow", true, false) == null, "old battlement vista retired")
	check(_find_type(tableau, "CharacterBody2D") == null and _find_type(ui, "CharacterBody2D") == null, "tableau knight is menu art, not a gameplay actor")
	var count_before := _count(title)

	# --- Native framing at the presented size ---
	await _check_framing("1280x720")

	# --- Arrival reveal never blocks input ---
	ui.hide_all_panels()
	ui.show_panel("title")
	await _frames(2)
	check(tableau.is_visible_in_tree(), "tableau visible with the title")
	check(tableau.reveal > 0.0 and tableau.reveal < 1.0, "title arrival starts a reveal (reveal=%.2f)" % tableau.reveal)
	check(_focus_name() == "start", "BEGIN focused during the reveal (got %s)" % _focus_name())
	await _key(KEY_ENTER)
	await _frames(4)
	check(starts == 1 and game.state == Game.GState.PLAYING, "Enter during the reveal starts a run immediately")

	# --- Title-only lifetime and untouched gameplay actor ---
	check(not tableau.is_visible_in_tree(), "tableau hidden once the run starts")
	var clock_a: float = tableau.time
	await _frames(6)
	check(is_equal_approx(clock_a, tableau.time), "tableau clock stops while hidden")
	check(is_instance_valid(game.player) and game.player is Player, "run spawns the real Player")
	var player_script := game.player.get_script() as Script
	check(player_script != null and player_script.resource_path == "res://scripts/player.gd", "gameplay actor is scripts/player.gd")
	check(is_equal_approx(Content.P_BODY_W, 26.0) and is_equal_approx(Content.P_BODY_H, 54.0), "gameplay body proportions unchanged")
	check(not tableau.is_ancestor_of(game.player), "the tableau never owns the gameplay actor")

	# --- Repeated title return leaks nothing ---
	for i in range(3):
		ui.quit_to_title_requested.emit()
		await _frames(4)
		check(game.state == Game.GState.TITLE and tableau.is_visible_in_tree(), "return %d: title shows the tableau again" % i)
		ui.forge_requested.emit()
		await _frames(2)
		check(not tableau.is_visible_in_tree(), "return %d: forge hides the tableau" % i)
		ui.back_from_forge_requested.emit()
		await _frames(2)
	check(_count(title) == count_before, "repeated title return leaks no nodes (%d -> %d)" % [count_before, _count(title)])
	var tableaus := 0
	for child in title.get_children():
		if child.name == "TitleTableau":
			tableaus += 1
	check(tableaus == 1, "exactly one tableau after repeated returns (got %d)" % tableaus)
	check(_tableau() == tableau, "same tableau instance survives the returns")

	# --- Reduced motion is static ---
	ui._reduced_motion_check.button_pressed = true
	await _frames(3)
	check(Feedback.motion_reduced, "reduced motion option reaches Feedback")
	ui.hide_all_panels()
	ui.show_panel("title")
	await _frames(2)
	check(tableau.reveal >= 1.0, "reduced motion skips the reveal")
	var sig_a: Array = tableau.motion_signature()
	await _frames(6)
	var sig_b: Array = tableau.motion_signature()
	check(sig_a == sig_b, "reduced motion freezes the tableau (%s vs %s)" % [sig_a, sig_b])
	var embers := tableau.get_node_or_null("Embers") as CPUParticles2D
	check(embers != null and not embers.visible, "reduced motion hides the embers")
	ui._reduced_motion_check.button_pressed = false
	await _frames(6)
	check(tableau.motion_signature() != sig_b, "motion resumes when the option is cleared")
	check(embers != null and embers.visible, "embers return with motion")

	# --- Framing holds at a smaller presented size ---
	await _set_viewport(Vector2i(960, 540))
	await _check_framing("960x540")
	await _set_viewport(Vector2i(1280, 720))
	await _frames(60)

	# --- Real rendered frame: warm knight flame in a dark, non-uniform scene ---
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == Vector2i(1280, 720), "real frame is 1280x720 (got %s)" % image.get_size())
	var flame: Vector2 = root.get_final_transform() * tableau.knight_flame_point()
	var warm := image.get_pixel(int(flame.x), int(flame.y))
	check(warm.r > warm.b + 0.2, "knight flame renders warm at %s (got %s)" % [flame, warm])
	# Rendered glyph ink: the warm title lettering's horizontal extent is centred
	# on the BEGIN entry, measured on the real frame rather than on containers.
	var wm_rect: Rect2 = (title.find_child("TitleStack", true, false) as Control).get_global_rect()
	var begin_rect: Rect2 = (title.find_child("start", true, false) as Control).get_global_rect()
	var ink_min := INF
	var ink_max := -INF
	for x in range(0, 1280):
		for y in range(int(wm_rect.position.y) + 6, int(wm_rect.end.y) - 6, 2):
			var px := root.get_final_transform() * Vector2(x, y)
			var c := image.get_pixel(int(px.x), int(px.y))
			if c.r > 0.75 and c.g > 0.35 and c.b < 0.35:
				ink_min = minf(ink_min, float(x))
				ink_max = maxf(ink_max, float(x))
				break
	var ink_centre := (ink_min + ink_max) * 0.5
	check(ink_max > ink_min and absf(ink_centre - begin_rect.get_center().x) <= 3.0, "title glyph ink centred on BEGIN (ink %.0f..%.0f centre %.1f vs %.1f)" % [ink_min, ink_max, ink_centre, begin_rect.get_center().x])
	var corner := image.get_pixel(24, 24)
	check(_luma(corner) < 0.2, "top-left vault stays dark (got %s)" % corner)
	var total := 0.0
	var samples := 0
	var lit := 0
	for y in range(0, 720, 8):
		for x in range(0, 1280, 8):
			var l := _luma(image.get_pixel(x, y))
			total += l
			samples += 1
			if l > 0.08:
				lit += 1
	var mean := total / float(samples)
	check(mean > 0.03 and mean < 0.35, "scene is moody, not black or washed (mean luma %.3f)" % mean)
	check(lit > samples / 12 and lit < samples * 3 / 4, "scene has lit structure and deep shadow (%d/%d lit)" % [lit, samples])

	print("OPENING_SCENE_RESULT: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
