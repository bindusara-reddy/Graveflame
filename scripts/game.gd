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
	RenderingServer.set_default_clear_color(Content.PAL.bg_bot)
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
	queue_redraw()
	if state == GState.PLAYING and is_instance_valid(player):
		# Camera follows player, clamped to room bounds
		var cam := feedback.camera
		var target := _camera_target_for(player.global_position)
		cam.global_position = cam.global_position.lerp(target, 8.0 * delta)
		# Update boss HP bar every frame
		if is_instance_valid(room) and room.boss != null and is_instance_valid(room.boss) and not room.boss.dead:
			ui.update_boss_bar(room.boss.hp)
		# Check player death handled by signal; check fall off world
		if player.global_position.y > Content.FLOOR_Y + 240:
			player.take_damage(9999.0, Vector2.UP, 0.0)

func _draw() -> void:
	# Layered original crypt-city backdrop. It stays vector-only, but the broad
	# silhouettes, furnace bloom, chains and drifting ash create real depth.
	var gtl := Vector2(Content.ROOM_LEFT, -400)
	# Camera can ease down to y=520, so cover well beyond the viewport bottom.
	var gbr := Vector2(Content.ROOM_RIGHT, Content.FLOOR_Y + 480)
	var n := 48
	for i in range(n):
		var t := float(i) / float(n)
		var c := _bg_grad.sample(t)
		var y0 := gtl.y + t * (gbr.y - gtl.y)
		var y1 := gtl.y + (float(i + 1) / float(n)) * (gbr.y - gtl.y)
		draw_rect(Rect2(gtl.x, y0, gbr.x - gtl.x, y1 - y0), c)
	var now := float(Time.get_ticks_msec()) * 0.001
	# Distant Graveflame furnace.
	for i in range(5, 0, -1):
		var rad := 70.0 + float(i) * 58.0
		draw_circle(Vector2(770.0, 250.0), rad, Color(0.72, 0.18, 0.12, 0.012 + float(6 - i) * 0.008))
	# Far prison skyline and uneven roofs.
	var skyline := PackedVector2Array([
		Vector2(-200, 470), Vector2(-200, 280), Vector2(-120, 240), Vector2(-40, 315),
		Vector2(55, 210), Vector2(145, 300), Vector2(250, 185), Vector2(340, 300),
		Vector2(455, 245), Vector2(560, 310), Vector2(670, 170), Vector2(755, 290),
		Vector2(865, 220), Vector2(965, 310), Vector2(1080, 190), Vector2(1175, 275),
		Vector2(1285, 225), Vector2(1480, 300), Vector2(1480, 560), Vector2(-200, 560),
	])
	draw_colored_polygon(skyline, Color("15111e"))
	# Slit windows, arches and bridges make the silhouette read as architecture.
	for i in range(13):
		var x := -120.0 + float(i) * 132.0
		var top := 290.0 + float((i * 37) % 90)
		draw_rect(Rect2(x, top, 10.0, 58.0), Color(0.65, 0.24, 0.16, 0.15 + float(i % 3) * 0.04))
		draw_arc(Vector2(x + 5.0, top), 5.0, PI, TAU, 8, Color(0.75, 0.32, 0.18, 0.18), 2.0)
	for i in range(7):
		var arch_x := -70.0 + float(i) * 245.0
		draw_arc(Vector2(arch_x, 500.0), 78.0, PI, TAU, 24, Color(0.30, 0.25, 0.36, 0.16), 14.0)
		draw_line(Vector2(arch_x - 78.0, 500.0), Vector2(arch_x - 78.0, 590.0), Color(0.30, 0.25, 0.36, 0.14), 14.0)
		draw_line(Vector2(arch_x + 78.0, 500.0), Vector2(arch_x + 78.0, 590.0), Color(0.30, 0.25, 0.36, 0.14), 14.0)
	# Hanging chains, each with a different deterministic sway.
	for chain in range(8):
		var cx := -80.0 + float(chain) * 225.0
		var length := 95 + (chain * 43) % 150
		var sway := sin(now * 0.7 + float(chain)) * 5.0
		var pts := PackedVector2Array()
		for link in range(8):
			var lt := float(link) / 7.0
			pts.append(Vector2(cx + sway * lt, -80.0 + float(length) * lt))
		draw_polyline(pts, Color(0.40, 0.36, 0.46, 0.22), 2.0, true)
	# Slow ash motes are positional and deterministic, so reduced motion can leave
	# the gameplay feedback quiet without making the scene sterile.
	for mote in range(34):
		var mx := Content.ROOM_LEFT + fmod(float(mote * 173) + now * (4.0 + float(mote % 5)), Content.ROOM_RIGHT - Content.ROOM_LEFT)
		var my := -80.0 + fmod(float(mote * 91) + now * (8.0 + float(mote % 4)), 620.0)
		var ma := 0.12 + float(mote % 4) * 0.035
		draw_circle(Vector2(mx, my), 1.0 + float(mote % 3) * 0.45, Color(0.82, 0.62, 0.48, ma))
	# Low fog bands separate the walkable plane from the backdrop.
	for band in range(4):
		var fy := 500.0 + float(band) * 30.0 + sin(now * 0.25 + float(band)) * 5.0
		draw_rect(Rect2(Content.ROOM_LEFT, fy, Content.ROOM_RIGHT - Content.ROOM_LEFT, 42.0), Color(0.34, 0.28, 0.39, 0.025))

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
	# Wire before entering the tree so _ready()'s initial resource signals are not lost.
	player.hp_changed.connect(ui.set_hp)
	player.special_changed.connect(ui.set_special)
	player.hit_landed.connect(_on_player_hit)
	player.projectile_requested.connect(_on_player_projectile)
	player.died.connect(_on_player_died)
	player.slam_landed.connect(_on_slam_landed)
	player.parried.connect(_on_parried)
	player.flask_changed.connect(ui.set_flask)
	player.hurt_taken.connect(_on_player_hurt)
	player.action_feedback.connect(_on_player_action)
	world.add_child(player)
	# Resolve the player's parry scan before projectile/enemy hit checks each tick.
	world.move_child(player, 0)
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
	_clear_projectiles()
	ui.hide_room_clear()
	var tmpl := run.advance_to_next_room()
	var is_boss := run.is_boss_room()
	room = Room.new()
	room.setup(tmpl, is_boss, player, run.rng.randi())
	room.set_meta("room_index", run.room_index)
	# Connect before _ready() because boss_spawned and wave_started happen there.
	room.completed.connect(_on_room_completed)
	room.cleared.connect(_on_room_cleared)
	room.enemy_died.connect(_on_enemy_died)
	room.projectile_requested.connect(_on_enemy_projectile)
	room.boss_spawned.connect(_on_boss_spawned)
	room.boss_phase_changed.connect(_on_boss_phase)
	room.enemy_exploded.connect(_on_enemy_exploded)
	world.add_child(room)
	# position player at entry
	var entry := room.get_entry_point()
	player.respawn_at(entry)
	player.suppress_gameplay_input()
	# Snap across the rift instead of briefly lerping from the previous exit.
	feedback.camera.global_position = _camera_target_for(entry)
	# UI
	ui.set_room(run.room_index, run.rooms_total())
	if is_boss:
		ui.set_room(run.room_index, run.rooms_total())
	player.build = run.build

func _camera_target_for(pos: Vector2) -> Vector2:
	var target := pos
	var lim_l := Content.ROOM_LEFT + Content.VIEW_W * 0.5
	var lim_r := Content.ROOM_RIGHT - Content.VIEW_W * 0.5
	target.x = clampf(target.x, lim_l, lim_r)
	target.y = clampf(target.y, 200.0, Content.FLOOR_Y - 80.0)
	return target

func _clear_room() -> void:
	if is_instance_valid(room):
		room.despawn()
		room = null

func _clear_projectiles() -> void:
	if is_instance_valid(projectiles):
		for c in projectiles.get_children():
			c.queue_free()

# --- Signal handlers ---
func _on_player_hit(dmg: float, pos: Vector2, heavy: bool) -> void:
	feedback.impact(pos, Content.PAL.player_accent if player._flame_time > 0.0 else Content.PAL.attack, heavy)
	feedback.hit_stop(0.065 if heavy else 0.045)
	feedback.shake(6.0 if heavy else 3.0, 0.14 if heavy else 0.08)
	feedback.play("hit")

func _on_player_hurt(amount: float, pos: Vector2) -> void:
	feedback.flash_hurt(pos)
	feedback.shake(7.0, 0.18)
	feedback.play("hurt")

func _on_player_action(kind: String, pos: Vector2) -> void:
	match kind:
		"swing":
			feedback.play("swing")
			feedback.slash(pos + Vector2(player.facing * 28.0, -8.0), player.facing, Content.PAL.player_accent if player._flame_time > 0.0 else Content.PAL.attack, player.attack_index == Content.COMBO.size() - 1)
		"jump": feedback.play("jump")
		"dash":
			feedback.play("dash")
			feedback.afterimage(pos, player.facing, Content.PAL.player)
		"parry_start": feedback.play("shield")
		"heal": feedback.play("heal")
		"flame":
			feedback.play("flame")
			feedback.burst(pos, 28, Content.PAL.player_accent, 300.0)
			feedback.shake(5.0, 0.2)
		"slam": feedback.play("swing")
		_: pass

func _on_player_projectile(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color) -> void:
	_spawn_projectile(team, pos, vel, dmg, kb, pierce, life, color)
	feedback.play("shoot")

func _on_enemy_projectile(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color) -> void:
	_spawn_projectile(team, pos, vel, dmg, kb, pierce, life, color)

func _spawn_projectile(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color) -> void:
	var p := Projectile.new()
	p.setup(team, pos, vel, dmg, kb, pierce, life, color)
	projectiles.add_child(p)

func _on_enemy_died(sc: int) -> void:
	# Falling out of a pit is cleanup, not a player kill or a cell reward.
	if sc <= 0:
		return
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
	var boss_death := false
	if is_instance_valid(room):
		for e in room.enemies:
			if is_instance_valid(e) and e.dead:
				feedback.flash_death(e.global_position, e.data.color)
		if room.boss != null and is_instance_valid(room.boss) and room.boss.dead:
			boss_death = true
			feedback.flash_death(room.boss.global_position, Content.BOSS_COLOR)
			feedback.shake(16.0, 0.5)
			feedback.play("die")
	if boss_death:
		return
	feedback.shake(6.0, 0.18)
	feedback.play("die")

func _on_room_cleared(room_name: String) -> void:
	feedback.play("clear")
	ui.show_room_clear(room_name)

func _on_room_completed() -> void:
	ui.hide_room_clear()
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
	feedback.land_dust(pos, 1.4)
	feedback.play("land")

func _on_parried(pos: Vector2, success: bool) -> void:
	if success:
		feedback.impact(pos, Content.PAL.special, true)
		feedback.hit_stop(0.065)
		feedback.shake(4.0, 0.1)
		feedback.play("parry")

func _on_enemy_exploded(pos: Vector2, radius: float, damage: float) -> void:
	if damage <= 0.0:
		feedback.shake(6.0, 0.16)
		feedback.land_dust(pos, clampf(radius / 70.0, 1.0, 2.0))
		feedback.play("land")
		return
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
	if is_instance_valid(player):
		player.suppress_gameplay_input()
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
