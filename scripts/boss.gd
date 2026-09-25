class_name Boss
extends Enemy
## Phased boss: lunge, projectile fan, ground slam, arena charge. Phase 2 below
## 50% HP: faster, relentless, and it calls two wisps to the throne room.

const WardenArt := preload("res://scripts/warden_art.gd")

signal phase_changed(phase: int)
signal summon_requested(kind: int, pos: Vector2)
## The felled Warden breaking apart, a beat after the killing blow.
signal shattered(pos: Vector2)

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
## Game-time seconds from the killing blow to the Warden coming apart.
const SHATTER_T := 0.62
var _death_t := 0.0
var _shattered := false

func _ready() -> void:
	if Enemy.vows.has("v_pyre"):
		# Vow of the Pyre: a hardier Warden that is already burning.
		max_hp = Content.BOSS_HP * 1.2
	kind = Kind.STALKER  # reuse melee shape
	data = Content.ENEMY[Kind.STALKER].duplicate()
	data.w = Content.BOSS_W
	data.h = Content.BOSS_H
	data.color = Content.BOSS_COLOR
	data.damage = Content.BOSS_DAMAGE
	hp = max_hp
	hp_max = max_hp
	_owner_id = get_instance_id()
	_build_bodies(Vector2(Content.BOSS_W, Content.BOSS_H), Vector2(60.0, 20.0))
	phase = BPhase.INTRO
	state = EState.SEEK

func _physics_process(delta: float) -> void:
	if dead:
		_step_death(delta)
		return
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
			if Enemy.vows.has("v_pyre"):
				_ignite()
		return
	_check_phase2()
	match state:
		EState.SEEK: _boss_seek(delta)
		EState.WINDUP: _step_windup(delta)
		EState.ATTACK: _boss_attack(delta)
		EState.RECOVER: _boss_recover(delta)
		EState.STAGGER: _step_stagger(delta)
		EState.DEAD: pass

func _check_phase2() -> void:
	if not _phase2_triggered and hp <= max_hp * Content.BOSS_PHASE2_AT:
		_ignite()

## Phase two: faster, relentless, and two wisps called to the throne.
func _ignite() -> void:
	if _phase2_triggered:
		return
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
			velocity.x = move_toward(velocity.x, facing * Content.BOSS_SPEED, 1600.0 * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
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
	# Announce the chosen move at the decision point so every entry into a
	# windup is voiced, and the player can answer the one that is coming.
	emit_signal("telegraphed", _action_telegraph(), global_position, true)

## Telegraph id for the move just chosen, resolved to a sound by the game.
func _action_telegraph() -> String:
	match action_idx:
		Action.FAN: return "fan"
		Action.SLAM: return "slam"
		Action.CHARGE: return "charge"
		_: return "lunge"

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
	var charge := action_idx == Action.CHARGE
	velocity.y += Content.GRAVITY * delta
	if charge:
		# Locked heading: the telegraph promised this line, so it never tracks the player.
		_charge_t -= delta
		velocity.x = _charge_dir * Content.BOSS_CHARGE_SPEED
		if is_on_wall():
			_charge_t = 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
	move_and_slide()
	st_timer -= delta
	if action_idx == Action.SLAM and is_on_floor() and not _slam_wave_emitted:
		_slam_wave_emitted = true
		_emit_slam_waves()
	var dmg := Content.BOSS_DAMAGE * (1.15 if charge else 1.0) * Enemy.vow_damage()
	var knock := 480.0 if charge else 420.0
	_strike_overlaps(dmg, Vector2(facing, -0.3), knock)
	var finished := st_timer <= 0.0
	if charge:
		finished = _charge_t <= 0.0
	if finished:
		_disarm()
		velocity.x *= 0.2
		state = EState.RECOVER
		if charge:
			st_timer = 0.55 if phase == BPhase.TWO else 0.8
		else:
			st_timer = 0.5 if phase == BPhase.TWO else 0.7

func _step_windup(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
	move_and_slide()
	st_timer -= delta
	if st_timer <= 0.0:
		match action_idx:
			Action.LUNGE: _do_lunge()
			Action.FAN: _do_fan()
			Action.SLAM: _do_slam()
			Action.CHARGE: _do_charge()

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
		emit_signal("projectile_requested", "enemy", global_position + Vector2(0.0, -20.0), v, Content.BOSS_SHOT_DAMAGE * Enemy.vow_damage(), 180.0, 0, 2.6, Content.BOSS_COLOR)
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
	emit_signal("projectile_requested", "enemy", global_position + Vector2(-30.0, 0.0), Vector2(-speed, 0.0), Content.BOSS_SHOT_DAMAGE * 0.8 * Enemy.vow_damage(), 120.0, 0, 1.4, Content.BOSS_COLOR)
	emit_signal("projectile_requested", "enemy", global_position + Vector2(30.0, 0.0), Vector2(speed, 0.0), Content.BOSS_SHOT_DAMAGE * 0.8 * Enemy.vow_damage(), 120.0, 0, 1.4, Content.BOSS_COLOR)
	if phase == BPhase.TWO:
		# Phase 2 adds a slower, higher pair so a single jump no longer clears everything.
		emit_signal("projectile_requested", "enemy", global_position + Vector2(-30.0, -70.0), Vector2(-speed * 0.55, 0.0), Content.BOSS_SHOT_DAMAGE * 0.8 * Enemy.vow_damage(), 120.0, 0, 1.6, Content.BOSS_COLOR)
		emit_signal("projectile_requested", "enemy", global_position + Vector2(30.0, -70.0), Vector2(speed * 0.55, 0.0), Content.BOSS_SHOT_DAMAGE * 0.8 * Enemy.vow_damage(), 120.0, 0, 1.6, Content.BOSS_COLOR)
	emit_signal("exploded", global_position + Vector2(0.0, Content.BOSS_H * 0.45), 120.0, 0.0)

func _boss_recover(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
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

## Shudder, crack with fire, then come apart. Visual only; the fight is over.
func _step_death(delta: float) -> void:
	if _shattered:
		return
	_death_t += delta
	_anim_t += delta
	velocity.x = 0.0
	velocity.y += Content.GRAVITY * delta
	move_and_slide()
	_hurt_flash = 0.1 if fmod(_death_t, 0.14) < 0.06 else 0.0
	if _death_t >= SHATTER_T:
		_shattered = true
		visible = false
		emit_signal("shattered", global_position + Vector2(0.0, -24.0))
	queue_redraw()

func visual_pose() -> Dictionary:
	var p := WardenArt.pose(self)
	if dead:
		var k := clampf(_death_t / SHATTER_T, 0.0, 1.0)
		p["dying"] = k
		var amp := 1.5 + 5.0 * k
		p["jitter"] = Vector2(sin(_death_t * 91.0), cos(_death_t * 73.0)) * amp if not Feedback.motion_reduced else Vector2.ZERO
		p["lean"] = -0.12 * k
	return p

func _draw() -> void:
	WardenArt.paint(self, visual_pose())
