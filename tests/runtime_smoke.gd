extends SceneTree
## SceneTree-backed smoke coverage for behavior that pure data tests cannot verify.
## Run: godot --headless --path . --script res://tests/runtime_smoke.gd

var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


const MusicSynth := preload("res://scripts/music.gd")
const TEST_SAVE := "user://graveflame_save_smoke.json"


func _run() -> void:
	await process_frame
	Save.path = TEST_SAVE
	_test_physics_layers()
	_test_chamber_spawn_separation()
	await _test_project_boot()
	await _test_projectile_reflection()
	await _test_player_room_respawn()
	await _test_burn_expiry()
	await _test_boss_intro()
	await _test_room_exit_flow()
	await _test_forge_focus_rebuild()
	await _test_responsive_ui()
	await _test_enemy_scaling_and_elites()
	await _test_second_wind()
	await _test_thorns_and_executioner()
	await _test_pyre()
	await _test_boss_charge_and_summons()
	await _test_boss_room_adds()
	await _test_music_renders()
	await _test_room_dressing()
	await _test_full_run_simulation()
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)
	var passed := failures == 0
	print("RUNTIME_SMOKE_RESULT: %s (%d checks, %d failures)" % ["PASS" if passed else "FAIL", checks, failures])
	quit(0 if passed else 1)


func _test_physics_layers() -> void:
	var layers := {
		"World": Content.L_WORLD,
		"PlayerBody": Content.L_PLAYER_BODY,
		"EnemyBody": Content.L_ENEMY_BODY,
		"PlayerHurtbox": Content.L_PLAYER_HURT,
		"EnemyHurtbox": Content.L_ENEMY_HURT,
		"PlayerAttack": Content.L_PLAYER_ATK,
		"EnemyAttack": Content.L_ENEMY_ATK,
		"Trigger": Content.L_TRIGGER,
	}
	var seen := {}
	for layer_name: String in layers:
		var mask: int = layers[layer_name]
		check(mask > 0 and (mask & (mask - 1)) == 0, "%s layer is a power-of-two mask" % layer_name)
		check(not seen.has(mask), "%s layer mask is unique" % layer_name)
		seen[mask] = true
	check(seen.size() == layers.size(), "all eight physics layer masks are distinct")


func _test_chamber_spawn_separation() -> void:
	var chamber: Dictionary = {}
	for template in Content.ROOM_TEMPLATES:
		if str(template.get("tag", "")) == "chamber":
			chamber = template
			break
	check(not chamber.is_empty(), "chamber room template is available")
	if chamber.is_empty():
		return
	var slots: Array = chamber.get("slots", [])
	check(not slots.is_empty(), "chamber room defines enemy spawn slots")
	if slots.is_empty():
		return
	var entry: Vector2 = chamber.get("entry", Vector2.ZERO)
	var first_slot: Vector2 = slots[0]
	var largest_enemy := Vector2.ZERO
	for enemy_data: Dictionary in Content.ENEMY.values():
		largest_enemy.x = maxf(largest_enemy.x, float(enemy_data.get("w", 0.0)))
		largest_enemy.y = maxf(largest_enemy.y, float(enemy_data.get("h", 0.0)))
	var center_delta := (first_slot - entry).abs()
	var half_extents := (Vector2(Content.P_BODY_W, Content.P_BODY_H) + largest_enemy) * 0.5
	var clearance := center_delta - half_extents
	check(clearance.x >= 32.0 or clearance.y >= 32.0, "chamber entry has safe clearance from its first enemy spawn")


func _test_project_boot() -> void:
	var scene_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	check(scene_path == "res://main.tscn", "project declares the expected main scene")
	var packed = load(scene_path)
	check(packed is PackedScene, "main scene loads as a PackedScene")
	if not (packed is PackedScene):
		return
	var game = packed.instantiate()
	check(game != null, "main scene instantiates")
	root.add_child(game)
	await process_frame
	await physics_frame
	check(game.is_inside_tree(), "main scene remains alive after process and physics frames")
	check(game is Game, "main scene root has the Game script")
	if game is Game:
		check(game.state == Game.GState.TITLE, "project boots into the title state")
		check(is_instance_valid(game.ui), "project boot constructs the UI")
		check(is_instance_valid(game.feedback) and is_instance_valid(game.feedback.camera), "project boot constructs feedback and camera")
	game.queue_free()
	await process_frame


func _test_projectile_reflection() -> void:
	var projectile := Projectile.new()
	root.add_child(projectile)
	projectile.setup("enemy", Vector2(300, 200), Vector2(-420, 0), 10.0, 160.0, 0, 2.0, Color("ff6b6b"))
	check(projectile.monitorable, "enemy projectile is monitorable by a parry Area2D")
	check(projectile.team == "enemy" and projectile.get_meta("team", "") == "enemy", "enemy projectile property and metadata agree")
	check(projectile.collision_layer == Content.L_ENEMY_ATK and projectile.collision_mask == Content.L_PLAYER_HURT, "enemy projectile uses enemy attack layers")
	var original_damage := projectile.damage
	projectile.reflect(Vector2.RIGHT, Content.PARRY_PROJECTILE_BOOST)
	check(projectile.team == "player", "reflection changes the projectile team")
	check(projectile.get_meta("team", "") == "player", "reflection updates projectile team metadata")
	check(projectile.get_meta("attack_kind", "") == "projectile", "reflected projectile remains tagged as a projectile")
	check(projectile.collision_layer == Content.L_PLAYER_ATK, "reflected projectile moves to the player attack layer")
	check(projectile.collision_mask == Content.L_ENEMY_HURT, "reflected projectile targets enemy hurtboxes")
	check(is_equal_approx(float(projectile.get_meta("damage", 0.0)), projectile.damage), "reflection refreshes damage metadata")
	check(projectile.damage > original_damage and projectile.vel.x > 0.0, "reflection boosts damage and redirects velocity")
	projectile.queue_free()
	await process_frame


func _test_player_room_respawn() -> void:
	var run_model := RunModel.new(112358)
	var player := Player.new()
	player.setup(run_model)
	root.add_child(player)
	player.flask_charges = 1
	player.special = 42.0
	# Simulate a transition occurring during contaminated combat state. Room
	# travel must not carry active hitboxes, buffered attacks, or parry windows.
	player.state = Player.State.PARRY
	player.attack_index = 1
	player.atk_phase = "active"
	player.attack_buffer = 0.1
	player._queued_attack = true
	player.atk_hit[99] = true
	player._atk_shape.disabled = false
	player._attack_area.monitoring = true
	player.parry_time = 0.1
	player._draw_parry = 0.2
	player._parry_hit[99] = true
	player._parry_succeeded = true
	player._parry_shape.disabled = false
	player._parry_area.monitoring = true
	var destination := Vector2(512, 384)
	player.respawn_at(destination)
	check(player.global_position == destination, "room respawn moves the player to the next entry")
	check(player.flask_charges == 1, "room respawn preserves current flask charges")
	check(is_equal_approx(player.special, 42.0), "room respawn preserves current special meter")
	check(not player.dead and player.state == Player.State.LOCOMOTION, "room respawn restores a live locomotion state")
	check(player.attack_index == -1 and player.atk_phase == "none", "room respawn clears the active combo state")
	check(is_zero_approx(player.attack_buffer) and not player._queued_attack and player.atk_hit.is_empty(), "room respawn clears buffered attack data")
	check(player._atk_shape.disabled and not player._attack_area.monitoring, "room respawn disables the melee hitbox")
	check(is_zero_approx(player.parry_time) and is_zero_approx(player._draw_parry), "room respawn clears the parry window and visual")
	check(player._parry_hit.is_empty() and not player._parry_succeeded, "room respawn clears parry hit bookkeeping")
	check(player._parry_shape.disabled and not player._parry_area.monitoring, "room respawn disables the parry hitbox")
	player.queue_free()
	await process_frame


func _test_burn_expiry() -> void:
	var enemy := Enemy.new()
	enemy.setup(Enemy.Kind.STALKER, Vector2(400, Content.FLOOR_Y - 40))
	root.add_child(enemy)
	enemy.apply_burn(10.0, 0.01)
	check(is_equal_approx(enemy.burn_dps, 10.0) and enemy.burn_time > 0.0, "burn application records DPS and duration")
	enemy._tick_status(0.02)
	check(is_zero_approx(enemy.burn_time), "burn duration reaches zero when the status expires")
	check(is_zero_approx(enemy.burn_dps), "burn DPS resets when the status expires")
	enemy.apply_burn(2.0, 1.0)
	check(is_equal_approx(enemy.burn_dps, 2.0), "a new burn does not inherit expired DPS")
	enemy.queue_free()
	await process_frame


func _test_boss_intro() -> void:
	var boss := Boss.new()
	boss.intro_t = 0.01
	root.add_child(boss)
	check(boss.phase == Boss.BPhase.INTRO, "boss starts in its intro phase")
	check(is_instance_valid(boss._hurtbox) and boss._hurtbox.is_in_group("enemy_hurtbox"), "boss hurtbox joins the slam target group")
	await physics_frame
	await physics_frame
	check(boss.phase == Boss.BPhase.ONE, "boss leaves intro after its intro timer")
	check(boss.state == Enemy.EState.SEEK, "boss enters an active seek state after intro")
	boss.queue_free()
	await process_frame


func _test_room_exit_flow() -> void:
	var player_stub := Node2D.new()
	player_stub.global_position = Vector2.ZERO
	root.add_child(player_stub)
	var room := Room.new()
	room.setup(Content.ROOM_TEMPLATES[0], false, player_stub, 2468)
	room.set_meta("room_index", 0)
	var completed_count := [0]
	var cleared_count := [0]
	room.completed.connect(func(): completed_count[0] += 1)
	room.cleared.connect(func(_room_name: String): cleared_count[0] += 1)
	root.add_child(room)
	check(room.enemies.size() > 0, "runtime room spawns its encounter")
	check(not room.exit_open, "room exit begins sealed")
	var spawned := room.enemies.duplicate()
	for enemy in spawned:
		if is_instance_valid(enemy):
			enemy.take_damage(99999.0, Vector2.RIGHT, 0.0)
	check(room.exit_open, "final enemy kill unlocks the room exit")
	check(cleared_count[0] == 1, "final enemy kill emits one cleared signal")
	check(completed_count[0] == 0, "final enemy kill does not auto-complete the room")
	check(room.is_at_exit(room._exit_rect.get_center()), "unlocked exit reports its interaction area")
	room.queue_free()
	player_stub.queue_free()
	await process_frame


func _test_forge_focus_rebuild() -> void:
	var ui := UI.new()
	root.add_child(ui)
	ui.setup_forge(999)
	ui.hide_all_panels()
	ui.show_panel("forge")
	await process_frame
	await process_frame
	var panel: Control = ui._panels.get("forge")
	var initial_focus: Control = root.gui_get_focus_owner()
	check(_is_usable_focus(initial_focus, panel), "forge acquires a usable focus target when opened")
	ui.setup_forge(999)
	await process_frame
	await process_frame
	var rebuilt_focus: Control = root.gui_get_focus_owner()
	check(_is_usable_focus(rebuilt_focus, panel), "forge retains a usable focus target after rebuilding rows")
	check(rebuilt_focus == null or is_instance_valid(rebuilt_focus), "forge rebuild does not retain a freed focus owner")
	ui.queue_free()
	await process_frame


func _test_responsive_ui() -> void:
	var original_size := root.size
	var ui := UI.new()
	root.add_child(ui)
	ui.setup_upgrades([
		Content.UPGRADES[0],
		Content.UPGRADES[1],
		Content.UPGRADES[2],
	])
	ui.setup_forge(999)
	await process_frame
	await process_frame
	var viewport_sizes := [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(1280, 800)]
	var panel_names := ["title", "pause", "reward", "gameover", "victory", "forge"]
	for viewport_size in viewport_sizes:
		root.size = viewport_size
		await process_frame
		await process_frame
		for panel_name in panel_names:
			ui.hide_all_panels()
			ui.show_panel(panel_name)
			await process_frame
			await process_frame
			_check_panel_layout(ui, panel_name, viewport_size)
	ui.queue_free()
	root.size = original_size
	await process_frame


func _check_panel_layout(ui: UI, panel_name: String, requested_size: Vector2i) -> void:
	var panel: Control = ui._panels.get(panel_name)
	check(panel != null and panel.visible, "%s panel is visible at %s" % [panel_name, requested_size])
	if panel == null:
		return
	var ui_rect: Rect2 = ui._root.get_global_rect()
	var dialog = panel.get_meta("dialog", null)
	check(dialog is Control and _rect_inside((dialog as Control).get_global_rect(), ui_rect), "%s dialog remains on-screen at %s" % [panel_name, requested_size])
	var controls: Array[Control] = []
	_collect_interactive_controls(panel, controls)
	check(not controls.is_empty(), "%s panel exposes interactive controls" % panel_name)
	for control in controls:
		var scroll := _scroll_ancestor(control, panel)
		if scroll != null:
			check(_rect_inside(scroll.get_global_rect(), ui_rect), "%s scroll viewport remains on-screen at %s" % [panel_name, requested_size])
		else:
			check(_rect_inside(control.get_global_rect(), ui_rect), "%s/%s remains on-screen at %s" % [panel_name, control.name, requested_size])


func _collect_interactive_controls(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is Button or child is CheckBox:
			var control := child as Control
			if control.visible:
				out.append(control)
		_collect_interactive_controls(child, out)


func _scroll_ancestor(control: Control, boundary: Node) -> ScrollContainer:
	var current := control.get_parent()
	while current != null and current != boundary:
		if current is ScrollContainer:
			return current as ScrollContainer
		current = current.get_parent()
	return null


func _is_usable_focus(control: Control, panel: Control) -> bool:
	if control == null or not is_instance_valid(control) or panel == null:
		return false
	if control != panel and not panel.is_ancestor_of(control):
		return false
	if not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
		return false
	return not (control is BaseButton) or not (control as BaseButton).disabled


func _test_enemy_scaling_and_elites() -> void:
	var enemy := Enemy.new()
	enemy.setup(Enemy.Kind.STALKER, Vector2(400, Content.FLOOR_Y - 40), { "hp_mul": 1.5, "dmg_mul": 1.2, "elite": true })
	root.add_child(enemy)
	var base: Dictionary = Content.ENEMY[Enemy.Kind.STALKER]
	check(enemy.elite, "elite flag is applied from spawn mods")
	check(is_equal_approx(enemy.hp_max, float(base.hp) * 1.5 * Content.ELITE_HP_MUL), "elite hp stacks difficulty and elite multipliers")
	check(is_equal_approx(enemy.attack_damage(), float(base.damage) * 1.2 * Content.ELITE_DMG_MUL), "elite damage stacks difficulty and elite multipliers")
	check(is_equal_approx(enemy._sprite.size_mul, Content.ELITE_SCALE), "elite body is drawn larger")
	var events: Array = []
	enemy.damaged.connect(func(amount: float, _pos: Vector2, blocked: bool): events.append([amount, blocked]))
	enemy.take_damage(10.0, Vector2.RIGHT, 0.0)
	check(events.size() == 1 and is_equal_approx(float(events[0][0]), 10.0) and not bool(events[0][1]), "enemy emits a damaged event for floating numbers")
	var score := [0]
	enemy.died.connect(func(s: int): score[0] = s)
	enemy.take_damage(99999.0, Vector2.RIGHT, 0.0)
	check(score[0] == int(base.score) * Content.ELITE_SCORE_MUL, "elite kills award multiplied score")
	enemy.queue_free()
	var brute := Enemy.new()
	brute.setup(Enemy.Kind.BRUTE, Vector2(600, Content.FLOOR_Y - 40))
	root.add_child(brute)
	brute.facing = 1.0
	var blocked_events: Array = []
	brute.damaged.connect(func(_amount: float, _pos: Vector2, blocked: bool): blocked_events.append(blocked))
	brute.take_damage(5.0, Vector2(-1.0, 0.0), 0.0)
	check(blocked_events.size() == 1 and bool(blocked_events[0]), "brute shield hits report as blocked")
	check(is_equal_approx(brute.hp, brute.hp_max), "blocked hits leave brute hp untouched")
	brute.queue_free()
	await process_frame


func _test_second_wind() -> void:
	var run_model := RunModel.new(8)
	run_model.apply_upgrade({ "id": "secondwind", "kind": "second_wind", "value": 1.0 })
	var player := Player.new()
	player.setup(run_model)
	root.add_child(player)
	var died := [0]
	var feedback_kinds: Array = []
	player.died.connect(func(): died[0] += 1)
	player.action_feedback.connect(func(kind: String, _pos: Vector2): feedback_kinds.append(kind))
	player.take_damage(99999.0, Vector2.RIGHT, 100.0)
	check(died[0] == 0 and not player.dead, "second wind survives a lethal hit")
	check(is_equal_approx(float(player.build.hp), float(player.build.max_hp) * Content.SECOND_WIND_HP_FRAC), "second wind restores the configured fraction of max hp")
	check(bool(run_model.build.second_wind_used), "second wind is spent on the run model")
	check(feedback_kinds.has("second_wind"), "second wind announces itself for feedback")
	player.iframes = 0.0
	player.take_damage(99999.0, Vector2.RIGHT, 100.0)
	check(died[0] == 1 and player.dead, "second wind only triggers once per run")
	player.queue_free()
	await process_frame


func _test_thorns_and_executioner() -> void:
	var run_model := RunModel.new(9)
	run_model.apply_upgrade({ "id": "thorns", "kind": "thorns", "value": 15.0 })
	run_model.apply_upgrade({ "id": "executioner", "kind": "execute", "value": 0.5 })
	var player := Player.new()
	player.setup(run_model)
	root.add_child(player)
	player.global_position = Vector2(500, Content.FLOOR_Y - 40)
	var near := Enemy.new()
	near.setup(Enemy.Kind.STALKER, Vector2(540, Content.FLOOR_Y - 40))
	root.add_child(near)
	var far := Enemy.new()
	far.setup(Enemy.Kind.STALKER, Vector2(900, Content.FLOOR_Y - 40))
	root.add_child(far)
	await physics_frame
	player.iframes = 0.0
	player.take_damage(5.0, Vector2.RIGHT, 50.0)
	check(is_equal_approx(near.hp, near.hp_max - 15.0), "cinder skin scorches an adjacent enemy")
	check(is_equal_approx(far.hp, far.hp_max), "cinder skin leaves distant enemies alone")
	check(is_equal_approx(player._damage_mul(far), 1.0), "executioner is inactive against healthy targets")
	far.hp = far.hp_max * 0.2
	check(is_equal_approx(player._damage_mul(far), 1.5), "executioner adds its bonus against low targets")
	check(player.momentum_stacks() == 0, "momentum is inert without the boon")
	run_model.apply_upgrade({ "id": "momentum", "kind": "momentum", "value": 0.12 })
	player.on_enemy_killed()
	player.on_enemy_killed()
	check(player.momentum_stacks() == 2 and is_equal_approx(player._speed_mul(), 1.0 + 0.24), "momentum stacks feed speed")
	check(is_equal_approx(player._damage_mul(), 1.2), "momentum stacks feed damage")
	for n in [player, near, far]:
		n.queue_free()
	await process_frame


func _test_pyre() -> void:
	Enemy.pyre_damage = 60.0
	var a := Enemy.new()
	a.setup(Enemy.Kind.STALKER, Vector2(500, Content.FLOOR_Y - 40))
	root.add_child(a)
	var b := Enemy.new()
	b.setup(Enemy.Kind.STALKER, Vector2(560, Content.FLOOR_Y - 40))
	root.add_child(b)
	var c := Enemy.new()
	c.setup(Enemy.Kind.STALKER, Vector2(1000, Content.FLOOR_Y - 40))
	root.add_child(c)
	await physics_frame
	var bursts := [0]
	a.pyre_burst.connect(func(_pos: Vector2, _radius: float): bursts[0] += 1)
	a.apply_burn(8.0, 3.0)
	a.take_damage(99999.0, Vector2.RIGHT, 0.0)
	check(bursts[0] == 1, "a burning enemy detonates when it dies")
	check(is_equal_approx(b.hp, b.hp_max - 60.0) and b.burn_time > 0.0, "pyre damages and ignites a neighbour")
	check(is_equal_approx(c.hp, c.hp_max), "pyre respects its radius")
	var d := Enemy.new()
	d.setup(Enemy.Kind.STALKER, Vector2(560, Content.FLOOR_Y - 40))
	root.add_child(d)
	var quiet := [0]
	d.pyre_burst.connect(func(_pos: Vector2, _radius: float): quiet[0] += 1)
	d.take_damage(99999.0, Vector2.RIGHT, 0.0)
	check(quiet[0] == 0, "an unburnt enemy does not detonate")
	Enemy.pyre_damage = 0.0
	for n in [a, b, c, d]:
		n.queue_free()
	await process_frame


func _test_boss_charge_and_summons() -> void:
	var boss := Boss.new()
	boss.intro_t = 0.01
	root.add_child(boss)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = Content.L_WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000, 100)
	shape.shape = rect
	floor_body.add_child(shape)
	floor_body.position = Vector2(640, Content.FLOOR_Y + 50)
	root.add_child(floor_body)
	boss.global_position = Vector2(400, Content.FLOOR_Y - Content.BOSS_H * 0.5)
	await physics_frame
	await physics_frame
	boss.facing = 1.0
	boss._begin_charge()
	check(boss.state == Enemy.EState.WINDUP and boss.action_idx == Boss.Action.CHARGE, "boss can enter a charge windup")
	boss._do_charge()
	check(boss.state == Enemy.EState.ATTACK and boss.velocity.x > 0.0, "charge commits with forward velocity")
	var start_x := boss.global_position.x
	var guard := 0
	while boss.state == Enemy.EState.ATTACK and guard < 120:
		await physics_frame
		guard += 1
	check(boss.state == Enemy.EState.RECOVER, "charge ends in recovery")
	check(boss.global_position.x > start_x + 200.0, "charge covers real ground")
	check(not boss._atk_area.monitoring, "charge disarms its hitbox when it ends")
	var summons: Array = []
	boss.summon_requested.connect(func(kind: int, pos: Vector2): summons.append([kind, pos]))
	boss.hp = boss.max_hp * 0.4
	boss._check_phase2()
	check(boss.phase == Boss.BPhase.TWO, "boss enters phase two below half health")
	check(summons.size() == 2 and int(summons[0][0]) == Content.BOSS_SUMMON_KIND, "phase two summons two wisps")
	boss._check_phase2()
	check(summons.size() == 2, "summons only happen once")
	boss.queue_free()
	floor_body.queue_free()
	await process_frame


func _test_boss_room_adds() -> void:
	var player_stub := Node2D.new()
	root.add_child(player_stub)
	var room := Room.new()
	room.setup(Content.BOSS_TEMPLATE, true, player_stub, 1357)
	room.set_meta("room_index", Content.ROOMS_BEFORE_BOSS + 1)
	var completed := [0]
	var cleared := [0]
	var deaths: Array = []
	room.completed.connect(func(): completed[0] += 1)
	room.cleared.connect(func(_n: String): cleared[0] += 1)
	room.enemy_died.connect(func(score: int, _pos: Vector2, tier: int, _color: Color): deaths.append([score, tier]))
	root.add_child(room)
	check(room.boss != null and is_instance_valid(room.boss), "boss room spawns its boss")
	room._on_boss_summon(Content.BOSS_SUMMON_KIND, Vector2(300, Content.FLOOR_Y - 260))
	check(room.enemies.size() == 1, "boss summons register as room enemies")
	var add: Node = room.enemies[0]
	check(float(add.hp_max) > float(Content.ENEMY[Content.BOSS_SUMMON_KIND].hp), "summoned adds inherit the room's difficulty scaling")
	add.take_damage(99999.0, Vector2.RIGHT, 0.0)
	check(completed[0] == 0 and cleared[0] == 0 and not room.exit_open, "killing an add never clears or unseals the throne room")
	check(deaths.size() == 1 and int(deaths[0][1]) == 0, "add death reports as a regular kill")
	room.boss.take_damage(99999.0, Vector2.RIGHT, 0.0)
	check(completed[0] == 1, "boss death completes the room")
	check(deaths.size() == 2 and int(deaths[1][1]) == 2, "boss death reports the boss tier")
	room.queue_free()
	player_stub.queue_free()
	await process_frame


func _test_room_dressing() -> void:
	var player_stub := Node2D.new()
	root.add_child(player_stub)
	var spawned: Array = []
	var room := Room.new()
	room.mood = Content.mood_for(0.4)
	room.setup(Content.ROOM_TEMPLATES[1], false, player_stub, 99)
	room.set_meta("room_index", 1)
	room.enemy_spawned.connect(func(pos: Vector2, color: Color): spawned.append([pos, color]))
	root.add_child(room)
	check(spawned.size() == room.enemies.size() and spawned.size() > 0, "every spawned enemy announces a rift position")
	check(room.exit_center() == room._exit_rect.get_center(), "exit_center exposes the rift gate position")
	var lights: Array = room.light_points()
	for lp in lights:
		check(lp.has("pos") and lp.has("radius") and lp.has("color") and lp.has("alpha"), "room light points carry the light layer fields")
	room.queue_free()
	var throne := Room.new()
	throne.mood = Content.mood_for(1.0)
	throne.setup(Content.BOSS_TEMPLATE, true, player_stub, 7)
	throne.set_meta("room_index", Content.ROOMS_BEFORE_BOSS + 1)
	root.add_child(throne)
	check(throne.light_points().size() >= 3, "the throne room lights its braziers")
	throne.queue_free()
	player_stub.queue_free()
	await process_frame


func _test_music_renders() -> void:
	var music = MusicSynth.new()
	root.add_child(music)
	var waited := 0
	while not music.is_ready() and waited < 1800:
		await process_frame
		waited += 1
	check(music.is_ready(), "procedural score finishes rendering in the background")
	if music.is_ready():
		for name in ["explore", "boss"]:
			var player: AudioStreamPlayer = music._players[name]
			var stream := player.stream as AudioStreamWAV
			check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s track is a seamless loop" % name)
			if stream != null:
				var data := stream.data
				var peak := 0
				var stride := maxi(2, (data.size() / 2 / 400) * 2)
				for i in range(0, data.size() - 1, stride):
					peak = maxi(peak, absi(data.decode_s16(i)))
				check(peak > 4000 and peak < 32700, "%s track has healthy level (peak %d)" % [name, peak])
		music.play_track("boss")
		check(music._current == "boss", "track switching records the active cue")
	music.queue_free()
	await process_frame


## Drives a whole run headlessly: clear every chamber, take boons, fell the boss.
func _test_full_run_simulation() -> void:
	var packed = load("res://main.tscn")
	var game: Game = packed.instantiate()
	root.add_child(game)
	await process_frame
	var cells_before := Save.get_cells()
	game._on_start()
	await physics_frame
	check(game.state == Game.GState.PLAYING and is_instance_valid(game.room), "simulated run starts in its first chamber")
	var rooms_visited := 0
	var saw_numbers := false
	var saw_streak := false
	var guard := 0
	while game.state != Game.GState.VICTORY and game.state != Game.GState.GAME_OVER and guard < 4000:
		guard += 1
		var room: Room = game.room
		if not is_instance_valid(room):
			await physics_frame
			continue
		if room.is_boss:
			if room.boss != null and is_instance_valid(room.boss) and not room.boss.dead:
				if room.boss.phase == Boss.BPhase.INTRO:
					await physics_frame
					continue
				room.boss.take_damage(room.boss.max_hp * 0.3, Vector2.RIGHT, 0.0)
				for e in room.enemies.duplicate():
					if is_instance_valid(e) and not e.dead:
						e.take_damage(99999.0, Vector2.RIGHT, 0.0)
			await physics_frame
			continue
		if room.exit_open:
			rooms_visited += 1
			game._on_room_completed()
			await process_frame
			check(game.state == Game.GState.REWARD and game._pending_upgrades.size() == Content.UPGRADES_PER_OFFER, "clearing a chamber offers boons")
			game._on_upgrade_selected(0)
			await physics_frame
			continue
		var alive := 0
		for e in room.enemies.duplicate():
			if is_instance_valid(e) and not e.dead:
				alive += 1
				e.take_damage(6.0, Vector2.RIGHT, 0.0)
				e.take_damage(99999.0, Vector2.RIGHT, 0.0)
		if alive > 0:
			for p in game.feedback._particles:
				if str(p.get("kind", "")) == "number":
					saw_numbers = true
			if game._streak_kills >= 2:
				saw_streak = true
		await physics_frame
	check(game.state == Game.GState.VICTORY, "simulated run reaches victory (guard %d)" % guard)
	check(rooms_visited == Content.ROOMS_BEFORE_BOSS + 1, "every combat chamber was cleared before the throne")
	check(saw_numbers, "hits spawn floating damage numbers")
	check(saw_streak, "chained kills build a streak")
	check(int(game._stats.kills) > 0 and float(game._stats.damage_dealt) > 0.0, "run statistics accumulate")
	check(int(game._stats.rooms) == game.run.rooms_total(), "run statistics record the final chamber")
	check(Save.get_cells() > cells_before, "a run banks cells")
	check(game.music._current == "title", "victory returns the score to the title cue")
	game.queue_free()
	await process_frame


func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	var tolerance := 1.0
	return (
		inner.size.x > 0.0
		and inner.size.y > 0.0
		and inner.position.x >= outer.position.x - tolerance
		and inner.position.y >= outer.position.y - tolerance
		and inner.end.x <= outer.end.x + tolerance
		and inner.end.y <= outer.end.y + tolerance
	)
