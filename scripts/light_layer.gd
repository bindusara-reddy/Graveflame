extends Node2D
## Additive radial lights drawn between the backdrop and the world: player flame
## aura, boss furnace core, projectile glints and the wall torches on the arches.
## Platforms and actors draw above this node, so they remain clean silhouettes.

const VFX := preload("res://scripts/vfx.gd")

var game: Game
var _t := 0.0

func _ready() -> void:
	material = VFX.radial_material()
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	if game == null or game.state == Game.GState.TITLE:
		return
	var moving := not Feedback.motion_reduced
	var gain := 0.7 if Feedback.flash_reduced else 1.0
	var t := _t if moving else 0.0
	var idx := 0
	for p in game.torch_positions():
		var flicker := 1.0
		if moving:
			flicker += sin(t * 9.0 + float(idx) * 1.7) * 0.06 + sin(t * 23.0 + float(idx) * 0.9) * 0.03
		VFX.draw_radial(self, p, 96.0 * flicker, Color(VFX.GOLD, 0.28 * gain))
		idx += 1
	var player := game.player
	if is_instance_valid(player) and not player.dead:
		var flame := player._flame_time > 0.0
		var pos := player.global_position
		VFX.draw_radial(self, pos + Vector2(0.0, -10.0), 190.0 * (1.2 if flame else 1.0), Color(VFX.ORANGE, 0.18 * gain))
		VFX.draw_radial(self, pos + Vector2(0.0, -16.0), 52.0 * (1.35 if flame else 1.0), Color(VFX.GOLD, 0.45 * gain))
	var room := game.room
	if is_instance_valid(room) and room.boss != null and is_instance_valid(room.boss) and not room.boss.dead:
		var pulse := sin(t * 6.0) * 8.0 if moving else 0.0
		VFX.draw_radial(self, room.boss.global_position, 240.0 + pulse, Color(VFX.EMBER, 0.22 * gain))
	if is_instance_valid(game.projectiles):
		for p in game.projectiles.get_children():
			if p is Projectile:
				VFX.draw_radial(self, p.global_position, 46.0, Color(p.color, 0.3 * gain))
