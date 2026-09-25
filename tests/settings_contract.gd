extends "res://tests/harness.gd"
## Settings contracts. Two things here failed silently before and would do so
## again: a toggle whose icon reserved layout space but never painted (no error,
## just an invisible control), and a volume that was stored but never reached the
## audio bus. Both are pinned behaviourally rather than structurally.
var _vp: SubViewport

func boot() -> void:
	_vp = make_capture_viewport()
	await load_main_scene(12, _vp)

func teardown() -> void:
	await free_game()
	if is_instance_valid(_vp):
		_vp.queue_free()
	await ticks(4)

## Mean luminance over a rectangle of the rendered frame.
func sample(x0: int, y0: int, w: int, h: int) -> float:
	var img := _vp.get_texture().get_image()
	var total := 0.0
	var samples := 0
	for dx in range(0, w):
		for dy in range(0, h):
			var x := x0 + dx
			var y := y0 + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			total += img.get_pixel(x, y).get_luminance()
			samples += 1
	if samples == 0:
		return 0.0
	return total / float(samples)

func run() -> void:
	use_scratch_save("settings_contract")
	await boot()

	check(AudioServer.get_bus_index("Music") >= 0, "a Music bus exists for the score")
	check(AudioServer.get_bus_index("SFX") >= 0, "an SFX bus exists for gameplay cues")

	game.ui.options_requested.emit()
	await ticks(6)
	check((game.ui._panels["options"] as Control).visible, "OPTIONS opens")
	check(game.ui._option_sliders.has("master") and game.ui._option_sliders.has("music") and game.ui._option_sliders.has("sfx"), "the mix exposes master, music and effects")

	# --- A toggle must visibly paint BOTH states ---
	# The off state is the one that regressed silently before: the theme's
	# unchecked icon matched the panel's own luminance, so an OFF toggle was
	# invisible. Measure against the dialog's padding, not a constant, so this
	# stays honest if the palette changes.
	# These checks read real pixels, so they need a rendering device. Headless
	# runs skip them explicitly rather than failing or quietly passing.
	var box: CheckBox = game.ui._reduced_motion_check
	if DisplayServer.get_name() == "headless":
		print("NOTE: no render device; skipped the toggle-rendering checks")
	else:
		var rect: Rect2 = box.get_global_rect()
		var dialog: Rect2 = (game.ui._panels["options"] as Control).get_meta("dialog").get_global_rect()
		var cy := int(rect.position.y + rect.size.y * 0.5)
		var bx := int(rect.position.x)
		var background := sample(int(dialog.position.x) + 6, cy - 11, 26, 22)
		box.button_pressed = false
		await ticks(4)
		var off := sample(bx, cy - 11, 21, 22)
		box.button_pressed = true
		await ticks(4)
		var on := sample(bx, cy - 11, 21, 22)
		check(off > background + 0.03, "an unchecked toggle is visible against the panel (panel=%.3f off=%.3f)" % [background, off])
		check(on > off + 0.05, "a checked toggle reads differently from an unchecked one (off=%.3f on=%.3f)" % [off, on])

	# --- A volume must reach the bus, not just the save file ---
	var music_slider: HSlider = game.ui._option_sliders["music"]["slider"]
	var music_bus := AudioServer.get_bus_index("Music")
	music_slider.value = 0.0
	await ticks(3)
	check(AudioServer.get_bus_volume_db(music_bus) < -60.0, "the music slider silences the Music bus")
	check(is_zero_approx(float(Save.get_options()["music"])), "the music level is persisted")

	music_slider.value = 0.5
	await ticks(3)
	var db := AudioServer.get_bus_volume_db(music_bus)
	check(db > -20.0 and db < 0.0, "a half music slider is audible but attenuated (got %.1f dB)" % db)

	# --- A relaunch must honour the stored mix ---
	await teardown()
	await boot()
	var restored: HSlider = game.ui._option_sliders["music"]["slider"]
	check(is_equal_approx(restored.value, 0.5), "a relaunch restores the saved music level (got %.2f)" % restored.value)
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) < 0.0, "a relaunch reapplies the mix to the bus")

	await teardown()
	await finish("SETTINGS")
