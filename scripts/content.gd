class_name Content
extends RefCounted
## Immutable tuning, room templates, enemy stats, combo data, and upgrade defs.

# --- Physics layer bitmasks (must match project.godot layer ordinals) ---
const L_WORLD := 1 << 0
const L_PLAYER_BODY := 1 << 1
const L_ENEMY_BODY := 1 << 2
const L_PLAYER_HURT := 1 << 3
const L_ENEMY_HURT := 1 << 4
const L_PLAYER_ATK := 1 << 5
const L_ENEMY_ATK := 1 << 6
const L_TRIGGER := 1 << 7

## A collision shape holding a fresh rectangle of `size`; callers position it.
static func rect_shape(size: Vector2) -> CollisionShape2D:
	var rect := RectangleShape2D.new()
	rect.size = size
	var shape := CollisionShape2D.new()
	shape.shape = rect
	return shape

# --- World / camera ---
const VIEW_W := 1280
const VIEW_H := 720
## Locked camera zoom for the approval frame: a ~15% tighter frame so the
## fighters read at Blasphemous scale without losing duel spacing.
const CAM_ZOOM := 1.15
const FLOOR_Y := 600.0
const ROOM_LEFT := -200.0
const ROOM_RIGHT := 1480.0
const GRAVITY := 2200.0

# --- Player base stats ---
const P_MAX_HP := 100.0
const P_SPEED := 360.0
const P_ACCEL := 3000.0
const P_AIR_ACCEL := 1600.0
const P_FRICTION := 2600.0
const P_JUMP_VEL := -820.0
const P_DOUBLE_JUMP_VEL := -720.0
const P_MAX_JUMPS := 2
const P_COYOTE := 0.10
const P_JUMP_BUFFER := 0.12
const P_JUMP_CUT := 0.45
const P_DASH_SPEED := 760.0
const P_DASH_TIME := 0.18
const P_DASH_CD := 0.55
const P_DASH_IFRAMES := 0.22
const P_HURT_IFRAMES := 0.7
const P_ATTACK_BUFFER := 0.18
const P_DASH_BUFFER := 0.12
const P_BODY_W := 26.0
const P_BODY_H := 54.0
const P_SPECIAL_MAX := 100.0
const P_SPECIAL_GAIN := 9.0
const P_SPECIAL_COST := 40.0
const P_FLAME_DURATION := 5.0
const P_FLAME_DAMAGE_MUL := 1.35
const P_FLAME_BURN_DPS := 8.0
const P_FLAME_BURN_TIME := 3.0
const P_HEAL_TIME := 0.55

# --- Down-slam (air attack) ---
const P_SLAM_DAMAGE := 30.0
const P_SLAM_KNOCK := 520.0
const P_SLAM_RADIUS := 110.0
const P_SLAM_VEL := 1500.0

# --- Wall slide / wall jump ---
const P_WALL_SLIDE_SPEED := 120.0
const P_WALL_JUMP_VEL := Vector2(560.0, -760.0)
const P_WALL_STICK_TIME := 0.12

# --- Parry (timed block) ---
const PARRY_WINDOW := 0.16       # active deflect window
const PARRY_COOLDOWN := 0.5
const PARRY_RANGE := 78.0
const PARRY_DAMAGE := 18.0       # damage dealt to deflected melee enemy
const PARRY_PROJECTILE_BOOST := 1.6  # deflected projectile damage multiplier
## A confirmed deflection banks one short-lived, committed counterattack.
const RIPOSTE_WINDOW := 1.2
const RIPOSTE := {
	"name": "riposte", "startup": 0.06, "active": 0.12, "recover": 0.24,
	"damage": 34.0, "knock": 540.0, "range": 112.0,
	"window": 0.0, "lunge": 360.0,
}

# --- Healing flask (Dead Cells-style) ---
const FLASK_MAX := 3
const FLASK_HEAL := 45.0
## Flask charges a cleared chamber returns, so health is carried through the
## run and a Healing Font (which refills them all) is a real choice.
const FLASK_PER_ROOM := 1

# --- Combo: three swings. Times in seconds. ---
const COMBO := [
	{ "name": "cut",   "startup": 0.06, "active": 0.08, "recover": 0.16, "damage": 12.0, "knock": 220.0, "range": 64.0,  "window": 0.32, "lunge": 150.0 },
	{ "name": "cleave","startup": 0.08, "active": 0.10, "recover": 0.20, "damage": 16.0, "knock": 300.0, "range": 74.0,  "window": 0.34, "lunge": 185.0 },
	{ "name": "finish","startup": 0.10, "active": 0.12, "recover": 0.26, "damage": 24.0, "knock": 460.0, "range": 84.0,  "window": 0.0, "lunge": 235.0 },
]

# --- Enemy archetypes ---
enum EnemyKind { STALKER, HOPPER, WISP, BRUTE, BOMBER, CROW }
## `name` is what the game calls a creature aloud: its debut lesson and an elite's oath.
const ENEMY := {
	EnemyKind.STALKER: { "name": "STALKER", "hp": 40.0,  "speed": 150.0, "damage": 14.0, "knock": 240.0, "cd": 1.3, "windup": 0.45, "recover": 0.5,  "score": 12, "w": 34.0, "h": 46.0, "color": Color("c44b3f") },
	EnemyKind.HOPPER:  { "name": "HOPPER", "hp": 28.0,  "speed": 210.0, "damage": 12.0, "knock": 200.0, "cd": 1.6, "windup": 0.30, "recover": 0.4,  "score": 14, "w": 32.0, "h": 38.0, "color": Color("d98c2b") },
	EnemyKind.WISP:    { "name": "WISP", "hp": 20.0,  "speed": 120.0, "damage": 10.0, "knock": 160.0, "cd": 2.4, "windup": 0.55, "recover": 0.45, "score": 18, "w": 30.0, "h": 30.0, "color": Color("7b6bd1") },
	EnemyKind.BRUTE:   { "name": "IRON PENITENT", "hp": 80.0,  "speed": 95.0,  "damage": 20.0, "knock": 360.0, "cd": 1.8, "windup": 0.60, "recover": 0.65, "score": 24, "w": 48.0, "h": 58.0, "color": Color("5a7a3a"), "shielded": true, "shield_hp": 30.0, "poise": 4.0 },
	EnemyKind.BOMBER:  { "name": "POWDER PILGRIM", "hp": 22.0,  "speed": 170.0, "damage": 20.0, "knock": 100.0, "cd": 1.4, "windup": 0.80, "recover": 0.0,  "score": 20, "w": 34.0, "h": 36.0, "color": Color("b85c2e"), "explodes": true, "fuse": 0.8, "blast_radius": 90.0 },
	## Carrion crow: circles overhead, shrieks while it hangs in the air, then
	## dives along a line it commits to. Sidestep the line or parry it down.
	EnemyKind.CROW:    { "name": "CARRION CROW", "hp": 24.0,  "speed": 230.0, "damage": 13.0, "knock": 220.0, "cd": 1.9, "windup": 0.55, "recover": 0.55, "score": 18, "w": 34.0, "h": 26.0, "color": Color("5a4a78"), "dive_speed": 760.0 },
}
const CROW_HOVER := 165.0
const WISP_SHOT_SPEED := 420.0
const WISP_SHOT_LIFE := 2.4
const WISP_SHOT_DAMAGE := 10.0
const WISP_RANGE := 520.0

# --- Boss ---
const BOSS_HP := 520.0
const BOSS_DAMAGE := 22.0
const BOSS_SPEED := 170.0
const BOSS_CHARGE_SPEED := 980.0
const BOSS_CHARGE_TIME := 0.5
const BOSS_SUMMON_KIND := EnemyKind.WISP
const BOSS_W := 84.0
const BOSS_H := 118.0
const BOSS_COLOR := Color("8a2f3d")
const BOSS_SHOT_SPEED := 380.0
const BOSS_SHOT_DAMAGE := 14.0
const BOSS_PHASE2_AT := 0.5

# --- Run structure ---
const ROOMS_BEFORE_BOSS := 6
const UPGRADES_PER_OFFER := 3

# --- Difficulty curve: enemies harden with depth so upgrades stay meaningful ---
const DIFF_HP_PER_ROOM := 0.10
const DIFF_DMG_PER_ROOM := 0.05

# --- Elites: one per room at most, rolled from room 2 onward ---
const ELITE_HP_MUL := 1.8
const ELITE_DMG_MUL := 1.3
const ELITE_SCALE := 1.22
const ELITE_CELLS := 3
const ELITE_SCORE_MUL := 3
const ELITE_COLOR := Color("ffd166")
## Extra blows an elite's committed windup shrugs off (see Enemy.poise_max).
const ELITE_POISE := 2.0
## Elites from this chamber on swear an oath, named as they arrive:
## kindled - leaves a trail of burning ground, and cannot be set alight;
## warded - two paper runes each swallow a blow before it can be hurt;
## vengeful - bursts into a ring of slow, parryable embers when it falls;
## twinned - at half health a plain copy of it steps out beside it.
const OATH_FROM_ROOM := 3
const ELITE_OATHS := ["kindled", "warded", "vengeful", "twinned"]

# --- Kill streaks: chained kills inside the window multiply score ---
const STREAK_WINDOW := 3.4
const STREAK_TIERS := [2, 4, 7, 11]
const STREAK_MULTS := [1.0, 1.25, 1.5, 2.0, 3.0]

# --- Upgrade rarity roll weights ---
const RARITY_WEIGHTS := { "common": 60.0, "rare": 30.0, "epic": 10.0 }
const RARITY_COLORS := { "common": Color("a99db2"), "rare": Color("7fd4ff"), "epic": Color("ffb347") }

# --- Second Wind / Pyre / Thorns tuning ---
const SECOND_WIND_HP_FRAC := 0.3
const PYRE_RADIUS := 96.0
const THORNS_RADIUS := 100.0
const MOMENTUM_TIME := 4.0
const MOMENTUM_MAX_STACKS := 3
const BLOODRUSH_HP_FRAC := 0.4
const EXECUTE_HP_FRAC := 0.25

## Enemy stat multipliers for a route position (room 0 is the intro).
static func difficulty_for_room(room_index: int) -> Dictionary:
	var depth := maxi(0, room_index)
	return { "hp_mul": 1.0 + DIFF_HP_PER_ROOM * float(depth), "dmg_mul": 1.0 + DIFF_DMG_PER_ROOM * float(depth) }

static func elite_chance(room_index: int) -> float:
	if room_index < 2:
		return 0.0
	return clampf(0.3 + 0.08 * float(room_index - 2), 0.0, 0.7)

static func streak_multiplier(kills: int) -> float:
	var tier := 0
	for threshold in STREAK_TIERS:
		if kills >= int(threshold):
			tier += 1
	return float(STREAK_MULTS[clampi(tier, 0, STREAK_MULTS.size() - 1)])

static func streak_tier(kills: int) -> int:
	var tier := 0
	for threshold in STREAK_TIERS:
		if kills >= int(threshold):
			tier += 1
	return tier

# --- Palettes ---
const PAL := {
	"player": Color("e8e0d0"),
	"player_accent": Color("ff7a18"),
	"attack": Color("ffa827"),
	"special": Color("7fd4ff"),
	"exit": Color("2be4c8"),
	"text": Color("e8e0d0"),
	"hurt_number": Color("ff6b6b"),
	"heal_number": Color("2be4c8"),
}

# --- Depth moods: the keep warms from a cold crypt to the ember throne ---
## Each keyframe is a full palette; mood_for() blends between them by route progress.
const MOODS := [
	{
		"name": "crypt", "ambient": Color(0.5, 0.56, 0.78), "bg_top": Color("060812"), "bg_mid": Color("0e1526"), "bg_bot": Color("172238"), "pit": Color("04060c"),
		"fog": Color("1a2440"), "stone": Color("222c44"), "wall": Color("141c30"), "edge": Color("2a3652"), "spire": Color("090c18"),
		"torch": Color("ffa827"), "glow": Color(0.85, 0.25, 0.08), "moon": Color("c9d2ee"), "moon_alpha": 0.9,
		"banner": Color("1d3a45"), "glass": Color("3a7f9a"), "stars": 1.0, "ember_seep": 0.0, "moss": 0.8,
	},
	{
		"name": "forge", "ambient": Color(0.7, 0.52, 0.46), "bg_top": Color("0a0509"), "bg_mid": Color("1d0d16"), "bg_bot": Color("2b1412"), "pit": Color("0a0405"),
		"fog": Color("3a1410"), "stone": Color("2a1522"), "wall": Color("1e0f18"), "edge": Color("35192a"), "spire": Color("120710"),
		"torch": Color("ff7a18"), "glow": Color(1.0, 0.4, 0.08), "moon": Color("ff9a4a"), "moon_alpha": 0.7,
		"banner": Color("4a2a12"), "glass": Color("c9662a"), "stars": 0.35, "ember_seep": 0.6, "moss": 0.2,
	},
	{
		"name": "throne", "ambient": Color(0.72, 0.42, 0.46), "bg_top": Color("0b0407"), "bg_mid": Color("200a11"), "bg_bot": Color("35101a"), "pit": Color("0c0406"),
		"fog": Color("46101a"), "stone": Color("2e1320"), "wall": Color("240c15"), "edge": Color("3f1524"), "spire": Color("15060c"),
		"torch": Color("ff5a2a"), "glow": Color(1.0, 0.22, 0.1), "moon": Color("ff5f4a"), "moon_alpha": 0.8,
		"banner": Color("5c1220"), "glass": Color("b8283c"), "stars": 0.0, "ember_seep": 1.0, "moss": 0.0,
	},
]

## Blend the mood keyframes for a route position: 0 is the first chamber, 1 the throne.
static func mood_for(progress: float) -> Dictionary:
	var p := clampf(progress, 0.0, 1.0) * float(MOODS.size() - 1)
	var i := mini(floori(p), MOODS.size() - 2)
	var t := p - float(i)
	var a: Dictionary = MOODS[i]
	var b: Dictionary = MOODS[i + 1]
	var out := {}
	for key in a:
		if a[key] is Color:
			out[key] = (a[key] as Color).lerp(b[key], t)
		elif a[key] is float:
			out[key] = lerpf(float(a[key]), float(b[key]), t)
		else:
			out[key] = a[key] if t < 0.5 else b[key]
	return out

# --- Upgrades ---
## Boons. `rarity` weights the roll; `unique` boons are offered at most once per run.
static var UPGRADES: Array = [
	{ "id": "vitality",  "title": "Vitality",   "desc": "+25 max HP and full heal.",        "kind": "max_hp",     "value": 25.0, "rarity": "common" },
	{ "id": "swift",     "title": "Swift Feet", "desc": "+12% move speed.",                 "kind": "speed_mul",  "value": 0.12, "rarity": "common" },
	{ "id": "power",     "title": "Power",      "desc": "+20% melee damage.",               "kind": "dmg_mul",    "value": 0.20, "rarity": "common" },
	{ "id": "edge",      "title": "Razor Edge", "desc": "+35% combo finisher damage.",      "kind": "finish_mul", "value": 0.35, "rarity": "rare" },
	{ "id": "magnet",    "title": "Magnetism",  "desc": "+40% special meter gain.",         "kind": "special_mul","value": 0.40, "rarity": "common" },
	{ "id": "warden",    "title": "Warden",     "desc": "+0.4s hurt invulnerability.",      "kind": "iframes",    "value": 0.4, "rarity": "common" },
	{ "id": "surge",     "title": "Surge",      "desc": "The lance pierces three foes and strikes 35% harder.", "kind": "special_pierce", "value": 0.35, "rarity": "rare", "unique": true },
	{ "id": "leech",     "title": "Leech",      "desc": "Heal 3 HP per enemy hit.",         "kind": "lifesteal",  "value": 3.0, "rarity": "rare" },
	{ "id": "ember",     "title": "Ember Heart","desc": "Heal 20 HP now.",                  "kind": "heal",       "value": 20.0, "rarity": "common" },
	{ "id": "slam",      "title": "Crater",     "desc": "Down-slam deals +60% damage & wider blast.", "kind": "slam_mul", "value": 0.60, "rarity": "rare" },
	{ "id": "parry",     "title": "Riposte",    "desc": "Parry window +50% and deflects deal +12 dmg.", "kind": "parry", "value": 12.0, "rarity": "rare" },
	{ "id": "flask",     "title": "Witch Flask","desc": "+1 flask charge, filled now.", "kind": "flask_charge", "value": 1.0, "rarity": "rare" },
	{ "id": "dashmaster","title": "Dashmaster", "desc": "Dash cooldown halved, longer i-frames.", "kind": "dash_master", "value": 0.5, "rarity": "epic", "unique": true },
	# --- Synergy boons ---
	{ "id": "backdraft", "title": "Backdraft",  "desc": "A successful parry refunds 30 Graveflame.", "kind": "parry_special", "value": 30.0, "rarity": "rare" },
	{ "id": "kindling",  "title": "Kindling",   "desc": "Burn +6 dps and +2s. Finishers always ignite.", "kind": "burn", "value": 6.0, "rarity": "common" },
	{ "id": "momentum",  "title": "Momentum",   "desc": "Kills grant +12% speed & +10% damage for 4s (stacks 3x).", "kind": "momentum", "value": 0.12, "rarity": "rare" },
	{ "id": "bloodrush", "title": "Bloodrush",  "desc": "Below 40% HP, deal +35% damage.",  "kind": "bloodrush",  "value": 0.35, "rarity": "rare" },
	{ "id": "secondwind","title": "Second Wind","desc": "Once per run, survive a lethal hit at 30% HP.", "kind": "second_wind", "value": 1.0, "rarity": "epic", "unique": true },
	{ "id": "executioner","title": "Executioner","desc": "Enemies below 25% HP take +50% damage.", "kind": "execute", "value": 0.5, "rarity": "rare", "unique": true },
	{ "id": "pyre",      "title": "Pyre",       "desc": "Burning enemies explode on death for 60 damage.", "kind": "pyre", "value": 60.0, "rarity": "epic", "unique": true },
	{ "id": "emberwave", "title": "Emberwave",  "desc": "Every combo finisher hurls a flame wave.", "kind": "finisher_wave", "value": 1.0, "rarity": "epic", "unique": true },
	{ "id": "thorns",    "title": "Cinder Skin","desc": "Taking a hit scorches nearby enemies for 15.", "kind": "thorns", "value": 15.0, "rarity": "common" },
	# --- Move-changing boons: they alter what an action does, not just a number ---
	{ "id": "cindertrail", "title": "Cinder Trail", "desc": "Dashing leaves burning ground that sets foes alight.", "kind": "cinder_trail", "value": 1.0, "rarity": "rare", "unique": true },
	{ "id": "flareparry",  "title": "Flare Parry",  "desc": "A perfect parry bursts in flame, 22 damage around you.", "kind": "flare_parry", "value": 22.0, "rarity": "rare", "unique": true },
	{ "id": "twinlance",   "title": "Twin Lance",   "desc": "The flame lance looses two bolts.", "kind": "twin_lance", "value": 1.0, "rarity": "rare", "unique": true },
	{ "id": "phoenix",     "title": "Phoenix Flask", "desc": "Drinking a flask ignites you and bursts for 30 damage.", "kind": "phoenix", "value": 30.0, "rarity": "epic", "unique": true },
	{ "id": "brand",       "title": "Ember Brand",  "desc": "Burning enemies take +25% damage.", "kind": "brand", "value": 0.25, "rarity": "common" },
	{ "id": "skyfall",     "title": "Skyfall",      "desc": "Down-slams send shockwaves racing along the floor.", "kind": "skyfall", "value": 1.0, "rarity": "rare", "unique": true },
]

static func upgrade_rarity(u: Dictionary) -> String:
	return str(u.get("rarity", "common"))

static func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS["common"])

## Room templates. Each defines platforms (Rect2 in pixels), hazards, spawn slots, entry, exit.
static var ROOM_TEMPLATES: Array = [
	{
		"tag": "intro",
		"name": "ASHEN CELLS",
		"platforms": [ Rect2(ROOM_LEFT, FLOOR_Y, ROOM_RIGHT - ROOM_LEFT, 120) ],
		"hazards": [],
		"slots": [ Vector2(380, FLOOR_Y - 40), Vector2(900, FLOOR_Y - 40) ],
		"entry": Vector2(160, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
	{
		"tag": "gap",
		"name": "BROKEN CAUSEWAY",
		"platforms": [
			# Near floors run right up to their pit's spikes, so no bottomless strip opens in front of a pit.
			Rect2(ROOM_LEFT, FLOOR_Y, 620 - ROOM_LEFT, 120),
			Rect2(860, FLOOR_Y, ROOM_RIGHT - 860, 120),
			Rect2(680, FLOOR_Y - 180, 140, 40),
		],
		"hazards": [ Rect2(620, FLOOR_Y + 20, 240, 100) ],
		"slots": [ Vector2(430, FLOOR_Y - 40), Vector2(720, FLOOR_Y - 220), Vector2(1040, FLOOR_Y - 40) ],
		"entry": Vector2(180, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
	{
		"tag": "tiers",
		"name": "WARDEN'S ASCENT",
		"platforms": [
			Rect2(ROOM_LEFT, FLOOR_Y, ROOM_RIGHT - ROOM_LEFT, 120),
			Rect2(300, FLOOR_Y - 170, 260, 36),
			Rect2(720, FLOOR_Y - 170, 260, 36),
			Rect2(540, FLOOR_Y - 320, 200, 36),
		],
		"hazards": [],
		"slots": [ Vector2(420, FLOOR_Y - 210), Vector2(840, FLOOR_Y - 210), Vector2(640, FLOOR_Y - 360) ],
		"entry": Vector2(180, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
	{
		"tag": "arena",
		"name": "BLOODLESS YARD",
		"platforms": [
			Rect2(ROOM_LEFT, FLOOR_Y, ROOM_RIGHT - ROOM_LEFT, 120),
			Rect2(240, FLOOR_Y - 200, 160, 36),
			Rect2(880, FLOOR_Y - 200, 160, 36),
		],
		"hazards": [],
		"slots": [ Vector2(420, FLOOR_Y - 40), Vector2(640, FLOOR_Y - 240), Vector2(900, FLOOR_Y - 40) ],
		"entry": Vector2(180, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
	{
		"tag": "platforms",
		"name": "CINDERWORKS",
		"platforms": [
			Rect2(ROOM_LEFT, FLOOR_Y, 460 - ROOM_LEFT, 120),
			Rect2(820, FLOOR_Y, ROOM_RIGHT - 820, 120),
			Rect2(440, FLOOR_Y - 160, 120, 34),
			Rect2(700, FLOOR_Y - 160, 120, 34),
			Rect2(560, FLOOR_Y - 300, 120, 34),
		],
		"hazards": [ Rect2(460, FLOOR_Y + 20, 360, 100) ],
		"slots": [ Vector2(500, FLOOR_Y - 200), Vector2(760, FLOOR_Y - 200), Vector2(640, FLOOR_Y - 340) ],
		"entry": Vector2(180, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
	{
		# Vertical shaft with tall walls — designed for wall slide + wall jump.
		"tag": "chamber",
		"name": "HOLLOW SHAFT",
		"platforms": [
			Rect2(ROOM_LEFT, FLOOR_Y, 320 - ROOM_LEFT, 120),
			Rect2(960, FLOOR_Y, ROOM_RIGHT - 960, 120),
			Rect2(320, FLOOR_Y, 80, 500),   # left wall block
			Rect2(880, FLOOR_Y, 80, 500),   # right wall block
			Rect2(480, FLOOR_Y - 150, 120, 30),
			Rect2(680, FLOOR_Y - 280, 120, 30),
		],
		"walls": [ Rect2(360, 100, 30, 460), Rect2(890, 100, 30, 460) ],  # climbable wall surfaces
		"hazards": [ Rect2(400, FLOOR_Y + 20, 560, 100) ],
		# Keep the first wave clear of the entry ledge.
		"slots": [ Vector2(1100, FLOOR_Y - 40), Vector2(540, FLOOR_Y - 190), Vector2(740, FLOOR_Y - 320) ],
		"entry": Vector2(40, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
	{
		# Two raised side platforms with a central pit — encourages air combat and slamming.
		"tag": "crossfire",
		"name": "GALLOW CROSSING",
		"platforms": [
			Rect2(ROOM_LEFT, FLOOR_Y, 360 - ROOM_LEFT, 120),
			Rect2(920, FLOOR_Y, ROOM_RIGHT - 920, 120),
			Rect2(220, FLOOR_Y - 220, 220, 34),
			Rect2(840, FLOOR_Y - 220, 220, 34),
			Rect2(560, FLOOR_Y - 360, 160, 34),
		],
		"hazards": [ Rect2(360, FLOOR_Y + 20, 560, 100) ],
		"slots": [ Vector2(330, FLOOR_Y - 260), Vector2(950, FLOOR_Y - 260), Vector2(640, FLOOR_Y - 400), Vector2(300, FLOOR_Y - 40) ],
		"entry": Vector2(40, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
]

static var BOSS_TEMPLATE: Dictionary = {
	"tag": "boss",
	"name": "EMBER THRONE",
	"platforms": [ Rect2(ROOM_LEFT, FLOOR_Y, ROOM_RIGHT - ROOM_LEFT, 120) ],
	"hazards": [],
	"slots": [],
	# The knight enters down the hall from the Warden's throne at x 640.
	"entry": Vector2(180, FLOOR_Y - 80),
	"exit": Vector2(640, FLOOR_Y - 80),
}

## Authored encounter waves for the first two route positions. A short breath between
## waves keeps combat readable while still building the gauntlet pressure of the genre.
const OPENING_WAVES := [
	[[EnemyKind.STALKER, EnemyKind.STALKER]],
	[[EnemyKind.STALKER, EnemyKind.HOPPER], [EnemyKind.WISP, EnemyKind.STALKER]],
]

## Enemies per wave for each generated chamber, from the first after the
## opening waves: a steady climb to three full waves just before the throne.
## Deeper chambers reuse the last row.
const WAVE_PLAN := [[2, 3], [2, 4], [2, 3, 3], [2, 3, 4], [3, 4, 4]]

## The chamber where each archetype first appears; the stalker is there from
## the start. A generated chamber opens with its newcomer beside a lone
## stalker, and the game names it (HINTS "debut_<kind>") the first time.
const DEBUTS := {
	EnemyKind.HOPPER: 1, EnemyKind.WISP: 1, EnemyKind.BOMBER: 2, EnemyKind.CROW: 3, EnemyKind.BRUTE: 4,
}

## Authored waves that test a lesson from an earlier chamber. A seeded few of
## the last chambers each stage one as their final wave (see set_piece_for).
## `stagger` spaces the members' first strikes, so dives come in a rhythm.
const SET_PIECES := [
	{ "name": "powder keg", "from_room": 3, "kinds": [EnemyKind.BOMBER, EnemyKind.STALKER, EnemyKind.BOMBER, EnemyKind.STALKER] },
	{ "name": "murder", "from_room": 4, "kinds": [EnemyKind.CROW, EnemyKind.CROW, EnemyKind.CROW], "stagger": 0.7 },
	{ "name": "shieldwall", "from_room": 5, "kinds": [EnemyKind.BRUTE, EnemyKind.WISP, EnemyKind.WISP] },
]

## Threat costs used by the wave generator. Heavier archetypes unlock with depth.
const THREAT_COST := {
	EnemyKind.STALKER: 2.0, EnemyKind.HOPPER: 2.0, EnemyKind.WISP: 2.5, EnemyKind.BRUTE: 4.0, EnemyKind.BOMBER: 3.0, EnemyKind.CROW: 2.5,
}

static func _unlocked_kinds(room_index: int) -> Array:
	var kinds: Array = [EnemyKind.STALKER]
	for kind in DEBUTS:
		if int(DEBUTS[kind]) <= room_index:
			kinds.append(kind)
	return kinds

## Encounter waves for a route position. The first two rooms are authored so the
## opening curve is stable; deeper rooms follow WAVE_PLAN, open with the
## chamber's debut, close with its set piece (if any), and fill the rest from
## the room's seeded RNG, so a seed always reproduces the same gauntlet.
static func generate_waves(room_index: int, rng: RandomNumberGenerator, set_piece: Dictionary = {}) -> Array:
	if room_index < OPENING_WAVES.size():
		# Copied: rooms append a Trial wave to the array they are handed.
		return (OPENING_WAVES[room_index] as Array).duplicate(true)
	var plan: Array = WAVE_PLAN[mini(room_index - OPENING_WAVES.size(), WAVE_PLAN.size() - 1)]
	var kinds := _unlocked_kinds(room_index)
	var debut = DEBUTS.find_key(room_index)
	var staged: Array = set_piece.get("kinds", [])
	var waves: Array = []
	for w in range(plan.size()):
		if w == 0 and debut != null:
			waves.append([debut, EnemyKind.STALKER])
		elif w == plan.size() - 1 and not staged.is_empty():
			waves.append(staged.duplicate())
		else:
			waves.append(_roll_wave(int(plan[w]), room_index, kinds, rng, waves + [staged]))
	return waves

## One wave of `size` foes drawn from `kinds`. A draw that would break a
## composition rule or the wave's threat cap becomes a stalker, so the wave
## keeps its size and stays readable. `room` holds the chamber's other waves.
static func _roll_wave(size: int, room_index: int, kinds: Array, rng: RandomNumberGenerator, room: Array) -> Array:
	var cap := 2.6 * float(size) + 0.5 * float(room_index)
	var wave: Array = []
	var threat := 0.0
	for i in range(size):
		var kind: int = kinds[rng.randi_range(0, kinds.size() - 1)]
		if threat + float(THREAT_COST[kind]) > cap or not _fits(kind, wave, room, room_index):
			kind = EnemyKind.STALKER
		wave.append(kind)
		threat += float(THREAT_COST[kind])
	return wave

## Composition rules: one bomber and one brute a wave, never more than two
## flyers at once (two divers is a coin flip, not a read), and at most two
## brutes a chamber, one where they debut.
static func _fits(kind: int, wave: Array, room: Array, room_index: int) -> bool:
	match kind:
		EnemyKind.BOMBER:
			return not wave.has(kind)
		EnemyKind.WISP, EnemyKind.CROW:
			return wave.count(EnemyKind.WISP) + wave.count(EnemyKind.CROW) < 2
		EnemyKind.BRUTE:
			var in_room := 0
			for other: Array in room:
				in_room += other.count(kind)
			return not wave.has(kind) and in_room < (1 if int(DEBUTS[kind]) == room_index else 2)
	return true

## The set piece a chamber stages this descent, or {}. Seeded by the run so a
## replayed seed matches; no piece repeats in a descent, and none comes before
## the chamber it may first appear in.
static func set_piece_for(room_index: int, run_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var staged := {}
	# Latest-opening piece first, so every piece still finds a chamber of its own.
	for i in range(SET_PIECES.size() - 1, -1, -1):
		var piece: Dictionary = SET_PIECES[i]
		var open: Array = range(int(piece.from_room), ROOMS_BEFORE_BOSS + 1).filter(func(r): return not staged.has(r))
		staged[open[rng.randi_range(0, open.size() - 1)]] = piece
	return staged.get(room_index, {})

## An elite's oath (ELITE_OATHS), drawn from the chamber's RNG from
## OATH_FROM_ROOM on; "" before then. A kindled trail burns along the ground,
## so flyers never swear it.
static func roll_oath(kind: int, room_index: int, rng: RandomNumberGenerator) -> String:
	if room_index < OATH_FROM_ROOM:
		return ""
	var oaths: Array = ELITE_OATHS.filter(func(o): return o != "kindled" or not (kind == EnemyKind.WISP or kind == EnemyKind.CROW))
	return str(oaths[rng.randi_range(0, oaths.size() - 1)])

static func room_name(template: Dictionary) -> String:
	return str(template.get("name", str(template.get("tag", "unknown")).to_upper()))

# --- Controls ---
## The single source of truth for the controls screen AND the rebinding list.
## Both render from the LIVE input map, so neither can drift from what the game
## actually does. Order is the order the player sees.
const CONTROLS_ROWS := [
	{ "label": "MOVE LEFT",  "action": "move_left" },
	{ "label": "MOVE RIGHT", "action": "move_right" },
	{ "label": "JUMP",       "action": "jump" },
	{ "label": "BLADE",      "action": "attack" },
	{ "label": "DASH",       "action": "dash" },
	{ "label": "LANCE",      "action": "special" },
	{ "label": "IGNITE",     "action": "ignite" },
	{ "label": "PARRY",      "action": "parry" },
	{ "label": "FLASK",      "action": "heal" },
	{ "label": "ENTER RIFT", "action": "interact" },
	{ "label": "PAUSE",      "action": "pause" },
]
## Composites that are not actions of their own, shown as a hint under the table.
const CONTROLS_HINTS := "AIR SLAM:  DOWN + BLADE      ·      GAMEPAD IS ALWAYS LIVE"

# --- First-run teaching ---
## One-time contextual lessons. Each is shown the first time the situation that
## makes the mechanic useful actually arises, so the player learns by playing
## rather than by reading a bindings list and guessing what matters.
const HINTS := {
	"parry": "S — PARRY.  Time it against a winding strike to deflect it.",
	"riposte": "Deflected!  A counter is banked — press J to riposte.",
	"slam": "DOWN + J in the air — down-slam onto a crowd.",
	"wall_jump": "Against a wall, jump again to kick away.",
	"flask": "F — FLASK.  One charge returns with every chamber cleared.",
	# Each archetype, named the first time the descent shows it (DEBUTS).
	"debut_hopper": "HOPPER.  It leaps at you from afar: step back, then cut it as it lands.",
	"debut_wisp": "WISP.  It shoots from above: parry the bolt back, or climb to reach it.",
	"debut_bomber": "POWDER PILGRIM.  Dash clear of its ring, or cut it down before it lights.",
	"debut_crow": "CARRION CROW.  Watch its dashed line, then sidestep or parry the dive.",
	"debut_brute": "IRON PENITENT.  Its shield faces you: strike from behind, or break its guard.",
}

# --- Vows (unlocked by the first victory) ---
## Burdens sworn before a descent. Each makes the keep harsher and pays for it
## in score and cells. `score` is the added score multiplier.
const VOWS := [
	{ "id": "v_embers", "title": "Vow of Embers",     "desc": "Enemies strike 35% harder.",                  "score": 0.30 },
	{ "id": "v_thirst", "title": "Vow of Thirst",     "desc": "Cleared chambers return no flask charges.",   "score": 0.25 },
	{ "id": "v_gilded", "title": "Vow of the Gilded", "desc": "Every chamber carries an elite.",             "score": 0.25 },
	{ "id": "v_haste",  "title": "Vow of Haste",      "desc": "Enemies move and wind up faster.",            "score": 0.30 },
	{ "id": "v_pyre",   "title": "Vow of the Pyre",   "desc": "The Warden rises already ignited, and hardier.", "score": 0.30 },
]

static func vow_score_multiplier(sworn: Array) -> float:
	var m := 1.0
	for v in VOWS:
		if sworn.has(v.id):
			m += float(v.score)
	return m

# --- Epitaphs ---
## The line under the verdict. A run that ends differently reads differently;
## the pick is seeded by the run so a replayed seed says the same thing.
const EPITAPHS := [
	"Ash remembers every attempt.",
	"The keep keeps what it takes.",
	"A crown of fire. A crown of cinders.",
	"The flame gutters. It does not go out.",
	"Every knight before you fell here too.",
	"Even embers remember the shape of the fire.",
	"The descent is patient.",
	"Somewhere below, the throne grows warmer.",
]
const EPITAPH_THRONE := "The Warden stokes its throne with your flame."
const VICTORY_LINES := [
	"The keep falls silent, but the descent is never the same twice.",
	"The throne is cold. For now.",
	"Your flame burns where the Warden's did.",
	"The Ember Throne answers to no one tonight.",
]

# --- The finale ("Strike the Set") ---
## Every string the ending shows. Headings stay within 34 characters so a card
## never wraps; the credit row can be blanked without touching the director.
const FINALE_TEXT := {
	"keep": "THE KEEP KEEPS WHAT IT TAKES.",
	"back": "TONIGHT, IT GIVES THEM BACK.",
	"cold": "THE THRONE IS COLD.",
	"again": "AGAIN IT FALLS. AGAIN THEY RISE.",
	"hold": "HOLD",
	"ignite": "IGNITE",
	"let_go": "LET GO",
	"skip": "HOLD %s TO SKIP",
	"bill_title": "THE DESCENT",
	"bill_sub": "IN EIGHT CHAMBERS · EVERY ATTEMPT REMEMBERED",
	"fallen": "THE FALLEN",
	"warden": "THE EMBER WARDEN",
	"warden_gloss": "Keeper of a cold throne. For now.",
	"warden_gloss_oath": "Keeper of a cold throne.",
	"knight": "THE KNIGHT",
	"knight_gloss": "Who carried their flames.",
	"knight_gloss_oath": "Who carried their flames, and every vow.",
	"sworn": "SWORN",
	"house": "THE HOUSE",
	"credit": "MADE BY BINDU · Every shape cut in code. Every sound struck from nothing.",
	"curtain": "THE CURTAIN FALLS.",
	"curtain_answer": "The flame does not.",
	"took_nothing": "The keep took nothing from you.",
	"vows_awaken": "VOWS AWAKEN AT THE FORGE.",
}
## The ending answers the last thing a death screen said to the player.
const EPITAPH_ANSWERS := {
	"Ash remembers every attempt.": "Every one of them took a bow.",
	"The keep keeps what it takes.": "Tonight, it gave them back.",
	"A crown of fire. A crown of cinders.": "Neither. A crown they lent you.",
	"The flame gutters. It does not go out.": "It did not go out.",
	"Every knight before you fell here too.": "Every one of them stood up.",
	"Even embers remember the shape of the fire.": "And the fire remembered them.",
	"The descent is patient.": "So were you.",
	"Somewhere below, the throne grows warmer.": "Tonight it burns for them.",
	"The Warden stokes its throne with your flame.": "Your flame is your own again.",
}
## The title's bell question as [onset in seconds of held time, MIDI note]: the
## opening contour of the title melody, still in D minor, ending on the C#.
const GATHER_LINE := [[0.00, 69], [0.88, 74], [1.32, 72], [1.54, 69], [1.76, 65], [2.64, 64], [3.52, 73]]
## Pitch ratios over D for the pop-up folds (D-minor pentatonic) and the
## homecoming (D-major pentatonic).
const FOLD_MINOR := [1.0, 1.1892, 1.3348, 1.4983, 1.7818, 2.0]
const FOLD_MAJOR := [1.0, 1.1225, 1.2599, 1.4983, 1.6818]
## Crowd sizes: the stage holds 16 fallen; a deathless win raises five elders;
## a veteran whose deaths predate the count sees twelve.
const FALLEN_CAP := 16
const ELDERS := 5
const UNCOUNTED_CROWD := 12
const HOUSE_CAP := 23
const NUMBER_WORDS := [
	"zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
	"eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
]
const ORDINAL_WORDS := [
	"", "FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH", "SIXTH", "SEVENTH", "EIGHTH", "NINTH", "TENTH",
	"ELEVENTH", "TWELFTH", "THIRTEENTH", "FOURTEENTH", "FIFTEENTH", "SIXTEENTH", "SEVENTEENTH", "EIGHTEENTH", "NINETEENTH", "TWENTIETH",
]

## The boon definition for an id, or {} when the id is unknown.
static func upgrade_def(id: String) -> Dictionary:
	for u in UPGRADES:
		if str(u.id) == id:
			return u
	return {}

## Spelled out to twenty, digits after: the playbill reads as print, not a HUD.
static func number_word(n: int) -> String:
	return NUMBER_WORDS[n] if n >= 0 and n < NUMBER_WORDS.size() else str(n)

## "THE FOURTH FLAME": the victory panel's kicker counts wins as flames.
static func flame_ordinal(n: int) -> String:
	if n > 0 and n < ORDINAL_WORDS.size():
		return "THE %s FLAME" % ORDINAL_WORDS[n]
	var suffix := "TH"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["TH", "ST", "ND", "RD", "TH", "TH", "TH", "TH", "TH", "TH"][n % 10]
	return "THE %d%s FLAME" % [n, suffix]

## The Warden you meet was mended at your last curtain, and says so.
static func boss_subtitle(victories: int, oath: bool) -> String:
	if oath:
		return "Its wires were cut. It rose anyway."
	match victories:
		0: return "Keeper of the Ember Throne"
		1: return "Felled once. Mended."
		2: return "Felled twice. Mended."
	return "Felled %d times. Mended." % victories

## THE FALLEN's gloss. An unknown count (a save older than the count) is said
## honestly rather than guessed.
static func fallen_gloss(falls: int, unknown: bool) -> String:
	if unknown:
		return "Uncounted. Each of them was you."
	match falls:
		0: return "Those before you. Not one was you."
		1: return "One knight. It was you."
	return "%d knights. Each of them was you." % falls

## THE HOUSE's gloss for the past victors watching; empty on a first win.
static func house_gloss(past: int) -> String:
	if past <= 0:
		return ""
	if past == 1:
		return "One flame, watching."
	if past == 9:
		return "Nine flames stand for the tenth."
	var count := number_word(past).capitalize()
	return "%s flames, %s." % [count, "watching" if past < 9 else "standing"]

## The final card: the last epitaph quoted, then the ending's answer to it.
## A deathless run is told it lost nothing; with nothing to answer, the curtain line.
static func finale_answer(last_epitaph: String, falls_since: int, unknown: bool) -> Dictionary:
	if falls_since == 0 and not unknown:
		return { "quote": "", "answer": FINALE_TEXT.took_nothing }
	if EPITAPH_ANSWERS.has(last_epitaph):
		return { "quote": "“%s”" % last_epitaph, "answer": EPITAPH_ANSWERS[last_epitaph] }
	return { "quote": FINALE_TEXT.curtain, "answer": FINALE_TEXT.curtain_answer }

## Which cut of the ending plays: "full" the first time and for the first
## Fivefold Oath, "abridged" for the 2nd and 3rd or a new milestone, else "brief".
static func finale_tier(seen_before: int, milestone: String) -> String:
	if seen_before <= 0 or milestone == "oath":
		return "full"
	if seen_before <= 2 or not milestone.is_empty():
		return "abridged"
	return "brief"

# --- Cells meta-progression (currency kept across runs, Dead Cells-style) ---
## Ranked relics. `costs[r]` buys rank r+1; `value` applies once per rank owned.
## Costs climb so cells keep meaning something long after the first few runs.
const META_UPGRADES: Array = [
	{ "id": "m_max_hp",  "title": "Ember Soul",    "desc": "+10 starting health per rank.",       "costs": [5, 12, 22, 36, 55], "kind": "max_hp",        "value": 10.0 },
	{ "id": "m_dmg",     "title": "Sharpened",     "desc": "+6% melee damage per rank.",          "costs": [7, 16, 28, 44, 64], "kind": "dmg_mul",       "value": 0.06 },
	{ "id": "m_flask",   "title": "Potion Belt",   "desc": "+1 flask charge per rank.",           "costs": [8, 30],             "kind": "flask",         "value": 1.0 },
	{ "id": "m_speed",   "title": "Quickened",     "desc": "+4% move speed per rank.",            "costs": [6, 14, 26],         "kind": "speed_mul",     "value": 0.04 },
	{ "id": "m_special", "title": "Arcane Spark",  "desc": "Start each run with +20 Graveflame per rank.", "costs": [6, 14, 26], "kind": "special_start", "value": 20.0 },
	{ "id": "m_kindled", "title": "Kindled Blood", "desc": "Begin every run carrying a common boon.", "costs": [30],          "kind": "start_boon",    "value": 1.0 },
	{ "id": "m_seer",    "title": "Seer's Eye",    "desc": "Boon offers show a fourth choice.",    "costs": [45],             "kind": "offer_count",   "value": 1.0 },
	{ "id": "m_tithe",   "title": "Tithe",         "desc": "+25% cells from every source per rank.", "costs": [20, 50],        "kind": "cell_mul",      "value": 0.25 },
]

static func meta_def(id: String) -> Dictionary:
	for u in META_UPGRADES:
		if str(u.id) == id:
			return u
	return {}

static func meta_max_rank(u: Dictionary) -> int:
	return (u.costs as Array).size()

## Cost of the next rank, or -1 when the relic is mastered.
static func meta_next_cost(u: Dictionary, rank: int) -> int:
	var costs: Array = u.costs
	return int(costs[rank]) if rank < costs.size() else -1
