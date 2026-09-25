extends "res://tests/harness.gd"
## The finale theatre's drawing contract: a fresh burn material per finale that
## honours reduced motion and flash, an idle theatre that never repaints, each
## animated var repainting only its own piece, a house lit by its footlights,
## and a playbill that fits its rows, settles its swing and inks rows in.
## Run: godot4 --headless --path . --script res://tests/finale_stage_contract.gd --audio-driver Dummy

var draws := {}


func run() -> void:
	var motion := Feedback.motion_reduced
	var flash := Feedback.flash_reduced
	Feedback.motion_reduced = false
	Feedback.flash_reduced = false
	_test_burn_material()
	var stage := FinaleStage.new()
	var front := FinaleStage.FinaleFront.new()
	var bill := FinaleStage.Playbill.new()
	var text := FinaleStage.PlaybillText.new(bill)
	for node in [stage, front, bill, text]:
		root.add_child(node)
	await _test_repaints(stage, front)
	await _test_house_light(front)
	_test_playbill(bill, text)
	Feedback.motion_reduced = motion
	Feedback.flash_reduced = flash
	for node in [stage, front, bill, text]:
		node.queue_free()
	await finish("FINALE_STAGE")


func _test_burn_material() -> void:
	var a := FinaleStage.burn_away_material()
	var b := FinaleStage.burn_away_material()
	check(a != b and a.shader != b.shader, "every finale gets its own burn material")
	check(a.get_shader_parameter("travel") == 1.0 and a.get_shader_parameter("rim_gain") == 1.0, "the burn travels with a full ember rim by default")
	Feedback.motion_reduced = true
	Feedback.flash_reduced = true
	var still := FinaleStage.burn_away_material()
	check(still.get_shader_parameter("travel") == 0.0 and still.get_shader_parameter("rim_gain") == 0.7, "reduced motion and flash give a still, dimmer dissolve")
	Feedback.motion_reduced = false
	Feedback.flash_reduced = false


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


func _test_repaints(stage: FinaleStage, front: FinaleStage.FinaleFront) -> void:
	_watch(stage._back, "back")
	_watch(stage._embers, "embers")
	_watch(stage._traveler, "traveler")
	_watch(front._frame, "frame")
	_watch(front._flames, "flames")
	_watch(front._lamps, "lamps")
	_watch(front._drop, "drop")
	_watch(front._house, "house")
	_watch(front._crowns, "crowns")
	await ticks(3)
	_reset_draws()
	await ticks(20)
	check(_total_draws() == 0, "an idle, unlit theatre never repaints (%d draws)" % _total_draws())

	stage.closed = 0.5
	front.main_drop = 0.5
	await ticks(2)
	check(draws.traveler == 1 and draws.drop == 1, "drawing the traveler repaints it; the great curtain paints once as it appears")
	check(draws.back == 0 and draws.frame == 0 and draws.lamps == 0, "and nothing else repaints")
	_reset_draws()
	front.main_drop = 1.0
	stage.remnant_heat = 0.4
	await ticks(2)
	check(draws.drop == 0 and front._drop.position.y == 0.0, "the great curtain falls by moving, not repainting")
	check(draws.embers == 0 and is_equal_approx(stage._embers.modulate.a, 0.4), "the remnants cool by fading their embers, not repainting")
	stage.closed = 1.0
	check(not stage._back.visible, "a closed traveler hides the back wall and its remnants")

	_reset_draws()
	front.lamps[4] = 1.0
	await ticks(10)
	check(draws.flames >= 9, "a lit footlight flickers every frame, even when set in place")
	check(draws.lamps == 1, "its tin repaints once, for the change")
	check(draws.frame == 0 and draws.back == 0 and draws.house == 0, "static geometry stays recorded while lamps burn")

	front.house_count = 23
	await ticks(2)
	_reset_draws()
	await ticks(10)
	check(draws.crowns >= 9 and draws.house == 0, "the audience's crowns flicker while the seats and patrons stay recorded")
	Feedback.motion_reduced = true
	await ticks(2)
	_reset_draws()
	await ticks(10)
	check(draws.flames == 0 and draws.crowns == 0, "reduced motion freezes every flicker")
	front.rise = 1.0
	await ticks(2)
	check(draws.house == 1 and draws.crowns == 1, "the house standing repaints it once under reduced motion")
	Feedback.motion_reduced = false


## The footlights are the house's only light: it comes up as they kindle and
## goes dark as they gutter, by modulation alone.
func _test_house_light(front: FinaleStage.FinaleFront) -> void:
	front.lamps.fill(1.0)
	await ticks(2)
	check(front._frame.modulate == Color.WHITE and front._drop.modulate == Color.WHITE, "every lamp lit shows the frame and the curtain in full")
	_reset_draws()
	front.lamps.fill(0.0)
	await ticks(2)
	var dark := front._frame.modulate.v
	check(dark <= 0.25 and front._house.modulate.v == dark, "with the lamps out the house goes dark (%.2f)" % dark)
	check(draws.frame == 0 and draws.drop == 0, "without repainting the frame or the curtain")


func _test_playbill(bill: FinaleStage.Playbill, text: FinaleStage.PlaybillText) -> void:
	bill.rows = ["THE FALLEN — 12 knights. Each of them was you.", {"sigils": ["vitality", "swift"]},
		"THE KNIGHT — Who carried their flames."]
	check(bill.row_lines == [1.0, FinaleStage.Playbill.SIGIL_LINES, 1.0], "a cast row takes one line, the boon sigils a little more")
	var lines := bill.row_lines[0] + bill.row_lines[1] + bill.row_lines[2]
	var expected := FinaleStage.Playbill.HEADER + FinaleStage.Playbill.FOOTER + FinaleStage.Playbill.LINE * lines
	check(is_equal_approx(bill.sheet.y, expected), "the sheet grows to hold its rows")
	var swing := 0.0
	for i in range(72):
		bill.drop = Tween.interpolate_value(0.0, 1.0, float(i + 1) / 60.0, 1.2, Tween.TRANS_BACK, Tween.EASE_OUT)
		bill._process(1.0 / 60.0)
		swing = maxf(swing, absf(bill.rotation))
	for i in range(600):
		bill._process(1.0 / 60.0)
		swing = maxf(swing, absf(bill.rotation))
	check(swing > 0.025 and swing <= FinaleStage.Playbill.SWING_MAX, "lowering the bill sets it swinging a degree or two (%.3f rad)" % swing)
	check(bill.rotation == 0.0 and not bill.is_processing(), "the swing dies away and the bill stops processing")
	bill.revealed = 1
	for i in range(12):
		text._process(1.0 / 60.0)
	check(text._row_alpha[0] > 0.0 and text._row_alpha[0] < 1.0 and text._row_alpha[1] == 0.0, "a revealed row inks in over time; the rest wait")
	for i in range(20):
		text._process(1.0 / 60.0)
	check(text._row_alpha[0] == 1.0, "and is fully inked within FADE")
	check(text.size.is_equal_approx(bill.screen_rect().size), "the type covers the sheet it is set on")
