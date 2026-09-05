extends SceneTree
## Boss appearance contract. Real boss states; behavior tuning is not replaced.
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	Save.path = "user://boss_art_contract.json"
	var game: Game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.ui.start_requested.emit()
	game.run.room_index = game.run.rooms_total() - 2
	game._advance_room()
	await process_frame
	var boss := game.room.boss
	check(boss.has_method("visual_pose"), "redesigned boss has one connected pose used by its renderer")
	if boss.has_method("visual_pose"):
		var rest: Dictionary = boss.call("visual_pose")
		check((rest.offhand as Vector2).x <= -45.0 and float(rest.get("off_angle", 0.0)) > 1.6, "resting rear claws point outward, clear of the legs")
		var poses: Array = []
		for action in ["_begin_lunge", "_begin_fan", "_begin_slam", "_begin_charge"]:
			boss.call(action)
			var pose: Dictionary = boss.call("visual_pose")
			poses.append(pose)
			check((pose.hand as Vector2).distance_to(pose.elbow) <= 85.0, action + " claw connects to the forearm")
			check((pose.elbow as Vector2).distance_to(pose.shoulder) <= 85.0, action + " arm connects to its shoulder")
			check(absf(float(pose.lean)) <= 0.35, action + " preserves upright imposing silhouette")
		check(poses[0].get("archetype", "") == "cinder_creature", "new family is a creature, not a reskinned masked knight")
		check(poses[0].get("accent") == Content.PAL.player_accent, "boss shares the original player's ember accent")
		check((poses[2].hand as Vector2).y < (poses[0].hand as Vector2).y - 50.0, "lunge and overhead slam have distinct claw poses")
		check((poses[1].offhand as Vector2).y < (poses[0].offhand as Vector2).y - 10.0, "projectile fan raises the free casting hand")
		check(float(poses[3].lean) > float(poses[0].lean), "charge visibly commits the body forward")
		var art: Script = load("res://scripts/warden_art.gd")
		check(not art.BODY.has("mask") and not art.BODY.has("cuirass"), "rejected mask and plate-suit geometry are absent")
		for key in art.BODY:
			var points: PackedVector2Array = art.BODY[key]
			check(points.size() >= 3 and not Geometry2D.triangulate_polygon(points).is_empty(), "authored " + key + " polygon triangulates")
		check(boss.max_hp == Content.BOSS_HP and Content.BOSS_W == 84.0 and Content.BOSS_H == 118.0, "redesign preserves health and collision dimensions")
	game.queue_free()
	await process_frame
	print("BOSS_ART_RESULT: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
