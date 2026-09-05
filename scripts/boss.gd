class_name Boss
extends Enemy
## Phased boss: lunge, projectile fan, ground slam, arena charge. Phase 2 below
## 50% HP: faster, relentless, and it calls two wisps to the throne room.

const WardenArt := preload("res://scripts/warden_art.gd")

signal phase_changed(phase: int)
signal died_boss
signal hp_changed_boss(hp: float, max_hp: float)
signal summon_requested(kind: int, pos: Vector2)

enum BPhase { INTRO, ONE, TWO }
enum Action { LUNGE, FAN, SLAM, CHARGE }

var phase: int = BPhase.INTRO
var intro_t := 1.2
var action_t := 1.5
var action_idx: int = Action.LUNGE
var max_hp := Content.BOSS_HP
var _phase2_triggered := false
var _slam_wave_emitted := false
var _charge_dir := 1.0
var _charge_t := 0.0
var _summoned := false

func _ready() -> void:
	kind = Kind.STALKER  # reuse melee shape
	data = Content.ENEMY[Kind.STALKER].duplicate()
	data.w = Content.BOSS_W
	data.h = Content.BOSS_H
	data.color = Content.BOSS_COLOR
	data.damage = Content.BOSS_DAMAGE
	hp = max_hp
	hp_max = max_hp
	_owner_id = get_instance_id()
	collision_layer = Content.L_ENEMY_BODY
	collision_mask = Content.L_WORLD
	var bs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(Content.BOSS_W, Content.BOSS_H)
	bs.shape = rect
	add_child(bs)
	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = Content.L_ENEMY_HURT
	_hurtbox.collision_mask = 0
	var hs := CollisionShape2D.new()
	var hrect := RectangleShape2D.new()
	hrect.size = Vector2(Content.BOSS_W, Content.BOSS_H)
	hs.shape = hrect
	_hurtbox.add_child(hs)
	_hurtbox.set_meta("team", "enemy")
	_hurtbox.set_meta("owner", self)
	_hurtbox.set_meta("owner_id", _owner_id)
	_hurtbox.add_to_group("enemy_hurtbox")
	add_child(_hurtbox)
	_atk_area = Area2D.new()
	_atk_area.collision_layer = Content.L_ENEMY_ATK
	_atk_area.collision_mask = Content.L_PLAYER_HURT
	_atk_area.monitoring = false
	_atk_shape = CollisionShape2D.new()
	var arect := RectangleShape2D.new()
	arect.size = Vector2(Content.BOSS_W + 60.0, Content.BOSS_H + 20.0)
	_atk_shape.shape = arect
	_atk_shape.disabled = true
	_atk_area.add_child(_atk_shape)
	_atk_area.set_meta("team", "enemy")
	_atk_area.set_meta("owner", self)
	_atk_area.set_meta("owner_id", _owner_id)
	_atk_area.set_meta("attack_kind", "melee")
	_atk_area.set_meta("attack_active", false)
	add_child(_atk_area)
	phase = BPhase.INTRO
	state = EState.SEEK

func _physics_process(delta: float) -> void:
	if dead: return
	_tick_status(delta)
	if dead: return
	if global_position.y > Content.FLOOR_Y + 220.0:
		# A physics edge case must never strand the run with an unreachable boss.
		global_position = Vector2(900.0, Content.FLOOR_Y - Content.BOSS_H * 0.6)
		velocity = Vector2.ZERO
		state = EState.SEEK
		action_t = 0.65
		_disarm()
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	_wisp_t += delta  # reuse for aura pulsing
	_air_time = 0.0 if is_on_floor() else minf(_air_time + delta, 1.0)
	_anim_t += delta
	queue_redraw()
	if phase == BPhase.INTRO:
		intro_t -= delta
		velocity.y += Content.GRAVITY * delta
		move_and_slide()
		if intro_t <= 0.0:
			phase = BPhase.ONE
			state = EState.SEEK
			action_t = 0.55
			emit_signal("phase_changed", 1)
		return
	_check_phase2()
	match state:
		EState.SEEK: _boss_seek(delta)
		EState.WINDUP: _step_windup(delta)
		EState.ATTACK: _boss_attack(delta)
		EState.RECOVER: _boss_recover(delta)
		EState.STAGGER: _step_stagger(delta)
		EState.DEAD: pass

func _disarm() -> void:
	_atk_shape.set_deferred("disabled", true)
	_atk_area.monitoring = false
	_atk_area.set_meta("attack_active", false)

func _check_phase2() -> void:
	if not _phase2_triggered and hp <= max_hp * Content.BOSS_PHASE2_AT:
		_phase2_triggered = true
		phase = BPhase.TWO
		emit_signal("phase_changed", 2)
		_disarm()
		state = EState.SEEK
		action_t = 0.8
		if not _summoned:
			_summoned = true
			emit_signal("summon_requested", Content.BOSS_SUMMON_KIND, Vector2(300.0, Content.FLOOR_Y - 260.0))
			emit_signal("summon_requested", Content.BOSS_SUMMON_KIND, Vector2(980.0, Content.FLOOR_Y - 260.0))

func _boss_seek(delta: float) -> void:
	var player = _get_player()
	velocity.y += Content.GRAVITY * delta
	if player != null and is_instance_valid(player):
		var to_p: Vector2 = player.global_position - global_position
		facing = signf(to_p.x) if absf(to_p.x) > 4.0 else facing
		if absf(to_p.x) > 120.0:
			velocity.x = _approach(velocity.x, facing * Content.BOSS_SPEED, 1600.0 * delta)
		else:
			velocity.x = _approach(velocity.x, 0.0, 1600.0 * delta)
	else:
		velocity.x = _approach(velocity.x, 0.0, 1600.0 * delta)
	move_and_slide()
	action_t -= delta
	if action_t <= 0.0:
		_choose_action(player)

func _choose_action(player) -> void:
	var dx := 0.0
	if player != null and is_instance_valid(player):
		dx = absf((player.global_position - global_position).x)
	var options: Array = [Action.LUNGE, Action.FAN, Action.SLAM, Action.CHARGE]
	if dx < 110.0:
		options = [Action.LUNGE, Action.LUNGE, Action.SLAM]   # bias melee when close
	elif dx > 380.0:
		options.append_array([Action.CHARGE, Action.CHARGE])  # close the gap with a charge
	if phase == BPhase.TWO:
		options.append_array([Action.FAN, Action.CHARGE])     # more pressure in p2
	action_idx = options[randi() % options.size()]
	match action_idx:
		Action.LUNGE: _begin_lunge()
		Action.FAN: _begin_fan()
		Action.SLAM: _begin_slam()
		Action.CHARGE: _begin_charge()
		_: _begin_lunge()

func _begin_lunge() -> void:
	action_idx = Action.LUNGE
	state = EState.WINDUP
	st_timer = 0.4 if phase == BPhase.TWO else 0.55
	data.windup = st_timer

func _begin_fan() -> void:
	action_idx = Action.FAN
	state = EState.WINDUP
	st_timer = 0.5 if phase == BPhase.TWO else 0.65
	data.windup = st_timer

func _begin_slam() -> void:
	action_idx = Action.SLAM
	state = EState.WINDUP
	st_timer = 0.45
	data.windup = st_timer
	velocity.y = -700.0  # leap

func _begin_charge() -> void:
	action_idx = Action.CHARGE
	state = EState.WINDUP
	st_timer = 0.5 if phase == BPhase.TWO else 0.7
	data.windup = st_timer
	_charge_dir = facing

func _boss_attack(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	if action_idx == Action.CHARGE:
		# Locked heading: the telegraph promised this line, so it never tracks the player.
		_charge_t -= delta
		velocity.x = _charge_dir * Content.BOSS_CHARGE_SPEED
		if is_on_wall():
			_charge_t = 0.0
	else:
		velocity.x = _approach(velocity.x, 0.0, 1600.0 * delta)
	move_and_slide()
	st_timer -= delta
	if action_idx == Action.SLAM and is_on_floor() and not _slam_wave_emitted:
		_slam_wave_emitted = true
		_emit_slam_waves()
	if not _atk_hit:
		for area in _atk_area.get_overlapping_areas():
			if not is_instance_valid(area): continue
			if area.get_meta("team") == "enemy": continue
			var tgt = area.get_meta("owner")
			if tgt != null and is_instance_valid(tgt) and tgt.has_method("take_damage"):
				var dmg := Content.BOSS_DAMAGE * (1.15 if action_idx == Action.CHARGE else 1.0)
				tgt.take_damage(dmg, Vector2(facing, -0.3), 480.0 if action_idx == Action.CHARGE else 420.0)
				_atk_hit = true
				break
	var finished := st_timer <= 0.0
	if action_idx == Action.CHARGE:
		finished = _charge_t <= 0.0
	if finished:
		_disarm()
		velocity.x *= 0.2
		state = EState.RECOVER
		if action_idx == Action.CHARGE:
			st_timer = 0.55 if phase == BPhase.TWO else 0.8
		else:
			st_timer = 0.5 if phase == BPhase.TWO else 0.7

func _step_windup(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = _approach(velocity.x, 0.0, 1800.0 * delta)
	move_and_slide()
	st_timer -= delta
	if st_timer <= 0.0:
		match action_idx:
			Action.LUNGE: _do_lunge()
			Action.FAN: _do_fan()
			Action.SLAM: _do_slam()
			Action.CHARGE: _do_charge()

func _arm(front_offset: float) -> void:
	_atk_hit = false
	_atk_shape.position = Vector2(facing * front_offset, 0.0)
	_atk_shape.disabled = false
	_atk_area.monitoring = true
	_atk_area.set_meta("attack_active", true)

func _do_lunge() -> void:
	state = EState.ATTACK
	st_timer = 0.22
	_arm(Content.BOSS_W * 0.5 + 30.0)
	velocity = Vector2(facing * 620.0, -180.0)

func _do_charge() -> void:
	state = EState.ATTACK
	facing = _charge_dir
	_charge_t = Content.BOSS_CHARGE_TIME
	st_timer = _charge_t
	_arm(Content.BOSS_W * 0.5 + 24.0)
	velocity = Vector2(_charge_dir * Content.BOSS_CHARGE_SPEED, 0.0)

func _do_fan() -> void:
	var n := 5 if phase == BPhase.TWO else 3
	var spread := 0.9
	var player = _get_player()
	var base_dir := Vector2(facing, 0.0)
	if player != null and is_instance_valid(player):
		base_dir = (player.global_position - global_position).normalized()
	var base_ang := base_dir.angle()
	for i in range(n):
		var a := base_ang + lerpf(-spread * 0.5, spread * 0.5, float(i) / maxf(1.0, float(n - 1)))
		var v := Vector2(cos(a), sin(a)) * Content.BOSS_SHOT_SPEED
		emit_signal("projectile_requested", "enemy", global_position + Vector2(0.0, -20.0), v, Content.BOSS_SHOT_DAMAGE, 180.0, 0, 2.6, Content.BOSS_COLOR)
	state = EState.RECOVER
	st_timer = 0.6 if phase == BPhase.TWO else 0.85

func _do_slam() -> void:
	# On landing, melee burst + shockwave projectiles
	state = EState.ATTACK
	st_timer = 0.3
	_arm(0.0)
	velocity = Vector2(0.0, 900.0)
	_slam_wave_emitted = false

func _emit_slam_waves() -> void:
	# Shockwaves happen on contact with the floor, not at the top of the leap.
	var speed := Content.BOSS_SHOT_SPEED * 0.7
	emit_signal("projectile_requested", "enemy", global_position + Vector2(-30.0, 0.0), Vector2(-speed, 0.0), Content.BOSS_SHOT_DAMAGE * 0.8, 120.0, 0, 1.4, Content.BOSS_COLOR)
	emit_signal("projectile_requested", "enemy", global_position + Vector2(30.0, 0.0), Vector2(speed, 0.0), Content.BOSS_SHOT_DAMAGE * 0.8, 120.0, 0, 1.4, Content.BOSS_COLOR)
	if phase == BPhase.TWO:
		# Phase 2 adds a slower, higher pair so a single jump no longer clears everything.
		emit_signal("projectile_requested", "enemy", global_position + Vector2(-30.0, -70.0), Vector2(-speed * 0.55, 0.0), Content.BOSS_SHOT_DAMAGE * 0.8, 120.0, 0, 1.6, Content.BOSS_COLOR)
		emit_signal("projectile_requested", "enemy", global_position + Vector2(30.0, -70.0), Vector2(speed * 0.55, 0.0), Content.BOSS_SHOT_DAMAGE * 0.8, 120.0, 0, 1.6, Content.BOSS_COLOR)
	emit_signal("exploded", global_position + Vector2(0.0, Content.BOSS_H * 0.45), 120.0, 0.0)

func _boss_recover(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = _approach(velocity.x, 0.0, 1800.0 * delta)
	move_and_slide()
	st_timer -= delta
	if st_timer <= 0.0:
		state = EState.SEEK
		action_t = 0.3 if phase == BPhase.TWO else 0.55

func take_damage(amount: float, from_dir: Vector2, kb: float) -> void:
	if dead: return
	var dealt := minf(amount, maxf(hp, 0.0))
	hp -= amount
	_hurt_flash = 0.08
	emit_signal("hp_changed_boss", hp, max_hp)
	emit_signal("damaged", dealt, global_position + Vector2(0.0, -Content.BOSS_H * 0.5), false)
	# Boss resists knockback heavily
	if hp <= 0.0:
		_die()
		return
	# A committed charge or phase-2 attack cannot be interrupted.
	if state == EState.ATTACK and action_idx == Action.CHARGE:
		return
	if phase == BPhase.TWO:
		if state == EState.STAGGER:
			state = EState.SEEK  # no stagger in phase 2, relentless
	else:
		if state == EState.ATTACK:
			_disarm()
		state = EState.STAGGER
		stagger_t = 0.12
		velocity = from_dir.normalized() * kb * 0.3

func _die(_award_reward: bool = true) -> void:
	if dead: return
	dead = true
	state = EState.DEAD
	_disarm()
	_hurtbox.set_deferred("monitorable", false)
	emit_signal("died", 300)
	emit_signal("died_boss")

func visual_pose() -> Dictionary:
	return WardenArt.pose(self)

func _draw() -> void:
	WardenArt.paint(self, visual_pose())
