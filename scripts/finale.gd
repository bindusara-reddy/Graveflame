class_name Finale
extends Node
## "The Warden's Crown": the ending, directed from the killing blow to the
## results panel. The Warden splits open like a paper costume; kneeling inside
## is the burnt-out knight who won the throne before, in the same crown. It
## speaks once and crumbles, and its crown, cracking on the floor, pours out
## every flame the throne swallowed, one for each knight ever lost, while the
## fallen fold up out of the floor around the cold throne. The throne calls,
## and the knight chooses: TAKE THE CROWN (it sits; the hall relights red),
## GIVE THEM BACK (each flame goes home; the keep burns away to the open sky
## and the fallen climb the well to become stars) or, sworn to all five vows,
## END IT (it strikes the throne; every fire goes out; a grey dawn). The last
## epitaph the knight died to is answered, and the results open.
##
## Everything runs on this node's own real-time clock (step), from an event
## sheet anchored to the kill and to the choice. The timeline never waits on
## audio, frame rate or Engine.time_scale; only the choice and the gather wait
## on the player, and nothing ever picks for them. A test can drive it frame by
## frame (autostep off). Every tween is a ramp on that clock, every layer and
## actor is created here, and abort() puts back everything borrowed from the
## game, from any phase.

const VFX := preload("res://scripts/vfx.gd")
const Cast := preload("res://scripts/finale_actors.gd")

signal finished(skipped: bool)

enum Phase { PROLOGUE, REVEAL, HOARD, CALL, CHOICE, CROWN, PROMPT, GATHER, LETGO, SKY, DARK, LAST_WORD, DONE }

## curtain_b2 runs at 84 bpm; the last word lands on its beat 32.
const BEAT := 60.0 / 84.0
## Held framings as [centre, zoom]. Reduced motion cuts between exactly these.
const HALL := [Vector2(640.0, 390.0), 1.0]
const THRONE := [Vector2(640.0, 470.0), 1.5]
const BEFORE_THRONE := [Vector2(640.0, 440.0), 1.2]
const SEATED := [Vector2(640.0, 470.0), 1.8]
const DAWN_FRAME := [Vector2(640.0, 400.0), 1.1]
const SIGIL := Vector2(640.0, 438.0)
const SIGIL_FLAME := Vector2(640.0, 454.0)
## The knight's body centre when seated: hips on the seat's top at y 528.
const SEAT := Vector2(640.0, 522.0)
const COLD_AMBIENT := Color(0.46, 0.42, 0.58)
const STARVED_AMBIENT := Color(0.42, 0.42, 0.46)
const DARK_AMBIENT := Color(0.07, 0.06, 0.1)
## The cast's light once the keep is gone: grey dawn over END IT.
const DAWN_LIGHT := Color(0.72, 0.75, 0.86)
const DARK_EDGE := Color(0.01, 0.0, 0.02, 0.92)
## Seconds a choice is held to be kept.
const CHOICE_HOLD := 1.2
const CONFIRM_KEYS := ["ui_accept", "attack", "interact", "ignite", "jump"]
const GATHER_KEYS := ["ignite", "attack", "interact"]
## Per cut: `pace` scales travel and holds; the reveal's zoom and how long the
## burnt knight's words hold; when it crumbles after the take-over; how long the
## hoard takes to pour; whether the knight walks to the throne (or a dip-cut
## puts it there); when the gather prompt starts by itself; the burn and the
## tilt up the well (0: no tilt); the lead from LET GO to curtain_b2, the beat
## it opens on and the beat the camera comes back down to the knight.
const CUTS := {
	"full": { "pace": 1.0, "zoom": 1.9, "words": 2.8, "crumble": 4.4, "pour": 2.4, "walk": true, "auto": 5.0, "burn": 4.8, "tilt": 5.0, "lead": 7.14, "call": 0.0, "down": 24.0 },
	"abridged": { "pace": 0.8, "zoom": 1.7, "words": 2.2, "crumble": 3.4, "pour": 1.4, "walk": false, "auto": 2.5, "burn": 3.5, "tilt": 3.5, "lead": 7.14, "call": 16.0, "down": 26.0 },
	"brief": { "pace": 0.6, "zoom": 1.6, "words": 1.6, "crumble": 2.4, "pour": 0.8, "walk": false, "auto": 0.0, "burn": 2.5, "tilt": 0.0, "lead": 2.5, "call": 24.0, "down": 0.0 },
}

## Tests turn this off and call step() themselves.
var autostep := true
var game: Game
## Save.record_victory()'s result plus vows, boons, gold and tier (see Game._victory).
var ctx: Dictionary = {}
var tier := "full"
var phase: Phase = Phase.PROLOGUE
## The ending chosen at the throne ("" until then): a Save.ENDINGS id.
var ending := ""
## Real seconds since the killing blow.
var clock := 0.0
## What the director animates and writes onto the game every step.
var cam_center := Vector2.ZERO
var cam_zoom := 1.0
var ambient := Color.WHITE
var vignette := Game.VIGNETTE_EDGE
var burn := 0.0

var _cut: Dictionary = {}
var _offered: Array = []
var _events: Array = []
var _ramps: Array = []
var _sounded: Dictionary = {}
var _owns_camera := false
var _ambient_live := false
var _vignette_live := false
var _burning := false
var _handed_off := false
var _light_follows := true
var _skipping := false
var _b0 := 0.0
var _b2_playing := false
var _side := -1.0
var _crowd := 0
# Layers and what is drawn on them.
var _sky_layer: CanvasLayer
var _actor_layer: CanvasLayer
var _actors: Node2D
var _sky: FinaleSky
var _cards: Control
var _dip: ColorRect
var _prompt: FinalePrompt
var _choice: ChoicePrompt
var _skip: SkipRing
# The cast.
var _shell: Cast.WardenShell
var _burnt: Cast.BurntKnight
var _relic: Cast.RelicCrown
var _relic_held := false
var _hoard: Cast.HoardField
var _knight: Cast.FinaleKnight
var _fallen: Array = []
var _crowns: Cast.CrownField
var _streams: Cast.FlameStream
var _ash: Cast.AshField
var _rostrum: Cast.Rostrum
var _throne: Cast.ThroneProxy
# The choice: the ending in hand (-1 none yet), how long it has been held, and
# the keys' last states, so only fresh presses move or confirm.
var _pick := -1
var _pick_hold := 0.0
var _armed := false
var _left_was := false
var _right_was := false
# The gather: held time along Content.GATHER_LINE.
var _gather_t := 0.0
var _gather_goal := 0.0
var _note := 0
var _auto := false
var _idle := 0.0
var _held := false
var _letgo_t := 0.0
var _letgo_held := false
var _skip_hold := 0.0

## Builds the layers. The Finale starts in PROLOGUE while the game's own victory
## beat plays out in slow motion.
func setup(g: Game, context: Dictionary) -> void:
	game = g
	ctx = context
	tier = str(ctx.get("tier", "full"))
	_cut = CUTS[tier]
	process_mode = Node.PROCESS_MODE_ALWAYS
	if bool(ctx.get("unknown", false)):
		_crowd = Content.UNCOUNTED_CROWD
	else:
		_crowd = mini(int(ctx.get("falls_total", 0)), Content.FALLEN_CAP)
	_offered = ["crown", "given"]
	if (ctx.get("vows", []) as Array).size() == Content.VOWS.size():
		_offered.append("ended")
	_build_layers()

func phase_name() -> String:
	return Phase.keys()[phase]

## The endings the knight is offered, in order.
func offered() -> Array:
	return _offered.duplicate()

func _process(delta: float) -> void:
	if autostep:
		step(minf(0.05, delta / maxf(Engine.time_scale, 0.001)))

## Advances the ending by `real_dt` seconds: input, the event sheet, every
## ramp, the cast, then the camera and the layers that follow it.
func step(real_dt: float) -> void:
	if phase == Phase.DONE:
		return
	clock += real_dt
	_poll_skip(real_dt)
	_poll_choice(real_dt)
	_poll_gather(real_dt)
	while not _events.is_empty() and float(_events[0][0]) <= clock and phase != Phase.DONE:
		(_events.pop_front()[1] as Callable).call()
	_update_ramps()
	for actor in _cast():
		if actor.has_method("advance"):
			actor.advance(real_dt)
	if _sky.has_method("advance"):
		_sky.advance(real_dt)
	if _relic_held and is_instance_valid(_knight):
		_relic.position = _knight.hand_point() + Vector2(0.0, -3.0)
	if is_instance_valid(_knight) and _light_follows:
		game.player.global_position = _knight.position
	_apply()

# --- I. Inside the Warden -------------------------------------------------------

## The Warden splits open like a paper costume, its halves falling away; where
## it stood kneels the burnt-out knight who won the throne before, in the same
## crown. Called at the Warden's shatter, inside the victory's slow motion.
func shatter(pos: Vector2) -> void:
	if is_instance_valid(_burnt) or _skipping or phase == Phase.DONE:
		return
	var boss: Boss = game.room.boss if is_instance_valid(game.room) else null
	var face := -1.0
	if is_instance_valid(boss):
		face = boss.facing
		_shell = Cast.WardenShell.new()
		_shell.position = boss.global_position
		_shell.setup(boss.visual_pose(), face, boss._anim_t)
		_add_to_world(_shell, 2)
		if Feedback.motion_reduced:
			_ramp(_shell, "modulate:a", 0.0, 0.5)
		else:
			_ramp(_shell, "open", 1.0, 1.1, Tween.TRANS_QUAD, Tween.EASE_IN)
			_after(1.1, _ramp.bind(_shell, "modulate:a", 0.0, 0.12))
	_burnt = Cast.BurntKnight.new()
	_burnt.setup(pos.x, face, str(ctx.get("last_ending", "")) == "crown")
	_add_to_world(_burnt, 1)
	_relic = Cast.RelicCrown.new()
	_relic.position = _burnt.crown_point()
	_add_to_world(_relic, 1)
	_ash = Cast.AshField.new()
	_add_to_world(_ash, 3)

## The victory beat has ended: the director takes the camera. The tree keeps
## running, so the braziers and the atmosphere live on. The burnt knight speaks
## its one line, then crumbles.
func take_over() -> void:
	if phase != Phase.PROLOGUE or _skipping:
		return
	phase = Phase.REVEAL
	var camera := game.feedback.camera
	game.feedback.end_slow_motion()
	_stand_in()
	cam_center = camera.global_position
	cam_zoom = camera.zoom.x
	_owns_camera = not Feedback.motion_reduced
	ambient = game.mood.ambient
	if not is_instance_valid(_burnt):
		shatter(_boss_point())
	if int(ctx.get("finale_seen", 0)) > 0:
		_skip.caption = Content.FINALE_TEXT.skip % str(UI._binding_text("pause").key).to_upper()
	var kneel := _burnt.position + Vector2(0.0, -30.0)
	_move_camera([Vector2(clampf(kneel.x, 360.0, 920.0), kneel.y), float(_cut.zoom)], 2.2 * _pace())
	var words: String = Content.WARDEN_WORDS.get(str(ctx.get("last_ending", "")), Content.WARDEN_WORDS[""])
	_after(0.9, _card.bind("“%s”" % words, float(_cut.words), 96.0, 26, UI.C_MUTED))
	_after(float(_cut.crumble), _crumble)

## Swaps the real knight for the stand-in in the same pose. The player stays
## in the tree, hidden and still, and is moved with the stand-in so LightRig's
## knight flame follows it.
func _stand_in() -> void:
	var player := game.player
	_knight = Cast.FinaleKnight.new()
	_knight.setup(player, bool(ctx.get("gold", false)))
	_add_to_world(_knight, 1)
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED

func _boss_point() -> Vector2:
	var room := game.room
	if is_instance_valid(room) and is_instance_valid(room.boss):
		return room.boss.global_position + Vector2(0.0, -24.0)
	return Vector2(640.0, 480.0)

## The burnt knight crumbles to ash from the crown down; the crown drops to the
## floor and lies there, still faintly burning.
func _crumble() -> void:
	var dur := 1.6 * _pace()
	_ramp(_burnt, "crumble", 1.0, dur)
	game.feedback.play("burn", 0.7, -8.0)
	for k in range(4):
		_after(dur * float(k) / 4.0, _ash.puff.bind(_burnt.position + Vector2(0.0, -22.0 + 13.0 * float(k)), 10, Vector2(12.0, 5.0)))
	var rest := Vector2(_burnt.position.x + 12.0 * _burnt.facing, Cast.stage_floor(_burnt.position.x) - 1.0)
	_after(0.2, _ramp.bind(_relic, "position", rest, 0.5, Tween.TRANS_BOUNCE, Tween.EASE_OUT))
	_after(0.2, _ramp.bind(_relic, "tilt", 0.3 * _burnt.facing, 0.5))
	_after(dur + 0.5, _pour)

# --- II. The fallen ---------------------------------------------------------------

## Stations beside the dais, filled inner to outer and alternating sides, front
## rank first; the back rank stands smaller and darker behind. None comes
## within 236 px of the throne, so the knight has the dais and the space
## before it to itself. The outermost front pair is a spare.
static func stations() -> Array:
	var out: Array = []
	# [first k, last k + 1, inner x, scale, back rank]
	for rank in [[0, 5, 236.0, 1.0, false], [0, 3, 259.0, 0.86, true], [5, 6, 236.0, 1.0, false]]:
		for k in range(rank[0], rank[1]):
			for side: float in [-1.0, 1.0]:
				out.append({ "x": Cast.THRONE_X + side * (float(rank[2]) + 46.0 * float(k)), "scale": rank[3], "back": rank[4] })
	return out

## The crown cracks and lets out every flame the throne swallowed, one for each
## knight ever lost. For each, a fallen knight folds up out of the floor around
## the throne, silent and dark.
func _pour() -> void:
	phase = Phase.HOARD
	_move_camera(HALL, 3.0 * _pace())
	_ramp(_relic, "crack", 1.0, 0.25)
	_ramp(_relic, "burn", 0.9, 0.2)
	_after(0.6, _ramp.bind(_relic, "burn", 0.25, 1.2))
	game.feedback.play("shatter", 1.3, -4.0)
	_cue("curtain_a")
	_spawn_crowd()
	var n := _fallen.size()
	var stagger := clampf(float(_cut.pour) / float(maxi(n, 1)), 0.06, 0.3)
	_hoard.pour(_relic.position + Vector2(0.0, -8.0), n, stagger)
	for i in range(n):
		_after(0.35 + stagger * float(i), _rise_fallen.bind(i))
	var settled := 0.35 + stagger * float(n) + 0.7
	_after(settled, _cool)
	_after(settled + 1.4 * _pace(), _call)

## Builds the crowd folded flat and hidden, back rank first so it draws
## behind, then the one crown field over them, the hoard and the stream layer.
func _spawn_crowd() -> void:
	var places := stations().slice(0, _crowd)
	_fallen.resize(places.size())
	for back: bool in [true, false]:
		for i in range(places.size()):
			if bool(places[i].back) == back:
				var f := Cast.FinaleFallen.new()
				f.setup(places[i], i)
				f.visible = false
				_fallen[i] = f
				_add_to_world(f, 0)
	_crowns = Cast.CrownField.new()
	for f in _fallen:
		_crowns.add(f)
	_add_to_world(_crowns, 0)
	_hoard = Cast.HoardField.new()
	_add_to_world(_hoard, 2)
	_streams = Cast.FlameStream.new()
	_add_to_world(_streams, 2)

## A fallen knight hinges up out of the floor, a charred stub where its flame
## was, on a plucked note climbing a D-minor pentatonic. Under reduced motion
## the page fades in already standing.
func _rise_fallen(i: int) -> void:
	var f: Cast.FinaleFallen = _fallen[i]
	f.visible = true
	_crowns.set_lit(i, 0.0)
	if Feedback.motion_reduced:
		f.hinge = 1.0
		f.modulate.a = 0.0
		_ramp(f, "modulate:a", 1.0, 0.25)
	else:
		_ramp(f, "hinge", 1.0, 0.32, Tween.TRANS_BACK, Tween.EASE_OUT)
	game.feedback.play("fold", Content.FOLD_MINOR[i % Content.FOLD_MINOR.size()], -4.0, false)

## With its hoard gone the throne goes cold: the sigil gutters out, the fires
## sink to a third and the hall cools toward blue.
func _cool() -> void:
	_ramp(game.room, "sigil_heat", 0.0, 1.2)
	_ramp(game.room, "fire_heat", 0.35, 2.0)
	_ramp(game, "sconce_heat", 0.35, 2.0)
	_ambient_live = true
	_ramp(self, "ambient", COLD_AMBIENT, 2.0)

# --- III. The throne calls ----------------------------------------------------------

## The throne calls: the hoard is drawn in over the cold seat, the braziers
## lean toward it, the knight comes to stand before it and the crown drifts to
## the knight's feet.
func _call() -> void:
	phase = Phase.CALL
	var pull := 3.0 * _pace()
	_ramp(_hoard, "ring_center", Vector2(640.0, 330.0), pull)
	_ramp(_hoard, "ring_rx", 190.0, pull)
	_ramp(_hoard, "ring_ry", 44.0, pull)
	_ramp(game.room, "fire_lean", 1.0, pull)
	_card(Content.FINALE_TEXT.cold, 3.6, 96.0)
	_after(1.3, _card.bind(Content.FINALE_TEXT.not_cold, 2.3, 136.0))
	var stop := _throne_stop()
	if bool(_cut.walk):
		_move_camera(BEFORE_THRONE, 3.0)
		_knight.gesture_to("", 0.0)
		_knight.walk(stop, clampf(absf(stop - _knight.position.x) / 2.6, 90.0, 300.0), -_side, _before_throne)
	else:
		_dip_cut(_at_throne.bind(stop), 0.3)

func _at_throne(stop: float) -> void:
	_knight.place(stop, -_side)
	_frame_now(BEFORE_THRONE)
	_before_throne()

## Where the knight stops before the dais, on the side it came from.
func _throne_stop() -> float:
	_side = signf(_knight.position.x - Cast.THRONE_X)
	if _side == 0.0:
		_side = -1.0
	return Cast.THRONE_X + 176.0 * _side

## The crown, lifted a little by the throne's pull, drifts to the knight's feet.
func _before_throne() -> void:
	var feet := Vector2(_knight.position.x - 20.0 * _side, Content.FLOOR_Y - 1.0)
	var drift := 2.4 * _pace()
	var over := (_relic.position + feet) * 0.5 + Vector2(0.0, -34.0)
	_ramp(_relic, "position", over, drift * 0.5, Tween.TRANS_SINE, Tween.EASE_OUT)
	_after(drift * 0.5, _ramp.bind(_relic, "position", feet, drift * 0.5, Tween.TRANS_SINE, Tween.EASE_IN))
	_ramp(_relic, "tilt", 0.0, drift)
	_after(drift + 0.4, _offer_choice)

# --- IV. The choice -----------------------------------------------------------------

## The choice. It waits as long as the knight does; nothing picks for it.
func _offer_choice() -> void:
	phase = Phase.CHOICE
	_choice.options = _offered.map(func(e): return Content.CHOICES[e])
	_choice.visible = true
	_choice.modulate.a = 0.0
	_ramp(_choice, "modulate:a", 1.0, 0.6)
	_armed = not _confirm_held()
	_cue("curtain_hold")

func _confirm_held() -> bool:
	return CONFIRM_KEYS.any(func(action): return Input.is_action_pressed(action))

## Left and right move between the endings; a fresh press held CHOICE_HOLD
## seconds keeps the one in hand. Letting go drains the hold three times as fast.
func _poll_choice(dt: float) -> void:
	if phase != Phase.CHOICE:
		return
	var left := Input.is_action_pressed("move_left") or Input.is_action_pressed("ui_left")
	var right := Input.is_action_pressed("move_right") or Input.is_action_pressed("ui_right")
	if left and not _left_was:
		_step_pick(-1)
	if right and not _right_was:
		_step_pick(1)
	_left_was = left
	_right_was = right
	var held := _confirm_held()
	_armed = _armed or not held
	if held and _armed and _pick >= 0:
		_pick_hold += dt
	else:
		_pick_hold = maxf(0.0, _pick_hold - 3.0 * dt)
	_choice.fill = _pick_hold / CHOICE_HOLD
	if _pick_hold >= CHOICE_HOLD:
		choose(_offered[_pick])

## The first press picks the near end of that side; later ones step along.
func _step_pick(dir: int) -> void:
	if _pick < 0:
		_pick = 0 if dir < 0 else mini(1, _offered.size() - 1)
	else:
		_pick = clampi(_pick + dir, 0, _offered.size() - 1)
	_pick_hold = 0.0
	_choice.selected = _pick
	game.feedback.play("ui_move")

## The knight's choice, kept in the save the moment it is made.
func choose(choice: String) -> void:
	if phase != Phase.CHOICE or not _offered.has(choice):
		return
	ending = choice
	Save.set_last_ending(choice)
	_ramp(_choice, "modulate:a", 0.0, 0.4)
	game.feedback.play("grave_bell", 0.5, -6.0, false)
	match choice:
		"crown":
			_take_crown()
		"given":
			_give_back()
		"ended":
			_end_it()

## A skip before the choice takes the ending last chosen, if it is offered.
func _default_ending() -> String:
	var last := str(ctx.get("last_ending", ""))
	return last if _offered.has(last) else "given"

# --- V. TAKE THE CROWN ----------------------------------------------------------------

## The knight stoops for the crown, lifts it and climbs the dais to sit.
func _take_crown() -> void:
	phase = Phase.CROWN
	_stop_cue("curtain_hold", 1.2)
	_knight.gesture_to("reach", 10.0)
	_after(0.5 * _pace(), _lift_crown)
	_after(1.2 * _pace(), _knight.walk.bind(Cast.THRONE_X, 110.0, -_side, _sit))

func _lift_crown() -> void:
	_relic_held = true
	_ramp(_relic, "tilt", 0.0, 0.3)
	_knight.gesture_to("raise", 8.0)
	game.feedback.play("kindle", 0.8, -8.0)

## Up onto the seat, legs hanging from a throne built for the Warden; then the
## crown comes down onto the knight's head.
func _sit() -> void:
	_knight.grounded = false
	_knight.gesture_to("sit", 8.0)
	_ramp(_knight, "position", SEAT, 0.35, Tween.TRANS_BACK, Tween.EASE_OUT)
	_move_camera(SEATED, 3.0 * _pace())
	_after(0.7, _crown_knight)

func _crown_knight() -> void:
	_relic_held = false
	_knight.gesture_to("", 6.0)
	_ramp(_relic, "position", _knight.head_point(), 0.5, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	_after(0.5, _crowned)

## The crown takes: the knight's flame flares and turns the Warden's red, the
## hoard pours into the throne, the hall relights red and the fallen kneel.
func _crowned() -> void:
	_relic.visible = false
	_knight.crown = 1.5
	_ramp(_knight, "red", 1.0, 0.8)
	_after(0.8, _ramp.bind(_knight, "crown", 1.15, 1.0))
	game.feedback.play("pyre", 0.8)
	game.feedback.play("elite", 0.667)
	game.feedback.shake(6.0, 0.4)
	var n := _hoard.count()
	for i in range(n):
		_after(0.05 * float(i), _hoard.send.bind(i, SIGIL_FLAME, 0.7))
	_after(0.05 * float(n) + 0.6, _flare.bind(Content.PAL.player_accent))
	_after(0.05 * float(n) + 0.6, _relight_red.bind(2.0))
	_after(0.05 * float(n) + 0.6, _cue.bind("curtain_a"))
	_after(1.4, _kneel_all)
	_after(3.4, _card.bind(Content.FINALE_TEXT.crowned, 3.0, 96.0))
	_after(8.2 * _pace(), _last_word)

## The sigil takes the fire and flares: a ring under reduced flash.
func _flare(color: Color) -> void:
	_ramp(game.room, "sigil_heat", 1.2 if Feedback.flash_reduced else 1.4, 0.2)
	if Feedback.flash_reduced:
		game.feedback._add_ring(SIGIL, color, 12.0, 90.0, 0.5, 4.0)
	else:
		game.feedback.flash_death(SIGIL, color, true)

## Every fire back to full in the Warden's red.
func _relight_red(dur: float) -> void:
	for pair in [["sigil_heat", 1.0], ["sigil_gold", 0.0], ["fire_heat", 1.0], ["fire_lean", 0.0], ["throne_ash", 0.0]]:
		_ramp(game.room, pair[0], pair[1], dur)
	_ramp(game, "sconce_heat", 1.0, dur)
	_ambient_live = true
	_ramp(self, "ambient", game.mood.ambient, dur)

## The fallen kneel to their Warden, from the wings inward.
func _kneel_all() -> void:
	for f in _fallen:
		var wave := (430.0 - absf(f.position.x - Cast.THRONE_X)) / 46.0 * 0.12
		_after(maxf(wave, 0.0), f.set.bind("gesture", "kneel"))

# --- V. GIVE THEM BACK ------------------------------------------------------------

## The gather: hold IGNITE and the title's question plays a note at a time,
## each note sending the next flames home to their knights. The brief cut
## gathers by itself at double speed; with no one lost, there is nothing to
## give back and the knight simply lets the crown go.
func _give_back() -> void:
	if _fallen.is_empty():
		phase = Phase.LETGO
		_after(1.0, _let_go)
	elif tier == "brief":
		_begin_gather(true)
	else:
		phase = Phase.PROMPT
		_prompt.visible = true
		_after(float(_cut.auto), _auto_start)

func _auto_start() -> void:
	if phase == Phase.PROMPT:
		_begin_gather(true)

func _begin_gather(auto: bool) -> void:
	phase = Phase.GATHER
	_prompt.visible = true
	_auto = auto
	_ring_notes()

func _gather_held() -> bool:
	return GATHER_KEYS.any(func(action): return Input.is_action_pressed(action))

## Reads the gather keys. Holding plays the question a note at a time; letting
## go pauses it and loses nothing, a tap always rings one more note, and a
## pause of 3 s resumes by itself. After the C#, letting go is LET GO: held on,
## they are let go after 2.5 s anyway.
func _poll_gather(dt: float) -> void:
	var held := _gather_held()
	var pressed := held and not _held
	_held = held
	match phase:
		Phase.PROMPT:
			if pressed:
				_begin_gather(false)
		Phase.GATHER:
			if pressed and _note < Content.GATHER_LINE.size():
				_gather_goal = maxf(_gather_goal, float(Content.GATHER_LINE[_note][0]))
			if held or _auto or _gather_t < _gather_goal:
				_gather_t += dt * (2.0 if tier == "brief" else 1.0)
				_idle = 0.0
				_knight.gesture_to("raise", 30.0)
			else:
				# Released: the blade dips and nothing more goes home, nothing is lost.
				_idle += dt
				_auto = _idle >= 3.0
				_knight.gesture_to("", 12.0)
			_ring_notes()
		Phase.LETGO:
			if is_instance_valid(_prompt) and _prompt.let_go:
				_letgo_t += dt
				_letgo_held = _letgo_held or held
				var limit := 2.5 if _letgo_held else (0.3 if tier == "brief" else 0.8)
				if (_letgo_held and not held) or _letgo_t >= limit:
					_let_go()

## Rings every note of the question the held time has reached; each sends the
## next group of flames from the hoard home to their knights.
func _ring_notes() -> void:
	var line := Content.GATHER_LINE
	var n := _fallen.size()
	while _note < line.size() and _gather_t >= float(line[_note][0]):
		game.feedback.play("grave_bell", pow(2.0, (float(line[_note][1]) - 74.0) / 12.0), -6.0, false)
		for i in range(floori(float(_note * n) / line.size()), floori(float((_note + 1) * n) / line.size())):
			_return_flame(i)
		_note += 1
		_prompt.ticks = _note
	if _note >= line.size() and phase == Phase.GATHER:
		phase = Phase.LETGO
		_letgo_t = 0.0
		_letgo_held = _held
		_prompt.let_go = true

## A flame goes home: it arcs down onto its knight's head, which relights (a
## crossfade under reduced motion), on a note of a D-major pentatonic.
func _return_flame(i: int) -> void:
	var f: Cast.FinaleFallen = _fallen[i]
	_hoard.send(i, f.crown_point(), 0.6, _relit.bind(i))
	if Feedback.motion_reduced:
		_crowns.set_lit(i, 1.0, 0.5)

func _relit(i: int) -> void:
	_crowns.set_lit(i, 1.0)
	_sound("fold", Content.FOLD_MAJOR[i % Content.FOLD_MAJOR.size()], -8.0, false)

## LET GO: the knight lowers the blade and lets them go. The emptied crown goes
## out and the starved throne greys; the keep burns away from the top down to
## the open sky, and the fallen climb the well one by one to become stars. The
## knight stays below, looking up, its flame the last one left.
func _let_go() -> void:
	phase = Phase.SKY
	_prompt.visible = false
	_knight.gesture_to("", 6.0)
	_stop_cue("curtain_hold", 0.3)
	if not _cue("curtain_b1"):
		game.feedback.play("victory")
	_ramp(_relic, "burn", 0.0, 0.8)
	_starve(1.6)
	_after(1.0, _hand_off.bind(Color.WHITE))
	_after(1.0, _stand_rostrum)
	_after(1.2, _begin_burn.bind(float(_cut.burn)))
	if float(_cut.tilt) > 0.0:
		_after(2.2, _move_camera.bind([_sky.well_top(), 1.0], float(_cut.tilt)))
	else:
		_after(1.4, _move_camera.bind(_look_up_frame(), 1.5))
	_after(3.0 * _pace(), _release_fallen)
	_b0 = clock + float(_cut.lead) - float(_cut.call) * BEAT
	_at(_beat(float(_cut.call)), _open_b2)
	if float(_cut.down) > 0.0:
		_at(_beat(float(_cut.down)), _move_camera.bind(_look_up_frame(), 4.0 * _pace()))
	_at(_beat(32.0), _last_word)

## Seconds on the clock of curtain_b2's beat `k`.
func _beat(k: float) -> float:
	return _b0 + k * BEAT

func _open_b2() -> void:
	_b2_playing = _cue("curtain_b2", float(_cut.call) * BEAT)

## Starved, the throne goes grey and cold, and every fire in the hall sinks.
func _starve(dur: float) -> void:
	for pair in [["sigil_heat", 0.0], ["fire_heat", 0.12], ["fire_lean", 0.0], ["throne_ash", 1.0]]:
		_ramp(game.room, pair[0], pair[1], dur)
	_ramp(game, "sconce_heat", 0.2, dur)
	_ambient_live = true
	_ramp(self, "ambient", STARVED_AMBIENT, dur)

## Each fallen flame leaves its knight and climbs the well; the paper knight it
## leaves folds back into the floor. Spread over some ten seconds, however many.
func _release_fallen() -> void:
	_knight.gesture_to("look_up", 3.0)
	var n := _fallen.size()
	var stagger := clampf(10.0 * _pace() / float(maxi(n, 1)), 0.1, 1.5)
	for i in range(n):
		_sky.add_rising((_fallen[i] as Cast.FinaleFallen).crown_point(), stagger * float(i))
		_after(stagger * float(i), _fold_away.bind(i))

## A fallen knight's crown goes (up the well, or out) and its page folds flat.
func _fold_away(i: int) -> void:
	var f: Cast.FinaleFallen = _fallen[i]
	_crowns.set_lit(i, -1.0)
	if Feedback.motion_reduced:
		_ramp(f, "modulate:a", 0.0, 0.4)
	else:
		_ramp(f, "hinge", 0.0, 0.45, Tween.TRANS_QUAD, Tween.EASE_IN)
	_sound("fold", Content.FOLD_MAJOR[i % Content.FOLD_MAJOR.size()] * 2.0, -12.0, false)

## The knight at the bottom of the frame with the open sky above it.
func _look_up_frame() -> Array:
	return [Vector2(_knight.position.x if is_instance_valid(_knight) else 640.0, Content.FLOOR_Y - 200.0), 1.4]

# --- V. END IT --------------------------------------------------------------------

## END IT: the knight climbs to the throne, raises the blade and strikes.
func _end_it() -> void:
	phase = Phase.DARK
	_stop_cue("curtain_hold", 0.8)
	_move_camera(THRONE, 2.0 * _pace())
	_knight.gesture_to("", 0.0)
	_knight.walk(Cast.THRONE_X + 66.0 * _side, 120.0, -_side, _raise_blade)

func _raise_blade() -> void:
	_knight.gesture_to("raise", 8.0)
	_after(0.8, _strike)

## The throne cracks in two, and every fire in the keep goes out: the sigil,
## the braziers, the sconces, the crown; the hoard rises away up the well in a
## thin column and the fallen fold back into the floor. In the dark, the card;
## then the dawn.
func _strike() -> void:
	_knight.gesture_to("thrust", 30.0)
	var fb := game.feedback
	fb.play("clang", 0.7)
	fb.play("shatter", 0.6)
	fb.play("slam", 0.7)
	fb.shake(10.0, 0.4)
	fb.rumble(0.7, 1.0, 0.4)
	_flare(VFX.HOT)
	_ramp(game.room, "throne_split", 1.0, 0.5, Tween.TRANS_BACK, Tween.EASE_OUT)
	_ash.puff(SIGIL + Vector2(0.0, 40.0), 28, Vector2(40.0, 70.0), 0.0)
	_after(0.4, _douse.bind(2.4))
	_after(0.5, _column)
	_after(3.0, _dark_well)
	_after(3.4, _card.bind(Content.FINALE_TEXT.dark, 3.2, 96.0))
	_after(6.2 * _pace(), _move_camera.bind([_sky.well_top(), 1.0], 3.0 * _pace()))
	_after(7.6 * _pace(), _dawn)

## Every fire out, one after another, and the hall falls dark; the knight's
## own flame sinks to an ember, and its light is set aside with it.
func _douse(dur: float) -> void:
	for pair in [["sigil_heat", 0.0, 0.2], ["fire_heat", 0.0, 0.5], ["fire_lean", 0.0, 0.5], ["throne_ash", 1.0, 1.0]]:
		_ramp(game.room, pair[0], pair[1], dur * float(pair[2]))
	_ramp(game, "sconce_heat", 0.0, dur)
	_ramp(_relic, "burn", 0.0, dur * 0.3)
	_ramp(_knight, "crown", 0.35, dur)
	_ambient_live = true
	_ramp(self, "ambient", DARK_AMBIENT, dur)
	_vignette_live = true
	_ramp(self, "vignette", DARK_EDGE, dur)
	for k in range(5):
		_after(dur * float(k) / 5.0, _sound.bind("snuff", randf_range(0.85, 1.15)))
	_after(dur, _set_light_follows.bind(false))

## LightRig lights the knight's flame wherever the hidden player stands; with
## that flame down to an ember, the player is set aside below the hall.
func _set_light_follows(follows: bool) -> void:
	_light_follows = follows
	if not follows:
		game.player.global_position = Vector2(Cast.THRONE_X, Content.FLOOR_Y + 4000.0)

## The hoard rises away in a thin column up the well and goes out; the fallen
## it belonged to fold back into the floor.
func _column() -> void:
	var n := _hoard.count()
	for i in range(n):
		var top := Vector2(Cast.THRONE_X + sin(float(i) * 2.3) * 8.0, -360.0)
		_after(0.08 * float(i), _hoard.send.bind(i, top, 2.6, Callable(), true))
	for i in range(_fallen.size()):
		_after(0.6 + 0.08 * float(i), _fold_away.bind(i))

## In the dark, the keep gives way to the bare well beneath it; only the
## broken throne and its dais stay, painted again over the well's floor.
func _dark_well() -> void:
	_hand_off(ambient)
	_throne = Cast.ThroneProxy.new()
	_throne.room = game.room
	_actors.add_child(_throne)
	_actors.move_child(_throne, 0)
	_sky_layer.visible = true
	_ramp(game._world_container, "modulate:a", 0.0, 0.8)

## A thin grey dawn spills down the well from its mouth, and the camera comes
## down with it to the knight by the broken throne.
func _dawn() -> void:
	var dur := 6.0 * _pace()
	_ramp(_sky, "dawn", 1.0, dur)
	_ramp(_actors, "modulate", DAWN_LIGHT, dur)
	_ramp(self, "vignette", Game.VIGNETTE_EDGE, dur)
	_move_camera(DAWN_FRAME, dur)
	_knight.gesture_to("look_up", 3.0)
	_b0 = clock + 1.0 - 24.0 * BEAT
	_at(_beat(24.0), _open_b2_from.bind(24.0))
	_at(_beat(32.0), _last_word)

func _open_b2_from(k: float) -> void:
	_b2_playing = _cue("curtain_b2", k * BEAT)

# --- The keep burns away ------------------------------------------------------------

## Moves the cast out of the world viewport onto the actor layer, keeping
## their draw order, before the keep is taken away: positions carry over
## unchanged because the layer shares the camera's canvas transform. The
## cast's light eases from the hall's to `light`.
func _hand_off(light: Color) -> void:
	if _handed_off:
		return
	_handed_off = true
	var cast := _cast()
	for node in game.world.get_children():
		if cast.has(node):
			node.reparent(_actors, false)
	_actors.modulate = ambient
	_ramp(_actors, "modulate", light, 1.5)

## The dais stands on as paper boxes when the rest of the keep burns.
func _stand_rostrum() -> void:
	_rostrum = Cast.Rostrum.new()
	_rostrum.modulate.a = 0.0
	_actors.add_child(_rostrum)
	_actors.move_child(_rostrum, 0)
	_ramp(_rostrum, "modulate:a", 1.0, 0.8)

## Burns the keep away from the top of the frame over `dur`, showing the sky
## beneath, and sheds ash along the front.
func _begin_burn(dur: float) -> void:
	var mat := FinaleSky.burn_away_material()
	mat.set_shader_parameter("aspect", float(Content.VIEW_W) / float(Content.VIEW_H))
	game._world_container.material = mat
	_burning = true
	_sky_layer.visible = true
	_ramp(self, "burn", 1.0, dur)
	_ramp(_sky, "reveal", 1.0, dur)
	_ash.rate = 40.0
	_after(dur, _ash.set.bind("rate", 0.0))
	game.feedback.play("burn")
	_after(1.4, game.feedback.play.bind("burn"))

## Where the burn's front crosses the frame, as a share of its height.
static func burn_front(progress: float) -> float:
	return lerpf(-0.1, 1.1, progress)

## The burn follows the camera, sheds ash along its front, and hides the whole
## world viewport once it has burned through.
func _apply_burn(view: Transform2D) -> void:
	var box := game._world_container
	(box.material as ShaderMaterial).set_shader_parameter("progress", burn)
	var sight := view.affine_inverse() * Rect2(Vector2.ZERO, box.size)
	_ash.bounds = sight
	_ash.front_y = sight.position.y + sight.size.y * burn_front(burn)
	if burn >= 1.0:
		box.visible = false
		_burning = false

# --- VI. The last word --------------------------------------------------------------

## The last epitaph the knight died to, quoted, and the ending's answer; then
## the results open.
func _last_word() -> void:
	phase = Phase.LAST_WORD
	if not _b2_playing:
		game.feedback.play("grave_bell", 1.0, 0.0, false)
	_final_card(0.6)
	_after(3.6, _fade_cards)
	_after(4.4, _finish.bind(false))

func _final_card(fade: float) -> void:
	var words := Content.finale_answer(str(ctx.get("last_epitaph", "")), int(ctx.get("falls_total", 0)), bool(ctx.get("unknown", false)), ending)
	for line in [[words.quote, 18, UI.C_MUTED, 450.0], [words.answer, 30, UI.C_TEXT, 488.0]]:
		if str(line[0]).is_empty():
			continue
		var label := _label(line[0], line[1], line[2], line[3])
		label.modulate.a = 0.0 if fade > 0.0 else 1.0
		_ramp(label, "modulate:a", 1.0, fade)

func _fade_cards() -> void:
	for label in _cards.get_children():
		_ramp(label, "modulate:a", 0.0, 0.8)

func _finish(skipped: bool) -> void:
	phase = Phase.DONE
	_skip.visible = false
	finished.emit(skipped)

# --- Skip and abort ---------------------------------------------------------------

## Holding pause skips. A first viewing advertises nothing and asks for 2 s
## (the ring shows after 0.5 s); repeat viewings caption the ring from the
## take-over and need 1 s. Letting go drains it three times as fast.
func _poll_skip(dt: float) -> void:
	if _skipping or phase >= Phase.LAST_WORD:
		return
	var first := int(ctx.get("finale_seen", 0)) == 0
	var need := 2.0 if first else 1.0
	if Input.is_action_pressed("pause"):
		_skip_hold += dt
	else:
		_skip_hold = maxf(0.0, _skip_hold - 3.0 * dt)
	_skip.fill = _skip_hold / need
	_skip.visible = _skip_hold > 0.5 if first else (phase != Phase.PROLOGUE or _skip_hold > 0.0)
	if _skip_hold >= need:
		skip_to_end()

## A dip to black, the chosen ending's last frame built at once (before the
## choice, the ending last chosen), then the final card and the results.
func skip_to_end() -> void:
	if _skipping or phase == Phase.DONE:
		return
	_skipping = true
	game._cancel_beat()
	_events.clear()
	_ramps.clear()
	_prompt.visible = false
	_choice.visible = false
	_skip.visible = false
	if ending.is_empty():
		ending = _default_ending()
		Save.set_last_ending(ending)
	_ramp(_dip, "color:a", 1.0, 0.3)
	_after(0.3, _final_state)
	_after(0.3, _ramp.bind(_dip, "color:a", 0.0, 0.3))
	_after(1.6, _finish.bind(true))

func _final_state() -> void:
	phase = Phase.LAST_WORD
	_free_cast()
	for card in _cards.get_children():
		card.queue_free()
	_stop_cues(0.3)
	_stand_in()
	_ash = Cast.AshField.new()
	_add_to_world(_ash, 3)
	_side = signf(_knight.position.x - Cast.THRONE_X) if _knight.position.x != Cast.THRONE_X else -1.0
	match ending:
		"crown":
			_relight_red(0.0)
			_knight.place(Cast.THRONE_X, -_side)
			_knight.grounded = false
			_knight.position = SEAT
			_knight.gesture_to("sit", 60.0)
			_knight.red = 1.0
			_frame_now(SEATED)
		"given":
			_starve(0.0)
			_knight.place(Cast.THRONE_X + 176.0 * _side, -_side)
			_knight.gesture_to("look_up", 60.0)
			_hand_off(Color.WHITE)
			_stand_rostrum()
			_begin_burn(0.0)
			_frame_now(_look_up_frame())
		"ended":
			_douse(0.0)
			_ramp(game.room, "throne_split", 1.0, 0.0)
			_knight.place(Cast.THRONE_X + 66.0 * _side, -_side)
			_knight.gesture_to("look_up", 60.0)
			_dark_well()
			_ramp(game._world_container, "modulate:a", 0.0, 0.0)
			_ramp(_actors, "modulate", DAWN_LIGHT, 0.0)
			_ramp(self, "vignette", Game.VIGNETTE_EDGE, 0.0)
			_sky.dawn = 1.0
			_frame_now(DAWN_FRAME)
	_final_card(0.0)

## Puts back everything the ending borrowed from the game; safe from any phase
## and safe twice. The layers, the cast on them and every scheduled event and
## ramp die with this node.
func abort() -> void:
	phase = Phase.DONE
	_events.clear()
	_ramps.clear()
	_free_cast()
	if not is_instance_valid(game):
		return
	var box := game._world_container
	box.material = null
	box.modulate = Color.WHITE
	box.visible = true
	var player := game.player
	if is_instance_valid(player):
		player.visible = true
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.cinematic = false
	game._reset_camera()
	game.feedback.calm_camera()
	game.sconce_heat = 1.0
	game._set_vignette(Game.VIGNETTE_EDGE)
	game._lights.set_ambient(game.mood.ambient)
	if is_instance_valid(game.room):
		for pair in [["sigil_heat", 1.0], ["fire_heat", 1.0], ["sigil_gold", 0.0], ["fire_lean", 0.0], ["throne_split", 0.0], ["throne_ash", 0.0]]:
			game.room.set(pair[0], pair[1])
	_stop_cues(0.0)

## Frees the cast wherever it stands, the world or the actor layer.
func _free_cast() -> void:
	for node in _cast():
		node.get_parent().remove_child(node)
		node.queue_free()
	_shell = null
	_burnt = null
	_relic = null
	_relic_held = false
	_hoard = null
	_knight = null
	_crowns = null
	_streams = null
	_ash = null
	_rostrum = null
	_throne = null
	_fallen.clear()
	_handed_off = false

# --- The director's machinery -----------------------------------------------------

## Every live cast member the director advances.
func _cast() -> Array:
	var out: Array = [_shell, _burnt, _relic, _hoard, _knight, _crowns, _streams, _ash, _rostrum, _throne]
	out.append_array(_fallen)
	return out.filter(func(node): return is_instance_valid(node))

## Cast joins the world after the room, at its gameplay z.
func _add_to_world(node: Node2D, z: int) -> void:
	node.z_index = z
	game.world.add_child(node)

## Travel and holds shrink with the shorter cuts.
func _pace() -> float:
	return float(_cut.pace)

## Schedules `action` on the event sheet `delay` seconds from now.
func _after(delay: float, action: Callable) -> void:
	_at(clock + delay, action)

func _at(time: float, action: Callable) -> void:
	var i := _events.size()
	while i > 0 and float(_events[i - 1][0]) > time:
		i -= 1
	_events.insert(i, [time, action])

## Animates `obj`'s property from its current value to `to` over `dur` seconds
## of the director's clock, replacing any ramp already driving it. A property
## the object lacks (a room without the finale's heat vars) is left alone.
func _ramp(obj: Object, prop: String, to: Variant, dur: float, trans: Tween.TransitionType = Tween.TRANS_SINE, ease: Tween.EaseType = Tween.EASE_IN_OUT) -> void:
	if not is_instance_valid(obj):
		return
	var path := NodePath(prop)
	var from = obj.get_indexed(path)
	if from == null:
		return
	_ramps = _ramps.filter(func(r): return is_instance_valid(r.obj) and not (r.obj == obj and r.prop == path))
	_ramps.append({ "obj": obj, "prop": path, "from": from, "to": to, "start": clock, "dur": maxf(dur, 0.001), "trans": trans, "ease": ease })

func _update_ramps() -> void:
	var i := 0
	while i < _ramps.size():
		var r: Dictionary = _ramps[i]
		var k := clampf((clock - float(r.start)) / float(r.dur), 0.0, 1.0)
		var alive := is_instance_valid(r.obj)
		if alive:
			(r.obj as Object).set_indexed(r.prop, Tween.interpolate_value(r.from, r.to - r.from, k, 1.0, r.trans, r.ease))
		if k >= 1.0 or not alive:
			_ramps.remove_at(i)
		else:
			i += 1

## Writes what the director animates onto the game, then gives every layer
## the world camera's canvas transform, which already carries the shake.
func _apply() -> void:
	if _ambient_live:
		game._lights.set_ambient(ambient)
	if _vignette_live:
		game._set_vignette(vignette)
	if _owns_camera:
		var camera := game.feedback.camera
		camera.global_position = cam_center
		camera.zoom = Vector2.ONE * cam_zoom
		camera.force_update_scroll()
	var view := game.world_view.canvas_transform
	_sky_layer.transform = view
	_actor_layer.transform = view
	if _burning:
		_apply_burn(view)
	if _prompt.visible and is_instance_valid(_knight):
		_prompt.position = view * _knight.position + Vector2(0.0, 58.0)
		_prompt.modulate.a = 1.0 if Feedback.motion_reduced else lerpf(0.65, 1.0, 0.5 + 0.5 * sin(clock * TAU * 1.2))

## Eases the virtual camera to a framing. Reduced motion never tweens it: it
## cuts to the held framing under a short dip to black.
func _move_camera(framing: Array, dur: float) -> void:
	if Feedback.motion_reduced:
		if not _owns_camera or cam_center != framing[0] or cam_zoom != framing[1]:
			_dip_cut(_frame_now.bind(framing), 0.35)
		return
	_ramp(self, "cam_center", framing[0], dur)
	_ramp(self, "cam_zoom", framing[1], dur)

func _frame_now(framing: Array) -> void:
	_ramps = _ramps.filter(func(r): return r.obj != self or (r.prop != NodePath("cam_center") and r.prop != NodePath("cam_zoom")))
	cam_center = framing[0]
	cam_zoom = framing[1]
	_owns_camera = true

## A dip to black; `action` runs unseen at the bottom.
func _dip_cut(action: Callable, total: float) -> void:
	_ramp(_dip, "color:a", 1.0, total * 0.5)
	_after(total * 0.5, action)
	_after(total * 0.5, _ramp.bind(_dip, "color:a", 0.0, total * 0.5))

## A card across the frame at height `y`: 0.4 s in, held, 0.4 s out.
func _card(text: String, hold: float, y: float, size: int = 30, color: Color = UI.C_TEXT) -> void:
	var label := _label(text, size, color, y)
	label.modulate.a = 0.0
	_ramp(label, "modulate:a", 1.0, 0.4)
	_after(0.4 + hold, _ramp.bind(label, "modulate:a", 0.0, 0.4))
	_after(0.8 + hold, label.queue_free)

## Serif text centred across the frame at height `y`, with the dark outline
## every finale line carries so it reads over fire and over black.
func _label(text: String, size: int, color: Color, y: float) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UI._heading_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(VFX.VOID, 0.6))
	label.add_theme_constant_override("outline_size", 6)
	label.position = Vector2(0.0, y - float(size))
	label.size = Vector2(Content.VIEW_W, float(size) * 2.0)
	_cards.add_child(label)
	return label

## Plays a cue at most 12 times a second, so a row of folds or snuffed fires
## reads as a flurry rather than a wall of sound.
func _sound(cue: String, pitch: float = 1.0, volume_db: float = 0.0, humanize: bool = true) -> void:
	if clock - float(_sounded.get(cue, -1.0)) < 1.0 / 12.0:
		return
	_sounded[cue] = clock
	game.feedback.play(cue, pitch, volume_db, humanize)

## The ending's cues come with the score's cue book. Until one is rendered, or
## with music off, the ending plays its sound-effect fallbacks instead.
func _cue(cue: String, from: float = 0.0) -> bool:
	var music: Node = game.music
	if not (music.has_method("has_cue") and music.enabled and music.has_cue(cue)):
		return false
	music.play_cue(cue, from)
	return true

func _stop_cue(cue: String, fade: float) -> void:
	if game.music.has_method("stop_cue"):
		game.music.stop_cue(cue, fade)

func _stop_cues(fade: float) -> void:
	if game.music.has_method("stop_cues"):
		game.music.stop_cues(fade)

## The sky (-1, behind the world), the actors (10) and the text (45: above the
## vignette at 40, under the UI at 50).
func _build_layers() -> void:
	_sky_layer = _layer("SkyLayer", -1)
	_sky = FinaleSky.new()
	# The director's clock drives the risers too, when the sky lets it.
	_sky.set("autostep", false)
	_sky_layer.add_child(_sky)
	_sky_layer.visible = false
	_actor_layer = _layer("ActorLayer", 10)
	_actors = Node2D.new()
	_actors.name = "Actors"
	_actor_layer.add_child(_actors)
	var text := _full_rect(Control.new(), _layer("TextLayer", 45))
	_cards = _full_rect(Control.new(), text)
	_prompt = FinalePrompt.new()
	_prompt.visible = false
	text.add_child(_prompt)
	_choice = _full_rect(ChoicePrompt.new(), text)
	_choice.visible = false
	_skip = _full_rect(SkipRing.new(), text)
	_skip.visible = false
	_dip = _full_rect(ColorRect.new(), text)
	_dip.color = Color(0.0, 0.0, 0.0, 0.0)

func _layer(layer_name: String, index: int) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = layer_name
	layer.layer = index
	add_child(layer)
	return layer

func _full_rect(control: Control, parent: Node) -> Control:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return control

## A key cap in the house style: the key's name on a dark rounded box, its rim
## gold when it matters now. Returns the cap's width.
static func draw_key_cap(ci: CanvasItem, x: float, key: String, gold: bool) -> float:
	var font := UI._heading_font()
	var width := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 16.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UI.C_INK, 0.9)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.border_color = UI.C_GOLD if gold else UI.C_EDGE
	ci.draw_style_box(box, Rect2(x, -14.0, width, 28.0))
	ci.draw_string(font, Vector2(x + 8.0, 6.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.C_TEXT)
	return width

## Outlined serif word with its left edge at `x`, on the baseline at y 6.
static func draw_word(ci: CanvasItem, x: float, text: String, size: int, color: Color, y: float = 6.0) -> void:
	var font := UI._heading_font()
	ci.draw_string_outline(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(VFX.VOID, 0.6))
	ci.draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## The choice, low in the frame in the house's serif: the endings side by side,
## the one in hand in gold between two chevrons, its rule filling as the hold
## keeps it; under them, how to choose on the device last touched.
class ChoicePrompt extends Control:
	const WORD := 26
	const GAP := 72.0
	var options: Array = []:
		set(value):
			options = value
			queue_redraw()
	var selected := -1:
		set(value):
			selected = value
			queue_redraw()
	var fill := 0.0:
		set(value):
			if value != fill:
				fill = value
				queue_redraw()

	func _draw() -> void:
		var font := UI._heading_font()
		var widths: Array = options.map(func(o): return font.get_string_size(o, HORIZONTAL_ALIGNMENT_LEFT, -1, WORD).x)
		var total: float = widths.reduce(func(a, b): return a + b, 0.0) + GAP * float(maxi(options.size() - 1, 0))
		var x := (size.x - total) * 0.5
		var y := size.y - 118.0
		for i in range(options.size()):
			var w: float = widths[i]
			var chosen := i == selected
			Finale.draw_word(self, x, options[i], WORD, UI.C_GOLD if chosen else UI.C_MUTED, y)
			draw_line(Vector2(x, y + 12.0), Vector2(x + w, y + 12.0), Color(UI.C_EDGE, 0.5), 2.0)
			if chosen:
				draw_line(Vector2(x, y + 12.0), Vector2(x + w * clampf(fill, 0.0, 1.0), y + 12.0), UI.C_GOLD, 3.0)
				for side: float in [-1.0, 1.0]:
					var tip := Vector2(x + w * 0.5 + side * (w * 0.5 + 22.0), y - 8.0)
					draw_colored_polygon(PackedVector2Array([tip, tip - Vector2(side * 8.0, -6.0), tip - Vector2(side * 8.0, 6.0)]), UI.C_GOLD)
			x += w + GAP
		# How to choose: left and right, then hold.
		var key := UI.prompt("ui_accept").trim_prefix("[").trim_suffix("]")
		var hold := str(Content.FINALE_TEXT.hold)
		var verb := str(Content.FINALE_TEXT.choose)
		var small := 18
		var hold_w := font.get_string_size(hold, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		var verb_w := font.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		var cap_w := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 16.0
		var line_w := 44.0 + hold_w + 10.0 + cap_w + 10.0 + verb_w
		draw_set_transform(Vector2((size.x - line_w) * 0.5, y + 50.0))
		for side: float in [-1.0, 1.0]:
			var tip := Vector2(14.0 + side * 12.0, 0.0)
			draw_colored_polygon(PackedVector2Array([tip, tip - Vector2(side * 9.0, -7.0), tip - Vector2(side * 9.0, 7.0)]), UI.C_TEXT)
		var cx := 44.0
		Finale.draw_word(self, cx, hold, small, UI.C_TEXT)
		cx += hold_w + 10.0
		cx += Finale.draw_key_cap(self, cx, key, selected >= 0) + 10.0
		Finale.draw_word(self, cx, verb, small, UI.C_TEXT)
		draw_set_transform(Vector2.ZERO)


## HOLD [Q / RT] IGNITE under the knight: a seven-tick ring that gains a tick
## per note of the question, and LET GO in gold once the C# hangs.
class FinalePrompt extends Control:
	var ticks := 0:
		set(value):
			ticks = value
			queue_redraw()
	var let_go := false:
		set(value):
			let_go = value
			queue_redraw()
	var _key := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var binding := UI._binding_text("ignite")
		_key = str(binding.key)
		if not Input.get_connected_joypads().is_empty() and not str(binding.pad).is_empty():
			_key += " / " + str(binding.pad)

	func _draw() -> void:
		var font := UI._heading_font()
		var left := "" if let_go else str(Content.FINALE_TEXT.hold)
		var right := str(Content.FINALE_TEXT.let_go if let_go else Content.FINALE_TEXT.ignite)
		var word := 18
		var gap := 10.0
		var cap_w := font.get_string_size(_key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 16.0
		var left_w := font.get_string_size(left, HORIZONTAL_ALIGNMENT_LEFT, -1, word).x
		var right_w := font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, word).x
		var x := -(26.0 + gap + (left_w + gap if not left.is_empty() else 0.0) + cap_w + gap + right_w) * 0.5
		var ring := Vector2(x + 13.0, 0.0)
		for j in range(7):
			var dir := Vector2.UP.rotated(TAU * float(j) / 7.0)
			draw_line(ring + dir * 7.0, ring + dir * 12.0, UI.C_GOLD if j < ticks else UI.C_EDGE, 2.5, true)
		x += 26.0 + gap
		if not left.is_empty():
			Finale.draw_word(self, x, left, word, UI.C_TEXT)
			x += left_w + gap
		x += Finale.draw_key_cap(self, x, _key, let_go) + gap
		Finale.draw_word(self, x, right, word, UI.C_GOLD if let_go else UI.C_TEXT)


## The skip ring, bottom right: a paper disc filling with an ember edge, with
## HOLD ESCAPE TO SKIP beside it on repeat viewings.
class SkipRing extends Control:
	var fill := 0.0:
		set(value):
			if value != fill:
				fill = value
				queue_redraw()
	var caption := ""

	func _draw() -> void:
		var c := size - Vector2(44.0, 44.0)
		draw_circle(c, 16.0, Color(UI.C_INK, 0.85))
		draw_arc(c, 16.0, 0.0, TAU, 32, Color(UI.C_EDGE, 0.9), 1.5, true)
		if fill > 0.0:
			draw_arc(c, 13.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(fill, 0.0, 1.0), 32, UI.C_EMBER, 4.0, true)
		if not caption.is_empty():
			var font := UI._heading_font()
			var w := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string_outline(font, c + Vector2(-28.0 - w, 5.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(VFX.VOID, 0.6))
			draw_string(font, c + Vector2(-28.0 - w, 5.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.C_MUTED)
