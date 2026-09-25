extends "res://tests/harness.gd"
## The ending ("The Warden's Crown"): one victory per kill and none for a trade,
## the save ledger and the ending it keeps, the choice that waits for the knight
## and is only ever made by a held, fresh press, every ending reaching the
## results with the right save writes in every cut, the gather, skipping,
## leaving from any phase, reduced motion, layer sync, and what the next
## descent remembers (the Warden's title and crown, the title tableau). Runs
## the real game on a scratch save and drives the director's clock itself, so
## its timings do not depend on frame rate.
## Run: godot4 --headless --path . --script res://tests/finale_contract.gd --audio-driver Dummy

const DT := 1.0 / 60.0
const Cast := preload("res://scripts/finale_actors.gd")
const ALL_VOWS := ["v_embers", "v_thirst", "v_gilded", "v_haste", "v_pyre"]
const KEYS := ["ignite", "pause", "ui_accept", "jump", "attack", "interact", "move_left", "move_right", "ui_left", "ui_right"]


func run() -> void:
	await process_frame
	use_scratch_save("finale_contract")
	_test_save_ledger()
	_test_stations()
	await _test_reentry()
	await _test_trade()
	await _test_choice_waits()
	await _test_choice_input()
	for ending in ["crown", "given", "ended"]:
		for cut in [["full", 0, 90.0], ["abridged", 1, 60.0], ["brief", 3, 45.0]]:
			await _test_ending(ending, cut[0], cut[1], cut[2])
	await _test_gather()
	await _test_skip()
	await _test_abort_every_phase()
	await _test_reduced_motion()
	await _test_layer_sync()
	await _test_remembered()
	await _test_title_states()
	release(KEYS)
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
	release(KEYS)
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


## One frame of the ending: the game's slow-motion beat (while it lasts), the
## Warden's own death (it splits open at its shatter) and the director, each
## advanced by 1/60 s of real time.
func _step(fin: Finale) -> void:
	if not game._beat_kind.is_empty():
		game._step_beat(Engine.time_scale * DT)
	var boss = game.room.boss if is_instance_valid(game.room) else null
	if is_instance_valid(boss) and boss.dead and not boss._shattered:
		boss._step_death(Engine.time_scale * DT)
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


## Kills the Warden and steps to the choice.
func _to_choice(save: Dictionary) -> Finale:
	await _at_throne(save)
	var fin := _kill_warden()
	check(_step_to(fin, Finale.Phase.CHOICE), "the ending comes to the choice (%s)" % fin.phase_name())
	return fin


# --- Pure checks --------------------------------------------------------------

## Migration, falls, the single victory write and the ending kept.
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
	check(not bool(rec.unknown) and int(rec.falls_total) == 1, "a legacy save counts the falls it has seen")
	check(str(rec.last_epitaph) == "The descent is patient." and str(Save.load_save().last_epitaph).is_empty(), "the win answers the last epitaph, then clears it")
	check(Save.get_roll() == [0, 0, 1] and Save.get_victories() == 3 and not Save.oath_kept(), "the win joins the roll")
	check(str(rec.last_ending) == "" and Save.get_last_ending() == "" and Save.get_endings_seen().is_empty() and not Save.ended_ever(), "an old save has no ending yet")
	Save.set_last_ending("crown")
	Save.set_last_ending("given")
	Save.set_last_ending("given")
	Save.set_last_ending("curtain")
	check(Save.get_last_ending() == "given" and Save.get_endings_seen() == ["crown", "given"] and not Save.ended_ever(), "each ending is kept once, the last one remembered, a stray one ignored")
	Save.record_fall("x")
	Save.record_fall("y")
	rec = Save.record_victory(ALL_VOWS)
	check(not bool(rec.unknown) and int(rec.falls_total) == 3, "every win counts every knight ever lost, not just the latest")
	check(Save.oath_kept() and str(rec.milestone) == "oath" and bool(rec.oath_first), "five vows keep the Fivefold Oath")
	check(int(rec.finale_seen) == 1 and Save.get_finale_seen() == 2 and str(rec.last_ending) == "given", "the win reports the viewings and the ending before it")
	Save.set_last_ending("ended")
	Save.set_last_ending("crown")
	check(Save.ended_ever() and Save.get_last_ending() == "crown", "once the keep is put out, that stays")
	_seed_save({ "last_ending": "throne", "ended_ever": false })
	check(Save.get_last_ending() == "", "a hand-edited ending reads as none")


## Stations stay clear of the throne and the space before it.
func _test_stations() -> void:
	var places := Finale.stations()
	check(places.size() >= Content.FALLEN_CAP, "there is a station for every fallen")
	check(places.all(func(p): return absf(float(p.x) - 640.0) >= 236.0), "no station is on the dais or where the knight stands")


# --- Runtime checks ------------------------------------------------------------

## The throne room re-emits completed as late adds die; one win only.
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


## A knight that falls before the Warden has traded: the run is lost.
func _test_trade() -> void:
	await _at_throne({})
	game.player.iframes = 0.0
	game.player.take_damage(99999.0, Vector2.RIGHT, 0.0)
	game.room.boss.take_damage(99999.0, Vector2.RIGHT, 0.0)
	check(game.state == Game.GState.GAME_OVER and game.finale == null, "a trade is a loss")
	check(Save.get_victories() == 0 and Save.get_falls() == 1, "a trade records a fall, not a win (%d, %d)" % [Save.get_victories(), Save.get_falls()])


## The reveal and the fallen play out by themselves; then the ending waits at
## the choice for as long as the knight does, and never picks.
func _test_choice_waits() -> void:
	await _at_throne({ "falls": 5, "last_epitaph": "The descent is patient." })
	var fin := _kill_warden()
	var reached := {}
	var split_open := false
	var t := 0.0
	while fin.phase != Finale.Phase.CHOICE and t < 60.0:
		_step(fin)
		reached[fin.phase_name()] = true
		split_open = split_open or (is_instance_valid(fin._shell) and fin._shell.open > 0.5)
		t += DT
	check(reached.has("REVEAL") and reached.has("HOARD") and reached.has("CALL") and fin.phase == Finale.Phase.CHOICE, "the Warden opens, the fallen rise and the throne calls (%s)" % [reached.keys()])
	check(split_open and is_instance_valid(fin._burnt) and fin._burnt.crumble >= 1.0, "the Warden split open on the burnt knight, who crumbled")
	check(fin._fallen.size() == 5 and fin._fallen.all(func(f): return f.visible and f.hinge >= 0.99), "one fallen knight stands for each knight lost (%d)" % fin._fallen.size())
	check(fin._hoard.count() == 5 and fin._crowns.lit(0) == 0.0, "their flames hang in the hoard; they stand dark")
	check(fin.offered() == ["crown", "given"], "without every vow, two endings are offered (%s)" % [fin.offered()])
	check(fin._relic.position.distance_to(fin._knight.position + Vector2(20.0 * -fin._side, Content.FLOOR_Y - 1.0 - fin._knight.position.y)) < 2.0, "the crown has drifted to the knight's feet")
	_step_for(fin, 60.0)
	check(fin.phase == Finale.Phase.CHOICE and fin.ending.is_empty() and Save.get_last_ending() == "", "a minute later it is still waiting, and nothing was chosen")


## Left and right move through the offer; only a fresh press held long enough
## chooses, and letting go early drains it.
func _test_choice_input() -> void:
	var fin: Finale = await _to_choice({ "victories": 1, "vows": ALL_VOWS })
	check(fin.offered() == ["crown", "given", "ended"], "sworn to every vow, END IT is offered too (%s)" % [fin.offered()])
	Input.action_press("ui_accept")
	_step_for(fin, 2.0)
	check(fin.phase == Finale.Phase.CHOICE and fin._pick == -1, "holding with nothing in hand chooses nothing")
	Input.action_release("ui_accept")
	Input.action_press("move_right")
	_step_for(fin, 0.2)
	Input.action_release("move_right")
	_step(fin)
	check(fin._pick == 1, "the first press right takes GIVE THEM BACK (%d)" % fin._pick)
	Input.action_press("ui_right")
	_step(fin)
	Input.action_release("ui_right")
	_step(fin)
	Input.action_press("move_left")
	_step(fin)
	Input.action_release("move_left")
	_step(fin)
	Input.action_press("move_left")
	_step(fin)
	Input.action_release("move_left")
	_step(fin)
	check(fin._pick == 0, "left and right step along and stop at the ends (%d)" % fin._pick)
	Input.action_press("attack")
	_step_for(fin, 0.8)
	Input.action_release("attack")
	_step_for(fin, 0.5)
	check(fin.phase == Finale.Phase.CHOICE and fin._pick_hold == 0.0, "letting go before the hold is done drains it")
	Input.action_press("move_right")
	_step(fin)
	Input.action_release("move_right")
	Input.action_press("jump")
	_step_for(fin, Finale.CHOICE_HOLD + 0.1)
	check(fin.ending == "given" and Save.get_last_ending() == "given" and fin.phase != Finale.Phase.CHOICE, "a full hold keeps the ending in hand, at once (%s)" % fin.ending)
	Input.action_release("jump")
	# A key already held when the choice appears must be let go first.
	await _at_throne({})
	fin = _kill_warden()
	Input.action_press("attack")
	check(_step_to(fin, Finale.Phase.CHOICE), "the choice comes with a key held")
	Input.action_press("move_left")
	_step(fin)
	Input.action_release("move_left")
	_step_for(fin, 3.0)
	check(fin.phase == Finale.Phase.CHOICE, "a key held from before the choice never makes it")
	Input.action_release("attack")


## Each ending, in each cut, with no input after the choice, reaches the
## results panel with the ending kept, and leaves the hall as that ending does.
func _test_ending(ending: String, cut: String, seen: int, limit: float) -> void:
	# Vows open after a first win; the Oath's first keeping always plays in full.
	var sworn := ending == "ended"
	var fin: Finale = await _to_choice({ "victories": maxi(seen, int(sworn)), "finale_seen": seen, "oath_kept": sworn and seen > 0,
		"falls": 4, "last_epitaph": "The descent is patient.", "vows": ALL_VOWS if sworn else [] })
	var tag := "%s/%s" % [ending, cut]
	check(fin.tier == cut, "%s: the save picks the %s cut (%s)" % [tag, cut, fin.tier])
	var endings := [0]
	fin.finished.connect(func(_skipped: bool): endings[0] += 1)
	fin.choose(ending)
	var reached := {}
	var t := 0.0
	while endings[0] == 0 and t < limit:
		_step(fin)
		reached[fin.phase_name()] = true
		t += DT
	check(endings[0] == 1, "%s: finished once within %.0f s (took %.1f s)" % [tag, limit, t])
	var acts: Array = { "crown": ["CROWN"], "given": ["SKY", "LETGO"], "ended": ["DARK"] }[ending]
	check(acts.all(func(a): return reached.has(a)) and reached.has("LAST_WORD"), "%s: every act plays (%s)" % [tag, reached.keys()])
	check(Save.get_last_ending() == ending and Save.get_endings_seen().has(ending) and Save.ended_ever() == (ending == "ended"), "%s: the save keeps the ending" % tag)
	var room := game.room
	match ending:
		"crown":
			check(is_equal_approx(room.sigil_heat, 1.0) and room.sigil_gold == 0.0 and game.sconce_heat == 1.0 and fin._knight.red == 1.0 and not fin._knight.grounded, "%s: the knight sits, red-crowned, in a hall relit red" % tag)
			check(fin._fallen.all(func(f): return f.gesture == "kneel"), "%s: the fallen kneel" % tag)
		"given":
			check(not game._world_container.visible and fin._sky.reveal == 1.0 and fin._sky_layer.visible, "%s: the keep burned away to the sky" % tag)
			check(fin._fallen.all(func(f): return fin._crowns.lit(fin._fallen.find(f)) < 0.0), "%s: every flame left for the well" % tag)
		"ended":
			check(room.throne_split == 1.0 and room.sigil_heat == 0.0 and room.fire_heat == 0.0 and game.sconce_heat == 0.0, "%s: the throne is split and every fire out" % tag)
			check(fin._sky.dawn == 1.0 and is_zero_approx(game._world_container.modulate.a), "%s: the dark keep gave way to a grey dawn" % tag)
	_step_for(fin, 1.0)
	check((game.ui._panels["victory"] as Control).visible and paused, "%s: the results open over a paused world" % tag)
	check(game.music._current == "title", "%s: the title theme returns" % tag)
	await _settle_time()
	check(Engine.time_scale == 1.0, "%s: real time runs at the panel" % tag)


## Under GIVE THEM BACK: holding plays the question, a release pauses it, a tap
## rings one note, and letting go after the C# is LET GO, in the same frame.
func _test_gather() -> void:
	var fin: Finale = await _to_choice({ "falls": 7 })
	fin.choose("given")
	check(fin.phase == Finale.Phase.PROMPT, "the gather waits at its prompt")
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
	_step_for(fin, 0.8)
	check(range(7).all(func(i): return fin._crowns.lit(i) == 1.0), "every flame has gone home to its knight")
	Input.action_release("ignite")
	fin.step(DT)
	check(fin.phase == Finale.Phase.SKY, "letting go lets them go in the same frame")


## Pitches of the bells rung since the last call (each voice is read once).
func _rung(bell: AudioStream) -> Array:
	var out: Array = []
	for voice in game.feedback._audio_pool:
		if voice.stream == bell:
			out.append(voice.pitch_scale)
			voice.stream = null
	return out


## The skip hold, first viewing and repeat, from the slow-motion beat, and the
## ending a skip takes: the one chosen, else the last one offered, else GIVE.
func _test_skip() -> void:
	await _at_throne({})
	var fin := _kill_warden()
	var skipped := [false]
	fin.finished.connect(func(s: bool): skipped[0] = s)
	_step_to(fin, Finale.Phase.REVEAL)
	Input.action_press("pause")
	_step_for(fin, 1.9)
	check(not fin._skipping, "a first viewing does not skip on 1.9 s of pause")
	_step_for(fin, 0.2)
	check(fin._skipping and fin.ending == "given" and Save.get_last_ending() == "given", "a first viewing skips on a 2 s hold, and gives them back")
	_step_to(fin, Finale.Phase.DONE, 3.0)
	check(skipped[0] and (game.ui._panels["victory"] as Control).visible, "the skip ends at the panel, flagged as skipped")
	check(not game._world_container.visible and fin._sky.reveal == 1.0, "a skipped GIVE THEM BACK ends under the open sky")
	game.ui._process(DT)
	var again: Button = game.ui._panels["victory"].find_child("again", true, false)
	check(again.disabled, "with pause still held the results cannot be pressed")
	Input.action_release("pause")
	game.ui._process(DT)
	# The first control grabs focus deferred, on the next frame.
	await process_frame
	check(not again.disabled and again.has_focus(), "released, NEW RUN takes focus")
	# A repeat viewing needs 1 s and takes the ending last chosen.
	await _at_throne({ "victories": 1, "finale_seen": 1, "last_ending": "crown" })
	fin = _kill_warden()
	_step_to(fin, Finale.Phase.HOARD)
	Input.action_press("pause")
	_step_for(fin, 1.05)
	Input.action_release("pause")
	check(fin._skipping and fin.ending == "crown", "a repeat viewing skips on a 1 s hold and takes the crown again")
	_step_to(fin, Finale.Phase.DONE, 3.0)
	check(fin._knight.red == 1.0 and not fin._knight.grounded and is_equal_approx(game.room.sigil_heat, 1.0), "a skipped crown ends on the red-crowned knight, seated")
	# END IT last time, but not sworn to every vow now: END IT is not offered.
	await _at_throne({ "victories": 1, "finale_seen": 1, "last_ending": "ended", "ended_ever": true })
	fin = _kill_warden()
	_step_to(fin, Finale.Phase.CALL)
	fin.skip_to_end()
	check(fin.ending == "given", "a skip never takes an ending that is not offered")
	# After the choice, a skip keeps the ending chosen.
	fin = await _to_choice({ "victories": 1, "finale_seen": 1, "vows": ALL_VOWS })
	fin.choose("ended")
	_step_for(fin, 1.0)
	fin.skip_to_end()
	_step_to(fin, Finale.Phase.DONE, 3.0)
	check(fin.ending == "ended" and game.room.throne_split == 1.0 and fin._sky.dawn == 1.0, "a skip after the choice ends that ending")
	# From the slow-motion beat.
	await _at_throne({ "victories": 1, "finale_seen": 1 })
	fin = _kill_warden()
	Input.action_press("pause")
	for i in range(66):
		fin.step(DT)
	Input.action_release("pause")
	for i in range(30):
		fin.step(DT)
	check(fin._skipping and fin.phase == Finale.Phase.LAST_WORD and game._beat_kind.is_empty(), "a skip during the slow-motion beat ends the beat")
	await _settle_time()
	check(Engine.time_scale == 1.0, "a skip during the beat restores real time")


## Leaving from any phase, by RETURN TO TITLE or NEW RUN, puts back everything
## the ending borrowed.
func _test_abort_every_phase() -> void:
	var paths := { "CROWN": "crown", "PROMPT": "given", "GATHER": "given", "LETGO": "given", "SKY": "given", "DARK": "ended", "LAST_WORD": "given", "DONE": "crown" }
	await _at_throne({})
	for leave in ["title", "new_run"]:
		for phase in Finale.Phase.values():
			var name: String = Finale.Phase.keys()[phase]
			# A run takes its vows from the save when it begins.
			_seed_save({ "falls": 3, "victories": 1, "vows": ALL_VOWS if paths.get(name, "") == "ended" else [] })
			game._begin_run()
			await _enter_throne()
			var fin := _kill_warden()
			if paths.has(name):
				_step_to(fin, Finale.Phase.CHOICE)
				fin.choose(paths[name])
				if name == "GATHER":
					Input.action_press("ignite")
			check(_step_to(fin, phase, 90.0), "%s: the ending reaches %s (%s)" % [leave, name, fin.phase_name()])
			Input.action_release("ignite")
			if leave == "title":
				game._on_quit_to_title()
			else:
				game._begin_run()
			await process_frame
			await _settle_time()
			var box := game._world_container
			var layers := game.find_children("*", "CanvasLayer", true, false).filter(func(l): return [-1, 10, 45].has(l.layer))
			# The title hides the world by itself; a new run shows it, unburned.
			var restored := not is_instance_valid(fin) and game.finale == null and box.material == null and box.modulate == Color.WHITE
			restored = restored and box.visible == (leave == "new_run")
			restored = restored and game.feedback.camera.zoom.is_equal_approx(Vector2.ONE * Content.CAM_ZOOM)
			restored = restored and game.feedback.camera.offset == Vector2.ZERO and Engine.time_scale == 1.0 and layers.is_empty() and game.sconce_heat == 1.0
			restored = restored and (leave == "title" or (game.player.visible and not game.player.cinematic))
			check(restored, "%s from %s restores the world" % [leave, name])


## Reduced motion: every ending still reaches the results; the camera holds a
## few framings and cuts between them; no ash, no travelling burn, and time
## never slows.
func _test_reduced_motion() -> void:
	for ending in ["crown", "given", "ended"]:
		await _at_throne({ "falls": 3, "victories": 1, "vows": ALL_VOWS })
		game.feedback.set_reduced_motion(true)
		var fin := _kill_warden()
		var zooms := {}
		var slowed := false
		var flakes := 0
		var travel := -1.0
		while fin.phase != Finale.Phase.DONE and fin.clock < 120.0:
			if fin.phase == Finale.Phase.CHOICE:
				fin.choose(ending)
			_step(fin)
			slowed = slowed or Engine.time_scale < 1.0
			if fin._owns_camera:
				zooms[snappedf(game.feedback.camera.zoom.x, 0.0001)] = true
			if is_instance_valid(fin._ash):
				flakes = maxi(flakes, fin._ash.count())
			if game._world_container.material is ShaderMaterial:
				travel = float((game._world_container.material as ShaderMaterial).get_shader_parameter("travel"))
		check(fin.phase == Finale.Phase.DONE, "%s: reduced motion still reaches the results" % ending)
		check(zooms.size() <= 5, "%s: reduced motion holds a few framings (%s)" % [ending, zooms.keys()])
		check(flakes == 0 and travel <= 0.0, "%s: reduced motion sheds no ash and burns without a travelling edge" % ending)
		check(not slowed, "%s: reduced motion never slows time" % ending)
		game.feedback.set_reduced_motion(false)


## Through the burn, the tilt and the dark, the actor and sky layers hold the
## world camera's exact canvas transform, frame by frame, shake and all.
func _test_layer_sync() -> void:
	var synced := true
	var frames := 0
	for ending in ["given", "ended"]:
		var fin: Finale = await _to_choice({ "falls": 3, "victories": 1, "vows": ALL_VOWS })
		fin.choose(ending)
		_step_to(fin, Finale.Phase.SKY if ending == "given" else Finale.Phase.DARK)
		_step_for(fin, 4.0)
		fin.autostep = true
		game.feedback.shake(8.0, 3.0)
		for i in range(90):
			await process_frame
			var view := game.world_view.canvas_transform
			for layer: CanvasLayer in [fin._actor_layer, fin._sky_layer]:
				synced = synced and layer.transform.origin.distance_to(view.origin) < 0.01 and layer.transform.x.distance_to(view.x) < 0.01
			frames += 1
		fin.autostep = false
	check(synced and frames == 180, "the actor and sky layers follow the shaking camera exactly")


## What the next descent remembers: the burnt knight's words and colours, the
## Warden's title card (the Trial still overrides it) and its crown.
func _test_remembered() -> void:
	for last in ["", "crown", "given", "ended"]:
		await _at_throne({ "victories": 1 if last != "" else 0, "last_ending": last })
		check(game.room.boss._victor_crown == (last == "crown") and float(game.room.boss.visual_pose().get("crown_gold", 0.0)) == (0.8 if last == "crown" else 0.0), "after '%s' the Warden wears the right crown" % last)
		check(_boss_card() == Content.boss_subtitle(last).to_upper(), "after '%s' the Warden is announced as '%s' (%s)" % [last, Content.boss_subtitle(last), _boss_card()])
		var fin := _kill_warden()
		var said := ""
		while fin.phase != Finale.Phase.HOARD and fin.clock < 30.0:
			_step(fin)
			for card in fin._cards.get_children():
				said = (card as Label).text
		check(said == "“%s”" % Content.WARDEN_WORDS[last], "after '%s' the burnt knight says %s" % [last, said])
		check(fin._burnt == null or fin._burnt.ours == (last == "crown"), "after '%s' the burnt knight wears the right colours" % last)
	await _at_throne({ "last_ending": "crown" })
	game.room.trial = true
	game._on_boss_spawned()
	check(_boss_card() == "TRIAL OF THE THRONE", "the Trial of the Throne still names the Warden's fight")


## The subtitle on the Warden's title card, as shown.
func _boss_card() -> String:
	return (game.ui._boss_intro.sub as Label).text


## The title remembers the last ending: an empty save is today's title; after
## the crown the landing is empty; after the flames went home a star hangs over
## the well; once the keep was put out, the dawn stays.
func _test_title_states() -> void:
	for state in [[{}, "", false], [{ "last_ending": "crown", "victories": 1 }, "crown", false], [{ "last_ending": "given", "victories": 2 }, "given", false], [{ "last_ending": "crown", "ended_ever": true, "victories": 3 }, "crown", true]]:
		release(KEYS)
		await free_game()
		_seed_save(state[0])
		await load_main_scene(2)
		var tableau = game.ui._title_tableau
		check(tableau.legacy.ending == state[1] and tableau.legacy.dawn == state[2], "the title reads the ending '%s' and dawn %s" % [state[1], state[2]])
