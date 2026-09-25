extends "res://tests/harness.gd"
## Run-state contracts: the save survives a torn write and is never written from
## a kill.
## Headless; uses a scratch save.
##   godot4 --headless --path . --script res://tests/run_state_contract.gd

const SCRATCH := "run_state_contract"

func run() -> void:
	use_scratch_save(SCRATCH)
	_test_save_file()
	await _test_banking()
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

func _test_banking() -> void:
	await boot()
	await clear_room()
	check(Save.get_cells() == 0 and game._unbanked_cells > 0, "kills never write the save mid-combat")
	game.room.chosen_exit = "font"
	game._on_room_completed()
	await ticks(2)
	check(Save.get_cells() == game._run_cells and game._unbanked_cells == 0, "cells are banked on the way into the next chamber")
	use_scratch_save(SCRATCH)
