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

# --- World / camera ---
const VIEW_W := 1280
const VIEW_H := 720
## Locked camera zoom for the approval frame: a ~15% tighter frame so the
## fighters read at Blasphemous scale without losing duel spacing.
const CAM_ZOOM := 1.15
## World pixels per rendered pixel. The whole frame renders vector-native at
## full resolution: no pixel grid, no nearest filtering, smooth sub-pixel art.
const PIXEL_SCALE := 1.0
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
## A confirmed deflection banks one short-lived, committed counterattack.
const RIPOSTE_WINDOW := 1.2
const RIPOSTE := {
	"name": "riposte", "startup": 0.06, "active": 0.12, "recover": 0.24,
	"damage": 34.0, "knock": 540.0, "range": 112.0, "arc": 1.4,
	"window": 0.0, "lunge": 360.0,
}

# --- Healing flask (Dead Cells-style) ---
const FLASK_MAX := 3
const FLASK_HEAL := 45.0
const FLASK_REFILL_ON_CLEAR := true  # refill to max when a room is cleared

# --- Combo: three swings. Times in seconds. ---
const COMBO := [
	{ "name": "cut",   "startup": 0.06, "active": 0.08, "recover": 0.16, "damage": 12.0, "knock": 220.0, "range": 64.0,  "arc": 1.6,  "window": 0.32, "lunge": 150.0 },
	{ "name": "cleave","startup": 0.08, "active": 0.10, "recover": 0.20, "damage": 16.0, "knock": 300.0, "range": 74.0,  "arc": 1.8,  "window": 0.34, "lunge": 185.0 },
	{ "name": "finish","startup": 0.10, "active": 0.12, "recover": 0.26, "damage": 24.0, "knock": 460.0, "range": 84.0,  "arc": 2.05, "window": 0.0, "lunge": 235.0 },
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
	# Backdrop: deep void above, crypt navy through the arches, a faint warm
	# horizon at the floor line, then the pit falls away to near-black.
	"bg_top": Color("07050b"),
	"bg_mid": Color("130d21"),
	"bg_bot": Color("1a112b"),
	"bg_pit": Color("050308"),
	"tyrian": Color("221538"),
	"mortar": Color("312347"),
	"slate": Color("5e4b75"),
	"rim": Color("7e639e"),
	"platform": Color("1f1430"),
	"platform_edge": Color("4d3866"),
	"hazard": Color("6a2230"),
	"player": Color("e8e0d0"),
	"player_accent": Color("ff7a18"),
	"enemy_hurt": Color("ffffff"),
	"attack": Color("ffa827"),
	"flame_gold": Color("ffa827"),
	"core_orange": Color("ff5500"),
	"ember": Color("ff2a00"),
	"special": Color("7fd4ff"),
	"exit": Color("2be4c8"),
	"text": Color("e8e0d0"),
	"text_dim": Color("9a8fa6"),
	"hurt_number": Color("ff6b6b"),
	"heal_number": Color("2be4c8"),
}

# --- Depth moods: the keep warms from a cold crypt to the ember throne ---
## Each keyframe is a full palette; mood_for() blends between them by route progress.
const MOODS := [
	{
		"name": "crypt", "ambient": Color(0.5, 0.56, 0.78), "bg_top": Color("060812"), "bg_mid": Color("0e1526"), "bg_bot": Color("172238"), "pit": Color("04060c"),
		"fog": Color("1a2440"), "stone": Color("222c44"), "wall": Color("141c30"), "edge": Color("2a3652"), "spire": Color("090c18"),
		"tile_tint": Color(1.0, 1.0, 1.0), "layer_tint": Color(1.0, 1.0, 1.0),
		"torch": Color("ffa827"), "glow": Color(0.85, 0.25, 0.08), "moon": Color("c9d2ee"), "moon_alpha": 0.9,
		"banner": Color("1d3a45"), "glass": Color("3a7f9a"), "stars": 1.0, "ember_seep": 0.0, "moss": 0.8,
	},
	{
		"name": "forge", "ambient": Color(0.7, 0.52, 0.46), "tile_tint": Color(1.08, 0.86, 0.72), "layer_tint": Color(1.05, 0.84, 0.7), "bg_top": Color("0a0509"), "bg_mid": Color("1d0d16"), "bg_bot": Color("2b1412"), "pit": Color("0a0405"),
		"fog": Color("3a1410"), "stone": Color("2a1522"), "wall": Color("1e0f18"), "edge": Color("35192a"), "spire": Color("120710"),
		"torch": Color("ff7a18"), "glow": Color(1.0, 0.4, 0.08), "moon": Color("ff9a4a"), "moon_alpha": 0.7,
		"banner": Color("4a2a12"), "glass": Color("c9662a"), "stars": 0.35, "ember_seep": 0.6, "moss": 0.2,
	},
	{
		"name": "throne", "ambient": Color(0.72, 0.42, 0.46), "tile_tint": Color(1.12, 0.72, 0.68), "layer_tint": Color(1.1, 0.68, 0.66), "bg_top": Color("0b0407"), "bg_mid": Color("200a11"), "bg_bot": Color("35101a"), "pit": Color("0c0406"),
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
	{ "id": "surge",     "title": "Surge",      "desc": "Lance pierces and +20% damage.",   "kind": "special_pierce", "value": 0.20, "rarity": "rare", "unique": true },
	{ "id": "leech",     "title": "Leech",      "desc": "Heal 3 HP per enemy hit.",         "kind": "lifesteal",  "value": 3.0, "rarity": "rare" },
	{ "id": "ember",     "title": "Ember Heart","desc": "Heal 20 HP now.",                  "kind": "heal",       "value": 20.0, "rarity": "common" },
	{ "id": "slam",      "title": "Crater",     "desc": "Down-slam deals +60% damage & wider blast.", "kind": "slam_mul", "value": 0.60, "rarity": "rare" },
	{ "id": "parry",     "title": "Riposte",    "desc": "Parry window +50% and deflects deal +12 dmg.", "kind": "parry", "value": 12.0, "rarity": "rare" },
	{ "id": "flask",     "title": "Witch Flask","desc": "+1 flask charge (refills between rooms).", "kind": "flask_charge", "value": 1.0, "rarity": "rare" },
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
			Rect2(ROOM_LEFT, FLOOR_Y, 620, 120),
			Rect2(860, FLOOR_Y, ROOM_RIGHT - 860, 120),
			Rect2(680, FLOOR_Y - 180, 140, 40),
		],
		"hazards": [ Rect2(620, FLOOR_Y + 20, 240, 100) ],
		"slots": [ Vector2(300, FLOOR_Y - 40), Vector2(720, FLOOR_Y - 220), Vector2(1040, FLOOR_Y - 40) ],
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
		"name": "HOLLOW SHAFT",
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
			Rect2(ROOM_LEFT, FLOOR_Y, 360, 120),
			Rect2(920, FLOOR_Y, ROOM_RIGHT - 920, 120),
			Rect2(220, FLOOR_Y - 220, 220, 34),
			Rect2(840, FLOOR_Y - 220, 220, 34),
			Rect2(560, FLOOR_Y - 360, 160, 34),
		],
		"hazards": [ Rect2(360, FLOOR_Y + 20, 560, 100) ],
		"slots": [ Vector2(330, FLOOR_Y - 260), Vector2(950, FLOOR_Y - 260), Vector2(640, FLOOR_Y - 400), Vector2(120, FLOOR_Y - 40) ],
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
	"entry": Vector2(640, FLOOR_Y - 80),
	"exit": Vector2(640, FLOOR_Y - 80),
}

## Authored encounter waves per route position. A short breath between waves keeps
## combat readable while still building the gauntlet pressure of the genre.
static func encounter_waves_for_room(room_index: int) -> Array:
	match room_index:
		0: return [[EnemyKind.STALKER, EnemyKind.STALKER]]
		1: return [[EnemyKind.STALKER, EnemyKind.HOPPER], [EnemyKind.WISP, EnemyKind.STALKER]]
		2: return [[EnemyKind.HOPPER, EnemyKind.WISP], [EnemyKind.HOPPER, EnemyKind.STALKER]]
		3: return [[EnemyKind.WISP, EnemyKind.STALKER], [EnemyKind.BRUTE, EnemyKind.BOMBER]]
		4: return [[EnemyKind.BRUTE, EnemyKind.WISP], [EnemyKind.BOMBER, EnemyKind.HOPPER, EnemyKind.STALKER]]
		5: return [[EnemyKind.BOMBER, EnemyKind.HOPPER, EnemyKind.WISP], [EnemyKind.BRUTE, EnemyKind.STALKER, EnemyKind.WISP]]
		_: return [[EnemyKind.STALKER, EnemyKind.HOPPER], [EnemyKind.WISP, EnemyKind.BRUTE]]

## Threat costs used by the wave generator. Heavier archetypes unlock with depth.
const THREAT_COST := {
	EnemyKind.STALKER: 2.0, EnemyKind.HOPPER: 2.0, EnemyKind.WISP: 2.5, EnemyKind.BRUTE: 4.0, EnemyKind.BOMBER: 3.0,
}
const WAVE_MAX_ENEMIES := 4

static func _unlocked_kinds(room_index: int) -> Array:
	var kinds: Array = [EnemyKind.STALKER, EnemyKind.HOPPER, EnemyKind.WISP]
	if room_index >= 2:
		kinds.append(EnemyKind.BOMBER)
	if room_index >= 3:
		kinds.append(EnemyKind.BRUTE)
	return kinds

## Encounter waves for a route position. The first two rooms are authored so the
## opening curve is stable; deeper rooms are filled from a threat budget with the
## room's seeded RNG, so a seed always reproduces the same gauntlet.
static func generate_waves(room_index: int, rng: RandomNumberGenerator) -> Array:
	if room_index <= 1:
		return encounter_waves_for_room(room_index)
	var wave_count := 3 if room_index >= 4 else 2
	var budget := 5.0 + 2.2 * float(room_index)
	var kinds := _unlocked_kinds(room_index)
	var waves: Array = []
	for w in range(wave_count):
		var wave: Array = []
		# Later waves inside a room are heavier than the opener.
		var wave_budget := budget * (0.8 + 0.2 * float(w))
		var spent := 0.0
		var guard := 0
		while wave.size() < WAVE_MAX_ENEMIES and guard < 32:
			guard += 1
			var kind: int = kinds[rng.randi_range(0, kinds.size() - 1)]
			var cost := float(THREAT_COST[kind])
			if spent + cost > wave_budget and not wave.is_empty():
				break
			# At most one brute and one bomber per wave keeps waves readable.
			if (kind == EnemyKind.BRUTE or kind == EnemyKind.BOMBER) and wave.has(kind):
				continue
			wave.append(kind)
			spent += cost
		if wave.is_empty():
			wave.append(EnemyKind.STALKER)
		waves.append(wave)
	return waves

## Compatibility helper used by tests and tooling that want a flat encounter.
static func encounter_for_room(room_index: int) -> Array:
	var out: Array = []
	for wave in encounter_waves_for_room(room_index):
		out.append_array(wave)
	return out

static func room_name(template: Dictionary) -> String:
	return str(template.get("name", str(template.get("tag", "unknown")).to_upper()))

# --- Cells meta-progression (currency kept across runs, Dead Cells-style) ---
const META_UPGRADES: Array = [
	{ "id": "m_max_hp",   "title": "Ember Soul",   "desc": "+10 starting HP.",          "cost": 5,  "kind": "max_hp",    "value": 10.0 },
	{ "id": "m_flask",    "title": "Potion Belt",  "desc": "+1 starting flask charge.", "cost": 8,  "kind": "flask",     "value": 1.0 },
	{ "id": "m_speed",    "title": "Quickened",    "desc": "+8% starting move speed.",  "cost": 6,  "kind": "speed_mul", "value": 0.08 },
	{ "id": "m_dmg",      "title": "Sharpened",    "desc": "+10% starting melee dmg.",  "cost": 7,  "kind": "dmg_mul",   "value": 0.10 },
	{ "id": "m_special",  "title": "Arcane Spark", "desc": "Start each run with 25 special.", "cost": 6, "kind": "special_start", "value": 25.0 },
]
