class_name Game
extends Node2D
## Root orchestrator: run lifecycle, room replacement, signal routing, pause, background.

const VFX := preload("res://scripts/vfx.gd")

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
# Visual layers. Lights and ambience are inserted before World so they draw above
# the backdrop but beneath platforms, actors and combat VFX.
const TORCH_Y := Content.FLOOR_Y - 200.0
var _light_layer: Node2D
var _atmosphere: Node2D
var _vignette: CanvasLayer
var _view_center := Vector2(Content.VIEW_W, Content.VIEW_H) * 0.5
var _atmo_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_default_clear_color(Content.PAL.bg_top)
	# Sky gradient: void above, crypt navy through the arches, warm at the floor line.
	_bg_grad = Gradient.new()
	_bg_grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	_bg_grad.colors = PackedColorArray([Content.PAL.bg_top, Content.PAL.bg_mid, Content.PAL.bg_bot])
	# Additive lights and ambient particles (pausable, like the world they belong to).
	_light_layer = load("res://scripts/light_layer.gd").new()
	_light_layer.name = "LightLayer"
	_light_layer.game = self
	_light_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_light_layer)
	_atmosphere = load("res://scripts/atmosphere.gd").new()
	_atmosphere.name = "Atmosphere"
	_atmosphere.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_atmosphere)
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
	# Fullscreen vignette. Layer 40 keeps it beneath the HUD (layer 50) so the
	# corner panels never lose contrast.
	_vignette = CanvasLayer.new()
	_vignette.name = "Vignette"
	_vignette.layer = 40
	var vignette_rect := ColorRect.new()
	vignette_rect.name = "VignetteRect"
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_rect.material = VFX.vignette_material()
	_vignette.add_child(vignette_rect)
	vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_vignette)
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
	_atmosphere.global_position = _view_center
	if not get_tree().paused and not Feedback.motion_reduced:
		_atmo_t += delta
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
	# Camera-driven parallax crypt. Each plane is shifted by (1 - depth) of the
	# view centre, so far planes crawl while near planes track the world. Read the
	# camera here (draw runs after every _process) so nothing lags a frame.
	_view_center = feedback.camera.get_screen_center_position()
	var left := Content.ROOM_LEFT - 240.0
	var right := Content.ROOM_RIGHT + 240.0
	var span := right - left
	var top := -560.0
	var horizon := Content.FLOOR_Y
	# Sky.
	for i in range(_bg_grad.get_point_count() - 1):
		var y0 := lerpf(top, horizon, _bg_grad.get_offset(i))
		var y1 := lerpf(top, horizon, _bg_grad.get_offset(i + 1))
		VFX.draw_vgradient(self, Rect2(left, y0, span, y1 - y0), _bg_grad.get_color(i), _bg_grad.get_color(i + 1))
	# Under-floor pit: the floor line falls away into absolute void.
	VFX.draw_vgradient(self, Rect2(left, horizon, span, 320.0), Content.PAL.bg_bot, Content.PAL.bg_pit)
	draw_rect(Rect2(left, horizon + 320.0, span, 520.0), Content.PAL.bg_pit)
	# Distant furnace bloom low on the horizon, behind the spires.
	var bloom := Vector2(_plane_x(0.1, 184.0), horizon - 60.0)
	for i in range(4, 0, -1):
		draw_circle(bloom, 90.0 + float(i) * 72.0, Color(0.85, 0.25, 0.08, 0.016 + float(5 - i) * 0.012))
	_draw_spires(horizon)
	_draw_arches(horizon)
	_draw_buttresses(horizon)
	_draw_fog(horizon)

## Visible repeat-index range for a plane at `depth` whose elements repeat every `period`.
func _plane_range(depth: float, period: float, margin: float) -> Vector2i:
	var half := get_viewport_rect().size.x * 0.5 + margin
	return Vector2i(floori((_view_center.x * depth - half) / period), ceili((_view_center.x * depth + half) / period))

func _plane_x(depth: float, layer_x: float) -> float:
	return layer_x + _view_center.x * (1.0 - depth)

## Sconce flame positions on the midground buttresses; the light layer stacks
## its torch glows on exactly these points.
func torch_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	var r := _plane_range(0.65, 320.0, 160.0)
	for k in range(r.x, r.y + 1):
		out.append(Vector2(_plane_x(0.65, float(k) * 320.0), TORCH_Y - 12.0))
	return out

func _draw_spires(horizon: float) -> void:
	var depth := 0.15
	var period := 150.0
	var col := Color("0b0714")
	var r := _plane_range(depth, period, 120.0)
	var base := horizon + 80.0
	var mass_top := horizon - 150.0
	draw_rect(Rect2(_plane_x(depth, float(r.x) * period) - period, mass_top, float(r.y - r.x + 2) * period, base - mass_top), col)
	for k in range(r.x, r.y + 1):
		var h := 300.0 + VFX.hash01(k, 1) * 120.0
		var w := 58.0 + VFX.hash01(k, 2) * 32.0
		var x := _plane_x(depth, float(k) * period + VFX.hash01(k, 3) * 40.0)
		var spire_top := base - h
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - w * 0.5, base), Vector2(x - w * 0.5, spire_top + 40.0), Vector2(x - w * 0.28, spire_top + 14.0),
			Vector2(x - w * 0.1, spire_top + 4.0), Vector2(x, spire_top - 26.0), Vector2(x + w * 0.1, spire_top + 6.0),
			Vector2(x + w * 0.3, spire_top + 18.0), Vector2(x + w * 0.5, spire_top + 44.0), Vector2(x + w * 0.5, base),
		]), col)
		# Two dim slit windows keep the towers reading as inhabited ruins.
		for wi in range(2):
			var wy := spire_top + 90.0 + float(wi) * 70.0 + VFX.hash01(k + wi, 4) * 30.0
			draw_rect(Rect2(x - 2.0 + (float(wi) - 0.5) * 10.0, wy, 4.0, 14.0), Color(0.9, 0.45, 0.2, 0.08 + VFX.hash01(k, 5 + wi) * 0.06))

func _draw_arches(horizon: float) -> void:
	var depth := 0.35
	var period := 200.0
	var wall := Color("160e26")
	var edge := Color("24183b")
	var r := _plane_range(depth, period, 160.0)
	var base := horizon + 60.0
	var arch_top := horizon - 340.0
	var x_start := _plane_x(depth, float(r.x) * period) - period
	var width := float(r.y - r.x + 2) * period
	# Entablature above the colonnade plus its ground course.
	draw_rect(Rect2(x_start, arch_top - 34.0, width, 34.0), wall)
	draw_line(Vector2(x_start, arch_top - 34.0), Vector2(x_start + width, arch_top - 34.0), edge, 2.0)
	draw_rect(Rect2(x_start, base - 24.0, width, 24.0), wall)
	for k in range(r.x, r.y + 1):
		var cx := _plane_x(depth, float(k) * period)
		# Pillars and the spandrel over an open arch; the sky shows through the opening.
		draw_rect(Rect2(cx - 80.0, arch_top, 28.0, base - arch_top), wall)
		draw_rect(Rect2(cx + 52.0, arch_top, 28.0, base - arch_top), wall)
		var spandrel := PackedVector2Array([Vector2(cx - 80.0, arch_top), Vector2(cx + 80.0, arch_top), Vector2(cx + 80.0, arch_top + 110.0)])
		for i in range(13):
			var a := -PI * float(i) / 12.0
			spandrel.append(Vector2(cx, arch_top + 110.0) + Vector2(cos(a), sin(a)) * 52.0)
		spandrel.append(Vector2(cx - 80.0, arch_top + 110.0))
		draw_colored_polygon(spandrel, wall)
		draw_arc(Vector2(cx, arch_top + 110.0), 52.0, PI, TAU, 16, edge, 1.5)
		# Hanging chains, each with a slow deterministic sway.
		if VFX.hash01(k, 7) > 0.35:
			var length := 80.0 + VFX.hash01(k, 8) * 100.0
			var sway := sin(_atmo_t * 0.7 + float(k)) * 4.0
			draw_dashed_line(Vector2(cx, arch_top - 34.0), Vector2(cx + sway, arch_top - 34.0 + length), edge, 2.0, 6.0)
		if VFX.hash01(k, 9) > 0.7:
			var drop := 240.0 + VFX.hash01(k, 10) * 220.0
			var sway2 := sin(_atmo_t * 0.5 + float(k) * 1.9) * 6.0
			draw_dashed_line(Vector2(cx + 46.0, -560.0), Vector2(cx + 46.0 + sway2, -560.0 + drop), edge, 2.0, 6.0)

func _draw_buttresses(horizon: float) -> void:
	var depth := 0.65
	var period := 320.0
	var stone := Color("201435")
	var frame := Color(VFX.MORTAR, 0.55)
	var r := _plane_range(depth, period, 160.0)
	var base := horizon + 60.0
	var top := horizon - 470.0
	var moving := not Feedback.motion_reduced
	for k in range(r.x, r.y + 1):
		var x := _plane_x(depth, float(k) * period)
		# Pilaster with capital and plinth.
		draw_rect(Rect2(x - 22.0, top, 44.0, base - top), stone)
		draw_rect(Rect2(x - 30.0, top, 60.0, 14.0), stone.lightened(0.08))
		draw_rect(Rect2(x - 28.0, horizon - 40.0, 56.0, 40.0), stone.lightened(0.05))
		draw_line(Vector2(x - 22.0, top), Vector2(x - 22.0, base), Color(VFX.RIM, 0.18), 1.5)
		# Recessed arch frame between pilasters.
		var mid := x + period * 0.5
		draw_arc(Vector2(mid, horizon - 230.0), 118.0, PI, TAU, 20, frame, 6.0)
		draw_line(Vector2(mid - 118.0, horizon - 230.0), Vector2(mid - 118.0, horizon - 20.0), frame, 6.0)
		draw_line(Vector2(mid + 118.0, horizon - 230.0), Vector2(mid + 118.0, horizon - 20.0), frame, 6.0)
		# Torch sconce: iron bracket, bowl and a small flame under the additive light.
		var sconce := Vector2(x, TORCH_Y)
		draw_rect(Rect2(sconce.x - 3.0, sconce.y, 6.0, 22.0), Color("1a1024"))
		draw_colored_polygon(PackedVector2Array([
			sconce + Vector2(-10.0, -4.0), sconce + Vector2(10.0, -4.0), sconce + Vector2(5.0, 6.0), sconce + Vector2(-5.0, 6.0),
		]), VFX.MORTAR)
		var lick := sin(_atmo_t * 11.0 + float(k) * 2.1) * 3.0 if moving else 0.0
		draw_colored_polygon(PackedVector2Array([
			sconce + Vector2(-7.0, -4.0), sconce + Vector2(-1.0 + lick * 0.4, -26.0 - lick), sconce + Vector2(7.0, -4.0),
		]), VFX.ORANGE)
		draw_colored_polygon(PackedVector2Array([
			sconce + Vector2(-3.5, -5.0), sconce + Vector2(0.5 + lick * 0.3, -17.0 - lick * 0.6), sconce + Vector2(3.5, -5.0),
		]), VFX.GOLD)

func _draw_fog(horizon: float) -> void:
	# Three drifting bands: high between the arches, low across the play plane and
	# a heavy layer in the pit. `_atmo_t` stops under reduced motion, so they freeze.
	var bands := [
		[horizon - 300.0, 120.0, 6.0, Color(VFX.NAVY, 0.09)],
		[horizon - 60.0, 90.0, 12.0, Color(VFX.TYRIAN, 0.14)],
		[horizon + 170.0, 140.0, 22.0, Color(VFX.TYRIAN, 0.14)],
	]
	var half := get_viewport_rect().size.x * 0.5 + 420.0
	var period := 360.0
	for b in range(bands.size()):
		var y: float = bands[b][0]
		var h: float = bands[b][1]
		var speed: float = bands[b][2]
		var col: Color = bands[b][3]
		var scroll := fmod(_atmo_t * speed, period)
		var kmin := floori((_view_center.x - half - scroll) / period)
		var kmax := ceili((_view_center.x + half - scroll) / period)
		for k in range(kmin, kmax + 1):
			var x := float(k) * period + scroll + VFX.hash01(k, 20 + b) * 120.0
			var rx := 220.0 + VFX.hash01(k, 30 + b) * 160.0
			var ry := h * (0.35 + VFX.hash01(k, 40 + b) * 0.25)
			var yy := y + sin(_atmo_t * 0.3 + float(k) * 1.3) * 6.0
			VFX.draw_ellipse(self, Vector2(x, yy), rx, ry, col)

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
		"swing_active":
			# Additive sweep afterglow matching the live hitbox arc.
			var def: Dictionary = Content.COMBO[clampi(player.attack_index, 0, Content.COMBO.size() - 1)]
			feedback.slash_arc(pos + Vector2(player.facing * 8.0, -8.0), player.facing, float(def.range), float(def.arc), player.attack_index == Content.COMBO.size() - 1)
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
			feedback.flash_death(room.boss.global_position, Content.BOSS_COLOR, true)
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
		feedback.parry_flash(pos)
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
	feedback.blast(pos, radius)
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
		"reduced_motion":
			feedback.set_reduced_motion(value)
			_atmosphere.set_reduced_motion(value)
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
