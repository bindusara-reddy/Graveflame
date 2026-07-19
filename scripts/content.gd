class_name Content
extends RefCounted
## Immutable tuning, room templates, enemy stats, combo data, and upgrade defs.

# --- Physics layers (must match project.godot) ---
const L_WORLD := 1
const L_PLAYER_BODY := 2
const L_ENEMY_BODY := 3
const L_PLAYER_HURT := 4
const L_ENEMY_HURT := 5
const L_PLAYER_ATK := 6
const L_ENEMY_ATK := 7
const L_TRIGGER := 8

# --- World / camera ---
const VIEW_W := 1280
const VIEW_H := 720
const TILE := 64
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
const P_BODY_W := 26.0
const P_BODY_H := 54.0
const P_SPECIAL_MAX := 100.0
const P_SPECIAL_GAIN := 9.0
const P_SPECIAL_COST := 50.0

# --- Down-slam (air attack) ---
const P_SLAM_DAMAGE := 30.0
const P_SLAM_KNOCK := 520.0
const P_SLAM_RADIUS := 110.0
const P_SLAM_VEL := 1500.0
const P_SLAM_RECOVER := 0.28

# --- Wall slide / wall jump ---
const P_WALL_SLIDE_SPEED := 120.0
const P_WALL_JUMP_VEL := Vector2(560.0, -760.0)
const P_WALL_STICK_TIME := 0.12

# --- Parry (timed block) ---
const PARRY_INPUT := "parry"
const PARRY_WINDOW := 0.16       # active deflect window
const PARRY_COOLDOWN := 0.5
const PARRY_RANGE := 78.0
const PARRY_DAMAGE := 18.0       # damage dealt to deflected melee enemy
const PARRY_PROJECTILE_BOOST := 1.6  # deflected projectile damage multiplier

# --- Healing flask (Dead Cells-style) ---
const FLASK_MAX := 3
const FLASK_HEAL := 45.0
const FLASK_REFILL_ON_CLEAR := true  # refill to max when a room is cleared

# --- Combo: three swings. Times in seconds. ---
const COMBO := [
	{ "name": "cut",   "startup": 0.06, "active": 0.08, "recover": 0.16, "damage": 12.0, "knock": 220.0, "range": 64.0,  "arc": 1.6,  "window": 0.32 },
	{ "name": "cleave","startup": 0.08, "active": 0.10, "recover": 0.22, "damage": 16.0, "knock": 300.0, "range": 74.0,  "arc": 1.8,  "window": 0.34 },
	{ "name": "finish","startup": 0.10, "active": 0.12, "recover": 0.30, "damage": 24.0, "knock": 460.0, "range": 84.0,  "arc": 2.05, "window": 0.0  },
]
const COMBO_RESET := 0.55

# --- Enemy archetypes ---
enum EnemyKind { STALKER, HOPPER, WISP, BRUTE, BOMBER }
const ENEMY := {
	EnemyKind.STALKER: { "hp": 40.0,  "speed": 150.0, "damage": 14.0, "knock": 240.0, "cd": 1.3, "windup": 0.45, "recover": 0.5,  "score": 12, "w": 34.0, "h": 46.0, "color": Color("c44b3f") },
	EnemyKind.HOPPER:  { "hp": 28.0,  "speed": 210.0, "damage": 12.0, "knock": 200.0, "cd": 1.6, "windup": 0.30, "recover": 0.4,  "score": 14, "w": 32.0, "h": 38.0, "color": Color("d98c2b") },
	EnemyKind.WISP:    { "hp": 20.0,  "speed": 120.0, "damage": 10.0, "knock": 160.0, "cd": 2.0, "windup": 0.55, "recover": 0.45, "score": 18, "w": 30.0, "h": 30.0, "color": Color("7b6bd1") },
	EnemyKind.BRUTE:   { "hp": 80.0,  "speed": 95.0,  "damage": 20.0, "knock": 360.0, "cd": 1.8, "windup": 0.60, "recover": 0.65, "score": 24, "w": 48.0, "h": 58.0, "color": Color("5a7a3a"), "shielded": true, "shield_hp": 30.0 },
	EnemyKind.BOMBER:  { "hp": 22.0,  "speed": 170.0, "damage": 26.0, "knock": 100.0, "cd": 1.4, "windup": 0.80, "recover": 0.0,  "score": 20, "w": 34.0, "h": 36.0, "color": Color("b85c2e"), "explodes": true, "fuse": 0.8, "blast_radius": 90.0 },
}
const ENEMY_RANGED := EnemyKind.WISP
const WISP_SHOT_SPEED := 460.0
const WISP_SHOT_LIFE := 2.4
const WISP_SHOT_DAMAGE := 10.0
const WISP_RANGE := 520.0

# --- Boss ---
const BOSS_HP := 420.0
const BOSS_DAMAGE := 22.0
const BOSS_SPEED := 170.0
const BOSS_W := 70.0
const BOSS_H := 96.0
const BOSS_COLOR := Color("8a2f3d")
const BOSS_SHOT_SPEED := 380.0
const BOSS_SHOT_DAMAGE := 14.0
const BOSS_PHASE2_AT := 0.5

# --- Run structure ---
const ROOMS_BEFORE_BOSS := 4
const UPGRADES_PER_OFFER := 3

# --- Palettes ---
const PAL := {
	"bg_top": Color("1a1426"),
	"bg_bot": Color("0c0a14"),
	"platform": Color("2b2436"),
	"platform_edge": Color("4a3f5e"),
	"hazard": Color("6a2230"),
	"player": Color("e8e0d0"),
	"player_accent": Color("ff7a18"),
	"enemy_hurt": Color("ffffff"),
	"attack": Color("ffd23f"),
	"special": Color("7fd4ff"),
	"exit": Color("5fe8a8"),
	"text": Color("e8e0d0"),
	"text_dim": Color("9a8fa6"),
}

# --- Upgrades ---
static var UPGRADES: Array = [
	{ "id": "vitality",  "title": "Vitality",   "desc": "+25 max HP and full heal.",        "kind": "max_hp",     "value": 25.0 },
	{ "id": "swift",     "title": "Swift Feet", "desc": "+12% move speed.",                 "kind": "speed_mul",  "value": 0.12 },
	{ "id": "power",     "title": "Power",      "desc": "+20% melee damage.",               "kind": "dmg_mul",    "value": 0.20 },
	{ "id": "edge",      "title": "Razor Edge", "desc": "+35% combo finisher damage.",      "kind": "finish_mul", "value": 0.35 },
	{ "id": "magnet",    "title": "Magnetism",  "desc": "+40% special meter gain.",         "kind": "special_mul","value": 0.40 },
	{ "id": "warden",    "title": "Warden",     "desc": "+0.4s hurt invulnerability.",      "kind": "iframes",    "value": 0.4 },
	{ "id": "surge",     "title": "Surge",      "desc": "Special pierces and +20% damage.", "kind": "special_pierce", "value": 0.20 },
	{ "id": "leech",     "title": "Leech",      "desc": "Heal 3 HP per enemy hit.",         "kind": "lifesteal",  "value": 3.0 },
	{ "id": "ember",     "title": "Ember Heart","desc": "Heal 20 HP now.",                  "kind": "heal",       "value": 20.0 },
	{ "id": "slam",      "title": "Crater",     "desc": "Down-slam deals +60% damage & wider blast.", "kind": "slam_mul", "value": 0.60 },
	{ "id": "parry",     "title": "Riposte",    "desc": "Parry window +50% and deflects deal +12 dmg.", "kind": "parry", "value": 12.0 },
	{ "id": "flask",     "title": "Witch Flask","desc": "+1 flask charge (heals between rooms).", "kind": "flask_charge", "value": 1.0 },
	{ "id": "dashmaster","title": "Dashmaster", "desc": "Dash cooldown halved, longer i-frames.", "kind": "dash_master", "value": 0.5 },
]

## Room templates. Each defines platforms (Rect2 in pixels), hazards, spawn slots, entry, exit.
static var ROOM_TEMPLATES: Array = [
	{
		"tag": "intro",
		"platforms": [ Rect2(ROOM_LEFT, FLOOR_Y, ROOM_RIGHT - ROOM_LEFT, 120) ],
		"hazards": [],
		"slots": [ Vector2(380, FLOOR_Y - 40), Vector2(900, FLOOR_Y - 40) ],
		"entry": Vector2(160, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
	{
		"tag": "gap",
		"platforms": [
			Rect2(ROOM_LEFT, FLOOR_Y, 620, 120),
			Rect2(860, FLOOR_Y, ROOM_RIGHT - 860, 120),
			Rect2(680, FLOOR_Y - 180, 140, 40),
		],
		"hazards": [ Rect2(620, FLOOR_Y + 20, 240, 100) ],
		"slots": [ Vector2(460, FLOOR_Y - 40), Vector2(720, FLOOR_Y - 220), Vector2(1040, FLOOR_Y - 40) ],
		"entry": Vector2(180, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
	{
		"tag": "tiers",
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
		"platforms": [
			Rect2(ROOM_LEFT, FLOOR_Y, 460, 120),
			Rect2(820, FLOOR_Y, ROOM_RIGHT - 820, 120),
			Rect2(440, FLOOR_Y - 160, 120, 34),
			Rect2(700, FLOOR_Y - 160, 120, 34),
			Rect2(560, FLOOR_Y - 300, 120, 34),
		],
		"hazards": [ Rect2(460, FLOOR_Y + 20, 360, 100) ],
		"slots": [ Vector2(560, FLOOR_Y - 200), Vector2(820, FLOOR_Y - 200), Vector2(640, FLOOR_Y - 340) ],
		"entry": Vector2(180, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
	{
		# Vertical shaft with tall walls — designed for wall slide + wall jump.
		"tag": "chamber",
		"platforms": [
			Rect2(ROOM_LEFT, FLOOR_Y, 320, 120),
			Rect2(960, FLOOR_Y, ROOM_RIGHT - 960, 120),
			Rect2(320, FLOOR_Y, 80, 500),   # left wall block
			Rect2(880, FLOOR_Y, 80, 500),   # right wall block
			Rect2(480, FLOOR_Y - 150, 120, 30),
			Rect2(680, FLOOR_Y - 280, 120, 30),
		],
		"walls": [ Rect2(360, 100, 30, 460), Rect2(890, 100, 30, 460) ],  # climbable wall surfaces
		"hazards": [ Rect2(400, FLOOR_Y + 20, 560, 100) ],
		"slots": [ Vector2(240, FLOOR_Y - 40), Vector2(540, FLOOR_Y - 190), Vector2(740, FLOOR_Y - 320), Vector2(1100, FLOOR_Y - 40) ],
		"entry": Vector2(180, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
	{
		# Two raised side platforms with a central pit — encourages air combat and slamming.
		"tag": "crossfire",
		"platforms": [
			Rect2(ROOM_LEFT, FLOOR_Y, 360, 120),
			Rect2(920, FLOOR_Y, ROOM_RIGHT - 920, 120),
			Rect2(220, FLOOR_Y - 220, 220, 34),
			Rect2(840, FLOOR_Y - 220, 220, 34),
			Rect2(560, FLOOR_Y - 360, 160, 34),
		],
		"hazards": [ Rect2(360, FLOOR_Y + 20, 560, 100) ],
		"slots": [ Vector2(330, FLOOR_Y - 260), Vector2(950, FLOOR_Y - 260), Vector2(640, FLOOR_Y - 400), Vector2(120, FLOOR_Y - 40) ],
		"entry": Vector2(180, FLOOR_Y - 80),
		"exit": Vector2(1180, FLOOR_Y - 80),
	},
]

static var BOSS_TEMPLATE: Dictionary = {
	"tag": "boss",
	"platforms": [ Rect2(ROOM_LEFT, FLOOR_Y, ROOM_RIGHT - ROOM_LEFT, 120) ],
	"hazards": [],
	"slots": [],
	"entry": Vector2(640, FLOOR_Y - 80),
	"exit": Vector2(640, FLOOR_Y - 80),
}

## Encounter budgets per room index (room 0 is intro, light).
static func encounter_for_room(room_index: int) -> Array:
	# returns array of EnemyKind
	match room_index:
		0: return [EnemyKind.STALKER, EnemyKind.STALKER]
		1: return [EnemyKind.STALKER, EnemyKind.HOPPER, EnemyKind.WISP]
		2: return [EnemyKind.HOPPER, EnemyKind.HOPPER, EnemyKind.WISP, EnemyKind.STALKER]
		3: return [EnemyKind.WISP, EnemyKind.HOPPER, EnemyKind.STALKER, EnemyKind.BRUTE, EnemyKind.BOMBER]
		4: return [EnemyKind.BRUTE, EnemyKind.BOMBER, EnemyKind.WISP, EnemyKind.HOPPER, EnemyKind.STALKER]
		_: return [EnemyKind.STALKER, EnemyKind.HOPPER, EnemyKind.WISP, EnemyKind.BRUTE]

# --- Cells meta-progression (currency kept across runs, Dead Cells-style) ---
const META_UPGRADES: Array = [
	{ "id": "m_max_hp",   "title": "Ember Soul",   "desc": "+10 starting HP.",          "cost": 5,  "kind": "max_hp",    "value": 10.0 },
	{ "id": "m_flask",    "title": "Potion Belt",  "desc": "+1 starting flask charge.", "cost": 8,  "kind": "flask",     "value": 1.0 },
	{ "id": "m_speed",    "title": "Quickened",    "desc": "+8% starting move speed.",  "cost": 6,  "kind": "speed_mul", "value": 0.08 },
	{ "id": "m_dmg",      "title": "Sharpened",    "desc": "+10% starting melee dmg.",  "cost": 7,  "kind": "dmg_mul",   "value": 0.10 },
	{ "id": "m_special",  "title": "Arcane Spark", "desc": "Start each run with 25 special.", "cost": 6, "kind": "special_start", "value": 25.0 },
]
