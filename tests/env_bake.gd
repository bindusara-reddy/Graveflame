extends SceneTree
## Bake the Blender environment renders (tools/render_environment.py) into
## palette-quantized pixel art under assets/env. Same method as the knight:
## Lanczos downsample to art resolution, tone each pixel inside its material
## family's ramp by auto-levelled luminance; backdrop layers get a 1px dark edge.
## Run: godot4 --headless --path . --script res://tests/env_bake.gd -- RENDER_DIR [OUT_DIR]

const FAMILIES := {
	"stone": [Color(1, 0, 0), [Color("1a2130"), Color("2a3448"), Color("3e4d66"), Color("566a88")]],
	"coping": [Color(0, 1, 0), [Color("2f3b52"), Color("4a5b7a"), Color("6f86aa"), Color("9db0cc")]],
	"mortar": [Color(0, 0, 1), [Color("10131c")]],
	"iron": [Color(1, 1, 0), [Color("1a1a22"), Color("33333f")]],
	"wood": [Color(1, 0, 1), [Color("3a2618"), Color("5a3c24"), Color("7a5533")]],
	"cloth": [Color(0, 1, 1), [Color("4a0f1c"), Color("7a1a2c"), Color("a02a3c")]],
	"glass": [Color(0.5, 0, 0), [Color("1f6f80"), Color("2fa5b8"), Color("8fe6ee")]],
	"window": [Color(0, 0.5, 0), [Color("ff9a3c"), Color("ffd27a")]],
	"flame": [Color(0, 0, 0.5), [Color("ff5a10"), Color("ffa827"), Color("fff0d0")]],
	"spire": [Color(0.5, 0.5, 0), [Color("0b0d16"), Color("141828")]],
	"moss": [Color(0.5, 0, 0.5), [Color("24503a"), Color("3a7a55")]],
	"gold": [Color(0, 0.5, 0.5), [Color("9c7233"), Color("f0b45a")]],
}
const OUTLINE := Color("0b0d16")

var render_dir := ""
var out_dir := "res://assets/env"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: render_dir = args[0]
	if args.size() > 1: out_dir = args[1]
	if render_dir.is_empty():
		printerr("usage: env_bake.gd -- RENDER_DIR [OUT_DIR]")
		quit(1)
		return
	_bake()
	quit(0)

func _family_of(id: Color) -> String:
	var best := "stone"
	var best_d := INF
	for name in FAMILIES:
		var c: Color = FAMILIES[name][0]
		var d := (c.r - id.r) * (c.r - id.r) + (c.g - id.g) * (c.g - id.g) + (c.b - id.b) * (c.b - id.b)
		if d < best_d:
			best_d = d
			best = name
	return best

func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

func _bake_image(name: String, w: int, h: int, outline: bool) -> Image:
	var lit := Image.load_from_file(render_dir.path_join(name + ".png"))
	var idm := Image.load_from_file(render_dir.path_join(name + "_id.png"))
	if lit == null or idm == null:
		printerr("missing render: ", name)
		return null
	var small: Image = lit.duplicate()
	small.resize(w, h, Image.INTERPOLATE_LANCZOS)
	var ids: Image = idm.duplicate()
	ids.resize(w, h, Image.INTERPOLATE_NEAREST)
	var cls: Array = []
	var lums := {}
	for y in range(h):
		for x in range(w):
			var c := small.get_pixel(x, y)
			if c.a < 0.45:
				cls.append(null)
				continue
			var idc := ids.get_pixel(x, y)
			var fam := _family_of(idc) if idc.a > 0.4 else "mortar"
			var l := _lum(Color(c.r, c.g, c.b, 1.0))
			cls.append([fam, l])
			if not lums.has(fam): lums[fam] = PackedFloat32Array()
			lums[fam].append(l)
	var thresholds := {}
	for fam in lums:
		var arr: PackedFloat32Array = lums[fam]
		arr.sort()
		var n := arr.size()
		var ramp: Array = FAMILIES[fam][1]
		var cuts: Array = []
		for i in range(1, ramp.size()):
			cuts.append(arr[int(n * float(i) / float(ramp.size()))])
		thresholds[fam] = cuts
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in range(h):
		for x in range(w):
			var entry = cls[y * w + x]
			if entry == null: continue
			var fam: String = entry[0]
			var ramp: Array = FAMILIES[fam][1]
			var tone := 0
			for cut in thresholds[fam]:
				if float(entry[1]) >= float(cut):
					tone += 1
			out.set_pixel(x, y, ramp[mini(tone, ramp.size() - 1)])
	if outline:
		var edged: Image = out.duplicate()
		for y in range(h):
			for x in range(w):
				if out.get_pixel(x, y).a > 0.5: continue
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q := Vector2i(x, y) + d
					if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and out.get_pixel(q.x, q.y).a > 0.5:
						edged.set_pixel(x, y, OUTLINE)
						break
		out = edged
	return out

func _bake() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(render_dir.path_join("env.json")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var manifest := {}
	var review_dir := render_dir
	for name in meta:
		var w := int(meta[name].w)
		var h := int(meta[name].h)
		var img := _bake_image(name, w, h, name.begins_with("layer"))
		if img == null: continue
		img.save_png(out_dir.path_join(name + ".png"))
		manifest[name] = { "w": w, "h": h }
		var big: Image = img.duplicate()
		var k := 8 if w <= 64 else 3
		big.resize(w * k, h * k, Image.INTERPOLATE_NEAREST)
		var backed := Image.create(big.get_width(), big.get_height(), false, Image.FORMAT_RGBA8)
		backed.fill(Color("2a2438"))
		backed.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i.ZERO)
		backed.save_png(review_dir.path_join(name + "_review.png"))
	var f := FileAccess.open(out_dir.path_join("env_manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("ENV_BAKE_DONE images=", manifest.size())
