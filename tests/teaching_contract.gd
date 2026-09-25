extends "res://tests/harness.gd"
## Teaching contracts. The game cannot be judged fair if its least obvious
## mechanics are never explained, and the failure mode here is silent: a save
## flag that never gets set spams the same tip forever, and one that is always
## set teaches nothing. Both directions are pinned.

func windup_near_player() -> void:
	var live := live_enemies()
	if live.is_empty():
		return
	var enemy = live[0]
	enemy.global_position = game.player.global_position + Vector2(60.0, 0.0)
	enemy._begin_windup()

func run() -> void:
	use_scratch_save("teaching_contract")

	# The mechanics a player cannot infer from a bindings list must all be covered.
	for id in ["parry", "riposte", "slam", "wall_jump"]:
		check(Content.HINTS.has(id), "a lesson exists for %s" % id)

	await load_main_scene(6)
	await start_run(20)
	check(Save.get_learned_hints().is_empty(), "a fresh save has learned nothing")

	# A windup in the player's face is when parry timing matters.
	game._hint_cooldown = 0.0
	game.ui.hide_banners()
	windup_near_player()
	await ticks(3)
	check(Save.has_learned("parry"), "a close windup teaches parry")
	check(game.ui.hud._hint.visible, "the lesson is actually shown")
	var lesson: UiKit.PromptLine = game.ui.hud._hint_line
	check(lesson.template == Content.HINTS["parry"], "the lesson shows its own text")
	var first: Control = lesson.get_child(0)
	check(first is UiKit.Glyph and first.action == "parry", "the lesson opens on the live parry key cap")

	# ...and never again.
	game._hint_cooldown = 0.0
	windup_near_player()
	await ticks(3)
	var parry_count := 0
	for id in Save.get_learned_hints():
		if id == "parry":
			parry_count += 1
	check(parry_count == 1, "a lesson is never relearned")

	# The counter window is open at the moment of a deflection.
	game._hint_cooldown = 0.0
	game._on_parried(game.player.global_position, true)
	await ticks(3)
	check(Save.has_learned("riposte"), "a successful deflection teaches the riposte")

	# Lessons must not stack on top of each other.
	game._hint_cooldown = 0.0
	windup_near_player()
	await ticks(2)
	windup_near_player()
	await ticks(2)
	check(Save.get_learned_hints().size() <= 2, "lessons do not stack in one moment")

	# A returning player is not re-taught.
	var learned_before: Array = Save.get_learned_hints().duplicate()
	await free_game()
	await ticks(3)
	await load_main_scene(6)
	await start_run(20)
	check(Save.get_learned_hints() == learned_before, "learned lessons survive a relaunch")
	game._hint_cooldown = 0.0
	windup_near_player()
	await ticks(3)
	check(not game.ui.hud._hint.visible, "a returning player is not interrupted again")

	await finish("TEACHING")
