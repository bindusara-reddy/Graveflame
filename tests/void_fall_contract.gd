extends "res://tests/harness.gd"
## Staged gap + normal Dashmaster boon; NOT a full-run victory test.
## Walk/dash into the pit; never edit position, velocity, health, or i-frames.
## The pit section pins the whole spike contact: the first dash leaves from the
## causeway floor, the spikes land one 18-damage hit that closes the blade
## hitbox, and the knight is returned to solid ground rather than the void.
var below_ticks := 0
var deepest_y := 0.0
var saw_dash := false
var launched_from_floor := false
var blade_closed_on_hit := false
var damage_events := 0
var hp_events := 0
var death_events := 0
var second_wind_events := 0
var terminal_stats := -1.0
var reentered := false

func boot_component() -> void:
	# Focused signal/boon fixture, not input-only whole-run evidence.
	await load_main_scene()
	await start_run()
	game.run.apply_upgrade(upgrade("secondwind"))
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

func run() -> void:
	use_scratch_save("void_contract")
	await load_main_scene()
	await start_run(0)
	# Dashmaster lands in the shared run build before the gap room is entered.
	game.run.apply_upgrade(upgrade("dashmaster"))
	await enter_empty_room("gap")
	game.player.hurt_taken.connect(func(_amount, _pos): damage_events += 1)
	var rescued := [false]
	game.player.action_feedback.connect(func(kind, _pos): if kind == "rescued": rescued[0] = true)
	Input.action_press("move_right")
	for i in range(900):
		Input.action_release("dash")
		if game.player.position.x > 380.0 and game.player.dash_cd <= 0.0 and game.player.state == Player.State.LOCOMOTION:
			Input.action_release("move_left")
			Input.action_release("move_right")
			Input.action_press("move_left" if game.player.position.x > 620.0 else "move_right")
			if not saw_dash:
				launched_from_floor = game.player.is_on_floor()
			Input.action_press("dash")
			saw_dash = true
		await ticks(1)
		deepest_y = maxf(deepest_y, game.player.position.y)
		if game.player.position.y > Content.FLOOR_Y + 240.0: below_ticks += 1
		if damage_events > 0:
			# Read on the tick the spikes hit, before the knight is set back down.
			blade_closed_on_hit = game.player._atk_shape.disabled
			break
		if game.state == Game.GState.GAME_OVER or below_ticks >= 180: break
	release(["dash", "move_left", "move_right"])
	await ticks(20)
	# Spike pits cost health, not the run; only the world boundary is terminal.
	check(launched_from_floor, "dash launch begins on the real causeway floor")
	check(saw_dash and damage_events == 1, "real dash inputs carry the knight onto the pit spikes")
	check(blade_closed_on_hit, "hazard interruption leaves no active blade hitbox")
	check(below_ticks == 0 and game.state == Game.GState.PLAYING and not game.player.dead, "dash immunity cannot carry the knight past the spikes into the void")
	check(rescued[0] and game.player.position.y < Content.FLOOR_Y and game.player.is_on_floor(), "the spikes return the knight to solid ground")
	check(is_equal_approx(float(game.player.build.hp), 82.0) and is_equal_approx(float(game.run.build.hp), 82.0) and is_equal_approx(float(game._stats.damage_taken), 18.0), "a spike pit costs 18 health and the run synchronizes it")
	print("VOID_DASH_EVIDENCE: below_ticks=", below_ticks, " y=", deepest_y, " hp=", game.player.build.hp)
	game.player.fall_out_of_world()
	check(game.state == Game.GState.GAME_OVER and game.player.dead and game.player.build.hp == 0.0 and game.run.build.hp == 0.0, "crossing the world boundary remains terminal")
	check(damage_events == 2 and is_equal_approx(float(game._stats.damage_taken), 100.0), "terminal fall records remaining health exactly once")
	for i in range(3): game.player.fall_out_of_world()
	check(damage_events == 2 and is_equal_approx(float(game._stats.damage_taken), 100.0), "repeat terminal calls do not add damage")

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
	await finish("VOID_FALL")
