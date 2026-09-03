class_name Game
extends Node2D
## Root orchestrator: run lifecycle, room replacement, signal routing, pause, background.

const VFX := preload("res://scripts/vfx.gd")
const MusicSynth := preload("res://scripts/music.gd")
const BackdropPainter := preload("res://scripts/backdrop.gd")
const LightRig := preload("res://scripts/light_rig.gd")

enum GState { TITLE, PLAYING, REWARD, GAME_OVER, VICTORY }

var state: int = GState.TITLE
var run: RunModel
var world: Node2D
var projectiles: Node2D
var room: Room
var player: Player
var feedback: Feedback
var ui: UI
var music: Node  # music.gd; preloaded so it never depends on the class cache
var score: int = 0
var paused: bool = false
var _pending_upgrades: Array = []
var _seed: int = 0
var _run_cells: int = 0
# Kill streak: chained kills inside STREAK_WINDOW multiply score.
var _streak_kills := 0
var _streak_t := 0.0
var _streak_tier := 0
# Run statistics shown on the end screens.
var _stats: Dictionary = {}
var _vignette_rect: ColorRect
var _low_hp_t := 0.0
## Current depth palette; see Content.MOODS. Snaps per chamber under the rift fade.
var mood: Dictionary = Content.mood_for(0.0)
const VIGNETTE_EDGE := Color(0.027, 0.02, 0.043, 0.78)
const VIGNETTE_LOW_HP := Color(0.46, 0.04, 0.07, 0.92)
# Visual layers. Lights and ambience are inserted before World so they draw above
# the backdrop but beneath platforms, actors and combat VFX.
const TORCH_Y := Content.FLOOR_Y - 200.0
var _light_layer: Node2D
var _atmosphere: Node2D
var _vignette: CanvasLayer
## The world renders vector-native at full resolution with linear filtering,
## so actors, environment and lighting share one smooth coherent frame.
var _pixel_container: SubViewportContainer
var pixel_view: SubViewport
var _backdrop: Node2D
var _lights: Node2D
var _view_center := Vector2(Content.VIEW_W, Content.VIEW_H) * 0.5
var _atmo_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_default_clear_color(mood.bg_top)
	# Pixel viewport: the whole world draws at 1/PIXEL_SCALE resolution.
	_pixel_container = SubViewportContainer.new()
	_pixel_container.name = "PixelView"
	_pixel_container.stretch = true
	_pixel_container.stretch_shrink = int(Content.PIXEL_SCALE)
	_pixel_container.size = Vector2(Content.VIEW_W, Content.VIEW_H)
	_pixel_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pixel_container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_pixel_container)
	pixel_view = SubViewport.new()
	pixel_view.name = "Viewport"
	pixel_view.disable_3d = true
	pixel_view.handle_input_locally = false
	pixel_view.gui_disable_input = true
	pixel_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	pixel_view.snap_2d_transforms_to_pixel = false
	_pixel_container.add_child(pixel_view)
	_backdrop = BackdropPainter.new()
	_backdrop.name = "Backdrop"
	_backdrop.game = self
	_backdrop.process_mode = Node.PROCESS_MODE_PAUSABLE
	pixel_view.add_child(_backdrop)
	# Additive lights and ambient particles (pausable, like the world they belong to).
	_light_layer = load("res://scripts/light_layer.gd").new()
	_light_layer.name = "LightLayer"
	_light_layer.game = self
	_light_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	pixel_view.add_child(_light_layer)
	_atmosphere = load("res://scripts/atmosphere.gd").new()
	_atmosphere.name = "Atmosphere"
	_atmosphere.process_mode = Node.PROCESS_MODE_PAUSABLE
	pixel_view.add_child(_atmosphere)
	# World (pausable)
	world = Node2D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	pixel_view.add_child(world)
	projectiles = Node2D.new()
	projectiles.name = "Projectiles"
	projectiles.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_child(projectiles)
	# Feedback (pausable): camera, particles, audio.
	feedback = Feedback.new()
	feedback.name = "Feedback"
	feedback.process_mode = Node.PROCESS_MODE_PAUSABLE
	pixel_view.add_child(feedback)
	# Real 2D lights over everything in the pixel viewport.
	_lights = LightRig.new()
	_lights.name = "Lights"
	_lights.game = self
	_lights.process_mode = Node.PROCESS_MODE_PAUSABLE
	pixel_view.add_child(_lights)
	_lights.set_ambient(mood.ambient)
	# Procedural score (always; keeps playing under pause menus)
	music = MusicSynth.new()
	music.name = "Music"
	add_child(music)
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
	_vignette_rect = ColorRect.new()
	_vignette_rect.name = "VignetteRect"
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.material = VFX.vignette_material()
	_vignette.add_child(_vignette_rect)
	_vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	_reset_stats()
	music.play_track("title")
	set_process(true)

func _reset_stats() -> void:
	_stats = {
		"time": 0.0, "kills": 0, "elites": 0, "damage_dealt": 0.0, "damage_taken": 0.0,
		"best_streak": 0, "rooms": 0, "rooms_total": 0,
	}
	_streak_kills = 0
	_streak_t = 0.0
	_streak_tier = 0

func _process(delta: float) -> void:
	_atmosphere.global_position = _view_center
	if not get_tree().paused and not Feedback.motion_reduced:
		_atmo_t += delta
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
		if not get_tree().paused:
			_stats.time += delta
			_tick_streak(delta)
		_update_low_hp_vignette(delta)
	else:
		_set_vignette(VIGNETTE_EDGE)

func _tick_streak(delta: float) -> void:
	if _streak_kills <= 0:
		return
	_streak_t -= delta
	if _streak_t <= 0.0:
		_streak_kills = 0
		_streak_tier = 0
		ui.hide_streak()
		return
	ui.set_streak(_streak_kills, _streak_t / Content.STREAK_WINDOW, Content.streak_multiplier(_streak_kills))

func _register_kill() -> void:
	_streak_kills = _streak_kills + 1 if _streak_t > 0.0 else 1
	_streak_t = Content.STREAK_WINDOW
	_stats.best_streak = maxi(int(_stats.best_streak), _streak_kills)
	var tier := Content.streak_tier(_streak_kills)
	if tier > _streak_tier:
		feedback.play("streak", 1.0 + 0.16 * float(tier))
	_streak_tier = tier
	ui.set_streak(_streak_kills, 1.0, Content.streak_multiplier(_streak_kills))

## The vignette bleeds red as the flame gutters, pulsing faster the lower it gets.
func _update_low_hp_vignette(delta: float) -> void:
	var frac := float(player.build.hp) / maxf(1.0, float(player.build.max_hp))
	var low := clampf((0.34 - frac) / 0.34, 0.0, 1.0)
	if low <= 0.0:
		_low_hp_t = 0.0
		_set_vignette(VIGNETTE_EDGE)
		return
	if not get_tree().paused and not Feedback.motion_reduced:
		_low_hp_t += delta * (3.5 + low * 4.0)
	var pulse := 0.5 + 0.5 * sin(_low_hp_t) if not Feedback.motion_reduced else 0.5
	var strength := low * (0.5 + 0.5 * pulse) * (0.45 if Feedback.flash_reduced else 1.0)
	_set_vignette(VIGNETTE_EDGE.lerp(VIGNETTE_LOW_HP, strength))

func _set_vignette(edge: Color) -> void:
	if _vignette_rect != null and _vignette_rect.material is ShaderMaterial:
		(_vignette_rect.material as ShaderMaterial).set_shader_parameter("edge_color", edge)

func _paint_backdrop(ci: CanvasItem) -> void:
	# Camera-driven parallax crypt. Each plane is shifted by (1 - depth) of the
	# view centre, so far planes crawl while near planes track the world. Read the
	# camera here (draw runs after every _process) so nothing lags a frame.
	_view_center = feedback.camera.get_screen_center_position()
	var m := mood
	var left := Content.ROOM_LEFT - 240.0
	var right := Content.ROOM_RIGHT + 240.0
	var span := right - left
	var top := -560.0
	var horizon := Content.FLOOR_Y
	# Sky: void above, crypt navy through the arches, warm at the floor line.
	VFX.draw_vgradient(ci, Rect2(left, top, span, (horizon - top) * 0.6), m.bg_top, m.bg_mid)
	VFX.draw_vgradient(ci, Rect2(left, top + (horizon - top) * 0.6, span, (horizon - top) * 0.4), m.bg_mid, m.bg_bot)
	_draw_stars(ci, top, horizon)
	_draw_moon(ci, horizon)
	# Under-floor pit: the floor line falls away into absolute void.
	VFX.draw_vgradient(ci, Rect2(left, horizon, span, 320.0), m.bg_bot, m.pit)
	ci.draw_rect(Rect2(left, horizon + 320.0, span, 520.0), m.pit)
	var seep := float(m.ember_seep)
	if seep > 0.0:
		# Magma light seeping up from the depths as the keep warms.
		VFX.draw_vgradient(ci, Rect2(left, horizon + 120.0, span, 420.0), Color(m.glow, 0.0), Color(m.glow, 0.2 * seep))
	# Distant furnace bloom low on the horizon, behind the spires.
	var bloom := Vector2(_plane_x(0.1, 184.0), horizon - 60.0)
	for i in range(4, 0, -1):
		ci.draw_circle(bloom, 90.0 + float(i) * 72.0, Color(m.glow, (0.016 + float(5 - i) * 0.012) * (1.0 + seep)))
		_draw_spires(ci, horizon)
		_draw_arches(ci, horizon)
		_draw_light_shafts(ci, top, horizon)
		_draw_buttresses(ci, horizon)
	_draw_rubble(ci, horizon)
	_draw_undercroft(ci, horizon)
	_draw_fog(ci, horizon)

## Visible repeat-index range for a plane at `depth` whose elements repeat every `period`.
func _plane_range(depth: float, period: float, margin: float) -> Vector2i:
	var half := float(Content.VIEW_W) * 0.5 + margin
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

## Animated flames over the buttress sconces.
func _draw_sconce_flames(ci: CanvasItem) -> void:
	var moving := not Feedback.motion_reduced
	var t := _atmo_t if moving else 0.0
	var torch: Color = mood.torch
	var idx := 0
	for p in torch_positions():
		VFX.draw_flame(ci, p + Vector2(0.0, 10.0), 26.0, 12.0, t, float(idx) * 2.1, torch, VFX.GOLD)
		idx += 1

func _draw_stars(ci: CanvasItem, top: float, horizon: float) -> void:
	var vis := float(mood.stars)
	if vis <= 0.01:
		return
	var depth := 0.04
	var period := 90.0
	var r := _plane_range(depth, period, 60.0)
	var moving := not Feedback.motion_reduced
	for k in range(r.x, r.y + 1):
		for j in range(3):
			var h := VFX.hash01(k * 7 + j, 51)
			var x := _plane_x(depth, float(k) * period + VFX.hash01(k, 52 + j) * period)
			var y := horizon - 500.0 + VFX.hash01(k, 55 + j) * 260.0
			var tw := 0.5 + 0.5 * sin(_atmo_t * (1.0 + h * 2.0) + float(k)) if moving else 0.7
			ci.draw_circle(Vector2(x, y), 0.8 + h * 1.3, Color(0.85, 0.88, 1.0, (0.2 + 0.5 * tw) * vis))

## A cold moon over the crypt that reddens into a furnace sun deeper down.
func _draw_moon(ci: CanvasItem, horizon: float) -> void:
	var c := Vector2(_plane_x(0.06, 400.0), horizon - 340.0)
	var col: Color = mood.moon
	var a := float(mood.moon_alpha)
	for i in range(5, 0, -1):
		ci.draw_circle(c, 78.0 + float(i) * 36.0, Color(col, 0.016 * a * float(6 - i)))
	ci.draw_circle(c, 78.0, Color(col, 0.95 * a))
	for i in range(6):
		var off := Vector2(VFX.hash01(i, 61) - 0.5, VFX.hash01(i, 62) - 0.5) * 104.0
		ci.draw_circle(c + off, 5.0 + VFX.hash01(i, 63) * 13.0, Color(col.darkened(0.28), 0.5 * a))
	# Crescent bite in the crypt; it fills in as the moods warm.
	var bite := float(mood.stars)
	if bite > 0.01:
		ci.draw_circle(c + Vector2(38.0, -24.0), 72.0, Color(mood.bg_top, 0.85 * bite))

func _draw_spires(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.15
	var period := 150.0
	var col: Color = mood.spire
	var window_col: Color = mood.torch
	var r := _plane_range(depth, period, 120.0)
	var base := horizon + 80.0
	var mass_top := horizon - 150.0
	ci.draw_rect(Rect2(_plane_x(depth, float(r.x) * period) - period, mass_top, float(r.y - r.x + 2) * period, base - mass_top), col)
	for k in range(r.x, r.y + 1):
		var h := 300.0 + VFX.hash01(k, 1) * 120.0
		var w := 58.0 + VFX.hash01(k, 2) * 32.0
		var x := _plane_x(depth, float(k) * period + VFX.hash01(k, 3) * 40.0)
		var spire_top := base - h
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(x - w * 0.5, base), Vector2(x - w * 0.5, spire_top + 40.0), Vector2(x - w * 0.28, spire_top + 14.0),
			Vector2(x - w * 0.1, spire_top + 4.0), Vector2(x, spire_top - 26.0), Vector2(x + w * 0.1, spire_top + 6.0),
			Vector2(x + w * 0.3, spire_top + 18.0), Vector2(x + w * 0.5, spire_top + 44.0), Vector2(x + w * 0.5, base),
		]), col)
		# Slit windows keep the towers reading as inhabited ruins; a few flicker.
		for wi in range(3):
			var wy := spire_top + 80.0 + float(wi) * 64.0 + VFX.hash01(k + wi, 4) * 30.0
			var lit := VFX.hash01(k, 5 + wi)
			var flick := 1.0 if Feedback.motion_reduced else 0.85 + 0.15 * sin(_atmo_t * 3.0 + float(k * 3 + wi))
			ci.draw_rect(Rect2(x - 2.0 + (float(wi % 2) - 0.5) * 10.0, wy, 4.0, 14.0), Color(window_col, (0.06 + lit * 0.16) * flick))

func _draw_arches(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.35
	var period := 200.0
	var wall: Color = mood.wall
	var edge: Color = mood.edge
	var r := _plane_range(depth, period, 160.0)
	var base := horizon + 60.0
	var arch_top := horizon - 340.0
	var x_start := _plane_x(depth, float(r.x) * period) - period
	var width := float(r.y - r.x + 2) * period
	var moving := not Feedback.motion_reduced
	# Entablature above the colonnade plus its ground course.
	ci.draw_rect(Rect2(x_start, arch_top - 34.0, width, 34.0), wall)
	ci.draw_line(Vector2(x_start, arch_top - 34.0), Vector2(x_start + width, arch_top - 34.0), edge, 2.0)
	ci.draw_rect(Rect2(x_start, base - 24.0, width, 24.0), wall)
	for k in range(r.x, r.y + 1):
		var cx := _plane_x(depth, float(k) * period)
		var glazed := VFX.hash01(k, 11) > 0.6
		if glazed:
			# A walled bay: leaded rose window glowing with the mood's light.
			ci.draw_rect(Rect2(cx - 52.0, arch_top + 100.0, 104.0, base - arch_top - 100.0), wall.darkened(0.12))
			var wc := Vector2(cx, arch_top + 158.0)
			var glass: Color = mood.glass
			var breathe := 0.22 + (0.06 * sin(_atmo_t * 1.3 + float(k)) if moving else 0.0)
			ci.draw_circle(wc, 44.0, Color(glass, 0.06))
			ci.draw_circle(wc, 27.0, Color(glass, breathe))
			for i in range(6):
				var a := float(i) * PI / 3.0
				ci.draw_line(wc, wc + Vector2(cos(a), sin(a)) * 27.0, edge.darkened(0.3), 2.0)
			ci.draw_arc(wc, 27.0, 0.0, TAU, 24, edge.darkened(0.3), 2.5)
			ci.draw_arc(wc, 12.0, 0.0, TAU, 16, edge.darkened(0.3), 1.5)
		# Pillars and the spandrel over an open arch; the sky shows through the opening.
		ci.draw_rect(Rect2(cx - 80.0, arch_top, 28.0, base - arch_top), wall)
		ci.draw_rect(Rect2(cx + 52.0, arch_top, 28.0, base - arch_top), wall)
		var spandrel := PackedVector2Array([Vector2(cx - 80.0, arch_top), Vector2(cx + 80.0, arch_top), Vector2(cx + 80.0, arch_top + 110.0)])
		for i in range(13):
			var a := -PI * float(i) / 12.0
			spandrel.append(Vector2(cx, arch_top + 110.0) + Vector2(cos(a), sin(a)) * 52.0)
		spandrel.append(Vector2(cx - 80.0, arch_top + 110.0))
		ci.draw_colored_polygon(spandrel, wall)
		ci.draw_arc(Vector2(cx, arch_top + 110.0), 52.0, PI, TAU, 16, edge, 1.5)
		# Heraldic banners hang from the entablature on some bays.
		if VFX.hash01(k, 12) > 0.62:
			var by := arch_top - 30.0
			var bl := 150.0 + VFX.hash01(k, 13) * 70.0
			var sway := sin(_atmo_t * 0.9 + float(k) * 0.7) * 5.0 if moving else 0.0
			var bc: Color = mood.banner
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(cx - 22.0, by), Vector2(cx + 22.0, by), Vector2(cx + 22.0 + sway, by + bl - 22.0),
				Vector2(cx + sway, by + bl), Vector2(cx - 22.0 + sway, by + bl - 22.0),
			]), bc)
			ci.draw_line(Vector2(cx - 22.0, by), Vector2(cx - 22.0 + sway, by + bl - 22.0), Color(VFX.RIM, 0.12), 1.0)
			ci.draw_line(Vector2(cx - 27.0, by), Vector2(cx + 27.0, by), edge.lightened(0.15), 3.0)
			VFX.draw_flame(ci, Vector2(cx + sway * 0.5, by + bl * 0.55), 16.0, 9.0, 0.0, 0.0, Color(mood.torch, 0.55), Color(VFX.GOLD, 0.35))
		# Hanging chains, each with a slow deterministic sway.
		if VFX.hash01(k, 7) > 0.35:
			var length := 80.0 + VFX.hash01(k, 8) * 100.0
			var sway := sin(_atmo_t * 0.7 + float(k)) * 4.0 if moving else 0.0
			ci.draw_dashed_line(Vector2(cx, arch_top - 34.0), Vector2(cx + sway, arch_top - 34.0 + length), edge, 2.0, 6.0)
		if VFX.hash01(k, 9) > 0.7:
			var drop := 240.0 + VFX.hash01(k, 10) * 220.0
			var sway2 := sin(_atmo_t * 0.5 + float(k) * 1.9) * 6.0 if moving else 0.0
			ci.draw_dashed_line(Vector2(cx + 46.0, -560.0), Vector2(cx + 46.0 + sway2, -560.0 + drop), edge, 2.0, 6.0)

## Slanted shafts of moon or furnace light falling between the bays.
func _draw_light_shafts(ci: CanvasItem, top: float, horizon: float) -> void:
	var col: Color = mood.moon
	var strength := 0.03 * (0.5 + 0.5 * float(mood.stars)) + 0.025 * float(mood.ember_seep)
	var depth := 0.3
	var period := 420.0
	var r := _plane_range(depth, period, 260.0)
	var moving := not Feedback.motion_reduced
	for k in range(r.x, r.y + 1):
		if VFX.hash01(k, 71) < 0.4:
			continue
		var x := _plane_x(depth, float(k) * period + VFX.hash01(k, 72) * 200.0)
		var w := 60.0 + VFX.hash01(k, 73) * 90.0
		var sway := sin(_atmo_t * 0.25 + float(k)) * 18.0 if moving else 0.0
		var lean := 140.0 + VFX.hash01(k, 74) * 80.0
		ci.draw_polygon(PackedVector2Array([
			Vector2(x, top), Vector2(x + w, top),
			Vector2(x + w + lean + sway, horizon + 40.0), Vector2(x + lean + sway - w * 0.6, horizon + 40.0),
		]), PackedColorArray([Color(col, strength), Color(col, strength), Color(col, 0.0), Color(col, 0.0)]))

func _draw_buttresses(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.65
	var period := 320.0
	var stone: Color = mood.stone
	var frame := Color(VFX.MORTAR, 0.55)
	var r := _plane_range(depth, period, 160.0)
	var base := horizon + 60.0
	var top := horizon - 470.0
	var moving := not Feedback.motion_reduced
	var torch: Color = mood.torch
	for k in range(r.x, r.y + 1):
		var x := _plane_x(depth, float(k) * period)
		# Pilaster with capital and plinth.
		ci.draw_rect(Rect2(x - 22.0, top, 44.0, base - top), stone)
		ci.draw_rect(Rect2(x - 30.0, top, 60.0, 14.0), stone.lightened(0.08))
		ci.draw_rect(Rect2(x - 28.0, horizon - 40.0, 56.0, 40.0), stone.lightened(0.05))
		ci.draw_line(Vector2(x - 22.0, top), Vector2(x - 22.0, base), Color(VFX.RIM, 0.18), 1.5)
		# Crouching gargoyle on every other capital.
		if k % 2 == 0:
			var g := Vector2(x, top)
			ci.draw_colored_polygon(PackedVector2Array([
				g + Vector2(-16.0, 0.0), g + Vector2(-12.0, -14.0), g + Vector2(-4.0, -20.0), g + Vector2(2.0, -30.0),
				g + Vector2(8.0, -22.0), g + Vector2(18.0, -18.0), g + Vector2(14.0, -8.0), g + Vector2(18.0, 0.0),
			]), stone.darkened(0.25))
			ci.draw_colored_polygon(PackedVector2Array([g + Vector2(-2.0, -30.0), g + Vector2(-10.0, -44.0), g + Vector2(4.0, -34.0)]), stone.darkened(0.25))
			ci.draw_circle(g + Vector2(4.0, -25.0), 1.6, Color(torch, 0.7))
		# Recessed arch frame between pilasters.
		var mid := x + period * 0.5
		ci.draw_arc(Vector2(mid, horizon - 230.0), 118.0, PI, TAU, 20, frame, 6.0)
		ci.draw_line(Vector2(mid - 118.0, horizon - 230.0), Vector2(mid - 118.0, horizon - 20.0), frame, 6.0)
		ci.draw_line(Vector2(mid + 118.0, horizon - 230.0), Vector2(mid + 118.0, horizon - 20.0), frame, 6.0)
		# Torch sconce: iron bracket, bowl and a small flame under the additive light.
		var sconce := Vector2(x, TORCH_Y)
		ci.draw_rect(Rect2(sconce.x - 3.0, sconce.y, 6.0, 22.0), Color("1a1024"))
		ci.draw_colored_polygon(PackedVector2Array([
			sconce + Vector2(-10.0, -4.0), sconce + Vector2(10.0, -4.0), sconce + Vector2(5.0, 6.0), sconce + Vector2(-5.0, 6.0),
		]), VFX.MORTAR)
		var t := _atmo_t if moving else 0.0
		VFX.draw_flame(ci, sconce + Vector2(0.0, -4.0), 24.0, 12.0, t, float(k) * 2.1, torch, VFX.GOLD)
		# Soot streak above the sconce.
		ci.draw_rect(Rect2(sconce.x - 5.0, sconce.y - 70.0, 10.0, 44.0), Color(0.0, 0.0, 0.0, 0.18))

## Stone mounds and bones along the back wall, just behind the play plane.
func _draw_rubble(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.85
	var period := 260.0
	var r := _plane_range(depth, period, 120.0)
	var stone: Color = mood.stone
	for k in range(r.x, r.y + 1):
		if VFX.hash01(k, 81) < 0.45:
			continue
		var x := _plane_x(depth, float(k) * period + VFX.hash01(k, 82) * 160.0)
		var w := 40.0 + VFX.hash01(k, 83) * 70.0
		var h := 14.0 + VFX.hash01(k, 84) * 26.0
		var pts := PackedVector2Array([Vector2(x - w * 0.5, horizon)])
		for i in range(1, 6):
			var u := float(i) / 6.0
			pts.append(Vector2(x - w * 0.5 + u * w, horizon - h * (0.5 + 0.5 * sin(u * PI)) * (0.7 + VFX.hash01(k + i, 85) * 0.5)))
		pts.append(Vector2(x + w * 0.5, horizon))
		ci.draw_colored_polygon(pts, stone.darkened(0.35))
		ci.draw_polyline(pts, Color(VFX.RIM, 0.2), 1.0)
		if VFX.hash01(k, 86) > 0.6:
			var sk := Vector2(x + (VFX.hash01(k, 87) - 0.5) * w * 0.5, horizon - h * 0.5 - 4.0)
			ci.draw_circle(sk, 5.0, Color("8f877a"))
			ci.draw_circle(sk + Vector2(-2.0, -1.0), 1.4, VFX.VOID)
			ci.draw_circle(sk + Vector2(2.0, -1.0), 1.4, VFX.VOID)

## A drowned lower colonnade under the floor line, fading into the pit.
func _draw_undercroft(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.5
	var period := 260.0
	var r := _plane_range(depth, period, 160.0)
	var wall: Color = mood.wall
	var top := horizon + 130.0
	var bottom := horizon + 560.0
	var x_start := _plane_x(depth, float(r.x) * period) - period
	var width := float(r.y - r.x + 2) * period
	# Course line where the undercroft meets the slab, then fading pillars.
	VFX.draw_vgradient(ci, Rect2(x_start, top, width, 26.0), Color(wall, 0.55), Color(wall, 0.0))
	for k in range(r.x, r.y + 1):
		var cx := _plane_x(depth, float(k) * period)
		ci.draw_polygon(PackedVector2Array([
			Vector2(cx - 18.0, top), Vector2(cx + 18.0, top), Vector2(cx + 18.0, bottom), Vector2(cx - 18.0, bottom),
		]), PackedColorArray([Color(wall, 0.6), Color(wall, 0.6), Color(wall, 0.0), Color(wall, 0.0)]))
		ci.draw_arc(Vector2(cx + period * 0.5, top + 150.0), 86.0, PI, TAU, 18, Color(mood.edge, 0.22), 5.0)
		# Hanging roots and chains under the slab.
		if VFX.hash01(k, 121) > 0.5:
			var len := 40.0 + VFX.hash01(k, 122) * 90.0
			var sway := sin(_atmo_t * 0.6 + float(k)) * 4.0 if not Feedback.motion_reduced else 0.0
			ci.draw_dashed_line(Vector2(cx + 60.0, horizon + 120.0), Vector2(cx + 60.0 + sway, horizon + 120.0 + len), Color(mood.edge, 0.5), 2.0, 6.0)
	if float(mood.ember_seep) > 0.05:
		# Magma pool glimmers between the pillars.
		var seep := float(mood.ember_seep)
		for k in range(r.x, r.y + 1):
			var px := _plane_x(depth, float(k) * period + 130.0)
			var pulse := 0.6 + 0.4 * sin(_atmo_t * 1.5 + float(k)) if not Feedback.motion_reduced else 0.8
			VFX.draw_ellipse(ci, Vector2(px, horizon + 470.0), 70.0, 8.0, Color(mood.glow, 0.25 * seep * pulse))

func _draw_fog(ci: CanvasItem, horizon: float) -> void:
	# Three drifting bands: high between the arches, low across the play plane and
	# a heavy layer in the pit. `_atmo_t` stops under reduced motion, so they freeze.
	var fog: Color = mood.fog
	var bands := [
		[horizon - 300.0, 120.0, 6.0, Color(fog.lerp(VFX.NAVY, 0.4), 0.09)],
		[horizon - 60.0, 90.0, 12.0, Color(fog, 0.14)],
		[horizon + 170.0, 140.0, 22.0, Color(fog, 0.14)],
	]
	var half := float(Content.VIEW_W) * 0.5 + 420.0
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
			VFX.draw_ellipse(ci, Vector2(x, yy), rx, ry, col)

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
	_reset_stats()
	ui.hide_streak()
	ui.hide_banners()
	_seed = randi()
	run = RunModel.new(_seed)
	_stats.rooms_total = run.rooms_total()
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
	music.play_track("explore")

func _advance_room() -> void:
	_clear_room()
	_clear_projectiles()
	ui.hide_room_clear()
	var tmpl := run.advance_to_next_room()
	var is_boss := run.is_boss_room()
	mood = Content.mood_for(float(run.room_index) / maxf(1.0, float(run.rooms_total() - 1)))
	RenderingServer.set_default_clear_color(mood.bg_top)
	_lights.set_ambient(mood.ambient)
	room = Room.new()
	room.mood = mood
	room.setup(tmpl, is_boss, player, run.rng.randi())
	room.set_meta("room_index", run.room_index)
	# Connect before _ready() because boss_spawned and wave_started happen there.
	room.completed.connect(_on_room_completed)
	room.cleared.connect(_on_room_cleared)
	room.enemy_died.connect(_on_enemy_died)
	room.enemy_damaged.connect(_on_enemy_damaged)
	room.pyre_burst.connect(_on_pyre_burst)
	room.projectile_requested.connect(_on_enemy_projectile)
	room.boss_spawned.connect(_on_boss_spawned)
	room.boss_phase_changed.connect(_on_boss_phase)
	room.enemy_exploded.connect(_on_enemy_exploded)
	room.enemy_spawned.connect(_on_enemy_spawned)
	Enemy.pyre_damage = float(run.build.get("pyre_dmg", 0.0))
	world.add_child(room)
	# position player at entry
	var entry := room.get_entry_point()
	player.respawn_at(entry)
	player.suppress_gameplay_input()
	# Snap across the rift instead of briefly lerping from the previous exit.
	feedback.camera.global_position = _camera_target_for(entry)
	# UI
	ui.set_room(run.room_index, run.rooms_total())
	ui.fade_from_black(0.45)
	if not is_boss:
		ui.show_room_intro(run.room_index, run.rooms_total(), Content.room_name(tmpl))
	_stats.rooms = run.room_index + 1
	player.build = run.build

func _camera_target_for(pos: Vector2) -> Vector2:
	var target := pos
	# Look-ahead in the facing direction gives the swing room to land on screen.
	if is_instance_valid(player) and state == GState.PLAYING:
		target.x += player.facing * 56.0
	var lim_l := Content.ROOM_LEFT + Content.VIEW_W * 0.5
	var lim_r := Content.ROOM_RIGHT - Content.VIEW_W * 0.5
	target.x = clampf(target.x, lim_l, lim_r)
	target.y = clampf(target.y, 200.0, Content.FLOOR_Y - 140.0)
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
	feedback.damage_number(pos + Vector2(0.0, -44.0), amount, "hurt")
	_stats.damage_taken += amount

func _on_enemy_damaged(amount: float, pos: Vector2, blocked: bool) -> void:
	if blocked:
		feedback.damage_number(pos, amount, "block", "BLOCKED")
		return
	feedback.damage_number(pos, amount, "heavy" if amount >= 40.0 else "hit")
	_stats.damage_dealt += amount

func _on_enemy_spawned(pos: Vector2, color: Color) -> void:
	feedback.spawn_rift(pos, color)

func _on_pyre_burst(pos: Vector2, radius: float) -> void:
	feedback.blast(pos, radius)
	feedback.burst(pos, 22, Content.PAL.player_accent, 320.0)
	feedback.shake(5.0, 0.16)
	feedback.play("pyre")

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
		"heal":
			feedback.play("heal")
			feedback.damage_number(pos + Vector2(0.0, -48.0), Content.FLASK_HEAL, "heal", "+%d" % roundi(Content.FLASK_HEAL))
		"flame":
			feedback.play("flame")
			feedback.burst(pos, 28, Content.PAL.player_accent, 300.0)
			feedback.shake(5.0, 0.2)
		"slam": feedback.play("swing")
		"second_wind":
			feedback.play("second_wind")
			feedback.parry_flash(pos)
			feedback.burst(pos, 36, Content.PAL.heal_number, 340.0)
			feedback.hit_stop(0.12)
			feedback.shake(8.0, 0.3)
			feedback.damage_number(pos + Vector2(0.0, -64.0), 0.0, "heal", "SECOND WIND")
		"thorns":
			feedback.impact(pos, Content.PAL.player_accent, true)
			feedback.blast(pos, Content.THORNS_RADIUS * 0.8)
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

## tier: 0 regular, 1 elite, 2 boss.
func _on_enemy_died(sc: int, pos: Vector2, tier: int, color: Color) -> void:
	# Falling out of a pit is cleanup, not a player kill or a cell reward.
	if sc <= 0:
		return
	_register_kill()
	var mult := Content.streak_multiplier(_streak_kills)
	score += int(round(float(sc) * mult))
	ui.set_score(score)
	_stats.kills += 1
	if is_instance_valid(player):
		player.on_enemy_killed()
	# Award cells (1 per regular enemy; 3 for an elite; 10 for the boss)
	var cells_gain := 1
	match tier:
		1:
			cells_gain = Content.ELITE_CELLS
			_stats.elites += 1
		2:
			cells_gain = 10
	_run_cells += cells_gain
	Save.add_cells(cells_gain)
	ui.set_cells(Save.get_cells())
	match tier:
		2:
			feedback.flash_death(pos, Content.BOSS_COLOR, true)
			feedback.shake(16.0, 0.5)
			feedback.hit_stop(0.16)
			feedback.play("die")
			feedback.play("elite", 0.8)
		1:
			feedback.flash_death(pos, Content.ELITE_COLOR, true)
			feedback.shake(9.0, 0.26)
			feedback.hit_stop(0.09)
			feedback.play("die")
			feedback.play("elite")
			feedback.damage_number(pos + Vector2(0.0, -66.0), 0.0, "elite", "ELITE SLAIN  +%d CELLS" % cells_gain)
		_:
			feedback.flash_death(pos, color)
			feedback.shake(6.0, 0.18)
			feedback.play("die")

func _on_room_cleared(room_name: String) -> void:
	feedback.play("clear")
	ui.show_room_clear(room_name)

func _on_room_completed() -> void:
	ui.hide_room_clear()
	# A streak belongs to the chamber it was built in.
	_streak_kills = 0
	_streak_t = 0.0
	_streak_tier = 0
	ui.hide_streak()
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
	Enemy.pyre_damage = float(run.build.get("pyre_dmg", 0.0))
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
	ui.show_run_summary(_stats, "gameover")
	ui.hide_streak()
	ui.hide_banners()
	get_tree().paused = true
	state = GState.GAME_OVER
	ui.hide_boss_bar()
	ui.show_panel("gameover")
	music.play_track("title")

func _on_boss_spawned() -> void:
	if is_instance_valid(room) and room.boss != null:
		ui.show_boss_bar(Content.BOSS_HP)
		ui.show_boss_intro("The Ember Warden", "Keeper of the Ember Throne")
		feedback.shake(8.0, 0.3)
		feedback.play("boss")
		music.play_track("boss")

func _on_boss_phase(phase: int) -> void:
	feedback.shake(10.0, 0.35)
	feedback.play("boss")
	if phase == 2:
		# Phase-2 callout renders as a compact floating tag above the boss bar,
		# never as a center-screen card over the fighters.
		ui.flash_boss_phase("THE WARDEN IGNITES")
		feedback.hit_stop(0.1)
		if is_instance_valid(room) and room.boss != null and is_instance_valid(room.boss):
			feedback.blast(room.boss.global_position, 200.0)

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
	ui.hide_streak()
	ui.hide_banners()
	ui.show_run_cells(_run_cells, "victory")
	ui.show_run_summary(_stats, "victory")
	ui.show_panel("victory")
	music.play_track("title")

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
	ui.hide_streak()
	ui.hide_banners()
	ui.hide_all_panels()
	ui.show_panel("title")
	state = GState.TITLE
	mood = Content.mood_for(0.0)
	RenderingServer.set_default_clear_color(mood.bg_top)
	_lights.set_ambient(mood.ambient)
	music.play_track("title")

func _on_option_toggled(key: String, value: bool) -> void:
	match key:
		"reduced_motion":
			feedback.set_reduced_motion(value)
			_atmosphere.set_reduced_motion(value)
		"reduced_flash":
			feedback.set_reduced_flash(value)
			if _vignette_rect != null and _vignette_rect.material is ShaderMaterial:
				(_vignette_rect.material as ShaderMaterial).set_shader_parameter("grain", 0.0 if value else VFX.GRAIN_DEFAULT)
		"music": music.set_enabled(value)

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
