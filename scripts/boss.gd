class_name Boss
extends Enemy
## Phased boss: lunge, projectile fan, ground slam. Phase 2 below 50% HP.

signal phase_changed(phase: int)
signal died_boss
signal hp_changed_boss(hp: float, max_hp: float)

enum BPhase { INTRO, ONE, TWO }

var phase: int = BPhase.INTRO
var intro_t := 1.2
var action_t := 1.5
var action_idx := 0
var max_hp := Content.BOSS_HP
var _phase2_triggered := false
var _slam_wave_emitted := false

func _ready() -> void:
	kind = Kind.STALKER  # reuse melee shape
	data = Content.ENEMY[Kind.STALKER].duplicate()
	data.w = Content.BOSS_W
	data.h = Content.BOSS_H
	data.color = Content.BOSS_COLOR
	data.damage = Content.BOSS_DAMAGE
	hp = max_hp
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
		_atk_shape.set_deferred("disabled", true)
		_atk_area.monitoring = false
		_atk_area.set_meta("attack_active", false)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	_wisp_t += delta  # reuse for aura pulsing
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

func _check_phase2() -> void:
	if not _phase2_triggered and hp <= max_hp * Content.BOSS_PHASE2_AT:
		_phase2_triggered = true
		phase = BPhase.TWO
		emit_signal("phase_changed", 2)
		_atk_shape.set_deferred("disabled", true)
		_atk_area.monitoring = false
		_atk_area.set_meta("attack_active", false)
		state = EState.SEEK
		action_t = 0.8

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
	var close := player != null and absf((player.global_position - global_position).x) < 110.0
	var options: Array = [0, 1, 2]  # 0 lunge, 1 fan, 2 slam
	if close: options = [0, 0, 2]   # bias melee when close
	if phase == BPhase.TWO: options.append_array([1, 1])  # more projectiles in p2
	action_idx = options[randi() % options.size()]
	match action_idx:
		0: _begin_lunge()
		1: _begin_fan()
		2: _begin_slam()
		_: _begin_lunge()

func _begin_lunge() -> void:
	state = EState.WINDUP
	st_timer = 0.4 if phase == BPhase.TWO else 0.55
	data.windup = st_timer

func _begin_fan() -> void:
	state = EState.WINDUP
	st_timer = 0.5 if phase == BPhase.TWO else 0.65
	data.windup = st_timer

func _begin_slam() -> void:
	state = EState.WINDUP
	st_timer = 0.45
	data.windup = st_timer
	velocity.y = -700.0  # leap

func _boss_attack(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = _approach(velocity.x, 0.0, 1600.0 * delta)
	move_and_slide()
	st_timer -= delta
	if action_idx == 2 and is_on_floor() and not _slam_wave_emitted:
		_slam_wave_emitted = true
		_emit_slam_waves()
	if not _atk_hit:
		for area in _atk_area.get_overlapping_areas():
			if not is_instance_valid(area): continue
			if area.get_meta("team") == "enemy": continue
			var tgt = area.get_meta("owner")
			if tgt != null and is_instance_valid(tgt) and tgt.has_method("take_damage"):
				tgt.take_damage(Content.BOSS_DAMAGE, Vector2(facing, -0.3), 420.0)
				_atk_hit = true
				break
	if st_timer <= 0.0:
		_atk_shape.disabled = true
		_atk_area.monitoring = false
		_atk_area.set_meta("attack_active", false)
		state = EState.RECOVER
		st_timer = 0.5 if phase == BPhase.TWO else 0.7

func _step_windup(delta: float) -> void:
	velocity.y += Content.GRAVITY * delta
	velocity.x = _approach(velocity.x, 0.0, 1800.0 * delta)
	move_and_slide()
	st_timer -= delta
	if st_timer <= 0.0:
		match action_idx:
			0: _do_lunge()
			1: _do_fan()
			2: _do_slam()

func _do_lunge() -> void:
	state = EState.ATTACK
	st_timer = 0.22
	_atk_hit = false
	_atk_shape.position = Vector2(facing * (Content.BOSS_W * 0.5 + 30.0), 0.0)
	_atk_shape.disabled = false
	_atk_area.monitoring = true
	_atk_area.set_meta("attack_active", true)
	velocity = Vector2(facing * 620.0, -180.0)

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
	_atk_hit = false
	_atk_shape.position = Vector2(0.0, 0.0)
	_atk_shape.disabled = false
	_atk_area.monitoring = true
	_atk_area.set_meta("attack_active", true)
	velocity = Vector2(0.0, 900.0)
	_slam_wave_emitted = false

func _emit_slam_waves() -> void:
	# Shockwaves happen on contact with the floor, not at the top of the leap.
	emit_signal("projectile_requested", "enemy", global_position + Vector2(-30.0, 0.0), Vector2(-Content.BOSS_SHOT_SPEED * 0.7, 0.0), Content.BOSS_SHOT_DAMAGE * 0.8, 120.0, 0, 1.4, Content.BOSS_COLOR)
	emit_signal("projectile_requested", "enemy", global_position + Vector2(30.0, 0.0), Vector2(Content.BOSS_SHOT_SPEED * 0.7, 0.0), Content.BOSS_SHOT_DAMAGE * 0.8, 120.0, 0, 1.4, Content.BOSS_COLOR)
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
	hp -= amount
	_hurt_flash = 0.08
	emit_signal("hp_changed_boss", hp, max_hp)
	# Boss resists knockback heavily
	if hp <= 0.0:
		_die()
		return
	if phase == BPhase.TWO:
		state = EState.SEEK  # no stagger in phase 2, relentless
	else:
		state = EState.STAGGER
		stagger_t = 0.12
		velocity = from_dir.normalized() * kb * 0.3

func _die(_award_reward: bool = true) -> void:
	dead = true
	state = EState.DEAD
	_atk_shape.disabled = true
	_atk_area.monitoring = false
	_atk_area.set_meta("attack_active", false)
	_hurtbox.set_deferred("monitorable", false)
	emit_signal("died", 200)
	emit_signal("died_boss")

func _draw() -> void:
	var col := Content.BOSS_COLOR
	if _hurt_flash > 0.0: col = Color.WHITE
	var w := Content.BOSS_W
	var h := Content.BOSS_H
	# aura in phase 2
	if phase == BPhase.TWO:
		var pulse := 0.12 + sin(_wisp_t * 4.0) * 0.05
		draw_circle(Vector2.ZERO, w * 0.8, Color(1.0, 0.3, 0.3, pulse))
		draw_circle(Vector2.ZERO, w * 1.1, Color(1.0, 0.3, 0.3, pulse * 0.5))
	# Floor shadow, torn mantle and plated silhouette.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-48.0, h * 0.50), Vector2(48.0, h * 0.50),
		Vector2(34.0, h * 0.59), Vector2(-34.0, h * 0.59),
	]), Color(0.0, 0.0, 0.0, 0.34))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-facing * 18.0, -h * 0.35),
		Vector2(-facing * 58.0, -h * 0.05),
		Vector2(-facing * 42.0, h * 0.42),
		Vector2(-facing * 12.0, h * 0.27),
	]), Color("421c2c"))
	draw_line(Vector2(-18.0, h * 0.18), Vector2(-22.0, h * 0.48), Color("241a2b"), 16.0, true)
	draw_line(Vector2(18.0, h * 0.18), Vector2(22.0, h * 0.48), Color("241a2b"), 16.0, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.48, -h * 0.34), Vector2(w * 0.48, -h * 0.34),
		Vector2(w * 0.56, h * 0.22), Vector2(0.0, h * 0.40),
		Vector2(-w * 0.56, h * 0.22),
	]), col)
	# Armor ribs and a furnace core make the boss legible at a glance.
	for rib in range(3):
		var ry := -h * 0.12 + float(rib) * 15.0
		draw_line(Vector2(-w * 0.36, ry), Vector2(w * 0.36, ry + 3.0), col.lightened(0.18), 3.0, true)
	var core_pulse := 0.85 + sin(_wisp_t * 6.0) * 0.12
	draw_circle(Vector2(0.0, 6.0), 12.0 * core_pulse, Color(1.0, 0.25, 0.08, 0.24))
	draw_circle(Vector2(0.0, 6.0), 6.0, Color("ff9d2e"))
	# Mask and crown spikes.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.34, -h * 0.46), Vector2(w * 0.34, -h * 0.46),
		Vector2(w * 0.28, -h * 0.18), Vector2(0.0, -h * 0.10),
		Vector2(-w * 0.28, -h * 0.18),
	]), Color("251823") if _hurt_flash <= 0.0 else Color.WHITE)
	for i in range(5):
		var x := lerpf(-w*0.4, w*0.4, float(i) / 4.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 6, -h*0.5), Vector2(x + 6, -h*0.5), Vector2(x, -h*0.5 - 16)
		]), col.lightened(float(i % 2) * 0.12))
	# eyes
	draw_line(Vector2(-13.0, -h * 0.31), Vector2(-3.0, -h * 0.28), Color("ffd23f"), 4.0, true)
	draw_line(Vector2(13.0, -h * 0.31), Vector2(3.0, -h * 0.28), Color("ffd23f"), 4.0, true)
	# Massive cleaver arm points toward the player.
	draw_line(Vector2(facing * 24.0, -10.0), Vector2(facing * 55.0, 16.0), Color("918697"), 9.0, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(facing * 48.0, 8.0), Vector2(facing * 75.0, 20.0),
		Vector2(facing * 58.0, 31.0), Vector2(facing * 40.0, 17.0),
	]), Color("b8a9b8"))
	# telegraph
	if state == EState.WINDUP:
		var t := 1.0 - st_timer / maxf(0.01, data.windup)
		draw_rect(Rect2(-w*0.5, -h*0.5, w, h), Color(1.0, 0.2, 0.2, t * 0.4), false, 4.0)
