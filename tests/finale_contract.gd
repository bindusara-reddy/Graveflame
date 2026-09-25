extends "res://tests/harness.gd"
## The ending ("Strike the Set"): one victory per kill and none for a trade,
## the save ledger, every cut reaching the results with no input, the gather
## that plays the question, skipping, reduced motion, layer sync and abort from
## every phase. Runs the real game on a scratch save and drives the director's
## clock itself, so its timings do not depend on frame rate.
## Run: godot4 --headless --path . --script res://tests/finale_contract.gd --audio-driver Dummy

const DT := 1.0 / 60.0


func run() -> void:
	await process_frame
	use_scratch_save("finale_contract")
	_test_save_ledger()
	_test_stations()
	await _test_reentry()
	await _test_trade()
	for cut in [["full", 0, 60.0], ["abridged", 1, 38.0], ["brief", 3, 20.0]]:
		await _test_zero_input(cut[0], cut[1], cut[2])
	await _test_gather()
	await _test_skip()
	await _test_abort_every_phase()
	await _test_reduced_motion()
	await _test_layer_sync()
	release(["ignite", "pause", "ui_accept", "jump"])
	await finish("FINALE_CONTRACT")


## Starts the scratch save as `data` (empty = a brand-new player).
func _seed_save(data: Dictionary) -> void:
	var f := FileAccess.open(Save.path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	# Save caches the parsed file; re-pointing the path drops that cache.
	Save.path = Save.path


## A fresh game on `save`, already in the throne room with the Warden up.
func _at_throne(save: Dictionary) -> void:
	release(["ignite", "pause", "ui_accept", "jump"])
	await free_game()
	await _settle_time()
	_seed_save(save)
	await load_main_scene(1)
	game._begin_run()
	await _enter_throne()


func _enter_throne() -> void:
	game.run.room_index = game.run.rooms_total() - 2
	game._advance_room()
	for i in range(3):
		await physics_frame


## The killing blow's hit-stop runs in real time; wait (at most 1 s) for it to
## end, so a time-scale check sees what the ending left behind, not the blow.
func _settle_time() -> void:
	for i in range(50):
		if Engine.time_scale == 1.0:
			return
		await create_timer(0.02, true, false, true).timeout


## Kills the Warden and takes the director's clock over from the frame loop.
func _kill_warden() -> Finale:
	game.room.boss.take_damage(99999.0, Vector2.RIGHT, 0.0)
	var fin := game.finale
	if fin != null:
		fin.autostep = false
	return fin


## One frame of the ending: the game's slow-motion beat (while it lasts) and
## the director, both advanced by 1/60 s of real time.
func _step(fin: Finale) -> void:
	if not game._beat_kind.is_empty():
		game._step_beat(Engine.time_scale * DT)
	fin.step(DT)


func _step_for(fin: Finale, seconds: float) -> void:
	for i in range(roundi(seconds / DT)):
		_step(fin)


## Steps until the director reaches `phase`; false if it never does.
func _step_to(fin: Finale, phase: Finale.Phase, limit := 70.0) -> bool:
	var t := 0.0
	while fin.phase != phase and t < limit:
		_step(fin)
		t += DT
	return fin.phase == phase


# --- Pure checks --------------------------------------------------------------

## T10: migration, falls and the single victory write.
func _test_save_ledger() -> void:
	_seed_save({})
	Save.migrate_falls()
	check(Save.get_falls() == 0 and not Save.falls_legacy(), "a fresh save migrates as a clean count")
	_seed_save({ "cells": 12, "victories": 2 })
	Save.migrate_falls()
	check(Save.falls_legacy() and Save.get_roll() == [0, 0], "an old save with progress is marked legacy, its wins padded into the roll")
	Save.record_fall("The descent is patient.")
	Save.migrate_falls()
	check(Save.get_falls() == 1 and Save.falls_legacy(), "migration is idempotent and a fall counts once")
	var rec := Save.record_victory(["v_embers"])
	check(bool(rec.unknown) and int(rec.falls_since) == 1, "a legacy save's first counted win has an unknown crowd")
	check(str(rec.last_epitaph) == "The descent is patient." and str(Save.load_save().last_epitaph).is_empty(), "the win answers the last epitaph, then clears it")
	check(Save.get_roll() == [0, 0, 1] and Save.get_victories() == 3 and not Save.oath_kept(), "the win joins the roll")
	Save.record_fall("x")
	Save.record_fall("y")
	rec = Save.record_victory(["v_embers", "v_thirst", "v_gilded", "v_haste", "v_pyre"])
	check(not bool(rec.unknown) and int(rec.falls_since) == 2, "later wins count the falls since the last one")
	check(Save.oath_kept() and str(rec.milestone) == "oath" and bool(rec.oath_first), "five vows keep the Fivefold Oath")
	check(int(rec.finale_seen) == 1 and Save.get_finale_seen() == 2, "finale_seen reports the viewings before this one")


## Stations stay off the rostrum and out of the knight's way.
func _test_stations() -> void:
	var places := Finale.stations(596.0)
	check(places.size() >= Content.FALLEN_CAP, "there is a station for every fallen")
	check(places.all(func(p): return absf(float(p.x) - 640.0) >= 200.0 and absf(float(p.x) - 596.0) >= 36.0), "no station is on the rostrum or on the knight")


# --- Runtime checks ------------------------------------------------------------

## T1: the throne room re-emits completed as late adds die; one win only.
func _test_reentry() -> void:
	await _at_throne({})
	for x in [300.0, 1000.0]:
		game.room._on_boss_summon(Enemy.Kind.WISP, Vector2(x, 400.0))
	var cells := Save.get_cells()
	var fin := _kill_warden()
	var finales := game.get_children().filter(func(n): return n is Finale)
	check(finales.size() == 1, "one kill makes exactly one finale (%d)" % finales.size())
	check(Save.get_victories() == 1 and Save.get_finale_seen() == 1, "one kill records one victory (%d, %d)" % [Save.get_victories(), Save.get_finale_seen()])
	check(Save.get_cells() - cells == 30, "the throne pays its cells once (%d)" % (Save.get_cells() - cells))
	check(game.player.cinematic and fin.phase == Finale.Phase.PROLOGUE, "the knight is untouchable while the beat plays")


## T2: a knight that falls before the Warden has traded: the run is lost.
func _test_trade() -> void:
	await _at_throne({})
	game.player.iframes = 0.0
	game.player.take_damage(99999.0, Vector2.RIGHT, 0.0)
	game.room.boss.take_damage(99999.0, Vector2.RIGHT, 0.0)
	check(game.state == Game.GState.GAME_OVER and game.finale == null, "a trade is a loss")
	check(Save.get_victories() == 0 and Save.get_falls() == 1, "a trade records a fall, not a win (%d, %d)" % [Save.get_victories(), Save.get_falls()])


## T3: with no input at all, every cut reaches the results panel in time.
func _test_zero_input(cut: String, seen: int, limit: float) -> void:
	await _at_throne({ "victories": seen, "finale_seen": seen, "falls": 3, "falls_banked": 0 })
	var fin := _kill_warden()
	check(fin.tier == cut, "%s: the save picks the %s cut (%s)" % [cut, cut, fin.tier])
	var endings := [0]
	fin.finished.connect(func(_skipped: bool): endings[0] += 1)
	var t := 0.0
	var reached := {}
	while endings[0] == 0 and t < limit:
		_step(fin)
		reached[fin.phase_name()] = true
		t += DT
	_step_for(fin, 1.0)
	check(endings[0] == 1, "%s: finished once within %.0f s (took %.1f s)" % [cut, limit, t])
	check(reached.has("STRIKE") and reached.has("CALL") and reached.has("EMBER"), "%s: every act plays (%s)" % [cut, reached.keys()])
	check((game.ui._panels["victory"] as Control).visible and paused, "%s: the results open over a paused world" % cut)
	check(game.music._current == "title", "%s: the title theme returns" % cut)
	await _settle_time()
	check(Engine.time_scale == 1.0, "%s: real time runs at the panel" % cut)


## T4: holding plays the question; a release pauses it; a tap rings one note;
## letting go after the C# is LET GO, in the same frame.
func _test_gather() -> void:
	await _at_throne({})
	var fin := _kill_warden()
	check(_step_to(fin, Finale.Phase.PROMPT), "the knight reaches the prompt")
	var fb := game.feedback
	var bell := AudioStreamWAV.new()
	bell.data = PackedByteArray([0, 0, 0, 0])
	fb._streams["grave_bell"] = bell
	fb._takes["grave_bell"] = [bell]
	var pitches: Array = []
	Input.action_press("ignite")
	while fin._note < 3:
		_step(fin)
		pitches.append_array(_rung(bell))
	Input.action_release("ignite")
	_step(fin)
	var frozen := fin._gather_t
	_step_for(fin, 1.0)
	check(fin._gather_t == frozen and fin.phase == Finale.Phase.GATHER, "releasing pauses the gather and loses nothing")
	Input.action_press("ignite")
	_step_for(fin, 0.05)
	Input.action_release("ignite")
	_step_for(fin, 0.5)
	pitches.append_array(_rung(bell))
	check(fin._note == 4, "a tap rings exactly one more note (%d)" % fin._note)
	Input.action_press("ignite")
	while fin.phase == Finale.Phase.GATHER:
		_step(fin)
		pitches.append_array(_rung(bell))
	check(pitches.size() == Content.GATHER_LINE.size(), "the question is seven notes (%d)" % pitches.size())
	var exact := pitches.size() == Content.GATHER_LINE.size()
	for i in range(mini(pitches.size(), Content.GATHER_LINE.size())):
		exact = exact and is_equal_approx(pitches[i], pow(2.0, (float(Content.GATHER_LINE[i][1]) - 74.0) / 12.0))
	check(exact, "each note is in tune, never humanised")
	check(fin.phase == Finale.Phase.LETGO, "after the C# the prompt says LET GO")
	Input.action_release("ignite")
	fin.step(DT)
	check(fin.phase == Finale.Phase.STRIKE, "letting go strikes in the same frame")


## Pitches of the bells rung since the last call (each voice is read once).
func _rung(bell: AudioStream) -> Array:
	var out: Array = []
	for voice in game.feedback._audio_pool:
		if voice.stream == bell:
			out.append(voice.pitch_scale)
			voice.stream = null
	return out


## T6: the skip hold, first viewing and repeat, and from the slow-motion beat.
func _test_skip() -> void:
	await _at_throne({})
	var fin := _kill_warden()
	var skipped := [false]
	fin.finished.connect(func(s: bool): skipped[0] = s)
	_step_to(fin, Finale.Phase.HOARD)
	Input.action_press("pause")
	_step_for(fin, 1.9)
	check(not fin._skipping, "a first viewing does not skip on 1.9 s of pause")
	_step_for(fin, 0.2)
	check(fin._skipping, "a first viewing skips on a 2 s hold")
	_step_to(fin, Finale.Phase.DONE, 3.0)
	check(skipped[0] and (game.ui._panels["victory"] as Control).visible, "the skip ends at the panel, flagged as skipped")
	if game.ui.has_method("lock_until_released"):
		game.ui._process(DT)
		var again: Button = game.ui._panels["victory"].find_child("again", true, false)
		check(again.disabled, "with pause still held the results cannot be pressed")
		Input.action_release("pause")
		game.ui._process(DT)
		# The first control grabs focus deferred, on the next frame.
		await process_frame
		check(not again.disabled and again.has_focus(), "released, NEW RUN takes focus")
	await _at_throne({ "victories": 1, "finale_seen": 1 })
	fin = _kill_warden()
	_step_to(fin, Finale.Phase.HOARD)
	Input.action_press("pause")
	_step_for(fin, 1.05)
	check(fin._skipping, "a repeat viewing skips on a 1 s hold")
	Input.action_release("pause")
	await _at_throne({ "victories": 1, "finale_seen": 1 })
	fin = _kill_warden()
	Input.action_press("pause")
	for i in range(66):
		fin.step(DT)
	Input.action_release("pause")
	for i in range(30):
		fin.step(DT)
	check(fin._skipping and fin.phase == Finale.Phase.EMBER and game._beat_kind.is_empty(), "a skip during the slow-motion beat ends the beat")
	await _settle_time()
	check(Engine.time_scale == 1.0, "a skip during the beat restores real time")


## T7: leaving from any phase, by RETURN TO TITLE or NEW RUN, puts back
## everything the ending borrowed.
func _test_abort_every_phase() -> void:
	await _at_throne({})
	for leave in ["title", "new_run"]:
		for phase in Finale.Phase.values():
			_seed_save({})
			if leave == "title" or phase == 0:
				game._begin_run()
			await _enter_throne()
			var fin := _kill_warden()
			var name: String = Finale.Phase.keys()[phase]
			check(_step_to(fin, phase), "%s: the ending reaches %s" % [leave, name])
			if leave == "title":
				game._on_quit_to_title()
			else:
				game._begin_run()
			await process_frame
			await _settle_time()
			var box := game._world_container
			var layers := game.find_children("*", "CanvasLayer", true, false).filter(func(l): return [-1, 10, 11, 45].has(l.layer))
			# The title hides the world by itself; a new run shows it, unburned.
			var restored := not is_instance_valid(fin) and game.finale == null and box.material == null and box.position == Vector2.ZERO
			restored = restored and box.visible == (leave == "new_run")
			restored = restored and game.feedback.camera.zoom.is_equal_approx(Vector2.ONE * Content.CAM_ZOOM)
			restored = restored and game.feedback.camera.offset == Vector2.ZERO and Engine.time_scale == 1.0 and layers.is_empty() and game.sconce_heat == 1.0
			check(restored, "%s from %s restores the world" % [leave, name])


## T8: reduced motion holds three framings, sheds no ash, burns in place and
## never slows time.
func _test_reduced_motion() -> void:
	await _at_throne({})
	game.feedback.set_reduced_motion(true)
	var fin := _kill_warden()
	var zooms := {}
	var slowed := false
	var flakes := 0
	var travel := -1.0
	while fin.phase != Finale.Phase.DONE and fin.clock < 70.0:
		_step(fin)
		slowed = slowed or Engine.time_scale < 1.0
		if fin._owns_camera:
			zooms[snappedf(game.feedback.camera.zoom.x, 0.0001)] = true
		if is_instance_valid(fin._ash):
			flakes = maxi(flakes, fin._ash.count())
		if game._world_container.material is ShaderMaterial:
			travel = float((game._world_container.material as ShaderMaterial).get_shader_parameter("travel"))
	check(fin.phase == Finale.Phase.DONE, "reduced motion still reaches the results")
	check(zooms.size() <= 3, "reduced motion holds at most three framings (%s)" % [zooms.keys()])
	check(flakes == 0 and travel == 0.0, "reduced motion sheds no ash and burns without a travelling edge")
	check(not slowed, "reduced motion never slows time")
	game.feedback.set_reduced_motion(false)


## T9: through the shaking burn and the curtain call, every theatre layer holds
## the world camera's exact canvas transform, frame by frame.
func _test_layer_sync() -> void:
	await _at_throne({})
	var fin := _kill_warden()
	var synced := true
	var frames := 0
	for phase in [Finale.Phase.BURN, Finale.Phase.CALL]:
		_step_to(fin, phase)
		fin.autostep = true
		game.feedback.shake(8.0, 3.0)
		for i in range(90):
			await process_frame
			var view := game.world_view.canvas_transform
			var layer := fin._actor_layer.transform
			synced = synced and layer.origin.distance_to(view.origin) < 0.01 and layer.x.distance_to(view.x) < 0.01
			frames += 1
		fin.autostep = false
	check(synced and frames == 180, "the actor layer follows the shaking camera exactly")
