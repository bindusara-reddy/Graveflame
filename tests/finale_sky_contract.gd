extends "res://tests/harness.gd"
## The finale sky's contract with the ending's director: its API, a fresh burn
## material per finale that honours reduced motion and flash, fallen flames that
## count down and settle as stars round the moon, `reveal` and `dawn` lighting
## the sky without repainting what is painted once, an idle sky that never
## repaints, and reduced motion snapping flames to their stars.
## Run: godot4 --headless --path . --script res://tests/finale_sky_contract.gd --audio-driver Dummy

var draws := {}


func run() -> void:
	var motion := Feedback.motion_reduced
	var flash := Feedback.flash_reduced
	Feedback.motion_reduced = false
	Feedback.flash_reduced = false
	_test_burn_material()
	var sky := FinaleSky.new()
	sky.autostep = false
	root.add_child(sky)
	_test_api(sky)
	for key in ["well", "stars", "moon", "spill", "risers", "new_body"]:
		_watch(sky.get("_" + key) if key != "stars" else sky._stars[7], key)
	await ticks(3)
	_reset_draws()
	await ticks(10)
	check(_total_draws() == 0, "an idle sky never repaints (%d draws)" % _total_draws())
	await _test_light(sky)
	await _test_risers(sky)
	await _test_reduced_motion(sky)
	Feedback.motion_reduced = motion
	Feedback.flash_reduced = flash
	sky.queue_free()
	await finish("FINALE_SKY")


func _test_burn_material() -> void:
	var a := FinaleSky.burn_away_material()
	var b := FinaleSky.burn_away_material()
	check(a != b, "every finale gets its own burn material")
	var uniforms := a.shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u.name)
	for name in ["progress", "origin", "aspect", "travel", "rim_gain"]:
		check(uniforms.has(name), "the burn takes a '%s' uniform" % name)
	check(a.get_shader_parameter("travel") == 1.0 and a.get_shader_parameter("rim_gain") == 1.0, "the burn travels with a full ember rim by default")
	Feedback.motion_reduced = true
	Feedback.flash_reduced = true
	var still := FinaleSky.burn_away_material()
	check(still.get_shader_parameter("travel") == 0.0 and still.get_shader_parameter("rim_gain") == 0.7, "reduced motion and flash give a still, dimmer dissolve")
	Feedback.motion_reduced = false
	Feedback.flash_reduced = false


func _test_api(sky: FinaleSky) -> void:
	for method in ["add_rising", "rising_left", "well_top"]:
		check(sky.has_method(method), "the sky offers %s()" % method)
	for prop in ["reveal", "dawn", "moon_glow"]:
		check(prop in sky, "the sky has a '%s' property" % prop)
	check(sky.well_top().y < FinaleSky.RIM_Y, "the camera tilts up to above the well's rim")
	check(sky.rising_left() == 0 and not sky.is_processing(), "a new sky has nothing climbing and does not process")


func _test_light(sky: FinaleSky) -> void:
	sky.reveal = 1.0
	sky.moon_glow = 1.5
	await ticks(2)
	check(sky._stars[7].modulate.a > 0.99 and sky._moon.modulate.a > 0.99, "the whole night is out at reveal 1")
	check(draws.well == 0 and draws.stars == 0 and draws.moon == 0, "the night comes out by modulation, repainting nothing")
	_reset_draws()
	sky.dawn = 0.5
	await ticks(2)
	check(draws.spill == 1, "the dawn repaints its leading edge once per change")
	check(draws.well == 0 and draws.stars == 0, "and nothing else repaints")
	check(sky._stars[7].modulate.a < 0.51, "the dawn washes the stars out")
	sky.dawn = 0.0
	sky.moon_glow = 1.0


func _test_risers(sky: FinaleSky) -> void:
	for i in range(3):
		sky.add_rising(Vector2(420.0 + 80.0 * float(i), Content.FLOOR_Y - 40.0), 0.5 * float(i))
	check(sky.rising_left() == 3 and sky.is_processing(), "three flames wait to climb")
	await ticks(2)
	_reset_draws()
	sky.advance(1.0)
	await ticks(1)
	check(sky.rising_left() == 3 and draws.risers == 1, "climbing flames repaint as they rise (%d left)" % sky.rising_left())
	var counts: Array[int] = []
	for step in range(200):
		sky.advance(0.1)
		counts.append(sky.rising_left())
	check(counts.back() == 0 and counts.has(2) and counts.has(1), "the flames settle one by one, counting down to none")
	check(sky._new_stars.size() == 3, "each settled flame is a star")
	var apart := true
	for s in sky._new_stars:
		apart = apart and (s.p as Vector2).distance_to(FinaleSky.MOON) < 250.0
	check(apart, "the new stars ring the moon")
	await ticks(2)
	check(not sky.is_processing(), "the sky stops processing once every star has settled")
	_reset_draws()
	await ticks(10)
	check(_total_draws() == 0, "a settled sky is idle again (%d draws)" % _total_draws())


## Reduced motion: nothing travels. A flame waits out its delay, then its star
## is simply there, with no climb drawn and no pop.
func _test_reduced_motion(sky: FinaleSky) -> void:
	Feedback.motion_reduced = true
	var before := sky._new_stars.size()
	sky.add_rising(Vector2(640.0, Content.FLOOR_Y - 40.0), 0.3)
	_reset_draws()
	sky.advance(0.2)
	await ticks(2)
	check(sky.rising_left() == 1 and draws.risers == 0, "under reduced motion a waiting flame draws nothing")
	sky.advance(0.2)
	await ticks(2)
	check(sky.rising_left() == 0 and sky._new_stars.size() == before + 1, "then snaps straight to its star")
	check(draws.risers == 0 and float(sky._new_stars.back().age) == FinaleSky.SETTLE_TIME, "without climbing or popping in")
	Feedback.motion_reduced = false


func _watch(node: CanvasItem, key: String) -> void:
	draws[key] = 0
	node.draw.connect(func(): draws[key] += 1)


func _reset_draws() -> void:
	for key in draws:
		draws[key] = 0


func _total_draws() -> int:
	var total := 0
	for key in draws:
		total += draws[key]
	return total
