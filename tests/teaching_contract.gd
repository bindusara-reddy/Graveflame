extends SceneTree
## Teaching contracts. The game cannot be judged fair if its least obvious
## mechanics are never explained, and the failure mode here is silent: a save
## flag that never gets set spams the same tip forever, and one that is always
## set teaches nothing. Both directions are pinned.
var game: Game
var checks := 0
var failures := 0

const TMP_SAVE := "user://teaching_contract.json"

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

func boot() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await ticks(6)
	game.ui.start_requested.emit()
	await ticks(20)

func teardown() -> void:
	if is_instance_valid(game):
		game.queue_free()
	await ticks(3)

func first_live_enemy():
	for e in game.room.enemies:
		if is_instance_valid(e) and not e.dead:
			return e
	return null

func windup_near_player() -> void:
	var enemy = first_live_enemy()
	if enemy == null:
		return
	enemy.global_position = game.player.global_position + Vector2(60.0, 0.0)
	enemy._begin_windup()

func run() -> void:
	Save.path = TMP_SAVE
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(TMP_SAVE)

	# The mechanics a player cannot infer from a bindings list must all be covered.
	for id in ["parry", "riposte", "slam", "wall_jump"]:
		check(Content.HINTS.has(id), "a lesson exists for %s" % id)

	await boot()
	check(Save.get_learned_hints().is_empty(), "a fresh save has learned nothing")

	# A windup in the player's face is when parry timing matters.
	game._hint_cooldown = 0.0
	game.ui.hide_banners()
	windup_near_player()
	await ticks(3)
	check(Save.has_learned("parry"), "a close windup teaches parry")
	check(game.ui._hint_panel.visible, "the lesson is actually shown")
	check(game.ui._hint_label.text == str(Content.HINTS["parry"]), "the lesson shows its own text")

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
	await teardown()
	await boot()
	check(Save.get_learned_hints() == learned_before, "learned lessons survive a relaunch")
	game._hint_cooldown = 0.0
	windup_near_player()
	await ticks(3)
	check(not game.ui._hint_panel.visible, "a returning player is not interrupted again")

	await teardown()
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(TMP_SAVE)
	print("TEACHING_RESULT: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
