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


func _run() -> void:
	await process_frame
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
