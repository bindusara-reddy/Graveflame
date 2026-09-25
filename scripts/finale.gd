class_name Finale
extends Node
## "Strike the Set": the ending, directed from the killing blow to the results
## panel. The Warden's hoard returns one flame to each paper knight it took; the
## player's held IGNITE gathers their fire while the knight's crown plays the
## title's unanswered question, and LET GO gives it to the throne; the keep
## burns off its frame to show the stage it was always painted on, and the
## fallen, the Warden and the knight take their bows before the curtain falls.
##
## Everything runs on this node's own real-time clock (step), from an event
## sheet anchored to the kill, the take-over, the prompt, the LET GO (I) and the
## curtain call's downbeat (B0). The timeline never waits on audio, frame rate
## or Engine.time_scale, and a test can drive it frame by frame (autostep off).
## Every tween is a ramp on that clock, every layer and actor is created here,
## and abort() puts back everything borrowed from the game, from any phase.

const VFX := preload("res://scripts/vfx.gd")
const Cast := preload("res://scripts/finale_actors.gd")

signal finished(skipped: bool)

enum Phase { PROLOGUE, HOARD, COLD, WALK, PROMPT, GATHER, LETGO, STRIKE, BURN, CALL, CURTAIN, EMBER, DONE }

## curtain_b2 runs at 84 bpm; every B event lands on its beats.
const BEAT := 60.0 / 84.0
## Held framings as [centre, zoom]. Reduced motion cuts between exactly these.
const HALL := [Vector2(640.0, 390.0), 1.0]
const THRONE := [Vector2(620.0, 480.0), 1.55]
const THEATRE := [Vector2(640.0, 300.0), 0.86]
## The push for the knight's bow, which reduced motion leaves out.
const BOW_FRAME := [Vector2(640.0, 440.0), 1.12]
const SIGIL := Vector2(640.0, 438.0)
const SIGIL_FLAME := Vector2(640.0, 454.0)
const EMBER_TOP := Vector2(640.0, 330.0)
const WARDEN_Y := 460.0
const COLD_AMBIENT := Color(0.46, 0.42, 0.58)
const CURTAIN_DARK := Color(0.01, 0.0, 0.02, 0.9)
const GATHER_KEYS := ["ignite", "attack", "interact"]
## Per cut, in seconds: when the prompt starts by itself, the burn, when and how
## long the camera pulls back, when the footlights and the traveler go, the lead
## from LET GO to the call, and the curtain_b2 beat the call opens on.
const CUTS := {
	"full": { "auto": 5.0, "burn": 4.8, "pull_at": 1.8, "pull": 5.0, "lamps_at": 3.0, "traveler_at": 5.4, "lead": 7.14, "call": 0 },
	"abridged": { "auto": 2.5, "burn": 3.5, "pull_at": 0.4, "pull": 3.5, "lamps_at": 2.0, "traveler_at": 3.6, "lead": 7.14, "call": 16 },
	"brief": { "auto": 0.0, "burn": 2.5, "pull_at": 0.4, "pull": 2.5, "lamps_at": 1.0, "traveler_at": 1.4, "lead": 2.5, "call": 24 },
}

## Tests turn this off and call step() themselves.
var autostep := true
var game: Game
## Save.record_victory()'s result plus vows, boons, gold and tier (see Game._victory).
var ctx: Dictionary = {}
var tier := "full"
var phase: Phase = Phase.PROLOGUE
## Real seconds since the killing blow.
var clock := 0.0
## What the director animates and writes onto the game every step.
var cam_center := Vector2.ZERO
var cam_zoom := 1.0
var ambient := Color.WHITE
var vignette := Game.VIGNETTE_EDGE
var burn := 0.0

var _events: Array = []
var _ramps: Array = []
var _sounded: Dictionary = {}
var _owns_camera := false
var _ambient_live := false
var _vignette_live := false
var _burning := false
var _handed_off := false
var _skipping := false
var _b0 := 0.0
var _b2_playing := false
var _side := -1.0
# Layers and the theatre on them.
var _stage_layer: CanvasLayer
var _actor_layer: CanvasLayer
var _front_layer: CanvasLayer
var _actors: Node2D
var _cards: Control
var _dip: ColorRect
var _prompt: FinalePrompt
var _skip: SkipRing
var _stage: FinaleStage
var _front: FinaleStage.FinaleFront
var _bill: FinaleStage.Playbill
# The cast.
var _hoard: Cast.HoardField
var _knight: Cast.FinaleKnight
var _fallen: Array = []
var _crowns: Cast.CrownField
var _streams: Cast.FlameStream
var _warden: Cast.FinaleWarden
var _ash: Cast.AshField
var _crowd := 0
var _elder := false
# The gather: held time along Content.GATHER_LINE.
var _gather_t := 0.0
var _gather_goal := 0.0
var _note := 0
var _gathered := 0
var _auto := false
var _idle := 0.0
var _held := false
var _letgo_t := 0.0
var _letgo_held := false
var _skip_hold := 0.0

## Builds the layers and the hoard. The Finale starts in PROLOGUE while the
## game's own victory beat plays out in slow motion.
func setup(g: Game, context: Dictionary) -> void:
	game = g
	ctx = context
	tier = str(ctx.get("tier", "full"))
	process_mode = Node.PROCESS_MODE_ALWAYS
	var unknown := bool(ctx.get("unknown", false))
	_elder = int(ctx.get("falls_since", 0)) == 0 and not unknown
	if unknown:
		_crowd = Content.UNCOUNTED_CROWD
	elif _elder:
		_crowd = Content.ELDERS
	else:
		_crowd = mini(int(ctx.falls_since), Content.FALLEN_CAP)
	_build_layers()
	_hoard = Cast.HoardField.new()
	_hoard.elder = _elder
	_add_to_world(_hoard, 2)

func phase_name() -> String:
	return Phase.keys()[phase]

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
	_poll_gather(real_dt)
	while not _events.is_empty() and float(_events[0][0]) <= clock and phase != Phase.DONE:
		(_events.pop_front()[1] as Callable).call()
	_update_ramps()
	var world_dt := real_dt * Engine.time_scale if phase == Phase.PROLOGUE else real_dt
	for actor in _cast():
		# Until the take-over the hoard hangs in the world's slow motion.
		actor.advance(world_dt if actor == _hoard else real_dt)
	if is_instance_valid(_knight) and not _handed_off:
		game.player.global_position = _knight.position
	_apply()

# --- Act I: the hoard --------------------------------------------------------

## The shatter releases the hoard: one flame per knight the Warden took.
func release_hoard(pos: Vector2) -> void:
	if is_instance_valid(_hoard) and not _hoard.released:
		_hoard.release(pos, _crowd)

## The victory beat has ended: the director takes the camera and the stage.
## The tree keeps running, so the braziers and the atmosphere live on.
func take_over() -> void:
	if phase != Phase.PROLOGUE or _skipping:
		return
	phase = Phase.HOARD
	var camera := game.feedback.camera
	game.feedback.end_slow_motion()
	_stand_in()
	cam_center = camera.global_position
	cam_zoom = camera.zoom.x
	_owns_camera = not Feedback.motion_reduced
	ambient = game.mood.ambient
	release_hoard(_boss_point())
	_hoard.gather_to_ring()
	_spawn_crowd()
	_cue("curtain_a")
	if int(ctx.get("finale_seen", 0)) > 0:
		_skip.caption = Content.FINALE_TEXT.skip % str(UI._binding_text("pause").key).to_upper()
	var n := maxi(_fallen.size(), 1)
	match tier:
		"full":
			_move_camera(HALL, 3.0)
			_after(0.2, _card.bind("keep"))
			_after(3.6, _card.bind("back"))
			_pop_ups(3.8, clampf(2.0 / n, 0.10, 0.30))
			_after(7.1, _card.bind("cold"))
			_after(7.2, _walk)
		"abridged":
			_move_camera(HALL, 2.0)
			_after(0.2, _card.bind("again"))
			_pop_ups(0.6, clampf(1.2 / n, 0.06, 0.2))
			_after(3.2, _dip_cut.bind(_at_throne, 0.25))
		_:
			_move_camera(HALL, 1.0)
			_pop_ups(0.2, 0.0)
			_after(1.0, _dip_cut.bind(_at_throne, 0.25))

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

## Stations beside the dais, filled inner to outer and alternating sides, front
## rank first; the back rank stands smaller and darker behind. None comes within
## 200 px of centre (the rostrum is the hero's) or 36 px of where the knight
## stands. The outermost front pair is a spare for the ones the knight blocks.
static func stations(knight_x: float) -> Array:
	var out: Array = []
	# [first k, last k + 1, inner x, scale, back rank]
	for rank in [[0, 5, 200.0, 1.0, false], [0, 3, 223.0, 0.86, true], [5, 6, 200.0, 1.0, false]]:
		for k in range(rank[0], rank[1]):
			for side: float in [-1.0, 1.0]:
				var x := Cast.THRONE_X + side * (float(rank[2]) + 46.0 * float(k))
				if absf(x - knight_x) >= 36.0:
					out.append({ "x": x, "scale": rank[3], "back": rank[4] })
	return out

## Builds the crowd folded flat and hidden, back rank first so it draws behind,
## then the one crown field over them and the stream layer.
func _spawn_crowd() -> void:
	var places := stations(_knight.position.x).slice(0, _crowd)
	_fallen.resize(places.size())
	for back: bool in [true, false]:
		for i in range(places.size()):
			if bool(places[i].back) == back:
				var f := Cast.FinaleFallen.new()
				f.setup(places[i], i, _elder)
				f.visible = false
				_fallen[i] = f
				_add_to_world(f, 0)
	_crowns = Cast.CrownField.new()
	_crowns.elder = _elder
	for f in _fallen:
		_crowns.add(f)
	_add_to_world(_crowns, 0)
	_streams = Cast.FlameStream.new()
	_add_to_world(_streams, 2)

## Sends the hoard down a flame at a time; each lands as the crown of a paper
## knight folding up beneath it. The throne goes cold once the last settles.
func _pop_ups(start: float, stagger: float) -> void:
	for i in range(_fallen.size()):
		_after(start + stagger * float(i), _descend.bind(i))
	_after(start + stagger * float(maxi(_fallen.size() - 1, 0)) + 0.6, _cool)

func _descend(i: int) -> void:
	var f: Cast.FinaleFallen = _fallen[i]
	var still := Feedback.motion_reduced
	_hoard.descend(i, f.crown_at_rest(), 0.25 if still else 0.6, _crowns.set_lit.bind(i, 1.0, 0.0))
	if still:
		# Reduced motion: the page fades in already standing.
		f.hinge = 1.0
		f.visible = true
		f.modulate.a = 0.0
		_ramp(f, "modulate:a", 1.0, 0.25)
		_crowns.set_lit(i, 1.0)
		_fold_note(i)
	else:
		_after(0.28, _hinge_up.bind(i))

func _hinge_up(i: int) -> void:
	var f: Cast.FinaleFallen = _fallen[i]
	f.visible = true
	_ramp(f, "hinge", 1.0, 0.32, Tween.TRANS_BACK, Tween.EASE_OUT)
	_fold_note(i)

## Each fold rings a plucked note climbing a D-minor pentatonic.
func _fold_note(i: int) -> void:
	game.feedback.play("fold", Content.FOLD_MINOR[i % Content.FOLD_MINOR.size()], -4.0, false)

## The throne goes cold: the sigil gutters out, the fires sink to a third and
## the hall cools toward blue.
func _cool() -> void:
	phase = Phase.COLD
	_ramp(game.room, "sigil_heat", 0.0, 1.2)
	_ramp(game.room, "fire_heat", 0.35, 2.0)
	_ramp(game, "sconce_heat", 0.35, 2.0)
	_ambient_live = true
	_ramp(self, "ambient", COLD_AMBIENT, 2.0)

## Where the knight stops before the seat, on the side it came from.
func _throne_stop() -> float:
	_side = signf(_knight.position.x - Cast.THRONE_X)
	if _side == 0.0:
		_side = -1.0
	return Cast.THRONE_X + 44.0 * _side

## The knight walks, unhurried, up the dais steps to the cold seat, and every
## paper crown leans toward the throne.
func _walk() -> void:
	phase = Phase.WALK
	var stop := _throne_stop()
	_knight.gesture_to("", 0.0)
	_knight.walk(stop, clampf(absf(stop - _knight.position.x) / 2.8, 170.0, 320.0), -_side, _arrive)
	_move_camera(THRONE, 3.2)
	_crowns.lean_x = Cast.THRONE_X
	_ramp(_crowns, "lean", 0.6, 1.5)

## The shorter cuts skip the walk: under a dip the knight is at the seat.
func _at_throne() -> void:
	phase = Phase.WALK
	_knight.place(_throne_stop(), -_side)
	_frame_now(THRONE)
	_crowns.lean_x = Cast.THRONE_X
	_crowns.lean = 0.6
	_arrive()

# --- Act II: the throne -----------------------------------------------------

## At the throne. The brief cut gathers by itself at double speed; the others
## ask the player to hold IGNITE and start by themselves if nobody does.
func _arrive() -> void:
	if tier == "brief":
		_begin_gather(true)
		return
	phase = Phase.PROMPT
	_prompt.visible = true
	_cue("curtain_hold")
	_after(float(CUTS[tier].auto), _auto_start)

func _auto_start() -> void:
	if phase == Phase.PROMPT:
		_begin_gather(true)

func _begin_gather(auto: bool) -> void:
	phase = Phase.GATHER
	_auto = auto
	_ring_notes()

func _gather_held() -> bool:
	for action in GATHER_KEYS:
		if Input.is_action_pressed(action):
			return true
	return false

## Reads the gather keys. Holding plays the question a note at a time; letting
## go pauses it and loses nothing, a tap always rings one more note, and a
## pause of 3 s resumes by itself. After the C#, letting go is LET GO: held on,
## the fire leaves after 2.5 s anyway.
func _poll_gather(dt: float) -> void:
	var held := _gather_held()
	var pressed := held and not _held
	_held = held
	match phase:
		Phase.PROMPT:
			if pressed:
				_begin_gather(false)
		Phase.GATHER:
			if pressed and tier == "brief":
				_strike()
				return
			if pressed and _note < Content.GATHER_LINE.size():
				_gather_goal = maxf(_gather_goal, float(Content.GATHER_LINE[_note][0]))
			if held or _auto or _gather_t < _gather_goal:
				_gather_t += dt * (2.0 if tier == "brief" else 1.0)
				_idle = 0.0
				_knight.gesture_to("raise", 30.0)
			else:
				# Released: the blade dips and the stream stops, nothing is lost.
				_idle += dt
				_auto = _idle >= 3.0
				_knight.gesture_to("", 12.0)
			_ring_notes()
		Phase.LETGO:
			_letgo_t += dt
			_letgo_held = _letgo_held or held
			var limit := 2.5 if _letgo_held else (0.3 if tier == "brief" else 0.8)
			if (_letgo_held and not held) or _letgo_t >= limit:
				_strike()

## Rings every note of the question the held time has reached. Each lifts the
## next group of flames off the paper knights' heads toward the knight's crown.
func _ring_notes() -> void:
	var line := Content.GATHER_LINE
	var n := _fallen.size()
	while _note < line.size() and _gather_t >= float(line[_note][0]):
		game.feedback.play("grave_bell", pow(2.0, (float(line[_note][1]) - 74.0) / 12.0), -6.0, false)
		for i in range(floori(float(_note * n) / line.size()), floori(float((_note + 1) * n) / line.size())):
			_lift(i)
		_note += 1
		_prompt.ticks = _note
	if _note >= line.size() and phase == Phase.GATHER:
		phase = Phase.LETGO
		_letgo_t = 0.0
		_letgo_held = _held
		_prompt.let_go = true

## A crown lent: a charred stub stays on the head while the flame arcs into
## the knight's crown (a crossfade under reduced motion).
func _lift(i: int) -> void:
	var f: Cast.FinaleFallen = _fallen[i]
	var still := Feedback.motion_reduced
	_crowns.set_lit(i, 0.0, 0.5 if still else 0.0)
	_streams.launch(f.crown_point, _knight.head_point, 0.5 if still else 0.6, _lent)

func _lent() -> void:
	_gathered += 1
	_knight.gold = true
	_knight.crown = lerpf(1.0, 1.9, float(_gathered) / float(maxi(_fallen.size(), 1)))

## LET GO. The knight thrusts the burning blade into the backrest; this moment
## is I, the anchor for the burn, the theatre and the curtain call.
func _strike() -> void:
	phase = Phase.STRIKE
	var i := clock
	var cut: Dictionary = CUTS[tier]
	_prompt.visible = false
	_knight.gesture_to("thrust", 30.0)
	_knight.crown = 2.0
	game.feedback.play("kindle")
	_stop_cue("curtain_hold", 0.2)
	if not _cue("curtain_b1"):
		# Without the cue, the D-major bell arpeggio is the chord.
		game.feedback.play("victory")
	_streams.launch(_knight.blade_tip, func() -> Vector2: return SIGIL_FLAME, 0.25, Callable(), 0.0)
	_after(0.25, _flare)
	_after(0.3, _begin_burn)
	_after(0.4, _set_phase.bind(Phase.BURN))
	_after(float(cut.pull_at), _show_front)
	_after(float(cut.pull_at), _move_camera.bind(THEATRE, float(cut.pull)))
	_after(float(cut.lamps_at), _light_lamps)
	_after(float(cut.traveler_at), _ramp.bind(_stage, "closed", 1.0, 1.6 if tier != "brief" else 1.0))
	_b0 = i + float(cut.lead) - float(cut.call) * BEAT
	_schedule_call()

func _set_phase(p: Phase) -> void:
	phase = p

## The throne takes the flame: the dead sigil bursts gold-white, not the
## Warden's red, and under that flash the cast steps onto the stage.
func _flare() -> void:
	_ramp(game.room, "sigil_heat", 1.2 if Feedback.flash_reduced else 1.4, 0.2)
	_ramp(game.room, "sigil_gold", 1.0, 0.2)
	var fb := game.feedback
	if Feedback.flash_reduced:
		fb._add_ring(SIGIL, VFX.GOLD, 12.0, 90.0, 0.5, 4.0)
	else:
		fb.flash_death(SIGIL, VFX.GOLD, true)
	fb.shake(6.0, 0.3)
	_hand_off()

## Moves the cast out of the world viewport onto the actor layer, keeping
## their draw order. Positions carry over unchanged because the layer shares
## the camera's canvas transform; the stage light comes up from the hall's.
func _hand_off() -> void:
	_handed_off = true
	var cast := _cast()
	for node in game.world.get_children():
		if cast.has(node):
			node.reparent(_actors, false)
	# The paper rostrum fades up over the painted dais before the burn takes it.
	var rostrum := Cast.Rostrum.new()
	rostrum.modulate.a = 0.0
	_actors.add_child(rostrum)
	_actors.move_child(rostrum, 0)
	_ramp(rostrum, "modulate:a", 1.0, 0.8)
	_ash = Cast.AshField.new()
	_ash.z_index = 3
	_actors.add_child(_ash)
	_actors.modulate = ambient
	_ramp(_actors, "modulate", Color.WHITE, 1.5)
	_ambient_live = false
	_stage_layer.visible = true

# --- Act III: strike the set -------------------------------------------------

## The set burns off its frame from the sigil outward (the theatre's burn-away
## on the world's container); what hasn't burned lifts a little on the heat.
func _begin_burn() -> void:
	var mat := FinaleStage.burn_away_material()
	mat.set_shader_parameter("aspect", float(Content.VIEW_W) / float(Content.VIEW_H))
	game._world_container.material = mat
	_burning = true
	_ramp(self, "burn", 1.0, float(CUTS[tier].burn))
	_ramp(_stage, "remnant_heat", 0.0, 5.0)
	_ash.rate = 40.0
	game.feedback.play("burn")
	_after(1.4, game.feedback.play.bind("burn"))

## The burn follows the sigil across the moving camera, sheds ash along its
## front, and hides the whole world viewport once it has burned through.
func _apply_burn(view: Transform2D) -> void:
	var box := game._world_container
	var mat := box.material as ShaderMaterial
	mat.set_shader_parameter("progress", burn)
	mat.set_shader_parameter("origin", (view * SIGIL) / box.size)
	if not Feedback.motion_reduced:
		box.position.y = -24.0 * burn
	var sight := view.affine_inverse() * Rect2(Vector2.ZERO, box.size)
	_ash.front_center = SIGIL
	_ash.front_radius = burn * sight.size.length()
	_ash.bounds = sight
	if burn >= 1.0:
		box.visible = false
		_burning = false
		_ash.rate = 0.0

## It was always a stage: the proscenium comes up around the burning hall.
func _show_front() -> void:
	_front_layer.visible = true
	_front.modulate.a = 0.0
	_ramp(_front, "modulate:a", 1.0, 1.0)

## The footlights kindle from the centre outward, one every 0.05 s.
func _light_lamps() -> void:
	for step in range(9):
		_after(step * 0.1, _set_lamp.bind(8 - step, 1.0, "footlight"))
		_after(step * 0.1 + 0.05, _set_lamp.bind(9 + step, 1.0, "footlight"))

func _set_lamp(i: int, value: float, sound: String) -> void:
	_front.lamps[i] = value
	_sound(sound, randf_range(0.9, 1.2) if sound == "snuff" else 1.0)

# --- Acts IV and V: curtain call and curtain ----------------------------------

## The curtain call on curtain_b2's beats. The full cut gives the fallen, the
## Warden and the knight a bow each; the shorter cuts open later in the cue and
## bow together. Every cut lands the rising flame on the resolving D (B32).
func _schedule_call() -> void:
	_at(_beat(float(CUTS[tier].call)), _open_call)
	match tier:
		"full":
			_at(_beat(2.0), _reveal.bind(1))
			_at(_beat(2.0), _homecoming.bind(0.8))
			_at(_beat(4.6), _fallen_bow)
			_at(_beat(8.0), _reveal.bind(2))
			_at(_beat(8.0), _warden_act.bind(1.0))
			_at(_beat(14.0), _knight_bow.bind(false))
			_at(_beat(20.0), _curtain.bind(0.22))
		"abridged":
			_at(_beat(16.0), _homecoming.bind(0.5))
			_at(_beat(16.8), _warden_act.bind(2.0))
			_at(_beat(20.0), _knight_bow.bind(true))
			_at(_beat(24.0), _curtain.bind(0.22))
		_:
			_at(_beat(24.0), _homecoming.bind(0.4))
			_at(_beat(24.8), _knight_bow.bind(true))
			_at(_beat(27.0), _curtain.bind(0.12))
	_at(_beat(30.04), _rise_ember)
	_at(_beat(32.0), _answer)
	_at(_beat(32.0) + 3.6, _bloom)
	_at(_beat(32.0) + 4.4, _finish.bind(false))

## Seconds on the clock of curtain_b2's beat `k`.
func _beat(k: float) -> float:
	return _b0 + k * BEAT

## The playbill is lowered on its cords as the title's bell melody begins, now
## in D major. The brief cut's bill fades in already hanging.
func _open_call() -> void:
	phase = Phase.CALL
	_b2_playing = _cue("curtain_b2", float(CUTS[tier].call) * BEAT)
	_bill.revealed = 0 if tier == "full" else _bill.rows.size()
	_front.spot_x = _knight.position.x
	if tier == "brief":
		_stop_cue("curtain_b1", 0.6)
		_bill.drop = 1.0
		_bill.modulate.a = 0.0
		_ramp(_bill, "modulate:a", 1.0, 0.4)
	else:
		_ramp(_bill, "drop", 1.0, 1.2, Tween.TRANS_BACK, Tween.EASE_OUT)

func _reveal(rows: int) -> void:
	_bill.revealed = mini(rows, _bill.rows.size())

## The knight salutes and the lent flames fly home: every paper crown relights
## and the folds climb a D-major pentatonic.
func _homecoming(stagger: float) -> void:
	_knight.gesture_to("salute", 12.0)
	var n := _fallen.size()
	for i in range(n):
		_after(stagger * float(i) / float(n), _return_flame.bind(i))
	_after(stagger + 0.6, _settle_crown)

func _return_flame(i: int) -> void:
	var f: Cast.FinaleFallen = _fallen[i]
	var still := Feedback.motion_reduced
	if still:
		_crowns.set_lit(i, 1.0, 0.5)
	_streams.launch(_knight.head_point, f.crown_point, 0.5 if still else 0.6, _relit.bind(i))

func _relit(i: int) -> void:
	_crowns.set_lit(i, 1.0)
	_sound("fold", Content.FOLD_MAJOR[i % Content.FOLD_MAJOR.size()], -8.0, false)

func _settle_crown() -> void:
	_knight.crown = 1.0
	_knight.gesture_to("", 0.0)

## The fallen bow in a wave from the wings inward, a pair at a time.
func _fallen_bow() -> void:
	var outer := 0.0
	for f in _fallen:
		outer = maxf(outer, absf(f.position.x - Cast.THRONE_X))
	for f in _fallen:
		var wave := (outer - absf(f.position.x - Cast.THRONE_X)) / 23.0 * 0.08
		_after(wave, f.bow.bind("bow", 1.1))

## The Warden, for now: lowered from the flies as a mended paper puppet, one
## stiff bow, hauled back up. Under the Fivefold Oath its wires snap instead.
func _warden_act(speed: float) -> void:
	var s := 1.0 / speed
	_warden = Cast.FinaleWarden.new()
	_warden.position = Vector2(Cast.THRONE_X - 110.0 * _side, -400.0)
	_warden.facing = _side
	_actors.add_child(_warden)
	if Feedback.motion_reduced:
		_warden.position.y = WARDEN_Y
		_warden.modulate.a = 0.0
		_ramp(_warden, "modulate:a", 1.0, 0.4 * s)
	else:
		_ramp(_warden, "position:y", WARDEN_Y, 1.1 * s, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
		_warden.swing = 0.05
	_after(1.3 * s, _ramp.bind(_warden, "bow", 1.0, 0.4 * s))
	_after(2.1 * s, _ramp.bind(_warden, "bow", 0.0, 0.3 * s))
	if (ctx.get("vows", []) as Array).size() == Content.VOWS.size():
		_after(2.5 * s, _snap_wires)
	elif Feedback.motion_reduced:
		_after(2.5 * s, _ramp.bind(_warden, "modulate:a", 0.0, 0.4 * s))
	else:
		_after(2.5 * s, _ramp.bind(_warden, "position:y", -500.0, 1.1 * s, Tween.TRANS_QUAD, Tween.EASE_IN))

## The Fivefold Oath: the wires snap and the Warden drops and folds flat onto
## the boards like dropped cardboard, and stays there.
func _snap_wires() -> void:
	_warden.wires = false
	game.feedback.play("shatter", 1.4)
	_after(0.1, game.feedback.play.bind("shatter", 1.4))
	_ramp(_warden, "position:y", Cast.stage_floor(_warden.position.x), 0.25, Tween.TRANS_QUAD, Tween.EASE_IN)
	_after(0.25, _fold_warden)

func _fold_warden() -> void:
	_ramp(_warden, "scale:y", 0.08, 0.35, Tween.TRANS_QUAD, Tween.EASE_IN)
	game.feedback.play("slam", 0.8)
	_ash.puff(_warden.position, 24)

## The knight's bow, the last and longest: a follow-spot finds it, it steps to
## centre and the fallen turn their crowns toward it (the shorter cuts bow
## together). A socket lights per vow sworn; from the tenth victory the house
## stands.
func _knight_bow(ensemble: bool) -> void:
	_reveal(_bill.rows.size())
	_front.spot_x = Cast.THRONE_X
	_ramp(_front, "spot", 1.0, 0.6)
	if not Feedback.motion_reduced:
		_move_camera(BOW_FRAME, 1.4)
	_knight.gesture_to("", 0.0)
	_knight.walk(Cast.THRONE_X, 88.0, _knight.facing, _bow_down)
	_crowns.lean_x = Cast.THRONE_X
	_ramp(_crowns, "lean", 1.0, 0.8)
	for f in _fallen:
		f.bow("bow" if ensemble else "nod", 2.6)
	var vows: Array = ctx.get("vows", [])
	var lit := 0
	for v in range(Content.VOWS.size()):
		if vows.has(Content.VOWS[v].id):
			_after(0.6 + 0.15 * float(lit), _light_socket.bind(v))
			lit += 1
	if int(ctx.get("victories", 1)) >= 10:
		_after(0.6, _ramp.bind(_front, "rise", 1.0, 0.5))

func _bow_down() -> void:
	_knight.gesture_to("knight_bow", 6.0)
	_knight.crown = 2.0
	_after(1.7, _bow_up)

func _bow_up() -> void:
	_knight.gesture_to("", 6.0)
	_knight.crown = 1.0

func _light_socket(v: int) -> void:
	_front.vow_lit[v] = true
	game.feedback.play("elite", 1.2, -6.0)

## The great curtain falls over all of them and the footlights gutter out from
## the edges inward until the theatre is black.
func _curtain(lamp_step: float) -> void:
	phase = Phase.CURTAIN
	_move_camera(THEATRE, 1.2)
	_ramp(_front, "spot", 0.0, 0.8)
	_ramp(_bill, "drop", 0.0, 0.8, Tween.TRANS_QUAD, Tween.EASE_IN)
	_ramp(_front, "main_drop", 1.0, 1.6, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
	game.feedback.play("curtain", 0.8)
	for k in range(9):
		_after(1.0 + lamp_step * float(k), _set_lamp.bind(k, 0.0, "snuff"))
		_after(1.0 + lamp_step * float(k), _set_lamp.bind(17 - k, 0.0, "snuff"))
	_vignette_live = true
	_ramp(self, "vignette", CURTAIN_DARK, 2.0)

## The flame does not fall: the knight's own crown flame slips out from under
## the hem, in front of the curtain, and rises into the dark on the resolving D.
func _rise_ember() -> void:
	phase = Phase.EMBER
	_hoard.reparent(_front_layer, false)
	_hoard.halo_alpha = 0.5
	if Feedback.motion_reduced:
		_hoard.ember_pos = EMBER_TOP
		_ramp(_hoard, "ember_alpha", 1.0, 1.4)
	else:
		_hoard.ember_alpha = 1.0
		_ramp(_hoard, "ember_pos", EMBER_TOP, 1.4, Tween.TRANS_SINE, Tween.EASE_OUT)

## B32: the last epitaph the player died to, quoted, and the ending's answer.
func _answer() -> void:
	if not _b2_playing:
		game.feedback.play("grave_bell", 1.0, 0.0, false)
	_final_card(0.6)

func _final_card(fade: float) -> void:
	var words := Content.finale_answer(str(ctx.get("last_epitaph", "")), int(ctx.get("falls_since", 0)), bool(ctx.get("unknown", false)))
	for line in [[words.quote, 18, UI.C_MUTED, 450.0], [words.answer, 30, UI.C_TEXT, 488.0]]:
		if str(line[0]).is_empty():
			continue
		var label := _label(line[0], line[1], line[2], line[3])
		label.modulate.a = 0.0 if fade > 0.0 else 1.0
		_ramp(label, "modulate:a", 1.0, fade)

## The flame blooms and the results open out of it.
func _bloom() -> void:
	_ramp(_hoard, "halo_radius", 900.0, 0.8)
	_ramp(_hoard, "halo_alpha", 0.0, 0.8)
	_ramp(_hoard, "ember_alpha", 0.0, 0.8)
	for label in _cards.get_children():
		_ramp(label, "modulate:a", 0.0, 0.8)

func _finish(skipped: bool) -> void:
	phase = Phase.DONE
	_skip.visible = false
	finished.emit(skipped)

# --- Skip and abort ---------------------------------------------------------

## Holding pause skips. A first viewing advertises nothing and asks for 2 s
## (the ring shows after 0.5 s); repeat viewings caption the ring from the
## take-over and need 1 s. Letting go drains it three times as fast.
func _poll_skip(dt: float) -> void:
	if _skipping or phase > Phase.EMBER:
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

## A dip to black, the final state built at once (the set gone, the curtain
## down, the lamps out), then the final card, which survives a skip, and the
## results panel.
func skip_to_end() -> void:
	if _skipping or phase == Phase.DONE:
		return
	_skipping = true
	game._cancel_beat()
	_events.clear()
	_ramps.clear()
	_prompt.visible = false
	_skip.visible = false
	_ramp(_dip, "color:a", 1.0, 0.3)
	_after(0.3, _final_state)
	_after(0.3, _ramp.bind(_dip, "color:a", 0.0, 0.3))
	_after(1.6, _finish.bind(true))

func _final_state() -> void:
	phase = Phase.EMBER
	var player := game.player
	if is_instance_valid(player):
		player.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
	_free_cast()
	for card in _cards.get_children():
		card.queue_free()
	var box := game._world_container
	box.material = null
	box.visible = false
	box.position = Vector2.ZERO
	_burning = false
	_ambient_live = false
	_stage_layer.visible = true
	_stage.closed = 1.0
	_stage.remnant_heat = 0.0
	_front_layer.visible = true
	_front.modulate.a = 1.0
	_front.main_drop = 1.0
	_front.spot = 0.0
	_front.lamps.fill(0.0)
	_bill.drop = 0.0
	_frame_now(THEATRE)
	_vignette_live = true
	vignette = CURTAIN_DARK
	_stop_cues(0.3)
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
	box.position = Vector2.ZERO
	box.visible = true
	var player := game.player
	if is_instance_valid(player):
		player.visible = true
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.cinematic = false
	game._reset_camera()
	game.feedback.shake_time = 0.0
	game.feedback.camera.offset = Vector2.ZERO
	game.sconce_heat = 1.0
	game._set_vignette(Game.VIGNETTE_EDGE)
	game._lights.set_ambient(game.mood.ambient)
	if is_instance_valid(game.room):
		game.room.set("sigil_heat", 1.0)
		game.room.set("fire_heat", 1.0)
		game.room.set("sigil_gold", 0.0)
	_stop_cues(0.0)

## Frees the cast wherever it stands, the world or the actor layer.
func _free_cast() -> void:
	for node in _cast():
		node.get_parent().remove_child(node)
		node.queue_free()
	_hoard = null
	_knight = null
	_crowns = null
	_streams = null
	_warden = null
	_ash = null
	_fallen.clear()

# --- The director's machinery -------------------------------------------------

## Every live cast member the director advances.
func _cast() -> Array:
	var out: Array = [_hoard, _knight, _crowns, _streams, _warden, _ash]
	out.append_array(_fallen)
	return out.filter(func(node): return is_instance_valid(node))

## Cast joins the world after the room, at its gameplay z.
func _add_to_world(node: Node2D, z: int) -> void:
	node.z_index = z
	game.world.add_child(node)

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
	for layer in [_stage_layer, _actor_layer, _front_layer]:
		layer.transform = view
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

## An act card at the top of the frame: 0.4 s in, held, 0.4 s out.
func _card(key: String, hold: float = 2.5) -> void:
	var label := _label(Content.FINALE_TEXT[key], 30, UI.C_TEXT, 96.0)
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

## Plays a cue at most 12 times a second, so a row of lamps or a crowd of
## crowns reads as a flurry rather than a wall of sound.
func _sound(cue: String, pitch: float = 1.0, volume_db: float = 0.0, humanize: bool = true) -> void:
	if clock - float(_sounded.get(cue, -1.0)) < 1.0 / 12.0:
		return
	_sounded[cue] = clock
	game.feedback.play(cue, pitch, volume_db, humanize)

## The curtain cues come with the score's cue book. Until one is rendered, or
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

## Stage (-1, behind the world), actors (10), proscenium and bill (11) and
## text (45: above the vignette at 40, under the UI at 50).
func _build_layers() -> void:
	_stage_layer = _layer("StageLayer", -1)
	_stage = FinaleStage.new()
	_stage_layer.add_child(_stage)
	_stage_layer.visible = false
	_actor_layer = _layer("ActorLayer", 10)
	_actors = Node2D.new()
	_actors.name = "Actors"
	_actor_layer.add_child(_actors)
	_front_layer = _layer("FrontLayer", 11)
	_front = FinaleStage.FinaleFront.new()
	_front.house_count = mini(int(ctx.get("victories", 1)) - 1, Content.HOUSE_CAP)
	_front_layer.add_child(_front)
	_bill = FinaleStage.Playbill.new()
	_bill.rows = _playbill_rows()
	_front_layer.add_child(_bill)
	_front_layer.visible = false
	var text := _full_rect(Control.new(), _layer("TextLayer", 45))
	text.add_child(FinaleStage.PlaybillText.new(_bill))
	_cards = _full_rect(Control.new(), text)
	_prompt = FinalePrompt.new()
	_prompt.visible = false
	text.add_child(_prompt)
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

## The cast list: the fallen, the Warden (not in the brief cut), the knight and
## the run's boons, the vows sworn, the watching house and the credit.
func _playbill_rows() -> Array:
	var text := Content.FINALE_TEXT
	var vows: Array = ctx.get("vows", [])
	var oath := vows.size() == Content.VOWS.size()
	var rows: Array = ["%s — %s" % [text.fallen, Content.fallen_gloss(int(ctx.get("falls_since", 0)), bool(ctx.get("unknown", false)))]]
	if tier != "brief":
		rows.append("%s — %s" % [text.warden, text.warden_gloss_oath if oath else text.warden_gloss])
	rows.append("%s — %s" % [text.knight, text.knight_gloss_oath if oath else text.knight_gloss])
	var boons: Array = ctx.get("boons", [])
	if not boons.is_empty():
		rows.append({ "sigils": boons.slice(0, 8) })
	var sworn := PackedStringArray()
	for v in Content.VOWS:
		if vows.has(v.id):
			sworn.append(str(v.title).trim_prefix("Vow of "))
	if not sworn.is_empty():
		rows.append("%s — %s" % [text.sworn, " · ".join(sworn)])
	var house := Content.house_gloss(int(ctx.get("victories", 1)) - 1)
	if not house.is_empty():
		rows.append("%s — %s" % [text.house, house])
	if not str(text.credit).is_empty():
		rows.append(text.credit)
	return rows


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
	var _cap := StyleBoxFlat.new()
	var _cap_gold := StyleBoxFlat.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var binding := UI._binding_text("ignite")
		_key = str(binding.key)
		if not Input.get_connected_joypads().is_empty() and not str(binding.pad).is_empty():
			_key += " / " + str(binding.pad)
		for box: StyleBoxFlat in [_cap, _cap_gold]:
			box.bg_color = Color(UI.C_INK, 0.9)
			box.set_border_width_all(1)
			box.set_corner_radius_all(4)
		_cap.border_color = UI.C_EDGE
		_cap_gold.border_color = UI.C_GOLD

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
			_word(font, x, left, word, UI.C_TEXT)
			x += left_w + gap
		draw_style_box(_cap_gold if let_go else _cap, Rect2(x, -14.0, cap_w, 28.0))
		draw_string(font, Vector2(x + 8.0, 6.0), _key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.C_TEXT)
		_word(font, x + cap_w + gap, right, word, UI.C_GOLD if let_go else UI.C_TEXT)

	func _word(font: Font, x: float, text: String, size: int, color: Color) -> void:
		draw_string_outline(font, Vector2(x, 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(VFX.VOID, 0.6))
		draw_string(font, Vector2(x, 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


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
