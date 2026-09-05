extends SceneTree
## Staged gap + normal Dashmaster boon; NOT a full-run victory test.
## Walk/dash into the pit; never edit position, velocity, health, or i-frames.
var game: Game
var below_ticks := 0
var deepest_y := 0.0
var saw_dash := false
var damage_events := 0
var checks := 0
var failures := 0
var hp_events := 0
var death_events := 0
var second_wind_events := 0
var terminal_stats := -1.0
var reentered := false

func boot_component() -> void:
	# Focused signal/boon fixture, not input-only whole-run evidence.
	paused = false
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await ticks(3)
	game.ui.start_requested.emit()
	await ticks(4)
	game.run.apply_upgrade(Content.UPGRADES.filter(func(u): return u.id == "secondwind")[0])
	damage_events = 0
	hp_events = 0
	death_events = 0
	second_wind_events = 0
	terminal_stats = -1.0
	game.player.hurt_taken.connect(func(_amount, _pos): damage_events += 1)
	game.player.hp_changed.connect(func(_hp, _max_hp): hp_events += 1)
	game.player.died.connect(func():
		death_events += 1
		terminal_stats = float(game._stats.damage_taken))
	game.player.action_feedback.connect(func(kind, _pos):
		if kind == "second_wind": second_wind_events += 1)

func _init() -> void:
	call_deferred("run")

func ticks(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func run() -> void:
	Save.path = "user://void_contract.json"
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await ticks(3)
	game.ui.start_requested.emit()
	var gap: Dictionary = Content.ROOM_TEMPLATES.filter(func(t): return t.tag == "gap")[0].duplicate(true)
	gap.slots = []
	game.run.route[1] = gap
	game._advance_room()
	game.run.apply_upgrade(Content.UPGRADES.filter(func(u): return u.id == "dashmaster")[0])
	await ticks(85)
	game.player.hurt_taken.connect(func(_amount, _pos): damage_events += 1)
	Input.action_press("move_right")
	for i in range(900):
		Input.action_release("dash")
		if game.player.position.x > 380.0 and game.player.dash_cd <= 0.0 and game.player.state == Player.State.LOCOMOTION:
			Input.action_release("move_left")
			Input.action_release("move_right")
			Input.action_press("move_left" if game.player.position.x > 620.0 else "move_right")
			Input.action_press("dash")
			saw_dash = true
		await ticks(1)
		deepest_y = maxf(deepest_y, game.player.position.y)
		if game.player.position.y > Content.FLOOR_Y + 240.0: below_ticks += 1
		if game.state == Game.GState.GAME_OVER or below_ticks >= 180: break
	for action in ["dash", "move_left", "move_right"]: Input.action_release(action)
	check(saw_dash and deepest_y > Content.FLOOR_Y + 240.0, "real dash inputs reach the death plane")
	check(game.state == Game.GState.GAME_OVER and below_ticks <= 2, "invulnerability cannot postpone terminal out-of-world death")
	check(game.player.dead and game.player.build.hp == 0.0 and game.run.build.hp == 0.0, "terminal fall synchronizes player and run health")
	check(damage_events == 1 and is_equal_approx(float(game._stats.damage_taken), 100.0), "terminal fall records remaining health exactly once")
	print("VOID_DASH_EVIDENCE: below_ticks=", below_ticks, " y=", deepest_y, " hp=", game.player.build.hp)
	for i in range(3): game.player.fall_out_of_world()
	check(damage_events == 1 and is_equal_approx(float(game._stats.damage_taken), 100.0), "repeat terminal calls after a real fall do not add damage")

	await boot_component()
	check(game.player.build.second_wind and not game.player.build.second_wind_used, "normal boon grants an unused Second Wind")
	game.player.fall_out_of_world()
	check(game.state == Game.GState.GAME_OVER and game.player.dead and game.player.build.hp == 0.0 and game.run.build.hp == 0.0, "terminal call bypasses unused Second Wind and spawn immunity")
	check(not game.player.build.second_wind_used and not game.run.build.second_wind_used and second_wind_events == 0, "terminal fall never activates or spends Second Wind")
	check(damage_events == 1 and hp_events == 1 and death_events == 1 and is_equal_approx(terminal_stats, 100.0), "terminal health and damage signals precede the one death summary")
	for i in range(3): game.player.fall_out_of_world()
	check(damage_events == 1 and hp_events == 1 and death_events == 1, "repeat calls leave all terminal signals idempotent")

	await boot_component()
	# Damage injection is limited to this ordinary-hit / terminal-boundary fixture.
	game.player.iframes = 0.0
	game.player.take_damage(9999.0, Vector2.RIGHT, 0.0)
	check(not game.player.dead and game.player.build.second_wind_used and game.run.build.second_wind_used and second_wind_events == 1, "ordinary lethal damage still activates Second Wind exactly once")
	check(game.player.build.hp == 30.0 and game.run.build.hp == 30.0 and game.player.iframes > 0.0 and damage_events == 1 and float(game._stats.damage_taken) == 100.0, "ordinary revival synchronizes health, immunity and capped damage")
	game.player.take_damage(9999.0, Vector2.RIGHT, 0.0)
	check(game.player.build.hp == 30.0 and damage_events == 1, "ordinary follow-up hit remains blocked by revival immunity")
	game.player.fall_out_of_world()
	check(game.player.dead and game.player.build.hp == 0.0 and game.run.build.hp == 0.0 and death_events == 1 and damage_events == 2 and is_equal_approx(terminal_stats, 130.0), "terminal fall during revival immunity records only the restored health")
	game.player.fall_out_of_world()
	check(death_events == 1 and damage_events == 2 and hp_events == 2 and second_wind_events == 1, "repeat terminal call after revival adds no signals")

	await boot_component()
	# Synchronous subscribers can invoke the public terminal entry point again.
	game.player.hp_changed.connect(func(_hp, _max_hp):
		if not reentered:
			reentered = true
			game.player.fall_out_of_world())
	game.player.fall_out_of_world()
	check(reentered and hp_events == 1 and damage_events == 1 and death_events == 1, "reentrant terminal call from health notification emits each signal once")
	check(is_equal_approx(terminal_stats, 100.0) and game.player.dead and game.run.build.hp == 0.0, "reentrant death summary includes the complete terminal loss")
	paused = false
	game.queue_free()
	await process_frame
	print("VOID_FALL_RESULT: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
