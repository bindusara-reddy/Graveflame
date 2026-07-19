class_name Player
extends CharacterBody2D
## Player controller: platforming, 3-hit combo, down-slam, ranged special, dash, parry,
## wall slide + wall jump, healing flask, hurt, custom drawing.
## A Dead Cells-inspired action-roguelite character. All art is drawn procedurally.

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

var build: Dictionary = {}
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
var _queued_attack := false
var dash_cd := 0.0
var dash_time := 0.0
var iframes := 0.0
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
var _attack_origin := Vector2.ZERO
var _attack_arc := 1.6
var _attack_range := 64.0
var _hurt_flash := 0.0
var _run_model: RunModel
var _owner_id := 0
# --- Down-slam ---
var _slam_active := false
var _slam_recover := 0.0
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
# --- Flask heal visual ---
var _flask_heal_flash := 0.0
var _heal_time := 0.0
# --- Full-meter Graveflame mode ---
var _flame_time := 0.0
var _anim_time := 0.0
var _input_lock_frames := 0

func setup(rm: RunModel) -> void:
	_run_model = rm
	build = rm.build
	_owner_id = get_instance_id()

func _ready() -> void:
	# Body collision
	collision_layer = Content.L_PLAYER_BODY
	collision_mask = Content.L_WORLD
	# Build body collision shape
	var bs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(Content.P_BODY_W, Content.P_BODY_H)
	bs.shape = rect
	add_child(bs)
	# Hurtbox
	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = Content.L_PLAYER_HURT
	_hurtbox.collision_mask = 0
	var hs := CollisionShape2D.new()
	var hrect := RectangleShape2D.new()
	hrect.size = Vector2(Content.P_BODY_W, Content.P_BODY_H)
	hs.shape = hrect
	_hurtbox.add_child(hs)
	_hurtbox.set_meta("team", "player")
	_hurtbox.set_meta("owner", self)
	_hurtbox.set_meta("owner_id", _owner_id)
	add_child(_hurtbox)
	# Attack hitbox
	_attack_area = Area2D.new()
	_attack_area.collision_layer = Content.L_PLAYER_ATK
	_attack_area.collision_mask = Content.L_ENEMY_HURT
	_attack_area.monitoring = false
	_atk_shape = CollisionShape2D.new()
	_atk_shape.shape = _atk_rect
	_atk_shape.disabled = true
	_attack_area.add_child(_atk_shape)
	add_child(_attack_area)
	# Parry deflection area (front-facing rectangle)
	_parry_area = Area2D.new()
	_parry_area.collision_layer = Content.L_PLAYER_ATK
	_parry_area.collision_mask = Content.L_ENEMY_ATK
	_parry_area.monitoring = false
	_parry_shape = CollisionShape2D.new()
	_parry_shape.shape = _parry_rect
	_parry_shape.disabled = true
	_parry_area.add_child(_parry_shape)
	add_child(_parry_area)
	jumps_left = Content.P_MAX_JUMPS
	if build.is_empty():
		build = {
			"max_hp": Content.P_MAX_HP, "hp": Content.P_MAX_HP, "speed_mul": 1.0, "dmg_mul": 1.0,
			"finish_mul": 1.0, "special_mul": 1.0, "special_pierce": false, "lifesteal": 0.0,
			"iframes_bonus": 0.0, "slam_mul": 1.0, "slam_radius_bonus": 0.0,
			"parry_bonus_dmg": 0.0, "parry_window_mul": 1.0, "flask_charges": Content.FLASK_MAX,
			"dash_cd_mul": 1.0, "dash_iframes_bonus": 0.0, "special_start": 0.0,
		}
	flask_max = int(build.get("flask_charges", Content.FLASK_MAX))
	flask_charges = flask_max
	special = float(build.get("special_start", 0.0))
	emit_signal("hp_changed", float(build.hp), float(build.max_hp))
	emit_signal("special_changed", special, max_special)
	emit_signal("flask_changed", flask_charges, flask_max)

func _physics_process(delta: float) -> void:
	if dead:
		return
	var controls_locked := _input_lock_frames > 0
	if controls_locked:
		_input_lock_frames -= 1
		attack_buffer = 0.0
		jump_buffer = 0.0
	_anim_time += delta
	if not controls_locked and Input.is_action_just_pressed("attack"):
		attack_buffer = Content.P_ATTACK_BUFFER
	else:
		attack_buffer = maxf(0.0, attack_buffer - delta)
	_flame_time = maxf(0.0, _flame_time - delta)
	if iframes > 0.0: iframes -= delta
	if dash_cd > 0.0: dash_cd -= delta
	if _hurt_flash > 0.0: _hurt_flash -= delta
	if _flask_heal_flash > 0.0: _flask_heal_flash -= delta
	if parry_cd > 0.0: parry_cd -= delta
	if _draw_parry > 0.0: _draw_parry -= delta
	if _draw_slam_impact > 0.0: _draw_slam_impact -= delta
	if _slam_recover > 0.0: _slam_recover -= delta
	coyote = maxf(0.0, coyote - delta)
	jump_buffer = maxf(0.0, jump_buffer - delta)
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

	queue_redraw()

# --- Locomotion ---
func _step_locomotion(delta: float, controls_locked: bool = false) -> void:
	var dir := 0.0 if controls_locked else Input.get_axis("move_left", "move_right")
	if dir != 0.0: facing = signf(dir)
	var accel := Content.P_AIR_ACCEL if not is_on_floor() else Content.P_ACCEL
	var target := dir * Content.P_SPEED * float(build.get("speed_mul", 1.0))
	velocity.x = _approach(velocity.x, target, accel * delta)
	# Gravity (reduced while wall sliding)
	var grav := Content.GRAVITY
	if wall_sliding and velocity.y > 0.0:
		grav = 0.0
		velocity.y = minf(velocity.y, Content.P_WALL_SLIDE_SPEED)
	velocity.y += grav * delta
	# Jump
	if not controls_locked and Input.is_action_just_pressed("jump"):
		jump_buffer = Content.P_JUMP_BUFFER
	# Wall jump takes priority over air jump when against a wall
	if jump_buffer > 0.0 and _wall_dir != 0.0 and not is_on_floor():
		_do_wall_jump()
		jump_buffer = 0.0
	elif jump_buffer > 0.0 and (is_on_floor() or coyote > 0.0 or jumps_left >= Content.P_MAX_JUMPS):
		_do_jump(false)
		jump_buffer = 0.0
	elif jump_buffer > 0.0 and jumps_left > 0 and not is_on_floor() and jumps_left < Content.P_MAX_JUMPS:
		_do_jump(true)
		jump_buffer = 0.0
	# Variable jump cut
	if not controls_locked and Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= Content.P_JUMP_CUT
	# Friction on ground when no input
	if dir == 0.0 and is_on_floor():
		velocity.x = _approach(velocity.x, 0.0, Content.P_FRICTION * delta)
	# Dash
	if not controls_locked and Input.is_action_just_pressed("dash") and dash_cd <= 0.0:
		_begin_dash()
		return
	# Parry
	if not controls_locked and Input.is_action_just_pressed("parry") and parry_cd <= 0.0:
		_begin_parry()
		return
	# Buffered attack (ground/upward air) or down-slam while falling.
	if attack_buffer > 0.0:
		attack_buffer = 0.0
		if not is_on_floor() and velocity.y > -50.0:
			_begin_slam()
			return
		_begin_attack()
		return
	# Special
	if not controls_locked and Input.is_action_just_pressed("special") and special >= Content.P_SPECIAL_COST:
		_do_special()
		return
	if not controls_locked and Input.is_action_just_pressed("ignite") and special >= max_special:
		_do_graveflame()
		return
	# Flask heal
	if not controls_locked and Input.is_action_just_pressed("heal"):
		_begin_heal()
		return
	move_and_slide()
	_floor_and_wall_tracking()

func _floor_and_wall_tracking() -> void:
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
				_wall_stick -= get_process_delta_time()
			else:
				wall_sliding = false

func _do_jump(is_double: bool) -> void:
	velocity.y = Content.P_DOUBLE_JUMP_VEL if is_double else Content.P_JUMP_VEL
	jumps_left -= 1
	if is_double: jumps_left = mini(jumps_left, Content.P_MAX_JUMPS - 1)
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

func _approach(current: float, target: float, max_delta: float) -> float:
	if current < target: return minf(current + max_delta, target)
	return maxf(current - max_delta, target)

# --- Attack combo ---
func _begin_attack(force_chain: bool = false) -> void:
	if force_chain and attack_index >= 0 and attack_index < Content.COMBO.size() - 1:
		attack_index += 1
	elif combo_timer > 0.0 and attack_index >= 0 and attack_index < Content.COMBO.size() - 1:
		attack_index += 1
	else:
		attack_index = 0
	var def: Dictionary = Content.COMBO[attack_index]
	attack_buffer = 0.0
	_queued_attack = false
	state = State.ATTACK
	atk_phase = "startup"
	atk_time = def.startup
	velocity.x = facing * float(def.get("lunge", 150.0))
	set_meta("atk_def", def)
	emit_signal("action_feedback", "swing", global_position)

func _step_attack(delta: float) -> void:
	if attack_buffer > 0.0 and attack_index < Content.COMBO.size() - 1:
		_queued_attack = true
		attack_buffer = 0.0
	# Recovery can be cancelled into a dash, keeping combat responsive without
	# removing the commitment of startup and active frames.
	if atk_phase == "recover" and Input.is_action_just_pressed("dash") and dash_cd <= 0.0:
		_deactivate_hitbox()
		_begin_dash()
		return
	velocity.y += Content.GRAVITY * delta
	var air_dir := Input.get_axis("move_left", "move_right")
	var drag := Content.P_AIR_ACCEL if not is_on_floor() else Content.P_FRICTION
	var target_x := air_dir * Content.P_SPEED * 0.45 if not is_on_floor() else 0.0
	velocity.x = _approach(velocity.x, target_x, drag * delta)
	var def: Dictionary = get_meta("atk_def")
	atk_time -= delta
	if atk_phase == "startup" and atk_time <= 0.0:
		atk_phase = "active"
		atk_time = def.active
		_activate_hitbox(def)
	elif atk_phase == "active":
		_scan_attack_hits(def)
		if atk_time <= 0.0:
			atk_phase = "recover"
			atk_time = def.recover
			_deactivate_hitbox()
	elif atk_phase == "recover" and atk_time <= 0.0:
		atk_phase = "none"
		if _queued_attack and attack_index < Content.COMBO.size() - 1:
			_begin_attack(true)
			return
		combo_timer = def.window
		state = State.LOCOMOTION
		attack_index = -1 if def.window <= 0.0 else attack_index
	move_and_slide()
	_floor_and_wall_tracking()

func _activate_hitbox(def: Dictionary) -> void:
	_attack_origin = Vector2(facing * 8.0, -8.0)
	_atk_rect.size = Vector2(def.range, Content.P_BODY_H + 10.0)
	_atk_shape.position = _attack_origin + Vector2(facing * def.range * 0.5, 0.0)
	_atk_shape.disabled = false
	_attack_area.monitoring = true
	_draw_attack = true
	_attack_arc = def.arc
	_attack_range = def.range
	atk_hit.clear()
	if attack_index == Content.COMBO.size() - 1 and _flame_time > 0.0:
		var wave_pos := global_position + Vector2(facing * 34.0, -8.0)
		emit_signal("projectile_requested", "player", wave_pos, Vector2(facing * 560.0, 0.0), 18.0 * float(build.get("dmg_mul", 1.0)), 320.0, 2, 0.32, Content.PAL.player_accent)

func _deactivate_hitbox() -> void:
	_atk_shape.disabled = true
	_attack_area.monitoring = false
	_draw_attack = false

func _scan_attack_hits(def: Dictionary) -> void:
	for area in _attack_area.get_overlapping_areas():
		if not is_instance_valid(area): continue
		var ateam = area.get_meta("team")
		if ateam == null or ateam == "player": continue
		var oid: int = area.get_meta("owner_id", 0)
		if atk_hit.has(oid): continue
		atk_hit[oid] = true
		var tgt = area.get_meta("owner")
		if tgt != null and is_instance_valid(tgt) and tgt.has_method("take_damage"):
			var dmg: float = def.damage * float(build.get("dmg_mul", 1.0))
			if attack_index == Content.COMBO.size() - 1:
				dmg *= float(build.get("finish_mul", 1.0))
			if _flame_time > 0.0:
				dmg *= Content.P_FLAME_DAMAGE_MUL
			tgt.take_damage(dmg, Vector2(facing, -0.2), def.knock)
			if _flame_time > 0.0 and tgt.has_method("apply_burn"):
				tgt.apply_burn(Content.P_FLAME_BURN_DPS, Content.P_FLAME_BURN_TIME)
			emit_signal("hit_landed", dmg, tgt.global_position, attack_index == Content.COMBO.size() - 1)
			_gain_special(Content.P_SPECIAL_GAIN * float(build.get("special_mul", 1.0)))
			if float(build.get("lifesteal", 0.0)) > 0.0:
				_heal(float(build.lifesteal))

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
	velocity.x = _approach(velocity.x, 0.0, Content.P_FRICTION * delta)
	move_and_slide()
	if is_on_floor():
		_do_slam_impact()
		_slam_active = false
		_slam_recover = Content.P_SLAM_RECOVER
		state = State.LOCOMOTION
	# Cull if somehow below world
	if global_position.y > Content.FLOOR_Y + 300:
		_slam_active = false
		state = State.LOCOMOTION

func _do_slam_impact() -> void:
	var radius: float = Content.P_SLAM_RADIUS + float(build.get("slam_radius_bonus", 0.0))
	var dmg: float = Content.P_SLAM_DAMAGE * float(build.get("slam_mul", 1.0)) * float(build.get("dmg_mul", 1.0))
	# AoE: damage all enemies overlapping a circle centered on player
	var center := global_position + Vector2(0.0, 10.0)
	# Use a temporary Area2D circle query
	var hit_any := false
	for area in get_tree().get_nodes_in_group("enemy_hurtbox"):
		if not is_instance_valid(area): continue
		if area.global_position.distance_to(center) <= radius + 24.0:
			var tgt = area.get_meta("owner")
			if tgt != null and is_instance_valid(tgt) and tgt.has_method("take_damage"):
				var kdir: Vector2 = (tgt.global_position - center).normalized()
				if kdir == Vector2.ZERO: kdir = Vector2.UP
				tgt.take_damage(dmg, Vector2(kdir.x, -0.7), Content.P_SLAM_KNOCK)
				hit_any = true
	if hit_any:
		_gain_special(Content.P_SPECIAL_GAIN * float(build.get("special_mul", 1.0)) * 2.0)
	_draw_slam_impact = 0.3
	emit_signal("slam_landed", center, radius)
	# small bounce
	velocity.y = -220.0

# --- Special ---
func _do_special() -> void:
	special -= Content.P_SPECIAL_COST
	emit_signal("special_changed", special, max_special)
	var spd := 700.0
	var dmg := 26.0 * float(build.get("dmg_mul", 1.0))
	if build.get("special_pierce", false): dmg *= 1.2
	var pierce := 3 if bool(build.get("special_pierce", false)) else 0
	var pos := global_position + Vector2(facing * 30.0, -10.0)
	emit_signal("projectile_requested", "player", pos, Vector2(facing * spd, 0.0), dmg, 360.0, pierce, 1.6, Content.PAL.special)
	emit_signal("action_feedback", "special", pos)

func _do_graveflame() -> void:
	special = 0.0
	_flame_time = Content.P_FLAME_DURATION
	iframes = maxf(iframes, 0.18)
	emit_signal("special_changed", special, max_special)
	emit_signal("action_feedback", "flame", global_position)

func _gain_special(amount: float) -> void:
	special = minf(max_special, special + amount)
	emit_signal("special_changed", special, max_special)

# --- Dash ---
func _begin_dash() -> void:
	state = State.DASH
	dash_time = Content.P_DASH_TIME
	dash_cd = Content.P_DASH_CD * float(build.get("dash_cd_mul", 1.0))
	iframes = maxf(iframes, Content.P_DASH_IFRAMES + float(build.get("dash_iframes_bonus", 0.0)))
	var dir := Input.get_axis("move_left", "move_right")
	if dir == 0.0: dir = facing
	velocity = Vector2(dir * Content.P_DASH_SPEED, 0.0)
	wall_sliding = false
	emit_signal("action_feedback", "dash", global_position)

func _step_dash(delta: float) -> void:
	dash_time -= delta
	velocity.y = 0.0
	if dash_time <= 0.0:
		state = State.LOCOMOTION
		velocity.x *= 0.5
	move_and_slide()

# --- Parry ---
func _begin_parry() -> void:
	state = State.PARRY
	parry_time = Content.PARRY_WINDOW * float(build.get("parry_window_mul", 1.0))
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
	velocity.x = _approach(velocity.x, 0.0, Content.P_FRICTION * delta)
	parry_time -= delta
	_scan_parry()
	if parry_time <= 0.0:
		_parry_shape.disabled = true
		_parry_area.monitoring = false
		if not _parry_succeeded:
			emit_signal("parried", global_position + Vector2(facing * 40.0, 0.0), false)
		state = State.LOCOMOTION
	move_and_slide()
	_floor_and_wall_tracking()

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
		if attack_kind == "projectile" and area.has_method("reflect"):
			area.reflect(Vector2(facing, -0.05), Content.PARRY_PROJECTILE_BOOST)
			_parry_hit[oid] = true
			_parry_succeeded = true
			emit_signal("parried", global_position + Vector2(facing * 40.0, 0.0), true)
			_gain_special(Content.P_SPECIAL_GAIN * 2.5)
			continue
		if attack_kind != "melee" or not bool(area.get_meta("attack_active", false)):
			continue
		var attacker = area.get_meta("owner", null)
		if attacker != null and is_instance_valid(attacker) and attacker.has_method("take_damage"):
			attacker.take_damage(Content.PARRY_DAMAGE + float(build.get("parry_bonus_dmg", 0.0)), Vector2(-facing, 0.0), 420.0)
			if attacker.has_method("on_parried"):
				attacker.on_parried(Vector2(facing, -0.2))
			_parry_hit[oid] = true
			_parry_succeeded = true
			emit_signal("parried", global_position + Vector2(facing * 40.0, 0.0), true)
			_gain_special(Content.P_SPECIAL_GAIN * 2.5)

# --- Healing flask ---
func _begin_heal() -> void:
	if flask_charges <= 0 or float(build.hp) >= float(build.max_hp):
		return
	state = State.HEAL
	_heal_time = Content.P_HEAL_TIME
	velocity.x *= 0.2
	emit_signal("action_feedback", "heal_start", global_position)

func _step_heal(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = _approach(velocity.x, 0.0, Content.P_FRICTION * 2.0 * delta)
	move_and_slide()
	_floor_and_wall_tracking()
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

func refill_flask() -> void:
	flask_max = int(build.get("flask_charges", Content.FLASK_MAX))
	flask_charges = flask_max
	emit_signal("flask_changed", flask_charges, flask_max)

# --- Hurt ---
func take_damage(amount: float, from_dir: Vector2, kb: float) -> void:
	if dead or iframes > 0.0: return
	# Only a confirmed forward deflection grants immunity. Hazards, explosions and
	# attacks from behind still connect during the parry animation.
	if state == State.PARRY and parry_time > 0.0:
		var parries_before := _parry_hit.size()
		_scan_parry()
		if _parry_hit.size() > parries_before:
			return
	build.hp = maxf(0.0, float(build.hp) - amount)
	if _run_model: _run_model.build.hp = build.hp
	emit_signal("hp_changed", float(build.hp), float(build.max_hp))
	_hurt_flash = 0.12
	if float(build.hp) <= 0.0:
		_die()
		return
	emit_signal("hurt_taken", amount, global_position)
	state = State.HURT
	iframes = Content.P_HURT_IFRAMES + float(build.get("iframes_bonus", 0.0))
	var hit_dir := from_dir.normalized()
	velocity = Vector2(hit_dir.x * kb, minf(-kb * 0.35, hit_dir.y * kb))
	atk_phase = "none"
	_deactivate_hitbox()
	wall_sliding = false

func _step_hurt(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = _approach(velocity.x, 0.0, Content.P_FRICTION * 3.0 * delta)
	move_and_slide()
	if absf(velocity.x) < 30.0 and is_on_floor():
		state = State.LOCOMOTION

func _heal(amount: float) -> void:
	build.hp = minf(float(build.max_hp), float(build.hp) + amount)
	if _run_model: _run_model.build.hp = build.hp
	emit_signal("hp_changed", float(build.hp), float(build.max_hp))

func _die() -> void:
	dead = true
	state = State.DEAD
	_deactivate_hitbox()
	emit_signal("died")

func respawn_at(pos: Vector2, reset_resources: bool = false) -> void:
	_deactivate_hitbox()
	if _parry_shape != null:
		_parry_shape.disabled = true
	if _parry_area != null:
		_parry_area.monitoring = false
	global_position = pos
	velocity = Vector2.ZERO
	dead = false
	state = State.LOCOMOTION
	iframes = 1.2
	attack_buffer = 0.0
	_queued_attack = false
	attack_index = -1
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
	_slam_recover = 0.0
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

# --- Drawing ---
func _draw() -> void:
	var w := Content.P_BODY_W
	var h := Content.P_BODY_H
	var flicker := iframes > 0.0 and fmod(iframes, 0.12) < 0.06
	var body_col: Color = Content.PAL.player if not flicker else Content.PAL.player_accent
	if _hurt_flash > 0.0: body_col = Color.WHITE
	if _flask_heal_flash > 0.0:
		body_col = body_col.lerp(Color("5fe8a8"), 0.5)
	# Grounding shadow and a compact, readable flame-headed silhouette.
	if is_on_floor():
		draw_colored_polygon(PackedVector2Array([
			Vector2(-18, h * 0.52), Vector2(18, h * 0.52),
			Vector2(12, h * 0.60), Vector2(-12, h * 0.60),
		]), Color(0.0, 0.0, 0.0, 0.28))
	var run_amount := clampf(absf(velocity.x) / Content.P_SPEED, 0.0, 1.0)
	var bob := sin(_anim_time * 14.0) * 1.5 * run_amount if is_on_floor() else 0.0
	var lean := clampf(velocity.x / 1800.0, -0.12, 0.12)
	draw_set_transform(Vector2(0.0, bob), lean, Vector2.ONE)
	# Tattered scarf/cape trails opposite the facing direction.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-facing * 7.0, -h * 0.3),
		Vector2(-facing * (25.0 + run_amount * 9.0), -h * 0.08),
		Vector2(-facing * 12.0, h * 0.24),
	]), Color("c94a28"))
	# Boots and legs.
	draw_line(Vector2(-7.0, h * 0.12), Vector2(-8.0 - facing * run_amount * 4.0, h * 0.48), Color("17131f"), 8.0, true)
	draw_line(Vector2(7.0, h * 0.12), Vector2(8.0 + facing * run_amount * 4.0, h * 0.48), Color("221a2c"), 8.0, true)
	# Asymmetric coat with a bright Graveflame sash.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.48, -h * 0.28), Vector2(w * 0.42, -h * 0.32),
		Vector2(w * 0.52, h * 0.24), Vector2(0.0, h * 0.36),
		Vector2(-w * 0.56, h * 0.20),
	]), body_col)
	draw_line(Vector2(-facing * 7.0, -h * 0.24), Vector2(facing * 8.0, h * 0.24), Content.PAL.player_accent, 4.0, true)
	# Dark mask under an animated, entirely procedural flame crown.
	var head_pos := Vector2(0.0, -h * 0.52)
	draw_circle(head_pos, w * 0.40, Color("211828"))
	var flame_col := Color("ff7a18") if _flame_time <= 0.0 else Color("ffd23f")
	for i in range(4):
		var fx := -9.0 + float(i) * 6.0
		var tip := 9.0 + sin(_anim_time * 10.0 + float(i) * 1.7) * 4.0
		draw_colored_polygon(PackedVector2Array([
			head_pos + Vector2(fx - 4.0, -4.0),
			head_pos + Vector2(fx, -tip - 7.0),
			head_pos + Vector2(fx + 4.0, -3.0),
		]), flame_col)
	draw_circle(head_pos + Vector2(facing * 4.0, -1.0), 2.8, Color("ffe8a3"))
	# Sword silhouette reads even when no attack arc is active.
	draw_line(Vector2(facing * 10.0, -4.0), Vector2(facing * 25.0, 13.0), Color("aab4c4"), 3.0, true)
	draw_line(Vector2(facing * 7.0, 0.0), Vector2(facing * 14.0, -7.0), Color("f0b45a"), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _flame_time > 0.0:
		var aura_alpha := 0.10 + sin(_anim_time * 8.0) * 0.035
		draw_circle(Vector2(0.0, -8.0), 34.0, Color(1.0, 0.3, 0.05, aura_alpha))
		draw_arc(Vector2(0.0, -8.0), 30.0, 0.0, TAU, 32, Color(1.0, 0.55, 0.1, 0.45), 2.0)
	if state == State.HEAL:
		var heal_progress := clampf(1.0 - _heal_time / Content.P_HEAL_TIME, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 33.0, -PI * 0.5, -PI * 0.5 + TAU * heal_progress, 32, Color("5fe8a8"), 4.0)
	# attack arc
	if _draw_attack:
		var origin := Vector2(facing * 8.0, -8.0)
		_draw_arc(origin, _attack_range, _attack_arc, facing, Content.PAL.attack, 4.0)
	# slam impact ring
	if _draw_slam_impact > 0.0:
		var rad: float = Content.P_SLAM_RADIUS + float(build.get("slam_radius_bonus", 0.0))
		var t: float = _draw_slam_impact / 0.3
		var c := Color(1.0, 0.8, 0.3, t * 0.7)
		draw_arc(Vector2(0.0, 10.0), rad * (1.0 - t * 0.3), 0, TAU, 32, c, 4.0)
		draw_arc(Vector2(0.0, 10.0), rad * (1.0 - t * 0.5), 0, TAU, 32, Color(1.0, 0.5, 0.2, t * 0.4), 2.0)
	# slam descent trail
	if _slam_active:
		draw_line(Vector2(0, 0), Vector2(0, 40), Color(1.0, 0.8, 0.3, 0.5), 3.0)
	# parry shield arc
	if _draw_parry > 0.0:
		var pw: float = Content.PARRY_RANGE
		var t: float = clampf(_draw_parry / Content.PARRY_WINDOW, 0.0, 1.0)
		var col := Color("7fd4ff") if t > 0.3 else Color("ffd23f")
		# crescent in front
		_draw_arc(Vector2(facing * 8.0, 0.0), pw * 0.9, 2.4, facing, col, 5.0)
		# glow
		draw_circle(Vector2(facing * pw * 0.4, 0.0), pw * 0.3, Color(col.r, col.g, col.b, 0.15 * t))
	# wall slide dust indicator
	if wall_sliding:
		var wx: float = _wall_dir * w * 0.5
		draw_line(Vector2(wx, -h * 0.3), Vector2(wx, h * 0.3), Color(0.8, 0.8, 0.9, 0.5), 2.0)
		for i in range(3):
			var dy: float = float(i) * 8.0 - 8.0
			draw_circle(Vector2(wx, dy + 12.0), 2.0, Color(0.8, 0.8, 0.9, 0.4))

func _draw_arc(origin: Vector2, radius: float, arc: float, dir: float, col: Color, thickness: float) -> void:
	var pts := PackedVector2Array()
	var n := 16
	var base := 0.0 if dir > 0.0 else PI
	for i in range(n + 1):
		var t := base - arc * 0.5 + arc * float(i) / float(n)
		if dir < 0.0: t = base + arc * 0.5 - arc * float(i) / float(n)
		pts.append(origin + Vector2(cos(t), sin(t)) * radius)
	if pts.size() >= 2:
		draw_polyline(pts, col, thickness, true)
		# fill fan lightly
		var fill := Color(col.r, col.g, col.b, 0.18)
		pts.append(origin)
		draw_colored_polygon(pts, fill)
