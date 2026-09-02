"""Model, pose and render the Graveflame creature family in Blender.

Run:  blender -b --python tools/render_creatures.py -- OUT_DIR [creature,creature]
Writes OUT_DIR/<creature>_<state>_<k>.png (lit) and *_id.png (material IDs) at
SUPER x the frame size, plus creatures.json. tests/creature_bake.gd turns them
into assets/creatures/<creature>_<state>.png sheets and anim_manifest.json.

Units are world pixels (frames are drawn at scale 1 in game). Each creature
faces +X and stands on z = 0; the camera frames x in [-w/2, w/2], z in [0, h].
States and frame counts match the game: idle 4, windup 3, attack 3, stagger 2,
death 3.
"""
import json
import math
import os
import sys

import bpy

SUPER = 6
STATES = {"idle": 4, "windup": 3, "attack": 3, "stagger": 2, "death": 3}

# Material families: (base colour, ID colour). The bake tones each family's ramp.
FAMILIES = {
    "cloth": ((0.30, 0.32, 0.44), (1, 0, 0)),
    "cloth_dark": ((0.16, 0.17, 0.25), (0, 1, 0)),
    "skin": ((0.36, 0.46, 0.30), (0, 0, 1)),
    "iron": ((0.22, 0.23, 0.30), (1, 1, 0)),
    "gold": ((0.94, 0.70, 0.35), (1, 0, 1)),
    "steel": ((0.62, 0.68, 0.76), (0, 1, 1)),
    "glow_teal": ((0.25, 0.95, 0.95), (0.5, 0, 0)),
    "glow_orange": ((1.0, 0.45, 0.10), (0, 0.5, 0)),
    "eye": ((1.0, 0.5, 0.1), (0, 0, 0.5)),
    "flame": ((1.0, 0.42, 0.08), (0.5, 0.5, 0)),
    "bone": ((0.82, 0.78, 0.68), (0.5, 0, 0.5)),
    "cloak_red": ((0.42, 0.09, 0.14), (0, 0.5, 0.5)),
    "belly": ((0.72, 0.74, 0.58), (1, 0.5, 0)),
    "void": ((0.05, 0.04, 0.07), (0.5, 0.5, 0.5)),
}
EMISSIVE = {"glow_teal": 5.0, "glow_orange": 4.0, "eye": 8.0, "flame": 8.0}


def rad(d):
    return math.radians(d)


def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    color, _ = FAMILIES[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.35 if name in ("steel", "gold") else 0.85
    bsdf.inputs["Metallic"].default_value = 0.6 if name in ("steel", "gold", "iron") else 0.0
    if name in EMISSIVE:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = EMISSIVE[name]
    return m


def set_id_mode(on):
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
            emi.inputs["Color"].default_value = (*FAMILIES[m.name][1], 1.0)
            emi.inputs["Strength"].default_value = 1.0
        for link in list(nt.links):
            if link.to_node == out and link.to_socket.name == "Surface":
                nt.links.remove(link)
        nt.links.new((emi if on else bsdf).outputs[0], out.inputs["Surface"])


def scene(width, height):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x = width * SUPER
    sc.render.resolution_y = height * SUPER
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.eevee.taa_render_samples = 16
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.30, 0.34, 0.5, 1.0)
    bg.inputs[1].default_value = 0.6
    sc.world = world
    cam = bpy.data.cameras.new("Cam")
    cam.type = "ORTHO"
    cam.sensor_fit = "HORIZONTAL"
    cam.ortho_scale = width
    cam.clip_end = 2000.0
    co = bpy.data.objects.new("Cam", cam)
    sc.collection.objects.link(co)
    co.location = (0.0, -400.0, height * 0.5)
    co.rotation_euler = (rad(90), 0, 0)
    sc.camera = co
    key = bpy.data.lights.new("Key", "SUN")
    key.energy = 4.0
    key.color = (1.0, 0.92, 0.84)
    ko = bpy.data.objects.new("Key", key)
    sc.collection.objects.link(ko)
    ko.rotation_euler = (rad(55), rad(-20), rad(-35))
    fill = bpy.data.lights.new("Fill", "SUN")
    fill.energy = 1.2
    fill.color = (0.55, 0.65, 1.0)
    fo = bpy.data.objects.new("Fill", fill)
    sc.collection.objects.link(fo)
    fo.rotation_euler = (rad(60), rad(25), rad(150))
    return sc


# --- primitives -----------------------------------------------------------------------

def finish(obj, name, family, parent, loc, rot=(0, 0, 0), scale=(1, 1, 1), smooth=True, bevel=0.0):
    obj.name = name
    obj.data.materials.append(mat(family))
    obj.parent = parent
    obj.location = loc
    obj.rotation_euler = rot
    obj.scale = scale
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    for p in obj.data.polygons:
        p.use_smooth = smooth
    return obj


def box(name, fam, parent, size, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    o = bpy.context.active_object
    if bevel > 0.0:
        # bake the scale so the bevel width is uniform
        o.scale = size
        bpy.ops.object.transform_apply(scale=True)
        return finish(o, name, fam, parent, loc, rot, (1, 1, 1), smooth=False, bevel=bevel)
    return finish(o, name, fam, parent, loc, rot, size, smooth=False)


def sphere(name, fam, parent, r, loc=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=24, ring_count=12)
    return finish(bpy.context.active_object, name, fam, parent, loc, (0, 0, 0), scale)


def capsule(name, fam, parent, r, length, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Limb hanging along local -Z from its joint, rounded ends."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=r, depth=length)
    o = finish(bpy.context.active_object, name, fam, parent, loc, rot)
    for v in o.data.vertices:
        v.co.z -= length * 0.5
    sphere(name + "_cap", fam, o, r, (0, 0, -length))
    sphere(name + "_top", fam, o, r, (0, 0, 0))
    return o


def cone(name, fam, parent, r, h, loc=(0, 0, 0), rot=(0, 0, 0), verts=12):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0.0, depth=h)
    o = finish(bpy.context.active_object, name, fam, parent, loc, rot)
    for v in o.data.vertices:
        v.co.z += h * 0.5
    return o


def torus(name, fam, parent, major, minor, loc=(0, 0, 0), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=24, minor_segments=8, major_radius=major, minor_radius=minor)
    return finish(bpy.context.active_object, name, fam, parent, loc, rot)


class Rig:
    def __init__(self):
        self.j = {}
        self.root = self.joint("root")

    def joint(self, name, parent=None, loc=(0, 0, 0)):
        e = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(e)
        e.parent = parent
        e.location = loc
        self.j[name] = e
        return e

    def apply(self, pose):
        """pose: {joint: deg (rot about Y) | {"rot": deg, "loc": (x,y,z), "scale": s|(x,y,z)}}"""
        for name, spec in pose.items():
            e = self.j.get(name)
            if e is None:
                continue
            if isinstance(spec, dict):
                e.rotation_euler = (0, rad(spec.get("rot", 0.0)), 0)
                if "loc" in spec:
                    e.location = spec["loc"]
                if "scale" in spec:
                    s = spec["scale"]
                    e.scale = (s, s, s) if isinstance(s, (int, float)) else s
            else:
                e.rotation_euler = (0, rad(spec), 0)

    def reset(self):
        for e in self.j.values():
            e.rotation_euler = (0, 0, 0)
            e.scale = (1, 1, 1)


def lerp(a, b, t):
    return a + (b - a) * t


def fall(k, n):
    """Death: topple backwards about the feet over the frames."""
    t = (k + 1) / n
    return {"root": {"rot": -lerp(20, 88, t), "loc": (-4 * t, 0, -2 * t)}}


# --- creatures ---------------------------------------------------------------------------

def stalker(rig):
    r = rig
    hips = r.joint("hips", r.root, (0, 0, 19))
    spine = r.joint("spine", hips, (0, 0, 1))
    neck = r.joint("neck", spine, (2.5, 0, 17))
    for side, y in (("F", -3.2), ("B", 3.2)):
        t = r.joint("thigh" + side, hips, (0, y, 0))
        s = r.joint("shin" + side, t, (0, 0, -10))
        capsule("thigh" + side, "cloth_dark", t, 2.8, 10)
        capsule("shin" + side, "cloth_dark", s, 2.4, 9)
        box("foot" + side, "void", s, (7, 4, 2.6), (2.2, 0, -9.6))
    # hunched robe, wide hem
    box("robe", "cloth", spine, (13, 10, 17), (0, 0, 8.5), bevel=1.5)
    box("hem", "cloth", hips, (15, 11, 6), (-0.5, 0, -1), bevel=1.2)
    box("belt", "cloth_dark", spine, (14, 11, 2), (0, 0, 2))
    for side, y in (("F", -6.5), ("B", 6.5)):
        sh = r.joint("shoulder" + side, spine, (1, y, 15))
        capsule("arm" + side, "cloth", sh, 2.4, 11)
        sphere("hand" + side, "void", sh, 2.4, (0, 0, -11.5))
    wrist = r.joint("wrist", r.j["shoulderF"], (0, -0.6, -11.8))
    box("dagger", "steel", wrist, (2.4, 0.9, 13), (0, 0, -5.0))
    box("dedge", "bone", wrist, (0.7, 1.0, 11), (1.0, 0, -5.0))
    box("dguard", "gold", wrist, (5.5, 1.6, 1.6), (0, 0, 1.6))
    # hood with a void face and one ember eye
    sphere("hood", "cloth", neck, 7.4, (-1.0, 0, 5), (1.05, 1.0, 1.2))
    cone("peak", "cloth", neck, 5.5, 10, (-3.5, 0, 9), rot=(0, rad(-40), 0))
    box("brim", "cloth", neck, (6, 12, 2.4), (4.5, 0, 9.5), bevel=0.8)
    sphere("face", "void", neck, 5.6, (5.2, 0, 4.2), (0.75, 0.95, 1.0))
    sphere("eye", "eye", neck, 1.5, (8.6, -1.8, 5.0))
    box("jaw", "bone", neck, (2.2, 5, 1.2), (8.4, 0, 1.6))
    cone("hemL", "cloth", hips, 2.2, 5, (-4, -3, -3), rot=(math.pi, 0, 0))
    cone("hemR", "cloth", hips, 2.2, 5, (2, 3, -3), rot=(math.pi, 0, 0))


def stalker_pose(state, k, n):
    t = k / max(1, n - 1)
    base = {"spine": 18, "neck": -14, "thighF": 10, "shinF": -18, "thighB": -8, "shinB": 12, "shoulderF": 35, "shoulderB": -10, "wrist": 25}
    if state == "idle":
        w = math.sin(t * math.pi * 2)
        base.update({"spine": 18 + 2 * w, "shoulderF": 20 + 4 * w, "root": {"rot": 0, "loc": (0, 0, -0.6 * (1 - math.cos(t * math.pi * 2)) * 0.5)}})
    elif state == "windup":
        base.update({"spine": lerp(18, 4, t), "shoulderF": lerp(35, -110, t), "wrist": 60, "shoulderB": lerp(-10, 30, t), "root": {"rot": 0, "loc": (-2 * t, 0, 0)}})
    elif state == "attack":
        base.update({"spine": lerp(30, 42, t), "shoulderF": lerp(60, 115, t), "wrist": 10, "thighF": 40, "shinF": -20, "thighB": -35, "shinB": 30, "root": {"rot": 0, "loc": (lerp(4, 9, t), 0, 0)}})
    elif state == "stagger":
        base.update({"spine": -22 - 8 * t, "neck": 15, "shoulderF": -40, "shoulderB": -50, "root": {"rot": 0, "loc": (-3 - 3 * t, 0, 0)}})
    elif state == "death":
        base.update({"spine": -10, "shoulderF": -60, "shoulderB": -40})
        base.update(fall(k, n))
    return base


def hopper(rig):
    r = rig
    body = r.joint("body", r.root, (0, 0, 16))
    sphere("torso", "skin", body, 12, (0, 0, 3), (1.25, 0.75, 0.9))
    sphere("belly", "belly", body, 9, (5, 0, -1), (0.9, 0.6, 0.7))
    for i, (x, y, z) in enumerate(((-8, -3, 12), (-3, 4, 14), (3, -5, 13), (-9, 5, 9))):
        sphere("wart%d" % i, "cloth_dark", body, 1.6, (x, y, z))
    sphere("eyeF", "eye", body, 2.2, (10, -4, 8))
    sphere("eyeB", "eye", body, 1.8, (7.5, -8.5, 9.5))
    sphere("brow", "skin", body, 4.5, (9, -4, 10.5), (1.0, 1.2, 0.6))
    box("mouth", "void", body, (2.0, 14, 1.4), (13.6, 0, 3))
    for i in range(3):
        cone("fang%d" % i, "bone", body, 0.9, 2.4, (13.9, -4 + i * 4, 2.4), rot=(math.pi, 0, 0), verts=6)
    for side, y in (("F", -10.5), ("B", 10.5)):
        t = r.joint("thigh" + side, body, (-6, y, -1))
        s = r.joint("shin" + side, t, (0, 0, -11))
        f = r.joint("foot" + side, s, (0, 0, -11))
        capsule("thigh" + side, "skin", t, 3.8, 11)
        capsule("shin" + side, "skin", s, 2.8, 11)
        box("foot" + side, "cloth_dark", f, (9, 4, 2.2), (3, 0, 0))
        a = r.joint("arm" + side, body, (8, y * 0.85, -3))
        capsule("arm" + side, "skin", a, 1.8, 7)
        sphere("hand" + side, "cloth_dark", a, 2.0, (0, 0, -7.5))


def hopper_pose(state, k, n):
    t = k / max(1, n - 1)
    base = {"thighF": -75, "shinF": 140, "footF": -65, "thighB": -75, "shinB": 140, "footB": -65, "armF": 35, "armB": 30}
    if state == "idle":
        w = math.sin(t * math.pi * 2)
        base.update({"body": {"rot": 2 * w, "loc": (0, 0, 16 + 0.8 * w), "scale": (1.0, 1.0, 1.0 + 0.03 * w)}})
    elif state == "windup":
        base.update({"thighF": lerp(-75, -95, t), "shinF": lerp(140, 165, t), "footF": lerp(-65, -70, t), "thighB": lerp(-75, -95, t), "shinB": lerp(140, 165, t), "footB": -70,
                     "body": {"rot": -6 * t, "loc": (0, 0, 16 - 4 * t)}, "armF": 60, "armB": 55})
    elif state == "attack":
        base.update({"thighF": lerp(-40, -15, t), "shinF": lerp(60, 20, t), "footF": lerp(-20, -5, t), "thighB": lerp(-40, -15, t), "shinB": lerp(60, 20, t), "footB": -5,
                     "body": {"rot": 18, "loc": (4 + 4 * t, 0, 24 + 6 * (1 - t))}, "armF": 95, "armB": 90})
    elif state == "stagger":
        base.update({"body": {"rot": -25 - 8 * t, "loc": (-3, 0, 16)}, "armF": -30, "armB": -30})
    elif state == "death":
        base.update({"body": {"rot": -10, "loc": (0, 0, 16 - 6 * t), "scale": (1.15 + 0.1 * t, 1.0, 0.7 - 0.25 * t)}, "thighF": -40, "shinF": 40, "thighB": -40, "shinB": 40, "armF": -60, "armB": -60})
    return base


def wisp(rig):
    r = rig
    core = r.joint("core", r.root, (0, 0, 38))
    glow = r.joint("glow", core, (0, 0, 0))
    sphere("orb", "glow_teal", glow, 5.2)
    sphere("orbin", "bone", glow, 2.4)
    cage = r.joint("cage", core, (0, 0, 0))
    for x, y in ((-5, -5), (5, -5), (-5, 5), (5, 5)):
        box("bar", "iron", cage, (1.3, 1.3, 22), (x, y, 0))
    box("ringT", "iron", cage, (12.5, 12.5, 1.6), (0, 0, 11))
    box("ringB", "iron", cage, (12.5, 12.5, 1.6), (0, 0, -11))
    cone("cap", "iron", cage, 8.5, 7, (0, 0, 11.8), verts=8)
    sphere("knob", "gold", cage, 1.4, (0, 0, 19))
    box("hookr", "iron", cage, (1.2, 1.2, 4), (0, 0, 21))
    for i, (x, y) in enumerate(((-3, -3), (3, 2), (-1, 4))):
        tj = r.joint("tendril%d" % i, cage, (x, y, -12))
        box("tendril%d" % i, "cloth_dark", tj, (1.8, 1.0, 12), (0, 0, -6))
        tj2 = r.joint("tendril%db" % i, tj, (0, 0, -12))
        box("tendril%db" % i, "glow_teal", tj2, (1.2, 0.8, 8), (0, 0, -4))


def wisp_pose(state, k, n):
    t = k / max(1, n - 1)
    w = math.sin(t * math.pi * 2)
    base = {"tendril0": 15 * w, "tendril1": -12 * w, "tendril2": 8 * w, "tendril0b": 20 * w, "tendril1b": -18 * w, "tendril2b": 14 * w, "glow": {"scale": 1.0}}
    if state == "idle":
        base.update({"core": {"rot": 3 * w, "loc": (0, 0, 38 + 2 * w)}})
    elif state == "windup":
        base.update({"glow": {"scale": lerp(1.0, 1.7, t)}, "core": {"rot": -8 * t, "loc": (-1.5 * t, 0, 38 + 1.5 * t)}})
    elif state == "attack":
        base.update({"glow": {"scale": lerp(2.0, 1.1, t)}, "core": {"rot": 12 * (1 - t), "loc": (3 * (1 - t), 0, 38)}})
    elif state == "stagger":
        base.update({"core": {"rot": -30 - 10 * t, "loc": (-4, 0, 36)}, "glow": {"scale": 0.8}})
    elif state == "death":
        base.update({"core": {"rot": lerp(-30, -80, t), "loc": (-3, 0, 38 - 12 * t)}, "glow": {"scale": lerp(0.7, 0.15, t)}})
    return base


def brute(rig):
    r = rig
    hips = r.joint("hips", r.root, (0, 0, 25))
    spine = r.joint("spine", hips, (0, 0, 1))
    neck = r.joint("neck", spine, (1, 0, 23))
    for side, y in (("F", -6), ("B", 6)):
        t = r.joint("thigh" + side, hips, (0, y, 0))
        s = r.joint("shin" + side, t, (0, 0, -12))
        capsule("thigh" + side, "cloth_dark", t, 5.0, 12)
        capsule("shin" + side, "iron", s, 4.6, 11)
        box("boot" + side, "iron", s, (12, 8, 4), (3, 0, -12), bevel=0.8)
    box("cuirass", "iron", spine, (22, 17, 22), (0, 0, 12), bevel=1.6)
    box("plate", "steel", spine, (6, 12, 12), (11.5, 0, 12), bevel=0.8)
    box("belt", "cloth_dark", spine, (24, 19, 3), (0, 0, 1.5))
    box("buckle", "gold", spine, (3, 4, 3), (12, 0, 1.5))
    for y in (-11, 11):
        sphere("pauldron", "iron", spine, 6.5, (1, y, 23), (1.1, 1.0, 0.85))
    sphere("head", "void", neck, 5, (1, 0, 3.5))
    box("helm", "iron", neck, (11, 11, 9), (0.5, 0, 5), bevel=1.0)
    box("visor", "eye", neck, (2, 7, 1.4), (6.2, 0, 4.5))
    box("crest", "gold", neck, (8, 2, 4), (-1, 0, 10.5))
    # shield hangs from the spine so it stays squarely in front
    box("shield", "steel", spine, (4, 22, 30), (15, -2, 6), bevel=1.0)
    box("shieldrim", "iron", spine, (4.5, 24, 3), (15, -2, 20.5))
    box("shieldrim2", "iron", spine, (4.5, 24, 3), (15, -2, -8.5))
    box("emblem", "gold", spine, (1.2, 7, 7), (17.4, -2, 6), rot=(rad(45), 0, 0))
    for side, y in (("F", -13), ("B", 13)):
        sh = r.joint("shoulder" + side, spine, (2, y, 21))
        capsule("arm" + side, "iron", sh, 4.0, 15)
        sphere("fist" + side, "cloth_dark", sh, 4.2, (0, 0, -15.5))
    wrist = r.joint("wrist", r.j["shoulderB"], (0, 0.5, -16))
    box("haft", "cloth_dark", wrist, (2.2, 2.2, 26), (0, 0, 9))
    sphere("macehead", "iron", wrist, 6, (0, 0, 24))
    for i in range(6):
        a = i * math.pi / 3
        cone("spike%d" % i, "steel", wrist, 1.8, 4.5, (math.cos(a) * 5.5, 0, 24 + math.sin(a) * 5.5), rot=(0, -a + math.pi * 0.5, 0), verts=6)


def brute_pose(state, k, n):
    t = k / max(1, n - 1)
    base = {"spine": 4, "thighF": 6, "shinF": -6, "thighB": -6, "shinB": 6, "shoulderF": 10, "shoulderB": -25, "wrist": 0}
    if state == "idle":
        w = math.sin(t * math.pi * 2)
        base.update({"spine": 4 + 1.5 * w, "shoulderB": -25 + 3 * w, "root": {"rot": 0, "loc": (0, 0, -0.5 * (1 - math.cos(t * math.pi * 2)) * 0.5)}})
    elif state == "windup":
        base.update({"spine": lerp(0, -14, t), "shoulderB": lerp(-25, -150, t), "wrist": lerp(0, 30, t), "root": {"rot": 0, "loc": (-2 * t, 0, 0)}})
    elif state == "attack":
        base.update({"spine": lerp(10, 24, t), "shoulderB": lerp(-40, 95, t), "wrist": lerp(30, -20, t), "thighF": 30, "shinF": -15, "thighB": -25, "shinB": 20, "root": {"rot": 0, "loc": (lerp(2, 7, t), 0, 0)}})
    elif state == "stagger":
        base.update({"spine": -18 - 6 * t, "shoulderF": -30, "shoulderB": -60, "root": {"rot": 0, "loc": (-3 - 2 * t, 0, 0)}})
    elif state == "death":
        base.update({"spine": -6, "shoulderF": -30, "shoulderB": -70})
        base.update(fall(k, n))
    return base


def bomber(rig):
    r = rig
    body = r.joint("body", r.root, (0, 0, 16))
    sphere("shell", "iron", body, 14, (0, 0, 2))
    box("seam", "cloth_dark", body, (0.8, 29, 1.4), (0, 0, 2), rot=(0, rad(90), 0))
    for i, (z, rot) in enumerate(((6, 20), (-2, -30), (10, -60), (-7, 45))):
        box("crack%d" % i, "glow_orange", body, (1.4, 1.2, 7), (12.6, -3 + i * 2, 2 + z * 0.6), rot=(rad(rot), rad(20), 0))
    sphere("eyeF", "eye", body, 1.9, (11.5, -4.5, 7))
    sphere("eyeB", "eye", body, 1.6, (9.5, -8, 8))
    box("browF", "cloth_dark", body, (3, 5, 1.2), (11.8, -4.5, 9.2), rot=(0, 0, rad(-25)))
    for i in range(4):
        cone("tooth%d" % i, "bone", body, 0.9, 2.2, (13.6, -6 + i * 4, -1), rot=(math.pi, 0, 0), verts=6)
    box("mouth", "void", body, (1.6, 15, 1.6), (13.9, 0, -0.5))
    fuse = r.joint("fuse", body, (-2, 0, 15))
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=1.3, depth=9)
    fz = finish(bpy.context.active_object, "fuse", "cloth_dark", fuse, (0, 0, 4.5), (0, rad(-15), 0))
    fl = r.joint("flame", fuse, (1.2, 0, 9))
    cone("fl0", "flame", fl, 2.4, 6, (0, 0, 0), verts=8)
    cone("fl1", "glow_orange", fl, 1.3, 4, (0.2, -0.3, 0.5), verts=8)
    for side, y in (("F", -6), ("B", 6)):
        lj = r.joint("leg" + side, body, (0, y, -11))
        capsule("leg" + side, "cloth_dark", lj, 2.4, 6)
        box("foot" + side, "iron", lj, (7, 4, 2.4), (2, 0, -6.4))
        aj = r.joint("arm" + side, body, (4, y * 1.9, 0))
        capsule("arm" + side, "cloth_dark", aj, 1.8, 6)
        sphere("hand" + side, "iron", aj, 2.0, (0, 0, -6.4))


def bomber_pose(state, k, n):
    t = k / max(1, n - 1)
    w = math.sin(t * math.pi * 2)
    base = {"legF": 20 * w, "legB": -20 * w, "armF": 20, "armB": 15, "flame": {"scale": 1.0}}
    if state == "idle":
        base.update({"body": {"rot": 4 * w, "loc": (0, 0, 16 + abs(w) * 1.2)}})
    elif state == "windup":
        base.update({"body": {"rot": 6 * (1 if k % 2 else -1), "loc": (1.5 * (1 if k % 2 else -1), 0, 16), "scale": 1.0 + 0.05 * t}, "flame": {"scale": lerp(1.2, 2.2, t)}, "armF": 60, "armB": 60})
    elif state == "attack":
        base.update({"body": {"rot": 0, "loc": (0, 0, 16 + 2 * t), "scale": lerp(1.1, 1.35, t)}, "flame": {"scale": lerp(2.2, 3.0, t)}, "armF": 90, "armB": 90})
    elif state == "stagger":
        base.update({"body": {"rot": -25 - 10 * t, "loc": (-3, 0, 16)}, "armF": -40, "armB": -40})
    elif state == "death":
        base.update({"body": {"rot": 0, "loc": (0, 0, 16 + 4 * t), "scale": (1.4, 1.7, 0.35)[k] if k < 3 else 0.35}, "flame": {"scale": 3.0 if k < 2 else 0.2}})
    return base


def warden(rig, phase2=False):
    r = rig
    hips = r.joint("hips", r.root, (0, 0, 40))
    spine = r.joint("spine", hips, (0, 0, 1))
    neck = r.joint("neck", spine, (1.5, 0, 34))
    for side, y in (("F", -8), ("B", 8)):
        t = r.joint("thigh" + side, hips, (0, y, 0))
        s = r.joint("shin" + side, t, (0, 0, -19))
        capsule("thigh" + side, "iron", t, 6.6, 19)
        box("tasset" + side, "steel", t, (10, 8, 12), (2, 0, -6), bevel=1.0)
        capsule("shin" + side, "iron", s, 5.8, 18)
        box("sabaton" + side, "steel", s, (16, 10, 5), (4, 0, -19), bevel=1.0)
    box("cuirass", "iron", spine, (30, 22, 32), (0, 0, 17), bevel=2.0)
    box("plate", "steel", spine, (8, 16, 20), (15, 0, 18), bevel=1.2)
    box("trimT", "gold", spine, (32, 24, 2.2), (0, 0, 33))
    box("trimB", "gold", spine, (32, 24, 2.2), (0, 0, 1.5))
    box("sigil", "glow_orange", spine, (2.5, 7, 8), (18.6, 0, 20), rot=(rad(45), 0, 0))
    for y in (-15, 15):
        sphere("pauldron", "iron", spine, 9.5, (1, y, 33), (1.15, 1.0, 0.8))
        torus("prim", "gold", spine, 9.0, 1.2, (1, y, 33), rot=(rad(90), 0, 0))
    box("helm", "iron", neck, (15, 15, 17), (0.5, 0, 8), bevel=1.6)
    cone("helmtop", "iron", neck, 8, 7, (0.5, 0, 16.5), verts=8)
    box("visor", "eye", neck, (2.2, 10, 2), (8.3, 0, 8.5))
    box("faceplate", "steel", neck, (3, 9, 8), (8.2, 0, 3.5), bevel=0.6)
    for y, rot in ((-6.5, 35), (6.5, 35)):
        cone("horn", "bone", neck, 2.6, 13, (-1, y, 14), rot=(rad(-40) if y < 0 else rad(40), rad(-rot), 0), verts=8)
    # cape
    c0 = r.joint("cape0", spine, (-12, 0, 32))
    box("capeM0", "cloak_red", c0, (2.5, 22, 20), (0, 0, -10))
    c1 = r.joint("cape1", c0, (0, 0, -20))
    box("capeM1", "cloak_red", c1, (2.5, 20, 20), (0, 0, -10))
    c2 = r.joint("cape2", c1, (0, 0, -20))
    box("capeM2", "cloak_red", c2, (2.5, 18, 16), (0, 0, -8))
    for side, y in (("F", -18), ("B", 18)):
        sh = r.joint("shoulder" + side, spine, (2, y, 30))
        capsule("arm" + side, "iron", sh, 5.2, 22)
        sphere("gauntlet" + side, "steel", sh, 5.8, (0, 0, -23))
    wrist = r.joint("wrist", r.j["shoulderF"], (0, -1, -24))
    box("grip", "cloth_dark", wrist, (2.6, 2.6, 8), (0, 0, 0))
    box("guard", "gold", wrist, (3, 3, 16), (0, 0, 4.5), rot=(rad(90), 0, 0))
    box("pommel", "gold", wrist, (4, 4, 3), (0, 0, -5))
    box("blade", "steel", wrist, (5.0, 1.4, 54), (0, 0, 32))
    box("fuller", "cloth_dark", wrist, (1.2, 1.6, 44), (0, 0, 30))
    box("tip", "steel", wrist, (3.0, 1.4, 6), (0, 0, 61))
    if phase2:
        for i, (x, y, z) in enumerate(((-4, -15, 40), (6, -15, 41), (-3, 15, 40), (7, 15, 41), (-6, 0, 58), (4, 0, 60))):
            cone("p2flame%d" % i, "flame", spine if z < 50 else neck, 3.0, 9 + (i % 2) * 3, (x, y, z) if z < 50 else (x, y, z - 42), verts=8)
        box("p2crack", "glow_orange", spine, (1.6, 26, 3), (15.5, 0, 26))


def warden_pose(state, k, n):
    t = k / max(1, n - 1)
    base = {"spine": 3, "thighF": 6, "shinF": -6, "thighB": -6, "shinB": 6, "shoulderF": 28, "wrist": 200, "shoulderB": -12, "cape0": 8, "cape1": 6, "cape2": 5}
    if state == "idle":
        w = math.sin(t * math.pi * 2)
        base.update({"spine": 3 + 1.2 * w, "shoulderF": 28 + 2 * w, "root": {"rot": 0, "loc": (0, 0, -0.4 * (1 - math.cos(t * math.pi * 2)) * 0.5)}})
    elif state == "windup":
        base.update({"spine": lerp(0, -12, t), "shoulderF": lerp(28, -120, t), "wrist": lerp(200, 190, t), "shoulderB": lerp(-12, 40, t), "cape0": 20, "cape1": 12, "cape2": 8, "root": {"rot": 0, "loc": (-3 * t, 0, 0)}})
    elif state == "attack":
        base.update({"spine": lerp(12, 26, t), "shoulderF": lerp(-20, 135, t), "wrist": 190, "thighF": 36, "shinF": -18, "thighB": -30, "shinB": 24, "cape0": 40, "cape1": 25, "cape2": 12, "root": {"rot": 0, "loc": (lerp(2, 8, t), 0, 0)}})
    elif state == "stagger":
        base.update({"spine": -16 - 6 * t, "shoulderF": -20, "shoulderB": -40, "root": {"rot": 0, "loc": (-3 - 2 * t, 0, 0)}})
    elif state == "death":
        base.update({"spine": -8, "shoulderF": -40, "shoulderB": -60, "cape0": -20, "cape1": -10, "cape2": -5})
        base.update(fall(k, n))
    return base


CREATURES = {
    # name: (frame_w, frame_h, builder, poser)
    "stalker": (72, 64, stalker, stalker_pose),
    "hopper": (72, 56, hopper, hopper_pose),
    "wisp": (64, 64, wisp, wisp_pose),
    "brute": (104, 80, brute, brute_pose),
    "bomber": (64, 56, bomber, bomber_pose),
    "warden": (140, 120, lambda r: warden(r, False), warden_pose),
    "warden_phase2": (140, 120, lambda r: warden(r, True), warden_pose),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = argv[0] if argv else "/tmp/graveflame-creature-render"
    only = argv[1].split(",") if len(argv) > 1 else None
    os.makedirs(out_dir, exist_ok=True)
    meta = {}
    for name, (w, h, builder, poser) in CREATURES.items():
        if only and name not in only:
            continue
        sc = scene(w, h)
        rig = Rig()
        builder(rig)
        meta[name] = {"frame_w": w, "frame_h": h, "feet_y": h - 2, "states": {}}
        for id_pass in (False, True):
            set_id_mode(id_pass)
            if id_pass:
                sc.world.node_tree.nodes.get("Background").inputs[1].default_value = 0.0
                sc.eevee.taa_render_samples = 1
            for state, count in STATES.items():
                meta[name]["states"][state] = count
                for k in range(count):
                    rig.reset()
                    rig.apply(poser(state, k, count))
                    sc.render.filepath = os.path.join(out_dir, "%s_%s_%d%s.png" % (name, state, k, "_id" if id_pass else ""))
                    bpy.ops.render.render(write_still=True)
    with open(os.path.join(out_dir, "creatures.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print("CREATURE_RENDER_DONE", len(meta))


if __name__ == "__main__":
    main()
