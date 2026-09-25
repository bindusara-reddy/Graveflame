extends Node2D
## A world-viewport canvas Game repaints every frame through `paint`: the
## parallax backdrop behind the world and the foreground silhouettes before it.
## The geometry itself is owned by Game.

var paint: Callable

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if paint.is_valid():
		paint.call(self)
