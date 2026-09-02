extends SceneTree
## Bake the Blender creature renders (tools/render_creatures.py) into the game's
## creature sheets: assets/creatures/<creature>_<state>.png plus anim_manifest.json.
## Each pixel is toned inside its material family's ramp by auto-levelled
## luminance and the silhouette gets a 1px dark edge, so the whole cast shares
## one palette with the knight and the environment.
## Run: godot4 --headless --path . --script res://tests/creature_bake.gd -- RENDER_DIR [OUT_DIR]

const FAMILIES := {
	"cloth": [Color(1, 0, 0), [Color("1c1e2c"), Color("30334a"), Color("4a4e64"), Color("6c7490")]],
	"cloth_dark": [Color(0, 1, 0), [Color("111219"), Color("1e2030"), Color("2e3145")]],
	"skin": [Color(0, 0, 1), [Color("2a3a24"), Color("3f5a34"), Color("5c7a48"), Color("7f9a5e")]],
	"iron": [Color(1, 1, 0), [Color("161821"), Color("2a2d3b"), Color("434758"), Color("5c6275")]],
	"gold": [Color(1, 0, 1), [Color("8a6228"), Color("c0903f"), Color("f0b45a"), Color("ffe6a8")]],
	"steel": [Color(0, 1, 1), [Color("4e586a"), Color("7d8899"), Color("aab4c4"), Color("e6ecf4")]],
	"glow_teal": [Color(0.5, 0, 0), [Color("1f8a96"), Color("2fd0d8"), Color("b8fff6")]],
	"glow_orange": [Color(0, 0.5, 0), [Color("d84a0c"), Color("ff7a18"), Color("ffc060")]],
	"eye": [Color(0, 0, 0.5), [Color("ff7a18"), Color("ffd27a")]],
	"flame": [Color(0.5, 0.5, 0), [Color("ff5a10"), Color("ffa827"), Color("fff0d0")]],
	"bone": [Color(0.5, 0, 0.5), [Color("8f877a"), Color("bdb3a3"), Color("e6ddcc")]],
	"cloak_red": [Color(0, 0.5, 0.5), [Color("2a0d14"), Color("4a1a22"), Color("6f2a31"), Color("8e3a3f")]],
	"belly": [Color(1, 0.5, 0), [Color("7a7a5a"), Color("a6a878"), Color("cfd0a0")]],
	"void": [Color(0.5, 0.5, 0.5), [Color("0d0f16"), Color("161a24")]],
}
const OUTLINE := Color("0d0f16")

var render_dir := ""
var out_dir := "res://assets/creatures"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: render_dir = args[0]
	if args.size() > 1: out_dir = args[1]
	if render_dir.is_empty():
		printerr("usage: creature_bake.gd -- RENDER_DIR [OUT_DIR]")
		quit(1)
		return
	_bake()
	quit(0)

func _family_of(id: Color) -> String:
	var best := "cloth"
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

## Classify one frame: array of null | [family, luminance] per art pixel.
func _classify(lit_path: String, id_path: String, w: int, h: int) -> Array:
	var lit := Image.load_from_file(lit_path)
	var idm := Image.load_from_file(id_path)
	if lit == null or idm == null:
		return []
	var small: Image = lit.duplicate()
	small.resize(w, h, Image.INTERPOLATE_LANCZOS)
	var ids: Image = idm.duplicate()
	ids.resize(w, h, Image.INTERPOLATE_NEAREST)
	var out: Array = []
	for y in range(h):
		for x in range(w):
			var c := small.get_pixel(x, y)
			if c.a < 0.45:
				out.append(null)
				continue
			var idc := ids.get_pixel(x, y)
			out.append([_family_of(idc) if idc.a > 0.4 else "void", _lum(Color(c.r, c.g, c.b, 1.0))])
	return out

func _bake() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(render_dir.path_join("creatures.json")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var manifest := { "creatures": {} }
	for creature in meta:
		var info: Dictionary = meta[creature]
		var w := int(info.frame_w)
		var h := int(info.frame_h)
		# Pass 1: classify every frame of this creature and gather family luminance.
		var frames := {}
		var lums := {}
		for state in info.states:
			var count := int(info.states[state])
			for k in range(count):
				var base := "%s_%s_%d" % [creature, state, k]
				var cls := _classify(render_dir.path_join(base + ".png"), render_dir.path_join(base + "_id.png"), w, h)
				if cls.is_empty():
					printerr("missing render: ", base)
					continue
				frames[base] = cls
				for e in cls:
					if e == null: continue
					if not lums.has(e[0]): lums[e[0]] = PackedFloat32Array()
					lums[e[0]].append(e[1])
		var thresholds := {}
		for fam in lums:
			var arr: PackedFloat32Array = lums[fam]
			arr.sort()
			var n := arr.size()
			var ramp: Array = FAMILIES[fam][1]
			var cuts: Array = []
			for i in range(1, ramp.size()):
				cuts.append(arr[mini(n - 1, int(n * float(i) / float(ramp.size())))])
			thresholds[fam] = cuts
		# Pass 2: tone, outline and pack one sheet per state.
		manifest.creatures[creature] = {}
		for state in info.states:
			var count := int(info.states[state])
			var sheet := Image.create(w * count, h, false, Image.FORMAT_RGBA8)
			sheet.fill(Color(0, 0, 0, 0))
			for k in range(count):
				var base := "%s_%s_%d" % [creature, state, k]
				if not frames.has(base): continue
				var cls: Array = frames[base]
				var frame := Image.create(w, h, false, Image.FORMAT_RGBA8)
				frame.fill(Color(0, 0, 0, 0))
				for y in range(h):
					for x in range(w):
						var e = cls[y * w + x]
						if e == null: continue
						var ramp: Array = FAMILIES[e[0]][1]
						var tone := 0
						for cut in thresholds[e[0]]:
							if float(e[1]) >= float(cut):
								tone += 1
						frame.set_pixel(x, y, ramp[mini(tone, ramp.size() - 1)])
				var edged: Image = frame.duplicate()
				for y in range(h):
					for x in range(w):
						if frame.get_pixel(x, y).a > 0.5: continue
						for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							var q := Vector2i(x, y) + d
							if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and frame.get_pixel(q.x, q.y).a > 0.5:
								edged.set_pixel(x, y, OUTLINE)
								break
				sheet.blit_rect(edged, Rect2i(0, 0, w, h), Vector2i(k * w, 0))
			var file := "%s_%s.png" % [creature, state]
			sheet.save_png(out_dir.path_join(file))
			manifest.creatures[creature][state] = { "file": file, "frames": count, "frame_w": w, "frame_h": h, "feet_y": int(info.feet_y), "scale": 1.0 }
			if state == "idle":
				var big: Image = sheet.duplicate()
				big.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
				var backed := Image.create(big.get_width(), big.get_height(), false, Image.FORMAT_RGBA8)
				backed.fill(Color("2a2438"))
				backed.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i.ZERO)
				backed.save_png(render_dir.path_join(creature + "_review.png"))
	var f := FileAccess.open(out_dir.path_join("anim_manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("CREATURE_BAKE_DONE creatures=", manifest.creatures.size())
