class_name Boss
extends Enemy
## Phased boss: lunge, projectile fan, ground slam, arena charge. Phase 2 below
## 50% HP: faster, relentless, and it calls two wisps to the throne room.

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

func _draw() -> void:
	# The Ember Warden: an imposing, towering gothic inquisitor/executioner fused
	# to an ancient ember furnace. Redesigned from the ground up:
	# - Tall, athletic, towering proportion (elevated shoulders, narrow waist, tattered battle skirt)
	# - Elongated horned iron mitre / inquisitorial crown distinctly above the shoulders
	# - Organic cathedral ribcage furnace (pointed arch with glowing vertical ribs & cinders)
	# - Gothic flared pauldrons with hanging liturgical chains
	# - Massive executioner's greatsword / jagged guillotine blade etched with hot ember runes
	var flash := _hurt_flash > 0.0
	var w := Content.BOSS_W
	var h := Content.BOSS_H
	var t := _anim_t if not Feedback.motion_reduced else 0.0
	var p2 := phase == BPhase.TWO
	var hot := 1.45 if p2 else 1.0
	var iron := Color.WHITE if flash else Color("1c131a")
	var dark_iron := Color.WHITE if flash else Color("120b12")
	var plate := Color.WHITE if flash else Content.BOSS_COLOR
	var trim_gold := Color.WHITE if flash else Color("c98a3b")
	var steel := Color("6d6575")

	# Windup / attack progress drive anticipation and strike poses.
	var tw := 0.0
	if state == EState.WINDUP:
		tw = clampf(1.0 - st_timer / maxf(0.01, float(data.windup)), 0.0, 1.0)
	var ta := 0.0
	if state == EState.ATTACK:
		var _active := 0.22
		if action_idx == Action.CHARGE:
			_active = Content.BOSS_CHARGE_TIME
		elif not action_idx == Action.LUNGE:
			_active = 0.3
		ta = clampf(1.0 - st_timer / _active, 0.0, 1.0)

	var sy := 1.0
	var lean := 0.0
	match state:
		EState.WINDUP:
			match action_idx:
				Action.LUNGE:
					sy = 1.0 - 0.08 * tw
					lean = -0.16 * tw
				Action.FAN:
					sy = 1.0 + 0.04 * tw
					lean = -0.05 * tw
				_:
					sy = 1.0 + 0.06 * tw
					lean = 0.06 * tw
		EState.ATTACK:
			if action_idx == Action.LUNGE:
				lean = 0.20 * (1.0 - ta)
				sy = 1.0 + 0.05 * (1.0 - ta)
			else:
				sy = 1.0 - 0.06 * (1.0 - ta)
		EState.STAGGER:
			lean = -0.14 * clampf(stagger_t / 0.12, 0.0, 1.0)

	var air := clampf(_air_time / 0.3, 0.0, 1.0)
	if p2:
		var pulse := 0.14 + sin(t * 4.5) * 0.06
		draw_circle(Vector2.ZERO, w * 0.85, Color(1.0, 0.25, 0.05, pulse))
		draw_circle(Vector2.ZERO, w * 1.25, Color(1.0, 0.25, 0.05, pulse * 0.4))
	VFX.draw_contact_shadow(self, Vector2(0.0, h * 0.5 + 2.0), 92.0, 16.0, air)
	VFX.set_pose(self, Vector2(0.0, h * 0.5), facing, Vector2(2.0 - sy, sy), lean)

	# 1. Flowing liturgical cape & tattered battle skirt (replaces stocky squat)
	var sway := sin(t * 1.6) * 5.0
	var sway2 := sin(t * 1.6 + 1.2) * 4.0
	# Rear long cape
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.45, -h * 0.35), Vector2(w * 0.15, -h * 0.35),
		Vector2(w * 0.28 + sway * 0.4, h * 0.30), Vector2(w * 0.18 + sway, h * 0.54),
		Vector2(-w * 0.1, h * 0.42), Vector2(-w * 0.35 - sway, h * 0.56),
		Vector2(-w * 0.65 - sway * 1.4, h * 0.48), Vector2(-w * 0.75 - sway * 1.2, h * 0.05),
	]), Color.WHITE if flash else Color("160810"))
	# Front mid-layer mantle
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.38, -h * 0.30), Vector2(w * 0.18, -h * 0.30),
		Vector2(w * 0.15 + sway2, h * 0.22), Vector2(-w * 0.05, h * 0.48),
		Vector2(-w * 0.40 - sway2, h * 0.52), Vector2(-w * 0.58 - sway2, h * 0.15),
	]), Color.WHITE if flash else Color("320f1a"))

	# 2. Hanging executioner's chains (longer, gothic, flaring during movement)
	var chain_col := Color("5a5062")
	for i in range(3):
		var fi := float(i)
		var anchor := Vector2(-w * 0.42 - fi * 10.0, -h * 0.32 + fi * 6.0)
		if p2:
			VFX.draw_chain(self, anchor, 24.0 + fi * 8.0, sin(t * 8.0 + fi * 1.9) * 12.0, chain_col)
		else:
			VFX.draw_chain(self, anchor, 56.0 + fi * 14.0, sin(t * 1.8 + fi * 1.2) * 6.0, chain_col)
	VFX.draw_chain(self, Vector2(w * 0.46, -h * 0.28), 20.0 if p2 else 48.0, sin(t * (7.0 if p2 else 1.8) + 2.2) * (9.0 if p2 else 5.0), chain_col)

	# 3. Tall greaves and armored legs (slender, upright, imposing)
	for side: float in [-1.0, 1.0]:
		var hipx := side * 13.0
		var ankle := hipx + side * 4.0
		# Long thigh and calf lines
		draw_line(Vector2(hipx, h * 0.05), Vector2(hipx + side * 2.0, h * 0.26), iron, 12.0, true)
		draw_line(Vector2(hipx + side * 2.0, h * 0.26), Vector2(ankle, h * 0.47), dark_iron, 11.0, true)
		# Flared gothic knee poleyn (pointed diamond)
		draw_colored_polygon(PackedVector2Array([
			Vector2(hipx + side * 2.0 - 6.0, h * 0.24), Vector2(hipx + side * 2.0, h * 0.18),
			Vector2(hipx + side * 2.0 + 6.0, h * 0.24), Vector2(hipx + side * 2.0, h * 0.32),
		]), plate if flash else plate.darkened(0.15))
		draw_line(Vector2(hipx + side * 2.0, h * 0.18), Vector2(hipx + side * 2.0, h * 0.32), trim_gold, 1.5)
		# Pointed gothic sabaton / foot
		draw_colored_polygon(PackedVector2Array([
			Vector2(ankle - 8.0, h * 0.46), Vector2(ankle + 12.0, h * 0.46),
			Vector2(ankle + 16.0, h * 0.50), Vector2(ankle - 8.0, h * 0.50),
		]), iron)

	# 4. Off-hand arm & conjuring gesture (raises for fan / slam)
	var b_sh := Vector2(-w * 0.30, -h * 0.32)
	var b_rest := Vector2(-w * 0.48, h * 0.15)
	var b_hand := b_rest
	if state == EState.WINDUP and action_idx == Action.FAN:
		b_hand = b_rest.lerp(Vector2(-w * 0.52, -h * 0.68), tw)
	elif state == EState.WINDUP and action_idx == Action.SLAM:
		b_hand = b_rest.lerp(Vector2(-w * 0.55, -h * 0.15), tw)
	var b_el := (b_sh + b_hand) * 0.5 + Vector2(-8.0, 0.0)
	draw_line(b_sh, b_el, iron, 10.0, true)
	draw_line(b_el, b_hand, iron, 8.5, true)
	draw_circle(b_hand, 7.5, iron if flash else iron.darkened(0.2))
	draw_arc(b_hand, 7.5, -2.6, 0.6, 8, plate, 2.5)
	if state == EState.WINDUP and action_idx == Action.FAN:
		var palm := b_hand + Vector2(0.0, -12.0)
		VFX.draw_ember_dot(self, palm, 4.0 + tw * 6.0, VFX.EMBER, 0.7 + tw)
		for k in range(5):
			var a := t * 10.0 + float(k) * TAU / 5.0
			draw_circle(palm + Vector2(cos(a), sin(a)) * lerpf(28.0, 6.0, tw), 1.8, Color(VFX.HOT, 0.9))

	# 5. Torso: tapered gothic cuirass with waist cinch & ceremonial plate
	var torso := PackedVector2Array([
		Vector2(-w * 0.38, -h * 0.38), Vector2(w * 0.38, -h * 0.38),
		Vector2(w * 0.34, -h * 0.02), Vector2(w * 0.26, h * 0.16),
		Vector2(-w * 0.26, h * 0.16), Vector2(-w * 0.34, -h * 0.02),
	])
	VFX.draw_shaded_polygon(self, torso, iron, not flash)
	VFX.draw_rim(self, torso, 1.0, 1.1)

	# Segmented fluted chest plates
	for side: float in [-1.0, 1.0]:
		var pl := PackedVector2Array([
			Vector2(side * w * 0.12, -h * 0.36), Vector2(side * w * 0.34, -h * 0.36),
			Vector2(side * w * 0.30, -h * 0.06), Vector2(side * w * 0.22, h * 0.12),
			Vector2(side * w * 0.10, h * 0.08),
		])
		VFX.draw_shaded_polygon(self, pl, plate, not flash)
		VFX.draw_rim(self, pl, 1.0, 1.15)
		draw_line(Vector2(side * w * 0.12, -h * 0.36), Vector2(side * w * 0.22, h * 0.12), trim_gold, 1.5)

	# Capped iron belt and heraldic faulds
	draw_rect(Rect2(-w * 0.28, h * 0.14, w * 0.56, 7.0), dark_iron)
	draw_rect(Rect2(-w * 0.08, h * 0.13, w * 0.16, 9.0), trim_gold)

	# 6. Furnace Core: Cathedral ribcage with glowing molten interior (replaces square stove door)
	var core_c := Vector2(0.0, -h * 0.12)
	var flare := 1.0 + (tw * 0.7 if state == EState.WINDUP and action_idx == Action.FAN else 0.0)
	var heat := (0.9 + sin(t * 5.5) * 0.14) * hot * flare
	# Ambient core aura
	draw_circle(core_c, 36.0 * heat, Color(VFX.ORANGE, 0.12 * heat))
	draw_circle(core_c, 22.0 * heat, Color(VFX.HOT, 0.20 * heat))
	# Cathedral lancet-arch opening
	var arch_h := 38.0
	var arch_w := 12.0
	var arch_pts := PackedVector2Array([
		core_c + Vector2(-arch_w, arch_h * 0.5),
		core_c + Vector2(-arch_w, -arch_h * 0.1),
		core_c + Vector2(0.0, -arch_h * 0.55),
		core_c + Vector2(arch_w, -arch_h * 0.1),
		core_c + Vector2(arch_w, arch_h * 0.5),
	])
	draw_colored_polygon(arch_pts, VFX.VOID)
	# Burning interior hearth
	draw_circle(core_c + Vector2(0.0, 4.0), 11.0, Color(VFX.EMBER, 0.85))
	draw_circle(core_c + Vector2(0.0, 5.0), 7.0, Color(VFX.HOT, 0.95))
	draw_circle(core_c + Vector2(0.0, 6.0), 3.5, Color.WHITE)
	# Rising flames inside the ribcage
	VFX.draw_flame(self, core_c + Vector2(-3.5, 12.0), 22.0 * heat, 9.0, t, 0.0, VFX.HOT, VFX.GOLD)
	VFX.draw_flame(self, core_c + Vector2(3.5, 12.0), 26.0 * heat, 9.0, t, 2.3, VFX.HOT, VFX.GOLD)
	if p2:
		VFX.draw_flame(self, core_c + Vector2(0.0, 10.0), 32.0 * heat, 8.0, t, 4.1, Color.WHITE, VFX.HOT)
	# Organic arched bone-iron ribs curving across the furnace
	for r_idx in range(4):
		var ry := core_c.y - arch_h * 0.3 + float(r_idx) * 9.5
		var rib_curve := sin(float(r_idx) / 3.0 * PI) * 3.0
		draw_line(Vector2(-arch_w - 2.0, ry), Vector2(-1.0, ry + rib_curve), dark_iron, 2.5)
		draw_line(Vector2(arch_w + 2.0, ry), Vector2(1.0, ry + rib_curve), dark_iron, 2.5)
		draw_line(Vector2(-arch_w - 1.0, ry), Vector2(-1.0, ry + rib_curve), trim_gold, 1.0)
	# Outer gothic frame around the aperture
	draw_polyline(arch_pts, trim_gold, 2.0, true)

	# 7. Gothic Spired Pauldrons (tall, peaked upward, eliminating the flat hockey-pad line)
	for side: float in [-1.0, 1.0]:
		var pld := PackedVector2Array([
			Vector2(side * w * 0.18, -h * 0.38),
			Vector2(side * w * 0.36, -h * 0.52),  # high curved crest
			Vector2(side * w * 0.52, -h * 0.56),  # upward sweeping gothic spike
			Vector2(side * w * 0.56, -h * 0.34),  # tapering blade edge
			Vector2(side * w * 0.40, -h * 0.22),
			Vector2(side * w * 0.22, -h * 0.24),
		])
		VFX.draw_shaded_polygon(self, pld, iron, not flash)
		VFX.draw_rim(self, pld, 1.0, 1.2)
		draw_line(pld[0], pld[2], trim_gold, 2.0)
		draw_line(pld[2], pld[4], plate if flash else plate.darkened(0.1), 2.0)
		# Spire tip glow in phase 2
		if p2:
			VFX.draw_flame(self, pld[2], 14.0, 7.0, t, float(side) * 2.0, VFX.HOT, VFX.GOLD)

	# 8. Head & Inquisitor's Mitre / Horned Crown (raised on an armored gorget neck)
	var neck_y := -h * 0.38
	# Armored neck gorget
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9.0, neck_y), Vector2(9.0, neck_y),
		Vector2(12.0, neck_y - 8.0), Vector2(-12.0, neck_y - 8.0),
	]), dark_iron)
	draw_line(Vector2(-12.0, neck_y - 8.0), Vector2(12.0, neck_y - 8.0), trim_gold, 2.0)

	# Helm / Mitre: tall, pointed cathedral helmet
	var head_center_y := neck_y - 20.0
	var mitre := PackedVector2Array([
		Vector2(-14.0, head_center_y + 12.0),
		Vector2(-12.0, head_center_y - 6.0),
		Vector2(-6.0, head_center_y - 26.0),   # tall steeple peak
		Vector2(0.0, head_center_y - 34.0),    # mitre pinnacle
		Vector2(6.0, head_center_y - 26.0),
		Vector2(12.0, head_center_y - 6.0),
		Vector2(14.0, head_center_y + 12.0),
		Vector2(0.0, head_center_y + 16.0),
	])
	VFX.draw_shaded_polygon(self, mitre, iron, not flash)
	VFX.draw_rim(self, mitre, 1.0, 1.3)
	draw_line(Vector2(0.0, head_center_y - 34.0), Vector2(0.0, head_center_y + 16.0), trim_gold, 1.5)

	# Crown horns flaring from the temple
	for h_side: float in [-1.0, 1.0]:
		var horn := PackedVector2Array([
			Vector2(h_side * 10.0, head_center_y - 8.0),
			Vector2(h_side * 22.0, head_center_y - 24.0),
			Vector2(h_side * 18.0, head_center_y - 28.0),
			Vector2(h_side * 8.0, head_center_y - 14.0),
		])
		draw_colored_polygon(horn, dark_iron)
		draw_line(horn[0], horn[1], trim_gold, 1.5)
		if p2:
			VFX.draw_flame(self, horn[1], 16.0, 7.0, t, h_side * 1.5)

	# Weeping flame eye slit (single horizontal slit with glowing tear lines)
	draw_rect(Rect2(-9.0, head_center_y + 1.0, 18.0, 4.0), Color("080408"))
	var eye_col := VFX.HOT if p2 else VFX.GOLD
	var eye_blink := 0.88 + sin(t * 6.5) * 0.12
	VFX.draw_ember_dot(self, Vector2(-4.5, head_center_y + 3.0), 2.2 * (1.0 + tw * 0.4), eye_col, eye_blink * hot)
	VFX.draw_ember_dot(self, Vector2(4.5, head_center_y + 3.0), 2.2 * (1.0 + tw * 0.4), eye_col, eye_blink * hot)
	# Embers weeping down the visor
	draw_line(Vector2(-4.5, head_center_y + 5.0), Vector2(-4.5, head_center_y + 12.0), Color(VFX.EMBER, 0.75 * hot), 1.5)
	draw_line(Vector2(4.5, head_center_y + 5.0), Vector2(4.5, head_center_y + 12.0), Color(VFX.EMBER, 0.75 * hot), 1.5)

	# Mitre pinnacle flame
	VFX.draw_flame(self, Vector2(0.0, head_center_y - 32.0), 20.0 * (1.3 if p2 else 0.9), 9.0, t, 0.0, VFX.HOT, VFX.GOLD)

	# 9. Weapon Arm & Executioner's Greatsword (massive, jagged guillotine blade, two-handed poise)
	var f_sh := Vector2(w * 0.32, -h * 0.32)
	var rest := f_sh + Vector2(w * 0.12, h * 0.28)
	var back := Vector2(-w * 0.12, -h * 0.72)
	var overhead := Vector2(w * 0.24, -h * 0.94)
	var hand := rest
	var blade_ang := -1.30

	match state:
		EState.WINDUP:
			match action_idx:
				Action.LUNGE:
					hand = rest.lerp(back, tw)
					blade_ang = lerpf(-1.30, -2.45, tw)
				Action.SLAM:
					hand = rest.lerp(overhead, tw)
					blade_ang = lerpf(-1.30, -1.55, tw)
				_:
					hand = rest + Vector2(0.0, -tw * 8.0)
		EState.ATTACK:
			if action_idx == Action.LUNGE:
				var k := minf(1.0, ta * 1.6)
				hand = back.lerp(f_sh + Vector2(w * 0.68, h * 0.08), k)
				blade_ang = lerpf(-2.45, 0.20, k)
			else:
				var k := minf(1.0, ta * 1.8)
				hand = overhead.lerp(f_sh + Vector2(w * 0.30, h * 0.58), k)
				blade_ang = lerpf(-1.55, 1.25, k)

	# Arm segments
	var f_el := (f_sh + hand) * 0.5 + Vector2(7.0, -5.0)
	draw_line(f_sh, f_el, iron, 11.0, true)
	draw_line(f_el, hand, iron, 9.5, true)
	draw_circle(f_el, 6.0, plate if flash else plate.darkened(0.15))

	# Massive executioner's two-handed greatsword / guillotine blade
	# Pommel, long grip, cruciform guard
	draw_colored_polygon(VFX.limb(PackedVector2Array([
		Vector2(-20.0, -3.0), Vector2(5.0, -3.0), Vector2(5.0, 3.0), Vector2(-20.0, 3.0),
	]), hand, blade_ang), dark_iron)
	draw_circle(hand + Vector2(-20.0, 0.0).rotated(blade_ang), 4.5, trim_gold)
	# Crossguard (flared gothic quillons)
	var guard_poly := VFX.limb(PackedVector2Array([
		Vector2(4.0, -14.0), Vector2(8.0, -12.0), Vector2(8.0, 12.0), Vector2(4.0, 14.0),
		Vector2(2.0, 0.0),
	]), hand, blade_ang)
	draw_colored_polygon(guard_poly, trim_gold)

	# Blade: long, broad, jagged executioner guillotine (length 78px, width 18px)
	var blade_pts := PackedVector2Array([
		Vector2(8.0, -7.0),
		Vector2(58.0, -9.0),
		Vector2(82.0, -13.0),  # flared executioner tip
		Vector2(84.0, 11.0),
		Vector2(64.0, 10.0),
		Vector2(48.0, 12.0),
		Vector2(32.0, 8.0),
		Vector2(8.0, 7.0),
	])
	var transformed_blade := VFX.limb(blade_pts, hand, blade_ang)
	draw_colored_polygon(transformed_blade, Color("4a4252"))
	# Chiseled blade fuller & inner steel
	var inner_blade := VFX.limb(PackedVector2Array([
		Vector2(10.0, -4.0), Vector2(60.0, -5.0), Vector2(78.0, -8.0),
		Vector2(76.0, 4.0), Vector2(10.0, 3.0),
	]), hand, blade_ang)
	draw_colored_polygon(inner_blade, steel)

	# Glowing ember runes carved along the blade fuller
	var rune_start := hand + Vector2(16.0, 0.0).rotated(blade_ang)
	var rune_end := hand + Vector2(70.0, -2.0).rotated(blade_ang)
	draw_line(rune_start, rune_end, Color(VFX.EMBER, 0.8 * hot), 2.5)
	draw_line(rune_start, rune_end, Color(VFX.HOT, 0.95), 1.0)

	# Burning cutting edge
	var cut_edge := PackedVector2Array([
		transformed_blade[2], transformed_blade[3], transformed_blade[4],
		transformed_blade[5], transformed_blade[6], transformed_blade[7],
	])
	draw_polyline(cut_edge, Color(VFX.EMBER, 0.7 * hot), 4.5, true)
	draw_polyline(cut_edge, Color(VFX.HOT, 1.0), 2.0, true)
	draw_circle(hand, 5.0, iron)

	# Trailing blade flame & burning embers
	if p2 or (state == EState.ATTACK):
		var tip_pos := transformed_blade[2]
		VFX.draw_flame(self, tip_pos, 24.0 * hot, 11.0, t, 1.5, VFX.HOT, VFX.GOLD)
		for ep in range(3):
			var u := 0.25 + float(ep) * 0.3
			var e_pos := transformed_blade[0].lerp(transformed_blade[2], u)
			VFX.draw_ember_dot(self, e_pos, 2.5 * hot, VFX.GOLD, 0.8)

	if burn_time > 0.0:
		for i in range(3):
			VFX.draw_flame(self, Vector2(-w * 0.4 + float(i) * w * 0.4, -h * 0.35), 18.0, 10.0, t, float(i) * 2.3)

	draw_set_transform_matrix(Transform2D.IDENTITY)

	# 10. Stylized in-world telegraphs (ground arc, never a raw debug rectangle)
	if state == EState.WINDUP:
		var tele := PackedVector2Array()
		for i in range(19):
			var u := float(i) / 18.0
			tele.append(Vector2(lerpf(-w * 0.55, w * 0.55, u), h * 0.5 + 4.0 - sin(u * PI) * 8.0))
		draw_polyline(tele, Color(1.0, 0.35, 0.1, tw * 0.85), 3.5, true)
		draw_line(Vector2(-w * 0.55, h * 0.5 + 4.0), Vector2(-w * 0.55, -h * 0.45), Color(1.0, 0.35, 0.1, tw * 0.4), 2.0, true)
		draw_line(Vector2(w * 0.55, h * 0.5 + 4.0), Vector2(w * 0.55, -h * 0.45), Color(1.0, 0.35, 0.1, tw * 0.4), 2.0, true)

