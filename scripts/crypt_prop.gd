extends Area2D
## Breakable floor dressing: urns and candle stands in the crypt, coal and iron
## in the works, lanterns and bone in the ashpit. Cosmetic destruction, never loot.

const VFX := preload("res://scripts/vfx.gd")
signal shattered(pos: Vector2, force: Vector2, color: Color)
enum Kind { URN, STAND, SKULLS, SCUTTLE, CRUCIBLE, ANVIL, LANTERN, CAIRN, CHARRED_URN }
const BRONZE := Color("a78060")
const STONE := Color("887591")
const BONE := Color("bdb3a3")
const IRON := Color("4a4450")
const COAL := Color("3a2a22")
const CHAR := Color("3a3034")
## What each zone leaves on its floors; a chamber deals through its zone's set.
const ZONE_KINDS := {
	"crypt": [Kind.URN, Kind.STAND, Kind.SKULLS],
	"works": [Kind.SCUTTLE, Kind.CRUCIBLE, Kind.ANVIL],
	"ashpit": [Kind.LANTERN, Kind.CAIRN, Kind.CHARRED_URN],
}
## Per kind: hurtbox height, and the colour its shards fly in.
const SPEC := {
	Kind.URN: [38.0, STONE], Kind.STAND: [48.0, BRONZE], Kind.SKULLS: [32.0, BONE],
	Kind.SCUTTLE: [32.0, COAL], Kind.CRUCIBLE: [34.0, BRONZE], Kind.ANVIL: [30.0, IRON],
	Kind.LANTERN: [44.0, IRON], Kind.CAIRN: [32.0, BONE], Kind.CHARRED_URN: [38.0, CHAR],
}
var kind := Kind.URN
var broken := false
var _time := 0.0
var _shape: CollisionShape2D

func _ready() -> void:
	collision_layer = Content.L_ENEMY_HURT
	collision_mask = 0
	monitoring = false
	monitorable = true
	set_meta("team", "scenery")
	set_meta("owner", self)
	set_meta("owner_id", get_instance_id())
	add_to_group("breakable_prop")
	var height: float = SPEC[kind][0]
	_shape = Content.rect_shape(Vector2(30.0, height))
	_shape.position.y = -height * 0.5
	add_child(_shape)
	set_process(flame_height() > 0.0)

## Height of the prop's flame over its base, for the room's light list; 0 when it has none.
func flame_height() -> float:
	match kind:
		Kind.STAND: return 49.0
		Kind.LANTERN: return 20.0
	return 0.0

func take_damage(amount: float, direction: Vector2, force: float) -> void:
	if broken or amount <= 0.0:
		return
	broken = true
	set_deferred("monitorable", false)
	_shape.set_deferred("disabled", true)
	remove_from_group("breakable_prop")
	set_process(false)
	shattered.emit(global_position + Vector2(0.0, -24.0), direction * minf(force, 420.0), SPEC[kind][1])
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
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, 0.0), Vector2(x, -h), Vector2(x + 6.0, -1.0)]), (SPEC[kind][1] as Color).darkened(0.28))
		return
	match kind:
		Kind.STAND:
			draw_line(Vector2(0.0, -4.0), Vector2(0.0, -41.0), BRONZE.darkened(0.3), 5.0, true)
			draw_line(Vector2(1.0, -6.0), Vector2(1.0, -39.0), BRONZE, 1.5, true)
			var arms := PackedVector2Array([Vector2(-14.0, -38.0), Vector2(-12.0, -29.0), Vector2(0.0, -24.0), Vector2(12.0, -29.0), Vector2(14.0, -38.0)])
			draw_polyline(arms, BRONZE, 3.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(-12.0, 0.0), Vector2(-6.0, -5.0), Vector2(6.0, -5.0), Vector2(12.0, 0.0)]), BRONZE.darkened(0.2))
			for x in [-14.0, 0.0, 14.0]:
				var y := -44.0 if x == 0.0 else -39.0
				draw_line(Vector2(x, y), Vector2(x, y - 8.0), Color("c3b79a"), 4.0, true)
				VFX.draw_flame(self, Vector2(x, y - 7.0), 10.0, 4.0, _time, x, Color("ff9b51"), VFX.GOLD)
		Kind.URN, Kind.CHARRED_URN:
			_draw_urn(STONE if kind == Kind.URN else CHAR)
		Kind.SKULLS:
			for c: Vector2 in [Vector2(-8.0, -8.0), Vector2(8.0, -8.0), Vector2(0.0, -21.0)]:
				draw_circle(c, 7.5, BONE.darkened(0.12))
				draw_rect(Rect2(c.x - 4.0, c.y + 4.0, 8.0, 4.0), BONE.darkened(0.3))
				draw_circle(c + Vector2(-2.6, -0.5), 1.8, VFX.VOID)
				draw_circle(c + Vector2(2.6, -0.5), 1.8, VFX.VOID)
		Kind.SCUTTLE:
			draw_arc(Vector2(0.0, -22.0), 12.0, PI, TAU, 10, IRON.lightened(0.2), 2.0, true)
			VFX.draw_shaded_polygon(self, PackedVector2Array([Vector2(-13.0, 0.0), Vector2(-15.0, -20.0), Vector2(13.0, -24.0), Vector2(14.0, 0.0)]), IRON)
			draw_colored_polygon(PackedVector2Array([Vector2(-15.0, -20.0), Vector2(-8.0, -28.0), Vector2(0.0, -25.0), Vector2(6.0, -31.0), Vector2(13.0, -24.0)]), COAL)
			for p: Vector2 in [Vector2(-5.0, -25.0), Vector2(6.0, -27.0)]:
				draw_circle(p, 1.6, Color(VFX.ORANGE, 0.85))
		Kind.CRUCIBLE:
			for leg: float in [-1.0, 0.0, 1.0]:
				draw_line(Vector2(leg * 9.0, -18.0), Vector2(leg * 14.0, 0.0), IRON, 3.0, true)
			VFX.draw_shaded_polygon(self, PackedVector2Array([Vector2(-15.0, -32.0), Vector2(15.0, -32.0), Vector2(10.0, -16.0), Vector2(-10.0, -16.0)]), BRONZE.darkened(0.3))
			VFX.draw_ellipse(self, Vector2(0.0, -32.0), 13.0, 3.0, VFX.ORANGE)
			VFX.draw_ellipse(self, Vector2(0.0, -32.0), 7.0, 1.6, VFX.GOLD)
		Kind.ANVIL:
			VFX.draw_shaded_polygon(self, PackedVector2Array([
				Vector2(-21.0, -27.0), Vector2(-12.0, -29.0), Vector2(14.0, -29.0), Vector2(14.0, -22.0), Vector2(6.0, -20.0), Vector2(5.0, -11.0),
				Vector2(12.0, -7.0), Vector2(12.0, 0.0), Vector2(-12.0, 0.0), Vector2(-12.0, -7.0), Vector2(-5.0, -11.0), Vector2(-6.0, -20.0), Vector2(-12.0, -23.0),
			]), IRON)
			draw_line(Vector2(-12.0, -28.0), Vector2(13.0, -28.0), IRON.lightened(0.4), 1.5, true)
		Kind.LANTERN:
			VFX.draw_flame(self, Vector2(0.0, -8.0), 16.0, 7.0, _time, 0.0, Color("ff9b51"), VFX.GOLD)
			draw_rect(Rect2(-10.0, -5.0, 20.0, 5.0), IRON)
			for x in [-8.0, -3.0, 3.0, 8.0]:
				draw_line(Vector2(x, -5.0), Vector2(x, -34.0), IRON, 2.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(-11.0, -34.0), Vector2(11.0, -34.0), Vector2(0.0, -41.0)]), IRON)
			draw_arc(Vector2(0.0, -44.0), 3.0, 0.0, TAU, 8, IRON, 1.5)
		Kind.CAIRN:
			draw_line(Vector2(-10.0, -10.0), Vector2(-19.0, -23.0), BONE, 3.0, true)
			draw_line(Vector2(8.0, -16.0), Vector2(15.0, -28.0), BONE.darkened(0.1), 3.0, true)
			VFX.draw_ellipse(self, Vector2(0.0, -5.0), 14.0, 5.0, CHAR.lightened(0.1))
			VFX.draw_ellipse(self, Vector2(-2.0, -13.0), 11.0, 4.5, CHAR.lightened(0.18))
			VFX.draw_ellipse(self, Vector2(1.0, -20.0), 8.0, 4.0, CHAR.lightened(0.12))
			draw_circle(Vector2(1.0, -27.0), 5.0, BONE.darkened(0.12))
			draw_circle(Vector2(-0.8, -27.5), 1.3, VFX.VOID)
			draw_circle(Vector2(2.8, -27.5), 1.3, VFX.VOID)

## A funerary urn in `stone`; a charred one carries glowing cracks.
func _draw_urn(stone: Color) -> void:
	var body := PackedVector2Array([
		Vector2(-7.0, -35.0), Vector2(7.0, -35.0), Vector2(8.0, -28.0),
		Vector2(15.0, -24.0), Vector2(14.0, -12.0), Vector2(7.0, -5.0),
		Vector2(7.0, -2.0), Vector2(-7.0, -2.0), Vector2(-7.0, -5.0),
		Vector2(-14.0, -12.0), Vector2(-15.0, -24.0), Vector2(-8.0, -28.0),
	])
	VFX.draw_shaded_polygon(self, body, stone, true)
	draw_polyline(PackedVector2Array([Vector2(-7.0, -33.0), Vector2(-8.0, -28.0), Vector2(-13.0, -23.0), Vector2(-12.0, -14.0)]), stone.lightened(0.25), 1.4, true)
	VFX.draw_ellipse(self, Vector2(0.0, -36.0), 9.0, 3.0, BRONZE)
	VFX.draw_ellipse(self, Vector2(0.0, -37.0), 5.0, 1.8, stone.darkened(0.5))
	if stone == CHAR:
		draw_polyline(PackedVector2Array([Vector2(-10.0, -22.0), Vector2(-4.0, -17.0), Vector2(-6.0, -10.0)]), Color(VFX.ORANGE, 0.8), 1.5, true)
		draw_polyline(PackedVector2Array([Vector2(9.0, -24.0), Vector2(5.0, -18.0), Vector2(8.0, -12.0)]), Color(VFX.EMBER, 0.7), 1.2, true)
		return
	draw_line(Vector2(-11.0, -25.0), Vector2(11.0, -25.0), BRONZE, 2.0, true)
	draw_line(Vector2(0.0, -22.0), Vector2(0.0, -11.0), BRONZE, 1.8, true)
	draw_line(Vector2(-4.0, -18.0), Vector2(4.0, -18.0), BRONZE, 1.8, true)
	draw_line(Vector2(-9.0, -2.0), Vector2(9.0, -2.0), BRONZE.darkened(0.15), 3.0, true)
