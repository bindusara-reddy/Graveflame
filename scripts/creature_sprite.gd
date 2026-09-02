extends Sprite2D
## Sprite-sheet body for enemies and the boss (the approved Blender creature
## family). Each frame it reads the owner's public state and maps it onto a
## sheet; it never writes back, so gameplay is untouched. Sheets are authored
## facing right at 2x pixel scale, so they display at SHEET_SCALE.

const VFX := preload("res://scripts/vfx.gd")
const ASSET_DIR := "res://assets/creatures/"
const SHEET_SCALE := 0.5
const IDLE_FPS := 6.0
const DEATH_FRAME_TIME := 0.12
const DEATH_HOLD := 0.25
const DEATH_FADE := 0.45

static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
## Mood tint applied to every creature. Sprites are unshaded so enemies always
## read, and this keeps them sitting in the room's light instead of popping out.
static var tint := Color.WHITE

var creature := "stalker"
var foot_y := 0.0                    ## local y where the manifest feet row must sit
var under: Node2D                    ## companion node (shadow pass) to redraw with us
var creature_provider: Callable      ## optional: sheet family for this frame (boss phases)
var active_time_provider: Callable   ## optional: seconds the owner's ATTACK state lasts
var size_mul := 1.0                  ## elite scale on top of SHEET_SCALE
var elite_tint := Color.WHITE        ## gilding for elites, multiplied with the mood tint
var _sheet := ""
var _idle_t := 0.0
var _stagger_total := 0.18
var _last_state := -1
var _flash_material: ShaderMaterial

static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var text := ""
		if FileAccess.file_exists(ASSET_DIR + "anim_manifest.json"):
			text = FileAccess.get_file_as_string(ASSET_DIR + "anim_manifest.json")
		var parsed = JSON.parse_string(text) if not text.is_empty() else null
		if parsed is Dictionary and parsed.has("creatures"):
			_manifest = parsed.creatures
		else:
			_manifest = {"_missing": true}
	return _manifest

static func sheet_info(family: String, state: String) -> Dictionary:
	var m := manifest()
	if m.has(family) and m[family] is Dictionary and m[family].has(state):
		return m[family][state]
	return {}

static func sheet_texture(file: String) -> Texture2D:
	if not _textures.has(file):
		var path := ASSET_DIR + file
		_textures[file] = load(path) if ResourceLoader.exists(path) else null
	return _textures[file]

func setup(p_creature: String, p_foot_y: float) -> void:
	creature = p_creature
	foot_y = p_foot_y

func _ready() -> void:
	name = "Body"
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The owner's _draw() paints telegraphs, HP and flames over the body.
	show_behind_parent = true
	scale = Vector2(SHEET_SCALE, SHEET_SCALE)
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = VFX.flash_shader()
	material = _flash_material
	var owner_node := get_parent()
	if owner_node != null and owner_node.has_signal("died"):
		# Connected before the room's handler, so the corpse exists before the free.
		owner_node.died.connect(_on_owner_died)
	_apply_sheet("idle")
	set_process(true)

func _family() -> String:
	if creature_provider.is_valid():
		return str(creature_provider.call())
	return creature

## Sheet pixel offset that places the manifest feet row on foot_y. The sprite is
## scaled about the owner origin, so the offset is expressed in sheet pixels.
static func feet_offset(info: Dictionary, p_foot_y: float) -> Vector2:
	var frame_h := float(info.get("frame_h", 96))
	var feet := float(info.get("feet_y", frame_h - 1.0))
	return Vector2(0.0, p_foot_y / SHEET_SCALE - (feet + 0.5 - frame_h * 0.5))

func _apply_sheet(state: String) -> void:
	var fam := _family()
	var key := fam + "/" + state
	if key == _sheet:
		return
	var info := sheet_info(fam, state)
	if info.is_empty():
		info = sheet_info(fam, "idle")
	_sheet = key
	var tex: Texture2D = sheet_texture(str(info.get("file", ""))) if not info.is_empty() else null
	texture = tex
	visible = tex != null
	if tex == null:
		return
	hframes = maxi(1, int(info.get("frames", 1)))
	vframes = 1
	frame = 0
	offset = feet_offset(info, foot_y)

func _frame_at(t: float) -> void:
	frame = clampi(int(t * float(hframes)), 0, hframes - 1)

func _process(delta: float) -> void:
	var p := get_parent()
	if p == null:
		return
	if under != null:
		under.queue_redraw()
	var st := int(p.get("state"))
	if st != _last_state:
		if st == Enemy.EState.STAGGER:
			_stagger_total = maxf(0.01, float(p.get("stagger_t")))
		_last_state = st
	flip_h = float(p.get("facing")) < 0.0
	self_modulate = tint * elite_tint
	var pop := 1.0
	var spawn := float(p.get("_spawn_anim"))
	if spawn > 0.0:
		pop = 1.0 - spawn / 0.4
	scale = Vector2(SHEET_SCALE * pop * size_mul, SHEET_SCALE * pop * size_mul)
	_flash_material.set_shader_parameter("flash", 1.0 if float(p.get("_hurt_flash")) > 0.0 else 0.0)
	var data: Dictionary = p.get("data")
	var st_timer := float(p.get("st_timer"))
	match st:
		Enemy.EState.WINDUP:
			_apply_sheet("windup")
			_frame_at(clampf(1.0 - st_timer / maxf(0.01, float(data.get("windup", 0.4))), 0.0, 1.0))
		Enemy.EState.ATTACK:
			var active := float(data.get("active", 0.18))
			if active_time_provider.is_valid():
				active = float(active_time_provider.call())
			var ta := clampf(1.0 - st_timer / maxf(0.01, active), 0.0, 1.0)
			_apply_sheet("attack")
			# Frames 1-2 cover the active window; frame 3 belongs to recovery.
			frame = mini(hframes - 1, 0 if ta < 0.5 else 1)
		Enemy.EState.RECOVER:
			_apply_sheet("attack")
			frame = hframes - 1
		Enemy.EState.STAGGER:
			_apply_sheet("stagger")
			_frame_at(clampf(1.0 - float(p.get("stagger_t")) / _stagger_total, 0.0, 1.0))
		Enemy.EState.DEAD:
			pass
		_:
			_apply_sheet("idle")
			_idle_t += delta
			frame = int(_idle_t * IDLE_FPS) % hframes

## Death: the owner is freed by existing room logic, so a detached corpse plays
## the death sheet in its place, holds, fades and frees itself.
func _on_owner_died(_score: int = 0) -> void:
	var p := get_parent()
	if p == null or not p.is_inside_tree():
		return
	var host := p.get_parent()
	if host == null:
		return
	var info := sheet_info(_family(), "death")
	if info.is_empty():
		return
	var tex := sheet_texture(str(info.get("file", "")))
	if tex == null:
		return
	var corpse := Sprite2D.new()
	corpse.name = "Corpse"
	corpse.texture = tex
	corpse.centered = true
	corpse.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	corpse.hframes = maxi(1, int(info.get("frames", 1)))
	corpse.frame = 0
	corpse.flip_h = flip_h
	corpse.scale = Vector2(SHEET_SCALE * size_mul, SHEET_SCALE * size_mul)
	corpse.self_modulate = self_modulate
	corpse.offset = feet_offset(info, foot_y)
	host.add_child(corpse)
	corpse.global_position = p.global_position
	var tween := corpse.create_tween()
	tween.tween_property(corpse, "frame", corpse.hframes - 1, DEATH_FRAME_TIME * float(corpse.hframes))
	tween.tween_interval(DEATH_HOLD)
	tween.tween_property(corpse, "modulate:a", 0.0, DEATH_FADE)
	tween.tween_callback(corpse.queue_free)
