extends SceneTree
## The finale theatre's drawing contract: a fresh burn material per finale that
## honours reduced motion and flash, an idle theatre that never repaints, each
## animated var repainting only its own piece, and a playbill that fits its rows,
## settles its swing and inks rows in.
var checks := 0
var failures := 0
var draws := {}

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func watch(node: CanvasItem, key: String) -> void:
	draws[key] = 0
	node.draw.connect(func(): draws[key] += 1)

func reset_draws() -> void:
	for key in draws:
		draws[key] = 0

func _run() -> void:
	var motion := Feedback.motion_reduced
	var flash := Feedback.flash_reduced
	Feedback.motion_reduced = false
	Feedback.flash_reduced = false
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

	var stage := FinaleStage.new()
	var front := FinaleStage.FinaleFront.new()
	var bill := FinaleStage.Playbill.new()
	var text := FinaleStage.PlaybillText.new(bill)
	for node in [stage, front, bill, text]:
		root.add_child(node)
	watch(stage._back, "back")
	watch(stage._traveler, "traveler")
	watch(front._frame, "frame")
	watch(front._live, "live")
	watch(front._drop, "drop")
	watch(front._house, "house")
	await frames(3)
	reset_draws()
	await frames(20)
	var idle := 0
	for key in draws:
		idle += draws[key]
	check(idle == 0, "an idle, unlit theatre never repaints (%d draws)" % idle)

	stage.closed = 0.5
	front.main_drop = 0.5
	await frames(2)
	check(draws.traveler == 1 and draws.drop == 1, "closing the curtains repaints the curtains")
	check(draws.back == 0 and draws.frame == 0 and draws.live == 0, "and nothing else")

	reset_draws()
	front.lamps[4] = 1.0
	await frames(10)
	check(draws.live >= 9, "a lit footlight flickers every frame, even when set in place")
	check(draws.frame == 0 and draws.back == 0, "static geometry stays recorded while lamps burn")
	Feedback.motion_reduced = true
	await frames(2)
	reset_draws()
	await frames(10)
	check(draws.live == 0 and draws.house == 0, "reduced motion freezes every flicker")
	front.house_count = 23
	front.rise = 1.0
	await frames(2)
	check(draws.house == 1, "filling the house repaints it once under reduced motion")
	Feedback.motion_reduced = false

	var cast := ["THE FALLEN — 12 knights. Each of them was you.", {"sigils": ["vitality", "swift"]},
		"MADE BY BINDU · Every shape cut in code. Every sound struck from nothing. Every flame kept."]
	bill.rows = cast
	check(bill.row_lines.size() == 3 and bill.row_lines[0] == 1.0 and bill.row_lines[2] >= 2.0, "a long credit wraps instead of shrinking under 14 px")
	var expected := FinaleStage.Playbill.HEADER + FinaleStage.Playbill.FOOTER + FinaleStage.Playbill.LINE * (bill.row_lines[0] + bill.row_lines[1] + bill.row_lines[2])
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

	Feedback.motion_reduced = motion
	Feedback.flash_reduced = flash
	for node in [stage, front, bill, text]:
		node.queue_free()
	await process_frame
	print("FINALE_STAGE_RESULT: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
