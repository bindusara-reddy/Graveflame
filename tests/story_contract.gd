extends "res://tests/harness.gd"
## The story's hooks in a live descent (headless): the first descent ever opens
## on the inscription and no later one does, each cleared chamber says its
## litany line in order of depth (the ending's variant once the save keeps
## one), the Warden burns with the knight's dead, and a fall prints the hoard.
## Checks on today's UI (the lesson strip, the phase tag, the epitaph label)
## run only while it lacks the story's own cards.

var _save: Script = Save


func run() -> void:
	use_scratch_save("story_contract")
	await load_main_scene(4)
	await start_run()
	var cards: bool = game.ui.has_method("show_inscription")
	check(game._opening_inscription() == Content.INSCRIPTION, "the first descent ever opens on the inscription")
	if not cards:
		check(game.ui._hint_label.text.contains("Yours got up."), "without its card the inscription reads on the lesson strip")
		game.ui.hide_banners()
		game._inscribe(game._opening_inscription())
		check(not game.ui._hint_panel.visible, "the inscription is carved once a sitting")
	_check_litany(cards)
	_check_phase_tag()
	await _check_hoard(cards)
	await finish("STORY")


func _check_litany(cards: bool) -> void:
	for k in range(Content.LITANY.size()):
		game.run.room_index = k
		check(game._litany_line() == Content.LITANY[k], "chamber %d says litany line %d" % [k + 1, k + 1])
	game.run.room_index = game.run.rooms_total() - 1
	check(game._litany_line() == "", "the throne room says no litany line")
	game.run.room_index = 1
	if not cards:
		game._hint_cooldown = 0.0
		game._on_room_cleared("PENITENT STAIR")
		check(game.ui._hint_label.text == Content.LITANY[1], "a cleared chamber says its line on the lesson strip")
		game.ui.show_hint("A LESSON")
		game._hint_cooldown = 3.0
		game._on_room_cleared("PENITENT STAIR")
		check(game.ui._hint_label.text == "A LESSON", "the litany never speaks over a lesson being read")
	if _save.has_method("set_last_ending"):
		_save.call("set_last_ending", "given")
		game.run.room_index = Content.LITANY_TURN - 1
		check(game._litany_line() == Content.LITANY_AFTER.given[0], "after an ending the litany turns at line %d" % Content.LITANY_TURN)
		_save.call("set_last_ending", "")


func _check_phase_tag() -> void:
	var tag: Label = game.ui.get("_boss_phase_tag")
	game._on_boss_phase(2)
	if tag != null:
		check(tag.text == Content.WARDEN_IGNITES, "a knight with no dead sees the Warden simply ignite")
	Save.record_fall("")
	game._on_boss_phase(2)
	if tag != null:
		check(tag.text == Content.WARDEN_BURNS, "the Warden burns with the knight's dead")
	check(game._opening_inscription().is_empty(), "no later descent opens on the inscription")


func _check_hoard(cards: bool) -> void:
	game.player.iframes = 0.0
	game.player.take_damage(9999.0, Vector2.RIGHT, 0.0)
	await ticks(10)
	check(game.state == Game.GState.GAME_OVER, "the knight falls")
	check(Save.get_falls() == 2, "the fall is counted")
	check(game._stats.get("hoard_line", "") == Content.hoard_line(2), "the hoard counts every fall, this one included")
	check(Save.load_save().get("last_epitaph", "") == game._stats.line and Content.EPITAPHS.has(game._stats.line), "the save keeps the bare epitaph for the ending")
	if not cards:
		var shown := (game.ui._panels["gameover"].get_meta("line_label") as Label).text
		check(shown == "%s\n%s" % [game._stats.line, Content.hoard_line(2)], "the death screen prints the hoard under the epitaph (got %s)" % shown)
	game.state = Game.GState.VICTORY
	game._finalize_summary()
	check(game._stats.hoard_line == "", "a won descent holds no hoard line")
