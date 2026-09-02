extends Node2D
## Additive radial lights drawn between the backdrop and the world: player flame
## aura, boss furnace core, projectile glints, wall torches, room light points
## (braziers, candles), the open rift, and glows on wisps, elites and burning foes.
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
	var gain := (0.7 if Feedback.flash_reduced else 1.0) * 0.5
	var t := _t if moving else 0.0
	var mood: Dictionary = game.mood
	var torch: Color = mood.get("torch", VFX.GOLD)
	var idx := 0
	for p in game.torch_positions():
		var flicker := 1.0
		if moving:
			flicker += sin(t * 9.0 + float(idx) * 1.7) * 0.06 + sin(t * 23.0 + float(idx) * 0.9) * 0.03
		VFX.draw_radial(self, p, 110.0 * flicker, Color(torch, 0.3 * gain))
		VFX.draw_radial(self, p, 40.0 * flicker, Color(VFX.HOT, 0.12 * gain))
		idx += 1
	var player := game.player
	if is_instance_valid(player) and not player.dead:
		var flame := player._flame_time > 0.0
		var pos := player.global_position
		VFX.draw_radial(self, pos + Vector2(0.0, -10.0), 190.0 * (1.2 if flame else 1.0), Color(VFX.ORANGE, 0.18 * gain))
		VFX.draw_radial(self, pos + Vector2(0.0, -16.0), 52.0 * (1.35 if flame else 1.0), Color(VFX.GOLD, 0.45 * gain))
		# Ground pool under the knight's feet.
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
		VFX.draw_radial(self, Vector2(pos.x, (pos.y + 26.0) / 0.35), 90.0, Color(VFX.ORANGE, 0.14 * gain))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var room := game.room
	if is_instance_valid(room):
		for lp in room.light_points():
			var flick := 1.0
			if moving:
				flick += sin(t * float(lp.get("rate", 8.0)) + float(lp.get("phase", 0.0))) * 0.08
			VFX.draw_radial(self, lp.pos, float(lp.radius) * flick, Color(lp.color, float(lp.alpha) * gain))
		if room.exit_open:
			var pulse := 1.0 + (sin(t * 3.0) * 0.08 if moving else 0.0)
			VFX.draw_radial(self, room.exit_center(), 150.0 * pulse, Color(Content.PAL.exit, 0.32 * gain))
			VFX.draw_radial(self, room.exit_center(), 46.0, Color(VFX.HOT, 0.18 * gain))
		for e in room.enemies:
			if not is_instance_valid(e) or e.dead:
				continue
			var epos: Vector2 = e.global_position
			if e.kind == Enemy.Kind.WISP:
				VFX.draw_radial(self, epos, 74.0, Color(e.data.color, 0.38 * gain))
			if e.elite:
				VFX.draw_radial(self, epos, 120.0, Color(Content.ELITE_COLOR, 0.2 * gain))
			if e.burn_time > 0.0:
				VFX.draw_radial(self, epos + Vector2(0.0, -8.0), 84.0, Color(VFX.ORANGE, 0.32 * gain))
			if e.kind == Enemy.Kind.BOMBER and e._bomb_armed:
				var fuse := clampf(1.0 - e._fuse_t / maxf(0.01, e._fuse_total), 0.0, 1.0)
				VFX.draw_radial(self, epos, 60.0 + fuse * 60.0, Color(VFX.EMBER, (0.15 + fuse * 0.3) * gain))
		if room.boss != null and is_instance_valid(room.boss) and not room.boss.dead:
			var pulse := sin(t * 6.0) * 8.0 if moving else 0.0
			VFX.draw_radial(self, room.boss.global_position, 240.0 + pulse, Color(VFX.EMBER, 0.22 * gain))
	if is_instance_valid(game.projectiles):
		for p in game.projectiles.get_children():
			if p is Projectile:
				VFX.draw_radial(self, p.global_position, 46.0, Color(p.color, 0.3 * gain))
