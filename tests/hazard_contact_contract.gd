extends SceneTree
## Room-selection fixture only. Actual walking/dashing triggers the real hazard
## Area2D callback; engine diagnostics are gated separately from the result line.
var game: Game
var hurt := 0
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func ticks(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)

func run() -> void:
	Save.path="user://hazard_contract.json"
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await ticks(3)
	game.ui.start_requested.emit()
	var gap: Dictionary = Content.ROOM_TEMPLATES.filter(func(t):return t.tag=="gap")[0].duplicate(true)
	gap.slots=[]
	game.run.route[1]=gap
	game._advance_room()
	await ticks(85)
	game.player.hurt_taken.connect(func(_amount,_pos):hurt+=1)
	Input.action_press("move_right")
	for i in range(90):
		await ticks(1)
		if game.player.position.x>388.0: break
	check(game.player.is_on_floor(),"dash launch begins on the real causeway floor")
	Input.action_press("dash")
	await ticks(1)
	Input.action_release("dash")
	for i in range(90):
		await ticks(1)
		if hurt>0 or game.player.dead: break
	Input.action_release("move_right")
	check(hurt==1,"real pit contact delivers exactly one damage event")
	check(is_equal_approx(float(game.player.build.hp),82.0),"hazard damage is 18, not instant death")
	check(game.player._atk_shape.disabled,"hazard interruption leaves no active blade hitbox")
	paused=false
	game.queue_free()
	await process_frame
	print("HAZARD_CONTACT_RESULT: %s (%d checks, %d failures)" % ["PASS" if failures==0 else "FAIL",checks,failures])
	quit(0 if failures==0 else 1)
