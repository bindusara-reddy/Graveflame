extends SceneTree
## Dev tool: writes the composited knight sprite sheet (1x and 8x nearest) so the
## pixel art can be reviewed outside the game.
## Run: godot4 --headless --path . --script res://tests/knight_dump.gd -- OUT_DIR
const KnightArt := preload("res://scripts/knight_art.gd")

func _init() -> void:
	var out_dir := "/tmp"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var img := KnightArt.atlas().get_image()
	img.save_png(out_dir.path_join("knight_sheet.png"))
	var big := img.duplicate()
	big.resize(img.get_width() * 8, img.get_height() * 8, Image.INTERPOLATE_NEAREST)
	# Dark backing so the outline reads.
	var backed := Image.create(big.get_width(), big.get_height(), false, Image.FORMAT_RGBA8)
	backed.fill(Color("2a2438"))
	backed.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i.ZERO)
	backed.save_png(out_dir.path_join("knight_sheet_8x.png"))
	# Contact sheet: 7 columns, 6x, so every frame is readable at a glance.
	var names: Array = KnightArt.frame_names()
	var cols := 7
	var rows := int(ceil(float(names.size()) / float(cols)))
	var fw := KnightArt.FRAME_W
	var fh := KnightArt.FRAME_H
	var grid := Image.create(cols * fw, rows * fh, false, Image.FORMAT_RGBA8)
	grid.fill(Color("2a2438"))
	var flames := KnightArt.flame_atlas().get_image()
	for i in range(names.size()):
		var r: Rect2 = KnightArt.frame_rect(names[i])
		var cell := Vector2i((i % cols) * fw, (i / cols) * fh)
		grid.blend_rect(img, Rect2i(r.position, r.size), cell)
		# Burning head, as the game composes it at runtime.
		var a: Vector2i = KnightArt.flame_anchor(names[i])
		var fr: Rect2 = KnightArt.flame_rect(i)
		grid.blend_rect(flames, Rect2i(fr.position, fr.size), cell + Vector2i(a.x - KnightArt.FLAME_W / 2, a.y + 1 - KnightArt.FLAME_H))
	grid.resize(grid.get_width() * 6, grid.get_height() * 6, Image.INTERPOLATE_NEAREST)
	grid.save_png(out_dir.path_join("knight_contact.png"))
	print("frames: ", names.size(), " sheet: ", img.get_size(), " order: ", names)
	quit(0)
