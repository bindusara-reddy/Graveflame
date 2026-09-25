extends "res://tests/harness.gd"
## Fixture-free opening clear: reads live AI, sends input, never edits actors.

const DUEL_ACTIONS := ["attack", "parry", "move_left", "move_right"]
var parries := 0
var counters := 0

func run() -> void:
	use_scratch_save("input_combat_clear")
	# BEGIN comes one idle frame after boot, as the duel bot was tuned: a settle
	# tick with a physics step in it shifts the opening fight and costs ripostes.
	await load_main_scene(0)
	await process_frame
	await start_run(0)
	game.player.parried.connect(func(_pos, success):
		if success:
			parries += 1
	)
	game.player.hit_landed.connect(func(_damage, _pos, _heavy):
		if game.player._riposte_attack:
			counters += 1
	)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 35000 and not game.room.exit_open and not game.player.dead:
		await ticks(1)
		release(DUEL_ACTIONS)
		var p := game.player
		var closest: Enemy = null
		var distance := INF
		for e in live_enemies():
			var d: float = absf(e.global_position.x - p.global_position.x)
			if d < distance:
				distance = d
				closest = e
		if closest == null: continue
		var dx := closest.global_position.x - p.global_position.x
		if distance > 46.0 and p.state == Player.State.LOCOMOTION:
			Input.action_press("move_right" if dx > 0.0 else "move_left")
		if p.riposte_time > 0.0 and distance < 118.0 and p.facing == signf(dx):
			Input.action_press("attack")
		elif closest.state == Enemy.EState.WINDUP and closest.st_timer < 0.10 and p.parry_cd <= 0.0:
			Input.action_press("parry")
	release(DUEL_ACTIONS)
	var cleared: bool = game.room.exit_open and not game.player.dead and game._stats.kills == 2
	check(cleared, "input alone clears the opening chamber (kills=%d hp=%.1f)" % [game._stats.kills, float(game.player.build.hp)])
	check(parries >= 2 and counters >= 2, "the clear used real parries and ripostes (parries=%d ripostes=%d)" % [parries, counters])
	# Traverse to the exit using the same controls as the player, then use E.
	var exit_start := Time.get_ticks_msec()
	while cleared and absf(game.player.global_position.x - game.room.exit_center().x) > 20.0 and Time.get_ticks_msec() - exit_start < 10000:
		Input.action_press("move_right")
		await physics_frame
	Input.action_release("move_right")
	if cleared:
		await process_frame
		await hold_action("interact", 3)
		check(game.state == Game.GState.REWARD, "walking to the rift and pressing interact opens the reward")
	await finish("INPUT_CLEAR")
