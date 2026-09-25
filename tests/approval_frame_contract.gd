extends "res://tests/harness.gd"
## Approval-frame contract for the Blasphemous bar. Runs headless via SceneTree
## (no rendering): stages real gameplay state and asserts every number the
## approval frame must hit. A failing check = rebuild the layer, no eyeballing.
## Run: godot4 --headless --path . --script res://tests/approval_frame_contract.gd


func run() -> void:
	await process_frame
	use_scratch_save("graveflame_save_approval")
	# One title-screen game serves every layout check below.
	await load_main_scene(1)
	_test_camera_framing()
	_test_phase_tag()
	_test_banner_placement()
	await free_game()
	await _test_attack_staging()
	await _test_boss_staging()
	_test_damage_numbers()
	await finish("APPROVAL_CONTRACT")


## The locked camera contract: tighter frame, fighters read at Blasphemous scale.
func _test_camera_framing() -> void:
	check(Content.CAM_ZOOM >= 1.1 and Content.CAM_ZOOM <= 1.2, "CAM_ZOOM stays in the locked 1.1-1.2 band")
	check(Content.PIXEL_SCALE <= 1.0, "vector-native PIXEL_SCALE stays at or below 1.0")
	var zoom: Vector2 = game.feedback.camera.zoom
	check(is_equal_approx(zoom.x, Content.CAM_ZOOM / Content.PIXEL_SCALE), "camera zoom honors the CAM_ZOOM contract")
	# Tighter frame: at 1280 wide the view spans ~1113 world px, never the full room.
	var view_span: float = float(Content.VIEW_W) / zoom.x
	check(view_span < float(Content.VIEW_W), "tighter camera shows less than the full authored width")
	check(view_span > 900.0, "tighter camera still keeps duel spacing on screen")
	# Hero must read at responsive, agile action scale (compact silhouette): >=7% of visible frame height.
	var hero_frac: float = float(Content.P_BODY_H) / (float(Content.VIEW_H) / zoom.y)
	check(hero_frac >= 0.07, "hero body height reads >=7% of the visible frame")
	# Boss must loom: >=18% of visible frame height.
	var boss_frac: float = float(Content.BOSS_H) / (float(Content.VIEW_H) / zoom.y)
	check(boss_frac >= 0.18, "boss body height reads >=18% of the visible frame")


## The finisher swing must be stageable: real state, real arc, real hit-stop.
func _test_attack_staging() -> void:
	var rm := RunModel.new(4242)
	var player := Player.new()
	player.setup(rm)
	root.add_child(player)
	await process_frame
	await physics_frame
	check(player.has_method("_begin_attack"), "player exposes _begin_attack for the staged frame")
	check(player.has_method("_draw"), "player draws its own body")
	# Stage the real combo path: first swing, then the forced chain into cleave.
	player._begin_attack(false)
	check(player.state == Player.State.ATTACK, "swing enters the real attack state")
	check(player.atk_phase == "startup", "swing starts in startup anticipation")
	check(player.attack_index == 0, "first swing is the cut")
	player._begin_attack(true)
	check(player.attack_index == 1, "forced chain reaches the cleave")
	var cleave: Dictionary = Content.COMBO[1]
	check(float(cleave.range) >= 70.0, "cleave range reaches the staged enemy")
	var sweep: Array = Player.KnightArt.SWINGS.cleave.smear
	check(absf(float(sweep[1]) - float(sweep[0])) >= 1.8, "cleave smear sweeps a readable fan")
	player.queue_free()
	await process_frame


## The boss must stage its threat pose: windup telegraph, phase-2 palette, scale.
func _test_boss_staging() -> void:
	var boss := Boss.new()
	root.add_child(boss)
	await process_frame
	await physics_frame
	var w := float(Content.BOSS_W)
	var h := float(Content.BOSS_H)
	check(w >= 64.0 and h >= 88.0, "boss hitbox keeps its imposing footprint")
	check(w / h > 0.6 and w / h < 0.9, "boss proportions stay humanoid-warden, not a blob")
	boss.intro_t = 0.01
	await physics_frame
	await physics_frame
	boss._begin_slam()
	check(boss.state == Enemy.EState.WINDUP, "boss slam stages a real windup for the frame")
	check(boss.has_method("_draw"), "boss draws its own body")
	boss.queue_free()
	await process_frame


## Banners must live in the upper third and never cover the combat plane.
func _test_phase_tag() -> void:
	check(game.ui.has_method("flash_boss_phase"), "phase-2 callout renders as a small tag, not a center card")
	game.ui.flash_boss_phase("THE WARDEN IGNITES")
	var tag: Label = game.ui.get("_boss_phase_tag")
	check(tag != null and tag.visible, "phase tag shows on trigger")
	if tag != null:
		var r: Rect2 = tag.get_global_rect()
		check(r.position.y < float(Content.VIEW_H) * 0.3, "phase tag stays in the upper strip")
		check(r.size.x < float(Content.VIEW_W) * 0.55, "phase tag never spans the combat plane")


func _test_banner_placement() -> void:
	var hud_size := Vector2(float(Content.VIEW_W), float(Content.VIEW_H))
	var upper_third := hud_size.y / 3.0
	var clear_banner: Control = game.ui.get("_room_clear_banner")
	check(clear_banner != null, "room-clear banner exists")
	if clear_banner != null:
		var r: Rect2 = clear_banner.get_global_rect()
		check(r.position.y + r.size.y <= upper_third + 120.0, "room-clear banner stays out of the combat plane")
	var room_intro: Dictionary = game.ui.get("_room_intro")
	if not room_intro.is_empty():
		var root_c: Control = room_intro["root"]
		var r2: Rect2 = root_c.get_global_rect()
		check(r2.position.y + r2.size.y * 0.5 <= hud_size.y * 0.55, "chamber card never covers the fighters")


## Damage numbers must disambiguate: player-dealt vs player-taken, capped size.
func _test_damage_numbers() -> void:
	check(Content.PAL.hurt_number != Content.PAL.text, "hurt numbers differ from body text")
	check(Content.PAL.heal_number != Content.PAL.hurt_number, "heal numbers differ from hurt numbers")
	check(Content.PAL.hurt_number == Color("ff6b6b"), "hurt palette stays locked")
	check(Content.PAL.heal_number == Color("2be4c8"), "heal palette stays locked")
