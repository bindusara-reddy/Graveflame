extends RefCounted
## Loader for the baked environment art (assets/env, produced by
## tools/render_environment.py + tests/env_bake.gd): stone tiles for platforms
## and walls, and the three parallax backdrop layers. When the folder is absent
## the room and backdrop fall back to their procedural vector drawing.

const DIR := "res://assets/env/"
const MANIFEST := DIR + "env_manifest.json"
## World pixels per art pixel.
const PX := 2.0
## Tiles are 32 art px = 64 world px; backdrop layers are 320 x 200 art px.
const TILE := 64.0
const LAYER_W := 640.0
const LAYER_H := 400.0

static var _checked := false
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}

static func _check() -> void:
	if _checked:
		return
	_checked = true
	if not FileAccess.file_exists(MANIFEST):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary:
		_manifest = parsed

static func has_env() -> bool:
	_check()
	return not _manifest.is_empty()

static func has(name: String) -> bool:
	_check()
	return _manifest.has(name)

static func tex(name: String) -> Texture2D:
	_check()
	if _textures.has(name):
		return _textures[name]
	var path := DIR + name + ".png"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	if t == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			t = ImageTexture.create_from_image(img)
	_textures[name] = t
	return t

## Draw `name` tile scaled to world size at `pos`, clipped to `size` (world px).
static func draw_tile(ci: CanvasItem, name: String, pos: Vector2, size: Vector2, tint: Color = Color.WHITE) -> void:
	var t := tex(name)
	if t == null or size.x <= 0.0 or size.y <= 0.0:
		return
	ci.draw_texture_rect_region(t, Rect2(pos, size), Rect2(Vector2.ZERO, size / PX), tint)
