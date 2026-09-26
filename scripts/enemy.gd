class_name Enemy
extends CharacterBody2D
## Compact state-machine enemy: STALKER (melee), HOPPER (leaping), WISP (ranged),
## BRUTE (shielded heavy), BOMBER (exploding kamikaze), CROW (diving flyer),
## SEXTON (distant bell-ringer whose toll rolls along the floor). Any of them
## may spawn as an elite: larger, tougher, gilded, and worth more cells.

const VFX := preload("res://scripts/vfx.gd")
const GroundFire := preload("res://scripts/ground_fire.gd")

signal died(score: int)
signal damaged(amount: float, pos: Vector2, blocked: bool)
signal projectile_requested(team: String, pos: Vector2, vel: Vector2, dmg: float, kb: float, pierce: int, life: float, color: Color)
signal exploded(pos: Vector2, radius: float, damage: float)
signal pyre_burst(pos: Vector2, radius: float)
## Windup announcement. The game voices this so an incoming hit is never a surprise.
signal telegraphed(kind: String, pos: Vector2, elite: bool)
## A beat the game names over the creature and/or voices: a broken guard, a
## ring-out. Either part may be empty.
signal announced(text: String, cue: String, pos: Vector2)
## A twinned elite at half health: the room sets a plain copy of it at `pos`.
signal twin_requested(kind: int, pos: Vector2)
## A shockwave running along the floor from pos: the Warden's slam ridge
## (style "wave") or a sexton's toll ("toll"). The game spawns it as a
## floor-hugging Projectile, jumpable and parryable like any shot.
signal wave_requested(pos: Vector2, vel: Vector2, dmg: float, life: float, style: String, color: Color)

enum Kind { STALKER, HOPPER, WISP, BRUTE, BOMBER, CROW, SEXTON }
enum EState { SPAWN, SEEK, WINDUP, ATTACK, RECOVER, STAGGER, DEAD }

## Telegraph id for an archetype's windup: the Kind's own name, lower-cased
## ("stalker", "crow"). The game resolves it to a sound, so enemy code never
## names an audio cue directly; anticipation_contract checks every Kind has one.
static func telegraph_id(p_kind: int) -> String:
	return str(Kind.keys()[p_kind]).to_lower()

## Once this share of a windup has passed, a poised creature is committed: a
## blow still lands but no longer calls the strike off.
const COMMIT_AT := 0.4
## Seconds without a blow before a creature's poise is whole again.
const POISE_REGEN := 1.0
## A worn-through guard: how long the creature reels, and how much harder it is
## hit until it has its feet back.
const BREAK_STAGGER := 0.6
const BREAK_VULNERABLE := 1.0
const BREAK_DAMAGE_MUL := 1.25
## Seconds a fresh spawn waits before its first windup, so no wave strikes the
## moment it lands.
const SPAWN_GRACE := 0.7
## A fall onto the spikes is the knight's kill if they struck it this recently.
const RING_OUT_CREDIT := 2.0
## How far above the knight's head a wisp keeps its line.
const WISP_ALTITUDE := 150.0
## Flyers ignore the arena rails, so they are held inside these walls instead.
const FLYER_LEFT := Content.ROOM_LEFT + 60.0
const FLYER_RIGHT := Content.ROOM_RIGHT - 60.0
## A hopper's forward hop lands about this far ahead; a leap up reaches this high.
const HOP_REACH := 150.0
const HOP_UP_REACH := 230.0
## The deepest drop a walker will take to floor below it.
const SAFE_DROP := 420.0
## Kindled oath: seconds between the embers it sheds while walking, and each
## ember's bite. Warded oath: blows its runes swallow whole.
const KINDLED_EVERY := 0.5
const KINDLED_BITE := 6.0
const WARD_RUNES := 2
## A sexton's toll rolls this high above its floor: under a jump, into a shin.
const TOLL_LIFT := 14.0
## Seconds after the toll that the sexton's bell still hangs low, swung through.
const TOLL_FOLLOW := 0.3

## Pyre boon damage, mirrored from the player's build by the game so a burning
## enemy can detonate against its neighbours without holding a player reference.
static var pyre_damage := 0.0
## Vows sworn for the current descent (id -> true), set by the game at run start.
static var vows: Dictionary = {}

## Damage multiplier from the Vow of Embers, for attacks that bypass `damage_mul`.
static func vow_damage() -> float:
	return 1.35 if vows.has("v_embers") else 1.0

## Live foes whose origin lies within `radius` of `center`. The knight's nova
## and Cinder Skin and a burning foe's pyre all strike this same set.
static func living_near(tree: SceneTree, center: Vector2, radius: float) -> Array:
	var found := []
	for area in tree.get_nodes_in_group("enemy_hurtbox"):
		var foe = area.get_meta("owner")
		if not is_instance_valid(foe) or foe.dead:
			continue
		if foe.global_position.distance_to(center) <= radius:
			found.append(foe)
	return found

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
## Direction the last blow travelled; the paper-cut death splits along it.
var _last_hit_dir := Vector2.RIGHT
## Set when the bomber goes off: a blast leaves nothing to cut in half.
var exploded_out := false
## A drawing-only copy (no collision, no AI) used by the paper-cut death.
var ghost := false
## True when the last blow was absorbed (the brute's shield) instead of dealt,
## so the knight's blade can ring off the guard.
var last_hit_blocked := false
## Poise left before the guard breaks; see _react_to_blow.
var _poise := 0.0
var _poise_regen_t := 0.0
var _poise_flash := 0.0  # visual only: a committed blow rings gold
## Seconds left of a broken guard's opening (BREAK_DAMAGE_MUL applies).
var _vulnerable_t := 0.0
var _spawn_grace := 0.0
## An elite's oath (Content.ELITE_OATHS), or "".
var oath := ""
var _wards := 0
var _twinned := false
var _ember_t := 0.0
## Seconds since the knight's side last struck this creature; drives ring-out credit.
var _since_struck := INF

## A frozen, collision-free copy of this creature's drawing, recoiling from the blow.
func echo() -> Node2D:
	var g: Enemy = Enemy.new()
	g.ghost = true
	g.kind = kind
	g.data = data
	g.elite = elite
	g.oath = oath
	g.facing = facing
	g.state = EState.STAGGER
	g.stagger_t = 0.18
	g._anim_t = _anim_t
	g._air_time = _air_time
	g.hp = 1.0
	g.hp_max = 1.0
	g.shield_active = shield_active
	g._hurt_flash = 0.1
	return g

## `mods` may carry hp_mul, dmg_mul (difficulty curve), elite (bool) and an
## elite's oath.
func setup(p_kind: int, p_pos: Vector2, mods: Dictionary = {}) -> void:
	kind = p_kind
	data = Content.ENEMY[p_kind]
	if vows.has("v_haste"):
		# Vow of Haste: quicker feet, shorter tells, less rest between strikes.
		data = data.duplicate()
		data.speed = float(data.speed) * 1.15
		data.windup = float(data.windup) * 0.85
		data.cd = float(data.cd) * 0.9
		if data.has("fuse"):
			data.fuse = float(data.fuse) * 0.85
	elite = bool(mods.get("elite", false))
	oath = str(mods.get("oath", "")) if elite else ""
	_wards = WARD_RUNES if oath == "warded" else 0
	_poise = poise_max()
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

## Blows a committed windup shrugs off before the guard breaks. Fodder has
## none and always flinches; elites stand firmer than their kind.
func poise_max() -> float:
	return float(data.get("poise", 0.0)) + (Content.ELITE_POISE if elite else 0.0)

## Contact damage for this instance, after difficulty and elite multipliers.
func attack_damage() -> float:
	return float(data.damage) * damage_mul

func _ready() -> void:
	if data.is_empty():
		data = Content.ENEMY[Kind.STALKER]
		# A ghost keeps the token health its echo gave it.
		if not ghost:
			hp_max = float(data.hp)
			hp = hp_max
	if ghost:
		set_physics_process(false)
		collision_layer = 0
		collision_mask = 0
		return
	_build_bodies(Vector2(float(data.w), float(data.h)), Vector2(40.0, 10.0))
	if _is_flyer():
		_wisp_y = global_position.y
		collision_mask = 0  # flyers ignore the world
	else:
		_ledge_ray = RayCast2D.new()
		_ledge_ray.collision_mask = Content.L_WORLD
		_ledge_ray.exclude_parent = true
		_ledge_ray.enabled = true
		_ledge_ray.target_position = Vector2(0.0, 42.0)
		add_child(_ledge_ray)
	state = EState.SEEK
	_spawn_anim = 0.4
	_spawn_grace = SPAWN_GRACE

## Body shape, hurtbox and melee box shared by every creature, the Warden
## included; `reach` is how far the melee box outgrows the body. Each area is
## fully configured before it enters the tree, so none is ever live half-built.
func _build_bodies(size: Vector2, reach: Vector2) -> void:
	collision_layer = Content.L_ENEMY_BODY
	collision_mask = Content.L_WORLD
	add_child(Content.rect_shape(size))
	_hurtbox = _tagged_area(Content.L_ENEMY_HURT, 0, Content.rect_shape(size))
	_hurtbox.add_to_group("enemy_hurtbox")
	add_child(_hurtbox)
	_atk_shape = Content.rect_shape(size + reach)
	_atk_shape.disabled = true
	_atk_area = _tagged_area(Content.L_ENEMY_ATK, Content.L_PLAYER_HURT, _atk_shape)
	_atk_area.monitoring = false
	_atk_area.set_meta("attack_kind", "melee")
	_atk_area.set_meta("attack_active", false)
	add_child(_atk_area)

## An unparented Area2D holding `shape`, tagged with the team and owner metas
## the knight's blade and parry read to tell who they touched.
func _tagged_area(layer: int, mask: int, shape: CollisionShape2D) -> Area2D:
	var area := Area2D.new()
	area.collision_layer = layer
	area.collision_mask = mask
	area.add_child(shape)
	area.set_meta("team", "enemy")
	area.set_meta("owner", self)
	area.set_meta("owner_id", _owner_id)
	return area

## Open the melee box `front_offset` ahead of the body for a fresh swing.
func _arm(front_offset: float) -> void:
	_atk_hit = false
	_atk_shape.position = Vector2(facing * front_offset, 0.0)
	_atk_shape.disabled = false
	_atk_area.monitoring = true
	_atk_area.set_meta("attack_active", true)

## Close the melee box. The shape is disabled deferred so this is safe inside a
## physics callback; attack_active drops at once, which the knight's parry reads.
func _disarm() -> void:
	_atk_shape.set_deferred("disabled", true)
	_atk_area.monitoring = false
	_atk_area.set_meta("attack_active", false)

## Land this swing on the first damageable non-enemy owner the melee box
## overlaps. A swing hits at most once.
func _strike_overlaps(dmg: float, dir: Vector2, knock: float) -> void:
	if _atk_hit:
		return
	for area in _atk_area.get_overlapping_areas():
		if not is_instance_valid(area) or area.get_meta("team") == "enemy":
			continue
		var target = area.get_meta("owner")
		if target != null and is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(dmg, dir, knock)
			_atk_hit = true
			return

## Every attack ends the same way: melee box closed, a rest, then the cooldown.
func _enter_recover() -> void:
	_disarm()
	state = EState.RECOVER
	st_timer = float(data.recover)
	cd = float(data.cd)

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
	_spawn_grace = maxf(0.0, _spawn_grace - delta)
	_elite_anim = maxf(0.0, _elite_anim - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	_shield_flash = maxf(0.0, _shield_flash - delta)
	_poise_flash = maxf(0.0, _poise_flash - delta)
	_vulnerable_t = maxf(0.0, _vulnerable_t - delta)
	_since_struck += delta
	if _poise_regen_t > 0.0:
		_poise_regen_t -= delta
		if _poise_regen_t <= 0.0:
			_poise = poise_max()
	cd = maxf(0.0, cd - delta)
	if global_position.y > Content.FLOOR_Y + 220.0:
		_die(false)
		return
	if kind == Kind.BRUTE and _air_time > 0.2 and is_on_floor():
		# A brute dropping from a ledge lands like a falling bell: dust and a jolt.
		exploded.emit(global_position + Vector2(0.0, float(data.h) * 0.5), 70.0, 0.0)
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
	if _is_flyer():
		global_position.x = clampf(global_position.x, FLYER_LEFT, FLYER_RIGHT)
	if oath == "kindled":
		_shed_embers(delta)

## A kindled elite sheds a patch of burning ground every KINDLED_EVERY seconds
## it walks, so its path stays dangerous behind it.
func _shed_embers(delta: float) -> void:
	_ember_t -= delta
	if _ember_t > 0.0 or not is_on_floor() or absf(velocity.x) < 30.0:
		return
	_ember_t = KINDLED_EVERY
	var fire := GroundFire.new()
	fire.bite = KINDLED_BITE * damage_mul
	fire.position = position + Vector2(0.0, float(data.h) * 0.5)
	get_parent().add_child(fire)

func _step_seek(delta: float) -> void:
	var player = _get_player()
	if player == null:
		_walk(0.0, delta)
		return
	var to_p: Vector2 = player.global_position - global_position
	facing = signf(to_p.x) if absf(to_p.x) > 4.0 else facing
	match kind:
		Kind.STALKER: _seek_stalker(to_p, delta)
		Kind.HOPPER: _seek_hopper(to_p, delta)
		Kind.WISP: _seek_wisp(to_p, delta)
		Kind.BRUTE: _seek_brute(to_p, delta)
		Kind.BOMBER: _seek_bomber(to_p, delta)
		Kind.CROW: _seek_crow(to_p, delta, player)
		Kind.SEXTON: _seek_sexton(to_p, delta)

## One grounded step at `speed`: gravity, the ledge-aware horizontal move, slide.
func _walk(speed: float, delta: float) -> void:
	_apply_gravity(delta)
	_move_x(speed, delta)
	move_and_slide()

## Walk at the knight until within stop_x of them, then hold.
func _close_in(dx: float, stop_x: float, delta: float, speed_mul := 1.0) -> void:
	var speed := facing * float(data.speed) * speed_mul if absf(dx) > stop_x else 0.0
	_walk(speed, delta)

## Off cooldown and past the spawn grace: free to start a windup.
func _ready_to_strike() -> bool:
	return cd <= 0.0 and _spawn_grace <= 0.0

func _seek_stalker(to_p: Vector2, delta: float) -> void:
	_close_in(to_p.x, 44.0, delta)
	if absf(to_p.x) < 50.0 and absf(to_p.y) < 60.0 and _ready_to_strike():
		_begin_windup()

## Hop at the knight across open floor, or leap up onto the ledge they stand
## on. It never hops where no floor waits to catch it.
func _seek_hopper(to_p: Vector2, delta: float) -> void:
	_close_in(to_p.x, 70.0, delta)
	if is_on_floor() and cd <= 0.0:
		var hop_up := to_p.y < -80.0 and to_p.y > -HOP_UP_REACH and absf(to_p.x) > 80.0 and absf(to_p.x) < 260.0
		if hop_up:
			_leap_onto(to_p)
		elif absf(to_p.x) < 360.0 and absf(to_p.x) > 50.0 and _floor_below(facing * HOP_REACH):
			velocity.y = -560.0
			velocity.x = facing * float(data.speed) * 1.4
	if absf(to_p.x) < 52.0 and absf(to_p.y) < 60.0 and _ready_to_strike():
		_begin_windup()

## An arc that peaks a little above the knight's ledge and comes down where
## they stand.
func _leap_onto(to_p: Vector2) -> void:
	var rise := -to_p.y
	var up := sqrt(2.0 * Content.GRAVITY * (rise + 40.0))
	var flight := (up + sqrt(maxf(up * up - 2.0 * Content.GRAVITY * rise, 0.0))) / Content.GRAVITY
	velocity = Vector2(to_p.x / flight, -up)

## True when solid floor lies under the point `dx` ahead, within a fall this
## creature would survive. A spike pit has none: its floor is the hazard.
func _floor_below(dx: float) -> bool:
	var from := global_position + Vector2(dx, 0.0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, SAFE_DROP), Content.L_WORLD, [get_rid()])
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()

## A skirmisher: it rides a line above the knight's head, closes when far,
## backs off when crowded, and looses a bolt whenever it has a clear angle.
func _seek_wisp(to_p: Vector2, delta: float) -> void:
	_wisp_t += delta
	var knight_y := global_position.y + to_p.y
	_wisp_y = move_toward(_wisp_y, clampf(knight_y - WISP_ALTITUDE, 150.0, Content.FLOOR_Y - WISP_ALTITUDE), 90.0 * delta)
	var target_y := _wisp_y + sin(_wisp_t * 2.0) * 22.0
	velocity.y = move_toward(velocity.y, (target_y - global_position.y) * 4.0, 800.0 * delta)
	var want_vx := 0.0
	if absf(to_p.x) > 420.0:
		want_vx = facing * float(data.speed)
	elif absf(to_p.x) < 240.0:
		want_vx = -facing * float(data.speed)
	velocity.x = move_toward(velocity.x, want_vx, 600.0 * delta)
	global_position += velocity * delta
	if _ready_to_strike() and absf(to_p.x) < Content.WISP_RANGE and absf(to_p.y) < 260.0:
		_begin_windup()

## Circle above the knight, drifting from side to side; commit to a dive when
## they are below and within reach.
func _seek_crow(to_p: Vector2, delta: float, player) -> void:
	_wisp_t += delta
	var target: Vector2 = player.global_position + Vector2(sin(_wisp_t * 0.9 + float(_owner_id % 7)) * 150.0, -Content.CROW_HOVER + sin(_wisp_t * 1.8) * 16.0)
	target.x = clampf(target.x, FLYER_LEFT, FLYER_RIGHT)
	target.y = maxf(target.y, 90.0)
	var want := (target - global_position)
	var speed := float(data.speed)
	var desired := want.normalized() * minf(speed, want.length() * 3.0)
	velocity = velocity.move_toward(desired, 900.0 * delta)
	global_position += velocity * delta
	if _ready_to_strike() and to_p.y > 70.0 and absf(to_p.x) < 300.0:
		_begin_windup()

## A bell-ringer keeps its distance on its own floor: it backs away from a
## knight inside SEXTON_NEAR and closes on one beyond SEXTON_FAR, then tolls
## once the knight stands within reach at about its own height.
func _seek_sexton(to_p: Vector2, delta: float) -> void:
	var dx := absf(to_p.x)
	var speed := 0.0
	if dx < Content.SEXTON_NEAR:
		speed = -facing * float(data.speed) * 0.8
	elif dx > Content.SEXTON_FAR:
		speed = facing * float(data.speed)
	_walk(speed, delta)
	if _ready_to_strike() and dx < Content.SEXTON_FAR + 40.0 and absf(to_p.y) < 140.0:
		_begin_windup()

func _seek_brute(to_p: Vector2, delta: float) -> void:
	# Slow heavy melee approach
	_close_in(to_p.x, 60.0, delta)
	if absf(to_p.x) < 64.0 and absf(to_p.y) < 70.0 and _ready_to_strike():
		_begin_windup()

func _seek_bomber(to_p: Vector2, delta: float) -> void:
	# Rush toward player; arm and start fuse when close
	_close_in(to_p.x, 48.0, delta, 1.15)
	if absf(to_p.x) < 56.0 and absf(to_p.y) < 80.0 and not _bomb_armed and _spawn_grace <= 0.0:
		_bomb_armed = true
		_begin_windup()

func _begin_windup() -> void:
	state = EState.WINDUP
	st_timer = float(data.windup)
	velocity.x *= 0.2
	if kind == Kind.BOMBER:
		# The fuse is the bomber's only clock, so the ring it draws never lies.
		_fuse_t = _fuse_total
	emit_signal("telegraphed", telegraph_id(kind), global_position, elite)

func _step_windup(delta: float) -> void:
	if kind == Kind.CROW:
		# Hang in the air, rising a little as the wings draw back.
		velocity = velocity.move_toward(Vector2(0.0, -30.0), 1200.0 * delta)
		global_position += velocity * delta
		var p = _get_player()
		if p != null:
			facing = signf(p.global_position.x - global_position.x) if absf(p.global_position.x - global_position.x) > 4.0 else facing
		st_timer -= delta
		if st_timer <= 0.0:
			_begin_dive()
		return
	_walk(0.0, delta)
	st_timer -= delta
	# An armed bomber only waits: its fuse, burning in _physics_process, sets it off.
	if st_timer > 0.0 or kind == Kind.BOMBER:
		return
	match kind:
		Kind.WISP:
			_wisp_shoot()
			_enter_recover()
		Kind.SEXTON:
			_toll()
			_enter_recover()
		_:
			state = EState.ATTACK
			st_timer = float(data.active) if data.has("active") else 0.18
			_arm(float(data.w) * 0.5 + 20.0)

## The dive: a straight line at where the knight stood when the shriek ended.
func _begin_dive() -> void:
	var p = _get_player()
	var aim := Vector2(facing, 1.2).normalized()
	if p != null:
		aim = (p.global_position - global_position).normalized()
		if aim.y < 0.35:
			aim = Vector2(signf(aim.x) if aim.x != 0.0 else facing, 0.35).normalized()
	state = EState.ATTACK
	velocity = aim * float(data.get("dive_speed", 720.0))
	st_timer = 0.9
	_arm(0.0)

func _step_dive(delta: float) -> void:
	global_position += velocity * delta
	st_timer -= delta
	_strike_overlaps(attack_damage(), Vector2(signf(velocity.x), -0.3), float(data.knock))
	var floor_hit := global_position.y >= Content.FLOOR_Y - float(data.h) * 0.5 - 6.0 and velocity.y > 0.0
	if st_timer <= 0.0 or _atk_hit or floor_hit:
		_enter_recover()
		# Pull out of the dive and climb away.
		velocity = Vector2(velocity.x * 0.35, -300.0)

func _step_attack(delta: float) -> void:
	if kind == Kind.CROW:
		_step_dive(delta)
		return
	_walk(facing * float(data.speed) * 0.3, delta)
	st_timer -= delta
	_strike_overlaps(attack_damage(), Vector2(facing, -0.2), float(data.knock))
	if st_timer <= 0.0:
		_enter_recover()

func _wisp_shoot() -> void:
	var player = _get_player()
	var dir := Vector2(facing, 0.0)
	if player != null:
		var d: Vector2 = (player.global_position - global_position).normalized()
		dir = d
	var color: Color = Content.ELITE_COLOR if elite else data.color
	emit_signal("projectile_requested", "enemy", global_position + Vector2(facing * 18.0, 0.0), dir * Content.WISP_SHOT_SPEED, Content.WISP_SHOT_DAMAGE * damage_mul, 160.0, 0, Content.WISP_SHOT_LIFE, color)
	if elite:
		# Elite wisps fire a tight twin volley.
		var side := Vector2(-dir.y, dir.x) * 14.0
		emit_signal("projectile_requested", "enemy", global_position + side, dir.rotated(0.16) * Content.WISP_SHOT_SPEED, Content.WISP_SHOT_DAMAGE * damage_mul, 160.0, 0, Content.WISP_SHOT_LIFE, color)

## The bell comes down: a toll rolls out both ways along the sexton's own floor,
## low enough to jump, and the game hears the bell ring.
func _toll() -> void:
	var feet := global_position.y + float(data.h) * 0.5
	var color: Color = Content.ELITE_COLOR if elite else Content.TOLL_COLOR
	for side: float in [-1.0, 1.0]:
		var at := Vector2(global_position.x + side * float(data.w) * 0.5, feet - TOLL_LIFT)
		wave_requested.emit(at, Vector2(side * float(data.toll_speed), 0.0), attack_damage(), float(data.toll_life), "toll", color)
	announced.emit("", "sexton_wave", global_position)

## The bomber bursts. Cut down while armed (`reduced`), it pops in a smaller
## blast that is practical to dash away from, and counts as the knight's kill;
## a fuse that burns down is its own doing and earns nothing. Either way the
## blast catches the knight and every creature near it, and the creatures it
## kills are the knight's.
func _do_explosion(reduced: bool = false) -> void:
	var blast := _blast_radius * (0.55 if reduced else 1.0)
	var blast_damage := attack_damage() * (0.4 if reduced else 1.0)
	exploded_out = true
	_die(reduced)
	var player = _get_player()
	if player != null and global_position.distance_to(player.global_position) <= blast:
		player.take_damage(blast_damage, _blast_dir(player), 380.0)
	for foe in living_near(get_tree(), global_position, blast):
		foe.take_damage(blast_damage, _blast_dir(foe), 380.0, 2.0)
	emit_signal("exploded", global_position, blast, blast_damage)

## Outward and a little up from the blast, toward `target`.
func _blast_dir(target: Node2D) -> Vector2:
	var away := (target.global_position - global_position).normalized()
	return Vector2(away.x if away != Vector2.ZERO else 0.0, -0.5)

func _step_recover(delta: float) -> void:
	if kind == Kind.CROW:
		velocity = velocity.move_toward(Vector2.ZERO, 520.0 * delta)
		global_position += velocity * delta
		st_timer -= delta
		if st_timer <= 0.0:
			state = EState.SEEK
		return
	_walk(0.0, delta)
	st_timer -= delta
	if st_timer <= 0.0:
		state = EState.SEEK

func _step_stagger(delta: float) -> void:
	_apply_gravity(delta)
	velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
	move_and_slide()
	stagger_t -= delta
	if stagger_t <= 0.0:
		state = EState.SEEK

## `poise_dmg` is how hard the blow tests a guard: a light cut 1, a parry or
## riposte enough to break any guard outright.
func take_damage(amount: float, from_dir: Vector2, kb: float, poise_dmg := 1.0) -> void:
	if dead: return
	_last_hit_dir = from_dir
	_since_struck = 0.0
	last_hit_blocked = _ward_blocks(amount, from_dir, kb) or _shield_blocks(amount, from_dir, kb)
	if last_hit_blocked:
		return
	if _vulnerable_t > 0.0:
		amount *= BREAK_DAMAGE_MUL
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
	if oath == "twinned" and not _twinned and hp <= hp_max * 0.5:
		_twinned = true
		twin_requested.emit(kind, global_position + Vector2(-facing * 44.0, -12.0))
	_react_to_blow(from_dir, kb, poise_dmg)

## A warded elite's runes each swallow one blow whole, whatever dealt it.
func _ward_blocks(amount: float, from_dir: Vector2, kb: float) -> bool:
	if _wards <= 0:
		return false
	_wards -= 1
	_shield_flash = 0.12
	emit_signal("damaged", amount, global_position + Vector2(0.0, -float(data.h) * 0.5), true)
	velocity = from_dir.normalized() * kb * 0.2
	return true

## The brute's tower shield takes a blow from the front: it rings off, or the
## shield finally breaks and staggers its bearer. True when the hit was absorbed.
func _shield_blocks(amount: float, from_dir: Vector2, kb: float) -> bool:
	# Frontal = the blow travels against the way the brute faces; a backstab slips past.
	if not shield_active or signf(from_dir.x) != -facing:
		return false
	_shield_flash = 0.12
	var absorbed := minf(amount, maxf(shield_hp, 0.0))
	shield_hp -= amount
	emit_signal("damaged", absorbed, global_position + Vector2(0.0, -float(data.h) * 0.5), true)
	if shield_hp <= 0.0:
		shield_active = false
		_shield_flash = 0.25
		_stagger(0.3, from_dir.normalized() * kb * 0.5)
	else:
		velocity = from_dir.normalized() * kb * 0.2
	return true

## How a blow that landed moves the creature. Fodder always flinches. A poised
## creature holds a committed windup through the blow, and a guard worn
## through breaks into a long stagger that leaves it open.
func _react_to_blow(from_dir: Vector2, kb: float, poise_dmg: float) -> void:
	if poise_max() > 0.0 and _vulnerable_t <= 0.0:
		_poise -= poise_dmg
		_poise_regen_t = POISE_REGEN
		if _poise <= 0.0:
			_break_guard(from_dir, kb)
			return
		if _committed():
			_poise_flash = 0.12
			return
	# Elites shrug off hits faster so they keep pressure on.
	_stagger(0.12 if elite else 0.18, from_dir.normalized() * kb * (0.6 if elite else 1.0))
	if _is_flyer():
		velocity.y = from_dir.y * kb * 0.5

## Past COMMIT_AT of its windup: the strike is coming whatever lands on it.
func _committed() -> bool:
	return state == EState.WINDUP and st_timer <= float(data.windup) * (1.0 - COMMIT_AT)

## The guard gives way: a long stagger, and blows land harder until it recovers.
func _break_guard(from_dir: Vector2, kb: float) -> void:
	_poise = poise_max()
	_vulnerable_t = BREAK_VULNERABLE
	_stagger(BREAK_STAGGER, from_dir.normalized() * kb * 0.6)
	announced.emit("BROKEN", "shatter", global_position + Vector2(0.0, -float(data.h) * 0.8))

## Knock the creature off its stride for `seconds` (a longer stagger already
## running is kept). Whatever it was swinging is called off, its melee box
## closes so nothing can parry a swing that is not coming, and a called-off
## strike waits out half a cooldown so it never winds straight back up. An
## armed fuse keeps burning.
func _stagger(seconds: float, knock: Vector2) -> void:
	if state == EState.WINDUP or state == EState.ATTACK:
		cd = maxf(cd, float(data.cd) * 0.5)
	stagger_t = maxf(stagger_t, seconds) if state == EState.STAGGER else seconds
	state = EState.STAGGER
	velocity = knock
	_disarm()

func apply_burn(dps: float, duration: float) -> void:
	if oath == "kindled":
		return  # it is already on fire, and feeds on it
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

## A parried strike always staggers, whatever the creature's poise.
func on_parried(knock_dir: Vector2) -> void:
	_stagger(0.4, knock_dir.normalized() * 260.0)

## Pyre boon: a burning enemy detonates against its neighbours when it dies.
func _pyre_detonate() -> void:
	if pyre_damage <= 0.0 or burn_time <= 0.0:
		return
	var radius := Content.PYRE_RADIUS
	# This foe is already dead, so the query leaves it out.
	for foe in living_near(get_tree(), global_position, radius + 20.0):
		# The blast's own chain may already have killed a later foe.
		if foe.dead:
			continue
		var dir: Vector2 = (foe.global_position - global_position).normalized()
		if dir == Vector2.ZERO: dir = Vector2.UP
		foe.take_damage(pyre_damage, Vector2(dir.x, -0.4), 300.0)
		foe.apply_burn(Content.P_FLAME_BURN_DPS, Content.P_FLAME_BURN_TIME * 0.5)
	emit_signal("pyre_burst", global_position, radius)

func _die(award_reward: bool = true) -> void:
	if dead: return
	dead = true
	state = EState.DEAD
	_disarm()
	_hurtbox.set_deferred("monitorable", false)
	if award_reward:
		_pyre_detonate()
	var score := int(data.score) * (Content.ELITE_SCORE_MUL if elite else 1)
	emit_signal("died", score if award_reward else 0)

## Wisps and crows fly: no gravity, no floor, no pits.
func _is_flyer() -> bool:
	return kind == Kind.WISP or kind == Kind.CROW

func _apply_gravity(delta: float) -> void:
	if not _is_flyer():
		velocity.y += Content.GRAVITY * delta

func _move_x(speed: float, delta: float) -> void:
	if _ledge_ray != null and speed != 0.0 and is_on_floor():
		_ledge_ray.position = Vector2(signf(speed) * (float(data.w) * 0.5 + 12.0), float(data.h) * 0.35)
		_ledge_ray.force_raycast_update()
		if not _ledge_ray.is_colliding() and not _drops_toward_knight(signf(speed)):
			speed = 0.0
	velocity.x = move_toward(velocity.x, speed, 2000.0 * delta)

## A walker at a ledge's lip steps off only toward a knight waiting below, and
## only where solid floor catches it: a spike pit is never a way down. A
## sexton never steps off: it keeps to its own floor and tolls along it.
func _drops_toward_knight(dir: float) -> bool:
	var player = _get_player()
	if player == null or kind == Kind.SEXTON:
		return false
	var to_p: Vector2 = player.global_position - global_position
	return to_p.y > 40.0 and signf(to_p.x) == dir and _floor_below(dir * (float(data.w) * 0.5 + 12.0))

## Onto the spikes. The knight earns the kill, and a RING OUT, if they struck
## it lately; a creature that blundered in on its own is cleared away quietly.
func ring_out() -> void:
	if dead or _is_flyer():
		return
	var credited := _since_struck <= RING_OUT_CREDIT
	_last_hit_dir = Vector2.DOWN
	if credited:
		announced.emit("RING OUT", "ring_out", global_position + Vector2(0.0, -float(data.h)))
	_die(credited)

## The knight, or null. Freed nodes leave their groups, so a non-null result is
## always valid.
func _get_player():
	return get_tree().get_first_node_in_group("player")

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
	elif kind == Kind.CROW:
		# Flyers pivot on their centre; a dive tips the whole cut-out down its line.
		var tilt := 0.0
		if state == EState.ATTACK:
			tilt = atan2(velocity.y, absf(velocity.x))
		elif state == EState.WINDUP:
			tilt = -0.25 * tw + (sin(_anim_t * 70.0) * 0.05 * tw if not Feedback.motion_reduced else 0.0)
		elif state == EState.STAGGER:
			tilt = -0.5
		VFX.set_pose(self, Vector2.ZERO, facing, Vector2(pop, pop), tilt)
	else:
		VFX.draw_contact_shadow(self, Vector2(0.0, h * 0.5 + 1.0), w * 1.1 * (2.0 - squash), 8.0, air)
		VFX.set_pose(self, Vector2(0.0, h * 0.5), facing, Vector2(pop * (2.0 - squash), pop * squash), lean)
	if elite:
		var pulse := 0.10 + sin(t * 3.0) * 0.03
		var escale := Content.ELITE_SCALE if _elite_anim <= 0.0 else lerpf(1.0, Content.ELITE_SCALE, clampf(1.0 - _elite_anim / 0.25, 0.0, 1.0))
		VFX.set_pose(self, Vector2(0.0, h * 0.5), facing, Vector2(pop * (2.0 - squash) * escale, pop * squash * escale), lean)
		draw_circle(Vector2(0.0, -h * 0.1), w * 1.15, Color(Content.ELITE_COLOR, pulse))
		draw_circle(Vector2(0.0, -h * 0.1), w * 0.8, Color(Content.ELITE_COLOR, pulse * 0.8))
		# A thin rim in the archetype's own hue, so the kind still reads under the gold.
		draw_arc(Vector2(0.0, -h * 0.1), w * 1.15, 0.0, TAU, 32, Color(data.color, 0.85), 2.0)
		# Gilded crest so elites read instantly, even mid-swarm.
		var crest_y := -h * 0.72 - 9.0 - h * 0.16 - 10.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(-9.0, crest_y), Vector2(-6.0, crest_y - 8.0), Vector2(-3.0, crest_y - 3.0),
			Vector2(0.0, crest_y - 11.0), Vector2(3.0, crest_y - 3.0), Vector2(6.0, crest_y - 8.0), Vector2(9.0, crest_y),
		]), Content.ELITE_COLOR)
		draw_circle(Vector2(0.0, crest_y - 11.0), 2.0, VFX.HOT)
		_draw_oath(w, h, t, Vector2(16.0, crest_y - 5.0))
	match kind:
		Kind.STALKER: _draw_stalker(w, h, base, mid, t, tw, ta, flash)
		Kind.HOPPER: _draw_hopper(w, h, base, mid, t, tw, flash, air)
		Kind.WISP: _draw_wisp(w, base, mid, t, tw, flash)
		Kind.BRUTE: _draw_brute(w, h, base, mid, t, tw, ta, flash)
		Kind.BOMBER: _draw_bomber(w, h, base, mid, t, flash)
		Kind.CROW: _draw_crow(w, h, base, mid, t, tw, flash)
		Kind.SEXTON: _draw_sexton(w, h, base, mid, t, tw, flash)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_guard(w, h, t)
	# The committed line: in the last beat of the shriek, a faint dashed track
	# shows where the dive will go, so a sidestep is a read, not a guess.
	if kind == Kind.CROW and state == EState.WINDUP and tw > 0.45:
		var pl = _get_player()
		if pl != null:
			var to: Vector2 = (pl.global_position - global_position)
			var k := clampf((tw - 0.45) / 0.55, 0.0, 1.0)
			draw_dashed_line(Vector2.ZERO, to.normalized() * minf(to.length(), 260.0), Color(1.0, 0.45, 0.15, 0.18 + 0.3 * k), 2.0, 9.0)
	# Bomber fuse telegraph: expanding ring toward the true blast radius.
	if kind == Kind.BOMBER and _bomb_armed and _fuse_t > 0.0:
		var ft: float = 1.0 - _fuse_t / _fuse_total
		var r := lerpf(12.0, _blast_radius, ft)
		draw_arc(Vector2.ZERO, r, 0, TAU, 28, Color(1.0, 0.3, 0.1, 0.25 + ft * 0.35), 2.0)
		if ft > 0.7:
			var pulse := 0.5 + sin(Time.get_ticks_msec() * 0.05) * 0.5
			draw_circle(Vector2.ZERO, w * 0.5, Color(1.0, 0.3, 0.2, pulse * 0.4))
	# Active melee reach: a ground arc under the true sweep, not a debug box.
	if state == EState.ATTACK and kind != Kind.CROW:
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

## An elite's oath as a small cut-paper sigil beside its crest at `at`; a
## warded elite also carries its remaining runes circling its body.
func _draw_oath(w: float, h: float, t: float, at: Vector2) -> void:
	var bone := Color("e8dcc0")
	match oath:
		"kindled":
			VFX.draw_flame(self, at + Vector2(0.0, 5.0), 11.0, 6.0, t, 0.7)
		"warded":
			var rune := PackedVector2Array([Vector2(0.0, -6.0), Vector2(4.0, 0.0), Vector2(0.0, 6.0), Vector2(-4.0, 0.0)])
			draw_colored_polygon(Transform2D(0.0, at) * rune, bone)
			for i in range(_wards):
				var a := t * 1.8 + float(i) * PI
				var spot := Vector2(cos(a) * w * 0.95, -h * 0.1 + sin(a) * h * 0.35)
				var paper := Transform2D(0.0, spot) * rune
				draw_colored_polygon(paper, Color.WHITE if _shield_flash > 0.0 else bone)
				draw_polyline(paper + PackedVector2Array([paper[0]]), Content.ELITE_COLOR, 1.2, true)
		"vengeful":
			var star := PackedVector2Array()
			for k in range(8):
				star.append(at + Vector2.UP.rotated(float(k) * PI / 4.0) * (6.5 if k % 2 == 0 else 2.5))
			draw_colored_polygon(star, VFX.EMBER)
		"twinned":
			draw_circle(at + Vector2(-3.0, 0.0), 3.5, Content.ELITE_COLOR)
			draw_arc(at + Vector2(3.0, 0.0), 3.5, 0.0, TAU, 12, bone, 1.5)

## A committed windup rings gold where a blow glances off it; a broken guard
## hangs round the body as a torn gold hoop until the opening closes.
func _draw_guard(w: float, h: float, t: float) -> void:
	var r := maxf(w, h) * 0.66
	var center := Vector2(0.0, -h * 0.08)
	if _poise_flash > 0.0:
		draw_arc(center, r, 0.0, TAU, 28, Color(VFX.GOLD, _poise_flash / 0.12), 3.0)
	if _vulnerable_t > 0.0:
		var k := _vulnerable_t / BREAK_VULNERABLE
		for i in range(3):
			var a0 := float(i) * TAU / 3.0 + t * 1.5
			draw_arc(center, r + 4.0, a0, a0 + 1.4, 8, Color(VFX.GOLD, 0.75 * k), 2.0)

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

func _draw_crow(w: float, h: float, base: Color, mid: Color, t: float, tw: float, flash: bool) -> void:
	# Wing beat: steady flaps while circling, raised and shivering on the shriek,
	# swept back flat along the body in the dive.
	var flap := sin(t * 13.0) * 0.85
	if state == EState.WINDUP:
		flap = 0.7 + sin(t * 60.0) * 0.12 * tw
	elif state == EState.ATTACK:
		flap = -0.95
	elif state == EState.RECOVER:
		flap = sin(t * 22.0) * 1.0
	var shoulder := Vector2(-1.0, -h * 0.22)
	var far := base if flash else base.darkened(0.3)
	_crow_wing(shoulder + Vector2(3.0, -1.0), flap * 0.85 - 0.15, w * 0.95, far)
	# Tail fan: three ragged feathers.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.35, -h * 0.12), Vector2(-w * 0.95, -h * 0.34), Vector2(-w * 0.82, -h * 0.08),
		Vector2(-w * 1.0, h * 0.06), Vector2(-w * 0.8, h * 0.16), Vector2(-w * 0.9, h * 0.34), Vector2(-w * 0.32, h * 0.16),
	]), base)
	# Body: a sleek cut-paper teardrop from beak to tail root.
	var body := PackedVector2Array([
		Vector2(w * 0.5, -h * 0.1), Vector2(w * 0.36, -h * 0.42), Vector2(w * 0.08, -h * 0.5),
		Vector2(-w * 0.3, -h * 0.3), Vector2(-w * 0.45, -h * 0.02), Vector2(-w * 0.26, h * 0.34),
		Vector2(w * 0.12, h * 0.36), Vector2(w * 0.38, h * 0.14),
	])
	VFX.draw_shaded_polygon(self, body, mid, not flash)
	VFX.draw_rim(self, body, 1.0, 0.9)
	# Dark head band and a heavy bone beak.
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, -h * 0.1), Vector2(w * 0.36, -h * 0.42), Vector2(w * 0.12, -h * 0.46), Vector2(w * 0.16, h * 0.02), Vector2(w * 0.38, h * 0.14)]), base)
	var beak := Color("d8c7a4") if not flash else Color.WHITE
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.46, -h * 0.2), Vector2(w * 0.86, -h * 0.02 + tw * 2.0), Vector2(w * 0.46, h * 0.06)]), beak)
	if tw > 0.0:
		# Beak parted mid-shriek.
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.48, h * 0.02), Vector2(w * 0.8, h * 0.12 + tw * 4.0), Vector2(w * 0.46, h * 0.1)]), beak.darkened(0.2))
	VFX.draw_ember_dot(self, Vector2(w * 0.3, -h * 0.2), 1.9 + tw * 1.2, VFX.GOLD, 0.8 + tw * 0.6)
	# Talons tucked under, reaching forward in the dive.
	var reach := 6.0 if state == EState.ATTACK else 0.0
	for i in range(2):
		var fx := w * (0.02 + 0.12 * float(i))
		draw_line(Vector2(fx, h * 0.3), Vector2(fx + 3.0 + reach, h * 0.52), base, 2.0, true)
	# Near wing over the body.
	_crow_wing(shoulder, flap, w, mid.darkened(0.12) if not flash else mid)

## One wing, pivoting at the shoulder: a leading edge and three primaries.
func _crow_wing(shoulder: Vector2, angle: float, span: float, col: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(4.0, 0.0), Vector2(-span * 0.1, -span * 0.52), Vector2(-span * 0.46, -span * 0.74),
		Vector2(-span * 0.5, -span * 0.58), Vector2(-span * 0.66, -span * 0.6), Vector2(-span * 0.62, -span * 0.44),
		Vector2(-span * 0.76, -span * 0.4), Vector2(-span * 0.58, -span * 0.24), Vector2(-span * 0.34, -span * 0.06),
	])
	var xf := Transform2D(angle, shoulder)
	var wing := xf * pts
	draw_colored_polygon(wing, col)
	draw_polyline(PackedVector2Array([wing[0], wing[1], wing[2]]), Color(VFX.RIM, 0.35), 1.2, true)

## The sexton: a hunched robe under a patched mantle, a low hood with one ember
## eye, a rope girdle and the bronze hand-bell. The bell hangs in front at
## rest, rises overhead through the windup and swings down with the toll.
func _draw_sexton(w: float, h: float, base: Color, mid: Color, t: float, tw: float, flash: bool) -> void:
	var sway := sin(t * 2.2) * 1.5
	var robe := PackedVector2Array([
		Vector2(-w * 0.46, h * 0.24), Vector2(-w * 0.5, -h * 0.06), Vector2(-w * 0.36, -h * 0.32),
		Vector2(-w * 0.1, -h * 0.44), Vector2(w * 0.14, -h * 0.34), Vector2(w * 0.32, -h * 0.12),
		Vector2(w * 0.36, h * 0.14), Vector2(w * 0.42, h * 0.5), Vector2(w * 0.2, h * 0.4),
		Vector2(w * 0.02, h * 0.5), Vector2(-w * 0.18, h * 0.4), Vector2(-w * 0.4, h * 0.5),
	])
	VFX.draw_shaded_polygon(self, robe, mid, not flash)
	VFX.draw_rim(self, robe, 1.0)
	# The mantle over the hump, its ragged edge falling across the back.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.5, -h * 0.06), Vector2(-w * 0.36, -h * 0.32), Vector2(-w * 0.1, -h * 0.44),
		Vector2(w * 0.14, -h * 0.34), Vector2(w * 0.06, -h * 0.12), Vector2(-w * 0.1, -h * 0.04),
		Vector2(-w * 0.22, h * 0.04), Vector2(-w * 0.36, -h * 0.02),
	]), base if flash else base.lightened(0.1))
	# Rope girdle, knotted in front, its loose end swinging.
	var rope := Color.WHITE if flash else Color("c9b48a")
	var knot := Vector2(w * 0.14, h * 0.11)
	draw_line(Vector2(-w * 0.46, h * 0.1), Vector2(w * 0.36, h * 0.12), base.darkened(0.3), 2.5, true)
	draw_polyline(PackedVector2Array([knot, knot + Vector2(1.0 + sway * 0.5, h * 0.14), knot + Vector2(2.0 + sway, h * 0.26)]), rope, 1.6, true)
	draw_circle(knot, 2.2, rope)
	# Hood hung low and forward, a hollow face and one ember eye.
	var hood := Vector2(w * 0.24, -h * 0.28)
	draw_circle(hood, w * 0.3, mid if flash else mid.darkened(0.15))
	VFX.draw_rim_circle(self, hood, w * 0.3, 1.0, 0.8)
	VFX.draw_ellipse(self, hood + Vector2(w * 0.08, 1.0), w * 0.16, w * 0.2, Color(0.05, 0.03, 0.06))
	VFX.draw_ember_dot(self, hood + Vector2(w * 0.12, 0.0), 2.0 + tw * 0.8, VFX.GOLD, 0.75 + 0.25 * sin(t * 9.0) + tw * 0.5)
	# The bell arm: quick up overhead, a trembling hold, then down through the toll.
	var lift := ease(tw, 0.4)
	var rung := 0.0
	if state == EState.RECOVER:
		rung = clampf((st_timer - float(data.recover) + TOLL_FOLLOW) / TOLL_FOLLOW, 0.0, 1.0)
	var shoulder := Vector2(w * 0.1, -h * 0.18)
	# Raised, the bell rides clear above the hood so the eye still shows under it.
	var hand := Vector2(w * 0.5, -h * 0.12).lerp(Vector2(w * 0.04, -h * 1.12), lift).lerp(Vector2(w * 0.66, h * 0.1), rung)
	var elbow := (shoulder + hand) * 0.5 + Vector2(4.0, 3.0)
	draw_polyline(PackedVector2Array([shoulder, elbow, hand]), base if flash else base.darkened(0.1), 6.0, true)
	var tremble := sin(t * 60.0) * 0.08 * tw * tw
	_draw_bell(hand, -0.45 * lift + 0.6 * rung + tremble, t, flash)
	if tw > 0.0:
		_draw_ripples(hand + Vector2(0.0, 17.0).rotated(-0.45 * lift), tw, t)
	draw_circle(hand, 3.0, base)

## The bronze hand-bell hanging from `hand`, tipped by `angle`: a turned wooden
## handle, a bevelled flaring body with a riveted waist band, a heavy lip and
## the clapper swinging under it.
func _draw_bell(hand: Vector2, angle: float, t: float, flash: bool) -> void:
	var xf := Transform2D(angle, hand)
	var bronze := Color.WHITE if flash else Color("b58a4a")
	var dark := Color("5e4220")
	var shine := Color("f2d59a")
	var wood := Color("4a3020")
	draw_line(xf * Vector2(0.0, -3.0), xf * Vector2(0.0, 8.0), wood, 4.0, true)
	draw_circle(xf * Vector2(0.0, -4.0), 3.0, wood)
	var body := xf * PackedVector2Array([
		Vector2(-5.0, 8.0), Vector2(5.0, 8.0), Vector2(7.5, 12.0), Vector2(8.5, 19.0),
		Vector2(12.5, 25.0), Vector2(-12.5, 25.0), Vector2(-8.5, 19.0), Vector2(-7.5, 12.0),
	])
	VFX.draw_shaded_polygon(self, body, bronze, not flash)
	# Bevel: the flank toward the knight catches the light, the far one falls dark.
	draw_colored_polygon(xf * PackedVector2Array([
		Vector2(5.0, 8.0), Vector2(7.5, 12.0), Vector2(8.5, 19.0), Vector2(12.5, 25.0),
		Vector2(8.5, 25.0), Vector2(5.5, 19.0), Vector2(4.5, 12.0), Vector2(3.0, 8.0),
	]), Color(shine, 0.5))
	draw_colored_polygon(xf * PackedVector2Array([
		Vector2(-5.0, 8.0), Vector2(-3.0, 8.0), Vector2(-4.5, 12.0), Vector2(-5.5, 19.0),
		Vector2(-8.5, 25.0), Vector2(-12.5, 25.0), Vector2(-8.5, 19.0), Vector2(-7.5, 12.0),
	]), Color(dark, 0.5))
	draw_line(xf * Vector2(-8.0, 15.0), xf * Vector2(8.0, 15.0), dark, 2.0, true)
	for x: float in [-5.0, 0.0, 5.0]:
		draw_circle(xf * Vector2(x, 15.0), 1.1, shine)
	draw_line(xf * Vector2(-13.0, 25.0), xf * Vector2(13.0, 25.0), dark, 3.0, true)
	draw_circle(xf * Vector2(sin(t * 14.0) * 1.5, 28.0), 2.4, Color(0.12, 0.1, 0.12))

## The tell drawn round the raised bell: paper ripple rings, each a cut strip
## over its own shadow, spreading and fading from the bell on both sides and
## gaining strength through the windup. Reduced motion holds them still.
func _draw_ripples(center: Vector2, tw: float, t: float) -> void:
	const SPAN := 36.0
	var ink := Content.TOLL_COLOR.lightened(0.4)
	for i in range(3):
		var r := 14.0 + fmod(t * 40.0 + float(i) * SPAN / 3.0, SPAN)
		var a := minf(1.0, 1.3 * tw * (1.0 - (r - 14.0) / SPAN))
		for side: float in [0.0, PI]:
			draw_arc(center + Vector2(1.5, 1.5), r, side - 0.8, side + 0.8, 10, Color(0.04, 0.02, 0.05, 0.5 * a), 4.0, true)
			draw_arc(center, r, side - 0.8, side + 0.8, 10, Color(ink, a), 3.0, true)
