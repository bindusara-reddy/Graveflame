extends SceneTree
## Anticipation contracts. Every windup that can damage the player has to be
## voiced, and the chamber has to report how many waves are left. Both are
## easy to break silently -- renaming a cue mutes it without any error, and a
## dropped connection makes the wave counter stale -- so both are pinned here.
var game: Game
var checks := 0
var failures := 0

const CUE_PREFIX := "tell_"
const TMP_SAVE := "user://anticipation_contract.json"

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

func _has_cue(name: String) -> bool:
	return game.feedback._streams.has(name)

func run() -> void:
	Save.path = TMP_SAVE
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await ticks(3)
	game.ui.start_requested.emit()
	await ticks(20)

	# --- Every archetype windup resolves to a real synthesized cue ---
	for kind in [Enemy.Kind.STALKER, Enemy.Kind.HOPPER, Enemy.Kind.WISP, Enemy.Kind.BRUTE, Enemy.Kind.BOMBER, Enemy.Kind.CROW]:
		var id: String = Enemy.telegraph_id(kind)
		check(_has_cue(CUE_PREFIX + id), "enemy windup cue exists: %s" % id)

	# --- Each of the warden's moves carries its own tell ---
	var boss := Boss.new()
	var tells := {}
	for action in [Boss.Action.LUNGE, Boss.Action.FAN, Boss.Action.SLAM, Boss.Action.CHARGE]:
		boss.action_idx = action
		tells[boss._action_telegraph()] = true
	boss.free()
	for id in tells.keys():
		check(_has_cue(CUE_PREFIX + str(id)), "warden move cue exists: %s" % id)
	check(tells.size() == 4, "the warden's four moves use four distinct tells")

	# --- Menu cues the UI actually emits ---
	for id in ["ui_confirm", "ui_back"]:
		check(_has_cue(id), "menu cue exists: %s" % id)

	# --- A live windup reaches the game end to end: Enemy -> Room -> Game ---
	var live: Array = []
	for e in game.room.enemies:
		if is_instance_valid(e) and not e.dead:
			live.append(e)
	check(not live.is_empty(), "the opening chamber spawns enemies to telegraph")
	if not live.is_empty():
		var enemy = live[0]
		var expected := CUE_PREFIX + Enemy.telegraph_id(enemy.kind)
		game._telegraph_at.clear()
		enemy.global_position = game.player.global_position + Vector2(60.0, 0.0)
		enemy._begin_windup()
		await ticks(2)
		check(game._telegraph_at.has(expected), "a live windup reaches the game as %s" % expected)
		# A tell beyond earshot must stay silent, and must not consume the cue
		# that a closer enemy may need in the same instant.
		game._telegraph_at.clear()
		enemy.global_position = game.player.global_position + Vector2(Game.TELEGRAPH_RANGE + 80.0, 0.0)
		enemy._begin_windup()
		await ticks(2)
		check(not game._telegraph_at.has(expected), "a windup beyond earshot is not voiced")

	# --- The chamber reports its waves; the throne room reports none ---
	game.run.room_index = 4
	game._advance_room()
	await ticks(10)
	var total: int = game.room.wave_count()
	check(total >= 1, "a combat chamber declares at least one wave")
	check(game.ui._wave_label.visible, "the wave counter is shown in a combat chamber")
	check(
		game.ui._wave_label.text == "WAVE 1 / %d" % total,
		"the wave counter opens on wave 1 (got %s)" % game.ui._wave_label.text
	)
	if total >= 2:
		# A shielded brute absorbs the first frontal hit and only breaks its
		# guard, so keep swinging until the wave is genuinely down. Keep the
		# player out of it: bomber blasts must not end the run mid-measurement.
		game.player.iframes = 30.0
		for e in game.room.enemies:
			if not is_instance_valid(e):
				continue
			for _swing in range(4):
				if not is_instance_valid(e) or e.dead:
					break
				e.take_damage(99999.0, Vector2.RIGHT, 0.0)
		await ticks(80)
		check(
			game.ui._wave_label.text == "WAVE 2 / %d" % total,
			"the wave counter advances with the fight (got %s)" % game.ui._wave_label.text
		)

	game.run.room_index = game.run.rooms_total() - 2
	game._advance_room()
	await ticks(20)
	check(not game.ui._wave_label.visible, "the throne room carries no wave counter")

	game.queue_free()
	await process_frame
	# Leave no scratch save in the player's userdata directory.
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(TMP_SAVE)
	print("ANTICIPATION_RESULT: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
