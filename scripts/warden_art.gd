extends RefCounted
## Original creature family. Broad living silhouette, ember mantle and clawed
## arms; deliberately no mask, plate suit or separate weapon from the rejected art.
const VFX := preload("res://scripts/vfx.gd")
const INK := Color("201421")
const CHAR := Color("533039")
const RUST := Color("bb6250")
const RIDGE := Color("e6b17a")
const HORN := Color("f2d5a0")
const MANTLE := Color("873844")
static var BODY: Dictionary = _body_shapes()
## Open detail strokes, sampled once like BODY. They stay out of BODY because it
## holds filled polygons only (boss_art_contract triangulates every entry).
static var STROKES: Dictionary = _stroke_shapes()
## Named limb poses that blend() eases a pose toward.
const SEATED := {"hand":Vector2(66,-30),"elbow":Vector2(46,-20),"offhand":Vector2(-66,-30),"claw_angle":1.45,"off_angle":1.9,"lean":0.07}
const KNEEL := {"hand":Vector2(56,12),"elbow":Vector2(48,-12),"offhand":Vector2(-46,10),"claw_angle":1.3,"off_angle":1.9,"lean":0.18}
const ROAR := {"hand":Vector2(74,-62),"elbow":Vector2(52,-46),"offhand":Vector2(-72,-58),"claw_angle":-0.9,"off_angle":-2.2,"lean":-0.15}
const SLUMP := {"hand":Vector2(46,34),"elbow":Vector2(44,-2),"offhand":Vector2(-42,30),"claw_angle":1.3,"off_angle":1.2,"lean":0.16}
## How far a kneeling Warden sinks toward the floor.
const KNEEL_SAG := 16.0
## The Warden's fault lines: fire splits it along them as it dies. The last
## is the seam down its middle, the last to burn through: the finale opens the
## Warden along it like a paper costume.
const FAULTS := [
	[Vector2(-30,-44),Vector2(-12,-20),Vector2(-20,2),Vector2(-6,24)],
	[Vector2(18,-60),Vector2(6,-38),Vector2(22,-14),Vector2(12,10)],
	[Vector2(-40,-8),Vector2(-18,-6),Vector2(4,-16),Vector2(34,-4)],
	[Vector2(0,-86),Vector2(10,-70),Vector2(2,-58)],
	[Vector2(3,-90),Vector2(-2,-62),Vector2(3,-32),Vector2(-2,-2),Vector2(2,28),Vector2(0,56)],
]
## The crown's three flames: base, height and width. A spent crown keeps only
## charred stubs of them.
const CROWN := [[Vector2(-8,-75),30.0,12.0],[Vector2(8,-85),39.0,12.0],[Vector2(25,-78),26.0,10.0]]
const CHARRED := Color("5a2a2a")

static func curve(start: Vector2, segments: Array) -> PackedVector2Array:
	var points := PackedVector2Array([start])
	var from := start
	for seg in segments:
		for i in range(1, 7):
			points.append(from.bezier_interpolate(seg[0], seg[1], seg[2], float(i) / 6.0))
		from = seg[2]
	return points

static func _body_shapes() -> Dictionary:
	return {
		"body": curve(Vector2(-38,-37), [
			[Vector2(-45,-63),Vector2(-4,-71),Vector2(23,-51)],
			[Vector2(43,-39),Vector2(42,-5),Vector2(28,13)],
			[Vector2(12,36),Vector2(-19,32),Vector2(-35,15)],
			[Vector2(-44,1),Vector2(-45,-19),Vector2(-38,-37)],
		]),
		"head": curve(Vector2(-12,-56), [
			[Vector2(-20,-74),Vector2(-8,-90),Vector2(10,-89)],
			[Vector2(28,-90),Vector2(36,-76),Vector2(36,-65)],
			[Vector2(46,-61),Vector2(45,-53),Vector2(34,-49)],
			[Vector2(20,-39),Vector2(-1,-41),Vector2(-12,-56)],
		]),
		"face": curve(Vector2(1,-71), [
			[Vector2(8,-81),Vector2(28,-78),Vector2(32,-66)],
			[Vector2(34,-57),Vector2(23,-52),Vector2(16,-51)],
			[Vector2(6,-51),Vector2(-3,-61),Vector2(1,-71)],
		]),
		"mantle": curve(Vector2(-22,-54), [
			[Vector2(-50,-58),Vector2(-57,-27),Vector2(-57,0)],
			[Vector2(-58,19),Vector2(-66,34),Vector2(-78,43)],
			[Vector2(-61,42),Vector2(-56,47),Vector2(-49,37)],
			[Vector2(-50,43),Vector2(-45,44),Vector2(-40,39)],
			[Vector2(-31,28),Vector2(-25,29),Vector2(-22,35)],
			[Vector2(-9,25),Vector2(-10,21),Vector2(0,19)],
			[Vector2(10,-3),Vector2(1,-46),Vector2(-22,-54)],
		]),
		"shade": curve(Vector2(-33,-42), [
			[Vector2(-42,-21),Vector2(-35,5),Vector2(-15,18)],
			[Vector2(-2,28),Vector2(13,22),Vector2(22,17)],
			[Vector2(9,5),Vector2(-4,-22),Vector2(-5,-53)],
			[Vector2(-20,-58),Vector2(-30,-52),Vector2(-33,-42)],
		]),
	}

static func _stroke_shapes() -> Dictionary:
	return {
		"mantle_fold": curve(Vector2(-29,-39), [[Vector2(-43,-20),Vector2(-33,12),Vector2(-55,38)]]),
		"shoulder_ridge": curve(Vector2(-31,-41), [[Vector2(-17,-50),Vector2(4,-40),Vector2(12,-26)]]),
		"fissure": PackedVector2Array([Vector2(12,-28),Vector2(3,-12),Vector2(13,-3),Vector2(5,11)]),
		"jaw": curve(Vector2(9,-51), [[Vector2(18,-43),Vector2(36,-44),Vector2(42,-55)]]),
	}

static func pose(b) -> Dictionary:
	var windup: bool = b.state == Enemy.EState.WINDUP
	var active: bool = b.state == Enemy.EState.ATTACK
	var recover: bool = b.state == Enemy.EState.RECOVER or b.state == Enemy.EState.STAGGER
	var progress := clampf(1.0 - float(b.st_timer) / maxf(float(b.data.get("windup", 0.5)), 0.01), 0.0, 1.0) if windup else 0.0
	var shoulder := Vector2(29,-33)
	var elbow := Vector2(47,-12)
	var hand := Vector2(53,17)
	var offhand := Vector2(-49,-2)
	var claw_angle := 0.80
	var off_angle := 2.3
	var lean := clampf(absf(b.velocity.x) / 2800.0, 0.0, 0.12)
	if windup or active:
		match int(b.action_idx):
			Boss.Action.LUNGE:
				hand = Vector2(38,-5).lerp(Vector2(16,-23),progress) if windup else Vector2(92,-14)
				elbow = Vector2(53,-16) if windup else Vector2(61,-26)
				claw_angle = -0.60 if windup else -0.05
				lean = -0.07 if windup else 0.20
			Boss.Action.FAN:
				offhand = Vector2(-52,-48).lerp(Vector2(-59,-67),progress)
				off_angle = -1.25
				hand = Vector2(45,13)
				lean = -0.035
			Boss.Action.SLAM:
				hand = Vector2(24,-95) if windup else Vector2(65,28)
				elbow = Vector2(52,-65) if windup else Vector2(48,-5)
				offhand = Vector2(-20,-90) if windup else Vector2(-29,31)
				claw_angle = -1.35 if windup else 0.80
				off_angle = -1.8 if windup else 0.9
				lean = -0.09 if windup else 0.20
			Boss.Action.CHARGE:
				hand = Vector2(64,8)
				elbow = Vector2(42,-14)
				offhand = Vector2(-14,31)
				claw_angle = 0.08
				lean = 0.25 + progress * 0.04 if windup else 0.30
	if recover:
		lean = 0.08
	var p := {"archetype":"cinder_creature", "accent":Content.PAL.player_accent,
		"shoulder":shoulder,"elbow":elbow,"hand":hand,"offhand":offhand,
		"claw_angle":claw_angle,"off_angle":off_angle,"lean":lean,
		"windup":windup,"active":active,"progress":progress,"phase2":b.phase >= 2}
	if b.state == Enemy.EState.RECOVER and int(b.action_idx) in [Boss.Action.SLAM, Boss.Action.CHARGE]:
		# Spent after a heavy move: slumped, crown low, panting. The knight's cue.
		blend(p,SLUMP,1.0)
		p.sag = 5.0
		p.crown = 0.75
		p.pant = true
	return p

## Ease the limbs and lean of pose `p` toward a named pose (SEATED, KNEEL...) by k.
static func blend(p: Dictionary, target: Dictionary, k: float) -> void:
	for key in target:
		p[key] = lerp(p[key],target[key],k)

## Blend pose `p` toward sitting on the Ember Throne by k (1 = seated): claws
## draped over the armrests, haunches forward, head low.
static func seat(p: Dictionary, k: float) -> void:
	blend(p,SEATED,k)
	p.sit = k

## Blend pose `p` down onto one knee by k: head bowed, claws planted on the
## floor, the whole body sunk KNEEL_SAG px.
static func kneel(p: Dictionary, k: float) -> void:
	blend(p,KNEEL,k)
	p.kneel = k
	p.sag = KNEEL_SAG*k

static func shape(ci: CanvasItem, points: PackedVector2Array, color: Color, edge: Color = RIDGE) -> void:
	ci.draw_colored_polygon(points,color)
	var border := points.duplicate()
	border.append(points[0])
	ci.draw_polyline(border,INK,1.8,true)
	# Keep a single restrained lit edge, matching the game's shaded vector actors.
	ci.draw_polyline(PackedVector2Array([points[0],points[1],points[2],points[3]]),edge,1.4,true)

static func arm(ci: CanvasItem, shoulder: Vector2, elbow: Vector2, hand: Vector2, angle: float, color: Color) -> void:
	ci.draw_line(shoulder,elbow,INK,26.0,true)
	ci.draw_line(shoulder,elbow,color.darkened(0.16),24.0,true)
	ci.draw_circle(elbow,12.7,INK)
	ci.draw_circle(elbow,11.5,color)
	var axis := (hand-elbow).normalized()
	var normal := Vector2(-axis.y,axis.x)
	var forearm := curve(elbow-normal*10.0,[
		[elbow-axis*5.0,elbow+normal*11.0,hand-axis*4.0+normal*16.0],
		[hand+axis*20.0+normal*16.0,hand+axis*22.0-normal*12.0,hand-axis*5.0-normal*15.0],
		[elbow-axis*4.0-normal*14.0,elbow-normal*10.0,elbow-normal*10.0],
	])
	shape(ci,forearm,color)
	ci.draw_line(elbow-normal*6.0,hand-normal*9.0,RIDGE.darkened(0.20),3.0,true)
	for i in range(2):
		var y := -7.0+float(i)*13.0
		var claw := PackedVector2Array([
			Vector2(5,y-3),Vector2(17,y-4),Vector2(29,y+1),
			Vector2(34,y+9),Vector2(23,y+4),Vector2(9,y+4),
		])
		for j in range(claw.size()): claw[j] = hand + claw[j].rotated(angle)
		ci.draw_colored_polygon(claw,HORN.darkened(0.12))
		ci.draw_polyline(PackedVector2Array([claw[0],claw[1],claw[2],claw[3]]),HORN,1.2,true)

static func paint(b,p: Dictionary) -> void:
	var ci: CanvasItem = b
	var t: float = 0.0 if Feedback.motion_reduced else b._anim_t
	var face: float = b.facing
	var phase2: bool = p.phase2
	var flash := 0.42 if b._hurt_flash > 0.0 and not Feedback.flash_reduced else 0.0
	var rust := RUST.lerp(HORN,flash)
	var fire: Color = Content.PAL.player_accent
	if Feedback.flash_reduced: fire = fire.darkened(0.22)
	fire = fire.lerp(VFX.HOT,float(p.get("heat",0.0)))
	var walk := clampf(absf(b.velocity.x)/Content.BOSS_SPEED,0.0,1.0)
	var stride := sin(t*8.0)*5.0*walk if b.is_on_floor() else 2.0
	var breathe := sin(t*2.2)*1.2
	VFX.draw_contact_shadow(ci,Vector2(0,60),88.0,14.0,clampf(b._air_time/0.3,0.0,1.0))
	if p.has("marker"):
		# Where the leap-slam will land: a scorch that burns brighter as it falls.
		var mk: float = p.marker_k
		var rx := lerpf(40.0,70.0,mk)
		VFX.draw_ellipse(ci,p.marker,rx,rx*0.16,Color(fire,0.2+0.4*mk))
		VFX.draw_ellipse_ring(ci,p.marker,rx,rx*0.16,Color(INK,0.7),2.0)
	var jitter: Vector2 = p.get("jitter", Vector2.ZERO)
	var sag: float = p.get("sag",0.0)
	ci.draw_set_transform(Vector2(jitter.x,breathe+jitter.y+sag),float(p.lean)*face,Vector2(face,1))
	# A broad flowing back mass, not separate armour ornaments.
	var mantle: PackedVector2Array = BODY.mantle.duplicate()
	for i in range(mantle.size()):
		if mantle[i].y > 0: mantle[i].x += sin(t*2.4+mantle[i].y*0.05)*3.0
	shape(ci,mantle,MANTLE.darkened(0.12),RUST)
	ci.draw_polyline(STROKES.mantle_fold,RUST.darkened(0.25),3.0,true)
	var mantle_fire: float = p.get("mantle_fire",0.0)
	if mantle_fire > 0.0:
		# An ignited mantle burns along its ragged hem.
		for i in range(0,mantle.size(),6):
			if mantle[i].y > 15.0:
				VFX.draw_flame(ci,mantle[i],20.0*mantle_fire,8.0,t,float(i)*0.7,fire,HORN)
	# Heavy haunches and three hooked toes anchor the creature to the same floor.
	# Optional pose keys (seat, rise, roar, kneel...) all default to the plain
	# standing Warden, so a bare pose draws exactly as it always has.
	var sit: float = p.get("sit",0.0)
	var kneeling: float = p.get("kneel",0.0)
	for side: float in [-1.0,1.0]:
		var hip := Vector2(side*20,14)
		var knee := Vector2(side*25+stride*side,35).lerp(Vector2(36+side*7,22),sit)
		var foot := Vector2(side*24-stride*side,55).lerp(Vector2(40+side*8,38),sit)
		# Kneeling (drawn KNEEL_SAG lower): front foot planted, rear knee down.
		knee = knee.lerp(Vector2(42,18) if side > 0.0 else Vector2(-6,40),kneeling)
		foot = foot.lerp(Vector2(40,39) if side > 0.0 else Vector2(-34,41),kneeling)
		ci.draw_line(hip,knee,INK,25.0,true)
		ci.draw_line(hip,knee,CHAR,20.0,true)
		ci.draw_line(knee,foot,INK,20.0,true)
		ci.draw_line(knee,foot,rust.darkened(0.15),15.0,true)
		ci.draw_colored_polygon(PackedVector2Array([foot+Vector2(-11,-6),foot+Vector2(9,-6),foot+Vector2(18,2),foot+Vector2(14,6),foot+Vector2(-13,5)]),rust.darkened(0.22))
		ci.draw_line(foot+Vector2(-3,-3),foot+Vector2(14,3),HORN.darkened(0.2),2.0,true)
	var back_shoulder := Vector2(-31,-34)
	var back_elbow := back_shoulder.lerp(p.offhand,0.52)+Vector2(-13,0)
	arm(ci,back_shoulder,back_elbow,p.offhand,float(p.off_angle),rust.darkened(0.30))
	shape(ci,BODY.body,rust)
	# Broad shading planes replace the rejected costume's many little plates.
	ci.draw_colored_polygon(BODY.shade,CHAR)
	ci.draw_polyline(STROKES.shoulder_ridge,RIDGE.darkened(0.14),3.5,true)
	# Scorched torso fissure: one directional ember motif, not a lantern/grille.
	var fissure: float = p.get("fissure",2.4 if phase2 else 1.5)
	ci.draw_polyline(STROKES.fissure,INK,maxf(7.0,fissure+4.0),true)
	ci.draw_polyline(STROKES.fissure,fire,fissure,true)
	shape(ci,BODY.head,rust.lightened(0.10))
	ci.draw_colored_polygon(BODY.face,INK)
	# Side-on eye, jaw and fangs read as a beast rather than a human death mask.
	# A dormant Warden's eye is dark ink; it kindles as it wakes.
	var eye: float = p.get("eye",1.0)
	ci.draw_line(Vector2(11,-68),Vector2(27,-70),INK.lerp(Color("ffdb87"),eye),4.0,true)
	ci.draw_line(Vector2(22,-69),Vector2(28,-71),Color(Color.WHITE,eye),1.5,true)
	ci.draw_polyline(STROKES.jaw,RIDGE,3.5,true)
	for x in [23.0,32.0]:
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x,-48),Vector2(x+4,-48),Vector2(x+2,-57)]),HORN)
	if p.get("pant",false):
		# Winded breath puffing from the jaw: the cue that it is open to a blow.
		var pk := fmod(t,0.35)/0.35
		var puff := Vector2(48+6.0*pk,-50-14.0*pk)
		var r := 4.0+4.0*pk
		ci.draw_circle(puff,r,Color(RIDGE,0.75*(1.0-pk)))
		ci.draw_arc(puff,r,0.0,TAU,14,Color(INK,0.6*(1.0-pk)),1.5,true)
	# Flame crown shares the hero's warm identity.
	var crown_scale: float = (1.35 if phase2 else 1.0)*float(p.get("crown",1.0))
	for i in range(CROWN.size()):
		var base: Vector2 = CROWN[i][0]
		var height: float = CROWN[i][1]
		var width: float = CROWN[i][2]
		if p.get("spent",false):
			# Burnt down to charred stubs, an ember still glowing at each tip.
			var tip := base+Vector2(0,-height*0.4)
			ci.draw_colored_polygon(PackedVector2Array([base+Vector2(-width*0.5,0),tip,base+Vector2(width*0.5,0)]),CHARRED)
			ci.draw_circle(tip,2.0,fire)
		else:
			# After the knight took the crown, the Warden wears it in the knight's gold.
			var gold: float = p.get("crown_gold",0.0)
			VFX.draw_flame(ci,base,height*crown_scale,width,t,[1.0,2.3,4.0][i],fire.lerp(VFX.GOLD,gold),Content.PAL.attack.lerp(VFX.HOT,gold))
	arm(ci,p.shoulder,p.elbow,p.hand,float(p.claw_angle),rust)
	if phase2:
		ci.draw_line(p.elbow+Vector2(3,0),p.hand,fire,2.0,true)
		VFX.draw_flame(ci,Vector2(-36,-40),15.0,6.0,t,5.1,fire,HORN)
	if p.windup and int(b.action_idx) == Boss.Action.FAN:
		var palm: Vector2 = p.offhand+Vector2(-6,-18)
		VFX.draw_flame(ci,palm,20.0+float(p.progress)*14.0,9.0,t,0.4,fire,HORN)
	if p.has("dying"):
		# Fire splitting the body along fault lines before it comes apart.
		var dk: float = p.dying
		for i in range(FAULTS.size()):
			var reveal := clampf(dk * 4.0 - float(i) * 0.7, 0.0, 1.0)
			if reveal <= 0.0:
				continue
			var line := PackedVector2Array()
			var pts: Array = FAULTS[i]
			var n := int(ceil(reveal * float(pts.size() - 1))) + 1
			for j in range(n):
				line.append(pts[j])
			if line.size() >= 2:
				ci.draw_polyline(line,INK,6.0,true)
				ci.draw_polyline(line,fire.lerp(Color.WHITE,dk*0.6),2.5+dk*2.0,true)
	if p.windup and int(b.action_idx) == Boss.Action.CHARGE:
		for i in range(3):
			var x := 55.0+float(i)*27.0
			ci.draw_polyline(PackedVector2Array([Vector2(x-7,54),Vector2(x,58),Vector2(x-7,62)]),Color(fire,0.2+float(p.progress)*0.6),2.0,true)
	ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
