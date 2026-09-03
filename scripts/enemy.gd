class_name Enemy
extends CharacterBody2D
## Compact state-machine enemy: STALKER (melee), HOPPER (leaping), WISP (ranged),
## BRUTE (shielded heavy), BOMBER (exploding kamikaze). Any of them may spawn as
## an elite: larger, tougher, gilded, and worth more cells.

const VFX := preload("res://scripts/vfx.gd")

signal died(score: int)
signal damaged(amount: float, pos: Vector2, blocked: bool)
signal projectile_requested(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color)
signal exploded(pos: Vector2, radius: float, damage: float)
signal pyre_burst(pos: Vector2, radius: float)

enum Kind { STALKER, HOPPER, WISP, BRUTE, BOMBER }
enum EState { SPAWN, SEEK, WINDUP, ATTACK, RECOVER, STAGGER, DEAD }

## Pyre boon damage, mirrored from the player's build by the game so a burning
## enemy can detonate against its neighbours without holding a player reference.
static var pyre_damage := 0.0

var kind: int = Kind.STALKER
var data: Dictionary = {}
var state: int = EState.SPAWN
var hp := 40.0
var hp_max := 40.0
var damage_mul := 1.0
var elite := false
var facing := -1.0
var st_timer := 0.0
var cd := 0.0
var stagger_t := 0.0
var dead := false
var _hurtbox: Area2D
var _atk_area: Area2D
var _atk_shape: CollisionShape2D
var _atk_hit := false
var _hurt_flash := 0.0
var _owner_id := 0
var _wisp_t := 0.0
var _wisp_y := 0.0
var _spawn_anim := 0.0
# --- Brute shield ---
var shield_hp := 0.0
var shield_active := false
var _shield_flash := 0.0
# --- Bomber fuse ---
var _fuse_t := 0.0
var _blast_radius := 90.0
var _fuse_total := 0.8
var _bomb_armed := false
# Graveflame damage-over-time status.
var burn_time := 0.0
var burn_dps := 0.0
var _ledge_ray: RayCast2D
var _air_time := 0.0  # visual only: drives the contact shadow
var _anim_t := 0.0  # visual only: idle motion clock
var _elite_anim := 0.0  # visual only: elite scale-up clock so elites pop instead of spawning big

## `mods` may carry hp_mul, dmg_mul (difficulty curve) and elite (bool).
func setup(p_kind: int, p_pos: Vector2, mods: Dictionary = {}) -> void:
	kind = p_kind
	data = Content.ENEMY[p_kind]
	elite = bool(mods.get("elite", false))
	_elite_anim = 0.25 if elite else 0.0
	var hp_mul := float(mods.get("hp_mul", 1.0)) * (Content.ELITE_HP_MUL if elite else 1.0)
	damage_mul = float(mods.get("dmg_mul", 1.0)) * (Content.ELITE_DMG_MUL if elite else 1.0)
	hp_max = float(data.hp) * hp_mul
	hp = hp_max
	global_position = p_pos
	_owner_id = get_instance_id()
	if bool(data.get("shielded", false)):
		shield_hp = float(data.get("shield_hp", 30.0)) * hp_mul
		shield_active = shield_hp > 0.0
	if bool(data.get("explodes", false)):
		_fuse_total = float(data.get("fuse", 0.8))
		_blast_radius = float(data.get("blast_radius", 90.0)) * (1.15 if elite else 1.0)

## Contact damage for this instance, after difficulty and elite multipliers.
func attack_damage() -> float:
	return float(data.damage) * damage_mul

func _ready() -> void:
	collision_layer = Content.L_ENEMY_BODY
	collision_mask = Content.L_WORLD
	if data.is_empty():
		data = Content.ENEMY[Kind.STALKER]
		hp_max = float(data.hp)
		hp = hp_max
	var bs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(float(data.w), float(data.h))
	bs.shape = rect
	add_child(bs)
	# Hurtbox
	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = Content.L_ENEMY_HURT
	_hurtbox.collision_mask = 0
	var hs := CollisionShape2D.new()
	var hrect := RectangleShape2D.new()
	hrect.size = Vector2(float(data.w), float(data.h))
	hs.shape = hrect
	_hurtbox.add_child(hs)
	_hurtbox.set_meta("team", "enemy")
	_hurtbox.set_meta("owner", self)
	_hurtbox.set_meta("owner_id", _owner_id)
	_hurtbox.add_to_group("enemy_hurtbox")
	add_child(_hurtbox)
	# Melee attack hitbox (used by stalker/hopper/brute)
	_atk_area = Area2D.new()
	_atk_area.collision_layer = Content.L_ENEMY_ATK
	_atk_area.collision_mask = Content.L_PLAYER_HURT
	_atk_area.monitoring = false
	_atk_shape = CollisionShape2D.new()
	var arect := RectangleShape2D.new()
	arect.size = Vector2(float(data.w) + 40.0, float(data.h) + 10.0)
	_atk_shape.shape = arect
	_atk_shape.disabled = true
	_atk_area.add_child(_atk_shape)
	_atk_area.set_meta("team", "enemy")
	_atk_area.set_meta("owner", self)
	_atk_area.set_meta("owner_id", _owner_id)
	_atk_area.set_meta("attack_kind", "melee")
	_atk_area.set_meta("attack_active", false)
	add_child(_atk_area)
	if kind == Kind.WISP:
		_wisp_y = global_position.y
		collision_mask = 0  # wisp hovers, ignores world
	else:
		_ledge_ray = RayCast2D.new()
		_ledge_ray.collision_mask = Content.L_WORLD
		_ledge_ray.exclude_parent = true
		_ledge_ray.enabled = true
		_ledge_ray.target_position = Vector2(0.0, 42.0)
		add_child(_ledge_ray)
	state = EState.SEEK
	_spawn_anim = 0.4

func _physics_process(delta: float) -> void:
	if dead: return
	_tick_status(delta)
	if dead: return
	if _bomb_armed:
		_fuse_t -= delta
		if _fuse_t <= 0.0:
			_do_explosion()
			return
	_spawn_anim = maxf(0.0, _spawn_anim - delta)
	_elite_anim = maxf(0.0, _elite_anim - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	_shield_flash = maxf(0.0, _shield_flash - delta)
	cd = maxf(0.0, cd - delta)
	if global_position.y > Content.FLOOR_Y + 220.0:
		_die(false)
		return
	_air_time = 0.0 if is_on_floor() else minf(_air_time + delta, 1.0)
	_anim_t += delta
	queue_redraw()
	match state:
		EState.SPAWN, EState.SEEK: _step_seek(delta)
		EState.WINDUP: _step_windup(delta)
		EState.ATTACK: _step_attack(delta)
		EState.RECOVER: _step_recover(delta)
		EState.STAGGER: _step_stagger(delta)
		EState.DEAD: pass

func _step_seek(delta: float) -> void:
	var player = _get_player()
	if player == null or not is_instance_valid(player):
		_apply_gravity(delta)
		_move_x(0.0, delta)
		move_and_slide()
		return
	var to_p: Vector2 = player.global_position - global_position
	facing = signf(to_p.x) if absf(to_p.x) > 4.0 else facing
	match kind:
		Kind.STALKER: _seek_stalker(to_p, delta)
		Kind.HOPPER: _seek_hopper(to_p, delta, player)
		Kind.WISP: _seek_wisp(to_p, delta, player)
		Kind.BRUTE: _seek_brute(to_p, delta)
		Kind.BOMBER: _seek_bomber(to_p, delta)

func _seek_stalker(to_p: Vector2, delta: float) -> void:
	_apply_gravity(delta)
	if absf(to_p.x) > 44.0:
		_move_x(facing * float(data.speed), delta)
	else:
		_move_x(0.0, delta)
	move_and_slide()
	if absf(to_p.x) < 50.0 and absf(to_p.y) < 60.0 and cd <= 0.0:
		_begin_windup()

func _seek_hopper(to_p: Vector2, delta: float, player) -> void:
	_apply_gravity(delta)
	if absf(to_p.x) > 70.0:
		_move_x(facing * float(data.speed), delta)
	else:
		_move_x(0.0, delta)
	move_and_slide()
	# Hop toward player when grounded and in range band
	if is_on_floor() and cd <= 0.0 and absf(to_p.x) < 360.0 and absf(to_p.x) > 50.0:
		velocity.y = -560.0
		velocity.x = facing * float(data.speed) * 1.4
	if absf(to_p.x) < 52.0 and absf(to_p.y) < 60.0 and cd <= 0.0:
		_begin_windup()

func _seek_wisp(to_p: Vector2, delta: float, player) -> void:
	# Hover with sine bob, maintain distance, shoot
	_wisp_t += delta
	var target_y := _wisp_y + sin(_wisp_t * 2.0) * 22.0
	velocity.y = _approach(velocity.y, (target_y - global_position.y) * 4.0, 800.0 * delta)
	var desired_x: float = global_position.x
	if absf(to_p.x) > 420.0:
		desired_x += facing * float(data.speed) * delta
	elif absf(to_p.x) < 240.0:
		desired_x -= facing * float(data.speed) * delta
	velocity.x = _approach(velocity.x, (desired_x - global_position.x) * 4.0, 800.0 * delta)
	global_position += velocity * delta
	if cd <= 0.0 and absf(to_p.x) < Content.WISP_RANGE and absf(to_p.y) < 200.0:
		_begin_windup()

func _seek_brute(to_p: Vector2, delta: float) -> void:
	# Slow heavy melee approach
	_apply_gravity(delta)
	if absf(to_p.x) > 60.0:
		_move_x(facing * float(data.speed), delta)
	else:
		_move_x(0.0, delta)
	move_and_slide()
	if absf(to_p.x) < 64.0 and absf(to_p.y) < 70.0 and cd <= 0.0:
		_begin_windup()

func _seek_bomber(to_p: Vector2, delta: float) -> void:
	# Rush toward player; arm and start fuse when close
	_apply_gravity(delta)
	var dist := absf(to_p.x)
	if dist > 48.0:
		_move_x(facing * float(data.speed) * 1.15, delta)
	else:
		_move_x(0.0, delta)
	move_and_slide()
	if dist < 56.0 and absf(to_p.y) < 80.0 and not _bomb_armed:
		_bomb_armed = true
		_begin_windup()

func _begin_windup() -> void:
	state = EState.WINDUP
	st_timer = float(data.windup)
	velocity.x *= 0.2
	if kind == Kind.BOMBER:
		_fuse_t = _fuse_total

func _step_windup(delta: float) -> void:
	_apply_gravity(delta)
	_move_x(0.0, delta)
	move_and_slide()
	st_timer -= delta
	if st_timer <= 0.0:
		if kind == Kind.WISP:
			_wisp_shoot()
			state = EState.RECOVER
			st_timer = float(data.recover)
			cd = float(data.cd)
		elif kind == Kind.BOMBER:
			# fuse ended through st_timer path (shouldn't happen, but explode)
			_do_explosion()
		else:
			state = EState.ATTACK
			st_timer = float(data.active) if data.has("active") else 0.18
			_atk_hit = false
			_atk_shape.position = Vector2(facing * (float(data.w) * 0.5 + 20.0), 0.0)
			_atk_shape.disabled = false
			_atk_area.monitoring = true
			_atk_area.set_meta("attack_active", true)

func _step_attack(delta: float) -> void:
	_apply_gravity(delta)
	_move_x(facing * float(data.speed) * 0.3, delta)
	move_and_slide()
	st_timer -= delta
	if not _atk_hit:
		for area in _atk_area.get_overlapping_areas():
			if not is_instance_valid(area): continue
			if area.get_meta("team") == "enemy": continue
			var tgt = area.get_meta("owner")
			if tgt != null and is_instance_valid(tgt) and tgt.has_method("take_damage"):
				tgt.take_damage(attack_damage(), Vector2(facing, -0.2), float(data.knock))
				_atk_hit = true
				break
	if st_timer <= 0.0:
		_atk_shape.disabled = true
		_atk_area.monitoring = false
		_atk_area.set_meta("attack_active", false)
		state = EState.RECOVER
		st_timer = float(data.recover)
		cd = float(data.cd)

func _wisp_shoot() -> void:
	var player = _get_player()
	var dir := Vector2(facing, 0.0)
	if player != null and is_instance_valid(player):
		var d: Vector2 = (player.global_position - global_position).normalized()
		dir = d
	var color: Color = Content.ELITE_COLOR if elite else data.color
	emit_signal("projectile_requested", "enemy", global_position + Vector2(facing * 18.0, 0.0), dir * Content.WISP_SHOT_SPEED, Content.WISP_SHOT_DAMAGE * damage_mul, 160.0, 0, Content.WISP_SHOT_LIFE, color)
	if elite:
		# Elite wisps fire a tight twin volley.
		var side := Vector2(-dir.y, dir.x) * 14.0
		emit_signal("projectile_requested", "enemy", global_position + side, dir.rotated(0.16) * Content.WISP_SHOT_SPEED, Content.WISP_SHOT_DAMAGE * damage_mul, 160.0, 0, Content.WISP_SHOT_LIFE, color)

func _do_explosion(reduced: bool = false) -> void:
	# Killing an armed bomber still pops it, but rewards the player with a much
	# smaller blast that is practical to dash away from.
	var blast := _blast_radius * (0.55 if reduced else 1.0)
	var blast_damage := attack_damage() * (0.4 if reduced else 1.0)
	var player = _get_player()
	if player != null and is_instance_valid(player):
		var d: float = global_position.distance_to(player.global_position)
		if d <= blast:
			var kdir: Vector2 = (player.global_position - global_position).normalized()
			if kdir == Vector2.ZERO: kdir = Vector2.UP
			player.take_damage(blast_damage, Vector2(kdir.x, -0.5), 380.0)
	emit_signal("exploded", global_position, blast, blast_damage)
	_die()

func _step_recover(delta: float) -> void:
	_apply_gravity(delta)
	_move_x(0.0, delta)
	move_and_slide()
	st_timer -= delta
	if st_timer <= 0.0:
		state = EState.SEEK

func _step_stagger(delta: float) -> void:
	_apply_gravity(delta)
	velocity.x = _approach(velocity.x, 0.0, 1800.0 * delta)
	move_and_slide()
	stagger_t -= delta
	if stagger_t <= 0.0:
		state = EState.SEEK

func take_damage(amount: float, from_dir: Vector2, kb: float) -> void:
	if dead: return
	# Brute shield: frontal hits absorbed by shield first
	if shield_active and kind == Kind.BRUTE:
		# Frontal = attacker is on the side the brute is facing
		var hit_from_front := signf(from_dir.x) == -facing
		if hit_from_front:
			_shield_flash = 0.12
			var absorbed := minf(amount, maxf(shield_hp, 0.0))
			shield_hp -= amount
			emit_signal("damaged", absorbed, global_position + Vector2(0.0, -float(data.h) * 0.5), true)
			if shield_hp <= 0.0:
				shield_active = false
				_shield_flash = 0.25
				# shield break stagger
				state = EState.STAGGER
				stagger_t = 0.3
				velocity = from_dir.normalized() * kb * 0.5
			else:
				# shield blocks the hit entirely; small pushback
				velocity = from_dir.normalized() * kb * 0.2
			return
		# backstab: bypass shield, full damage to HP
	var dealt := minf(amount, maxf(hp, 0.0))
	hp -= amount
	_hurt_flash = 0.1
	emit_signal("damaged", dealt, global_position + Vector2(0.0, -float(data.h) * 0.5), false)
	if hp <= 0.0:
		if kind == Kind.BOMBER and _bomb_armed:
			_do_explosion(true)
		else:
			_die()
		return
	state = EState.STAGGER
	# Elites shrug off hits faster so they keep pressure on.
	stagger_t = 0.12 if elite else 0.18
	velocity = from_dir.normalized() * kb * (0.6 if elite else 1.0)
	if kind == Kind.WISP:
		velocity.y = from_dir.y * kb * 0.5
	# An armed fuse deliberately keeps counting down through this stagger state.

func apply_burn(dps: float, duration: float) -> void:
	burn_dps = dps if burn_time <= 0.0 else maxf(burn_dps, dps)
	burn_time = maxf(burn_time, duration)
	queue_redraw()

func _tick_status(delta: float) -> void:
	if burn_time <= 0.0:
		burn_dps = 0.0
		return
	burn_time = maxf(0.0, burn_time - delta)
	hp -= burn_dps * delta
	_hurt_flash = maxf(_hurt_flash, 0.025)
	if burn_time <= 0.0:
		burn_dps = 0.0
	if hp <= 0.0:
		if kind == Kind.BOMBER and _bomb_armed:
			_do_explosion(true)
		else:
			_die()

func on_parried(knock_dir: Vector2) -> void:
	_atk_shape.set_deferred("disabled", true)
	_atk_area.monitoring = false
	_atk_area.set_meta("attack_active", false)
	state = EState.STAGGER
	stagger_t = 0.4
	velocity = knock_dir.normalized() * 260.0

## Pyre boon: a burning enemy detonates against its neighbours when it dies.
func _pyre_detonate() -> void:
	if pyre_damage <= 0.0 or burn_time <= 0.0:
		return
	var radius := Content.PYRE_RADIUS
	for area in get_tree().get_nodes_in_group("enemy_hurtbox"):
		if not is_instance_valid(area) or area == _hurtbox:
			continue
		var other = area.get_meta("owner")
		if other == null or not is_instance_valid(other) or other == self:
			continue
		if not other.has_method("take_damage") or bool(other.get("dead")):
			continue
		if other.global_position.distance_to(global_position) <= radius + 20.0:
			var dir: Vector2 = (other.global_position - global_position).normalized()
			if dir == Vector2.ZERO: dir = Vector2.UP
			other.take_damage(pyre_damage, Vector2(dir.x, -0.4), 300.0)
			if other.has_method("apply_burn"):
				other.apply_burn(Content.P_FLAME_BURN_DPS, Content.P_FLAME_BURN_TIME * 0.5)
	emit_signal("pyre_burst", global_position, radius)

func _die(award_reward: bool = true) -> void:
	if dead: return
	dead = true
	state = EState.DEAD
	_atk_shape.disabled = true
	_atk_area.monitoring = false
	_atk_area.set_meta("attack_active", false)
	_hurtbox.set_deferred("monitorable", false)
	if award_reward:
		_pyre_detonate()
	var score := int(data.score) * (Content.ELITE_SCORE_MUL if elite else 1)
	emit_signal("died", score if award_reward else 0)

func _apply_gravity(delta: float) -> void:
	if kind != Kind.WISP:
		velocity.y += Content.GRAVITY * delta

func _move_x(speed: float, delta: float) -> void:
	if _ledge_ray != null and speed != 0.0 and is_on_floor():
		_ledge_ray.position = Vector2(signf(speed) * (float(data.w) * 0.5 + 12.0), float(data.h) * 0.35)
		_ledge_ray.force_raycast_update()
		if not _ledge_ray.is_colliding():
			speed = 0.0
	velocity.x = _approach(velocity.x, speed, 2000.0 * delta)

func _approach(c: float, t: float, d: float) -> float:
	if c < t: return minf(c + d, t)
	return maxf(c - d, t)

func _get_player():
	var g = get_tree().get_first_node_in_group("player")
	return g

func _draw() -> void:
	# Value plan per creature: a dark base, the archetype hue for mid tones and a
	# few animated emissives. Geometry is authored facing right; set_pose mirrors.
	var flash := _hurt_flash > 0.0
	var hue: Color = data.color
	var mid: Color = Color.WHITE if flash else hue
	var base: Color = Color(0.92, 0.9, 0.94) if flash else hue.darkened(0.58)
	if elite and not flash:
		# Gilded elite: warm gold mids over a deep bronze base read instantly mid-swarm.
		mid = Content.ELITE_COLOR
		base = Color("6b4a1a")
		hue = Content.ELITE_COLOR
	var w: float = float(data.w)
	var h: float = float(data.h)
	var t := _anim_t if not Feedback.motion_reduced else 0.0
	# Pose: spawn pop, windup coil, attack lunge and stagger recoil, pivoting on the feet.
	var pop := 1.0
	if _spawn_anim > 0.0:
		pop = 1.0 - _spawn_anim / 0.4
	var tw := 0.0
	if state == EState.WINDUP:
		tw = clampf(1.0 - st_timer / maxf(0.01, float(data.windup)), 0.0, 1.0)
	var ta := 0.0
	if state == EState.ATTACK:
		ta = clampf(1.0 - st_timer / maxf(0.01, float(data.get("active", 0.18))), 0.0, 1.0)
	var squash := 1.0 - 0.2 * tw
	if state == EState.ATTACK:
		squash = 1.0 + 0.08 * (1.0 - ta)
	var lean := 0.0
	if state == EState.WINDUP:
		lean = -0.2 * tw
	elif state == EState.ATTACK:
		lean = 0.22 * (1.0 - ta)
	elif state == EState.STAGGER:
		lean = -0.28 * clampf(stagger_t / 0.18, 0.0, 1.0)
	var air := clampf(_air_time / 0.3, 0.0, 1.0)
	if kind == Kind.WISP:
		VFX.draw_contact_shadow(self, Vector2(0.0, w * 1.1), w * 0.9, 6.0, 1.0)
		VFX.set_pose(self, Vector2.ZERO, facing, Vector2(pop, pop), 0.0)
	else:
		VFX.draw_contact_shadow(self, Vector2(0.0, h * 0.5 + 1.0), w * 1.1 * (2.0 - squash), 8.0, air)
		VFX.set_pose(self, Vector2(0.0, h * 0.5), facing, Vector2(pop * (2.0 - squash), pop * squash), lean)
	if elite:
		var et := _anim_t if not Feedback.motion_reduced else 0.0
		var pulse := 0.10 + sin(et * 3.0) * 0.03
		var escale := Content.ELITE_SCALE if _elite_anim <= 0.0 else lerpf(1.0, Content.ELITE_SCALE, clampf(1.0 - _elite_anim / 0.25, 0.0, 1.0))
		VFX.set_pose(self, Vector2(0.0, h * 0.5), facing, Vector2(pop * (2.0 - squash) * escale, pop * squash * escale), lean)
		draw_circle(Vector2(0.0, -h * 0.1), w * 1.15, Color(Content.ELITE_COLOR, pulse))
		draw_circle(Vector2(0.0, -h * 0.1), w * 0.8, Color(Content.ELITE_COLOR, pulse * 0.8))
		# Gilded crest so elites read instantly, even mid-swarm.
		var crest_y := -h * 0.72 - 9.0 - h * 0.16 - 10.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(-9.0, crest_y), Vector2(-6.0, crest_y - 8.0), Vector2(-3.0, crest_y - 3.0),
			Vector2(0.0, crest_y - 11.0), Vector2(3.0, crest_y - 3.0), Vector2(6.0, crest_y - 8.0), Vector2(9.0, crest_y),
		]), Content.ELITE_COLOR)
		draw_circle(Vector2(0.0, crest_y - 11.0), 2.0, VFX.HOT)
	match kind:
		Kind.STALKER: _draw_stalker(w, h, base, mid, t, tw, ta, flash)
		Kind.HOPPER: _draw_hopper(w, h, base, mid, t, tw, flash, air)
		Kind.WISP: _draw_wisp(w, base, mid, t, tw, flash)
		Kind.BRUTE: _draw_brute(w, h, base, mid, t, tw, ta, flash)
		Kind.BOMBER: _draw_bomber(w, h, base, mid, t, flash)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# Bomber fuse telegraph: expanding ring toward the true blast radius.
	if kind == Kind.BOMBER and _bomb_armed and _fuse_t > 0.0:
		var ft: float = 1.0 - _fuse_t / _fuse_total
		var r := lerpf(12.0, _blast_radius, ft)
		draw_arc(Vector2.ZERO, r, 0, TAU, 28, Color(1.0, 0.3, 0.1, 0.25 + ft * 0.35), 2.0)
		if ft > 0.7:
			var pulse := 0.5 + sin(Time.get_ticks_msec() * 0.05) * 0.5
			draw_circle(Vector2.ZERO, w * 0.5, Color(1.0, 0.3, 0.2, pulse * 0.4))
	# Active melee reach: a ground arc under the true sweep, not a debug box.
	if state == EState.ATTACK:
		var reach := PackedVector2Array()
		for i in range(17):
			var u := float(i) / 16.0
			reach.append(Vector2(facing * (w * 0.5 + u * 40.0), -h * 0.5 + sin(u * PI) * 10.0 - 5.0 + u * (h + 10.0)))
		draw_polyline(reach, Color(1.0, 0.35, 0.1, 0.4), 3.0, true)
	if hp < hp_max:
		var hp_width := maxf(30.0, w)
		var hp_frac := clampf(hp / hp_max, 0.0, 1.0)
		draw_rect(Rect2(-hp_width * 0.5, -h * 0.72 - 9.0, hp_width, 4.0), Color(0.08, 0.06, 0.10, 0.8))
		draw_rect(Rect2(-hp_width * 0.5, -h * 0.72 - 9.0, hp_width * hp_frac, 4.0), mid)
	if burn_time > 0.0:
		for i in range(3):
			VFX.draw_flame(self, Vector2(-w * 0.28 + float(i) * w * 0.28, -h * 0.4), 14.0, 8.0, t, float(i) * 2.1)

func _draw_stalker(w: float, h: float, base: Color, mid: Color, t: float, tw: float, ta: float, flash: bool) -> void:
	var sway := sin(t * 2.6) * 2.0
	var sway2 := sin(t * 2.6 + 1.3) * 2.5
	# Two tattered cloak flaps trail behind on offset phases.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-4.0, -h * 0.32), Vector2(-w * 0.58 - sway, -h * 0.02), Vector2(-w * 0.66 - sway * 1.6, h * 0.44),
		Vector2(-w * 0.34, h * 0.3), Vector2(-8.0, h * 0.08),
	]), base if flash else base.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2.0, -h * 0.3), Vector2(-w * 0.42 - sway2, h * 0.12), Vector2(-w * 0.46 - sway2, h * 0.5),
		Vector2(-w * 0.12, h * 0.4),
	]), base)
	# Robe with a ragged hem and a dark sash.
	var robe := PackedVector2Array([
		Vector2(-w * 0.3, -h * 0.3), Vector2(w * 0.3, -h * 0.3), Vector2(w * 0.42, h * 0.2),
		Vector2(w * 0.36, h * 0.5), Vector2(w * 0.2, h * 0.36), Vector2(w * 0.04, h * 0.5),
		Vector2(-w * 0.14, h * 0.38), Vector2(-w * 0.3, h * 0.5), Vector2(-w * 0.42, h * 0.22),
	])
	VFX.draw_shaded_polygon(self, robe, mid, not flash)
	VFX.draw_rim(self, robe, 1.0)
	draw_line(Vector2(-w * 0.36, -h * 0.02), Vector2(w * 0.38, h * 0.02), base, 3.0)
	# Hood: dome plus a long peak trailing back; the face is a hollow with one ember eye.
	var hood := Vector2(3.0, -h * 0.44)
	draw_colored_polygon(PackedVector2Array([
		hood + Vector2(-w * 0.1, -w * 0.3), Vector2(-w * 0.62, -h * 0.98 + sway * 1.5), Vector2(-w * 0.34, -h * 0.5),
	]), mid if flash else mid.darkened(0.2))
	draw_circle(hood, w * 0.36, mid if flash else mid.darkened(0.12))
	VFX.draw_rim_circle(self, hood, w * 0.36, 1.0, 0.8)
	VFX.draw_ellipse(self, hood + Vector2(6.0, 1.0), w * 0.22, w * 0.27, Color(0.05, 0.03, 0.06))
	VFX.draw_ember_dot(self, hood + Vector2(9.0, -1.0), 2.0 + tw * 0.8, VFX.GOLD, 0.75 + 0.25 * sin(t * 9.0) + tw * 0.5)
	# Cleaver arm: rests low, rises behind the head on windup, sweeps forward on attack.
	var shoulder := Vector2(8.0, -h * 0.22)
	var ang := lerpf(0.85, -2.1, tw)
	if state == EState.ATTACK:
		ang = lerpf(-2.1, 0.45, minf(1.0, ta * 1.5))
	var hand := shoulder + Vector2(cos(ang), sin(ang)) * 17.0
	draw_line(shoulder, hand, base, 5.0, true)
	var blade := VFX.limb(PackedVector2Array([
		Vector2(-2.0, -3.0), Vector2(16.0, -9.0), Vector2(24.0, -4.0), Vector2(23.0, 5.0),
		Vector2(15.0, 8.0), Vector2(11.0, 4.0), Vector2(8.0, 8.0), Vector2(0.0, 5.0),
	]), hand, ang + 0.35)
	draw_colored_polygon(blade, Color("8f8496"))
	draw_polyline(PackedVector2Array([blade[1], blade[2], blade[3]]), Color("d9d2dc"), 1.5, true)
	draw_circle(hand, 3.0, base)

func _draw_hopper(w: float, h: float, base: Color, mid: Color, t: float, tw: float, flash: bool, air: float) -> void:
	# Grasshopper hind legs: the femur rises above the back and the shin drops to
	# the foot, coiling tighter on windup and stretching out while airborne.
	var hip := Vector2(-4.0, h * 0.1)
	for i in range(2):
		var off := Vector2(3.0 if i == 0 else -3.0, 0.0)
		var knee := hip + off + Vector2(-w * 0.55, -h * 0.42 - tw * h * 0.1).lerp(Vector2(-w * 0.5, h * 0.05), air)
		var foot := hip + off + Vector2(-w * 0.25, h * 0.4).lerp(Vector2(-w * 0.45, h * 0.55), air)
		var leg_col := base if i == 0 else base.darkened(0.25)
		draw_line(hip + off, knee, leg_col, 5.0, true)
		draw_circle(knee, 3.0, leg_col)
		draw_line(knee, foot, leg_col, 3.0, true)
		draw_line(foot, foot + Vector2(6.0, 0.0), leg_col, 2.5, true)
	draw_line(Vector2(6.0, h * 0.12), Vector2(10.0, h * 0.42), base, 3.0, true)
	# Bean body pitched forward with a pale underbelly.
	var body := Transform2D(0.3, Vector2(2.0, -h * 0.06)) * VFX.ellipse_points(Vector2.ZERO, w * 0.5, h * 0.3)
	VFX.draw_shaded_polygon(self, body, mid, not flash)
	VFX.draw_rim(self, body, 1.0)
	VFX.draw_ellipse(self, Vector2(5.0, h * 0.1), w * 0.3, h * 0.13, mid if flash else mid.lightened(0.25))
	# Snout and a dark dorsal stripe break the bean into a head and a back.
	draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.4, -h * 0.22), Vector2(w * 0.68, -h * 0.02), Vector2(w * 0.42, h * 0.06),
	]), mid if flash else mid.darkened(0.1))
	draw_line(Vector2(-w * 0.4, -h * 0.1), Vector2(w * 0.3, -h * 0.34), base, 3.0, true)
	# Swept-back antenna with an ember tip.
	var sway := sin(t * 3.2) * 3.0
	var tip := Vector2(-w * 0.72, -h * 0.5 + sway * 1.6)
	draw_polyline(PackedVector2Array([Vector2(2.0, -h * 0.3), Vector2(-w * 0.42, -h * 0.62 + sway), tip]), base, 2.5, true)
	VFX.draw_ember_dot(self, tip, 1.6, VFX.ORANGE, 0.7)
	# One big eye in a dark socket.
	VFX.draw_ellipse(self, Vector2(w * 0.28, -h * 0.16), 5.5, 4.5, Color(0.06, 0.03, 0.05))
	VFX.draw_ember_dot(self, Vector2(w * 0.3, -h * 0.17), 2.6 + tw, VFX.GOLD, 0.8 + tw * 0.6)

func _draw_wisp(w: float, base: Color, mid: Color, t: float, tw: float, flash: bool) -> void:
	var pulse := 0.9 + sin(t * 5.0) * 0.1
	# Three spectral tails trail below and behind on staggered phases.
	for i in range(3):
		var pts := PackedVector2Array()
		for k in range(5):
			var fk := float(k)
			pts.append(Vector2(sin(t * 4.0 + fk * 0.9 + float(i) * 2.1) * 4.0 - fk * 2.5 + (float(i) - 1.0) * 5.0, w * 0.3 + fk * 7.0))
		draw_polyline(pts, Color(mid, 0.4 - float(i) * 0.1), 3.0 - float(i) * 0.6, true)
	draw_circle(Vector2.ZERO, w * 0.9 * pulse, Color(mid, 0.1))
	var body := PackedVector2Array([
		Vector2(0.0, -w * 0.58), Vector2(w * 0.44, -w * 0.15), Vector2(w * 0.3, w * 0.25),
		Vector2(0.0, w * 0.5), Vector2(-w * 0.3, w * 0.25), Vector2(-w * 0.44, -w * 0.15),
	])
	VFX.draw_shaded_polygon(self, body, mid, not flash)
	# Dark cowl over the crown, a hollow face and one lantern eye.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -w * 0.58), Vector2(w * 0.44, -w * 0.15), Vector2(w * 0.2, -w * 0.05),
		Vector2(-w * 0.2, -w * 0.05), Vector2(-w * 0.44, -w * 0.15),
	]), Color(base, 0.85))
	VFX.draw_ellipse(self, Vector2(2.0, w * 0.02), w * 0.24, w * 0.2, Color(0.05, 0.03, 0.08))
	VFX.draw_ember_dot(self, Vector2(3.0, 0.0), 3.0 + tw * 2.0, VFX.GOLD, 0.85 + tw * 0.6)
	# Orbiting motes converge into the eye while a shot charges.
	for i in range(3):
		var a := t * 2.2 + float(i) * TAU / 3.0
		var r := lerpf(w * 0.78, w * 0.15, tw)
		draw_circle(Vector2(cos(a) * r, sin(a) * r * 0.55), 1.4 + tw, Color(VFX.HOT if tw > 0.0 else mid.lightened(0.4), 0.8))

func _draw_brute(w: float, h: float, base: Color, mid: Color, t: float, tw: float, ta: float, flash: bool) -> void:
	var breath := sin(t * 1.8) * 0.8
	# Back smokestack venting an ember.
	draw_rect(Rect2(-w * 0.34, -h * 0.66 - breath, w * 0.14, h * 0.28), base if flash else base.darkened(0.2))
	draw_rect(Rect2(-w * 0.37, -h * 0.68 - breath, w * 0.2, 4.0), base)
	var rise := fmod(t * 26.0, 22.0)
	VFX.draw_ember_dot(self, Vector2(-w * 0.27 + sin(t * 7.0) * 2.0, -h * 0.68 - rise), 1.4, VFX.ORANGE, 1.0 - rise / 22.0)
	# Legs: iron columns with knee plates.
	for side: float in [-1.0, 1.0]:
		draw_rect(Rect2(side * w * 0.22 - w * 0.11, h * 0.12, w * 0.22, h * 0.38), base)
		draw_rect(Rect2(side * w * 0.22 - w * 0.08, h * 0.22, w * 0.16, 5.0), mid if flash else mid.darkened(0.2))
	# Slab torso with plate seams.
	var torso := PackedVector2Array([
		Vector2(-w * 0.5, -h * 0.2), Vector2(-w * 0.36, -h * 0.44 - breath), Vector2(w * 0.36, -h * 0.44 - breath),
		Vector2(w * 0.5, -h * 0.2), Vector2(w * 0.44, h * 0.22), Vector2(-w * 0.44, h * 0.22),
	])
	VFX.draw_shaded_polygon(self, torso, mid, not flash)
	VFX.draw_rim(self, torso, 1.0, 1.1)
	draw_line(Vector2(-w * 0.46, -h * 0.05), Vector2(w * 0.46, -h * 0.05), base, 2.0)
	draw_line(Vector2(0.0, -h * 0.44 - breath), Vector2(0.0, h * 0.22), base, 2.0)
	for side: float in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(side * w * 0.56, -h * 0.28 - breath), Vector2(side * w * 0.3, -h * 0.5 - breath),
			Vector2(side * w * 0.18, -h * 0.34 - breath), Vector2(side * w * 0.5, -h * 0.12 - breath),
		]), mid if flash else mid.darkened(0.18))
	# Sunk visor head with two coal eyes.
	draw_rect(Rect2(-w * 0.16, -h * 0.58 - breath, w * 0.34, h * 0.18), base)
	draw_rect(Rect2(-w * 0.12, -h * 0.51 - breath, w * 0.28, 4.0), Color(0.04, 0.03, 0.04))
	for ex: float in [0.0, 6.0]:
		VFX.draw_ember_dot(self, Vector2(-w * 0.02 + ex, -h * 0.49 - breath), 1.6 + tw * 0.6, Color("ff5a3d"), 0.9 + tw * 0.5)
	# Ember cracks open once the shield is gone.
	if not shield_active:
		var glow := 0.6 + sin(t * 6.0) * 0.3
		draw_polyline(PackedVector2Array([Vector2(w * 0.1, -h * 0.3), Vector2(w * 0.2, -h * 0.12), Vector2(w * 0.14, h * 0.02), Vector2(w * 0.26, h * 0.14)]), Color(VFX.EMBER, glow), 1.5, true)
		draw_polyline(PackedVector2Array([Vector2(-w * 0.3, -h * 0.1), Vector2(-w * 0.2, h * 0.04), Vector2(-w * 0.28, h * 0.16)]), Color(VFX.EMBER, glow * 0.8), 1.5, true)
	# Club fist: rears back on windup, drives forward on attack.
	var shoulder := Vector2(w * 0.36, -h * 0.3 - breath)
	var rest := shoulder + Vector2(w * 0.16, h * 0.34)
	var raised := shoulder + Vector2(-w * 0.15, -h * 0.4)
	var hand := rest
	if state == EState.WINDUP:
		hand = rest.lerp(raised, tw)
	elif state == EState.ATTACK:
		hand = raised.lerp(shoulder + Vector2(w * 0.5, h * 0.12), minf(1.0, ta * 1.5))
	var elbow := (shoulder + hand) * 0.5 + Vector2(6.0, -4.0)
	draw_line(shoulder, elbow, base, 8.0, true)
	draw_line(elbow, hand, base, 7.0, true)
	draw_circle(hand, 8.0, base if flash else base.darkened(0.15))
	draw_arc(hand, 8.0, -2.4, 0.4, 8, mid if flash else mid.darkened(0.1), 2.5)
	# Riveted iron tower shield on the facing side.
	if shield_active:
		var scol := Color("6e6a7c") if _shield_flash <= 0.0 else Color.WHITE
		var face := Color("9a94aa") if _shield_flash <= 0.0 else Color.WHITE
		var sx := w * 0.5
		draw_rect(Rect2(sx - 5.0, -h * 0.4, 10.0, h * 0.76), scol)
		draw_circle(Vector2(sx, -h * 0.4), 5.0, scol)
		draw_rect(Rect2(sx - 1.0, -h * 0.36, 3.0, h * 0.68), face)
		for k in range(3):
			draw_circle(Vector2(sx + 2.0, -h * 0.3 + float(k) * h * 0.26), 1.4, Color("d8d2e0"))

func _draw_bomber(w: float, h: float, base: Color, mid: Color, t: float, flash: bool) -> void:
	var run := clampf(absf(velocity.x) / float(data.speed), 0.0, 1.0)
	var gait := sin(t * 18.0) * 0.6 * run
	var fuse_t := 0.0
	if _bomb_armed:
		fuse_t = clampf(1.0 - _fuse_t / _fuse_total, 0.0, 1.0)
	var jitter := Vector2(sin(t * 40.0), cos(t * 33.0)) * fuse_t * 1.5
	# Stubby scissoring legs.
	for side: float in [-1.0, 1.0]:
		var hip := Vector2(side * 5.0, h * 0.28)
		var foot := hip + Vector2(sin(gait) * side * 7.0, h * 0.22)
		draw_line(hip, foot, base, 4.0, true)
		draw_line(foot, foot + Vector2(4.0, 0.0), base, 3.0, true)
	# Iron shell with a riveted seam band and a crack that glows once armed.
	var center := Vector2(0.0, -2.0) + jitter
	draw_circle(center, w * 0.48, base)
	VFX.draw_shaded_polygon(self, VFX.ellipse_points(center, w * 0.42, w * 0.42), mid, not flash)
	VFX.draw_rim_circle(self, center, w * 0.46, 1.0, 0.9)
	VFX.draw_ellipse_ring(self, center, w * 0.42, w * 0.14, base, 2.5)
	for a: float in [0.3, 1.0, 2.1, 2.8]:
		draw_circle(center + Vector2(cos(a) * w * 0.42, sin(a) * w * 0.14), 1.3, mid if flash else mid.lightened(0.35))
	var crack_a := 0.3 + fuse_t * 0.7 + sin(t * 20.0) * fuse_t * 0.2
	if fuse_t > 0.0:
		draw_circle(center + Vector2(w * 0.18, -w * 0.05), w * 0.3, Color(VFX.ORANGE, 0.18 * fuse_t))
	draw_polyline(PackedVector2Array([
		center + Vector2(w * 0.1, -w * 0.3), center + Vector2(w * 0.22, -w * 0.12),
		center + Vector2(w * 0.14, w * 0.04), center + Vector2(w * 0.3, w * 0.18),
	]), Color(VFX.EMBER, crack_a), 1.5 + fuse_t, true)
	# Manic eye.
	draw_circle(center + Vector2(w * 0.2, -w * 0.1), 4.2, Color.WHITE if flash else Color("f2ead8"))
	draw_circle(center + Vector2(w * 0.2 + 1.2, -w * 0.1), 2.2 - fuse_t * 0.8, Color(0.06, 0.03, 0.04))
	# Fuse rope; the spark burns down toward the shell while armed.
	var fuse := PackedVector2Array([
		center + Vector2(0.0, -w * 0.44), center + Vector2(-3.0, -w * 0.62),
		center + Vector2(-8.0, -w * 0.74), center + Vector2(-14.0, -w * 0.76),
	])
	draw_polyline(fuse, base if flash else base.darkened(0.2), 2.5, true)
	var u := (1.0 - fuse_t) * 3.0
	var seg := mini(int(u), 2)
	var spark := fuse[seg].lerp(fuse[seg + 1], u - float(seg))
	VFX.draw_ember_dot(self, spark, 2.0 + fuse_t * 1.5, VFX.GOLD, 0.8 + sin(t * 30.0) * 0.2 + fuse_t * 0.4)
	if _bomb_armed:
		for k in range(3):
			draw_circle(spark + Vector2(sin(t * 25.0 + float(k) * 2.0) * 6.0, -3.0 - fmod(t * 40.0 + float(k) * 7.0, 10.0)), 1.0, Color(VFX.HOT, 0.8))
