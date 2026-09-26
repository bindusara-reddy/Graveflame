extends "res://tests/harness.gd"
## Audio contracts: the ending's cues and the new pieces render to spec, fades
## run in real time, layers hold their lockstep, the voice pool steals by rank,
## pause-proof voices ring through panels, pitched cues stay in tune, and the
## game drives the combat layer, the low-flame filter and the heartbeat.
## Run: godot4 --headless --path . --script res://tests/audio_contract.gd --audio-driver Dummy

const MusicSynth := preload("res://scripts/music.gd")
const SfxSynth := preload("res://scripts/sfx_synth.gd")


func run() -> void:
	use_scratch_save("audio_contract")
	_test_recipes()
	await _test_music_api()
	await _test_voices()
	await _test_game_hooks()
	await finish("AUDIO_CONTRACT")


## Waits in unscaled time. Timers fire before tweens step within a frame, so
## one more frame lets every fade due by now land before the caller checks it.
func _real_seconds(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	await process_frame


## Largest sample magnitude (0..1) of 16-bit PCM from from_byte on.
func _peak(pcm: PackedByteArray, from_byte: int) -> float:
	var peak := 0
	for i in range(from_byte, pcm.size() - 1, 2):
		peak = maxi(peak, absi(pcm.decode_s16(i)))
	return float(peak) / 32768.0


## Streams for players whose render has not landed, so API checks never wait.
func _stub_stream(loop: bool) -> AudioStreamWAV:
	var pcm := PackedByteArray()
	pcm.resize(MusicSynth.RATE * 4 * 2)
	return MusicSynth._make_stream(pcm, loop)


func _test_recipes() -> void:
	for cue in MusicSynth.CUES:
		check(not MusicSynth.TRACKS.has(cue), "%s never delays is_ready()" % cue)
		var pcm: PackedByteArray = MusicSynth._render_track(cue)
		var stream := MusicSynth._make_stream(pcm, MusicSynth._loops(cue))
		var frames := pcm.size() / 4
		check(_peak(pcm, 0) > 0.5, "%s renders a full-level mix" % cue)
		if cue == "curtain_hold":
			check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "the hold under the gathering loops")
		else:
			check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s plays once" % cue)
			var tail := _peak(pcm, (frames - MusicSynth.RATE / 2) * 4)
			check(tail < 0.01, "%s rings out inside its own length (last 0.5 s peak %.4f)" % [cue, tail])
	var b2_seconds := float(MusicSynth._render_track("curtain_b2").size() / 4) / MusicSynth.RATE
	check(absf(b2_seconds - (60.0 / 84.0 * 32.0 + 6.0)) < 0.01, "the curtain call is 32 beats at 84 bpm and its tail")
	# A layer and its base, a variant and its original, must be the same length
	# or they drift apart loop by loop.
	var explore_frames := int(60.0 / 84.0 * 4.0 * 16.0 * MusicSynth.RATE)
	check(MusicSynth._render_track("explore_hot").size() / 4 == explore_frames, "explore_hot is exactly as long as explore")
	var title_frames := int(60.0 / 72.0 * 4.0 * 8.0 * MusicSynth.RATE)
	check(MusicSynth._render_track("title_dawn").size() / 4 == title_frames, "the dawn title is exactly as long as the title")
	for cue in ["fold", "grave_bell", "kindle", "burn", "curtain", "snuff", "footlight", "ui_move", "clang", "spit",
			"bolt_hit", "heartbeat", "whiff", "perfect_parry", "ring_out", "tell_sexton", "sexton_wave", "roar",
			"last_ember", "card_deal", "uncork", "grave_light"]:
		check(SfxSynth.LEVELS.has(cue), "the cue book has %s" % cue)
		check(_peak(SfxSynth.build_pcm(cue), 0) > 0.2, "%s is a designed sound, not the fallback click" % cue)
	# Every Warden move is heard as it is loosed, not only wound up (Boss._release).
	for action: String in Boss.Action.keys():
		var cue := "release_" + action.to_lower()
		check(SfxSynth.LEVELS.has(cue) and _peak(SfxSynth.build_pcm(cue), 0) > 0.2, "the Warden's %s has a designed release cue" % action.to_lower())


func _test_music_api() -> void:
	var music = MusicSynth.new()
	root.add_child(music)
	var started := Time.get_ticks_msec()
	while not music.is_ready() and Time.get_ticks_msec() - started < 60000:
		await process_frame
	check(music.is_ready(), "the score's tracks are ready")
	# This fixture drives the API with stub streams; no late render may land mid-check.
	music._late_queue.clear()
	while not music._threads.is_empty():
		await process_frame
	for name in ["explore_hot", "title_dawn"] + MusicSynth.CUES:
		var p: AudioStreamPlayer = music._players[name]
		if p.stream == null:
			p.stream = _stub_stream(MusicSynth._loops(name))
	var players: Dictionary = music._players
	# The recipe renders above held the main thread for seconds; let that long
	# frame pass before timing a fade.
	await process_frame

	# Fades run in real seconds, whatever the time scale.
	Engine.time_scale = 0.25
	music.play_track("title", 0.5)
	await _real_seconds(0.7)
	Engine.time_scale = 1.0
	var title_db: float = (players["title"] as AudioStreamPlayer).volume_db
	check(absf(title_db - float(MusicSynth.LEVELS["title"])) < 0.5, "a fade under slow motion finishes in real time (got %.1f dB)" % title_db)

	# The combat layer starts with its base, held silent, and rises on demand.
	music.set_intensity(0.0, 0.0)
	music.play_track("explore", 0.0)
	var hot: AudioStreamPlayer = players["explore_hot"]
	check((players["explore"] as AudioStreamPlayer).playing and hot.playing, "explore starts with its combat layer running")
	check(hot.volume_db <= -79.0, "the combat layer waits at silence")
	music.set_intensity(1.0, 0.0)
	check(is_equal_approx(hot.volume_db, float(MusicSynth.LEVELS["explore_hot"])), "a wave raises the combat layer to its level")
	music.set_intensity(0.0, 0.0)
	await process_frame
	check(hot.playing, "a lowered layer keeps running in step with its base")

	# After a victory the title plays at dawn, still reported as the title.
	Save.add_victory(0)
	music.play_track("title", 0.0)
	check(music._current == "title", "the dawn title still answers to 'title'")
	check((players["title_dawn"] as AudioStreamPlayer).playing, "after a victory the title plays at dawn")
	_remove_scratch_save()

	# Cues overlap, stop on request, and fall silent with the music switch.
	check(music.has_cue("curtain_a") and not music.has_cue("title"), "has_cue knows the ending's cues")
	music.play_cue("curtain_a")
	music.play_cue("curtain_hold")
	var cue_a: AudioStreamPlayer = players["curtain_a"]
	var hold: AudioStreamPlayer = players["curtain_hold"]
	check(cue_a.playing and hold.playing, "one cue does not stop another")
	check(is_equal_approx(cue_a.volume_db, float(MusicSynth.CUE_LEVELS["curtain_a"])), "a cue plays at its own level")
	music.stop_cue("curtain_a", 0.0)
	check(not cue_a.playing, "stop_cue with no fade stops at once")
	music.set_enabled(false)
	check(not music.has_cue("curtain_hold"), "with the music off the finale falls back to effects")
	await _real_seconds(0.45)
	check(not hold.playing, "turning the music off stops the cues")
	music.set_enabled(true)

	# The killing blow: everything out, in real time.
	music.play_track("boss", 0.0)
	music.play_cue("curtain_hold")
	music.cut(0.1)
	await _real_seconds(0.25)
	var sounding := []
	for name in players:
		if (players[name] as AudioStreamPlayer).playing:
			sounding.append(name)
	check(music._current == "" and sounding.is_empty(), "cut() silences tracks and cues (still sounding: %s)" % str(sounding))
	music.queue_free()
	await process_frame


func _test_voices() -> void:
	var feedback := Feedback.new()
	root.add_child(feedback)
	var started := Time.get_ticks_msec()
	while feedback._takes.is_empty() and Time.get_ticks_msec() - started < 120000:
		await process_frame
	check(not feedback._takes.is_empty(), "the cue book renders")

	feedback.play("fold", 1.5, 0.0, false)
	check(_voice_of(feedback, "fold").pitch_scale == 1.5, "humanize=false plays the exact pitch")
	feedback.play("clear", 1.25)
	check(_voice_of(feedback, "clear").pitch_scale == 1.25, "a pitched cue is never detuned")
	var detuned := false
	for i in range(6):
		feedback.play("dash")
		detuned = detuned or _voice_of(feedback, "dash").pitch_scale != 1.0
	check(detuned, "noise cues are still humanized")

	feedback.stop_world_voices()
	for i in range(6):
		feedback.play("step")
	check(_count(feedback, "step") <= 2, "footsteps are capped at two voices")

	# A toll is never cut by a flurry, and a footstep never cuts anything.
	feedback.stop_world_voices()
	feedback.play("victory")
	var flurry := ["swing", "hit", "tear", "jump", "land", "dash", "shield", "hurt", "shoot", "flame", "slam", "boom", "riposte"]
	for i in range(40):
		feedback.play(flurry[i % flurry.size()])
	check(_voice_of(feedback, "victory") != null, "a flurry of hits steals around the victory toll")
	feedback.play("step")
	check(_voice_of(feedback, "step") == null, "a footstep is dropped rather than cut a busier voice")

	# Panels: world voices stop before the pause; persistent ones play through.
	feedback.play_persistent("defeat")
	feedback.stop_world_voices()
	var toll := _voice_of(feedback, "defeat")
	check(toll != null and toll.process_mode == Node.PROCESS_MODE_ALWAYS, "the toll plays on a voice the pause cannot hold")
	var world_left := 0
	for p in feedback._audio_pool:
		world_left += 1 if p.playing else 0
	check(world_left == 0, "stop_world_voices leaves no world sound to resume later")
	paused = true
	feedback.play("ui_confirm")
	check(feedback._persistent_pool.has(_voice_of(feedback, "ui_confirm")), "a cue played while paused is not frozen by the pause")
	paused = false

	# The heartbeat sounds once per pulse, on its peak.
	feedback._heartbeat_beat = -1
	var beats := 0
	for i in range(64):
		var before := _count(feedback, "heartbeat")
		feedback.heartbeat(float(i) * 0.25, 1.0)
		beats += 1 if _count(feedback, "heartbeat") > before else 0
	check(beats == 3, "a heartbeat per turn of the pulse (got %d over 16 rad)" % beats)
	feedback.queue_free()
	await process_frame


func _voice_of(feedback: Feedback, cue: String) -> AudioStreamPlayer:
	for p in feedback._audio_pool + feedback._persistent_pool:
		if p.playing and str(p.get_meta("cue", "")) == cue:
			return p
	return null


func _count(feedback: Feedback, cue: String) -> int:
	var n := 0
	for p in feedback._audio_pool + feedback._persistent_pool:
		if p.playing and str(p.get_meta("cue", "")) == cue:
			n += 1
	return n


func _test_game_hooks() -> void:
	await load_main_scene(1)
	await start_run(2)
	check(game.music._current == "explore" and game.music._intensity == 1.0, "a chamber's first wave raises the combat layer")
	game.feedback.play("elite")
	check(_voice_of(game.feedback, "elite").bus == "Stinger", "stingers are routed to duck the score")

	# The flame gutters: the score closes in and the heart starts to beat.
	var filter: AudioEffectLowPassFilter = game.music._filter
	check(filter != null, "the score has a low-pass on its bus")
	game.player.build.hp = float(game.player.build.max_hp) * 0.05
	var heard := false
	for i in range(90):
		await process_frame
		heard = heard or _voice_of(game.feedback, "heartbeat") != null
	check(filter != null and filter.cutoff_hz < 4000.0, "low health muffles the score")
	check(heard or game.feedback._takes.is_empty(), "low health is heard as a heartbeat")
	game.player.build.hp = game.player.build.max_hp
	paused = true
	await _real_seconds(0.5)
	check(filter != null and filter.cutoff_hz < 1500.0, "a panel that holds the run pushes the score behind it")
	paused = false
	await _real_seconds(0.5)
	check(filter != null and filter.cutoff_hz > 15000.0, "the score opens again when play resumes")
