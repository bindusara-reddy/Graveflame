extends SceneTree
## Dev tool: renders the procedural score to WAV files for offline listening/analysis.
## Run: godot4 --headless --path . --script res://tests/music_dump.gd -- OUT_DIR
const MusicSynth := preload("res://scripts/music.gd")

func _init() -> void:
	var out_dir := "/tmp"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var m = MusicSynth.new()
	var t0 := Time.get_ticks_msec()
	var explore: PackedByteArray = m._render_explore()
	var t1 := Time.get_ticks_msec()
	var boss: PackedByteArray = m._render_boss()
	var t2 := Time.get_ticks_msec()
	print("render ms: explore=%d boss=%d" % [t1 - t0, t2 - t1])
	MusicSynth._make_stream(explore).save_to_wav(out_dir.path_join("explore.wav"))
	MusicSynth._make_stream(boss).save_to_wav(out_dir.path_join("boss.wav"))
	print("DUMPED")
	quit(0)
