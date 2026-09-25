extends "res://tests/harness.gd"
## Run-state contracts: the save survives a torn write and is never written from
## a kill, the ledger records each descent once, a dead knight cannot take a
## rift, a Trial before the throne is paid there, Esc on a screen opened from
## pause steps back instead of resuming, and the camera frames the Warden.
## Headless; uses a scratch save.
##   godot4 --headless --path . --script res://tests/run_state_contract.gd

const SCRATCH := "run_state_contract"

func run() -> void:
	use_scratch_save(SCRATCH)
	_test_save_file()
	_test_ledger()
	_test_surge()
	await _test_banking()
	await _test_chamber_stats()
	await _test_look_ahead()
	await _test_dead_knight()
	await _test_throne()
	await _test_warden_framing()
	await _test_pause_routing()
	await finish("RUN_STATE")

func write_text(file: String, text: String) -> void:
	var f := FileAccess.open(file, FileAccess.WRITE)
	f.store_string(text)
	f.close()

## Drops Save's cache, as a relaunch would.
func relaunch_save() -> void:
	Save.path = Save.path

func boot() -> void:
	await load_main_scene()
	await start_run()
	game.player.iframes = 99.0

func clear_room() -> void:
	for e in live_enemies():
		e.take_damage(99999.0, Vector2.RIGHT, 0.0)
	game.room._wave_index = game.room._waves.size()
	game.room._unlock_exit()
	await ticks(2)

## Boots a run and walks straight into the throne room.
func enter_throne(trial := false) -> void:
	await boot()
	game.run.room_index = game.run.rooms_total() - 2
	game.run.trial_next = trial
	game._advance_room()
	await ticks(3)

func _test_save_file() -> void:
	Save.add_cells(5)
	Save.add_cells(2)
	check(not FileAccess.file_exists(Save.path + ".tmp"), "a write leaves no temporary file behind")
	var backup: Variant = JSON.parse_string(FileAccess.get_file_as_string(Save.path + ".bak"))
	check(backup is Dictionary and int(backup.cells) == 5, "the previous save is kept as a backup")
	var text := FileAccess.get_file_as_string(Save.path)
	write_text(Save.path, text.substr(0, text.length() - 7))
	relaunch_save()
	check(Save.get_cells() == 5, "a torn save falls back to its backup instead of wiping progress")
	write_text(Save.path, "{\"cells\": 999}")
	check(Save.get_cells() == 5, "reads come from memory, never the disk")
	write_text(Save.path, "{")
	write_text(Save.path + ".bak", "")
	relaunch_save()
	check(Save.get_cells() == 0, "an unreadable save and backup fall back to defaults")
	var kept := Array(DirAccess.get_files_at("user://")).filter(func(f: String): return f.begins_with(SCRATCH + ".json.corrupt-"))
	check(not kept.is_empty(), "the unreadable save is kept aside, not destroyed")
	for f in kept:
		DirAccess.remove_absolute("user://" + f)
	use_scratch_save(SCRATCH)

func _test_ledger() -> void:
	var win := {"won": true, "seed": 1, "room": 8, "score": 5000, "time": 300.0, "kills": 60, "cells": 90, "streak": 9, "heat": 2, "boons": ["power"]}
	check(Save.record_run(win).broken.is_empty(), "a first record beats nothing")
	var faster := win.duplicate()
	faster.time = 250.0
	faster.score = 4000
	var broken: Array = Save.record_run(faster).broken
	check(broken.has("fastest_win") and not broken.has("best_win_score"), "a faster, lower-scoring win breaks only the speed record (got %s)" % str(broken))
	var d := Save.load_save()
	check(int(d.stats.runs) == 2 and int(d.stats.wins) == 2 and int(d.stats.kills) == 120, "lifetime totals accumulate")
	check(int(d.boon_wins.power) == 2 and int(d.best_score) == 5000, "winning boons and the best score are recorded")
	var loss := win.duplicate()
	loss.won = false
	for i in range(Save.HISTORY_CAP):
		Save.record_run(loss)
	d = Save.load_save()
	check(d.history.size() == Save.HISTORY_CAP and not bool(d.history[0].won), "history keeps the newest descents, capped")
	check(int(d.stats.deaths) == Save.HISTORY_CAP and float(d.records.fastest_win) == 250.0, "a loss never sets a win record")
	use_scratch_save(SCRATCH)

func _test_surge() -> void:
	var rm := RunModel.new(1)
	var dmg := float(rm.build.dmg_mul)
	rm.apply_upgrade(upgrade("surge"))
	check(is_equal_approx(rm.build.dmg_mul, dmg) and is_equal_approx(rm.build.lance_mul, 1.35), "Surge strengthens the lance alone")

func _test_banking() -> void:
	await boot()
	await clear_room()
	check(Save.get_cells() == 0 and game._unbanked_cells > 0, "kills never write the save mid-combat")
	game.room.chosen_exit = "font"
	game._on_room_completed()
	await ticks(2)
	check(Save.get_cells() == game._run_cells and game._unbanked_cells == 0, "cells are banked on the way into the next chamber")
	use_scratch_save(SCRATCH)

func _test_chamber_stats() -> void:
	await boot()
	for key in ["kills_by_kind", "parries", "perfect_parries", "ripostes", "untouched_chambers", "damage_taken"]:
		check(game._stats.has(key), "run stats carry %s" % key)
	await clear_room()
	var by_kind := 0
	for kind in game._stats.kills_by_kind:
		by_kind += int(game._stats.kills_by_kind[kind])
	check(by_kind == int(game._stats.kills) and by_kind > 0, "every kill is counted by kind")
	game.room.chosen_exit = "font"
	game._on_room_completed()
	await ticks(2)
	check(int(game._stats.rooms) == 1 and int(game._stats.untouched_chambers) == 1, "a clear without a wound counts as cleared and untouched")

## Turning on the spot never pans; running eases the frame ahead.
func _test_look_ahead() -> void:
	await boot()
	await clear_room()
	var p := game.player
	game._look_x = 0.0
	p.facing = -1.0
	p.velocity.x = 0.0
	game._ease_look_ahead(1.0)
	check(is_zero_approx(game._look_x), "turning on the spot leaves the frame still")
	p.velocity.x = -300.0
	game._ease_look_ahead(0.1)
	check(is_equal_approx(game._look_x, -Game.LOOK_EASE * 0.1), "running eases the look-ahead instead of snapping it")
	game._ease_look_ahead(5.0)
	check(is_equal_approx(game._look_x, -Game.LOOK_AHEAD), "the look-ahead settles at its full reach")

func _test_dead_knight() -> void:
	use_scratch_save(SCRATCH)
	await boot()
	await clear_room()
	game.player.fall_out_of_world()
	game.room.chosen_exit = "boon"
	game._on_room_completed()
	await ticks(2)
	check(game.state == Game.GState.GAME_OVER and not (game.ui._panels["reward"] as Control).visible, "a dead knight cannot take a rift")
	var d := Save.load_save()
	check(int(d.stats.deaths) == 1 and int(d.history[0].room) == 0 and game._stats.has("broken"), "the death is recorded once, with no chamber cleared")

func _test_throne() -> void:
	await enter_throne(true)
	check(game.room.is_boss and game.room.trial and not game.run.trial_next, "a Trial taken before the throne is paid at the throne")
	check(game.ui.hud._boss_intro.kicker.text == "TRIAL OF THE THRONE", "the Warden's card names the Trial of the Throne")
	var boss: Boss = game.room.boss
	if "trial" in boss:
		check(boss.trial, "the Warden knows it is a Trial")

func _test_warden_framing() -> void:
	await enter_throne()
	# Both fighters stay in frame 800 px apart; the old look-ahead lost the Warden.
	game.room.boss.global_position.x = 1300.0
	var centre := game._camera_target_for(Vector2(500.0, Content.FLOOR_Y - 40.0)).x
	var half := Content.VIEW_W * 0.5 / Content.CAM_ZOOM
	check(absf(1300.0 - centre) < half and absf(500.0 - centre) < half, "the camera frames the knight and the Warden together")
	# The Warden's windups are voiced at any range; a far minion's are not.
	var far := game.player.global_position + Vector2(900.0, 0.0)
	game._telegraph_at.clear()
	game._on_enemy_telegraphed("fan", far, true)
	game._on_enemy_telegraphed("stalker", far, false)
	check(game._telegraph_at.has("tell_fan") and not game._telegraph_at.has("tell_stalker"), "the Warden's tells ignore the range gate")

func _test_pause_routing() -> void:
	await boot()
	await tap_key(KEY_ESCAPE)
	check(paused and (game.ui._panels["pause"] as Control).visible, "Esc pauses the run")
	game.ui.options_requested.emit()
	await ticks(2)
	await tap_key(KEY_ESCAPE)
	check(paused and (game.ui._panels["pause"] as Control).visible and not (game.ui._panels["options"] as Control).visible, "Esc on options opened from pause returns to pause")
	game.ui.options_requested.emit()
	game.ui.keys_requested.emit()
	await ticks(2)
	await tap_key(KEY_ESCAPE)
	check(paused and (game.ui._panels["options"] as Control).visible, "Esc on keys steps back to options, still paused")
	await tap_key(KEY_ESCAPE)
	await tap_key(KEY_ESCAPE)
	check(not paused and not game.paused, "Esc on the pause menu resumes")
