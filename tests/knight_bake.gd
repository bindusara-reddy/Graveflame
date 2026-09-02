extends SceneTree
## Bake the Blender renders into the game's pixel sheet. Each frame has a lit
## render and a flat material-ID render; every art pixel is toned inside the
## ramp of its own material family by the lit luminance, which is what gives
## the creature sheets their clean 2-3 tone shading. The dark silhouette comes
## from the inverted-hull outline rendered in Blender.
## Run: godot4 --headless --path . --script res://tests/knight_bake.gd -- RENDER_DIR [OUT_DIR]

## Family -> [ID colour, ramp dark..light]
const FAMILIES := {
	"cloak": [Color(1, 0, 0), [Color("2a0d14"), Color("4a1a22"), Color("6f2a31"), Color("8e3a3f")]],
	"tunic": [Color(0, 1, 0), [Color("7c7468"), Color("a89e90"), Color("cfc5b6"), Color("ece5d8")]],
	"dark": [Color(0, 0, 1), [Color("14101a"), Color("221c2c"), Color("342b42")]],
	"mask": [Color(0, 1, 1), [Color("a89e90"), Color("d8cfc0"), Color("f2ebe0")]],
	"steel": [Color(1, 0, 1), [Color("4e586a"), Color("7d8899"), Color("aab4c4"), Color("e6ecf4")]],
	"gold": [Color(1, 1, 0), [Color("8a6228"), Color("c0903f"), Color("f0b45a"), Color("ffe6a8")]],
	"sash": [Color(1, 0.5, 0), [Color("b8520c"), Color("ff7a18"), Color("ffa827")]],
	"flame_outer": [Color(0.5, 0, 0), [Color("e0400c"), Color("ff5a10")]],
	"flame_inner": [Color(0, 0.5, 0), [Color("ff9a1a"), Color("ffb84a")]],
	"flame_core": [Color(1, 1, 1), [Color("fff0d0")]],
	"eye": [Color(0, 0, 0.5), [Color("ff7a18")]],
	"outline": [Color(0, 0, 0), [Color("14101a")]],
	"head": [Color(0.5, 0, 0.5), [Color("1e1628"), Color("2f2540"), Color("443658"), Color("5b4b74")]],
}
const COLS := 12

var render_dir := ""
var out_dir := "res://assets/knight"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: render_dir = args[0]
	if args.size() > 1: out_dir = args[1]
	if render_dir.is_empty():
		printerr("usage: knight_bake.gd -- RENDER_DIR [OUT_DIR]")
		quit(1)
		return
	_bake()
	quit(0)

func _family_of(id: Color) -> String:
	var best := "dark"
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

## Pass 1: downsample and classify every frame. Returns per-frame arrays of
## [family, luminance] so pass 2 can auto-level each family across the sheet.
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
			var fam := _family_of(idc) if idc.a > 0.4 else "outline"
			out.append([fam, _lum(Color(c.r, c.g, c.b, 1.0))])
	return out

func _bake() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(render_dir.path_join("poses.json")))
	var poses: Array = meta.poses
	var flicker := int(meta.flicker)
	var w := int(meta.art[0])
	var h := int(meta.art[1])
	var names: Array = []
	for p in poses:
		for k in range(flicker):
			names.append("%s_f%d" % [p, k])
	var classified := {}
	var lums := {}
	for n in names:
		var cls := _classify(render_dir.path_join(n + ".png"), render_dir.path_join(n + "_id.png"), w, h)
		if cls.is_empty():
			printerr("missing render: ", n)
			continue
		classified[n] = cls
		for entry in cls:
			if entry == null: continue
			if not lums.has(entry[0]): lums[entry[0]] = PackedFloat32Array()
			lums[entry[0]].append(entry[1])
	# Auto-level thresholds: split each family's luminance range into as many
	# bands as its ramp has tones (slightly favouring the mid tones).
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
	var rows := int(ceil(float(names.size()) / float(COLS)))
	var sheet := Image.create(COLS * w, rows * h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	var frames := {}
	var i := 0
	for n in names:
		if not classified.has(n): continue
		var cls: Array = classified[n]
		var cell := Vector2i((i % COLS) * w, (i / COLS) * h)
		var frame := Image.create(w, h, false, Image.FORMAT_RGBA8)
		frame.fill(Color(0, 0, 0, 0))
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
				frame.set_pixel(x, y, ramp[mini(tone, ramp.size() - 1)])
		# Silhouette edge: grow the shape by one pixel of outline colour so thin
		# features (the blade) keep their own colour.
		var outline: Color = FAMILIES["outline"][1][0]
		var edged: Image = frame.duplicate()
		for y in range(h):
			for x in range(w):
				if frame.get_pixel(x, y).a > 0.5: continue
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q := Vector2i(x, y) + d
					if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and frame.get_pixel(q.x, q.y).a > 0.5:
						edged.set_pixel(x, y, outline)
						break
		sheet.blit_rect(edged, Rect2i(0, 0, w, h), cell)
		frames[n] = [cell.x, cell.y, w, h]
		i += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	sheet.save_png(out_dir.path_join("knight_sheet.png"))
	var manifest := { "frame_w": w, "frame_h": h, "flicker": flicker, "px": 1.0, "poses": poses, "frames": frames }
	var f := FileAccess.open(out_dir.path_join("knight_manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	var big: Image = sheet.duplicate()
	big.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
	var backed := Image.create(big.get_width(), big.get_height(), false, Image.FORMAT_RGBA8)
	backed.fill(Color("2a2438"))
	backed.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i.ZERO)
	backed.save_png(render_dir.path_join("knight_sheet_review.png"))
	print("KNIGHT_BAKE_DONE frames=", frames.size(), " sheet=", sheet.get_size())
