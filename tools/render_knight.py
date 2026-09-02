"""Model, pose and render the Graveflame knight in Blender.

Run:  blender -b --python tools/render_knight.py -- OUT_DIR
Writes OUT_DIR/<pose>_f<k>.png (RGBA, 8x the art resolution) for every pose
and each of the four fire-crown flicker frames, plus poses.json. The Godot
bake step (tests/knight_bake.gd) turns those into the palette-quantized sheet.

Units are art pixels. The knight faces +X, stands on z = 0 and is ~26 px tall;
the camera frames x in [-20, 20], z in [0, 40] (a 40 x 40 art frame).
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

ART_W, ART_H = 40, 40
SUPER = 8  # render supersampling factor

# --- palette-ish base colours (the bake step quantizes to the real palette) ---
COL = {
    "outline": (0.08, 0.06, 0.10),
    "cloak": (0.34, 0.11, 0.14),
    "tunic": (0.91, 0.88, 0.82),
    "sash": (1.0, 0.48, 0.09),
    "trousers": (0.16, 0.13, 0.20),
    "boot": (0.09, 0.07, 0.12),
    "head": (0.17, 0.13, 0.22),
    "mask": (0.85, 0.81, 0.75),
    "steel": (0.62, 0.68, 0.76),
    "gold": (0.94, 0.70, 0.35),
    "flame_outer": (1.0, 0.36, 0.06),
    "flame_inner": (1.0, 0.72, 0.22),
    "flame_core": (1.0, 0.95, 0.82),
    "eye": (1.0, 0.5, 0.1),
}


def rad(d):
    return math.radians(d)


# Flat colours for the material-ID pass; the bake tones each pixel inside the
# ramp that belongs to its family, so lighting never bleeds between materials.
ID_COLORS = {
    "cloak": (1, 0, 0), "tunic": (0, 1, 0), "dark": (0, 0, 1), "mask": (0, 1, 1), "steel": (1, 0, 1),
    "gold": (1, 1, 0), "sash": (1, 0.5, 0), "flame_outer": (0.5, 0, 0), "flame_inner": (0, 0.5, 0),
    "flame_core": (1, 1, 1), "eye": (0, 0, 0.5), "outline": (0, 0, 0), "head": (0.5, 0, 0.5),
}
FAMILY = {
    "cloak": "cloak", "tunic": "tunic", "trousers": "dark", "boot": "dark", "head": "head", "mask": "mask",
    "steel": "steel", "gold": "gold", "sash": "sash", "flame_outer": "flame_outer", "flame_inner": "flame_inner",
    "flame_core": "flame_core", "eye": "eye", "outline": "outline",
}
OUTLINE_THICKNESS = 0.9


def mat(name, color, rough=0.9, emit=0.0, metallic=0.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if emit > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    return m


def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    e.location = loc
    return e


def outline_material():
    m = bpy.data.materials.get("outline")
    if m is None:
        m = mat("outline", COL["outline"], rough=1.0)
        m.use_backface_culling = True
    return m


def finish(obj, name, material, parent, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), smooth=True):
    obj.name = name
    obj.data.materials.append(material)
    # (The dark silhouette edge is added by the bake step, which dilates the
    # alpha by one art pixel; an inverted hull is not culled reliably in EEVEE.)
    obj.parent = parent
    obj.location = loc
    obj.rotation_euler = rot
    obj.scale = scale
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    return obj


def box(name, material, parent, size, loc=(0, 0, 0), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    return finish(bpy.context.active_object, name, material, parent, loc, rot, size, smooth=False)


def sphere(name, material, parent, radius, loc=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=24, ring_count=12)
    return finish(bpy.context.active_object, name, material, parent, loc, (0, 0, 0), scale)


def capsule(name, material, parent, radius, length, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Cylinder along local -Z from the pivot (a limb hanging from its joint)."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=length)
    o = finish(bpy.context.active_object, name, material, parent, loc, rot)
    # shift so the top sits at the pivot
    for v in o.data.vertices:
        v.co.z -= length * 0.5
    return o


def cone(name, material, parent, r, h, loc=(0, 0, 0), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=r, radius2=0.0, depth=h)
    o = finish(bpy.context.active_object, name, material, parent, loc, rot)
    for v in o.data.vertices:
        v.co.z += h * 0.5
    return o


def torus(name, material, parent, major, minor, loc=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=24, minor_segments=8, major_radius=major, minor_radius=minor)
    return finish(bpy.context.active_object, name, material, parent, loc)


def build_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x = ART_W * SUPER
    sc.render.resolution_y = ART_H * SUPER
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    try:
        sc.eevee.taa_render_samples = 16
    except Exception:
        pass
    # World: dim cool ambient so shadows keep colour.
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.28, 0.24, 0.36, 1.0)
    bg.inputs[1].default_value = 0.7
    sc.world = world
    # Camera: orthographic side view, character faces +X.
    cam = bpy.data.cameras.new("Cam")
    cam.type = "ORTHO"
    cam.ortho_scale = ART_W
    co = bpy.data.objects.new("Cam", cam)
    sc.collection.objects.link(co)
    co.location = (0.0, -120.0, ART_H * 0.5)
    co.rotation_euler = (rad(90), 0, 0)
    sc.camera = co
    # Key from upper front-left of the viewer, warm; fill from behind, cool.
    key = bpy.data.lights.new("Key", "SUN")
    key.energy = 4.2
    key.color = (1.0, 0.93, 0.85)
    ko = bpy.data.objects.new("Key", key)
    sc.collection.objects.link(ko)
    ko.rotation_euler = (rad(55), rad(-20), rad(-35))
    fill = bpy.data.lights.new("Fill", "SUN")
    fill.energy = 1.1
    fill.color = (0.6, 0.65, 0.95)
    fo = bpy.data.objects.new("Fill", fill)
    sc.collection.objects.link(fo)
    fo.rotation_euler = (rad(60), rad(25), rad(150))
    return sc


class Knight:
    def __init__(self):
        m = {k: mat(k, v) for k, v in COL.items()}
        m["flame_outer"] = mat("flame_outer", COL["flame_outer"], emit=6.0)
        m["flame_inner"] = mat("flame_inner", COL["flame_inner"], emit=8.0)
        m["flame_core"] = mat("flame_core", COL["flame_core"], emit=10.0)
        m["eye"] = mat("eye", COL["eye"], emit=8.0)
        m["steel"] = mat("steel", COL["steel"], rough=0.35, metallic=0.6)
        m["gold"] = mat("gold", COL["gold"], rough=0.45, metallic=0.5)
        self.m = m
        # Joints
        self.root = empty("root", None, (0, 0, 0))
        self.hips = empty("hips", self.root, (0, 0, 10.0))
        self.spine = empty("spine", self.hips, (0, 0, 0.5))
        self.neck = empty("neck", self.spine, (0.6, 0, 8.4))
        self.thigh = {}
        self.shin = {}
        for side, y in (("F", -2.2), ("B", 2.2)):
            t = empty("thigh" + side, self.hips, (0, y, 0))
            s = empty("shin" + side, t, (0, 0, -5.2))
            self.thigh[side] = t
            self.shin[side] = s
            capsule("thighMesh" + side, m["trousers"], t, 2.1, 5.2)
            capsule("shinMesh" + side, m["trousers"], s, 1.8, 4.4)
            box("boot" + side, m["boot"], s, (4.6, 3.6, 2.2), (1.0, 0, -4.6))
        # Torso, sash, belt
        box("torso", m["tunic"], self.spine, (8.6, 6.6, 8.0), (0.2, 0, 4.3))
        box("shoulderF", m["cloak"], self.spine, (3.6, 3.0, 2.6), (0.6, -3.6, 8.4))
        box("shoulderB", m["cloak"], self.spine, (3.6, 3.0, 2.6), (0.6, 3.6, 8.4))
        box("sash", m["sash"], self.spine, (2.0, 0.6, 9.6), (0.3, -3.4, 4.6), (0, rad(-28), 0))
        box("belt", m["trousers"], self.spine, (9.0, 7.0, 1.4), (0.2, 0, 0.6))
        box("buckle", m["gold"], self.spine, (2.0, 0.6, 1.4), (2.0, -3.5, 0.6))
        # Arms
        self.shoulder = {}
        for side, y in (("F", -4.0), ("B", 4.0)):
            sh = empty("shoulder" + side, self.spine, (0.6, y, 7.8))
            self.shoulder[side] = sh
            capsule("armMesh" + side, m["tunic"], sh, 1.6, 6.2)
            sphere("hand" + side, m["boot"], sh, 1.7, (0, 0, -6.4))
        # Sword hangs from the front hand.
        self.wrist = empty("wrist", self.shoulder["F"], (0, -0.6, -6.6))
        box("grip", m["boot"], self.wrist, (1.3, 1.3, 2.8), (0, 0, 0.2))
        box("guard", m["gold"], self.wrist, (1.4, 1.4, 5.6), (0, 0, 1.7), (rad(90), 0, 0))
        box("pommel", m["gold"], self.wrist, (1.8, 1.8, 1.4), (0, 0, -1.6))
        box("blade", m["steel"], self.wrist, (2.2, 0.7, 10.5), (0, 0, 7.0))
        box("bladeEdge", m["tunic"], self.wrist, (0.7, 0.8, 9.5), (0.8, 0, 7.0))
        # Head with mask and eye, crown ring, flames
        head = sphere("head", m["head"], self.neck, 5.0, (0.2, 0, 4.4), (1.0, 0.95, 1.05))
        sphere("mask", m["mask"], self.neck, 4.4, (2.4, 0, 3.9), (0.55, 0.95, 1.0))
        sphere("eye", m["eye"], self.neck, 1.0, (5.0, -1.6, 4.6))
        torus("crown", m["gold"], self.neck, 5.0, 0.7, (0.2, 0, 8.2))
        self.flames = []
        for i, (x, y) in enumerate(((-3.8, 1.0), (-2.0, -2.6), (0.2, 0.6), (2.4, -2.6), (4.2, 1.0))):
            outer = cone("flame%d" % i, m["flame_outer"], self.neck, 1.6, 5.4, (x, y, 8.0))
            inner = cone("flameIn%d" % i, m["flame_inner"], self.neck, 1.0, 4.0, (x, y - 0.5, 8.2))
            core = cone("flameCore%d" % i, m["flame_core"], self.neck, 0.5, 2.2, (x, y - 1.0, 8.4))
            self.flames.append((outer, inner, core))
        # Cape: three hanging segments behind the back shoulder.
        self.cape = []
        parent = empty("cape0", self.spine, (-3.8, 0.0, 8.6))
        self.cape.append(parent)
        box("capeMesh0", m["cloak"], parent, (1.4, 8.0, 5.6), (0, 0, -2.8))
        for i in (1, 2):
            seg = empty("cape%d" % i, parent, (0, 0, -5.6))
            box("capeMesh%d" % i, m["cloak"], seg, (1.4, 8.0 - i * 0.8, 5.6), (0, 0, -2.8))
            self.cape.append(seg)
            parent = seg

    def pose(self, p):
        self.root.location = (0, 0, -p.get("bob", 0.0))
        self.spine.rotation_euler = (0, rad(p.get("torso", 0.0)), 0)
        self.neck.rotation_euler = (0, rad(p.get("head", 0.0)), 0)
        legs = p.get("legs", (0, 0, 0, 0))
        self.thigh["F"].rotation_euler = (0, rad(legs[0]), 0)
        self.shin["F"].rotation_euler = (0, rad(legs[1]), 0)
        self.thigh["B"].rotation_euler = (0, rad(legs[2]), 0)
        self.shin["B"].rotation_euler = (0, rad(legs[3]), 0)
        # Arm angle: 0 hangs down; positive swings forward (+X). The sword blade
        # points along the arm's -Z continuation, so sword_angle maps directly.
        self.shoulder["F"].rotation_euler = (0, rad(p.get("arm", 20.0)), 0)
        self.wrist.rotation_euler = (0, rad(p.get("wrist", 0.0) + 180.0), 0)
        self.shoulder["B"].rotation_euler = (0, rad(p.get("arm_back", -10.0)), 0)
        cape = p.get("cape", (12, 8, 6))
        for seg, a in zip(self.cape, cape):
            seg.rotation_euler = (0, rad(a), 0)

    def flicker(self, k):
        heights = [
            (4.0, 5.2, 3.4, 5.6, 3.8),
            (4.8, 4.2, 5.6, 4.0, 4.6),
            (3.6, 5.8, 4.4, 5.0, 4.2),
            (5.2, 3.8, 5.0, 4.6, 5.4),
        ][k % 4]
        for (outer, inner, core), h in zip(self.flames, heights):
            outer.scale = (1.0, 1.0, h / 4.0)
            inner.scale = (1.0, 1.0, h / 4.0)
            core.scale = (1.0, 1.0, h / 4.0)
            lean = math.sin(k * 1.7 + h) * 6.0
            for o in (outer, inner, core):
                o.rotation_euler = (0, rad(lean), 0)


# Sword angle convention (game): radians from horizontal, positive = down.
# Arm angle here: degrees, 0 = hanging straight down, 90 = forward horizontal.
def sword_to_arm(sword_rad):
    return 90.0 - math.degrees(sword_rad)


POSES = {
    "idle0": dict(bob=0.0, torso=2, head=0, legs=(4, -4, -4, 4), arm=sword_to_arm(0.6), cape=(10, 6, 4)),
    "idle1": dict(bob=0.35, torso=3, head=1, legs=(4, -4, -4, 4), arm=sword_to_arm(0.62), cape=(12, 7, 5)),
    "run0": dict(bob=0.6, torso=10, head=4, legs=(38, -20, -30, 45), arm=sword_to_arm(0.8), cape=(45, 20, 10)),
    "run1": dict(bob=0.0, torso=10, head=4, legs=(10, -60, 0, 10), arm=sword_to_arm(0.75), cape=(40, 18, 8)),
    "run2": dict(bob=0.6, torso=10, head=4, legs=(-30, 45, 38, -20), arm=sword_to_arm(0.8), cape=(45, 20, 10)),
    "run3": dict(bob=0.0, torso=10, head=4, legs=(0, 10, 10, -60), arm=sword_to_arm(0.75), cape=(40, 18, 8)),
    "jump": dict(bob=-0.5, torso=4, head=-4, legs=(30, -70, -10, 20), arm=sword_to_arm(-0.3), cape=(-25, -20, -15)),
    "fall": dict(bob=0.3, torso=6, head=6, legs=(15, -30, -20, 10), arm=sword_to_arm(0.9), cape=(-40, -30, -20)),
    "dash": dict(bob=1.8, torso=22, head=6, legs=(50, -30, -45, 30), arm=sword_to_arm(0.05), cape=(70, 30, 15)),
    "hurt": dict(bob=0.4, torso=-14, head=-12, legs=(-10, 10, 20, -10), arm=sword_to_arm(-0.5), cape=(-10, -5, 0)),
    "heal": dict(bob=2.2, torso=8, head=8, legs=(45, -80, -35, 70), arm=sword_to_arm(1.3), arm_back=-70, cape=(8, 5, 3)),
    "parry": dict(bob=0.2, torso=4, head=0, legs=(8, -8, -8, 8), arm=sword_to_arm(-1.5), cape=(12, 6, 4)),
    "slam": dict(bob=0.0, torso=12, head=10, legs=(30, -60, -15, 25), arm=sword_to_arm(1.45), cape=(-50, -30, -10)),
}
ATTACK_FRAMES = 8
for i in range(ATTACK_FRAMES):
    ang = -1.6 + 3.2 * i / (ATTACK_FRAMES - 1)
    lunge = i >= 3
    POSES["atk%d" % i] = dict(
        bob=0.5 if lunge else 0.0, torso=16 if lunge else 4, head=6 if lunge else 0,
        legs=(40, -20, -30, 40) if lunge else (6, -6, -6, 6),
        arm=sword_to_arm(ang), cape=(35, 18, 10) if lunge else (12, 6, 4),
    )


def set_id_mode(on):
    """Swap every material to a flat emission of its family ID colour (or back)."""
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        nt = m.node_tree
        out = nt.nodes.get("Material Output")
        bsdf = nt.nodes.get("Principled BSDF")
        emi = nt.nodes.get("IDEmission")
        if emi is None:
            emi = nt.nodes.new("ShaderNodeEmission")
            emi.name = "IDEmission"
            fam = FAMILY.get(m.name, "dark")
            emi.inputs["Color"].default_value = (*ID_COLORS[fam], 1.0)
            emi.inputs["Strength"].default_value = 1.0
        for link in list(nt.links):
            if link.to_node == out and link.to_socket.name == "Surface":
                nt.links.remove(link)
        nt.links.new((emi if on else bsdf).outputs[0], out.inputs["Surface"])


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = argv[0] if argv else "/tmp/graveflame-knight-render"
    os.makedirs(out_dir, exist_ok=True)
    sc = build_scene()
    knight = Knight()
    manifest = {"poses": list(POSES.keys()), "flicker": 4, "art": [ART_W, ART_H], "super": SUPER}
    for id_pass in (False, True):
        set_id_mode(id_pass)
        if id_pass:
            sc.world.node_tree.nodes.get("Background").inputs[1].default_value = 0.0
            sc.eevee.taa_render_samples = 1
        for name, p in POSES.items():
            knight.pose(p)
            for k in range(4):
                knight.flicker(k)
                suffix = "_id" if id_pass else ""
                sc.render.filepath = os.path.join(out_dir, "%s_f%d%s.png" % (name, k, suffix))
                bpy.ops.render.render(write_still=True)
    with open(os.path.join(out_dir, "poses.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print("KNIGHT_RENDER_DONE", len(POSES) * 4)


if __name__ == "__main__":
    main()
