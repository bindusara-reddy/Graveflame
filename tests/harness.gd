extends SceneTree
## Shared scaffolding for the contract suites: a check counter, frame stepping,
## a scratch save, main-scene boot, and the one-line result every runner greps.
## Suites extend this by path (no class_name, so the game's class cache stays
## clean) and implement run(); the harness calls it once the tree is live.
## Suites must not override _init: read OS.get_cmdline_user_args() at the top
## of run() instead, or the harness never starts.

## A suite that has not called finish() by then has hung (a script error aborts
## the coroutine without quitting), so it fails instead of waiting forever.
const WATCHDOG_SECONDS := 300.0

var checks := 0
var failures := 0
var game: Game
var _scratch_save := ""


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	# Process-always and ignoring time scale, so a paused tree or a slowed
	# hit-stop cannot hold the watchdog back.
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_watchdog_expired)
	run()


## Reports the hang as a failure so runners see a FAIL line and a non-zero exit.
func _watchdog_expired() -> void:
	printerr("FAIL: suite did not finish within %d s" % WATCHDOG_SECONDS)
	quit(1)


## Each suite overrides this and ends with finish(). Running the harness itself
## fails at once rather than idling until the watchdog.
func run() -> void:
	printerr("harness.gd is a base script; run a suite")
	quit(1)


## Counts one assertion; a failure prints its message and fails the suite.
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)


## One full frame is a physics step followed by an idle step; every
## input-driven fixture counts time in these.
func ticks(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame


## Points Save at a throwaway file and starts it empty, so a suite never reads
## or writes real progress. finish() deletes it again.
func use_scratch_save(name: String) -> void:
	_scratch_save = "user://%s.json" % name
	Save.path = _scratch_save
	_remove_scratch_save()


## Deletes the scratch save and the backup its writes keep, if a suite chose one.
func _remove_scratch_save() -> void:
	if _scratch_save == "":
		return
	for file in [_scratch_save, _scratch_save + ".bak"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## Replaces any running game with a fresh main scene on the title screen, added
## under parent (the root when null). The settle count is a parameter because
## frame-counting fixtures depend on exactly when the knight lands.
func load_main_scene(settle_ticks := 3, parent: Node = null) -> void:
	await free_game()
	game = load("res://main.tscn").instantiate()
	var host: Node = parent if parent != null else root
	host.add_child(game)
	await ticks(settle_ticks)


## Leaves the title for the first chamber the way BEGIN does.
func start_run(after_start_ticks := 4) -> void:
	game.ui.start_requested.emit()
	await ticks(after_start_ticks)


## Frees the current game, if any, and unpauses the tree it may have paused.
func free_game() -> void:
	paused = false
	if is_instance_valid(game):
		game.queue_free()
		await process_frame


## Lets go of every listed action, so no held input leaks into the next fixture.
func release(actions: Array) -> void:
	for action in actions:
		Input.action_release(action)


## Holds an input action for exactly hold_ticks frames, then lets go.
func hold_action(action: String, hold_ticks := 1) -> void:
	Input.action_press(action)
	await ticks(hold_ticks)
	Input.action_release(action)


## A 1280x720 offscreen target the game renders into, so captures and pixel
## reads never depend on the OS window size.
func make_capture_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	return vp


## Presses and releases a physical key through the real input pipeline.
func tap_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await ticks(2)


## Name of the control holding keyboard/pad focus, for readable focus checks.
func focus_name() -> String:
	var owner := root.gui_get_focus_owner()
	if owner == null:
		return "<none>"
	return owner.name


## Display suites only: resizes the real window and checks the viewport took it.
func set_window_size(size: Vector2i, fullscreen := false) -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		_request_windowed(size)
	await ticks(8)
	# Leaving fullscreen can hand back a maximised window; re-apply until it takes.
	var tries := 0
	while root.size != size and not fullscreen and tries < 6:
		_request_windowed(size)
		await ticks(10)
		tries += 1
	check(root.size == size, "presented viewport is %s (got %s)" % [size, root.size])


## Asks for a plain window of the given size at a fixed, reachable position.
func _request_windowed(size: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# Keep clear of the desktop's top bar so the window manager honours the size.
	DisplayServer.window_set_position(Vector2i(160, 120))
	DisplayServer.window_set_size(size)


## Enemies of the current room that are still in the tree and not dying.
func live_enemies() -> Array:
	return game.room.enemies.filter(func(e): return is_instance_valid(e) and not e.dead)


## The boon definition with this id, so fixtures grant boons by name.
func upgrade(id: String) -> Dictionary:
	return Content.UPGRADES.filter(func(u): return u.id == id)[0]


## Swaps the next route slot for an enemy-free copy of the tagged template and
## walks into it, so traversal fixtures run on real geometry without a fight.
func enter_empty_room(tag: String, settle_ticks := 85) -> bool:
	var matches := Content.ROOM_TEMPLATES.filter(func(t): return t.tag == tag)
	check(matches.size() == 1, tag + ": explicit room fixture exists")
	var next_room := game.run.room_index + 1
	var has_slot := next_room >= 0 and next_room < game.run.route.size()
	check(has_slot, tag + ": fixture has a next route slot")
	if matches.size() != 1 or not has_slot:
		return false
	var fixture: Dictionary = matches[0].duplicate(true)
	fixture.slots = []
	game.run.route[next_room] = fixture
	game._advance_room()
	await ticks(settle_ticks)
	return true


## Prints "<TAG>_RESULT: PASS|FAIL (n checks, n failures)" and exits with it.
func finish(tag: String) -> void:
	await free_game()
	# One more frame lets the freed game's audio streams release before the
	# quit, so the exit does not report them as leaked instances.
	await process_frame
	_remove_scratch_save()
	var passed := failures == 0
	var verdict := "PASS" if passed else "FAIL"
	var exit_code := 0 if passed else 1
	print("%s_RESULT: %s (%d checks, %d failures)" % [tag, verdict, checks, failures])
	quit(exit_code)
