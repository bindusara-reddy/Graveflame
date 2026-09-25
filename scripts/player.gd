class_name Player
extends CharacterBody2D
## Player controller: platforming, 3-hit combo, down-slam, ranged special, dash, parry,
## wall slide + wall jump, healing flask, hurt, custom drawing.
## A Dead Cells-inspired action-roguelite character. All art is drawn procedurally.

const VFX := preload("res://scripts/vfx.gd")
const KnightArt := preload("res://scripts/knight_art.gd")

## Double-jump somersault length, seconds.
const FLIP_TIME := 0.3
## One full stride (two steps) per this much ground covered, so feet never skate.
const STRIDE := 62.0
## Poise damage (see Enemy.take_damage) of the slam, and of the moves that
## always break a guard: a parry, a riposte, ignition.
const SLAM_POISE := 2.0
const GUARD_BREAK := 99.0
## How each blade blow lands. stop: hit-stop seconds, extending the game's base
## freeze (0.045, or 0.065 on heavies). slant: the cut sliver's screen angle
## when facing right. kick: camera shove in px. poise: guard damage dealt.
const BLOWS := {
	"cut": { "stop": 0.045, "slant": 0.55, "kick": 3.0, "poise": 1.0 },
	"cleave": { "stop": 0.05, "slant": -0.55, "kick": 3.0, "poise": 1.0 },
	"finish": { "stop": 0.075, "slant": 1.0, "kick": 6.0, "poise": 2.0 },
	"riposte": { "stop": 0.10, "slant": 0.0, "kick": 6.0, "poise": GUARD_BREAK },
}
## A killing blow holds the freeze this much longer.
const KILL_STOP_BONUS := 0.03
## Being struck freezes the world longest of all: it is the hit that must read.
const HURT_STOP := 0.085
## A finisher or riposte that lands on the ground rocks the knight back (px/s).
const HEAVY_RECOIL := 90.0
## A blow that rings off a shield throws the knight back this fast (px/s).
const GUARD_RECOIL := 220.0
## Graveflame ignition's shockwave: its reach (px) and how hard it throws (px/s).
const IGNITE_RADIUS := 170.0
const IGNITE_KNOCK := 460.0
## A deflect inside the first PERFECT_PARRY seconds of the window is perfect:
## the foe reels longer, the meter pays more and the riposte it banks hits
## harder. A whiff holds the stance PARRY_WHIFF_LAG longer, so spam costs.
const PERFECT_PARRY := 0.06
const PARRY_STAGGER := 0.6
const PERFECT_PARRY_STAGGER := 0.9
const PERFECT_PARRY_METER := 35.0
const PERFECT_RIPOSTE_MUL := 1.5
const PARRY_WHIFF_LAG := 0.10
## Presses held for a moment (seconds), so a parry, lance, flask or ignition
## tapped during another move still happens as soon as that move allows it.
const PRESS_BUFFER := { "parry": 0.10, "special": 0.12, "heal": 0.10, "ignite": 0.12 }
## The last stretch of a dash (seconds) that can flow straight into a parry or swing.
const DASH_CANCEL_TAIL := 0.05

signal hp_changed(hp: float, max_hp: float)
signal special_changed(value: float, maximum: float)
signal projectile_requested(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color)
signal hit_landed(damage: float, pos: Vector2, heavy: bool)
signal died
signal slam_landed(pos: Vector2, radius: float)
signal parried(pos: Vector2, success: bool)
signal flask_changed(charges: int, max_charges: int)
signal hurt_taken(amount: float, pos: Vector2)
signal action_feedback(kind: String, pos: Vector2)

enum State { LOCOMOTION, ATTACK, SLAM, DASH, PARRY, HEAL, HURT, DEAD }

## Shared by reference with RunModel.build, so there is nothing to sync.
var build: Dictionary = {}
## The game's camera, particles and sound, for the parts of a blow's feel only
## the knight knows (which swing, a kill, a perfect parry). Null in bare rigs.
var feedback: Feedback
var state: State = State.LOCOMOTION
var facing: float = 1.0
var coyote := 0.0
var jump_buffer := 0.0
var jumps_left := 0
var attack_index := -1
var combo_timer := 0.0
var atk_phase := "none"  # startup | active | recover | none
var atk_time := 0.0
var atk_hit: Dictionary = {}
var attack_buffer := 0.0
## Seconds each PRESS_BUFFER action stays pending.
var _pressed := { "parry": 0.0, "special": 0.0, "heal": 0.0, "ignite": 0.0 }
var _queued_attack := false
var dash_cd := 0.0
var _dash_buffer := 0.0
var dash_time := 0.0
var _dash_echo_pos := Vector2.ZERO
var iframes := 0.0
var _hurt_started_airborne := false
var special := 0.0
var max_special := Content.P_SPECIAL_MAX
var flask_charges := Content.FLASK_MAX
var flask_max := Content.FLASK_MAX
var dead := false
var _hurtbox: Area2D
var _attack_area: Area2D
var _atk_shape: CollisionShape2D
var _atk_rect := RectangleShape2D.new()
var _draw_attack := false
var _attack_range := 64.0
var _hurt_flash := 0.0
var _owner_id := 0
# --- Down-slam ---
var _slam_active := false
var _draw_slam_impact := 0.0
# --- Wall slide ---
var wall_sliding := false
var _wall_dir := 0.0   # -1 wall on left, 1 wall on right, 0 none
var _wall_stick := 0.0
# --- Parry ---
var parry_cd := 0.0
var parry_time := 0.0
var _draw_parry := 0.0
var _parry_area: Area2D
var _parry_shape: CollisionShape2D
var _parry_rect := RectangleShape2D.new()
var _parry_hit: Dictionary = {}
var _parry_succeeded := false
var riposte_time := 0.0
var _riposte_attack := false
## Damage multiplier of the banked riposte: PERFECT_RIPOSTE_MUL after a perfect parry.
var _riposte_mul := 1.0
# --- Flask heal visual ---
var _flask_heal_flash := 0.0
var _heal_time := 0.0
# --- Full-meter Graveflame mode ---
var _flame_time := 0.0
var _anim_time := 0.0
var _input_lock_frames := 0
var _air_time := 0.0  # visual only: drives the contact shadow
# --- Momentum boon: kill-fed speed/damage stacks ---
var _momentum_t := 0.0
var _momentum_stacks := 0
# Visual only: landing squash and the airborne state from the previous tick.
var _land_squash := 0.0
var _was_on_floor := true
var _prev_vy := 0.0
# --- Puppet animation (visual only; never read by gameplay) ---
## Current blended pose (see KnightArt) and the blade smear for this frame.
var _pose: Dictionary = {}
var _smear: Dictionary = {}
var _run_phase := 0.0
var _flip_t := 0.0
var _cast_t := 0.0
var _ignite_t := 0.0
var _turn_t := 0.0
var _last_facing := 1.0
## Seconds since the killing blow; drives the collapse.
var _death_t := 0.0
## Last spot the knight stood on solid ground; spike pits return them here.
var _safe_pos := Vector2.ZERO
## Set once the Warden falls: nothing can hurt the knight and it never flickers,
## so the finale's stand-in takes over from a steady figure.
var cinematic := false

## An off-by-default sensor on the knight's attack layer, watching `mask`
## through `rect`; the move that uses it places, sizes and enables it.
func _make_front_sensor(mask: int, rect: RectangleShape2D) -> Area2D:
	var area := Area2D.new()
	area.collision_layer = Content.L_PLAYER_ATK
	area.collision_mask = mask
	area.monitoring = false
	var shape := CollisionShape2D.new()
	shape.shape = rect
	shape.disabled = true
	area.add_child(shape)
	add_child(area)
	return area

func setup(rm: RunModel) -> void:
	build = rm.build
	_owner_id = get_instance_id()

func _ready() -> void:
	# Body collision
	collision_layer = Content.L_PLAYER_BODY
	collision_mask = Content.L_WORLD
	var body_size := Vector2(Content.P_BODY_W, Content.P_BODY_H)
	add_child(Content.rect_shape(body_size))
	# Hurtbox
	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = Content.L_PLAYER_HURT
	_hurtbox.collision_mask = 0
	_hurtbox.add_child(Content.rect_shape(body_size))
	_hurtbox.set_meta("team", "player")
	_hurtbox.set_meta("owner", self)
	_hurtbox.set_meta("owner_id", _owner_id)
	add_child(_hurtbox)
	# The blade's hitbox, then the parry's deflection area.
	_attack_area = _make_front_sensor(Content.L_ENEMY_HURT, _atk_rect)
	_atk_shape = _attack_area.get_child(0) as CollisionShape2D
	_parry_area = _make_front_sensor(Content.L_ENEMY_ATK, _parry_rect)
	_parry_shape = _parry_area.get_child(0) as CollisionShape2D
	jumps_left = Content.P_MAX_JUMPS
	if build.is_empty():
		build = RunModel.base_build()
	flask_max = int(build.get("flask_charges", Content.FLASK_MAX))
	flask_charges = flask_max
	special = float(build.get("special_start", 0.0))
	emit_signal("hp_changed", float(build.hp), float(build.max_hp))
	emit_signal("special_changed", special, max_special)
	emit_signal("flask_changed", flask_charges, flask_max)

func _physics_process(delta: float) -> void:
	if dead:
		# The body keeps animating its collapse after the killing blow.
		_death_t += delta
		_anim_time += delta
		_hurt_flash = maxf(0.0, _hurt_flash - delta)
		_step_animation(delta)
		queue_redraw()
		return
	var controls_locked := _input_lock_frames > 0
	if controls_locked:
		_input_lock_frames -= 1
		attack_buffer = 0.0
		jump_buffer = 0.0
		_dash_buffer = 0.0
		_clear_presses()
	_anim_time += delta
	_prev_vy = velocity.y
	if _land_squash > 0.0: _land_squash -= delta
	if not controls_locked and Input.is_action_just_pressed("attack"):
		attack_buffer = Content.P_ATTACK_BUFFER
	else:
		attack_buffer = maxf(0.0, attack_buffer - delta)
	_flame_time = maxf(0.0, _flame_time - delta)
	riposte_time = maxf(0.0, riposte_time - delta)
	if _momentum_t > 0.0:
		_momentum_t -= delta
		if _momentum_t <= 0.0:
			_momentum_stacks = 0
	if iframes > 0.0: iframes -= delta
	if dash_cd > 0.0: dash_cd -= delta
	if _hurt_flash > 0.0: _hurt_flash -= delta
	if _flask_heal_flash > 0.0: _flask_heal_flash -= delta
	if parry_cd > 0.0: parry_cd -= delta
	if _draw_parry > 0.0: _draw_parry -= delta
	if _draw_slam_impact > 0.0: _draw_slam_impact -= delta
	coyote = maxf(0.0, coyote - delta)
	jump_buffer = maxf(0.0, jump_buffer - delta)
	_dash_buffer = maxf(0.0, _dash_buffer - delta)
	if not controls_locked and Input.is_action_just_pressed("jump"):
		jump_buffer = Content.P_JUMP_BUFFER
	if not controls_locked and Input.is_action_just_pressed("dash"):
		_dash_buffer = Content.P_DASH_BUFFER
	for action in PRESS_BUFFER:
		if not controls_locked and Input.is_action_just_pressed(action):
			_pressed[action] = PRESS_BUFFER[action]
		else:
			_pressed[action] = maxf(0.0, _pressed[action] - delta)
	combo_timer = maxf(0.0, combo_timer - delta)

	match state:
		State.LOCOMOTION: _step_locomotion(delta, controls_locked)
		State.ATTACK: _step_attack(delta)
		State.SLAM: _step_slam(delta)
		State.DASH: _step_dash(delta)
		State.PARRY: _step_parry(delta)
		State.HEAL: _step_heal(delta)
		State.HURT: _step_hurt(delta)
		State.DEAD: pass

	if is_on_floor() and not _was_on_floor and _prev_vy > 320.0:
		_land_squash = 0.12
		if state != State.SLAM:
			emit_signal("action_feedback", "land", global_position + Vector2(0.0, Content.P_BODY_H * 0.5))
	_was_on_floor = is_on_floor()
	_air_time = 0.0 if is_on_floor() else minf(_air_time + delta, 1.0)
	if is_on_floor() and state != State.HURT and _ground_both_sides():
		_safe_pos = global_position
	_step_animation(delta)
	queue_redraw()


## Advance the puppet: stride phase by distance, one-shot gesture clocks, and a
## blend toward the pose the current state asks for.
func _step_animation(delta: float) -> void:
	if is_on_floor():
		var before := _run_phase
		_run_phase = fmod(_run_phase + absf(velocity.x) * delta / STRIDE * TAU, TAU)
		# A footfall each time a foot passes under the body: twice per stride.
		if state == State.LOCOMOTION and absf(velocity.x) > Content.P_SPEED * 0.35:
			if (before < PI and _run_phase >= PI) or _run_phase < before:
				emit_signal("action_feedback", "step", global_position)
	_cast_t = maxf(0.0, _cast_t - delta)
	_ignite_t = maxf(0.0, _ignite_t - delta)
	_turn_t = maxf(0.0, _turn_t - delta)
	if _flip_t > 0.0:
		_flip_t = maxf(0.0, _flip_t - delta)
		if is_on_floor() or state != State.LOCOMOTION or wall_sliding:
			_flip_t = 0.0
	if facing != _last_facing:
		# A cut-out turning over: the figure narrows through its edge and back.
		if state == State.LOCOMOTION:
			_turn_t = 0.07
		_last_facing = facing
	var want := KnightArt.target(self)
	_pose = KnightArt.blend(_pose, want.pose, float(want.rate), delta)
	_smear = want.smear

# --- Locomotion ---
func _step_locomotion(delta: float, controls_locked: bool = false) -> void:
	var dir := 0.0 if controls_locked else Input.get_axis("move_left", "move_right")
	if dir != 0.0: facing = signf(dir)
	var accel := Content.P_AIR_ACCEL if not is_on_floor() else Content.P_ACCEL
	var target := dir * Content.P_SPEED * _speed_mul()
	velocity.x = move_toward(velocity.x, target, accel * delta)
	# Gravity (reduced while wall sliding)
	var grav := Content.GRAVITY
	if wall_sliding and velocity.y > 0.0:
		grav = 0.0
		velocity.y = minf(velocity.y, Content.P_WALL_SLIDE_SPEED)
	velocity.y += grav * delta
	# Jump
	_try_buffered_jump()
	# Variable jump cut
	if not controls_locked and Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= Content.P_JUMP_CUT
	# Friction on ground when no input
	if dir == 0.0 and is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, Content.P_FRICTION * delta)
	# Dash
	if not controls_locked and _dash_buffer > 0.0 and dash_cd <= 0.0:
		_begin_dash()
		return
	if parry_cd <= 0.0 and _take_press("parry"):
		_begin_parry()
		return
	if attack_buffer > 0.0:
		_use_attack_press()
		return
	if special >= Content.P_SPECIAL_COST and _take_press("special"):
		_do_special()
		return
	if special >= max_special and _take_press("ignite"):
		_do_graveflame()
		return
	# A flask press that cannot drink stays pending instead of eating this step.
	if _can_heal() and _take_press("heal"):
		_begin_heal()
		return
	move_and_slide()
	_floor_and_wall_tracking(delta)

## True (and spent) when `action` was pressed within its PRESS_BUFFER time.
func _take_press(action: String) -> bool:
	if _pressed[action] <= 0.0:
		return false
	_pressed[action] = 0.0
	return true

func _clear_presses() -> void:
	for action in _pressed:
		_pressed[action] = 0.0

## Spend the buffered blade press. Falling never changes the player's intent:
## only Down + blade in the air commits a slam.
func _use_attack_press() -> void:
	attack_buffer = 0.0
	if not is_on_floor() and Input.is_action_pressed("move_down"):
		_begin_slam()
	else:
		_begin_attack()

## Shared by locomotion and attack recovery; consumes an existing jump, never
## invents another air jump or removes startup/active-frame commitment.
func _try_buffered_jump() -> bool:
	if jump_buffer <= 0.0:
		return false
	if _wall_dir != 0.0 and not is_on_floor():
		_do_wall_jump()
	elif is_on_floor() or coyote > 0.0 or jumps_left >= Content.P_MAX_JUMPS:
		_do_jump(false)
	elif jumps_left > 0 and not is_on_floor():
		_do_jump(true)
	else:
		return false
	jump_buffer = 0.0
	return true

func _floor_and_wall_tracking(delta: float) -> void:
	if is_on_floor():
		coyote = Content.P_COYOTE
		jumps_left = Content.P_MAX_JUMPS
		_wall_dir = 0.0
		wall_sliding = false
		_wall_stick = 0.0
	else:
		if coyote <= 0.0 and jumps_left == Content.P_MAX_JUMPS:
			jumps_left = Content.P_MAX_JUMPS - 1
		# Wall detection via collision normal
		_wall_dir = 0.0
		if get_slide_collision_count() > 0:
			for i in range(get_slide_collision_count()):
				var c = get_slide_collision(i)
				if c != null:
					var n: Vector2 = c.get_normal()
					if absf(n.x) > 0.7 and n.y > -0.3:
						_wall_dir = -signf(n.x)
						break
		# Wall sliding requires pressing toward the wall and moving down
		var pressed_dir := Input.get_axis("move_left", "move_right")
		if _wall_dir != 0.0 and signf(pressed_dir) == _wall_dir and velocity.y > 0.0:
			if not wall_sliding:
				wall_sliding = true
				_wall_stick = Content.P_WALL_STICK_TIME
		else:
			if _wall_stick > 0.0:
				_wall_stick -= delta
			else:
				wall_sliding = false

func _do_jump(is_double: bool) -> void:
	# Coyote time forgives a walked-off ledge; a deliberate jump consumes it.
	coyote = 0.0
	velocity.y = Content.P_DOUBLE_JUMP_VEL if is_double else Content.P_JUMP_VEL
	jumps_left -= 1
	if is_double:
		jumps_left = mini(jumps_left, Content.P_MAX_JUMPS - 1)
		_flip_t = FLIP_TIME
	wall_sliding = false
	emit_signal("action_feedback", "jump", global_position)

func _do_wall_jump() -> void:
	# Leap away from the wall
	velocity.x = -_wall_dir * Content.P_WALL_JUMP_VEL.x
	velocity.y = Content.P_WALL_JUMP_VEL.y
	facing = -_wall_dir
	jumps_left = Content.P_MAX_JUMPS - 1
	wall_sliding = false
	_wall_dir = 0.0
	emit_signal("action_feedback", "jump", global_position)

# --- Build-derived multipliers ---
func _speed_mul() -> float:
	return float(build.get("speed_mul", 1.0)) + float(build.get("momentum", 0.0)) * float(_momentum_stacks)

## Outgoing damage multiplier. Momentum stacks, Bloodrush (low HP) and
## Executioner (low target HP) layer on top of the flat Power bonus.
func _damage_mul(tgt = null) -> float:
	var m := float(build.get("dmg_mul", 1.0))
	if _momentum_stacks > 0:
		m += 0.10 * float(_momentum_stacks)
	if float(build.get("bloodrush", 0.0)) > 0.0 and float(build.hp) < float(build.max_hp) * Content.BLOODRUSH_HP_FRAC:
		m += float(build.bloodrush)
	# Ember Brand: burning targets take more.
	if tgt != null and float(build.get("brand", 0.0)) > 0.0:
		var burning = tgt.get("burn_time")
		if burning != null and float(burning) > 0.0:
			m += float(build.brand)
	if tgt != null and float(build.get("execute_bonus", 0.0)) > 0.0:
		var thp = tgt.get("hp")
		var tmax = tgt.get("hp_max")
		if thp != null and tmax != null and float(tmax) > 0.0 and float(thp) <= float(tmax) * Content.EXECUTE_HP_FRAC:
			m += float(build.execute_bonus)
	return m

## Called by the game on every kill the player earns.
func on_enemy_killed() -> void:
	if float(build.get("momentum", 0.0)) <= 0.0:
		return
	_momentum_stacks = mini(_momentum_stacks + 1, Content.MOMENTUM_MAX_STACKS)
	_momentum_t = Content.MOMENTUM_TIME

func momentum_stacks() -> int:
	return _momentum_stacks

## True on the combo's last, heaviest swing (a riposte reuses that slot).
func is_finisher() -> bool:
	return attack_index == Content.COMBO.size() - 1

# --- Attack combo ---
func _begin_attack(force_chain: bool = false) -> void:
	_riposte_attack = riposte_time > 0.0 and not force_chain
	if _riposte_attack:
		riposte_time = 0.0
		attack_index = Content.COMBO.size() - 1
	elif (force_chain or combo_timer > 0.0) and attack_index >= 0 and not is_finisher():
		attack_index += 1
	else:
		attack_index = 0
	var def: Dictionary = Content.RIPOSTE if _riposte_attack else Content.COMBO[attack_index]
	attack_buffer = 0.0
	_queued_attack = false
	# A chained swing turns to the held direction; the riposte keeps its mark.
	var held := Input.get_axis("move_left", "move_right")
	if held != 0.0 and not _riposte_attack:
		facing = signf(held)
	state = State.ATTACK
	atk_phase = "startup"
	atk_time = def.startup
	velocity.x = facing * float(def.get("lunge", 150.0))
	set_meta("atk_def", def)
	emit_signal("action_feedback", "swing", global_position)

func _step_attack(delta: float) -> void:
	if attack_buffer > 0.0 and not is_finisher():
		_queued_attack = true
		attack_buffer = 0.0
	# Recovery can be cancelled into a dash, keeping combat responsive without
	# removing the commitment of startup and active frames.
	if atk_phase == "recover" and _dash_buffer > 0.0 and dash_cd <= 0.0:
		_deactivate_hitbox()
		_begin_dash()
		return
	if atk_phase == "recover" and _try_buffered_jump():
		_drop_combo()
		return
	if atk_phase == "recover" and parry_cd <= 0.0 and _take_press("parry"):
		_drop_combo()
		_begin_parry()
		return
	velocity.y += Content.GRAVITY * delta
	var air_dir := Input.get_axis("move_left", "move_right")
	var drag := Content.P_AIR_ACCEL if not is_on_floor() else Content.P_FRICTION
	var target_x := air_dir * Content.P_SPEED * 0.45 if not is_on_floor() else 0.0
	velocity.x = move_toward(velocity.x, target_x, drag * delta)
	var def: Dictionary = get_meta("atk_def")
	atk_time -= delta
	# A queued swing links in halfway through recovery (never after the finisher).
	var linked := _queued_attack and atk_time <= float(def.recover) * 0.5
	if atk_phase == "startup" and atk_time <= 0.0:
		atk_phase = "active"
		atk_time = def.active
		_activate_hitbox(def)
	elif atk_phase == "active":
		_scan_attack_hits(def, _attack_area.get_overlapping_areas())
		if atk_time <= 0.0:
			atk_phase = "recover"
			atk_time = def.recover
			_deactivate_hitbox()
	elif atk_phase == "recover" and (atk_time <= 0.0 or linked):
		atk_phase = "none"
		if _queued_attack and not is_finisher():
			_begin_attack(true)
			return
		combo_timer = def.window
		state = State.LOCOMOTION
		attack_index = -1 if def.window <= 0.0 else attack_index
	move_and_slide()
	_floor_and_wall_tracking(delta)

## Leave the combo for a recovery cancel: the next swing starts from the cut.
func _drop_combo() -> void:
	_deactivate_hitbox()
	atk_phase = "none"
	_queued_attack = false
	attack_index = -1
	combo_timer = 0.0
	state = State.LOCOMOTION

func _activate_hitbox(def: Dictionary) -> void:
	var origin := Vector2(facing * 8.0, -8.0)
	_atk_rect.size = Vector2(def.range, Content.P_BODY_H + 10.0)
	_atk_shape.position = origin + Vector2(facing * def.range * 0.5, 0.0)
	_atk_shape.disabled = false
	_attack_area.monitoring = true
	_draw_attack = true
	_attack_range = def.range
	atk_hit.clear()
	emit_signal("action_feedback", "swing_active", global_position)
	if is_finisher() and (_flame_time > 0.0 or bool(build.get("finisher_wave", false))):
		var wave_pos := global_position + Vector2(facing * 34.0, -8.0)
		var wave_life := 0.32 if _flame_time > 0.0 else 0.26
		emit_signal("projectile_requested", "player", wave_pos, Vector2(facing * 560.0, 0.0), 18.0 * _damage_mul(), 320.0, 2, wave_life, Content.PAL.player_accent)
	_scan_attack_hits(def, _blade_touching())

## Hurtboxes under the blade right now. The sensor's own overlap list fills
## only on the next physics step, which would cost the swing its first frame.
func _blade_touching() -> Array:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _atk_rect
	query.transform = _atk_shape.global_transform
	query.collision_mask = _attack_area.collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return get_world_2d().direct_space_state.intersect_shape(query).map(func(hit): return hit.collider)

func _deactivate_hitbox() -> void:
	_atk_shape.disabled = true
	_attack_area.monitoring = false
	_draw_attack = false

## Land the swing on every hurtbox in `areas` it has not struck yet.
func _scan_attack_hits(def: Dictionary, areas: Array) -> void:
	for area in areas:
		if not is_instance_valid(area): continue
		var ateam = area.get_meta("team")
		if ateam == null or ateam == "player": continue
		var oid: int = area.get_meta("owner_id", 0)
		if atk_hit.has(oid): continue
		atk_hit[oid] = true
		var tgt = area.get_meta("owner")
		if tgt != null and is_instance_valid(tgt) and tgt.has_method("take_damage"):
			if ateam == "scenery":
				tgt.take_damage(float(def.damage), Vector2(facing, -0.3), float(def.knock))
				continue # no meter, lifesteal, damage stats or hit-stop from props
			var finisher := is_finisher()
			var blow: Dictionary = BLOWS[def.name]
			var dmg: float = def.damage * _damage_mul(tgt)
			if finisher:
				dmg *= float(build.get("finish_mul", 1.0))
			if _riposte_attack:
				dmg *= _riposte_mul
			if _flame_time > 0.0:
				dmg *= Content.P_FLAME_DAMAGE_MUL
			deal(tgt, dmg, Vector2(facing, -0.2), def.knock, blow.poise)
			var contact := _contact_point(area)
			if tgt.get("last_hit_blocked") == true:
				_ring_off_guard(contact)
				continue
			# Graveflame ignites every hit; Kindling makes finishers ignite too.
			var kindling := float(build.get("burn_bonus_dps", 0.0)) > 0.0
			if (_flame_time > 0.0 or (finisher and kindling)) and tgt.has_method("apply_burn"):
				tgt.apply_burn(Content.P_FLAME_BURN_DPS + float(build.get("burn_bonus_dps", 0.0)), Content.P_FLAME_BURN_TIME + float(build.get("burn_bonus_time", 0.0)))
			emit_signal("hit_landed", dmg, contact, finisher)
			_feel_blow(tgt, contact, blow, finisher)
			if finisher and is_on_floor() and atk_hit.size() == 1:
				velocity.x -= facing * HEAVY_RECOIL
			_gain_special(Content.P_SPECIAL_GAIN * float(build.get("special_mul", 1.0)))
			if float(build.get("lifesteal", 0.0)) > 0.0:
				_heal(float(build.lifesteal))

## Deal a blow through `tgt`'s take_damage, with the poise damage it carries
## when the target's take_damage accepts it (creatures do; scenery does not).
static func deal(tgt: Object, amount: float, dir: Vector2, knock: float, poise: float) -> void:
	if tgt.get_method_argument_count("take_damage") >= 4:
		tgt.take_damage(amount, dir, knock, poise)
	else:
		tgt.take_damage(amount, dir, knock)

## Where the blade meets the hurtbox `area`: its near edge at the knight's chest
## height, so sparks and the cut land on the silhouette rather than inside it.
func _contact_point(area: Area2D) -> Vector2:
	var box := area.get_child(0) as CollisionShape2D
	var center := area.global_position
	var half := Vector2(14.0, 20.0)
	if box != null and box.shape is RectangleShape2D:
		center += box.position
		half = (box.shape as RectangleShape2D).size * 0.5
	var y := clampf(global_position.y - 10.0, center.y - half.y * 0.8, center.y + half.y * 0.6)
	return Vector2(center.x - facing * half.x * 0.6, y)

## The blade rings off a raised guard: no flesh-hit feedback, meter or
## lifesteal, but a clang, slate sparks thrown back, a tick of freeze and a
## recoil that pushes the knight off the shield.
func _ring_off_guard(contact: Vector2) -> void:
	velocity.x = -facing * GUARD_RECOIL
	emit_signal("action_feedback", "blocked", contact)
	if feedback == null:
		return
	feedback.play("clang")
	feedback.burst_sparks(contact, 10, 260.0, VFX.SLATE.lightened(0.4), Vector2(-facing, -0.4))
	feedback.hit_stop(0.03)
	feedback.kick(Vector2(-facing, 0.0), 3.0)

## A blow's own weight on top of the game's sparks and base freeze: the victim
## shivers, the world holds per the swing (longer on a kill), and the camera is
## shoved along the blade over a cut sliver slanted like the swing.
func _feel_blow(tgt: Node, contact: Vector2, blow: Dictionary, heavy: bool) -> void:
	var stop: float = blow.stop + (KILL_STOP_BONUS if tgt.get("dead") == true else 0.0)
	VFX.jolt(tgt, stop)
	if feedback == null:
		return
	var slant: float = blow.slant
	feedback.cut_line(contact, slant if facing > 0.0 else PI - slant, heavy)
	feedback.hit_stop(stop)
	feedback.kick(Vector2(facing, 0.0), blow.kick)

# --- Down-slam ---
func _begin_slam() -> void:
	state = State.SLAM
	_slam_active = true
	velocity.y = Content.P_SLAM_VEL
	velocity.x *= 0.3
	# brief i-frames during descent so dropping through enemies feels fair
	iframes = maxf(iframes, 0.08)
	emit_signal("action_feedback", "slam", global_position)

func _step_slam(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, Content.P_FRICTION * delta)
	move_and_slide()
	if is_on_floor():
		_do_slam_impact()
		_slam_active = false
		state = State.LOCOMOTION
	# Cull if somehow below world
	if global_position.y > Content.FLOOR_Y + 300:
		_slam_active = false
		state = State.LOCOMOTION

func _do_slam_impact() -> void:
	var radius: float = Content.P_SLAM_RADIUS + float(build.get("slam_radius_bonus", 0.0))
	var base_dmg: float = Content.P_SLAM_DAMAGE * float(build.get("slam_mul", 1.0))
	# AoE: damage all enemies overlapping a circle centered on player
	var center := global_position + Vector2(0.0, 10.0)
	for prop in get_tree().get_nodes_in_group("breakable_prop"):
		if is_instance_valid(prop) and prop.global_position.distance_to(center) <= radius:
			prop.take_damage(base_dmg, Vector2(signf(prop.global_position.x - center.x), -0.7), Content.P_SLAM_KNOCK)
	var struck: Array = []
	for area in get_tree().get_nodes_in_group("enemy_hurtbox"):
		if not is_instance_valid(area): continue
		if area.global_position.distance_to(center) <= radius + 24.0:
			var tgt = area.get_meta("owner")
			if tgt != null and is_instance_valid(tgt) and tgt.has_method("take_damage"):
				var kdir: Vector2 = (tgt.global_position - center).normalized()
				if kdir == Vector2.ZERO: kdir = Vector2.UP
				deal(tgt, base_dmg * _damage_mul(tgt), Vector2(kdir.x, -0.7), Content.P_SLAM_KNOCK, SLAM_POISE)
				if tgt.get("last_hit_blocked") == true:
					continue
				struck.append(tgt)
				# Each foe caught gets its own contact burst, thrown away from the crater.
				if feedback != null:
					feedback.impact(tgt.global_position + Vector2(0.0, 10.0), Content.PAL.attack, true, Vector2(kdir.x, -0.6))
	if not struck.is_empty():
		_gain_special(Content.P_SPECIAL_GAIN * float(build.get("special_mul", 1.0)) * 2.0)
		# The freeze grows with every foe caught, and each one shivers through it.
		var stop := minf(0.05 + 0.015 * float(struck.size()), 0.11)
		for tgt in struck:
			VFX.jolt(tgt, stop)
		if feedback != null:
			feedback.hit_stop(stop)
	_draw_slam_impact = 0.3
	emit_signal("slam_landed", center, radius)
	if bool(build.get("skyfall", false)):
		# Skyfall: the impact runs out along the floor both ways.
		for dir: float in [-1.0, 1.0]:
			emit_signal("projectile_requested", "player", global_position + Vector2(dir * 26.0, 14.0), Vector2(dir * 560.0, 0.0), 18.0 * _damage_mul(), 300.0, 3, 0.6, VFX.ORANGE)
	# small bounce
	velocity.y = -220.0

# --- Special ---
func _do_special() -> void:
	special -= Content.P_SPECIAL_COST
	emit_signal("special_changed", special, max_special)
	var spd := 700.0
	var dmg := 26.0 * _damage_mul() * float(build.get("lance_mul", 1.0))
	var pierce := 3 if bool(build.get("special_pierce", false)) else 0
	var pos := global_position + Vector2(facing * 30.0, -10.0)
	if bool(build.get("twin_lance", false)):
		# Twin Lance: two bolts fanned a hair apart, each at full strength.
		for tilt: float in [-0.09, 0.09]:
			emit_signal("projectile_requested", "player", pos + Vector2(0.0, tilt * 60.0), Vector2(facing * spd, 0.0).rotated(tilt * facing), dmg, 360.0, pierce, 1.6, Content.PAL.special)
	else:
		emit_signal("projectile_requested", "player", pos, Vector2(facing * spd, 0.0), dmg, 360.0, pierce, 1.6, Content.PAL.special)
	emit_signal("action_feedback", "special", pos)
	_cast_t = 0.22

func _do_graveflame() -> void:
	special = 0.0
	_ignite_t = 0.4
	_flame_time = Content.P_FLAME_DURATION
	iframes = maxf(iframes, 0.18)
	emit_signal("special_changed", special, max_special)
	emit_signal("action_feedback", "flame", global_position)
	# Ignition is a showpiece and a panic button: it throws every foe close by
	# clear, guard broken and alight, while the world holds and the camera leans in.
	nova(0.0, IGNITE_RADIUS, IGNITE_KNOCK, GUARD_BREAK)
	if feedback != null:
		feedback.hit_stop(0.18)
		feedback.punch_zoom(1.08, 0.06, 0.3)
		feedback.blast(global_position, IGNITE_RADIUS)

func _gain_special(amount: float) -> void:
	special = minf(max_special, special + amount)
	emit_signal("special_changed", special, max_special)

# --- Dash ---
func _begin_dash() -> void:
	_dash_buffer = 0.0
	state = State.DASH
	dash_time = Content.P_DASH_TIME
	dash_cd = Content.P_DASH_CD * float(build.get("dash_cd_mul", 1.0))
	iframes = maxf(iframes, Content.P_DASH_IFRAMES + float(build.get("dash_iframes_bonus", 0.0)))
	var dir := Input.get_axis("move_left", "move_right")
	if dir == 0.0: dir = facing
	facing = signf(dir)
	_dash_echo_pos = global_position
	velocity = Vector2(dir * Content.P_DASH_SPEED, 0.0)
	wall_sliding = false
	emit_signal("action_feedback", "dash", global_position)

func _step_dash(delta: float) -> void:
	dash_time -= delta
	velocity.y = 0.0
	if dash_time <= DASH_CANCEL_TAIL and _cancel_dash_tail():
		return
	if dash_time <= 0.0:
		state = State.LOCOMOTION
		velocity.x *= 0.5
	move_and_slide()
	if global_position.distance_to(_dash_echo_pos) >= 24.0:
		_dash_echo_pos = global_position
		emit_signal("action_feedback", "dash_trail", global_position)
		if bool(build.get("cinder_trail", false)) and is_on_floor():
			emit_signal("action_feedback", "cinder", global_position + Vector2(0.0, Content.P_BODY_H * 0.5))

## The dash's tail flows straight into a buffered parry or blade press.
func _cancel_dash_tail() -> bool:
	if parry_cd <= 0.0 and _take_press("parry"):
		velocity.x *= 0.5
		_begin_parry()
	elif attack_buffer > 0.0:
		velocity.x *= 0.5
		_use_attack_press()
	else:
		return false
	return true

# --- Parry ---
## The deflect window's full length, with any boon that widens it.
func _parry_window() -> float:
	return Content.PARRY_WINDOW * float(build.get("parry_window_mul", 1.0))

func _begin_parry() -> void:
	state = State.PARRY
	parry_time = _parry_window()
	parry_cd = Content.PARRY_COOLDOWN
	# Position the parry rectangle in front
	var w := Content.PARRY_RANGE
	_parry_rect.size = Vector2(w, Content.P_BODY_H + 16.0)
	_parry_shape.position = Vector2(facing * w * 0.5, 0.0)
	_parry_shape.disabled = false
	_parry_area.monitoring = true
	_parry_hit.clear()
	_parry_succeeded = false
	_draw_parry = parry_time + 0.05
	emit_signal("action_feedback", "parry_start", global_position)

func _step_parry(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, Content.P_FRICTION * delta)
	parry_time -= delta
	var window_open := _parry_area.monitoring
	if window_open:
		_scan_parry()
	if _parry_succeeded and attack_buffer > 0.0:
		_close_parry()
		_draw_parry = 0.0
		_begin_attack()
		return
	if parry_time <= 0.0 and window_open:
		_close_parry()
		if not _parry_succeeded:
			emit_signal("parried", global_position + Vector2(facing * 40.0, 0.0), false)
			if feedback != null:
				feedback.play("whiff")
	# A whiffed parry holds the stance a beat longer with the sensor shut.
	if parry_time <= (0.0 if _parry_succeeded else -PARRY_WHIFF_LAG):
		state = State.LOCOMOTION
	move_and_slide()
	_floor_and_wall_tracking(delta)

func _scan_parry() -> void:
	# Persistent enemy hurtboxes are not in this area's mask: only active melee
	# attack areas and reflectable projectiles qualify.
	for area in _parry_area.get_overlapping_areas():
		if not is_instance_valid(area) or area.get_meta("team", "") != "enemy":
			continue
		var oid: int = int(area.get_meta("owner_id", 0))
		if _parry_hit.has(oid):
			continue
		var attack_kind := str(area.get_meta("attack_kind", ""))
		var perfect := parry_time >= _parry_window() - PERFECT_PARRY
		if attack_kind == "projectile":
			area.reflect(Vector2(facing, -0.05), Content.PARRY_PROJECTILE_BOOST)
		elif attack_kind == "melee" and bool(area.get_meta("attack_active", false)):
			# Melee areas always carry an owner, but it may already be gone.
			var attacker = area.get_meta("owner")
			if not is_instance_valid(attacker):
				continue
			# The deflect drives the attacker away from the knight, so a shield
			# faces it head-on and a parry that kills leaves the body at rest.
			deal(attacker, Content.PARRY_DAMAGE + float(build.get("parry_bonus_dmg", 0.0)), Vector2(facing, -0.1), 420.0, GUARD_BREAK)
			if not attacker.dead:
				attacker.on_parried(Vector2(facing, -0.2))
			# The riposte must land while the foe still reels, longest after a perfect parry.
			if attacker.state == Enemy.EState.STAGGER:
				attacker.stagger_t = maxf(attacker.stagger_t, PERFECT_PARRY_STAGGER if perfect else PARRY_STAGGER)
		else:
			continue
		# A deflect landed: it opens the riposte window and pays meter.
		var at := global_position + Vector2(facing * 40.0, 0.0)
		_parry_hit[oid] = true
		_parry_succeeded = true
		riposte_time = Content.RIPOSTE_WINDOW
		_riposte_mul = PERFECT_RIPOSTE_MUL if perfect else 1.0
		emit_signal("parried", at, true)
		if perfect:
			emit_signal("action_feedback", "perfect_parry", at)
		_feel_parry(perfect)
		var meter := PERFECT_PARRY_METER if perfect else Content.P_SPECIAL_GAIN * 2.5
		_gain_special(meter + float(build.get("parry_special", 0.0)))

## A deflect's weight beyond the game's ring and chime: a longer freeze and a
## shove along the blade; a perfect one also leans the camera in, blanches the
## vignette's edge and sounds its own cue.
func _feel_parry(perfect: bool) -> void:
	if feedback == null:
		return
	feedback.kick(Vector2(facing, 0.0), 6.0)
	if not perfect:
		feedback.hit_stop(0.09)
		return
	feedback.hit_stop(0.14)
	feedback.punch_zoom(1.06, 0.05, 0.25)
	feedback.flash_edge(Color(1.0, 1.0, 1.0, 0.3), 0.08)
	feedback.play("perfect_parry")

## Shut the parry's sensor. The shield visual (_draw_parry) is left to fade.
func _close_parry() -> void:
	_parry_shape.disabled = true
	_parry_area.monitoring = false

# --- Healing flask ---
## A flask can be drunk: a charge is left and there is health to restore.
func _can_heal() -> bool:
	return flask_charges > 0 and float(build.hp) < float(build.max_hp)

func _begin_heal() -> void:
	state = State.HEAL
	_heal_time = Content.P_HEAL_TIME
	velocity.x *= 0.2
	emit_signal("action_feedback", "heal_start", global_position)

func _step_heal(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, Content.P_FRICTION * 2.0 * delta)
	move_and_slide()
	_floor_and_wall_tracking(delta)
	_heal_time -= delta
	if _heal_time <= 0.0:
		_use_flask()
		state = State.LOCOMOTION

func _use_flask() -> void:
	if flask_charges <= 0:
		return
	if float(build.hp) >= float(build.max_hp):
		return
	flask_charges -= 1
	_heal(Content.FLASK_HEAL)
	_flask_heal_flash = 0.5
	emit_signal("flask_changed", flask_charges, flask_max)
	emit_signal("action_feedback", "heal", global_position)
	if float(build.get("phoenix", 0.0)) > 0.0:
		# Phoenix Flask: the draught catches fire.
		_flame_time = maxf(_flame_time, 3.0)
		nova(float(build.phoenix), 130.0)

## Restore `amount` flask charges (all of them when negative), capped at max.
func refill_flask(amount: int = -1) -> void:
	flask_max = int(build.get("flask_charges", Content.FLASK_MAX))
	flask_charges = flask_max if amount < 0 else mini(flask_max, flask_charges + amount)
	emit_signal("flask_changed", flask_charges, flask_max)

# --- Hurt ---
func take_damage(amount: float, from_dir: Vector2, kb: float) -> void:
	if dead or iframes > 0.0 or cinematic: return
	# Only a confirmed forward deflection grants immunity. Hazards, explosions and
	# attacks from behind still connect during the parry animation.
	if state == State.PARRY and parry_time > 0.0:
		var parries_before := _parry_hit.size()
		_scan_parry()
		if _parry_hit.size() > parries_before:
			return
	var dealt := minf(maxf(amount, 0.0), float(build.hp))
	var new_hp := float(build.hp) - amount
	riposte_time = 0.0
	_riposte_attack = false
	# A hit that lands ends the swing and any wall slide.
	atk_phase = "none"
	_deactivate_hitbox()
	wall_sliding = false
	if new_hp <= 0.0 and bool(build.get("second_wind", false)) and not bool(build.get("second_wind_used", false)):
		# Second Wind: the flame refuses to go out, once.
		build.second_wind_used = true
		_set_hp(float(build.max_hp) * Content.SECOND_WIND_HP_FRAC)
		_hurt_flash = 0.2
		_flask_heal_flash = 0.6
		iframes = 2.0
		state = State.LOCOMOTION
		velocity = Vector2(0.0, -420.0)
		emit_signal("action_feedback", "second_wind", global_position)
		emit_signal("hurt_taken", dealt, global_position)
		return
	_set_hp(new_hp)
	_hurt_flash = 0.12
	emit_signal("hurt_taken", dealt, global_position)
	if float(build.hp) <= 0.0:
		_die()
		return
	_feel_hurt(from_dir)
	state = State.HURT
	_hurt_started_airborne = not is_on_floor()
	iframes = Content.P_HURT_IFRAMES + float(build.get("iframes_bonus", 0.0))
	var hit_dir := from_dir.normalized()
	velocity = Vector2(hit_dir.x * kb, minf(-kb * 0.35, hit_dir.y * kb))
	if float(build.get("thorns", 0.0)) > 0.0:
		_thorns_burst()

## Being struck must read above everything else: the world holds, the view is
## shoved along the blow and the vignette flushes red for an instant.
func _feel_hurt(from_dir: Vector2) -> void:
	if feedback == null:
		return
	feedback.hit_stop(HURT_STOP)
	feedback.kick(from_dir, 6.0)
	feedback.flash_edge(Game.VIGNETTE_LOW_HP, 0.12)

## A ring of flame around the knight: damages and ignites every enemy within
## `radius`. Shared by Flare Parry, Phoenix Flask and ignition, which deals no
## damage but throws harder (`knock`) and breaks guards (`poise`).
func nova(dmg: float, radius: float, knock := 320.0, poise := 1.0) -> void:
	for foe in Enemy.living_near(get_tree(), global_position, radius):
		# A pyre chain set off by this blast may already have killed a later foe.
		if foe.dead:
			continue
		var dir: Vector2 = (foe.global_position - global_position).normalized()
		if dir == Vector2.ZERO: dir = Vector2(facing, 0.0)
		deal(foe, dmg * _damage_mul(foe), Vector2(dir.x, -0.4), knock, poise)
		foe.apply_burn(Content.P_FLAME_BURN_DPS, Content.P_FLAME_BURN_TIME)
	emit_signal("action_feedback", "nova", global_position)

## Cinder Skin: a hit taken scorches everything standing close.
func _thorns_burst() -> void:
	var dmg := float(build.get("thorns", 0.0))
	var hit_any := false
	for foe in Enemy.living_near(get_tree(), global_position, Content.THORNS_RADIUS):
		# A pyre chain set off by this burst may already have killed a later foe.
		if foe.dead:
			continue
		var dir: Vector2 = (foe.global_position - global_position).normalized()
		if dir == Vector2.ZERO: dir = Vector2(facing, 0.0)
		foe.take_damage(dmg, Vector2(dir.x, -0.3), 260.0)
		hit_any = true
	if hit_any:
		emit_signal("action_feedback", "thorns", global_position)

func _step_hurt(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, Content.P_FRICTION * 3.0 * delta)
	move_and_slide()
	_floor_and_wall_tracking(delta)
	# Keep grounded knockback committed to landing. Airborne hits release only
	# after the impulse settles and ascent ends, with contact bookkeeping current.
	if absf(velocity.x) < 30.0 and (is_on_floor() or (_hurt_started_airborne and velocity.y >= 0.0)):
		state = State.LOCOMOTION

func _heal(amount: float) -> void:
	_set_hp(float(build.hp) + amount)

## Write the knight's health, clamped to the flame's size, and tell the HUD.
func _set_hp(value: float) -> void:
	build.hp = clampf(value, 0.0, float(build.max_hp))
	hp_changed.emit(float(build.hp), float(build.max_hp))

## True when there is floor under both of the knight's flanks, a stride out.
## A pit rescue must never return the knight to the very lip it fell from.
func _ground_both_sides() -> bool:
	var space := get_world_2d().direct_space_state
	for side: float in [-1.0, 1.0]:
		var from := global_position + Vector2(side * 38.0, 0.0)
		var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, Content.P_BODY_H * 0.5 + 14.0), Content.L_WORLD)
		if space.intersect_ray(q).is_empty():
			return false
	return true

## Spike pits cost health, not the run: the spikes bite (through dash or parry
## immunity, since a pit is not an attack to dodge) and the knight is pulled
## back to the last solid ground they stood on.
func hit_hazard(amount: float) -> void:
	if dead or cinematic:
		return
	var held_iframes := iframes
	iframes = 0.0
	take_damage(amount, Vector2(0.0, -1.0), 0.0)
	if dead:
		return
	global_position = _safe_pos
	velocity = Vector2.ZERO
	state = State.LOCOMOTION
	_slam_active = false
	_deactivate_hitbox()
	iframes = maxf(1.0, held_iframes)
	_hurt_flash = 0.15
	emit_signal("action_feedback", "rescued", global_position)

## Crossing the world boundary is terminal, not a parryable or survivable hit.
## Dash immunity and Second Wind still apply to ordinary combat and hazards.
func fall_out_of_world() -> void:
	if dead or cinematic: return
	# Signals are synchronous: guard terminal re-entry before notifying listeners.
	dead = true
	var lost := maxf(0.0, float(build.hp))
	_set_hp(0.0)
	emit_signal("hurt_taken", lost, global_position)
	_die()

func _die() -> void:
	dead = true
	_death_t = 0.0
	_flip_t = 0.0
	riposte_time = 0.0
	_riposte_attack = false
	state = State.DEAD
	_deactivate_hitbox()
	emit_signal("died")

func respawn_at(pos: Vector2, reset_resources: bool = false) -> void:
	_deactivate_hitbox()
	riposte_time = 0.0
	_riposte_attack = false
	_close_parry()
	global_position = pos
	_safe_pos = pos
	velocity = Vector2.ZERO
	dead = false
	_death_t = 0.0
	_flip_t = 0.0
	_cast_t = 0.0
	_ignite_t = 0.0
	state = State.LOCOMOTION
	iframes = 1.2
	attack_buffer = 0.0
	_queued_attack = false
	attack_index = -1
	jump_buffer = 0.0
	_dash_buffer = 0.0
	_clear_presses()
	combo_timer = 0.0
	atk_phase = "none"
	atk_time = 0.0
	atk_hit.clear()
	_draw_attack = false
	parry_time = 0.0
	_parry_succeeded = false
	_parry_hit.clear()
	_draw_parry = 0.0
	_slam_active = false
	_draw_slam_impact = 0.0
	_heal_time = 0.0
	jumps_left = Content.P_MAX_JUMPS
	wall_sliding = false
	_wall_dir = 0.0
	# Room travel preserves the run resources. Only a brand-new run requests a
	# reset; _ready() already initializes them for the first room.
	if reset_resources:
		flask_max = int(build.get("flask_charges", Content.FLASK_MAX))
		flask_charges = flask_max
		special = float(build.get("special_start", 0.0))
	emit_signal("flask_changed", flask_charges, flask_max)
	emit_signal("special_changed", special, max_special)

func suppress_gameplay_input(frames: int = 2) -> void:
	_input_lock_frames = maxi(_input_lock_frames, frames)
	jump_buffer = 0.0
	_dash_buffer = 0.0
	_clear_presses()

# --- Drawing ---

func _draw() -> void:
	var w := Content.P_BODY_W
	var h := Content.P_BODY_H
	var flicker := iframes > 0.0 and fmod(iframes, 0.12) < 0.06 and not dead and not cinematic
	var body_col: Color = Content.PAL.player if not flicker else Content.PAL.player_accent
	if _hurt_flash > 0.0: body_col = Color.WHITE
	if _flask_heal_flash > 0.0:
		body_col = body_col.lerp(VFX.TEAL, 0.5)
	# Contact shadow (shrinks and fades with air time), then the jointed knight.
	VFX.draw_contact_shadow(self, Vector2(0.0, h * 0.5 + 1.0), 36.0, 8.0, clampf(_air_time / 0.3, 0.0, 1.0))
	if _pose.is_empty():
		_pose = KnightArt.target(self).pose
	var still := Feedback.motion_reduced
	KnightArt.paint(self, Vector2.ZERO, _pose, facing, {
		"coat": body_col,
		"unshaded": _hurt_flash > 0.0,
		"flame_mode": _flame_time > 0.0,
		"t": 0.0 if still else _anim_time,
		"blink": 1.0 if fmod(_anim_time, 3.7) > 3.58 and not still else 0.0,
		"flip_scale": lerpf(1.0, 0.25, _turn_t / 0.07) if _turn_t > 0.0 else 1.0,
	}, _smear if _draw_attack and not _riposte_attack else {})
	if dead:
		return
	if _flame_time > 0.0:
		var aura_alpha := 0.10 + sin(_anim_time * 8.0) * 0.035
		draw_circle(Vector2(0.0, -8.0), 34.0, Color(1.0, 0.3, 0.05, aura_alpha))
		draw_arc(Vector2(0.0, -8.0), 30.0, 0.0, TAU, 32, Color(1.0, 0.55, 0.1, 0.45), 2.0)
	if _momentum_stacks > 0:
		# Momentum: one orbiting ember per stack, tighter and brighter as it grows.
		var stack_t := _momentum_t / Content.MOMENTUM_TIME
		for i in range(_momentum_stacks):
			var ang := _anim_time * 5.0 + float(i) * TAU / float(_momentum_stacks)
			var orbit := Vector2(cos(ang) * 24.0, -10.0 + sin(ang) * 9.0)
			VFX.draw_ember_dot(self, orbit, 2.4, VFX.GOLD, 0.5 + 0.5 * stack_t)
	if state == State.HEAL:
		var heal_progress := clampf(1.0 - _heal_time / Content.P_HEAL_TIME, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 33.0, -PI * 0.5, -PI * 0.5 + TAU * heal_progress, 32, VFX.TEAL, 4.0)
	# The blade smear is part of the puppet; the counterthrust keeps its own line.
	if _draw_attack and _riposte_attack:
		# Counterthrust: a narrow forward blade, not the normal circular sweep.
		var tip := Vector2(facing * (_attack_range + 8.0), -8.0)
		draw_line(Vector2(facing * 16.0, -4.0), tip, Color(VFX.TEAL, 0.7), 5.0, true)
		draw_line(Vector2(facing * 22.0, -4.0), tip, Color(VFX.HOT, 0.9), 1.5, true)
	if riposte_time > 0.0:
		# Diegetic cue stays with the fighter instead of adding another HUD panel;
		# a perfect parry's harder riposte reads in gold.
		var perfect := _riposte_mul > 1.0
		var word := "PERFECT" if perfect else "RIPOSTE"
		var cue := Color(VFX.GOLD if perfect else VFX.TEAL, 0.65 if Feedback.flash_reduced else 0.95)
		draw_string_outline(ThemeDB.fallback_font, Vector2(-31.0, -72.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color("100c1b"))
		draw_string(ThemeDB.fallback_font, Vector2(-31.0, -72.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cue)
		draw_line(Vector2(-25.0, -65.0), Vector2(-25.0 + 50.0 * riposte_time / Content.RIPOSTE_WINDOW, -65.0), cue, 2.0, true)
	# slam impact ring
	if _draw_slam_impact > 0.0:
		var rad: float = Content.P_SLAM_RADIUS + float(build.get("slam_radius_bonus", 0.0))
		var t: float = _draw_slam_impact / 0.3
		var c := Color(1.0, 0.8, 0.3, t * 0.7)
		draw_arc(Vector2(0.0, 10.0), rad * (1.0 - t * 0.3), 0, TAU, 32, c, 4.0)
		draw_arc(Vector2(0.0, 10.0), rad * (1.0 - t * 0.5), 0, TAU, 32, Color(1.0, 0.5, 0.2, t * 0.4), 2.0)
	# slam descent trail: a streak rising off the plunging blade.
	if _slam_active:
		for i in range(3):
			var sx := (float(i) - 1.0) * 7.0
			draw_line(Vector2(sx, -30.0 - float(i % 2) * 8.0), Vector2(sx, -64.0 - float(i % 2) * 10.0), Color(1.0, 0.8, 0.3, 0.35 - float(i % 2) * 0.12), 2.0)
	# parry shield arc
	if _draw_parry > 0.0:
		var pw: float = Content.PARRY_RANGE
		var t: float = clampf(_draw_parry / Content.PARRY_WINDOW, 0.0, 1.0)
		var col := VFX.TEAL if t > 0.3 else VFX.GOLD
		# crescent in front
		_draw_arc(Vector2(facing * 8.0, 0.0), pw * 0.9, 2.4, facing, col, 5.0)
		# glow
		draw_circle(Vector2(facing * pw * 0.4, 0.0), pw * 0.3, Color(col, 0.15 * t))
	# wall slide dust indicator
	if wall_sliding:
		var wx: float = _wall_dir * w * 0.5
		draw_line(Vector2(wx, -h * 0.3), Vector2(wx, h * 0.3), Color(0.8, 0.8, 0.9, 0.5), 2.0)
		for i in range(3):
			var dy: float = float(i) * 8.0 - 8.0
			draw_circle(Vector2(wx, dy + 12.0), 2.0, Color(0.8, 0.8, 0.9, 0.4))

func _draw_arc(origin: Vector2, radius: float, arc: float, dir: float, col: Color, thickness: float) -> void:
	var segments := 16
	var base := 0.0 if dir > 0.0 else PI
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var t := base - arc * 0.5 + arc * float(i) / float(segments)
		pts.append(origin + Vector2(cos(t), sin(t)) * radius)
	draw_polyline(pts, col, thickness, true)
	# fill fan lightly
	pts.append(origin)
	draw_colored_polygon(pts, Color(col, 0.18))
