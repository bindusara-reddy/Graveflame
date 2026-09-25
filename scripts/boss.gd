class_name Boss
extends Enemy
## The Ember Warden. It waits seated on the Ember Throne and rises to meet the
## knight: lunge, projectile fan, tracked leap-slam, arena charge. Hits never
## cancel a committed move; they wear down its poise, and a broken guard (or
## any parry) drops it to one knee for a real punish window. Phase 2 below 50%
## HP: it roars, its mantle catches, it strings its moves and calls wisps.
## Phase 3, the Last Ember, below 22%: it kneels as if spent, rises white-hot,
## and fights faster over a floor that catches fire.

const WardenArt := preload("res://scripts/warden_art.gd")

signal phase_changed(phase: int)
signal summon_requested(kind: int, pos: Vector2)
## The felled Warden breaking apart, a beat after the killing blow.
signal shattered(pos: Vector2)
## A slam shockwave running along the floor from pos: the game spawns it as a
## Projectile drawn as a fire ridge (style "wave").
signal wave_requested(pos: Vector2, vel: Vector2, dmg: float, life: float)

enum BPhase { INTRO, ONE, TWO, THREE }
enum Action { LUNGE, FAN, SLAM, CHARGE }
## Scripted moments that play out whatever the knight does.
enum Beat { NONE, ROAR, EMBER }

# --- The throne entrance ---
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

# --- Poise ---
## Hits each phase's guard absorbs before it breaks, indexed by BPhase. A heavier
## blow spends more (poise_dmg); a parry breaks it outright.
const POISE := [8.0, 8.0, 12.0, 12.0]
## Seconds without a hit before the guard is whole again.
const POISE_REGEN_DELAY := 1.2
## How long a broken guard keeps the Warden on one knee, and the extra damage
## it takes meanwhile: the punish window.
const BREAK_TIME := 1.2
const BREAK_DAMAGE_MUL := 1.3

# --- Moves ---
## Chance, by phase, that a lunge runs straight on into a string of moves.
const STRING_CHANCE := [0.0, 0.0, 0.4, 0.7]
## A linked move (the next of a string) winds up this fraction of its usual tell.
const LINK_WINDUP := 0.55
## A charge runs through the knight's spot and this far past it, so a Warden
## baited near a wall crashes into it and reels for WALL_STUN seconds.
const CHARGE_OVERRUN := 260.0
const WALL_STUN := 1.4
## The Warden's shots burn ember-bright: its fire is the brightest thing in a
## red room, never a wine-dark dart lost against it.
const SHOT_COLOR := Color("ff9a3c")
## A fan never buries a shot in the floor short of the knight: it is lifted until
## its lowest shot would meet the floor SKIM_PAST px beyond the knight's feet,
## SKIM_HEIGHT px up, so that shot skims the floor through the knight.
const SKIM_PAST := 160.0
const SKIM_HEIGHT := 12.0
## Slam shockwaves: a fire ridge this high along the floor, to be jumped, and
## once ignited a slower pair at WAVE_HIGH, over a standing knight's head, that
## catches a jump timed too early or too late.
const WAVE_LOW := 14.0
const WAVE_HIGH := 84.0

# --- Phase beats ---
## Health fraction where the Last Ember begins.
const LAST_EMBER_AT := 0.22
## The phase-two roar: it rears back, and at ROAR_PEAK its mantle catches.
const ROAR_TIME := 0.9
const ROAR_PEAK := 0.35
## The Last Ember: down on one knee until EMBER_KNEEL, rising until EMBER_PEAK,
## where it roars, throws a close knight back and sets the floor alight.
const EMBER_TIME := 1.6
const EMBER_KNEEL := 0.5
const EMBER_PEAK := 1.1
const ROAR_RADIUS := 170.0
const ROAR_DAMAGE := 6.0
## The Last Ember's charge leaves a fire patch every this many px.
const TRAIL_STEP := 60.0
## Warden fire patches are the Cinder Trail's burning ground at this scale,
## so the hazard reads at a glance.
const PATCH_SCALE := 1.5

## Game-time seconds from the killing blow to the Warden coming apart.
const SHATTER_T := 0.62

var phase: int = BPhase.INTRO
var intro_t := 1.2
var action_t := 1.5
var action_idx: int = Action.LUNGE
## Set by the room before _ready: start seated on the throne, not standing.
var seated := false
var _seated_t := 0.0
## Seconds since waking from the throne; negative while it never sat.
var _rise_t := -1.0
var _poise: float = POISE[BPhase.ONE]
var _poise_regen_t := 0.0
## The last two moves, so none comes three times running.
var _history: Array[int] = []
## Moves queued to follow the current one without a rest: the strings.
var _string: Array[int] = []
## Where the tracked leap-slam will come down (its marker burns there).
var slam_x := 0.0
var _slam_wave_emitted := false
var _charge_dir := 1.0
var _charge_t := 0.0
## Where the Last Ember's charge last left a fire patch.
var _trail_x := 0.0
## Reeling after a charge into the wall.
var _dazed := false
var _beat: int = Beat.NONE
var _beat_t := 0.0
var _death_t := 0.0
var _shattered := false

## A patch of the Warden's own fire: the Cinder Trail's burning ground turned
## on the knight. It kindles for ARM_T before it bites, and bites only once.
class EmberPatch extends "res://scripts/ground_fire.gd":
	const ARM_T := 0.3
	const DAMAGE := 8.0
	var _bitten := false

	func _ready() -> void:
		super._ready()
		collision_layer = 0
		collision_mask = Content.L_PLAYER_HURT

	func _physics_process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		queue_redraw()
		if _bitten or _t < ARM_T:
			return
		for area in get_overlapping_areas():
			var knight = area.get_meta("owner", null)
			if area.get_meta("team", "") == "player" and is_instance_valid(knight) and knight.has_method("take_damage"):
				_bitten = true
				knight.take_damage(DAMAGE * Enemy.vow_damage(), Vector2(0.0, -1.0), 200.0)
				return

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
	_check_phase2()
	_check_phase3()
	if _beat != Beat.NONE:
		_step_beat(delta)
		return
	_regen_poise(delta)
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
	_face_player()
	var player = _get_player()
	var near: bool = player != null and absf(player.global_position.x - global_position.x) < WAKE_RANGE
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
	if phase == BPhase.ONE and hp <= hp_max * Content.BOSS_PHASE2_AT:
		_ignite()

## After the roar has played out, so one big blow still plays both beats in order.
func _check_phase3() -> void:
	if phase == BPhase.TWO and _beat == Beat.NONE and hp <= hp_max * LAST_EMBER_AT:
		_last_ember()

## Phase two: the Warden roars and its mantle catches fire, then fights faster,
## stringing its moves, with two wisps called to the throne.
func _ignite() -> void:
	if phase >= BPhase.TWO:
		return
	phase = BPhase.TWO
	_begin_beat(Beat.ROAR)
	emit_signal("summon_requested", Content.BOSS_SUMMON_KIND, Vector2(300.0, Content.FLOOR_Y - 260.0))
	emit_signal("summon_requested", Content.BOSS_SUMMON_KIND, Vector2(980.0, Content.FLOOR_Y - 260.0))

## Phase three, the Last Ember: the Warden crashes to one knee as if spent,
## then rises white-hot for a faster, burning finish.
func _last_ember() -> void:
	phase = BPhase.THREE
	_begin_beat(Beat.EMBER)
	emit_signal("exploded", global_position + Vector2(0.0, Content.BOSS_H * 0.5), 90.0, 0.0)

## Drop whatever is in hand and play a scripted beat.
func _begin_beat(beat: int) -> void:
	_disarm()
	_string.clear()
	_dazed = false
	state = EState.SEEK
	_poise = POISE[phase]
	_beat = beat
	_beat_t = 0.0

## A beat plays out whatever the knight does. Its peak is the phase change the
## game answers (shake, callout, music); then the fight resumes.
func _step_beat(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
	move_and_slide()
	var roar := _beat == Beat.ROAR
	var peak := ROAR_PEAK if roar else EMBER_PEAK
	var before_peak := _beat_t < peak
	_beat_t += delta
	if before_peak and _beat_t >= peak:
		emit_signal("phase_changed", phase)
		if not roar:
			_roar_blast()
	if _beat_t >= (ROAR_TIME if roar else EMBER_TIME):
		_beat = Beat.NONE
		action_t = 0.3

## The Last Ember's roar throws a close knight back, and the floor around the
## Warden catches fire.
func _roar_blast() -> void:
	var player = _get_player()
	if player != null and player.has_method("take_damage"):
		var dx: float = player.global_position.x - global_position.x
		if absf(dx) < ROAR_RADIUS:
			player.take_damage(ROAR_DAMAGE * Enemy.vow_damage(), Vector2(signf(dx), -0.6), 560.0)
	for offset: float in [-110.0, -55.0, 55.0, 110.0]:
		_kindle(global_position.x + offset)

## Set a patch of hostile fire burning on the floor at x.
func _kindle(x: float) -> void:
	var patch := EmberPatch.new()
	patch.scale = Vector2.ONE * PATCH_SCALE
	patch.position = Vector2(clampf(x, Content.ROOM_LEFT + 20.0, Content.ROOM_RIGHT - 20.0), Content.FLOOR_Y)
	get_parent().add_child.call_deferred(patch)

func _boss_seek(delta: float) -> void:
	var player = _get_player()
	velocity.y += Content.GRAVITY * delta
	var target_speed := 0.0
	_face_player()
	if player != null and absf(player.global_position.x - global_position.x) > 120.0:
		target_speed = facing * Content.BOSS_SPEED
	velocity.x = move_toward(velocity.x, target_speed, 1600.0 * delta)
	move_and_slide()
	action_t -= delta
	if action_t <= 0.0:
		_choose_action(player)

## Turn toward the knight, unless it is right overhead.
func _face_player() -> void:
	var player = _get_player()
	if player != null:
		var dx: float = player.global_position.x - global_position.x
		facing = signf(dx) if absf(dx) > 4.0 else facing

## Seconds that are `calm` in phase one and `hot` once ignited; the Last Ember
## quickens everything again.
func _timing(calm: float, hot: float) -> float:
	var seconds := calm if phase < BPhase.TWO else hot
	return seconds * (0.85 if phase == BPhase.THREE else 1.0)

func _choose_action(player) -> void:
	var dx := 0.0
	if player != null:
		dx = absf((player.global_position - global_position).x)
	var options: Array = [Action.LUNGE, Action.FAN, Action.SLAM, Action.CHARGE]
	if dx < 110.0:
		options = [Action.LUNGE, Action.LUNGE, Action.SLAM]   # bias melee when close
	elif dx > 380.0:
		options.append_array([Action.CHARGE, Action.CHARGE])  # close the gap with a charge
	if phase >= BPhase.TWO:
		options.append_array([Action.FAN, Action.CHARGE])     # more pressure once ignited
	if _history.size() == 2 and _history[0] == _history[1]:
		# Never one move three times running: the fight keeps asking new questions.
		options = options.filter(func(a: int) -> bool: return a != _history[0])
	var action: int = options[randi() % options.size()]
	if action == Action.LUNGE and randf() < STRING_CHANCE[phase]:
		# A lunge runs on into a point-blank fan; the Last Ember lunges twice first.
		_string = [Action.LUNGE, Action.FAN] if phase == BPhase.THREE else [Action.FAN]
	_start(action)

## Wind up `action` and announce it at the decision point, so every entry into
## a windup is voiced and the player can answer the one that is coming. A
## linked move, the next of a string, comes on a shorter tell.
func _start(action: int, linked := false) -> void:
	_history.append(action)
	if _history.size() > 2:
		_history.pop_front()
	match action:
		Action.LUNGE: _begin_lunge()
		Action.FAN: _begin_fan()
		Action.SLAM: _begin_slam()
		Action.CHARGE: _begin_charge()
	if linked:
		st_timer *= LINK_WINDUP
		data.windup = st_timer
	emit_signal("telegraphed", _action_telegraph(), global_position, true)

## Every move ends here: straight into the next link of a string, or a rest of
## `rest` seconds, the knight's window to strike back.
func _finish_move(rest: float) -> void:
	_disarm()
	if not _string.is_empty():
		_face_player()
		_start(_string.pop_front(), true)
		return
	state = EState.RECOVER
	st_timer = rest

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
	_wind_up(Action.LUNGE, _timing(0.55, 0.4))

func _begin_fan() -> void:
	_wind_up(Action.FAN, _timing(0.65, 0.5))

## The leap tracks the knight: in phase one it covers only part of the gap, so
## a sidestep beats it; once ignited it comes down right on them. slam_x is
## where it will land, and the marker burns there. The windup is the leap's
## rise, so it is not quickened.
func _begin_slam() -> void:
	var seconds := 0.45
	_wind_up(Action.SLAM, seconds)
	var target_x := global_position.x
	var player = _get_player()
	if player != null:
		target_x = clampf(player.global_position.x, Content.ROOM_LEFT + 80.0, Content.ROOM_RIGHT - 80.0)
	var reach := 0.6 if phase < BPhase.TWO else 1.0
	var drift := clampf((target_x - global_position.x) * reach / seconds, -650.0, 650.0)
	velocity = Vector2(drift, -700.0)
	slam_x = global_position.x + drift * seconds

func _begin_charge() -> void:
	_wind_up(Action.CHARGE, _timing(0.7, 0.5))
	_charge_dir = facing

func _boss_attack(delta: float) -> void:
	var charge := action_idx == Action.CHARGE
	velocity.y += Content.GRAVITY * delta
	if charge:
		# Locked heading: the telegraph promised this line, so it never tracks the player.
		_charge_t -= delta
		velocity.x = _charge_dir * Content.BOSS_CHARGE_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
	move_and_slide()
	st_timer -= delta
	if charge and is_on_wall():
		_crash_into_wall()
		return
	if charge and phase == BPhase.THREE and absf(global_position.x - _trail_x) >= TRAIL_STEP:
		# The Last Ember's charge leaves the floor burning behind it.
		_trail_x = global_position.x
		_kindle(_trail_x)
	if action_idx == Action.SLAM and is_on_floor() and not _slam_wave_emitted:
		_slam_wave_emitted = true
		_emit_slam_waves()
	var dmg := Content.BOSS_DAMAGE * (1.15 if charge else 1.0) * Enemy.vow_damage()
	var knock := 480.0 if charge else 420.0
	_strike_overlaps(dmg, Vector2(facing, -0.3), knock)
	var finished := _charge_t <= 0.0 if charge else st_timer <= 0.0
	if finished:
		velocity.x *= 0.2
		_finish_move(_timing(0.8, 0.55) if charge else _timing(0.7, 0.5))

## The charge meets the wall: dust and a thud, and the Warden reels back dazed
## for WALL_STUN seconds, the reward for baiting it there.
func _crash_into_wall() -> void:
	_string.clear()
	_disarm()
	emit_signal("exploded", global_position + Vector2(_charge_dir * Content.BOSS_W * 0.5, 0.0), 120.0, 0.0)
	velocity = Vector2(-_charge_dir * 200.0, -180.0)
	state = EState.RECOVER
	st_timer = _timing(WALL_STUN, WALL_STUN * 0.8)
	_dazed = true

func _step_windup(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	if action_idx != Action.SLAM:
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
	var player = _get_player()
	if player != null:
		var ahead: float = (player.global_position.x - global_position.x) * _charge_dir
		_charge_t = clampf((ahead + CHARGE_OVERRUN) / Content.BOSS_CHARGE_SPEED, Content.BOSS_CHARGE_TIME, 1.5)
	st_timer = _charge_t
	_trail_x = global_position.x
	_arm(Content.BOSS_W * 0.5 + 24.0)
	velocity = Vector2(_charge_dir * Content.BOSS_CHARGE_SPEED, 0.0)

## A fan of shots centred on the knight, lifted where needed so its lowest
## shot skims the floor instead of burying itself short of the knight.
func _do_fan() -> void:
	var n: int = [3, 3, 5, 7][phase]
	var spread := 1.1 if phase == BPhase.THREE else 0.9
	var origin := global_position + Vector2(0.0, -20.0)
	# Angles here are tilts below the horizontal on the side the shots fly to.
	var side := facing
	var tilt := 0.0
	var player = _get_player()
	if player != null:
		var to_knight: Vector2 = player.global_position - origin
		side = signf(to_knight.x) if absf(to_knight.x) > 1.0 else facing
		tilt = atan2(to_knight.y, absf(to_knight.x))
		var skim := atan2(Content.FLOOR_Y - SKIM_HEIGHT - origin.y, absf(to_knight.x) + SKIM_PAST)
		tilt = minf(tilt, skim - spread * 0.5)
	for i in range(n):
		var a := tilt + lerpf(-spread * 0.5, spread * 0.5, float(i) / maxf(1.0, float(n - 1)))
		var v := Vector2(side * cos(a), sin(a)) * Content.BOSS_SHOT_SPEED
		projectile_requested.emit("enemy", origin, v, Content.BOSS_SHOT_DAMAGE * Enemy.vow_damage(), 180.0, 0, 2.6, SHOT_COLOR)
	_finish_move(_timing(0.85, 0.6))

func _do_slam() -> void:
	# On landing, melee burst + shockwave projectiles
	state = EState.ATTACK
	st_timer = 0.3
	_arm(0.0)
	velocity = Vector2(0.0, 900.0)
	_slam_wave_emitted = false

## Shockwaves run out both ways when the slam meets the floor, not at the top
## of the leap: a fire ridge along the floor, once ignited a slower high pair
## above it, and in the Last Ember fire left burning either side.
func _emit_slam_waves() -> void:
	var speed := Content.BOSS_SHOT_SPEED * 0.7
	var damage := Content.BOSS_SHOT_DAMAGE * 0.8 * Enemy.vow_damage()
	for side: float in [-1.0, 1.0]:
		var x := global_position.x + side * 40.0
		wave_requested.emit(Vector2(x, Content.FLOOR_Y - WAVE_LOW), Vector2(side * speed, 0.0), damage, 1.4)
		if phase >= BPhase.TWO:
			projectile_requested.emit("enemy", Vector2(x, Content.FLOOR_Y - WAVE_HIGH), Vector2(side * speed * 0.55, 0.0), damage, 120.0, 0, 1.6, SHOT_COLOR)
		if phase == BPhase.THREE:
			_kindle(global_position.x + side * 60.0)
	emit_signal("exploded", global_position + Vector2(0.0, Content.BOSS_H * 0.45), 120.0, 0.0)

func _boss_recover(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
	move_and_slide()
	st_timer -= delta
	if st_timer <= 0.0:
		state = EState.SEEK
		_dazed = false
		action_t = _timing(0.55, 0.3)

func take_damage(amount: float, from_dir: Vector2, _kb: float, poise_dmg := 1.0) -> void:
	if dead: return
	var at := global_position + Vector2(0.0, -Content.BOSS_H * 0.5)
	# The Last Ember, kneeling and rising, turns every blow. Enemy's
	# last_hit_blocked (set by name, as Enemy owns it) tells the blade it glanced.
	var turned := _beat == Beat.EMBER
	set("last_hit_blocked", turned)
	if turned:
		emit_signal("damaged", 0.0, at, true)
		return
	if is_broken():
		amount *= BREAK_DAMAGE_MUL
	var dealt := minf(amount, maxf(hp, 0.0))
	hp -= amount
	_hurt_flash = 0.08
	emit_signal("damaged", dealt, at, false)
	if hp <= 0.0:
		_die()
		return
	if phase == BPhase.INTRO:
		_wake()
		return
	if is_broken() or _beat != Beat.NONE:
		return
	# Hyper-armour: the blow lands and flashes but never cancels what the
	# Warden is doing; it only spends poise.
	_poise_regen_t = POISE_REGEN_DELAY
	_poise -= poise_dmg
	if _poise <= 0.0:
		_break_guard(from_dir)

## A parried blow always breaks the guard, however much poise is left.
func on_parried(knock_dir: Vector2) -> void:
	if not dead and not is_broken() and _beat == Beat.NONE:
		_break_guard(knock_dir)

## True while the guard is broken and the Warden kneels open to punishment.
func is_broken() -> bool:
	return state == EState.STAGGER and not dead

## The guard gives: whatever was in hand is dropped and the Warden falls to one
## knee for BREAK_TIME. The knee strikes the floor with the slam's dust and thud.
func _break_guard(from_dir: Vector2) -> void:
	_disarm()
	_string.clear()
	_dazed = false
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

## WardenArt.pose covers the moves and rests; the Warden's own moments (the
## throne, a broken guard, the phase beats, the slam marker, death) are layered
## on here, because the art may also be driven by a stand-in without them.
func visual_pose() -> Dictionary:
	var p := WardenArt.pose(self)
	if phase >= BPhase.TWO:
		# Ignited for good: the mantle burns; the Last Ember burns white-hot.
		p["mantle_fire"] = 1.0 if phase == BPhase.TWO else 1.4
		if phase == BPhase.THREE:
			p["crown"] = float(p.get("crown", 1.0)) * 1.25
			p["fissure"] = 4.5
			p["heat"] = 0.3
	if dead:
		var k := clampf(_death_t / SHATTER_T, 0.0, 1.0)
		p["dying"] = k
		var amp := 1.5 + 5.0 * k
		p["jitter"] = Vector2(sin(_death_t * 91.0), cos(_death_t * 73.0)) * amp if not Feedback.motion_reduced else Vector2.ZERO
		p["lean"] = -0.12 * k
		return p
	if phase == BPhase.INTRO and state == EState.SEEK and (seated or _rise_t >= 0.0):
		# Seated: dark eye, crown banked to embers. Waking, the eye kindles
		# first, then the crown blooms as it stands.
		var woke := 0.0 if seated else _rise_t
		WardenArt.seat(p, 1.0 - clampf(woke / RISE_STAND, 0.0, 1.0))
		p["eye"] = clampf(woke / 0.25, 0.0, 1.0)
		p["crown"] = lerpf(0.3, 1.0, clampf(woke / 0.5, 0.0, 1.0))
	if is_broken():
		# Down on one knee in 0.12 s, back up over the last 0.2 s, winded.
		var down := clampf((BREAK_TIME - stagger_t) / 0.12, 0.0, 1.0)
		WardenArt.kneel(p, minf(down, clampf(stagger_t / 0.2, 0.0, 1.0)))
		p["crown"] = float(p.get("crown", 1.0)) * 0.7
		p["pant"] = true
	if _beat != Beat.NONE:
		_beat_pose(p)
	if _dazed and not Feedback.motion_reduced:
		p["lean"] = float(p.lean) + sin(_anim_t * 6.0) * 0.06
	if action_idx == Action.SLAM and (state == EState.WINDUP or (state == EState.ATTACK and not _slam_wave_emitted)):
		p["marker"] = to_local(Vector2(slam_x, Content.FLOOR_Y))
		p["marker_k"] = 1.0 if state == EState.ATTACK else float(p.progress)
	return p

## The roar rears back to its peak and holds, shaking. The Last Ember drops to
## one knee with its crown guttering, then rises into the same roar, white-hot.
func _beat_pose(p: Dictionary) -> void:
	var peak := ROAR_PEAK
	if _beat == Beat.ROAR:
		WardenArt.blend(p, WardenArt.ROAR, clampf(_beat_t / ROAR_PEAK, 0.0, 1.0))
		if _beat_t < ROAR_PEAK:
			p["mantle_fire"] = 0.0
	else:
		peak = EMBER_PEAK
		var down := clampf(_beat_t / 0.25, 0.0, 1.0)
		var up := clampf((_beat_t - EMBER_KNEEL) / (EMBER_PEAK - EMBER_KNEEL), 0.0, 1.0)
		WardenArt.kneel(p, down * (1.0 - up))
		WardenArt.blend(p, WardenArt.ROAR, up)
		p["crown"] = lerpf(lerpf(1.0, 0.4, down), 1.25, up)
		p["fissure"] = lerpf(2.4, 4.5, up)
		p["heat"] = 0.3 * up
		p["mantle_fire"] = lerpf(1.0, 1.4, up)
	if _beat_t >= peak and not Feedback.motion_reduced:
		p["jitter"] = Vector2(sin(_anim_t * 71.0), cos(_anim_t * 57.0)) * 1.5

func _draw() -> void:
	WardenArt.paint(self, visual_pose())
