class_name Game
extends Node2D
## Root orchestrator: run lifecycle, room replacement, signal routing, pause, background.

enum GState { TITLE, PLAYING, REWARD, GAME_OVER, VICTORY }

var state: int = GState.TITLE
var run: RunModel
var world: Node2D
var projectiles: Node2D
var room: Room
var player: Player
var feedback: Feedback
var ui: UI
var score: int = 0
var paused: bool = false
var _pending_upgrades: Array = []
var _seed: int = 0
var _bg_grad: Gradient
var _run_cells: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Background gradient
	_bg_grad = Gradient.new()
	_bg_grad.set_color(0, Content.PAL.bg_top)
	_bg_grad.set_color(1, Content.PAL.bg_bot)
	# World (pausable)
	world = Node2D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	projectiles = Node2D.new()
	projectiles.name = "Projectiles"
	projectiles.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_child(projectiles)
	# Feedback (pausable)
	feedback = Feedback.new()
	feedback.name = "Feedback"
	feedback.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(feedback)
	# UI (always)
	ui = UI.new()
	ui.name = "UI"
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	# Wire UI signals
	ui.start_requested.connect(_on_start)
	ui.resume_requested.connect(_on_resume)
	ui.restart_requested.connect(_on_restart)
	ui.quit_to_title_requested.connect(_on_quit_to_title)
	ui.upgrade_selected.connect(_on_upgrade_selected)
	ui.option_toggled.connect(_on_option_toggled)
	ui.forge_requested.connect(_on_forge_requested)
	ui.buy_meta_requested.connect(_on_buy_meta)
	ui.back_from_forge_requested.connect(_on_back_from_forge)
	# Show saved cells + best score on the HUD
	ui.set_cells(Save.get_cells())
	ui.set_best(Save.get_best_score())
	# Seed
	randomize()
	_seed = randi()
	set_process(true)

func _process(delta: float) -> void:
	if state == GState.PLAYING and is_instance_valid(player):
		# Camera follows player, clamped to room bounds
		var cam := feedback.camera
		var target := player.global_position
		var lim_l := Content.ROOM_LEFT + Content.VIEW_W * 0.5
		var lim_r := Content.ROOM_RIGHT - Content.VIEW_W * 0.5
		target.x = clampf(target.x, lim_l, lim_r)
		target.y = clampf(target.y, 200, Content.FLOOR_Y - 80)
		cam.global_position = cam.global_position.lerp(target, 8.0 * delta)
		# Update boss HP bar every frame
		if is_instance_valid(room) and room.boss != null and is_instance_valid(room.boss) and not room.boss.dead:
			ui.update_boss_bar(room.boss.hp)
		# Check player death handled by signal; check fall off world
		if player.global_position.y > Content.FLOOR_Y + 240:
			player.take_damage(9999.0, Vector2.UP, 0.0)

func _draw() -> void:
	# Background gradient covering room area
	var gtl := Vector2(Content.ROOM_LEFT, -400)
	var gbr := Vector2(Content.ROOM_RIGHT, Content.FLOOR_Y + 160)
	var n := 48
	for i in range(n):
		var t := float(i) / float(n)
		var c := _bg_grad.sample(t)
		var y0 := gtl.y + t * (gbr.y - gtl.y)
		var y1 := gtl.y + (float(i + 1) / float(n)) * (gbr.y - gtl.y)
		draw_rect(Rect2(gtl.x, y0, gbr.x - gtl.x, y1 - y0), c)
	# distant parallax glow
	var glow := Color(0.5, 0.3, 0.5, 0.06)
	draw_circle(Vector2(640, 120), 320.0, glow)

# --- Run lifecycle ---
func _on_start() -> void:
	_begin_run()

func _on_restart() -> void:
	_begin_run()

func _begin_run() -> void:
	# cleanup
	_clear_room()
	_clear_projectiles()
	if is_instance_valid(player):
		player.queue_free()
		player = null
	score = 0
	_run_cells = 0
	_seed = randi()
	run = RunModel.new(_seed)
	# Apply meta-progression modifiers from the save
	var meta: Dictionary = Save.get_meta_modifiers()
	run.build.max_hp = float(run.build.max_hp) + float(meta.get("max_hp", 0.0))
	run.build.hp = run.build.max_hp
	run.build.speed_mul = float(run.build.speed_mul) + float(meta.get("speed_mul", 0.0))
	run.build.dmg_mul = float(run.build.dmg_mul) + float(meta.get("dmg_mul", 0.0))
	run.build.flask_charges = int(run.build.flask_charges) + int(meta.get("flask", 0))
	run.build.special_start = float(meta.get("special_start", 0.0))
	# create player
	player = Player.new()
	player.add_to_group("player")
	player.setup(run)
	world.add_child(player)
	# wire player signals once
	player.hp_changed.connect(ui.set_hp)
	player.special_changed.connect(ui.set_special)
	player.hit_landed.connect(_on_player_hit)
	player.projectile_requested.connect(_on_player_projectile)
	player.died.connect(_on_player_died)
	player.slam_landed.connect(_on_slam_landed)
	player.parried.connect(_on_parried)
	player.flask_changed.connect(ui.set_flask)
	# first room
	_advance_room()
	ui.set_score(score)
	ui.hide_all_panels()
	ui.hide_boss_bar()
	get_tree().paused = false
	paused = false
	state = GState.PLAYING

func _advance_room() -> void:
	_clear_room()
	var tmpl := run.advance_to_next_room()
	var is_boss := run.is_boss_room()
	room = Room.new()
	room.setup(tmpl, is_boss, player, run.rng.randi())
	room.set_meta("room_index", run.room_index)
	world.add_child(room)
	# wire room signals
	room.completed.connect(_on_room_completed)
	room.enemy_died.connect(_on_enemy_died)
	room.projectile_requested.connect(_on_enemy_projectile)
	room.boss_spawned.connect(_on_boss_spawned)
	room.boss_phase_changed.connect(_on_boss_phase)
	room.enemy_exploded.connect(_on_enemy_exploded)
	# position player at entry
	var entry := room.get_entry_point()
	player.respawn_at(entry)
	# UI
	ui.set_room(run.room_index, run.rooms_total())
	if is_boss:
		ui.set_room(run.room_index, run.rooms_total())
	player.build = run.build

func _clear_room() -> void:
	if is_instance_valid(room):
		room.despawn()
		room = null

func _clear_projectiles() -> void:
	if is_instance_valid(projectiles):
		for c in projectiles.get_children():
			c.queue_free()

# --- Signal handlers ---
func _on_player_hit(dmg: float) -> void:
	feedback.flash_hit(player.global_position + Vector2(player.facing * 20, -10))
	feedback.shake(4.0, 0.12)
	feedback.play("hit")

func _on_player_projectile(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color) -> void:
	_spawn_projectile(team, pos, vel, dmg, kb, pierce, life, color)
	feedback.play("shoot")

func _on_enemy_projectile(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color) -> void:
	_spawn_projectile(team, pos, vel, dmg, kb, pierce, life, color)

func _spawn_projectile(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color) -> void:
	var p := Projectile.new()
	projectiles.add_child(p)
	p.setup(team, pos, vel, dmg, kb, pierce, life, color)

func _on_enemy_died(sc: int) -> void:
	score += sc
	ui.set_score(score)
	# Award cells (1 per regular enemy; 10 for boss)
	var cells_gain := 1
	if is_instance_valid(room) and room.boss != null and is_instance_valid(room.boss) and room.boss.dead:
		cells_gain = 10
	_run_cells += cells_gain
	Save.add_cells(cells_gain)
	ui.set_cells(Save.get_cells())
	# find the dead enemy position for effects via room
	if is_instance_valid(room):
		for e in room.enemies:
			if is_instance_valid(e) and e.dead:
				feedback.flash_death(e.global_position, e.data.color)
		if room.boss != null and is_instance_valid(room.boss) and room.boss.dead:
			feedback.flash_death(room.boss.global_position, Content.BOSS_COLOR)
			feedback.shake(16.0, 0.5)
			feedback.play("die")
	feedback.shake(6.0, 0.18)
	feedback.play("die")

func _on_room_completed() -> void:
	feedback.play("clear")
	if run.is_boss_room():
		_victory()
		return
	# offer upgrades
	_pending_upgrades = run.roll_upgrades()
	ui.setup_upgrades(_pending_upgrades)
	ui.show_panel("reward")
	get_tree().paused = true
	state = GState.REWARD

func _on_upgrade_selected(idx: int) -> void:
	if idx < 0 or idx >= _pending_upgrades.size():
		return
	run.apply_upgrade(_pending_upgrades[idx])
	player.build = run.build
	ui.set_hp(float(run.build.hp), float(run.build.max_hp))
	# Flask charges may have changed via upgrade
	if run.build.has("flask_charges"):
		player.flask_max = int(run.build.flask_charges)
	_pending_upgrades.clear()
	ui.hide_panel("reward")
	run.room_cleared()
	_advance_room()
	# Refill flask between rooms (Dead Cells-style)
	if Content.FLASK_REFILL_ON_CLEAR:
		player.refill_flask()
	get_tree().paused = false
	state = GState.PLAYING

func _on_player_died() -> void:
	feedback.flash_death(player.global_position, Content.PAL.player)
	feedback.shake(12.0, 0.4)
	feedback.play("die")
	# Persist best score + show cells earned
	Save.set_best_score(score)
	ui.set_best(Save.get_best_score())
	ui.show_run_cells(_run_cells, "gameover")
	get_tree().paused = true
	state = GState.GAME_OVER
	ui.hide_boss_bar()
	ui.show_panel("gameover")

func _on_boss_spawned() -> void:
	if is_instance_valid(room) and room.boss != null:
		ui.show_boss_bar(Content.BOSS_HP)
		feedback.shake(8.0, 0.3)
		feedback.play("boss")

func _on_boss_phase(phase: int) -> void:
	feedback.shake(10.0, 0.35)
	feedback.play("boss")

func _on_slam_landed(pos: Vector2, radius: float) -> void:
	feedback.shake(8.0, 0.22)
	feedback.burst(pos, 18, Content.PAL.attack, 320.0)
	feedback.play("die")

func _on_parried(pos: Vector2, success: bool) -> void:
	if success:
		feedback.flash_hit(pos)
		feedback.shake(3.0, 0.08)
		feedback.play("hit")
	else:
		feedback.play("dash")

func _on_enemy_exploded(pos: Vector2, radius: float, damage: float) -> void:
	feedback.shake(10.0, 0.3)
	feedback.burst(pos, 26, Color("ff7a18"), 360.0)
	feedback.play("die")

func _victory() -> void:
	# Bonus cells for clearing the run
	var bonus := 20
	_run_cells += bonus
	Save.add_cells(bonus)
	Save.set_best_score(score)
	get_tree().paused = true
	state = GState.VICTORY
	ui.hide_boss_bar()
	ui.show_run_cells(_run_cells, "victory")
	ui.show_panel("victory")

# --- Pause ---
func _on_resume() -> void:
	if state != GState.PLAYING: return
	get_tree().paused = false
	paused = false
	ui.hide_panel("pause")

func _on_quit_to_title() -> void:
	get_tree().paused = false
	paused = false
	_clear_room()
	_clear_projectiles()
	if is_instance_valid(player):
		player.queue_free()
		player = null
	ui.hide_boss_bar()
	ui.hide_all_panels()
	ui.show_panel("title")
	state = GState.TITLE

func _on_option_toggled(key: String, value: bool) -> void:
	match key:
		"reduced_motion": feedback.set_reduced_motion(value)
		"reduced_flash": feedback.set_reduced_flash(value)

func _on_forge_requested() -> void:
	ui.hide_all_panels()
	ui.setup_forge(Save.get_cells())
	ui.show_panel("forge")

func _on_buy_meta(idx: int) -> void:
	if idx < 0 or idx >= Content.META_UPGRADES.size():
		return
	var u: Dictionary = Content.META_UPGRADES[idx]
	if Save.purchase_meta(u.id):
		feedback.play("pickup")
	# Refresh the forge panel + HUD
	ui.setup_forge(Save.get_cells())
	ui.set_cells(Save.get_cells())

func _on_back_from_forge() -> void:
	ui.hide_all_panels()
	ui.show_panel("title")
	ui.set_cells(Save.get_cells())
	ui.set_best(Save.get_best_score())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and state == GState.PLAYING:
		if not paused:
			get_tree().paused = true
			paused = true
			ui.show_panel("pause")
		else:
			_on_resume()
		get_viewport().set_input_as_handled()
