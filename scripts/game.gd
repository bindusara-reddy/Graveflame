class_name Game
extends Node2D
## Root orchestrator: run lifecycle, room replacement, signal routing, pause, background.

const VFX := preload("res://scripts/vfx.gd")
const MusicSynth := preload("res://scripts/music.gd")
const BackdropPainter := preload("res://scripts/backdrop.gd")
const LightRig := preload("res://scripts/light_rig.gd")
const KnightArt := preload("res://scripts/knight_art.gd")
const GroundFire := preload("res://scripts/ground_fire.gd")

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
## Cells earned but not yet written to the save. Kills land inside physics
## steps, where file I/O must never run, so they wait for _bank_cells.
var _unbanked_cells := 0
## Tithe relic: every cell award is scaled by this.
var _cell_mul := 1.0
## Vows sworn for this descent, and the score multiplier they earn.
var _vows: Array = []
var _vow_mult := 1.0
# Kill streak: chained kills inside STREAK_WINDOW multiply score.
var _streak_kills := 0
var _streak_t := 0.0
var _streak_tier := 0
## Which screen OPTIONS was opened from, so BACK can return there.
var _options_return := "title"
## Seconds before another first-run lesson may appear, so two triggers in the
## same moment cannot stack into noise.
var _hint_cooldown := 0.0
## A lesson requested by a combat signal, resolved in _process. Teaching writes
## to the save file, and file I/O must never sit inside a physics callback where
## it can hitch a frame and shift combat timing.
var _queued_lesson := ""
## Lessons already taught on this save, read once per run so per-frame checks
## never touch the save file.
var _learned_lessons: Array = []
# Run statistics shown on the end screens.
var _stats: Dictionary = {}
## damage_taken when the current chamber began, to tell an untouched clear.
var _chamber_damage_mark := 0.0
var _vignette_rect: ColorRect
## The vignette's shader: retinted as health runs low, de-grained for reduced flash.
var _vignette_mat: ShaderMaterial
var _low_hp_t := 0.0
## Current depth palette; see Content.MOODS. Snaps per chamber under the rift fade.
var mood: Dictionary = Content.mood_for(0.0)
## Current chamber's depth band (Content.zone_for): picks the backdrop's architecture.
var zone := "crypt"
## A roofless chamber (template "open_sky"): its colonnade stands broken to a curtain wall.
var _open_sky := false
## The chamber's dressing salt (Room.dress_salt), re-dealing the backdrop's bays.
var dress_salt := 0
const VIGNETTE_EDGE := Color(0.027, 0.02, 0.043, 0.78)
const VIGNETTE_LOW_HP := Color(0.46, 0.04, 0.07, 0.92)
## Attack anticipation: a windup the player cannot hear reads as an unfair hit.
## RANGE bounds how far a tell carries; REFRACTORY stops a crowd stacking into noise.
const TELEGRAPH_RANGE := 620.0
const TELEGRAPH_REFRACTORY := 0.07
var _telegraph_at: Dictionary = {}
var _enemy_shot_frame := -1
# Visual layers. Lights and ambience are inserted before World so they draw above
# the backdrop but beneath platforms, actors and combat VFX.
const TORCH_Y := Content.FLOOR_Y - 200.0
## Flame scale of every wall sconce and its light; the finale sinks it when the
## throne goes cold.
var sconce_heat := 1.0
var _light_layer: Node2D
var _atmosphere: Node2D
var _vignette: CanvasLayer
## The world renders at the 1280x720 design size and is upscaled with linear
## filtering, so actors, environment and lighting share one smooth coherent frame.
var _world_container: SubViewportContainer
var world_view: SubViewport
var _backdrop: Node2D
var _foreground: Node2D
var _lights: Node2D
var _view_center := Vector2(Content.VIEW_W, Content.VIEW_H) * 0.5
var _atmo_t := 0.0
## Camera look-ahead (see _ease_look_ahead): px ahead of the knight, shorter
## beside a foe, eased at LOOK_EASE px/s and only while running faster than
## LOOK_RUN_SPEED.
const LOOK_AHEAD := 56.0
const LOOK_AHEAD_NEAR := 20.0
const LOOK_NEAR_RANGE := 320.0
const LOOK_EASE := 160.0
const LOOK_RUN_SPEED := 120.0
var _look_x := 0.0
## Throne-room framing: the camera leans this share of the way toward the
## Warden, capped, which keeps both fighters in view up to ~820 px apart.
const BOSS_FRAME_PULL := 0.38
const BOSS_FRAME_MAX := 260.0
## End-of-run beat. The run's state flips the instant it ends (death or the
## Warden falling), but the result screen waits: the world keeps playing in slow
## motion under a closing camera so the moment lands before the menu does.
const DEATH_BEAT := 1.9
const VICTORY_BEAT := 3.2
var _beat_kind := ""
var _beat_t := 0.0
var _beat_focus := Vector2.ZERO
var _beat_embers_at := 0.0
## The ending, from the Warden's killing blow until NEW RUN or RETURN TO TITLE.
var finale: Finale
## Held when the ending hands over to the results panel; its buttons wait until
## every one is released, so a held confirm cannot press NEW RUN.
const RELEASE_ACTIONS := ["ui_accept", "jump", "attack", "interact", "ignite", "pause"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_default_clear_color(mood.bg_top)
	# World viewport: backdrop, lights, world and feedback camera render inside it
	# at the 1280x720 design size; the UI stays outside.
	_world_container = SubViewportContainer.new()
	_world_container.name = "WorldView"
	_world_container.stretch = true
	_world_container.size = Vector2(Content.VIEW_W, Content.VIEW_H)
	_world_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_world_container)
	world_view = SubViewport.new()
	world_view.name = "Viewport"
	world_view.disable_3d = true
	world_view.handle_input_locally = false
	world_view.gui_disable_input = true
	world_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	_world_container.add_child(world_view)
	_backdrop = _add_layer(BackdropPainter.new(), "Backdrop", world_view)
	_backdrop.paint = _paint_backdrop
	# Additive lights and ambient particles (pausable, like the world they belong to).
	_light_layer = _add_layer(load("res://scripts/light_layer.gd").new(), "LightLayer", world_view)
	_light_layer.game = self
	_atmosphere = _add_layer(load("res://scripts/atmosphere.gd").new(), "Atmosphere", world_view)
	# World (pausable)
	world = _add_layer(Node2D.new(), "World", world_view)
	projectiles = _add_layer(Node2D.new(), "Projectiles", world)
	projectiles.z_index = 2
	# Foreground silhouettes: over the knight and creatures, under shots and effects.
	_foreground = _add_layer(BackdropPainter.new(), "Foreground", world_view)
	_foreground.paint = _paint_foreground
	_foreground.z_index = 1
	# Feedback (pausable): camera, particles, audio.
	feedback = _add_layer(Feedback.new(), "Feedback", world_view)
	feedback.z_index = 3
	# Real 2D lights over everything in the world viewport.
	_lights = _add_layer(LightRig.new(), "Lights", world_view)
	_lights.game = self
	_lights.set_ambient(mood.ambient)
	# Route synthesized audio through named buses so the options screen has
	# something to mix. Master already exists as bus 0.
	_ensure_audio_bus("Music")
	_ensure_audio_bus("SFX")
	_dress_audio_buses()
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
	_vignette_mat = VFX.vignette_material()
	_vignette_rect.material = _vignette_mat
	_vignette.add_child(_vignette_rect)
	_vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_vignette)
	# Wire UI signals
	ui.start_requested.connect(_begin_run)
	ui.resume_requested.connect(_on_resume)
	ui.restart_requested.connect(_begin_run)
	ui.quit_to_title_requested.connect(_on_quit_to_title)
	ui.upgrade_selected.connect(_on_upgrade_selected)
	ui.option_toggled.connect(_on_option_toggled)
	ui.forge_requested.connect(_on_forge_requested)
	ui.buy_meta_requested.connect(_on_buy_meta)
	ui.back_from_forge_requested.connect(_on_back_from_forge)
	# Menu feedback stays flat and dry: it is heard up close, at the cursor.
	ui.cue.connect(feedback.play)
	ui.options_requested.connect(_on_options_requested)
	ui.back_from_options_requested.connect(_on_back_from_options)
	ui.option_value_changed.connect(_on_option_value_changed)
	ui.keys_requested.connect(_on_keys_requested)
	ui.back_from_keys_requested.connect(_on_back_from_keys)
	ui.binding_changed.connect(_on_binding_changed)
	ui.vow_toggled.connect(_on_vow_toggled)
	# Show saved cells + best score on the HUD
	ui.set_cells(Save.get_cells())
	ui.set_best(Save.get_best_score())
	# Seed
	randomize()
	_seed = randi()
	_reset_stats()
	Save.migrate_falls()
	_restore_options()
	music.play_track("title")
	_set_world_shown(false)


## The title and its menus are opaque, so the world stops rendering and
## painting behind them instead of drawing unseen. Hiding the container pauses
## its SubViewport and a hidden CPUParticles2D stops simulating, but painters
## inside a SubViewport still count as visible, so their processing stops too.
## Feedback keeps running: it owns the camera and the sound pool menu cues use.
func _set_world_shown(shown: bool) -> void:
	_world_container.visible = shown
	_vignette.visible = shown
	_atmosphere.visible = shown
	for painter: Node in [_backdrop, _foreground, _light_layer, _lights]:
		painter.set_process(shown)


## Name `node` and add it under `parent`. World layers are pausable: they freeze
## with the game while the UI and music keep running.
func _add_layer(node: Node2D, layer_name: String, parent: Node) -> Node2D:
	node.name = layer_name
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	parent.add_child(node)
	return node


## Reapply the saved settings at boot so a relaunch honours them, then let the
## UI reflect the same values without firing the change handlers.
func _restore_options() -> void:
	var opts := Save.get_options()
	for key in ["reduced_motion", "reduced_flash", "fullscreen", "music_on", "vibration"]:
		_apply_toggle(key, bool(opts[key]))
	_apply_audio_options()
	Feedback.shake_scale = float(opts.shake)
	ui.sync_options(opts)
	_apply_bindings()


## Put one saved on/off setting into effect; boot and the settings screens share it.
func _apply_toggle(key: String, on: bool) -> void:
	match key:
		"reduced_motion":
			feedback.set_reduced_motion(on)
			_atmosphere.set_reduced_motion(on)
		"reduced_flash":
			feedback.set_reduced_flash(on)
			var grain := 0.0 if on else VFX.GRAIN_DEFAULT
			_vignette_mat.set_shader_parameter("grain", grain)
		"fullscreen":
			var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
			DisplayServer.window_set_mode(mode)
		"music_on":
			music.set_enabled(on)
		"vibration":
			Feedback.vibration = on


## The keep's acoustics: the score sits in a large stone hall, effects in a
## smaller, drier one so combat stays sharp, and a limiter on Master keeps a
## pile-up of impacts from clipping. Idempotent across reloads.
func _dress_audio_buses() -> void:
	var music := AudioServer.get_bus_index("Music")
	if music >= 0 and AudioServer.get_bus_effect_count(music) == 0:
		var hall := AudioEffectReverb.new()
		hall.room_size = 0.78
		hall.damping = 0.55
		hall.spread = 0.9
		hall.wet = 0.26
		hall.dry = 0.9
		hall.predelay_msec = 40.0
		AudioServer.add_bus_effect(music, hall)
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx >= 0 and AudioServer.get_bus_effect_count(sfx) == 0:
		var room := AudioEffectReverb.new()
		room.room_size = 0.42
		room.damping = 0.7
		room.wet = 0.1
		room.dry = 1.0
		room.predelay_msec = 12.0
		AudioServer.add_bus_effect(sfx, room)
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, limiter)

## Idempotent: a missing bus is added with the existing Master as its parent.
func _ensure_audio_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

func _reset_stats() -> void:
	# rooms counts chambers cleared, so a death at the throne never reads as a full clear.
	_stats = {
		"time": 0.0, "kills": 0, "elites": 0, "damage_dealt": 0.0, "damage_taken": 0.0,
		"best_streak": 0, "rooms": 0, "rooms_total": 0, "kills_by_kind": {},
		"parries": 0, "perfect_parries": 0, "ripostes": 0, "untouched_chambers": 0,
	}
	_break_streak()

## Drop the kill streak and its HUD meter.
func _break_streak() -> void:
	_streak_kills = 0
	_streak_t = 0.0
	_streak_tier = 0
	ui.hide_streak()

func _process(delta: float) -> void:
	_atmosphere.global_position = _view_center
	if not get_tree().paused and not Feedback.motion_reduced:
		_atmo_t += delta
	if not _beat_kind.is_empty():
		_step_beat(delta)
		return
	if state == GState.PLAYING and is_instance_valid(player):
		# Camera follows player, clamped to room bounds
		var cam := feedback.camera
		_ease_look_ahead(delta)
		var target := _camera_target_for(player.global_position)
		cam.global_position = cam.global_position.lerp(target, 8.0 * delta)
		# Update boss HP bar every frame
		var boss := _live_boss()
		if boss != null:
			ui.update_boss_bar(boss.hp)
		if is_instance_valid(room):
			ui.track_threats(room.enemies, world_view.get_canvas_transform())
		# Check player death handled by signal; check fall off world
		if player.global_position.y > Content.FLOOR_Y + 240:
			player.fall_out_of_world()
		if not get_tree().paused:
			_stats.time += delta
			_tick_streak(delta)
		_update_low_hp_vignette(delta)
		_teach_from_state(delta)
	elif not in_finale():
		_set_vignette(VIGNETTE_EDGE)


func _begin_beat(kind: String, focus: Vector2) -> void:
	ui.set_hud_faded(true)
	_beat_kind = kind
	_beat_t = 0.0
	_beat_focus = focus
	_beat_embers_at = 0.0

## Runs in unscaled time: Engine.time_scale is low for most of the beat.
func _step_beat(delta: float) -> void:
	var real_dt := minf(0.05, delta / maxf(Engine.time_scale, 0.001))
	_beat_t += real_dt
	var t := _beat_t
	var length := DEATH_BEAT if _beat_kind == "death" else VICTORY_BEAT
	var k := clampf(t / length, 0.0, 1.0)
	var cam := feedback.camera
	if not Feedback.motion_reduced:
		# Close in on the fallen (or the felled) and hold there.
		var push := 1.32 if _beat_kind == "death" else 1.2
		var zoom_to := Content.CAM_ZOOM * push
		cam.zoom = cam.zoom.lerp(Vector2.ONE * zoom_to, 1.0 - exp(-3.2 * real_dt))
		var focus := _beat_focus
		if _beat_kind == "death" and is_instance_valid(player):
			focus = player.global_position + Vector2(0.0, -18.0)
		cam.global_position = cam.global_position.lerp(focus, 1.0 - exp(-4.0 * real_dt))
	if _beat_kind == "death":
		# The frame bleeds to the low-health red, then toward the void.
		_set_vignette(VIGNETTE_LOW_HP.lerp(Color(0.02, 0.0, 0.02, 0.97), clampf((k - 0.45) / 0.55, 0.0, 1.0)))
	else:
		_set_vignette(VIGNETTE_EDGE)
		# Embers keep breaking off the Warden until it shatters.
		if is_instance_valid(room) and room.boss != null and is_instance_valid(room.boss) and room.boss.visible and t >= _beat_embers_at:
			_beat_embers_at = t + 0.12
			var bp: Vector2 = room.boss.global_position + Vector2(randf_range(-40.0, 40.0), randf_range(-60.0, 30.0))
			feedback.burst_sparks(bp, 6, 260.0, Content.PAL.player_accent)
	if t >= length:
		_finish_beat()

func _finish_beat() -> void:
	var kind := _beat_kind
	_beat_kind = ""
	feedback.end_slow_motion()
	if kind == "victory":
		# The finale takes the stage; the tree keeps running under it.
		finale.take_over()
		return
	feedback.stop_world_voices()
	get_tree().paused = true
	ui.show_panel("gameover", 0.6)
	# A slow rise, so the toll rings out into silence before the title.
	music.play_track("title", 3.0)

## Ends the end-of-run beat at once (a skip during the victory's slow motion).
func _cancel_beat() -> void:
	_beat_kind = ""
	feedback.end_slow_motion()

func in_finale() -> bool:
	return is_instance_valid(finale)

## The ending hands over to the results panel, shown over its closed-curtain
## theatre. Held keys stay locked out until released, so a celebratory jump
## cannot press NEW RUN.
func _on_finale_finished(skipped: bool) -> void:
	feedback.stop_world_voices()
	get_tree().paused = true
	ui.set_victory_extras(Content.flame_ordinal(int(finale.ctx.victories)), bool(finale.ctx.first))
	ui.show_panel("victory", 0.0 if skipped else 0.6)
	ui.lock_until_released("victory", RELEASE_ACTIONS)
	music.stop_cues(1.4)
	music.play_track("title")

## Ends any finale before the next screen: it puts back what it borrowed from
## the world, then goes with its layers and cast.
func _end_finale() -> void:
	if not in_finale():
		return
	finale.abort()
	remove_child(finale)
	finale.queue_free()
	finale = null

## Put the camera back to the locked play framing (after a beat pushed it in).
func _reset_camera() -> void:
	ui.set_hud_faded(false)
	feedback.end_slow_motion()
	feedback.camera.zoom = Vector2.ONE * Content.CAM_ZOOM

## Contextual first-run teaching. Each lesson fires the first time the situation
## that makes it useful actually arises, then never again for that save. The
## player cannot discover parry timing or the riposte follow-up from a bindings
## list, so these are taught where they matter.
func _teach(id: String) -> void:
	if _hint_cooldown > 0.0 or _learned_lessons.has(id):
		return
	var text: String = Content.HINTS.get(id, "")
	if text.is_empty():
		return
	Save.mark_learned(id)
	_learned_lessons.append(id)
	ui.show_hint(text)
	_hint_cooldown = 6.0


func _teach_from_state(delta: float) -> void:
	_hint_cooldown = maxf(0.0, _hint_cooldown - delta)
	if not is_instance_valid(player) or get_tree().paused:
		return
	# A lesson requested by a combat signal takes precedence over ambient ones.
	if not _queued_lesson.is_empty():
		var queued := _queued_lesson
		_queued_lesson = ""
		_teach(queued)
		return
	# Wall slide is the only reliable signal that a wall jump is available.
	if player.wall_sliding:
		_teach("wall_jump")
		return
	# Falling with no jumps left, and nothing underfoot to land on.
	if not player.is_on_floor() and player.velocity.y > 260.0 and player.jumps_left <= 0:
		_teach("slam")
		return
	# Hurt and still holding a charge: the moment a flask is worth remembering.
	if player.flask_charges > 0 and float(player.build.get("hp", 0.0)) <= float(player.build.get("max_hp", 100.0)) * 0.4:
		_teach("flask")

func _tick_streak(delta: float) -> void:
	if _streak_kills <= 0:
		return
	_streak_t -= delta
	if _streak_t <= 0.0:
		_break_streak()
		return
	ui.set_streak_fraction(_streak_t / Content.STREAK_WINDOW)

func _register_kill() -> void:
	_streak_kills = _streak_kills + 1 if _streak_t > 0.0 else 1
	_streak_t = Content.STREAK_WINDOW
	_stats.best_streak = maxi(int(_stats.best_streak), _streak_kills)
	var tier := Content.streak_tier(_streak_kills)
	if tier > _streak_tier:
		# Tiers climb the home triad above the cue's D: F, A, D, F.
		var semitones: int = [0, 3, 7, 12, 15][mini(tier, 4)]
		feedback.play("streak", pow(2.0, float(semitones) / 12.0))
	_streak_tier = tier
	ui.set_streak(_streak_kills, 1.0, Content.streak_multiplier(_streak_kills))

## The vignette bleeds red as the flame gutters, pulsing faster the lower it gets.
func _update_low_hp_vignette(delta: float) -> void:
	var frac := float(player.build.hp) / maxf(1.0, float(player.build.max_hp))
	var low := clampf((0.34 - frac) / 0.34, 0.0, 1.0)
	music.set_muffle(low)
	if low <= 0.0:
		_low_hp_t = 0.0
		_set_vignette(VIGNETTE_EDGE)
		return
	if not get_tree().paused and not Feedback.motion_reduced:
		_low_hp_t += delta * (3.5 + low * 4.0)
		feedback.heartbeat(_low_hp_t, low)
	var pulse := 0.5 + 0.5 * sin(_low_hp_t) if not Feedback.motion_reduced else 0.5
	var strength := low * (0.5 + 0.5 * pulse) * (0.45 if Feedback.flash_reduced else 1.0)
	_set_vignette(VIGNETTE_EDGE.lerp(VIGNETTE_LOW_HP, strength))

func _set_vignette(edge: Color) -> void:
	_vignette_mat.set_shader_parameter("edge_color", feedback.vignette_edge(edge))

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
	# Under-floor pit: the floor line falls away into absolute void.
	VFX.draw_vgradient(ci, Rect2(left, horizon, span, 320.0), m.bg_bot, m.pit)
	ci.draw_rect(Rect2(left, horizon + 320.0, span, 520.0), m.pit)
	var seep := float(m.ember_seep)
	# The ashpit's smoke veils its fires, so their glow reaches the air ash-grey
	# and the embers themselves stay the only hot colour in the pit.
	var ember: Color = (m.glow as Color).lerp(m.fog, 0.6) if zone == "ashpit" else m.glow
	if seep > 0.0:
		# Magma light seeping up from the depths as the keep warms.
		VFX.draw_vgradient(ci, Rect2(left, horizon + 120.0, span, 420.0), Color(ember, 0.0), Color(ember, 0.2 * seep))
	# From here each plane lifts itself for vertical parallax (see _lift).
	_draw_stars(ci, horizon)
	_draw_moon(ci, horizon)
	# Distant furnace bloom low on the horizon, behind the spires.
	_lift(ci, 0.1)
	var bloom := Vector2(_plane_x(0.1, 184.0), horizon - 60.0)
	for i in range(4, 0, -1):
		ci.draw_circle(bloom, 90.0 + float(i) * 72.0, Color(ember, (0.016 + float(5 - i) * 0.012) * (1.0 + seep)))
	# The middle planes are the zone's own architecture; the sky, undercroft and
	# fog are shared. The throne's apse stands in for all of them, unlifted: the
	# throne room has no climbing, so its apse never needs vertical parallax.
	if _in_throne_room():
		ci.draw_set_transform(Vector2.ZERO)
		_paint_throne_apse(ci, horizon)
	else:
		match zone:
			"works":
				_draw_stacks(ci, horizon)
				_draw_trusses(ci, horizon)
			"ashpit":
				_draw_crags(ci, horizon)
				_draw_ruin_arches(ci, horizon)
			_:
				_draw_spires(ci, horizon)
				if _open_sky:
					_draw_curtain_wall(ci, horizon)
				else:
					_draw_arches(ci, horizon)
		_draw_light_shafts(ci, top, horizon)
		_draw_buttresses(ci, horizon)
		_draw_rubble(ci, horizon)
	_draw_undercroft(ci, horizon)
	ci.draw_set_transform(Vector2.ZERO)
	_draw_fog(ci, horizon)

## The backdrop's per-bay dice. Salted per chamber, so every chamber deals its
## own bays, banners, chains and mounds from the same planes.
func _plane_hash(k: int, channel: int) -> float:
	return VFX.hash01(k + dress_salt, channel)

## Visible repeat-index range for a plane at `depth` whose elements repeat every `period`.
func _plane_range(depth: float, period: float, margin: float) -> Vector2i:
	var half := float(Content.VIEW_W) * 0.5 + margin
	return Vector2i(floori((_view_center.x * depth - half) / period), ceili((_view_center.x * depth + half) / period))

func _plane_x(depth: float, layer_x: float) -> float:
	return layer_x + _view_center.x * (1.0 - depth)

## The camera's height standing on the floor, where every plane was composed.
const REST_Y := Content.FLOOR_Y - 140.0

## Vertical parallax: how far a plane at `depth` rides up with the camera as it
## climbs above its floor rest, so far planes lag the platforms instead of the
## moon sinking behind them. Halved so every plane's base stays under the deck
## for as long as the deck is on screen.
func _plane_dy(depth: float) -> float:
	return (_view_center.y - REST_Y) * (1.0 - depth) * 0.5

## Offset the canvas for a plane at `depth`; the painter resets it before the fog.
func _lift(ci: CanvasItem, depth: float) -> void:
	ci.draw_set_transform(Vector2(0.0, _plane_dy(depth)))

## How strongly the farthest plane is pulled toward the mood's atmosphere.
const DEPTH_HAZE := 0.6

## Aerial perspective. Parallax alone only moves planes; without haze they all
## keep the same contrast and the scene reads as stacked cutouts rather than as
## receding space. Each plane is pushed toward the mood's own fog by how far away
## it sits, so distance costs contrast the way it does in air.
## `depth` is 0 at the far plane, 1 at the play plane.
func _haze(color: Color, depth: float) -> Color:
	return color.lerp(mood.fog, clampf((1.0 - depth) * DEPTH_HAZE, 0.0, 1.0))

## Sconce flame positions on the midground buttresses; the light layer stacks
## its torch glows on exactly these points.
## Asked for twice per frame (additive glow pass and PointLight rig), so the
## result is cached within a frame. Callers only read it.
var _torch_cache := PackedVector2Array()
var _torch_frame := -1

func torch_positions() -> PackedVector2Array:
	var frame := Engine.get_process_frames()
	if frame == _torch_frame:
		return _torch_cache
	var out := PackedVector2Array()
	if _in_throne_room():
		out = _apse_sconces()
	else:
		var r := _plane_range(0.65, 320.0, 160.0)
		for k in range(r.x, r.y + 1):
			out.append(Vector2(_plane_x(0.65, float(k) * 320.0), TORCH_Y - 12.0 + _plane_dy(0.65)))
	_torch_cache = out
	_torch_frame = frame
	return out

func _draw_stars(ci: CanvasItem, horizon: float) -> void:
	var vis := float(mood.stars)
	if vis <= 0.01:
		return
	var depth := 0.04
	_lift(ci, depth)
	var period := 90.0
	var r := _plane_range(depth, period, 60.0)
	var moving := not Feedback.motion_reduced
	for k in range(r.x, r.y + 1):
		for j in range(3):
			var h := _plane_hash(k * 7 + j, 51)
			var x := _plane_x(depth, float(k) * period + _plane_hash(k, 52 + j) * period)
			var y := horizon - 500.0 + _plane_hash(k, 55 + j) * 260.0
			var tw := 0.5 + 0.5 * sin(_atmo_t * (1.0 + h * 2.0) + float(k)) if moving else 0.7
			ci.draw_circle(Vector2(x, y), 0.8 + h * 1.3, Color(0.85, 0.88, 1.0, (0.2 + 0.5 * tw) * vis))

## A cold moon over the crypt that reddens into a furnace sun deeper down.
## Placed to land in the open sky between the HUD's corner panels and above the
## chamber banner (screen x ~800-840, y ~105 on the floor), where the crescent-to-
## furnace-sun progression can be seen. The throne's closed vault hides it.
func _draw_moon(ci: CanvasItem, horizon: float) -> void:
	var col: Color = mood.moon
	var a := float(mood.moon_alpha)
	if a <= 0.01:
		return
	_lift(ci, 0.06)
	var c := Vector2(_plane_x(0.06, 195.0), horizon - 362.0)
	for i in range(5, 0, -1):
		ci.draw_circle(c, 64.0 + float(i) * 30.0, Color(col, 0.016 * a * float(6 - i)))
	ci.draw_circle(c, 64.0, Color(col, 0.95 * a))
	for i in range(6):
		var off := Vector2(VFX.hash01(i, 61) - 0.5, VFX.hash01(i, 62) - 0.5) * 85.0
		ci.draw_circle(c + off, 4.0 + VFX.hash01(i, 63) * 11.0, Color(col.darkened(0.28), 0.5 * a))
	# Crescent bite in the crypt; it fills in as the moods warm.
	var bite := float(mood.stars)
	if bite > 0.01:
		ci.draw_circle(c + Vector2(31.0, -20.0), 59.0, Color(mood.bg_top, 0.85 * bite))

## A vertical shaft lit by a broad source: brightest a third of the way in from
## the lit edge, falling away toward the rim and the shadowed return. Filling a
## column with one flat colour (or two or three bands) is what made every pillar
## read as a cut-paper bar instead of a rounded mass.
func _draw_shaft(ci: CanvasItem, x: float, w: float, top: float, bottom: float, stone: Color) -> void:
	var hi := stone.lightened(0.20)
	var lo := stone.darkened(0.22)
	var steps := 8
	var h := bottom - top
	for i in range(steps):
		var u0 := float(i) / float(steps)
		var u1 := float(i + 1) / float(steps)
		var mid := (u0 + u1) * 0.5
		var lit := pow(maxf(0.0, cos((mid - 0.30) * 2.1)), 2.0)
		ci.draw_rect(Rect2(x + w * u0, top, w * (u1 - u0) + 0.6, h), lo.lerp(hi, lit))


func _draw_spires(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.15
	_lift(ci, depth)
	var period := 150.0
	var col: Color = _haze(mood.spire, depth)
	# Fenestration is emissive, but a light this far back is seen through air:
	# leaving it at full torch brightness is what makes the towers read as pasted
	# on top of the scene instead of behind it.
	var window_col: Color = _haze(mood.torch, depth)
	var r := _plane_range(depth, period, 120.0)
	var base := horizon + 80.0
	var mass_top := horizon - 150.0
	# Vertical form. A plane filled with one constant colour reads as cut paper;
	# a ramp (darker aloft, lifting toward the base where the hall's light pools)
	# gives the mass a sense of standing height instead of being a flat shape.
	var spire_lo := col.lightened(0.08)
	var spire_hi := col.darkened(0.22)
	VFX.draw_vgradient(ci, Rect2(_plane_x(depth, float(r.x) * period) - period, mass_top, float(r.y - r.x + 2) * period, base - mass_top), spire_hi, spire_lo)
	for k in range(r.x, r.y + 1):
		var h := 300.0 + _plane_hash(k, 1) * 120.0
		var w := 58.0 + _plane_hash(k, 2) * 32.0
		var x := _plane_x(depth, float(k) * period + _plane_hash(k, 3) * 40.0)
		var spire_top := base - h
		# Per-vertex ramp, indexed to the point order below: the two base corners
		# stay lifted while everything above the shoulder falls into shadow.
		ci.draw_polygon(PackedVector2Array([
			Vector2(x - w * 0.5, base), Vector2(x - w * 0.5, spire_top + 40.0), Vector2(x - w * 0.28, spire_top + 14.0),
			Vector2(x - w * 0.1, spire_top + 4.0), Vector2(x, spire_top - 26.0), Vector2(x + w * 0.1, spire_top + 6.0),
			Vector2(x + w * 0.3, spire_top + 18.0), Vector2(x + w * 0.5, spire_top + 44.0), Vector2(x + w * 0.5, base),
		]), PackedColorArray([
			spire_lo, spire_hi, spire_hi, spire_hi, spire_hi,
			spire_hi, spire_hi, spire_hi, spire_lo,
		]))
		# Slit windows keep the towers reading as inhabited ruins; a few flicker.
		for wi in range(3):
			var wy := spire_top + 80.0 + float(wi) * 64.0 + _plane_hash(k + wi, 4) * 30.0
			var lit := _plane_hash(k, 5 + wi)
			var flick := 1.0 if Feedback.motion_reduced else 0.85 + 0.15 * sin(_atmo_t * 3.0 + float(k * 3 + wi))
			ci.draw_rect(Rect2(x - 2.0 + (float(wi % 2) - 0.5) * 10.0, wy, 4.0, 14.0), Color(window_col, (0.06 + lit * 0.16) * flick))

func _draw_arches(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.35
	_lift(ci, depth)
	var period := 200.0
	var wall: Color = _haze(mood.wall, depth)
	var edge: Color = _haze(mood.edge, depth)
	var r := _plane_range(depth, period, 160.0)
	var base := horizon + 60.0
	var arch_top := horizon - 340.0
	var x_start := _plane_x(depth, float(r.x) * period) - period
	var width := float(r.y - r.x + 2) * period
	var moving := not Feedback.motion_reduced
	# Vertical form on the masses, and an occlusion band where the colonnade
	# passes under the entablature. That contact shadow is what makes the layers
	# stack into a space instead of floating as independent cutouts.
	var wall_hi := wall.darkened(0.16)
	var wall_lo := wall.lightened(0.05)
	# Entablature above the colonnade plus its ground course.
	VFX.draw_vgradient(ci, Rect2(x_start, arch_top - 34.0, width, 34.0), wall_hi, wall_lo)
	ci.draw_line(Vector2(x_start, arch_top - 34.0), Vector2(x_start + width, arch_top - 34.0), edge, 2.0)
	VFX.draw_vgradient(ci, Rect2(x_start, base - 24.0, width, 24.0), wall_lo, wall_hi)
	VFX.draw_vgradient(ci, Rect2(x_start, arch_top, width, 54.0), Color(0.0, 0.0, 0.0, 0.34), Color(0.0, 0.0, 0.0, 0.0))
	for k in range(r.x, r.y + 1):
		var cx := _plane_x(depth, float(k) * period)
		var glazed := _plane_hash(k, 11) > 0.6
		if glazed:
			# A walled bay: leaded rose window glowing with the mood's light.
			ci.draw_rect(Rect2(cx - 52.0, arch_top + 100.0, 104.0, base - arch_top - 100.0), wall.darkened(0.12))
			# The bay is recessed, so its opening is darker than the frame around
			# it and lifts toward the floor course.
			VFX.draw_vgradient(ci, Rect2(cx - 52.0, arch_top + 100.0, 104.0, base - arch_top - 100.0), Color(0.0, 0.0, 0.0, 0.26), Color(0.0, 0.0, 0.0, 0.06))
			var wc := Vector2(cx, arch_top + 158.0)
			var glass: Color = _haze(mood.glass, depth)
			var breathe := 0.22 + (0.06 * sin(_atmo_t * 1.3 + float(k)) if moving else 0.0)
			ci.draw_circle(wc, 44.0, Color(glass, 0.06))
			ci.draw_circle(wc, 27.0, Color(glass, breathe))
			for i in range(6):
				var a := float(i) * PI / 3.0
				ci.draw_line(wc, wc + Vector2(cos(a), sin(a)) * 27.0, edge.darkened(0.3), 2.0)
			ci.draw_arc(wc, 27.0, 0.0, TAU, 24, edge.darkened(0.3), 2.5)
			ci.draw_arc(wc, 12.0, 0.0, TAU, 16, edge.darkened(0.3), 1.5)
		# Pillars and the spandrel over an open arch; the sky shows through the opening.
		_draw_shaft(ci, cx - 80.0, 28.0, arch_top, base, wall)
		_draw_shaft(ci, cx + 52.0, 28.0, arch_top, base, wall)
		_draw_spandrel(ci, cx, arch_top, wall, edge)
		# Heraldic banners hang from the entablature on some bays.
		if _plane_hash(k, 12) > 0.62:
			var by := arch_top - 30.0
			var bl := 150.0 + _plane_hash(k, 13) * 70.0
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
		if _plane_hash(k, 7) > 0.35:
			var length := 80.0 + _plane_hash(k, 8) * 100.0
			var sway := sin(_atmo_t * 0.7 + float(k)) * 4.0 if moving else 0.0
			ci.draw_dashed_line(Vector2(cx, arch_top - 34.0), Vector2(cx + sway, arch_top - 34.0 + length), edge, 2.0, 6.0)
		if _plane_hash(k, 9) > 0.7:
			var drop := 240.0 + _plane_hash(k, 10) * 220.0
			var sway2 := sin(_atmo_t * 0.5 + float(k) * 1.9) * 6.0 if moving else 0.0
			ci.draw_dashed_line(Vector2(cx + 46.0, -560.0), Vector2(cx + 46.0 + sway2, -560.0 + drop), edge, 2.0, 6.0)

## The wall over an open arch between a bay's two pillars, with its moulded
## intrados. Shared by the crypt colonnade and the ashpit's ruin of it.
func _draw_spandrel(ci: CanvasItem, cx: float, arch_top: float, wall: Color, edge: Color) -> void:
	var spandrel := PackedVector2Array([Vector2(cx - 80.0, arch_top), Vector2(cx + 80.0, arch_top), Vector2(cx + 80.0, arch_top + 110.0)])
	for i in range(13):
		var a := -PI * float(i) / 12.0
		spandrel.append(Vector2(cx, arch_top + 110.0) + Vector2(cos(a), sin(a)) * 52.0)
	spandrel.append(Vector2(cx - 80.0, arch_top + 110.0))
	ci.draw_colored_polygon(spandrel, wall)
	ci.draw_arc(Vector2(cx, arch_top + 110.0), 52.0, PI, TAU, 16, edge, 1.5)

## Crypt yard, middle plane: the colonnade's outer curtain wall, roofless and
## broken to a jagged top 180-260px over the floor, so the yard opens on the sky.
## The stumps of its pillars still stand proud of the wall.
func _draw_curtain_wall(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.35
	_lift(ci, depth)
	var period := 200.0
	var wall: Color = _haze(mood.wall, depth)
	var edge: Color = _haze(mood.edge, depth)
	var r := _plane_range(depth, period, 160.0)
	var base := horizon + 60.0
	for k in range(r.x, r.y + 1):
		var x := _plane_x(depth, float(k) * period)
		var crest := PackedVector2Array()
		for i in range(6):
			crest.append(Vector2(x + float(i) * period / 5.0, horizon - 220.0 + (_plane_hash(k * 6 + i, 16) - 0.5) * 80.0))
		var mass := crest.duplicate()
		mass.append(Vector2(x + period, base))
		mass.append(Vector2(x, base))
		VFX.draw_shaded_polygon(ci, mass, wall)
		ci.draw_polyline(crest, edge, 1.5)
		var stump := horizon - 250.0 - _plane_hash(k, 17) * 60.0
		_draw_shaft(ci, x - 14.0, 28.0, stump, base, wall)
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(x - 14.0, stump + 6.0), Vector2(x - 6.0, stump - 8.0), Vector2(x + 2.0, stump + 2.0), Vector2(x + 14.0, stump - 6.0), Vector2(x + 14.0, stump + 8.0),
		]), wall)

## Works, far plane: foundry chimney stacks over a sawtooth shed roofline, each
## breathing a slow smoke plume. It stands where the crypt's spires stand, so
## the foundry reads as its own skyline rather than the crypt recoloured.
func _draw_stacks(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.15
	_lift(ci, depth)
	var period := 150.0
	var col: Color = _haze(mood.spire, depth)
	var mouth: Color = _haze(mood.torch, depth)
	var smoke: Color = _haze((mood.fog as Color).lightened(0.1), depth)
	var r := _plane_range(depth, period, 120.0)
	var base := horizon + 80.0
	var roof := horizon - 170.0
	var lit := col.lightened(0.08)
	var shade := col.darkened(0.22)
	VFX.draw_vgradient(ci, Rect2(_plane_x(depth, float(r.x) * period) - period, roof, float(r.y - r.x + 2) * period, base - roof), shade, lit)
	for k in range(r.x, r.y + 1):
		var x := _plane_x(depth, float(k) * period)
		# One shed tooth per bay: a steep glazed face catching the furnace light.
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x, roof), Vector2(x + 30.0, roof - 46.0), Vector2(x + period, roof)]), shade)
		ci.draw_line(Vector2(x + 3.0, roof - 3.0), Vector2(x + 28.0, roof - 42.0), Color(mouth, 0.16), 2.0)
		if _plane_hash(k, 1) < 0.3:
			continue
		var w := 40.0 + _plane_hash(k, 2) * 30.0
		var top := base - 380.0 - _plane_hash(k, 3) * 80.0
		var sx := x + 50.0 + _plane_hash(k, 4) * 60.0
		ci.draw_polygon(PackedVector2Array([
			Vector2(sx - w * 0.5, base), Vector2(sx - w * 0.42, top), Vector2(sx + w * 0.42, top), Vector2(sx + w * 0.5, base),
		]), PackedColorArray([lit, shade, shade, lit]))
		# Cap band, half again as wide as the stack, over a furnace-lit mouth.
		ci.draw_rect(Rect2(sx - w * 0.75, top - 14.0, w * 1.5, 14.0), shade.lightened(0.05))
		ci.draw_rect(Rect2(sx - w * 0.6, top - 16.0, w * 1.2, 2.0), Color(mouth, 0.3))
		# Five puffs climb and lean downwind at 6px/s, thinning as they rise.
		for i in range(5):
			var rise := fmod(_atmo_t * 6.0 + float(i) * 36.0 + _plane_hash(k, 5) * 36.0, 180.0)
			var puff := Vector2(sx + rise * 0.5, top - 22.0 - rise)
			VFX.draw_ellipse(ci, puff, 16.0 + rise * 0.22, 10.0 + rise * 0.1, Color(smoke, 0.2 * (1.0 - rise / 180.0)))

## Works, middle plane: an iron foundry hall. Posts carry riveted A-frame trusses
## over open bays, so the stacks show through above a brick dado; grated furnace
## ports glow in some bays and a crucible hangs on a chain in every third.
func _draw_trusses(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.35
	_lift(ci, depth)
	var period := 240.0
	var wall: Color = _haze(mood.wall, depth)
	var iron: Color = _haze((mood.edge as Color).darkened(0.35), depth)
	var rivet: Color = _haze(mood.edge, depth)
	var glow: Color = _haze(mood.glass, depth)
	var r := _plane_range(depth, period, 160.0)
	var base := horizon + 60.0
	var lintel := horizon - 360.0
	var dado := horizon - 200.0
	var x_start := _plane_x(depth, float(r.x) * period) - period
	var width := float(r.y - r.x + 2) * period
	var moving := not Feedback.motion_reduced
	VFX.draw_vgradient(ci, Rect2(x_start, dado, width, base - dado), wall.darkened(0.12), wall.lightened(0.05))
	ci.draw_rect(Rect2(x_start, dado - 8.0, width, 8.0), iron)
	ci.draw_rect(Rect2(x_start, lintel, width, 20.0), iron)
	for i in range(int(width / 24.0)):
		ci.draw_circle(Vector2(x_start + 12.0 + float(i) * 24.0, lintel + 10.0), 2.0, rivet)
	for k in range(r.x, r.y + 1):
		var cx := _plane_x(depth, float(k) * period)
		var bay := cx + period * 0.5
		var apex := Vector2(bay, lintel - 110.0)
		ci.draw_line(Vector2(cx, lintel), apex, iron, 14.0)
		ci.draw_line(Vector2(cx + period, lintel), apex, iron, 14.0)
		ci.draw_line(apex, Vector2(bay, lintel), iron, 6.0)
		_draw_shaft(ci, cx - 12.0, 24.0, lintel, base, iron)
		if _plane_hash(k, 11) > 0.55:
			# A grated furnace port breathing in the dado, where the crypt has glass.
			var port := Vector2(bay, dado + 84.0)
			var breathe := 0.24 + (0.06 * sin(_atmo_t * 1.3 + float(k)) if moving else 0.0)
			ci.draw_circle(port, 46.0, Color(glow, 0.06))
			ci.draw_circle(port, 34.0, Color(glow, breathe))
			for i in range(8):
				var dx := -30.0 + float(i) * 60.0 / 7.0
				var dy := sqrt(34.0 * 34.0 - dx * dx)
				ci.draw_line(Vector2(port.x + dx, port.y - dy), Vector2(port.x + dx, port.y + dy), iron, 2.5)
			ci.draw_arc(port, 34.0, 0.0, TAU, 24, iron, 4.0)
		if posmod(k + dress_salt, 3) == 0:
			# A crucible slung from the truss, its molten rim catching the light.
			var sway := sin(_atmo_t * 0.6 + float(k)) * 4.0 if moving else 0.0
			var cup := Vector2(bay + sway, lintel + 140.0 + _plane_hash(k, 12) * 60.0)
			ci.draw_dashed_line(Vector2(bay, lintel + 20.0), cup, rivet, 2.0, 6.0)
			ci.draw_colored_polygon(PackedVector2Array([cup + Vector2(-20.0, 0.0), cup + Vector2(20.0, 0.0), cup + Vector2(13.0, 28.0), cup + Vector2(-13.0, 28.0)]), iron)
			ci.draw_line(cup + Vector2(-21.0, 1.0), cup + Vector2(21.0, 1.0), Color(glow, 0.55), 2.0)

## Ashpit, far plane: a cave roof of hanging rock teeth over a ridge of broken
## crags. The ashpit lies under the keep, so stone closes its sky.
func _draw_crags(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.15
	_lift(ci, depth)
	var period := 150.0
	var col: Color = _haze(mood.spire, depth)
	var lit := col.lightened(0.08)
	var shade := col.darkened(0.22)
	var r := _plane_range(depth, period, 120.0)
	var x_start := _plane_x(depth, float(r.x) * period) - period
	var width := float(r.y - r.x + 2) * period
	var roof := horizon - 420.0
	var base := horizon + 80.0
	ci.draw_rect(Rect2(x_start, -560.0, width, roof + 560.0), shade)
	VFX.draw_vgradient(ci, Rect2(x_start, horizon - 120.0, width, base - horizon + 120.0), shade, lit)
	for k in range(r.x, r.y + 1):
		var x := _plane_x(depth, float(k) * period)
		# Five to nine stalactites per bay, their tips lifting toward the light.
		var teeth := 5 + int(_plane_hash(k, 1) * 5.0)
		var step := period / float(teeth)
		for i in range(teeth):
			var h := _plane_hash(k * 9 + i, 2)
			var tx := x + float(i) * step
			ci.draw_polygon(PackedVector2Array([
				Vector2(tx, roof - 1.0), Vector2(tx + step, roof - 1.0), Vector2(tx + step * (0.3 + 0.4 * h), roof + 20.0 + h * 100.0),
			]), PackedColorArray([shade, shade, lit]))
		# One broken crag on the far ridge per bay.
		var w := 70.0 + _plane_hash(k, 3) * 60.0
		var peak := base - 200.0 - _plane_hash(k, 4) * 140.0
		var cx := x + _plane_hash(k, 5) * 60.0
		ci.draw_polygon(PackedVector2Array([
			Vector2(cx - w * 0.5, base), Vector2(cx - w * 0.36, peak + 60.0), Vector2(cx - w * 0.12, peak + 18.0), Vector2(cx, peak),
			Vector2(cx + w * 0.18, peak + 34.0), Vector2(cx + w * 0.34, peak + 26.0), Vector2(cx + w * 0.5, base),
		]), PackedColorArray([lit, shade, shade, shade, shade, shade, lit]))

## Ashpit, middle plane: the crypt colonnade after the collapse. Every other bay
## has lost its spandrel and had its pillars snapped at 40-80% height, and roots
## spill from the broken end of each surviving stretch of entablature.
func _draw_ruin_arches(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.35
	_lift(ci, depth)
	var period := 200.0
	var wall: Color = _haze(mood.wall, depth)
	var edge: Color = _haze(mood.edge, depth)
	var root: Color = _haze(Color("2b1d12").lerp(mood.stone, 0.2), depth)
	var r := _plane_range(depth, period, 160.0)
	var base := horizon + 60.0
	var arch_top := horizon - 340.0
	var moving := not Feedback.motion_reduced
	for k in range(r.x, r.y + 1):
		var cx := _plane_x(depth, float(k) * period)
		var standing := posmod(k + dress_salt, 2) == 0
		for side in range(2):
			var px := cx - 80.0 + float(side) * 132.0
			var top := arch_top
			if not standing:
				top = base - (base - arch_top) * (0.4 + _plane_hash(k * 2 + side, 14) * 0.4)
			_draw_shaft(ci, px, 28.0, top, base, wall)
			if not standing:
				ci.draw_colored_polygon(PackedVector2Array([
					Vector2(px, top + 6.0), Vector2(px + 6.0, top - 8.0), Vector2(px + 13.0, top + 2.0), Vector2(px + 20.0, top - 12.0), Vector2(px + 28.0, top + 4.0),
				]), wall)
		if not standing:
			continue
		ci.draw_rect(Rect2(cx - 100.0, arch_top - 34.0, 200.0, 34.0), wall.darkened(0.16))
		ci.draw_line(Vector2(cx - 100.0, arch_top - 34.0), Vector2(cx + 100.0, arch_top - 34.0), edge, 2.0)
		_draw_spandrel(ci, cx, arch_top, wall, edge)
		for i in range(5):
			var rx := cx + 76.0 + float(i) * 6.0
			var fall := 60.0 + _plane_hash(k * 5 + i, 15) * 130.0
			var sway := sin(_atmo_t * 0.8 + float(k + i)) * 3.0 if moving else 0.0
			ci.draw_polyline(PackedVector2Array([
				Vector2(rx, arch_top - 20.0), Vector2(rx + 5.0 + sway, arch_top + fall * 0.4),
				Vector2(rx - 3.0 + sway, arch_top + fall * 0.75), Vector2(rx + 2.0 + sway * 1.5, arch_top + fall),
			]), root, 3.0 - float(i) * 0.4)

## Slanted shafts of moon or furnace light falling between the bays.
func _draw_light_shafts(ci: CanvasItem, top: float, horizon: float) -> void:
	var col: Color = mood.moon
	var strength := 0.03 * (0.5 + 0.5 * float(mood.stars)) + 0.025 * float(mood.ember_seep)
	var depth := 0.3
	_lift(ci, depth)
	var period := 420.0
	var r := _plane_range(depth, period, 260.0)
	var moving := not Feedback.motion_reduced
	for k in range(r.x, r.y + 1):
		if _plane_hash(k, 71) < 0.4:
			continue
		var x := _plane_x(depth, float(k) * period + _plane_hash(k, 72) * 200.0)
		var w := 60.0 + _plane_hash(k, 73) * 90.0
		var sway := sin(_atmo_t * 0.25 + float(k)) * 18.0 if moving else 0.0
		var lean := 140.0 + _plane_hash(k, 74) * 80.0
		ci.draw_polygon(PackedVector2Array([
			Vector2(x, top), Vector2(x + w, top),
			Vector2(x + w + lean + sway, horizon + 40.0), Vector2(x + lean + sway - w * 0.6, horizon + 40.0),
		]), PackedColorArray([Color(col, strength), Color(col, strength), Color(col, 0.0), Color(col, 0.0)]))

func _draw_buttresses(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.65
	_lift(ci, depth)
	var period := 320.0
	var stone: Color = _haze(mood.stone, depth)
	var frame := Color(VFX.MORTAR, 0.55)
	var r := _plane_range(depth, period, 160.0)
	var base := horizon + 60.0
	var top := horizon - 470.0
	var moving := not Feedback.motion_reduced
	var torch: Color = mood.torch
	for k in range(r.x, r.y + 1):
		var x := _plane_x(depth, float(k) * period)
		# Pilaster with capital and plinth, lit as a round shaft rather than a bar.
		_draw_shaft(ci, x - 22.0, 44.0, top, base, stone)
		ci.draw_rect(Rect2(x - 30.0, top, 60.0, 14.0), stone.lightened(0.08))
		ci.draw_rect(Rect2(x - 28.0, horizon - 40.0, 56.0, 40.0), stone.lightened(0.05))
		ci.draw_line(Vector2(x - 22.0, top), Vector2(x - 22.0, base), Color(VFX.RIM, 0.18), 1.5)
		if zone == "works":
			# The foundry strapped its old stone with iron.
			for i in range(3):
				ci.draw_rect(Rect2(x - 25.0, top + 70.0 + float(i) * 120.0, 50.0, 8.0), stone.darkened(0.4))
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
		VFX.draw_flame(ci, sconce + Vector2(0.0, -4.0), 24.0 * sconce_heat, 12.0 * sconce_heat, t, float(k) * 2.1, torch, VFX.GOLD)
		# Soot streak above the sconce.
		ci.draw_rect(Rect2(sconce.x - 5.0, sconce.y - 70.0, 10.0, 44.0), Color(0.0, 0.0, 0.0, 0.18))

## Stone mounds and bones along the back wall, just behind the play plane.
## The ashpit is where the keep's ruin ends up, so it lies twice as thick there,
## with bones scattered through it.
func _draw_rubble(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.85
	_lift(ci, depth)
	var ashpit := zone == "ashpit"
	var period := 130.0 if ashpit else 260.0
	var r := _plane_range(depth, period, 120.0)
	var stone: Color = _haze(mood.stone, depth)
	for k in range(r.x, r.y + 1):
		if _plane_hash(k, 81) < 0.45:
			continue
		var x := _plane_x(depth, float(k) * period + _plane_hash(k, 82) * 160.0)
		var w := 40.0 + _plane_hash(k, 83) * 70.0
		var h := 14.0 + _plane_hash(k, 84) * 26.0
		var pts := PackedVector2Array([Vector2(x - w * 0.5, horizon + 40.0)])
		for i in range(1, 6):
			var u := float(i) / 6.0
			pts.append(Vector2(x - w * 0.5 + u * w, horizon - h * (0.5 + 0.5 * sin(u * PI)) * (0.7 + _plane_hash(k + i, 85) * 0.5)))
		pts.append(Vector2(x + w * 0.5, horizon + 40.0))
		ci.draw_colored_polygon(pts, stone.darkened(0.35))
		ci.draw_polyline(pts, Color(VFX.RIM, 0.2), 1.0)
		var bone := Color("8f877a")
		if _plane_hash(k, 86) > (0.3 if ashpit else 0.6):
			var sk := Vector2(x + (_plane_hash(k, 87) - 0.5) * w * 0.5, horizon - h * 0.5 - 4.0)
			ci.draw_circle(sk, 5.0, bone)
			ci.draw_circle(sk + Vector2(-2.0, -1.0), 1.4, VFX.VOID)
			ci.draw_circle(sk + Vector2(2.0, -1.0), 1.4, VFX.VOID)
		if ashpit and _plane_hash(k, 88) > 0.4:
			# Two long bones crossed on the heap.
			var b := Vector2(x - w * 0.2, horizon - h * 0.4)
			ci.draw_line(b + Vector2(-12.0, 2.0), b + Vector2(12.0, -5.0), bone.darkened(0.15), 3.0)
			ci.draw_line(b + Vector2(-8.0, -6.0), b + Vector2(10.0, 3.0), bone.darkened(0.25), 3.0)

## A drowned lower colonnade under the floor line, fading into the pit.
func _draw_undercroft(ci: CanvasItem, horizon: float) -> void:
	var depth := 0.5
	_lift(ci, depth)
	var period := 260.0
	var r := _plane_range(depth, period, 160.0)
	var wall: Color = _haze(mood.wall, depth)
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
		if _plane_hash(k, 121) > 0.5:
			var len := 40.0 + _plane_hash(k, 122) * 90.0
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

# --- Throne apse ---
## The Ember Throne's hall is a closed apse and the finale's stage: a rose window
## over the throne, colossal columns carrying the sconces, and kneeling statues
## of past bearers. Offsets are from the throne with the view centred on it.
const APSE_COLUMNS := [-560.0, -300.0, 300.0, 560.0]
const APSE_STATUES := [-420.0, 420.0]
## A kneeling stone knight facing +x, feet at the origin, back to front: plinth,
## kneeling leg, the arm raising a torch cup, torso, planted leg, the sword set
## point-down and the hand resting on its pommel.
const STATUE := [
	[Vector2(-64, 0), Vector2(66, 0), Vector2(60, -24), Vector2(-58, -24)],
	[Vector2(-58, -24), Vector2(-4, -24), Vector2(-8, -40), Vector2(-54, -36)],
	[Vector2(-12, -26), Vector2(8, -34), Vector2(-14, -104), Vector2(-38, -98)],
	[Vector2(-24, -192), Vector2(-8, -186), Vector2(-20, -246), Vector2(-36, -244)],
	[Vector2(-40, -92), Vector2(16, -104), Vector2(34, -172), Vector2(16, -194), Vector2(-22, -186), Vector2(-44, -140)],
	[Vector2(-26, -98), Vector2(38, -104), Vector2(44, -86), Vector2(-18, -76)],
	[Vector2(22, -24), Vector2(54, -24), Vector2(46, -38), Vector2(42, -96), Vector2(22, -90)],
	[Vector2(58, -120), Vector2(66, -120), Vector2(64, -30), Vector2(62, -22), Vector2(60, -30)],
	[Vector2(46, -127), Vector2(78, -127), Vector2(78, -120), Vector2(46, -120)],
	[Vector2(60, -146), Vector2(64, -146), Vector2(64, -127), Vector2(60, -127)],
	[Vector2(6, -188), Vector2(26, -182), Vector2(64, -158), Vector2(58, -146), Vector2(16, -164)],
]
const STATUE_CUP := [Vector2(-46, -266), Vector2(-12, -266), Vector2(-20, -250), Vector2(-38, -250)]

## The boss room paints the throne apse and hangs its sconces there.
func _in_throne_room() -> bool:
	return is_instance_valid(room) and room.is_boss

## World x of an apse element `offset` from the throne on the plane at `depth`:
## exact with the view centred on the throne, parallaxing like every plane.
func _centred_x(depth: float, offset: float) -> float:
	return 640.0 + offset + (_view_center.x - 640.0) * (1.0 - depth)

## The throne's sconces hang on its columns, so its torch lights do too.
func _apse_sconces() -> PackedVector2Array:
	var out := PackedVector2Array()
	for offset in APSE_COLUMNS:
		out.append(Vector2(_centred_x(0.5, offset), TORCH_Y - 12.0))
	return out

## The throne room's mid planes, in place of the crypt's open colonnade: the
## vault is closed, so no sky, moon or spires show behind the Warden.
func _paint_throne_apse(ci: CanvasItem, horizon: float) -> void:
	var t := _atmo_t if not Feedback.motion_reduced else 0.0
	var wall: Color = _haze(mood.wall, 0.35)
	var left := Content.ROOM_LEFT - 240.0
	var span := Content.ROOM_RIGHT + 240.0 - left
	VFX.draw_vgradient(ci, Rect2(left, -560.0, span, horizon + 620.0), wall.darkened(0.55), wall)
	for i in range(1, 11):
		var y := horizon - 56.0 * float(i)
		ci.draw_line(Vector2(left, y), Vector2(left + span, y), Color(_haze(mood.edge, 0.35), 0.3), 1.5)
	_draw_rose_window(ci, Vector2(_centred_x(0.35, 0.0), horizon - 300.0), 150.0, t)
	for i in range(APSE_COLUMNS.size()):
		_draw_apse_column(ci, _centred_x(0.5, APSE_COLUMNS[i]), horizon, t, float(i) * 2.1)
	for offset in APSE_STATUES:
		_draw_statue(ci, Vector2(_centred_x(0.65, offset), horizon + 4.0), -signf(offset))

## The rose window in its recessed bay: twelve glass petals round a roundel that
## holds the Warden's sigil, burning as the throne's own sigil does, so it
## gutters and relights gold with it. The glass backlights the Warden.
func _draw_rose_window(ci: CanvasItem, c: Vector2, radius: float, t: float) -> void:
	var edge: Color = _haze(mood.edge, 0.35)
	var glass: Color = _haze(mood.glass, 0.35)
	# A pointed bay cut into the apse: two arcs meeting over the window.
	var half := radius + 50.0
	var bay := PackedVector2Array([Vector2(c.x - half, c.y + 360.0)])
	for i in range(7):
		var a := PI + PI / 3.0 * float(i) / 6.0
		bay.append(Vector2(c.x + half, c.y) + Vector2(cos(a), sin(a)) * half * 2.0)
	for i in range(1, 7):
		var a := -PI / 3.0 + PI / 3.0 * float(i) / 6.0
		bay.append(Vector2(c.x - half, c.y) + Vector2(cos(a), sin(a)) * half * 2.0)
	bay.append(Vector2(c.x + half, c.y + 360.0))
	ci.draw_colored_polygon(bay, _haze(mood.wall, 0.35).darkened(0.35))
	ci.draw_polyline(bay, edge, 3.0)
	ci.draw_circle(c, radius * 1.18, Color(glass, 0.08))
	ci.draw_circle(c, radius, Color("0a0508"))
	var r0 := radius * 0.4
	var reach := radius * 0.9 - r0
	var w := radius * 0.13
	for i in range(12):
		var a := TAU * float(i) / 12.0 - PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var petal := PackedVector2Array()
		for q: Vector2 in [Vector2(0.0, 0.0), Vector2(0.35, 0.7), Vector2(0.75, 1.0), Vector2(1.0, 0.45), Vector2(1.0, -0.45), Vector2(0.75, -1.0), Vector2(0.35, -0.7)]:
			petal.append(c + dir * (r0 + reach * q.x) + side * w * q.y)
		ci.draw_colored_polygon(petal, Color(glass, 0.55 + 0.1 * sin(t * 1.3 + float(i))))
		petal.append(petal[0])
		ci.draw_polyline(petal, edge.darkened(0.3), 2.0)
	var heat: float = room.sigil_flare()
	var fire: Color = (mood.torch as Color).lerp(VFX.GOLD, room.sigil_gold)
	ci.draw_circle(c, radius * 0.34, Color(glass, 0.35))
	if heat > 0.02:
		VFX.draw_flame(ci, c + Vector2(0.0, radius * 0.2), radius * 0.4 * heat, radius * 0.2, t, 0.0, Color(fire, minf(1.0, 0.9 * heat)), VFX.GOLD.lerp(VFX.HOT, room.sigil_gold))
	ci.draw_arc(c, radius * 0.34, 0.0, TAU, 32, edge, 6.0)
	ci.draw_arc(c, radius, 0.0, TAU, 48, edge, 14.0)

## A colossal column rising into the dark, bound by chains, with the cresset
## whose flame sinks with sconce_heat.
func _draw_apse_column(ci: CanvasItem, x: float, horizon: float, t: float, phase: float) -> void:
	var stone: Color = _haze(mood.stone, 0.5)
	var chain: Color = _haze(mood.edge, 0.5).darkened(0.2)
	_draw_shaft(ci, x - 42.0, 84.0, -560.0, horizon + 60.0, stone)
	ci.draw_line(Vector2(x - 42.0, -560.0), Vector2(x - 42.0, horizon), Color(VFX.RIM, 0.16), 1.5)
	ci.draw_rect(Rect2(x - 52.0, horizon - 84.0, 104.0, 14.0), stone.lightened(0.08))
	ci.draw_rect(Rect2(x - 60.0, horizon - 70.0, 120.0, 70.0), stone.lightened(0.04))
	for i in range(3):
		var y := horizon - 170.0 - 150.0 * float(i)
		ci.draw_dashed_line(Vector2(x - 44.0, y), Vector2(x + 44.0, y - 46.0), chain, 3.0, 7.0)
	ci.draw_dashed_line(Vector2(x + 44.0, horizon - 516.0), Vector2(x + 30.0, -560.0), chain, 3.0, 7.0)
	var at := Vector2(x, TORCH_Y)
	ci.draw_rect(Rect2(at.x - 4.0, at.y, 8.0, 26.0), Color("1a1024"))
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-16.0, -6.0), at + Vector2(16.0, -6.0), at + Vector2(9.0, 6.0), at + Vector2(-9.0, 6.0)]), VFX.MORTAR)
	VFX.draw_flame(ci, at + Vector2(0.0, -6.0), 30.0 * sconce_heat, 16.0 * sconce_heat, t, phase, mood.torch, VFX.GOLD)

## A kneeling stone knight, a past bearer of the flame, turned toward the throne
## (`side` +1 faces right). The torch cup it raises is charred and cold.
func _draw_statue(ci: CanvasItem, foot: Vector2, side: float) -> void:
	var stone: Color = _haze(mood.stone, 0.65)
	ci.draw_set_transform(foot, 0.0, Vector2(side, 1.0))
	for part in STATUE:
		var pts := PackedVector2Array(part)
		VFX.draw_shaded_polygon(ci, pts, stone)
		VFX.draw_rim(ci, pts, 1.0, 0.5, mood.torch)
	ci.draw_circle(Vector2(24.0, -204.0), 17.0, stone)
	ci.draw_line(Vector2(28.0, -206.0), Vector2(40.0, -204.0), VFX.VOID, 2.0)
	ci.draw_circle(Vector2(62.0, -150.0), 5.0, stone.darkened(0.2))
	ci.draw_colored_polygon(PackedVector2Array(STATUE_CUP), Color("1a1216"))
	ci.draw_polyline(PackedVector2Array(STATUE_CUP), Color(VFX.SLATE, 0.5), 1.5)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
## Foreground parallax depth: nearer than the play plane, so it slides past faster
## than the world. Its pillars stand nearer still.
const FG_DEPTH := 1.3
const FG_INK := Color("05040a")

## Paper silhouettes between the camera and the fight, in three places only:
## along the floor's face (never above the deck, never over a pit), hanging from
## the top of the view, and a rare full-height pillar. A silhouette with a
## fighter behind it fades, so the layer frames the fight but never hides it.
func _paint_foreground(ci: CanvasItem) -> void:
	if not is_instance_valid(room):
		return
	_view_center = feedback.camera.get_screen_center_position()
	var half := Vector2(Content.VIEW_W, Content.VIEW_H) * 0.5 / feedback.camera.zoom
	var view := Rect2(_view_center - half, half * 2.0)
	var rim := Color((mood.edge as Color).lightened(0.2), 0.8)
	_draw_fg_floor(ci, view, rim)
	# The throne keeps its vault and its duel clear: only the balustrade.
	if zone != "throne":
		_draw_fg_top(ci, view)
		_draw_fg_pillars(ci, view, rim)

## Along the floor's face: headstones in the crypt, half-sunk gears in the works,
## charred roots in the ashpit, a balustrade before the throne. Tops stop 28px
## under the deck so feet stay clear, and pits are left open.
func _draw_fg_floor(ci: CanvasItem, view: Rect2, rim: Color) -> void:
	var bottom := view.end.y + 8.0
	var ceiling := Content.FLOOR_Y + 28.0
	if bottom - ceiling < 12.0:
		return
	if zone == "throne":
		var rail := maxf(bottom - 60.0, ceiling)
		ci.draw_rect(Rect2(view.position.x - 20.0, rail, view.size.x + 40.0, 10.0), FG_INK)
		ci.draw_line(Vector2(view.position.x - 20.0, rail), Vector2(view.end.x + 20.0, rail), rim, 1.5)
		var posts := _plane_range(FG_DEPTH, 34.0, 40.0)
		for k in range(posts.x, posts.y + 1):
			var x := _plane_x(FG_DEPTH, float(k) * 34.0)
			var belly := (rail + bottom) * 0.5
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(x - 4.0, rail), Vector2(x + 4.0, rail), Vector2(x + 9.0, belly), Vector2(x + 3.0, bottom), Vector2(x - 3.0, bottom), Vector2(x - 9.0, belly),
			]), FG_INK)
			if posmod(k, 6) == 0:
				ci.draw_circle(Vector2(x, rail - 7.0), 8.0, FG_INK)
		return
	var r := _plane_range(FG_DEPTH, 380.0, 260.0)
	var pits: Array = room.template.get("hazards", [])
	for k in range(r.x, r.y + 1):
		if _plane_hash(k, 141) > 0.55:
			continue
		var x := _plane_x(FG_DEPTH, float(k) * 380.0 + _plane_hash(k, 142) * 200.0)
		var top := maxf(bottom - 40.0 - _plane_hash(k, 143) * 70.0, ceiling)
		if pits.any(func(pit: Rect2) -> bool: return x > pit.position.x - 70.0 and x < pit.end.x + 70.0):
			continue
		match zone:
			"works":
				var hub := Vector2(x, bottom + 10.0)
				var radius := hub.y - top
				var teeth := PackedVector2Array()
				for i in range(24):
					teeth.append(hub + Vector2.from_angle(TAU * float(i) / 24.0) * (radius if i % 2 == 0 else radius * 0.86))
				ci.draw_colored_polygon(teeth, FG_INK)
				ci.draw_arc(hub, radius * 0.86, PI * 1.15, PI * 1.85, 16, rim, 1.5)
			"ashpit":
				for i in range(3):
					var rx := x - 22.0 + float(i) * 22.0
					var tip := top + float(i % 2) * 18.0
					ci.draw_polyline(PackedVector2Array([Vector2(rx, bottom), Vector2(rx + 8.0, (tip + bottom) * 0.5), Vector2(rx - 6.0, tip)]), FG_INK, 9.0 - float(i) * 2.0)
			_:
				var w := 26.0 + _plane_hash(k, 144) * 16.0
				ci.draw_rect(Rect2(x - w * 0.5, top + w * 0.5, w, bottom - top - w * 0.5), FG_INK)
				ci.draw_circle(Vector2(x, top + w * 0.5), w * 0.5, FG_INK)
				ci.draw_arc(Vector2(x, top + w * 0.5), w * 0.5, PI, TAU, 12, rim, 1.5)

## Hanging from the top of the view, never more than 60px into it: sagging
## chains, some carrying a smouldering censer, or a curtain of roots in the ashpit.
func _draw_fg_top(ci: CanvasItem, view: Rect2) -> void:
	var r := _plane_range(FG_DEPTH, 460.0, 240.0)
	var top := view.position.y - 4.0
	for k in range(r.x, r.y + 1):
		if _plane_hash(k, 151) > 0.5:
			continue
		var x := _plane_x(FG_DEPTH, float(k) * 460.0 + _plane_hash(k, 152) * 160.0)
		var fade := _fg_alpha(Rect2(x - 64.0, top, 128.0, 64.0))
		var ink := Color(FG_INK, fade)
		if zone == "ashpit":
			for i in range(5):
				var rx := x - 40.0 + float(i) * 20.0
				var drop := 26.0 + _plane_hash(k * 5 + i, 153) * 36.0
				ci.draw_polyline(PackedVector2Array([Vector2(rx, top), Vector2(rx + 5.0, top + drop * 0.5), Vector2(rx - 2.0, top + drop)]), ink, 5.0 - float(i % 3))
			continue
		var sag := PackedVector2Array()
		for i in range(9):
			var u := float(i) / 8.0
			sag.append(Vector2(x - 60.0 + u * 120.0, top + 4.0 + 140.0 * u * (1.0 - u)))
		ci.draw_polyline(sag, ink, 4.0)
		if _plane_hash(k, 154) > 0.5:
			var cup := Vector2(x + 34.0, top + 44.0)
			ci.draw_line(Vector2(cup.x, top), cup, ink, 2.0)
			ci.draw_colored_polygon(PackedVector2Array([cup + Vector2(-9.0, 0.0), cup + Vector2(9.0, 0.0), cup + Vector2(5.0, 12.0), cup + Vector2(-5.0, 12.0)]), ink)
			ci.draw_circle(cup + Vector2(0.0, 3.0), 2.0, Color(mood.torch, 0.7 * fade))

## A rare full-height pillar sliding past close to the camera, lit down one edge.
func _draw_fg_pillars(ci: CanvasItem, view: Rect2, rim: Color) -> void:
	var depth := 1.45
	var r := _plane_range(depth, 900.0, 340.0)
	for k in range(r.x, r.y + 1):
		if _plane_hash(k, 161) > 0.5:
			continue
		var x := _plane_x(depth, float(k) * 900.0 + _plane_hash(k, 162) * 300.0)
		var shaft := Rect2(x - 35.0, view.position.y - 10.0, 70.0, view.size.y + 20.0)
		var fade := _fg_alpha(shaft)
		ci.draw_rect(shaft, Color(FG_INK, fade))
		ci.draw_rect(Rect2(shaft.end.x - 16.0, shaft.position.y, 10.0, shaft.size.y), Color(FG_INK.lightened(0.05), fade))
		ci.draw_line(shaft.position + Vector2(1.0, 0.0), Vector2(shaft.position.x + 1.0, shaft.end.y), Color(rim, rim.a * fade), 1.5)

## Opacity for a foreground silhouette over `area`: full with nobody behind it,
## thinning to 0.3 as the knight or a creature comes within 70px, so a fighter
## always shows through.
func _fg_alpha(area: Rect2) -> float:
	var nearest := INF
	var fighters: Array = room.enemies.duplicate()
	fighters.append(player)
	for f in fighters:
		if is_instance_valid(f):
			var p: Vector2 = f.global_position
			nearest = minf(nearest, Vector2(maxf(0.0, maxf(area.position.x - p.x, p.x - area.end.x)), maxf(0.0, maxf(area.position.y - p.y, p.y - area.end.y))).length())
	return lerpf(0.3, 1.0, clampf((nearest - 70.0) / 80.0, 0.0, 1.0))

# --- Run lifecycle ---
## Clear every trace of the current run: its finale (first, so it can put back
## what it borrowed), its closing beat, the camera, the chamber, projectiles,
## the knight and the run's HUD cards.
func _teardown_run() -> void:
	_end_finale()
	_beat_kind = ""
	_reset_camera()
	_clear_room()
	_clear_projectiles()
	if is_instance_valid(player):
		player.queue_free()
		player = null
	ui.hide_boss_bar()
	ui.hide_streak()
	ui.hide_banners()

func _begin_run() -> void:
	_set_world_shown(true)
	_teardown_run()
	score = 0
	_run_cells = 0
	_reset_stats()
	_learned_lessons = Save.get_learned_hints()
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
	run.offer_count = Content.UPGRADES_PER_OFFER + int(meta.get("offer_count", 0))
	_cell_mul = 1.0 + float(meta.get("cell_mul", 0.0))
	# Vows only bind once the Warden has fallen at least once.
	_vows = Save.get_vows() if Save.vows_unlocked() else []
	Enemy.vows = {}
	for v in _vows:
		Enemy.vows[v] = true
	_vow_mult = Content.vow_score_multiplier(_vows)
	_cell_mul += 0.1 * float(_vows.size())
	var kindled := ""
	if bool(meta.get("start_boon", false)):
		# Kindled Blood: one common boon, drawn from the run's own seed.
		var commons: Array = Content.UPGRADES.filter(func(u): return Content.upgrade_rarity(u) == "common" and str(u.kind) != "heal" and str(u.kind) != "max_hp")
		if not commons.is_empty():
			var gift: Dictionary = commons[run.rng.randi_range(0, commons.size() - 1)]
			run.apply_upgrade(gift)
			kindled = str(gift.title)
	# create player
	player = Player.new()
	# Physics order is independent of painter order. The player processes first
	# for parries, but must never disappear behind the throne or room props.
	player.z_index = 1
	player.add_to_group("player")
	player.setup(run)
	player.feedback = feedback
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
	get_tree().paused = false
	paused = false
	state = GState.PLAYING
	music.play_track("explore")
	if not kindled.is_empty():
		feedback.damage_number(player.global_position + Vector2(0.0, -70.0), 0.0, "elite", "KINDLED: " + kindled.to_upper())

func _advance_room() -> void:
	_clear_room()
	_clear_projectiles()
	ui.hide_room_clear()
	var tmpl := run.advance_to_next_room()
	var is_boss := run.is_boss_room()
	zone = Content.zone_for(str(tmpl.tag))
	_open_sky = bool(tmpl.get("open_sky", false))
	mood = Content.mood_for_zone(zone, _zone_progress())
	RenderingServer.set_default_clear_color(mood.bg_top)
	_lights.set_ambient(mood.ambient)
	_atmosphere.set_zone(zone, mood)
	room = Room.new()
	room.mood = mood
	room.setup(tmpl, is_boss, player, run.rng.randi())
	dress_salt = room.dress_salt
	if not is_boss:
		var hp_frac := float(run.build.hp) / maxf(1.0, float(run.build.max_hp))
		room.exit_kinds = run.roll_exits(hp_frac)
	# A Trial taken in the last chamber is paid at the throne (Trial of the Throne).
	room.trial = run.trial_next
	run.trial_next = false
	room.room_index = run.room_index
	room.run_seed = run.seed_value
	# Connect before _ready() because boss_spawned and the first wave happen there.
	room.completed.connect(_on_room_completed)
	room.cleared.connect(_on_room_cleared)
	room.enemy_died.connect(_on_enemy_died)
	room.enemy_damaged.connect(_on_enemy_damaged)
	room.pyre_burst.connect(_on_pyre_burst)
	room.projectile_requested.connect(_spawn_projectile)
	room.boss_spawned.connect(_on_boss_spawned)
	room.boss_phase_changed.connect(_on_boss_phase)
	room.enemy_exploded.connect(_on_enemy_exploded)
	room.enemy_spawned.connect(feedback.spawn_rift)
	room.wave_started.connect(_on_wave_started)
	room.telegraphed.connect(_on_enemy_telegraphed)
	room.enemy_announced.connect(_on_enemy_announced)
	room.lesson_requested.connect(_teach)
	room.prop_shattered.connect(feedback.shatter)
	room.boss_shattered.connect(_on_boss_shattered)
	room.boss_wave_requested.connect(_spawn_boss_wave)
	Enemy.pyre_damage = float(run.build.get("pyre_dmg", 0.0))
	world.add_child(room)
	# position player at entry
	var entry := room.get_entry_point()
	player.respawn_at(entry)
	player.suppress_gameplay_input()
	_chamber_damage_mark = float(_stats.damage_taken)
	# Snap across the rift instead of briefly lerping from the previous exit.
	_look_x = 0.0
	feedback.camera.global_position = _camera_target_for(entry)
	# UI
	ui.set_room(run.room_index, run.rooms_total())
	# The page burns open from where the knight arrives.
	var arrive := (entry - feedback.camera.global_position) * feedback.camera.zoom + Vector2(Content.VIEW_W, Content.VIEW_H) * 0.5
	ui.fade_from_black(0.45, arrive / Vector2(Content.VIEW_W, Content.VIEW_H))
	# The rift that swallowed the last chamber sets the knight down in this one.
	feedback.play("rift", 0.8, -6.0)
	if not is_boss:
		ui.show_room_intro(run.room_index, run.rooms_total(), Content.room_name(tmpl), room.trial)
	else:
		# The throne room is one continuous fight, so it carries no wave counter.
		ui.hide_wave()

## How far through its zone's stretch of the route this chamber sits: 0 at the
## zone's first chamber, 1 at its last. Lets the palette lean toward the next zone.
func _zone_progress() -> float:
	var first := run.room_index
	var last := run.room_index
	while first > 0 and Content.zone_for(str(run.route[first - 1].tag)) == zone:
		first -= 1
	while last < run.route.size() - 1 and Content.zone_for(str(run.route[last + 1].tag)) == zone:
		last += 1
	return float(run.room_index - first) / float(maxi(1, last - first))

func _camera_target_for(pos: Vector2) -> Vector2:
	var target := pos
	if state == GState.PLAYING:
		var boss := _live_boss()
		if boss != null:
			# The Warden is framed with the knight, so it never winds up off-screen.
			var pull := (boss.global_position.x - pos.x) * BOSS_FRAME_PULL
			target.x += clampf(pull, -BOSS_FRAME_MAX, BOSS_FRAME_MAX)
		else:
			target.x += _look_x
	# The zoom narrows the view, so the half-width the clamp keeps inside the room
	# is the zoomed one; the unzoomed width hid ~85px at each end of every room,
	# where the knight and enemies could stand and fight entirely off-screen.
	var half_w := Content.VIEW_W * 0.5 / Content.CAM_ZOOM
	var lim_l := Content.ROOM_LEFT + half_w
	var lim_r := Content.ROOM_RIGHT - half_w
	target.x = clampf(target.x, lim_l, lim_r)
	target.y = clampf(target.y, 200.0, Content.FLOOR_Y - 140.0)
	return target

## Look-ahead gives a swing room to land on screen. It eases toward the facing
## side and only follows a running knight, so turning on the spot to parry no
## longer pans the whole frame; beside a foe it shortens to keep the fight centred.
func _ease_look_ahead(delta: float) -> void:
	if absf(player.velocity.x) <= LOOK_RUN_SPEED:
		return
	var reach := LOOK_AHEAD_NEAR if _foe_within(LOOK_NEAR_RANGE) else LOOK_AHEAD
	_look_x = move_toward(_look_x, player.facing * reach, LOOK_EASE * delta)

## Whether a live foe stands within `distance` of the knight: the fight is
## close, so the look-ahead shortens to keep it centred.
func _foe_within(distance: float) -> bool:
	for e in room.enemies:
		if is_instance_valid(e) and not e.dead and e.global_position.distance_to(player.global_position) < distance:
			return true
	return false

## The Warden while it still fights, else null.
func _live_boss() -> Boss:
	if is_instance_valid(room) and is_instance_valid(room.boss) and not room.boss.dead:
		return room.boss
	return null

func _clear_room() -> void:
	if is_instance_valid(room):
		room.despawn()
		room = null

func _clear_projectiles() -> void:
	if is_instance_valid(projectiles):
		for c in projectiles.get_children():
			c.queue_free()

# --- Signal handlers ---
func _on_player_hit(_damage: float, pos: Vector2, heavy: bool) -> void:
	feedback.impact(pos, Content.PAL.player_accent if player._flame_time > 0.0 else Content.PAL.attack, heavy, Vector2(player.facing, -0.2))
	feedback.hit_stop(0.065 if heavy else 0.045)
	feedback.shake(6.0 if heavy else 3.0, 0.14 if heavy else 0.08)
	feedback.play("hit_heavy" if heavy else "hit", 1.0 if heavy else 1.0 + 0.07 * float(player.attack_index))
	feedback.rumble(0.35 if heavy else 0.2, 0.25 if heavy else 0.0, 0.08)

func _on_player_hurt(amount: float, pos: Vector2) -> void:
	feedback.flash_hurt(pos)
	feedback.shake(7.0, 0.18)
	feedback.play("hurt")
	feedback.rumble(0.3, 0.7, 0.2)
	feedback.damage_number(pos + Vector2(0.0, -44.0), amount, "hurt")
	_stats.damage_taken += amount

func _on_enemy_damaged(amount: float, pos: Vector2, blocked: bool) -> void:
	if blocked:
		feedback.damage_number(pos, amount, "block", "BLOCKED")
		return
	feedback.damage_number(pos, amount, "heavy" if amount >= 40.0 else "hit")
	_stats.damage_dealt += amount

## Voice every windup, attenuated by distance from the player. The refractory
## keeps a room full of simultaneous tells readable instead of deafening.
func _on_enemy_telegraphed(kind: String, pos: Vector2, _elite: bool) -> void:
	# Range first: an inaudible enemy must never consume another's cue. The
	# Warden's own moves (Boss.Action names) carry across its whole throne room.
	var distance := 0.0
	if is_instance_valid(player):
		distance = player.global_position.distance_to(pos)
	var boss_tell := Boss.Action.has(kind.to_upper())
	if distance > TELEGRAPH_RANGE and not boss_tell:
		return
	var cue := "tell_" + kind
	var now := float(Time.get_ticks_msec()) * 0.001
	if now - float(_telegraph_at.get(cue, -1.0)) < TELEGRAPH_REFRACTORY:
		return
	_telegraph_at[cue] = now
	var falloff := clampf(1.0 - distance / TELEGRAPH_RANGE, 0.5 if boss_tell else 0.06, 1.0)
	feedback.play(cue, 1.0, linear_to_db(falloff))
	# A close windup is exactly when parry timing needs to be explained. Queue
	# it: this runs inside the enemy's physics step.
	if distance < 260.0:
		_queued_lesson = "parry"

## A creature's beat worth naming or voicing: a broken guard, a ring-out, an
## elite's oath. Either part may be empty.
func _on_enemy_announced(text: String, cue: String, pos: Vector2) -> void:
	if not cue.is_empty():
		feedback.play(cue)
	if not text.is_empty():
		feedback.damage_number(pos, 0.0, "elite", text)

## The chamber's wave count is always on the HUD; only later waves call out,
## because the first lands under the chamber card that already names the room.
func _on_wave_started(current: int, total: int) -> void:
	ui.set_wave(current, total)
	music.set_intensity(1.0, 0.8)
	if current > 1:
		feedback.play("wave")

func _on_pyre_burst(pos: Vector2, radius: float) -> void:
	feedback.blast(pos, radius)
	feedback.burst(pos, 22, Content.PAL.player_accent, 320.0)
	feedback.shake(5.0, 0.16)
	feedback.play("pyre")

func _on_player_action(kind: String, pos: Vector2) -> void:
	_tally_action(kind)
	match kind:
		"swing":
			var heavy_swing := player.is_finisher()
			feedback.play("riposte" if player._riposte_attack else ("swing_heavy" if heavy_swing else "swing"))
			if not player._riposte_attack:
				feedback.slash(pos + Vector2(player.facing * 28.0, -8.0), player.facing, Content.PAL.player_accent if player._flame_time > 0.0 else Content.PAL.attack, heavy_swing)
		"swing_active":
			# Additive afterglow along the sweep the blade is about to travel.
			var def: Dictionary = player.get_meta("atk_def")
			if player._riposte_attack:
				feedback.riposte_cut(pos + Vector2(player.facing * 8.0, -8.0), player.facing, float(def.range))
			else:
				var sweep: Array = KnightArt.SWINGS[KnightArt.swing_name(player)].smear
				feedback.slash_arc(pos + Vector2(player.facing * 7.0, -9.0), player.facing, float(def.range), float(sweep[0]), float(sweep[1]), player.is_finisher())
		"jump": feedback.play("jump")
		"dash":
			feedback.play("dash")
			feedback.afterimage(pos, player.facing, Content.PAL.player, player._pose)
		"dash_trail":
			feedback.afterimage(pos, player.facing, Content.PAL.player_accent, player._pose)
		"parry_start": feedback.play("shield")
		"heal_start": feedback.play("uncork")
		"heal":
			feedback.play("heal")
			feedback.damage_number(pos + Vector2(0.0, -48.0), Content.FLASK_HEAL, "heal", "+%d" % roundi(Content.FLASK_HEAL))
		"flame":
			feedback.play("flame")
			feedback.burst(pos, 28, Content.PAL.player_accent, 300.0)
			feedback.shake(5.0, 0.2)
		"slam": feedback.play("swing_heavy", 0.85)
		"land": feedback.play("land")
		"cinder":
			var fire := GroundFire.new()
			projectiles.add_child(fire)
			fire.global_position = pos
		"nova":
			feedback.blast(pos, 130.0)
			feedback.burst(pos, 26, Content.PAL.player_accent, 360.0)
			feedback.shake(6.0, 0.18)
			feedback.play("pyre", 1.15)
		"rescued":
			# The rift spits the knight back onto the ledge.
			feedback.spawn_rift(pos, Content.PAL.exit)
			feedback.play("rift", 1.3)
		"step": feedback.play("step")
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

## Counts the knight's feats for the run's stats. Kept out of the feedback
## match above so a feat is counted once, however it is voiced.
func _tally_action(kind: String) -> void:
	if kind == "perfect_parry":
		_stats.perfect_parries += 1
	elif kind == "swing" and player._riposte_attack:
		_stats.ripostes += 1

func _on_player_projectile(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color) -> void:
	_spawn_projectile(team, pos, vel, dmg, kb, pierce, life, color)
	feedback.play("shoot")

func _spawn_projectile(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color) -> void:
	var p := Projectile.new()
	p.setup(team, pos, vel, dmg, kb, pierce, life, color)
	p.struck.connect(feedback.projectile_struck)
	projectiles.add_child(p)
	if team == "enemy":
		_voice_enemy_shot(pos)

## Enemy shots are heard as they are loosed, softer with distance like the
## windups, and once per volley: a fan of five in one frame is one spit.
func _voice_enemy_shot(pos: Vector2) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _enemy_shot_frame or not is_instance_valid(player):
		return
	_enemy_shot_frame = frame
	var falloff := clampf(1.0 - player.global_position.distance_to(pos) / TELEGRAPH_RANGE, 0.06, 1.0)
	feedback.play("spit", 1.0, linear_to_db(falloff))

## The Warden's slam shockwave: a hostile shot drawn as a fire ridge on the floor.
func _spawn_boss_wave(pos: Vector2, vel: Vector2, dmg: float, life: float) -> void:
	var wave := Projectile.new()
	wave.style = "wave"
	wave.setup("enemy", pos, vel, dmg, 120.0, 0, life, Boss.SHOT_COLOR)
	projectiles.add_child(wave)

## Flask charges a cleared chamber returns (none under the Vow of Thirst).
func _flask_per_room() -> int:
	return 0 if Enemy.vows.has("v_thirst") else Content.FLASK_PER_ROOM

## Award cells (scaled by Tithe) and return how many actually landed. The HUD
## counts them at once; the save gets them at the next _bank_cells.
func _award_cells(base: int) -> int:
	var n := maxi(1, roundi(float(base) * _cell_mul))
	_run_cells += n
	_unbanked_cells += n
	ui.set_cells(Save.get_cells() + _unbanked_cells)
	return n

## Write the cells earned since the last bank in one save. Runs at safe
## moments: stepping into the next chamber, the run's end, quitting to the
## title and closing the window.
func _bank_cells() -> void:
	if _unbanked_cells == 0:
		return
	ui.set_cells(Save.add_cells(_unbanked_cells))
	_unbanked_cells = 0

## tier: 0 regular, 1 elite, 2 boss. kind names the archetype ("warden" for the boss).
func _on_enemy_died(sc: int, pos: Vector2, tier: int, color: Color, kind: String) -> void:
	# Falling out of a pit is cleanup, not a player kill or a cell reward.
	if sc <= 0:
		return
	_register_kill()
	score += int(round(float(sc) * Content.streak_multiplier(_streak_kills) * _vow_mult))
	ui.set_score(score)
	_stats.kills += 1
	_stats.kills_by_kind[kind] = int(_stats.kills_by_kind.get(kind, 0)) + 1
	if is_instance_valid(player):
		player.on_enemy_killed()
	# Award cells (1 per regular enemy; 3 for an elite; 10 for the boss)
	match tier:
		2:
			_award_cells(10)
			# The killing blow lands hard; the Warden's own shattering is the payoff.
			feedback.impact(pos + Vector2(0.0, -30.0), Content.PAL.player_accent, true)
			feedback.shake(16.0, 0.5)
			feedback.hit_stop(0.16)
			feedback.play("die")
			feedback.play("elite", 0.749)  # the gong on A, the dominant
		1:
			_stats.elites += 1
			var cells := _award_cells(Content.ELITE_CELLS)
			feedback.flash_death(pos, Content.ELITE_COLOR, true)
			feedback.shake(9.0, 0.26)
			feedback.hit_stop(0.09)
			feedback.play("tear", 0.85)
			feedback.play("elite")
			feedback.damage_number(pos + Vector2(0.0, -66.0), 0.0, "elite", "ELITE SLAIN  +%d CELLS" % cells)
		_:
			_award_cells(1)
			feedback.flash_death(pos, color)
			feedback.shake(6.0, 0.18)
			feedback.play("tear")

func _on_room_cleared(room_name: String) -> void:
	feedback.play("clear")
	# The chamber exhales: the combat layer ebbs away under the clear bells.
	music.set_intensity(0.0, 3.0)
	feedback.chamber_cleared()
	ui.show_room_clear(room_name)

func _on_room_completed() -> void:
	# A dead knight must not take a rift (or win) during the death beat.
	if state != GState.PLAYING:
		return
	_stats.rooms = run.room_index + 1
	if is_equal_approx(float(_stats.damage_taken), _chamber_damage_mark):
		_stats.untouched_chambers += 1
	ui.hide_room_clear()
	# The rift swallows the chamber: mark the descent before the reward opens.
	feedback.play_persistent("rift")
	# A streak belongs to the chamber it was built in.
	_break_streak()
	if run.is_boss_room():
		_victory()
		return
	ui.hide_banners()
	var rift := room.chosen_exit if is_instance_valid(room) else "boon"
	match rift:
		"font", "cache":
			_take_rift_gift(rift)
			return
		"trial":
			# The harder road: a better boon now, and the next chamber pays for it.
			run.trial_next = true
			_pending_upgrades = run.roll_upgrades("rare")
		_:
			_pending_upgrades = run.roll_upgrades()
	ui.setup_upgrades(_pending_upgrades)
	ui.show_panel("reward")
	feedback.stop_world_voices()
	get_tree().paused = true
	state = GState.REWARD

## Font and Cache rifts carry their gift straight through into the next chamber.
func _take_rift_gift(kind: String) -> void:
	var text := ""
	if kind == "font":
		# The font restores the flame fully, refills every flask, and leaves the
		# flame a little larger.
		run.build.max_hp = float(run.build.max_hp) + 5.0
		var healed := float(run.build.max_hp) - float(run.build.hp)
		run.build.hp = run.build.max_hp
		text = "+%d HEALTH" % roundi(healed)
	else:
		var cells := _award_cells(10 + 3 * maxi(0, run.room_index))
		text = "+%d CELLS" % cells
	ui.set_hp(float(run.build.hp), float(run.build.max_hp))
	var flask_refill := -1 if kind == "font" else _flask_per_room()
	_enter_next_chamber(flask_refill)
	# After the move, so the number rises where the knight arrives.
	feedback.play("heal" if kind == "font" else "pickup")
	feedback.damage_number(player.global_position + Vector2(0.0, -70.0), 0.0, "heal" if kind == "font" else "elite", text)

func _on_upgrade_selected(idx: int) -> void:
	if idx < 0 or idx >= _pending_upgrades.size():
		return
	var taken: Dictionary = _pending_upgrades[idx]
	run.apply_upgrade(taken)
	ui.set_hp(float(run.build.hp), float(run.build.max_hp))
	# A Witch Flask adds `value` charges; other boons leave the belt as it was.
	var flask_bonus := 0
	if str(taken.get("kind", "")) == "flask_charge":
		flask_bonus = int(taken.get("value", 1))
	_pending_upgrades.clear()
	ui.hide_panel("reward")
	# A charge returns with every chamber cleared.
	_enter_next_chamber(_flask_per_room() + flask_bonus)
	get_tree().paused = false

## Step through the rift into the next chamber and return `flask_refill` flask
## charges there (-1 refills them all).
func _enter_next_chamber(flask_refill: int) -> void:
	_bank_cells()
	_advance_room()
	player.refill_flask(flask_refill)
	state = GState.PLAYING

## Fold the run's headline result into the stats the summary screen renders.
## Called before either end screen so death and victory report identically.
func _finalize_summary() -> void:
	var won := state == GState.VICTORY
	var previous_best := Save.get_best_score()
	_stats["score"] = score
	_stats["best"] = maxi(score, previous_best)
	_stats["new_best"] = score > previous_best
	ui.set_best(_stats.best)
	# The ledger's one write for this descent; it names the records it beat.
	_stats["broken"] = Save.record_run({
		"won": won, "seed": _seed, "room": _stats.rooms, "score": score,
		"time": snappedf(_stats.time, 0.1), "kills": _stats.kills, "cells": _run_cells,
		"streak": _stats.best_streak, "heat": _vows.size(), "boons": run.taken.keys(),
	}).broken
	var pick := absi(_seed) + int(_stats.kills)
	if won:
		_stats["line"] = Content.VICTORY_LINES[pick % Content.VICTORY_LINES.size()]
	elif run != null and run.is_boss_room():
		_stats["line"] = Content.EPITAPH_THRONE
	else:
		_stats["line"] = Content.EPITAPHS[pick % Content.EPITAPHS.size()]

## Settle the run for its end screen: the result, the cells banked (and the
## vows kept, on a victory) and the summary, with the run's HUD cards cleared.
## The state is set first because the epitaph depends on it.
func _close_run(victory: bool) -> void:
	state = GState.VICTORY if victory else GState.GAME_OVER
	var panel := "victory" if victory else "gameover"
	var vows_kept := _vows.size() if victory else 0
	_bank_cells()
	_finalize_summary()
	ui.show_run_cells(_run_cells, panel, vows_kept)
	ui.show_run_summary(_stats, panel)
	ui.hide_boss_bar()
	ui.hide_streak()
	ui.hide_banners()

func _on_player_died() -> void:
	# A knight that falls with the Warden has traded: the run is lost.
	if state != GState.PLAYING:
		return
	# Embers and paper shards, not a burst: the flame is going out.
	feedback.burst(player.global_position + Vector2(0.0, -28.0), 16, Content.PAL.player_accent, 180.0)
	feedback.shake(12.0, 0.4)
	# A toll rather than a hit: the run itself has ended, not just the player.
	feedback.play_persistent("defeat")
	_close_run(false)
	Save.record_fall(str(_stats.line))
	# The score drops out under the toll; the title theme returns with the screen.
	music.play_track("")
	feedback.slow_motion(0.3, DEATH_BEAT * 0.85)
	_begin_beat("death", player.global_position)

func _on_boss_spawned() -> void:
	if is_instance_valid(room) and room.boss != null:
		ui.show_boss_bar(room.boss.hp_max)
		var subtitle := "Trial of the Throne" if room.trial else Content.boss_subtitle(Save.get_victories(), Save.oath_kept())
		ui.show_boss_intro("The Ember Warden", subtitle)
		feedback.shake(8.0, 0.3)
		feedback.play("boss")
		# The keep goes quiet as the Warden drops; its theme lands on the first move.
		music.play_track("", 0.8)

func _on_boss_phase(phase: int) -> void:
	feedback.shake(10.0, 0.35)
	if phase == 1:
		music.play_track("boss", 0.0)
	else:
		feedback.play("boss")
	if phase == 2:
		feedback.play("roar")
		# Phase-2 callout renders as a compact floating tag above the boss bar,
		# never as a center-screen card over the fighters.
		ui.flash_boss_phase("THE WARDEN IGNITES")
		# The battle theme's second layer comes up with the fire.
		music.set_intensity(1.0)
		feedback.hit_stop(0.1)
		if is_instance_valid(room) and room.boss != null and is_instance_valid(room.boss):
			feedback.blast(room.boss.global_position, 200.0)
	elif phase == 3:
		_on_last_ember()

## The Warden's Last Ember (boss.gd) peaks in a roar: its own callout, the
## score at full heat and the blast that sets the floor alight.
func _on_last_ember() -> void:
	ui.flash_boss_phase("THE LAST EMBER")
	music.set_intensity(1.0)
	feedback.play("last_ember")
	feedback.play("roar", 0.8)
	feedback.shake(14.0, 0.5)
	feedback.hit_stop(0.1)
	if is_instance_valid(room) and room.boss != null:
		feedback.blast(room.boss.global_position, 260.0)

## The Warden comes apart: the run's last and loudest beat.
func _on_boss_shattered(pos: Vector2) -> void:
	feedback.flash_death(pos, Content.BOSS_COLOR, true)
	feedback.flash_death(pos + Vector2(0.0, -40.0), Content.PAL.player_accent, true)
	feedback.blast(pos, 280.0)
	feedback.burst(pos, 14, Content.PAL.player_accent, 520.0)
	feedback.shake(18.0, 0.6)
	feedback.play("pyre")
	feedback.play("elite", 0.667)  # the gong on G, in key
	feedback.rumble(0.8, 1.0, 0.6)
	if in_finale():
		finale.release_hoard(pos)

func _on_slam_landed(pos: Vector2, _radius: float) -> void:
	feedback.shake(8.0, 0.22)
	feedback.burst(pos, 18, Content.PAL.attack, 320.0)
	feedback.land_dust(pos, 1.4)
	feedback.play("slam")
	feedback.rumble(0.4, 0.8, 0.18)

func _on_parried(pos: Vector2, success: bool) -> void:
	if success:
		_stats.parries += 1
		feedback.parry_flash(pos)
		feedback.hit_stop(0.065)
		feedback.shake(4.0, 0.1)
		feedback.play("parry")
		feedback.rumble(0.8, 0.2, 0.1)
		if is_instance_valid(player) and float(run.build.get("flare_parry", 0.0)) > 0.0:
			player.nova(float(run.build.flare_parry), 120.0)
		# The counter window is open right now. Queue the lesson rather than
		# writing the save file from inside the player's physics step.
		_queued_lesson = "riposte"

func _on_enemy_exploded(pos: Vector2, radius: float, damage: float) -> void:
	if damage <= 0.0:
		feedback.shake(6.0, 0.16)
		feedback.land_dust(pos, clampf(radius / 70.0, 1.0, 2.0))
		feedback.play("slam", 0.8)
		return
	feedback.shake(10.0, 0.3)
	feedback.burst(pos, 26, Color("ff7a18"), 360.0)
	feedback.blast(pos, radius)
	feedback.play("boom")

func _victory() -> void:
	if state != GState.PLAYING:
		return
	# Bonus cells for clearing the run
	_award_cells(20)
	# The ending's single save write: the win is kept even if the finale is not.
	var rec := Save.record_victory(_vows)
	_close_run(true)
	feedback.play("victory")
	# The boss theme drops out and the victory bells ring alone.
	music.play_track("", 0.35)
	# The knight has won; nothing left in the hall may still hurt them.
	player.iframes = 0.0
	player.cinematic = true
	_clear_projectiles()
	var focus := Vector2(640.0, Content.FLOOR_Y - 120.0)
	if is_instance_valid(room):
		for e in room.enemies:
			if is_instance_valid(e) and not e.dead:
				feedback.flash_death(e.global_position, e.data.color)
				e._die(false)
		if room.boss != null and is_instance_valid(room.boss):
			focus = room.boss.global_position + Vector2(0.0, -30.0)
	var ctx := rec.duplicate()
	ctx.merge({
		"vows": _vows.duplicate(), "boons": run.taken.keys(), "gold": player._flame_time > 0.0,
		"tier": Content.finale_tier(int(rec.finale_seen), str(rec.milestone)),
	})
	finale = Finale.new()
	finale.name = "Finale"
	add_child(finale)
	finale.finished.connect(_on_finale_finished)
	finale.setup(self, ctx)
	feedback.slow_motion(0.25, 1.6)
	_begin_beat("victory", focus)

# --- Pause ---
func _on_resume() -> void:
	if state != GState.PLAYING: return
	if is_instance_valid(player):
		player.suppress_gameplay_input()
	get_tree().paused = false
	paused = false
	ui.hide_panel("pause")

func _on_quit_to_title() -> void:
	_bank_cells()
	get_tree().paused = false
	paused = false
	_teardown_run()
	ui.hide_all_panels()
	ui.show_panel("title")
	state = GState.TITLE
	_set_world_shown(false)
	zone = "crypt"
	mood = Content.mood_for(0.0)
	RenderingServer.set_default_clear_color(mood.bg_top)
	_lights.set_ambient(mood.ambient)
	music.play_track("title")

func _on_option_toggled(key: String, value: bool) -> void:
	Save.set_option(key, value)
	_apply_toggle(key, value)
	_apply_audio_options()

func _on_forge_requested() -> void:
	ui.hide_all_panels()
	ui.setup_forge(Save.get_cells())
	ui.show_panel("forge")


## Remember where OPTIONS was opened from so BACK returns there, and restore
## the pause state on the way out instead of dropping the player into a run.
func _on_options_requested() -> void:
	_options_return = "pause" if ui.is_panel_visible("pause") else "title"
	ui.hide_all_panels()
	ui.sync_options(Save.get_options())
	ui.show_panel("options")

func _on_back_from_options() -> void:
	ui.hide_all_panels()
	if _options_return == "pause" and state == GState.PLAYING:
		ui.show_panel("pause")
		return
	ui.show_panel("title")

func _on_option_value_changed(key: String, value: float) -> void:
	Save.set_option(key, value)
	_apply_audio_options()
	Feedback.shake_scale = float(Save.get_options().shake)

## Replace only the keyboard events for an action. Gamepad bindings are left
## untouched, so rebinding can never remove pad support as a side effect.
func _apply_binding(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	if keycode == 0:
		return
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	InputMap.action_add_event(action, key)


func _apply_bindings() -> void:
	var bindings := Save.get_bindings()
	for action in bindings:
		_apply_binding(str(action), int(bindings[action]))


func _on_binding_changed(action: String, keycode: int) -> void:
	Save.set_binding(action, keycode)
	_apply_binding(action, keycode)
	# The controls screen renders from the live map, so it must be rebuilt too.
	ui.sync_keys()
	ui.sync_controls()

func _on_keys_requested() -> void:
	ui.hide_all_panels()
	ui.sync_keys()
	ui.show_panel("keys")

func _on_back_from_keys() -> void:
	ui.hide_all_panels()
	ui.show_panel("options")


## Push the persisted mix onto the audio buses. Music also honours its own
## on/off toggle, which is folded into the music bus so the two cannot fight.
func _apply_audio_options() -> void:
	var opts := Save.get_options()
	_apply_bus("Master", float(opts.master))
	_apply_bus("Music", float(opts.music) * (1.0 if bool(opts.music_on) else 0.0))
	_apply_bus("SFX", float(opts.sfx))

func _apply_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))

func _on_buy_meta(idx: int) -> void:
	if idx < 0 or idx >= Content.META_UPGRADES.size():
		return
	var u: Dictionary = Content.META_UPGRADES[idx]
	if Save.purchase_meta(u.id):
		feedback.play("pickup")
	# Refresh the forge panel + HUD
	ui.setup_forge(Save.get_cells())
	ui.set_cells(Save.get_cells())

func _on_vow_toggled(id: String) -> void:
	if not Save.vows_unlocked():
		return
	Save.set_vow(id, not Save.get_vows().has(id))
	feedback.play("elite" if Save.get_vows().has(id) else "ui_back", 1.2)
	ui.setup_forge(Save.get_cells())

func _on_back_from_forge() -> void:
	ui.hide_all_panels()
	ui.show_panel("title")
	ui.set_cells(Save.get_cells())
	ui.set_best(Save.get_best_score())

## Closing the window mid-run keeps the cells earned so far.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_bank_cells()

## Pause opens the pause menu and closes it again. On a screen opened from the
## pause menu it steps back one screen instead, so no sub-screen can ever
## resume the run behind itself.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or state != GState.PLAYING:
		return
	if not paused:
		get_tree().paused = true
		paused = true
		ui.set_descent(run.taken, _seed)
		ui.show_panel("pause")
	elif ui.is_panel_visible("keys"):
		_on_back_from_keys()
	elif ui.is_panel_visible("options"):
		_on_back_from_options()
	elif ui.is_panel_visible("pause"):
		_on_resume()
	get_viewport().set_input_as_handled()
