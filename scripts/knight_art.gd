extends RefCounted
## Hand-authored pixel art for the Graveflame knight, on the same 2-world-pixel
## grid as the creature sheets. Body parts are small palette-indexed tiles that
## get composited into pose frames at boot, so every pose shares one silhouette
## and there is no PNG to keep in sync. Frames are authored facing right.
##
## Frame canvas: 34 x 32 art pixels, feet on the bottom row, body centre x = 16.

const FRAME_W := 34
const FRAME_H := 32
const CENTER_X := 16
## World units per art pixel.
const PX := 2.0

const PALETTE := {
	"K": Color("14101a"), # outline
	"H": Color("4a1a22"), # cloak dark
	"h": Color("6f2a31"), # cloak light
	"C": Color("32111a"), # cloak deep shade
	"T": Color("e8e0d0"), # tunic
	"t": Color("bfb5a6"), # tunic shade
	"S": Color("ff7a18"), # sash
	"M": Color("d8cfc0"), # mask
	"m": Color("a89e90"), # mask shade
	"E": Color("ff7a18"), # eye
	"B": Color("17131f"), # boots
	"b": Color("2e2637"), # trousers
	"W": Color("aab4c4"), # steel
	"w": Color("6e7887"), # steel dark
	"G": Color("f0b45a"), # gold
	"g": Color("9c7233"), # gold shade
	"R": Color("c8321a"), # flame ember
	"O": Color("ff5a10"), # flame orange
	"Y": Color("ffa827"), # flame gold
	"X": Color("fff0d0"), # flame white-hot
	"e": Color("ff7a18"), # skull socket glow
}

## The head: a dark cowl-less skull with a pale mask face and an ember eye,
## facing right. The fire is hair only, drawn from FLAMES as a separate animated
## sprite whose base sits on the crown so the face stays visible.
const SKULL := [
	"..KKKK..",
	".KbbbbK.",
	"KbbbMMmK",
	"KbbbMEmK",
	"KbbbMmmK",
	".KbbmmK.",
	"..KKKK..",
	"...KK...",
]

## Fire crown: a gold circlet on the brow with flame spikes, tall in the centre
## and shorter at the sides, flickering across four frames. 12 x 9, band on the
## bottom three rows so it sits on the forehead and the face stays visible.
const FLAMES := [
	[
		".....Y......",
		".....YY.....",
		"..Y..YOY..Y.",
		"..YY.OXO.YY.",
		".YYO.OXO.OYY",
		".ROOROXOROOR",
		"KGGGGGGGGGGK",
		"KgGGgGGgGGgK",
		".KKKKKKKKKK.",
	],
	[
		"......Y.....",
		".....YY.....",
		"..Y..YOY.Y..",
		"..YY.OXO.YY.",
		".YYO.OXO.OYY",
		".ROOROXOROOR",
		"KGGGGGGGGGGK",
		"KgGGgGGgGGgK",
		".KKKKKKKKKK.",
	],
	[
		"............",
		"..Y..YY..Y..",
		"..YY.YOY.YY.",
		".YYO.OXO.OYY",
		".YOO.OXO.OOY",
		".ROOROXOROOR",
		"KGGGGGGGGGGK",
		"KgGGgGGgGGgK",
		".KKKKKKKKKK.",
	],
	[
		"....Y.......",
		".....YY.....",
		"..Y.YOY..Y..",
		"..YY.OXO.YY.",
		".YYO.OXO.OYY",
		".ROOROXOROOR",
		"KGGGGGGGGGGK",
		"KgGGgGGgGGgK",
		".KKKKKKKKKK.",
	],
]
const FLAME_W := 12
const FLAME_H := 9

const TORSO := [
	"..KKKKKKKK..",
	".KHhTTTTthK.",
	".KHTSTTTtHK.",
	"..KTTSTTttK.",
	"..KTTTSTttK.",
	"..KtTTTSttK.",
	"..KttTTTStK.",
	"..KKGKKKKK..",
	"...KKKKK....",
]

const LEGS := {
	"stand": [
		"....KbbKbbK...",
		"....KbbKbbK...",
		"....KbbKbbK...",
		"....KbbKbbK...",
		"....KBBKBBK...",
		"....KBBKBBK...",
		"...KBBBKBBBK..",
		"...KKKKKKKKK..",
	],
	"run1": [
		".....KbbbK....",
		"....KbbKbbK...",
		"...KbbK.KbbK..",
		"..KbbK...KbbK.",
		"..KBBK...KBBK.",
		".KBBK.....KBBK",
		".KBBBK...KBBBK",
		".KKKKK...KKKKK",
	],
	"run2": [
		".....KbbbK....",
		".....KbbbK....",
		"....KbbKbK....",
		"....KbbKbK....",
		"....KBBKBK....",
		"....KBBKK.....",
		"...KBBBK......",
		"...KKKKK......",
	],
	"air": [
		"....KbbKbbK...",
		"...KbbKKbbK...",
		"...KbbK.KbbK..",
		"..KBBK..KBBK..",
		"..KBBK...KBBK.",
		".KBBBK...KBBBK",
		".KKKKK...KKKKK",
		"..............",
	],
	"dash": [
		"..............",
		"..............",
		".....KbbbbK...",
		"...KbbKKKbbK..",
		".KbbK.....KbbK",
		".KBBK.....KBBK",
		".KKKK.....KKKK",
		"..............",
	],
	"crouch": [
		"..............",
		"..............",
		"....KbbKbbK...",
		"...KbbbKbbbK..",
		"..KbbKKKKbbK..",
		"..KBBK...KBBK.",
		".KBBBK..KBBBK.",
		".KKKKK..KKKKK.",
	],
}

const CAPES := {
	"rest": [
		"......KKK.",
		".....KHHHK",
		"....KHhHHK",
		"....KHHHHK",
		"...KHhHHHK",
		"...KHHHHHK",
		"...KHHHHCK",
		"..KHhHHHCK",
		"..KHHHHHCK",
		"..KHHHHCCK",
		".KHhHHHCCK",
		".KHHHHHCCK",
		".KHHHHCCCK",
		".KHHHKCCCK",
		".KKKK.KKKK",
	],
	"run": [
		"........KKK",
		"......KKHHK",
		"....KKHhHHK",
		"..KKHHHHHCK",
		".KHhHHHHCCK",
		"KHHHHHHCCKK",
		"KHHHHCCCKK.",
		".KHHCCKKK..",
		".KKKKKK....",
	],
	"air": [
		"KKK.........",
		"KHHK........",
		"KHhHK.......",
		".KHHHK......",
		".KHhHHK.....",
		"..KHHHHK....",
		"..KHHHHHK...",
		"...KHhHHHK..",
		"...KHHHHHCK.",
		"....KHHHHCK.",
		"....KHHHCCK.",
		".....KHHCCK.",
		".....KKKKKK.",
	],
}

## Pose table: legs tile, cape tile, sword angle (radians, positive = down),
## body bob (px down), head lean (px forward), torso lean (px forward).
const POSES := {
	"idle0": { "legs": "stand", "cape": "rest", "sword": 0.6, "bob": 0, "head": 0, "torso": 0 },
	"idle1": { "legs": "stand", "cape": "rest", "sword": 0.62, "bob": 1, "head": 0, "torso": 0 },
	"run0": { "legs": "run1", "cape": "run", "sword": 0.8, "bob": 1, "head": 1, "torso": 1 },
	"run1": { "legs": "run2", "cape": "run", "sword": 0.75, "bob": 0, "head": 1, "torso": 1 },
	"run2": { "legs": "run3", "cape": "run", "sword": 0.8, "bob": 1, "head": 1, "torso": 1 },
	"run3": { "legs": "run4", "cape": "run", "sword": 0.75, "bob": 0, "head": 1, "torso": 1 },
	"jump": { "legs": "air", "cape": "air", "sword": -0.3, "bob": -1, "head": 0, "torso": 0 },
	"fall": { "legs": "air", "cape": "air", "sword": 0.9, "bob": 1, "head": 1, "torso": 0 },
	"dash": { "legs": "dash", "cape": "run", "sword": 0.05, "bob": 2, "head": 2, "torso": 2 },
	"hurt": { "legs": "stand", "cape": "rest", "sword": -0.5, "bob": 0, "head": -1, "torso": -1 },
	"heal": { "legs": "crouch", "cape": "rest", "sword": 1.3, "bob": 2, "head": 1, "torso": 1 },
	"parry": { "legs": "stand", "cape": "rest", "sword": -1.5, "bob": 0, "head": 0, "torso": 1 },
	"slam": { "legs": "air", "cape": "air", "sword": 1.45, "bob": 0, "head": 1, "torso": 0 },
}
const ATTACK_FRAMES := 8
const ATTACK_MIN := -1.6
const ATTACK_MAX := 1.6

## Procedural tile compositor (in-house): the knight is drawn from authored tiles
## plus the procedural fire crown. No baked sheets.

## Texture holding the frames: the procedurally composited tile atlas.
static func texture() -> Texture2D:
	return atlas()

## World pixels per texel for the active frames.
static func px() -> float:
	return PX

## Art-pixel size of one frame.
static func frame_size() -> Vector2:
	return Vector2(FRAME_W, FRAME_H)

## Frame for a pose at an animation tick.
static func frame(name: String, _tick: int) -> Rect2:
	return frame_rect(name)

static var _atlas: ImageTexture
static var _frames: Dictionary = {}
## Per-frame flame anchor: bottom-centre of the fire in frame art pixels.
static var _anchors: Dictionary = {}
static var _flame_atlas: ImageTexture

static func atlas() -> ImageTexture:
	if _atlas == null:
		_build()
	return _atlas

static func frame_rect(name: String) -> Rect2:
	if _atlas == null:
		_build()
	return _frames.get(name, _frames.get("idle0", Rect2()))

static func flame_anchor(name: String) -> Vector2i:
	if _atlas == null:
		_build()
	return _anchors.get(name, _anchors.get("idle0", Vector2i(CENTER_X, 8)))

## 4-frame fire strip, FLAME_W x FLAME_H each.
static func flame_atlas() -> ImageTexture:
	if _flame_atlas == null:
		var sheet := Image.create(FLAME_W * FLAMES.size(), FLAME_H, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0, 0, 0, 0))
		for i in range(FLAMES.size()):
			_blit(sheet, FLAMES[i], i * FLAME_W, 0)
		_flame_atlas = ImageTexture.create_from_image(sheet)
	return _flame_atlas

static func flame_rect(index: int) -> Rect2:
	return Rect2(posmod(index, FLAMES.size()) * FLAME_W, 0, FLAME_W, FLAME_H)

static func frame_names() -> Array:
	if _atlas == null:
		_build()
	return _frames.keys()

## Attack frame for a sword angle.
static func attack_frame(angle: float) -> String:
	var u := clampf((angle - ATTACK_MIN) / (ATTACK_MAX - ATTACK_MIN), 0.0, 1.0)
	return "atk%d" % roundi(u * float(ATTACK_FRAMES - 1))

static func _mirror(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append(String(r).reverse())
	return out

static func _legs(name: String) -> Array:
	match name:
		"run3": return _mirror(LEGS["run1"])
		"run4": return _mirror(LEGS["run2"])
	return LEGS[name]

static func _blit(img: Image, rows: Array, x0: int, y0: int) -> void:
	for y in range(rows.size()):
		var row := String(rows[y])
		for x in range(row.length()):
			var ch := row[x]
			if ch == ".":
				continue
			var px := x0 + x
			var py := y0 + y
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			img.set_pixel(px, py, PALETTE[ch])

## Blade, guard and pommel drawn as pixel lines, then outlined.
static func _sword(img: Image, grip: Vector2i, angle: float) -> void:
	var dir := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-dir.y, dir.x)
	var blade: Array[Vector2i] = []
	for i in range(1, 13):
		var p := Vector2(grip) + dir * float(i)
		blade.append(Vector2i(roundi(p.x), roundi(p.y)))
	var edge: Array[Vector2i] = []
	for i in range(2, 12):
		var p := Vector2(grip) + dir * float(i) + perp * 0.9
		edge.append(Vector2i(roundi(p.x), roundi(p.y)))
	var guard: Array[Vector2i] = []
	for i in range(-2, 3):
		var p := Vector2(grip) + perp * float(i) + dir * 0.5
		guard.append(Vector2i(roundi(p.x), roundi(p.y)))
	var pommel := Vector2(grip) - dir * 1.6
	var pom := Vector2i(roundi(pommel.x), roundi(pommel.y))
	var solid: Dictionary = {}
	for p in blade: solid[p] = PALETTE["W"]
	for p in edge: solid[p] = PALETTE["w"]
	for p in guard: solid[p] = PALETTE["G"]
	solid[pom] = PALETTE["g"]
	solid[blade[blade.size() - 1]] = Color("e6ecf4")
	# Outline: transparent neighbours of any sword pixel.
	for p in solid.keys():
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if solid.has(q):
				continue
			if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
				continue
			if img.get_pixel(q.x, q.y).a <= 0.01:
				img.set_pixel(q.x, q.y, PALETTE["K"])
	for p in solid.keys():
		if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
			continue
		img.set_pixel(p.x, p.y, solid[p])

static func _compose(pose: Dictionary) -> Array:
	var img := Image.create(FRAME_W, FRAME_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bob := int(pose.bob)
	var legs_y := FRAME_H - 8
	var torso_y := legs_y - 8 + bob
	var head_y := torso_y - 7
	var torso_x := CENTER_X - 6 + int(pose.torso)
	var head_x := CENTER_X - 3 + int(pose.head)
	# Cape hangs from the shoulders, behind everything.
	var cape: Array = CAPES[pose.cape]
	match String(pose.cape):
		"rest": _blit(img, cape, torso_x - 5, torso_y - 1)
		"run": _blit(img, cape, torso_x - 9, torso_y)
		"air": _blit(img, cape, torso_x - 10, torso_y - 8)
	_blit(img, _legs(pose.legs), CENTER_X - 7, legs_y)
	_blit(img, TORSO, torso_x, torso_y)
	_blit(img, SKULL, head_x, head_y)
	_sword(img, Vector2i(torso_x + 9, torso_y + 4), float(pose.sword))
	# The circlet's bottom row rests on the brow (one row below the skull top).
	return [img, Vector2i(head_x + 4, head_y + 1)]

static func _build() -> void:
	var names: Array = POSES.keys()
	var poses: Array = []
	for n in names:
		poses.append([n, POSES[n]])
	for i in range(ATTACK_FRAMES):
		var ang := lerpf(ATTACK_MIN, ATTACK_MAX, float(i) / float(ATTACK_FRAMES - 1))
		poses.append(["atk%d" % i, { "legs": "run1" if i >= 3 else "stand", "cape": "run", "sword": ang, "bob": 0 if i < 3 else 1, "head": 1, "torso": 2 if i >= 3 else 0 }])
	var sheet := Image.create(FRAME_W * poses.size(), FRAME_H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	_frames.clear()
	_anchors.clear()
	for i in range(poses.size()):
		var composed: Array = _compose(poses[i][1])
		var frame: Image = composed[0]
		sheet.blit_rect(frame, Rect2i(0, 0, FRAME_W, FRAME_H), Vector2i(i * FRAME_W, 0))
		_frames[poses[i][0]] = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		_anchors[poses[i][0]] = composed[1]
	_atlas = ImageTexture.create_from_image(sheet)

## Save the sheet as a PNG (dev tool / editor reference).
static func save_png(path: String) -> Error:
	return atlas().get_image().save_png(path)
