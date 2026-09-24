extends Node2D
## Paper-cut death. The felled enemy's own drawing is split along the killing
## blow into two halves that come apart, each cut edge burning like singed paper.
## Each half is a mask (a half-plane that clips its children) holding a frozen,
## collision-free echo of the enemy, so the halves are exactly the creature's art.

const VFX := preload("res://scripts/vfx.gd")
const LIFE := 0.75

var _halves: Array = []
var _t := 0.0
var _tangent := Vector2.RIGHT

## Half-plane mask: draws a large polygon on the +normal side of the cut and
## clips its children to it.
class HalfMask extends Node2D:
	var normal := Vector2.UP
	func _ready() -> void:
		clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	func _draw() -> void:
		var r := 220.0
		var t := Vector2(-normal.y, normal.x)
		draw_colored_polygon(PackedVector2Array([t * r, t * r + normal * r, -t * r + normal * r, -t * r]), Color.WHITE)

## Singed edge along the cut, drawn inside each half so only its own side shows.
class CutEdge extends Node2D:
	var tangent := Vector2.RIGHT
	var heat := 1.0
	var reach := 20.0
	var color := Color("ff7a18")
	func _draw() -> void:
		if heat <= 0.0:
			return
		var a := tangent * reach
		draw_line(-a, a, Color(color, 0.85 * heat), 5.0 * heat + 1.0, true)
		draw_line(-a, a, Color(VFX.HOT, heat), 1.6, true)

## Split `enemy` where it stands. `hit_dir` is the direction the killing blow
## travelled; the cut runs along it with a little tilt, as a blade would.
static func spawn(parent: Node, enemy, hit_dir: Vector2, rng_seed: int) -> Node2D:
	var node := new()
	parent.add_child(node)
	node.global_position = enemy.global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var dir := hit_dir.normalized() if hit_dir.length_squared() > 0.01 else Vector2.RIGHT
	# A near-vertical blow (slam, burn) reads better as a slanted cleave.
	if absf(dir.x) < 0.3:
		dir = Vector2(signf(rng.randf() - 0.5), -0.6).normalized()
	var tilt := rng.randf_range(-0.45, 0.45)
	var tangent := dir.rotated(tilt)
	var normal := Vector2(-tangent.y, tangent.x)
	if normal.y > 0.0:
		normal = -normal  # +normal is the upper piece
	node._tangent = tangent
	var edge_col: Color = Content.ELITE_COLOR if bool(enemy.elite) else Color("ff7a18")
	for side: float in [1.0, -1.0]:
		var mask := HalfMask.new()
		mask.normal = normal * side
		node.add_child(mask)
		var echo = enemy.echo()
		mask.add_child(echo)
		var edge := CutEdge.new()
		edge.tangent = tangent
		edge.color = edge_col
		# Only as long as the body is wide, so the singe stays on the paper.
		edge.reach = float(enemy.data.w) * (0.42 if not bool(enemy.elite) else 0.52)
		mask.add_child(edge)
		# The upper piece is thrown along the blow; the lower one slumps and drops.
		var upper := side > 0.0
		var push := dir * (rng.randf_range(150.0, 230.0) if upper else rng.randf_range(20.0, 60.0))
		var vel := push + normal * side * rng.randf_range(40.0, 90.0) + Vector2(0.0, -rng.randf_range(160.0, 240.0) if upper else -40.0)
		var spin := rng.randf_range(2.5, 6.0) * signf(dir.x) * (1.0 if upper else -0.5)
		node._halves.append({ "mask": mask, "echo": echo, "edge": edge, "vel": vel, "spin": spin })
	return node

func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / LIFE, 0.0, 1.0)
	var moving := not Feedback.motion_reduced
	for h in _halves:
		var mask: Node2D = h.mask
		var vel: Vector2 = h.vel
		if moving:
			vel.y += 900.0 * delta
			vel.x *= 1.0 - 1.5 * delta
			h.vel = vel
			mask.position += vel * delta
			mask.rotation += float(h.spin) * delta
		var echo = h.echo
		if is_instance_valid(echo) and _t > 0.05 and echo._hurt_flash > 0.0:
			echo._hurt_flash = 0.0
			echo.queue_redraw()
		var edge: CutEdge = h.edge
		edge.heat = clampf(1.0 - _t / 0.3, 0.0, 1.0)
		edge.queue_redraw()
		# Paper does not fade: the pieces hold, then drop out of existence in the
		# last few frames, like a cut-out pulled off the stage.
		mask.modulate.a = 1.0 if k < 0.7 else clampf(1.0 - (k - 0.7) / 0.3, 0.0, 1.0)
	if _t >= LIFE:
		queue_free()
