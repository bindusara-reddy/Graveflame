class_name Boss
extends Enemy
## Phased boss: lunge, projectile fan, ground slam, arena charge. It waits
## seated on the Ember Throne and rises to meet the knight. Phase 2 below 50%
## HP: faster, relentless, and it calls two wisps to the throne room.
## Hits never cancel a committed move; they wear down its poise, and a broken
## guard (or any parry) drops it to one knee for a real punish window.

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
var _phase2_triggered := false
var _slam_wave_emitted := false
var _charge_dir := 1.0
var _charge_t := 0.0
var _summoned := false
## Game-time seconds from the killing blow to the Warden coming apart.
const SHATTER_T := 0.62
var _death_t := 0.0
var _shattered := false
## Hits each phase's guard absorbs before it breaks, indexed by BPhase. A heavier
## blow spends more (poise_dmg); a parry breaks it outright.
const POISE := [8.0, 8.0, 12.0]
## Seconds without a hit before the guard is whole again.
const POISE_REGEN_DELAY := 1.2
## How long a broken guard keeps the Warden on one knee, and the extra damage
## it takes meanwhile: the punish window.
const BREAK_TIME := 1.2
const BREAK_DAMAGE_MUL := 1.3
var _poise: float = POISE[BPhase.ONE]
var _poise_regen_t := 0.0
## Where the Warden sits on the Ember Throne (room._throne, x 640): haunches on
## the seat, feet on the top dais step.
const THRONE_SEAT := Vector2(640.0, Content.FLOOR_Y - 86.0)
## A seated Warden wakes when the knight comes this close, when WAKE_AFTER
## seconds have passed (half that once it has been felled before), or when hit.
const WAKE_RANGE := 310.0
const WAKE_AFTER := 3.0
## After waking it stands on the dais this long, lifting RISE_LIFT px so its
## feet clear the top step, then steps down toward the knight.
const RISE_STAND := 0.6
const RISE_LIFT := 17.0
## Set by the room before _ready: start seated on the throne, not standing.
var seated := false
var _seated_t := 0.0
## Seconds since waking from the throne; negative while it never sat.
var _rise_t := -1.0

func _ready() -> void:
	hp_max = Content.BOSS_HP
	if Enemy.vows.has("v_pyre"):
		# Vow of the Pyre: a hardier Warden that is already burning.
		hp_max = Content.BOSS_HP * 1.2
	kind = Kind.STALKER  # reuse melee shape
	data = Content.ENEMY[Kind.STALKER].duplicate()
	data.w = Content.BOSS_W
	data.h = Content.BOSS_H
	data.color = Content.BOSS_COLOR
	data.damage = Content.BOSS_DAMAGE
	hp = hp_max
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
		_step_intro(delta)
		return
	_regen_poise(delta)
	_check_phase2()
	match state:
		EState.SEEK: _boss_seek(delta)
		EState.WINDUP: _step_windup(delta)
		EState.ATTACK: _boss_attack(delta)
		EState.RECOVER: _boss_recover(delta)
		EState.STAGGER: _step_stagger(delta)
		EState.DEAD: pass

## Before the fight: seated and dormant, then rising off the throne. A Warden
## that never sat (tests, captures) just stands for intro_t.
func _step_intro(delta: float) -> void:
	if seated:
		_sit(delta)
		return
	if _rise_t >= 0.0:
		_rise(delta)
		return
	intro_t -= delta
	velocity.y += Content.GRAVITY * delta
	move_and_slide()
	if intro_t <= 0.0:
		_end_intro()

## Dormant on the throne, turned toward the knight, until something wakes it.
## The Vow of the Pyre wakes it at once: it is already burning.
func _sit(delta: float) -> void:
	_seated_t += delta
	var wait := WAKE_AFTER * (0.5 if Save.get_victories() > 0 else 1.0)
	if Enemy.vows.has("v_pyre"):
		wait = 0.0
	var player = _get_player()
	var near := false
	if player != null:
		var dx: float = player.global_position.x - global_position.x
		facing = signf(dx) if absf(dx) > 4.0 else facing
		near = absf(dx) < WAKE_RANGE
	if near or _seated_t >= wait:
		_wake()

func _wake() -> void:
	if seated:
		seated = false
		_rise_t = 0.0

## Stand up on the dais, then step down toward the knight. The fight begins the
## moment it lands, with the landing's dust and thud.
func _rise(delta: float) -> void:
	var was_standing := _rise_t >= RISE_STAND
	_rise_t += delta
	if _rise_t < RISE_STAND:
		global_position.y = THRONE_SEAT.y - RISE_LIFT * _rise_t / RISE_STAND
		return
	if not was_standing:
		velocity = Vector2(facing * 240.0, -320.0)
	velocity.y += Content.GRAVITY * delta
	move_and_slide()
	if is_on_floor():
		emit_signal("exploded", global_position + Vector2(0.0, Content.BOSS_H * 0.5), 120.0, 0.0)
		_end_intro()

func _end_intro() -> void:
	phase = BPhase.ONE
	state = EState.SEEK
	action_t = 0.55
	emit_signal("phase_changed", 1)
	if Enemy.vows.has("v_pyre"):
		_ignite()

func _check_phase2() -> void:
	if not _phase2_triggered and hp <= hp_max * Content.BOSS_PHASE2_AT:
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
	var target_speed := 0.0
	if player != null:
		var to_p: Vector2 = player.global_position - global_position
		facing = signf(to_p.x) if absf(to_p.x) > 4.0 else facing
		if absf(to_p.x) > 120.0:
			target_speed = facing * Content.BOSS_SPEED
	velocity.x = move_toward(velocity.x, target_speed, 1600.0 * delta)
	move_and_slide()
	action_t -= delta
	if action_t <= 0.0:
		_choose_action(player)

func _choose_action(player) -> void:
	var dx := 0.0
	if player != null:
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
	# Announce the chosen move at the decision point so every entry into a
	# windup is voiced, and the player can answer the one that is coming.
	emit_signal("telegraphed", _action_telegraph(), global_position, true)

## Telegraph id for the move just chosen: the Action's own name, lower-cased
## ("lunge", "slam"), resolved to a sound by the game. anticipation_contract
## checks every Action has one.
func _action_telegraph() -> String:
	return str(Action.keys()[action_idx]).to_lower()

## Start winding up `action` for `seconds`. data.windup carries the same length
## because WardenArt reads it to pace the tell.
func _wind_up(action: int, seconds: float) -> void:
	action_idx = action
	state = EState.WINDUP
	st_timer = seconds
	data.windup = seconds

func _begin_lunge() -> void:
	var seconds := 0.4 if phase == BPhase.TWO else 0.55
	_wind_up(Action.LUNGE, seconds)

func _begin_fan() -> void:
	var seconds := 0.5 if phase == BPhase.TWO else 0.65
	_wind_up(Action.FAN, seconds)

func _begin_slam() -> void:
	_wind_up(Action.SLAM, 0.45)
	velocity.y = -700.0  # leap

func _begin_charge() -> void:
	var seconds := 0.5 if phase == BPhase.TWO else 0.7
	_wind_up(Action.CHARGE, seconds)
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
	if player != null:
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
	var damage := Content.BOSS_SHOT_DAMAGE * 0.8 * Enemy.vow_damage()
	for side: float in [-1.0, 1.0]:
		projectile_requested.emit("enemy", global_position + Vector2(side * 30.0, 0.0), Vector2(side * speed, 0.0), damage, 120.0, 0, 1.4, Content.BOSS_COLOR)
	if phase == BPhase.TWO:
		# Phase 2 adds a slower, higher pair so a single jump no longer clears everything.
		for side: float in [-1.0, 1.0]:
			projectile_requested.emit("enemy", global_position + Vector2(side * 30.0, -70.0), Vector2(side * speed * 0.55, 0.0), damage, 120.0, 0, 1.6, Content.BOSS_COLOR)
	emit_signal("exploded", global_position + Vector2(0.0, Content.BOSS_H * 0.45), 120.0, 0.0)

func _boss_recover(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
	move_and_slide()
	st_timer -= delta
	if st_timer <= 0.0:
		state = EState.SEEK
		action_t = 0.3 if phase == BPhase.TWO else 0.55

func take_damage(amount: float, from_dir: Vector2, _kb: float, poise_dmg := 1.0) -> void:
	if dead: return
	if is_broken():
		amount *= BREAK_DAMAGE_MUL
	var dealt := minf(amount, maxf(hp, 0.0))
	hp -= amount
	_hurt_flash = 0.08
	emit_signal("damaged", dealt, global_position + Vector2(0.0, -Content.BOSS_H * 0.5), false)
	if hp <= 0.0:
		_die()
		return
	if phase == BPhase.INTRO:
		_wake()
		return
	if is_broken():
		return
	# Hyper-armour: the blow lands and flashes but never cancels what the
	# Warden is doing; it only spends poise.
	_poise_regen_t = POISE_REGEN_DELAY
	_poise -= poise_dmg
	if _poise <= 0.0:
		_break_guard(from_dir)

## A parried blow always breaks the guard, however much poise is left.
func on_parried(knock_dir: Vector2) -> void:
	if not dead and not is_broken():
		_break_guard(knock_dir)

## True while the guard is broken and the Warden kneels open to punishment.
func is_broken() -> bool:
	return state == EState.STAGGER and not dead

## The guard gives: whatever was in hand is dropped and the Warden falls to one
## knee for BREAK_TIME. The knee strikes the floor with the slam's dust and thud.
func _break_guard(from_dir: Vector2) -> void:
	_disarm()
	state = EState.STAGGER
	stagger_t = BREAK_TIME
	action_t = 0.3
	velocity = Vector2(signf(from_dir.x) * 160.0, 0.0)
	_poise = POISE[phase]
	emit_signal("exploded", global_position + Vector2(0.0, Content.BOSS_H * 0.5), 90.0, 0.0)

## Poise refills all at once after POISE_REGEN_DELAY seconds untouched, so only
## a sustained assault (or a parry) breaks the guard.
func _regen_poise(delta: float) -> void:
	_poise_regen_t -= delta
	if _poise_regen_t <= 0.0:
		_poise = POISE[phase]

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
	if phase == BPhase.INTRO and state == EState.SEEK and (seated or _rise_t >= 0.0):
		# Seated: dark eye, crown banked to embers. Waking, the eye kindles
		# first, then the crown blooms as it stands.
		var woke := 0.0 if seated else _rise_t
		WardenArt.seat(p, 1.0 - clampf(woke / RISE_STAND, 0.0, 1.0))
		p["eye"] = clampf(woke / 0.25, 0.0, 1.0)
		p["crown"] = lerpf(0.3, 1.0, clampf(woke / 0.5, 0.0, 1.0))
	if dead:
		var k := clampf(_death_t / SHATTER_T, 0.0, 1.0)
		p["dying"] = k
		var amp := 1.5 + 5.0 * k
		p["jitter"] = Vector2(sin(_death_t * 91.0), cos(_death_t * 73.0)) * amp if not Feedback.motion_reduced else Vector2.ZERO
		p["lean"] = -0.12 * k
	return p

func _draw() -> void:
	WardenArt.paint(self, visual_pose())
