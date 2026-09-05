extends Area2D
## Original vector urns and candle stands. Cosmetic destruction, never loot.

const VFX := preload("res://scripts/vfx.gd")
signal shattered(pos: Vector2, force: Vector2, color: Color)
var kind := 0 # 0: funerary urn, 1: three-armed candle stand
var broken := false
var _time := 0.0
var _shape: CollisionShape2D
const BRONZE := Color("a78060")
const STONE := Color("887591")

func _ready() -> void:
	collision_layer = Content.L_ENEMY_HURT
	collision_mask = 0
	monitoring = false
	monitorable = true
	set_meta("team", "scenery")
	set_meta("owner", self)
	set_meta("owner_id", get_instance_id())
	add_to_group("breakable_prop")
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30.0, 48.0 if kind == 1 else 38.0)
	_shape.shape = rect
	_shape.position.y = -rect.size.y * 0.5
	add_child(_shape)
	set_process(kind == 1)

func take_damage(amount: float, direction: Vector2, force: float) -> void:
	if broken or amount <= 0.0:
		return
	broken = true
	set_deferred("monitorable", false)
	_shape.set_deferred("disabled", true)
	remove_from_group("breakable_prop")
	set_process(false)
	shattered.emit(global_position + Vector2(0.0, -24.0), direction * minf(force, 420.0), BRONZE if kind == 1 else STONE)
	queue_redraw()

func _process(delta: float) -> void:
	if not Feedback.motion_reduced:
		_time += delta
	queue_redraw()

func _draw() -> void:
	VFX.draw_ellipse(self, Vector2(0.0, 1.0), 24.0, 4.0, Color(0.025, 0.018, 0.04, 0.6))
	if broken:
		for i in range(5):
			var x := -19.0 + float(i) * 9.0
			var h := 3.0 + float(i % 3) * 2.0
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, 0.0), Vector2(x, -h), Vector2(x + 6.0, -1.0)]), STONE.darkened(0.28))
		return
	if kind == 1:
		draw_line(Vector2(0.0, -4.0), Vector2(0.0, -41.0), BRONZE.darkened(0.3), 5.0, true)
		draw_line(Vector2(1.0, -6.0), Vector2(1.0, -39.0), BRONZE, 1.5, true)
		var arms := PackedVector2Array([Vector2(-14.0, -38.0), Vector2(-12.0, -29.0), Vector2(0.0, -24.0), Vector2(12.0, -29.0), Vector2(14.0, -38.0)])
		draw_polyline(arms, BRONZE, 3.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(-12.0, 0.0), Vector2(-6.0, -5.0), Vector2(6.0, -5.0), Vector2(12.0, 0.0)]), BRONZE.darkened(0.2))
		for x in [-14.0, 0.0, 14.0]:
			var y := -44.0 if x == 0.0 else -39.0
			draw_line(Vector2(x, y), Vector2(x, y - 8.0), Color("c3b79a"), 4.0, true)
			VFX.draw_flame(self, Vector2(x, y - 7.0), 10.0, 4.0, _time, x, Color("ff9b51"), VFX.GOLD)
	else:
		var body := PackedVector2Array([
			Vector2(-7.0, -35.0), Vector2(7.0, -35.0), Vector2(8.0, -28.0),
			Vector2(15.0, -24.0), Vector2(14.0, -12.0), Vector2(7.0, -5.0),
			Vector2(7.0, -2.0), Vector2(-7.0, -2.0), Vector2(-7.0, -5.0),
			Vector2(-14.0, -12.0), Vector2(-15.0, -24.0), Vector2(-8.0, -28.0),
		])
		VFX.draw_shaded_polygon(self, body, STONE, true)
		draw_polyline(PackedVector2Array([Vector2(-7.0, -33.0), Vector2(-8.0, -28.0), Vector2(-13.0, -23.0), Vector2(-12.0, -14.0)]), STONE.lightened(0.25), 1.4, true)
		VFX.draw_ellipse(self, Vector2(0.0, -36.0), 9.0, 3.0, BRONZE)
		VFX.draw_ellipse(self, Vector2(0.0, -37.0), 5.0, 1.8, STONE.darkened(0.5))
		draw_line(Vector2(-11.0, -25.0), Vector2(11.0, -25.0), BRONZE, 2.0, true)
		draw_line(Vector2(0.0, -22.0), Vector2(0.0, -11.0), BRONZE, 1.8, true)
		draw_line(Vector2(-4.0, -18.0), Vector2(4.0, -18.0), BRONZE, 1.8, true)
		draw_line(Vector2(-9.0, -2.0), Vector2(9.0, -2.0), BRONZE.darkened(0.15), 3.0, true)
