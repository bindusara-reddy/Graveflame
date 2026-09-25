class_name FinaleStage
extends Node2D
## PLACEHOLDER from the ending-director stream so the director and its contract
## run on their own. ENDING-THEATRE ships the real theatre under these exact
## names; at integration its file replaces this one wholesale.
##   FinaleStage   back wall and the traveler curtain (`closed`, `remnant_heat`)
##   FinaleFront   proscenium, main curtain, footlights, sockets, house
##   Playbill      the bill on its cords (`drop`, `rows`, `revealed`)
##   PlaybillText  the bill's type in screen space

const VFX := preload("res://scripts/vfx.gd")
const BURN_AWAY := """
shader_type canvas_item;
render_mode unshaded;
uniform float progress = 0.0;
uniform vec2 origin = vec2(0.5, 0.6);
uniform float aspect = 1.7778;
uniform float travel = 1.0;
uniform float rim_gain = 1.0;
void fragment() {
	vec4 world = texture(TEXTURE, UV);
	float d = distance(UV * vec2(aspect, 1.0), origin * vec2(aspect, 1.0)) / (aspect + 1.0);
	float front = progress * 1.3 - d;
	float charred = mix(smoothstep(0.0, 0.35, progress), step(0.0, front), travel);
	float burned = mix(smoothstep(0.45, 1.0, progress), step(0.25, front), travel);
	vec3 col = mix(world.rgb, vec3(0.06, 0.035, 0.05), charred);
	col = mix(col, vec3(1.0, 0.48, 0.12), exp(-abs(front) * 60.0) * travel * rim_gain);
	COLOR = vec4(col, world.a * (1.0 - burned));
}
"""

var closed := 0.0:
	set(value):
		closed = value
		queue_redraw()
var remnant_heat := 1.0


static func burn_away_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = BURN_AWAY
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("travel", 0.0 if Feedback.motion_reduced else 1.0)
	mat.set_shader_parameter("rim_gain", 0.7 if Feedback.flash_reduced else 1.0)
	return mat


func _draw() -> void:
	VFX.draw_vgradient(self, Rect2(-600.0, -700.0, 2480.0, 1300.0), Color("08050c"), Color("1a0f1c"))
	draw_rect(Rect2(-600.0, 600.0, 2480.0, 40.0), Color("24151d"))
	var inner := 620.0 * (1.0 - clampf(closed, 0.0, 1.0))
	draw_rect(Rect2(-600.0, -160.0, 1240.0 - inner, 760.0), Color("3a0b16"))
	draw_rect(Rect2(640.0 + inner, -160.0, 1240.0 - inner, 760.0), Color("3a0b16"))


class FinaleFront extends Node2D:
	var lamps: Array[float] = []
	var vow_lit: Array[bool] = []
	var main_drop := 0.0
	var spot := 0.0
	var spot_x := 640.0
	var house_count := 0
	var rise := 0.0

	func _init() -> void:
		lamps.resize(18)
		lamps.fill(0.0)
		vow_lit.resize(5)
		vow_lit.fill(false)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		for x: float in [-400.0, 1240.0]:
			draw_rect(Rect2(x, -700.0, 440.0, 1400.0), Color("1c1024"))
		draw_rect(Rect2(40.0, -200.0, 1200.0, 200.0), Color("1c1024"))
		draw_line(Vector2(40.0, 0.0), Vector2(1240.0, 0.0), Color("b8873a"), 7.0)
		for v in range(5):
			draw_circle(Vector2(640.0 + float(v - 2) * 78.0, -20.0), 7.0, Color("ffd166") if vow_lit[v] else Color("3a2a44"))
		draw_rect(Rect2(40.0, -150.0, 1200.0, 752.0 * main_drop), Color("8c2234"))
		for i in range(18):
			var base := Vector2(80.0 + 66.0 * float(i), 606.0)
			draw_rect(Rect2(base - Vector2(10.0, 2.0), Vector2(20.0, 8.0)), Color("8e8898"))
			if lamps[i] > 0.0:
				VFX.draw_flame(self, base, 14.0 * lamps[i], 7.0, 0.0, float(i), VFX.ORANGE, VFX.GOLD)
		for i in range(house_count):
			draw_circle(Vector2(640.0 + float(i - house_count / 2) * 52.0, 660.0 - 14.0 * rise), 14.0, Color("120c18"))


class Playbill extends Node2D:
	const SHEET := Vector2(640.0, 250.0)
	var drop := 0.0:
		set(value):
			drop = value
			queue_redraw()
	var title := Content.FINALE_TEXT.bill_title
	var subtitle := Content.FINALE_TEXT.bill_sub
	var rows: Array = []
	var revealed := 0

	func _init() -> void:
		position = Vector2(640.0, -420.0)

	func sheet_transform() -> Transform2D:
		return get_global_transform_with_canvas() * Transform2D(0.0, Vector2(-SHEET.x * 0.5, 450.0 * drop))

	func screen_rect() -> Rect2:
		var xf := sheet_transform()
		return Rect2(xf.origin, SHEET * xf.get_scale())

	func _draw() -> void:
		if drop > 0.0:
			draw_rect(Rect2(Vector2(-SHEET.x * 0.5, 450.0 * drop), SHEET), Color("e6d8bc"))


class PlaybillText extends Control:
	var bill: Playbill

	func _init(for_bill: Playbill = null) -> void:
		bill = for_bill
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		if bill != null and is_instance_valid(bill):
			var r := bill.screen_rect()
			position = r.position
			size = r.size
			queue_redraw()

	func _draw() -> void:
		if bill == null or bill.drop <= 0.0:
			return
		var font := UI._heading_font()
		var ink := Color("2a1410")
		draw_string(font, Vector2(0.0, 40.0), bill.title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, ink)
		draw_string(font, Vector2(0.0, 62.0), bill.subtitle, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, ink)
		for i in range(mini(bill.revealed, bill.rows.size())):
			var row = bill.rows[i]
			if row is String:
				draw_string(font, Vector2(0.0, 90.0 + 18.0 * float(i)), row, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, ink)
