extends Node2D
## Parallax crypt painter. Lives inside the world viewport; the geometry itself
## is owned by Game.

var game: Game

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if game != null:
		game._paint_backdrop(self)
