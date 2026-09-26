extends "res://tests/harness.gd"
## Anticipation contracts. Every windup that can damage the player has to be
## voiced, and the chamber has to report how many waves are left. Both are
## easy to break silently -- renaming a cue mutes it without any error, and a
## dropped connection makes the wave counter stale -- so both are pinned here.
const CUE_PREFIX := "tell_"

func _has_cue(name: String) -> bool:
	return game.feedback._streams.has(name)

func run() -> void:
	use_scratch_save("anticipation_contract")
	await load_main_scene()
	await start_run(20)

	# --- Every archetype windup resolves to a real synthesized cue ---
	for kind in Enemy.Kind.values():
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
	var live := live_enemies()
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
	var waves: UiKit.Pips = game.ui.hud._waves
	check(waves.visible, "the wave pips are shown in a combat chamber")
	check(
		waves.count == total and waves.filled == 1,
		"the wave pips open on wave 1 (got %d of %d)" % [waves.filled, waves.count]
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
			waves.filled == 2 and waves.count == total,
			"the wave pips advance with the fight (got %d of %d)" % [waves.filled, waves.count]
		)

	game.run.room_index = game.run.rooms_total() - 2
	game._advance_room()
	await ticks(20)
	check(not waves.visible, "the throne room carries no wave pips")

	await finish("ANTICIPATION")
