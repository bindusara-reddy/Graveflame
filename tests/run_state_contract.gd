extends "res://tests/harness.gd"
## Run-state contracts: the save survives a torn write and is never written from
## a kill, the ledger records each descent once, and a dead knight cannot take a
## rift.
## Headless; uses a scratch save.
##   godot4 --headless --path . --script res://tests/run_state_contract.gd

const SCRATCH := "run_state_contract"

func run() -> void:
	use_scratch_save(SCRATCH)
	_test_save_file()
	_test_ledger()
	await _test_banking()
	await _test_chamber_stats()
	await _test_dead_knight()
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
