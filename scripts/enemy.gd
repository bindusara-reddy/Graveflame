class_name Enemy
extends CharacterBody2D
## Compact state-machine enemy: STALKER (melee), HOPPER (leaping), WISP (ranged),
## BRUTE (shielded heavy), BOMBER (exploding kamikaze). Any of them may spawn as
## an elite: larger, tougher, gilded, and worth more cells.

const VFX := preload("res://scripts/vfx.gd")
const CreatureSprite := preload("res://scripts/creature_sprite.gd")

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
var _sprite: Sprite2D
var _shadow: Node2D

## `mods` may carry hp_mul, dmg_mul (difficulty curve) and elite (bool).
func setup(p_kind: int, p_pos: Vector2, mods: Dictionary = {}) -> void:
	kind = p_kind
	data = Content.ENEMY[p_kind]
	elite = bool(mods.get("elite", false))
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
	_build_body()
	state = EState.SEEK
	_spawn_anim = 0.4

## Visual only: a shadow pass and the sprite-sheet body, both drawn behind this
## node so _draw() can paint gameplay overlays (shield, telegraphs, HP) on top.
func _build_body() -> void:
	_shadow = Node2D.new()
	_shadow.name = "Shadow"
	_shadow.show_behind_parent = true
	_shadow.draw.connect(_draw_under)
	add_child(_shadow)
	_sprite = CreatureSprite.new()
	_sprite.setup(_creature_name(), _foot_y())
	_sprite.under = _shadow
	if elite:
		_sprite.size_mul = Content.ELITE_SCALE
		_sprite.elite_tint = Color(1.0, 0.9, 0.7)
	add_child(_sprite)

func _creature_name() -> String:
	return ["stalker", "hopper", "wisp", "brute", "bomber"][clampi(kind, 0, 4)]

## Where the sheet's feet row sits: the old vector art stood on h * 0.5.
func _foot_y() -> float:
	if kind == Kind.WISP:
		return float(data.w) * 0.6
	return float(data.h) * 0.5

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

## Under-pass drawn beneath the sprite body: the contact shadow (and elite aura).
func _draw_under() -> void:
	var w: float = float(data.w)
	var h: float = float(data.h)
	if elite:
		var t := _anim_t if not Feedback.motion_reduced else 0.0
		var pulse := 0.10 + sin(t * 3.0) * 0.03
		_shadow.draw_circle(Vector2(0.0, -h * 0.1), w * 1.15, Color(Content.ELITE_COLOR, pulse))
		_shadow.draw_circle(Vector2(0.0, -h * 0.1), w * 0.8, Color(Content.ELITE_COLOR, pulse * 0.8))
	if kind == Kind.WISP:
		VFX.draw_contact_shadow(_shadow, Vector2(0.0, w * 1.1), w * 0.9, 6.0, 1.0)
	else:
		VFX.draw_contact_shadow(_shadow, Vector2(0.0, h * 0.5 + 1.0), w * 1.1 * (1.2 if elite else 1.0), 8.0, clampf(_air_time / 0.3, 0.0, 1.0))

func _draw() -> void:
	# The sprite body draws behind this node; this pass is the gameplay-critical
	# overlays: brute shield state, bomber blast ring, windup telegraph, active
	# attack area, HP bar and burn flames.
	var w: float = float(data.w)
	var h: float = float(data.h)
	var mid: Color = Color.WHITE if _hurt_flash > 0.0 else data.color
	var t := _anim_t if not Feedback.motion_reduced else 0.0
	var top_y := -h * 0.72 - 9.0
	if elite:
		top_y -= h * 0.16
		# Gilded crest so elites read instantly, even mid-swarm.
		var crest_y := top_y - 10.0
		var gold := Content.ELITE_COLOR
		draw_colored_polygon(PackedVector2Array([
			Vector2(-9.0, crest_y), Vector2(-6.0, crest_y - 8.0), Vector2(-3.0, crest_y - 3.0),
			Vector2(0.0, crest_y - 11.0), Vector2(3.0, crest_y - 3.0), Vector2(6.0, crest_y - 8.0), Vector2(9.0, crest_y),
		]), gold)
		draw_circle(Vector2(0.0, crest_y - 11.0), 2.0, VFX.HOT)
	if shield_active and kind == Kind.BRUTE:
		var scol := Color("6e6a7c") if _shield_flash <= 0.0 else Color.WHITE
		var face := Color("9a94aa") if _shield_flash <= 0.0 else Color.WHITE
		var sx: float = facing * w * 0.5
		draw_rect(Rect2(sx - 5.0, -h * 0.4, 10.0, h * 0.76), scol)
		draw_circle(Vector2(sx, -h * 0.4), 5.0, scol)
		draw_rect(Rect2(sx + facing * 1.0 - 1.5, -h * 0.36, 3.0, h * 0.68), face)
		for k in range(3):
			draw_circle(Vector2(sx + facing * 2.0, -h * 0.3 + float(k) * h * 0.26), 1.4, Color("d8d2e0"))
	if kind == Kind.BOMBER and _bomb_armed and _fuse_t > 0.0:
		var ft: float = 1.0 - _fuse_t / _fuse_total
		var r := lerpf(12.0, _blast_radius, ft)
		draw_arc(Vector2.ZERO, r, 0, TAU, 28, Color(1.0, 0.3, 0.1, 0.25 + ft * 0.35), 2.0)
		if ft > 0.7:
			var pulse := 0.5 + sin(Time.get_ticks_msec() * 0.05) * 0.5
			draw_circle(Vector2.ZERO, w * 0.5, Color(1.0, 0.3, 0.2, pulse * 0.4))
	if state == EState.WINDUP and kind != Kind.BOMBER:
		var tw: float = clampf(1.0 - st_timer / maxf(0.01, float(data.windup)), 0.0, 1.0)
		if kind == Kind.WISP:
			# Cast ring converging on the caster.
			draw_arc(Vector2.ZERO, lerpf(w * 1.2, w * 0.5, tw), 0.0, TAU, 28, Color(1.0, 0.35, 0.2, 0.45 + tw * 0.4), 1.5 + tw * 2.0)
		else:
			draw_arc(Vector2(facing * w * 0.5, 0.0), 14.0, 0.0, TAU * tw, 16, Color("ff3d3d"), 3.0)
	# Active melee area: the exact rectangle the hitbox covers.
	if state == EState.ATTACK:
		var off: float = 0.0 if facing >= 0.0 else 40.0
		draw_rect(Rect2(facing * (w * 0.5) - off, -h * 0.5 - 5, 40, h + 10), Color(1.0, 0.35, 0.1, 0.26))
	if hp < hp_max:
		var hp_width := maxf(30.0, w) * (1.25 if elite else 1.0)
		var hp_frac := clampf(hp / hp_max, 0.0, 1.0)
		draw_rect(Rect2(-hp_width * 0.5, top_y, hp_width, 4.0), Color(0.08, 0.06, 0.10, 0.8))
		draw_rect(Rect2(-hp_width * 0.5, top_y, hp_width * hp_frac, 4.0), Content.ELITE_COLOR if elite and _hurt_flash <= 0.0 else mid)
	if burn_time > 0.0:
		for i in range(3):
			VFX.draw_flame(self, Vector2(-w * 0.28 + float(i) * w * 0.28, -h * 0.4), 14.0, 8.0, t, float(i) * 2.1)
