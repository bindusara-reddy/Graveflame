"""Model and render the Graveflame environment art in Blender: stone tiles for
platforms and walls, and three seamless parallax backdrop layers.

Run:  blender -b --python tools/render_environment.py -- OUT_DIR
Writes OUT_DIR/<name>.png and <name>_id.png (lit + material-ID) at 8x the art
resolution, plus env.json describing each image. tests/env_bake.gd turns these
into palette-quantized pixel art in assets/env.

Units are art pixels (1 art px = 2 world px in game). The camera looks along +Y;
X is horizontal, Z is up. Every image is authored to tile horizontally with a
period equal to its width (geometry is instanced in the neighbouring periods).
"""
import json
import math
import os
import random
import sys

import bpy

SUPER = 8
TILE = 32

COL = {
    "stone": (0.36, 0.40, 0.52),
    "coping": (0.48, 0.52, 0.64),
    "mortar": (0.09, 0.10, 0.15),
    "iron": (0.14, 0.14, 0.18),
    "wood": (0.30, 0.19, 0.11),
    "cloth": (0.45, 0.09, 0.15),
    "glass": (0.16, 0.55, 0.62),
    "window": (1.0, 0.62, 0.25),
    "flame": (1.0, 0.45, 0.10),
    "spire": (0.07, 0.07, 0.12),
    "moss": (0.18, 0.40, 0.26),
    "gold": (0.94, 0.70, 0.35),
}
ID_COLORS = {
    "stone": (1, 0, 0), "coping": (0, 1, 0), "mortar": (0, 0, 1), "iron": (1, 1, 0), "wood": (1, 0, 1),
    "cloth": (0, 1, 1), "glass": (0.5, 0, 0), "window": (0, 0.5, 0), "flame": (0, 0, 0.5), "spire": (0.5, 0.5, 0),
    "moss": (0.5, 0, 0.5), "gold": (0, 0.5, 0.5),
}


def rad(d):
    return math.radians(d)


def mat(name, color, rough=0.9, emit=0.0, noise=0.0, per_object=0.0, bump=0.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if emit > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    src = None
    if per_object > 0.0:
        info = nt.nodes.new("ShaderNodeObjectInfo")
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs[0].default_value = per_object
        mix.inputs[6].default_value = (*color, 1.0)
        mix.inputs[7].default_value = (color[0] * 0.7, color[1] * 0.7, color[2] * 0.75, 1.0)
        nt.links.new(info.outputs["Random"], mix.inputs[0])
        src = mix.outputs[2]
    if noise > 0.0:
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = 3.0
        tex.inputs["Detail"].default_value = 5.0
        tex.inputs["Roughness"].default_value = 0.6
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.3
        ramp.color_ramp.elements[0].color = (1.0 - noise, 1.0 - noise, 1.0 - noise, 1.0)
        ramp.color_ramp.elements[1].position = 0.75
        ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
        nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs[0].default_value = 1.0
        if src is not None:
            nt.links.new(src, mul.inputs[6])
        else:
            mul.inputs[6].default_value = (*color, 1.0)
        nt.links.new(ramp.outputs["Color"], mul.inputs[7])
        src = mul.outputs[2]
        if bump > 0.0:
            b = nt.nodes.new("ShaderNodeBump")
            b.inputs["Strength"].default_value = bump
            nt.links.new(tex.outputs["Fac"], b.inputs["Height"])
            nt.links.new(b.outputs["Normal"], bsdf.inputs["Normal"])
    if src is not None:
        nt.links.new(src, bsdf.inputs["Base Color"])
    return m


def materials():
    return {
        "stone": mat("stone", COL["stone"], noise=0.35, per_object=1.0, bump=0.35),
        "coping": mat("coping", COL["coping"], noise=0.25, per_object=0.6, bump=0.25),
        "mortar": mat("mortar", COL["mortar"], noise=0.3),
        "iron": mat("iron", COL["iron"], rough=0.6),
        "wood": mat("wood", COL["wood"], noise=0.3, per_object=0.5),
        "cloth": mat("cloth", COL["cloth"], noise=0.2),
        "glass": mat("glass", COL["glass"], emit=2.5),
        "window": mat("window", COL["window"], emit=6.0),
        "flame": mat("flame", COL["flame"], emit=8.0),
        "spire": mat("spire", COL["spire"], noise=0.15),
        "moss": mat("moss", COL["moss"], noise=0.4),
        "gold": mat("gold", COL["gold"], rough=0.45),
    }


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


def setup(width, height, key_dir=(55, -20, -35), ambient=0.5, sun=3.6):
    """Camera framing x in [-w/2, w/2], z in [0, h]."""
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
    bg.inputs[0].default_value = (0.30, 0.36, 0.55, 1.0)
    bg.inputs[1].default_value = ambient
    sc.world = world
    cam = bpy.data.cameras.new("Cam")
    cam.type = "ORTHO"
    cam.sensor_fit = "HORIZONTAL"
    cam.ortho_scale = width
    cam.clip_end = 1000.0
    co = bpy.data.objects.new("Cam", cam)
    sc.collection.objects.link(co)
    co.location = (0.0, -300.0, height * 0.5)
    co.rotation_euler = (rad(90), 0, 0)
    sc.camera = co
    key = bpy.data.lights.new("Key", "SUN")
    key.energy = sun
    key.color = (1.0, 0.92, 0.82)
    ko = bpy.data.objects.new("Key", key)
    sc.collection.objects.link(ko)
    ko.rotation_euler = tuple(rad(a) for a in key_dir)
    fill = bpy.data.lights.new("Fill", "SUN")
    fill.energy = 1.0
    fill.color = (0.55, 0.65, 1.0)
    fo = bpy.data.objects.new("Fill", fill)
    sc.collection.objects.link(fo)
    fo.rotation_euler = (rad(70), rad(20), rad(160))
    return sc


def box(name, material, size, loc, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.location = loc
    o.rotation_euler = rot
    o.data.materials.append(material)
    if bevel > 0.0:
        bpy.ops.object.transform_apply(scale=True)
        mod = o.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        for p in o.data.polygons:
            p.use_smooth = False
    return o


def point_light(loc, energy=600.0, color=(1.0, 0.7, 0.4), radius=3.0):
    l = bpy.data.lights.new("P", "POINT")
    l.energy = energy
    l.color = color
    l.shadow_soft_size = radius
    o = bpy.data.objects.new("P", l)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    return o


ROW_PATTERNS = [
    [16, 16], [12, 20], [8, 16, 8], [20, 12], [16, 8, 8], [12, 12, 8],
]


def brick_rows(m, x0, x1, z0, rows, row_h, period, seed, depth_y=0.0, cut_left=None, cut_right=None, offset_parity=0):
    """Rows of bevelled bricks from z0 upward, repeating every `period` in x so the
    tile wraps. cut_left/right drop bricks whose centre is past the cut."""
    rnd = random.Random(seed)
    for r in range(rows):
        pattern = ROW_PATTERNS[(seed + r) % len(ROW_PATTERNS)]
        off = 8 if (r + offset_parity) % 2 else 0
        z = z0 + r * row_h
        for copy in (-1, 0, 1):
            x = x0 + off + copy * period
            for w in pattern:
                cx = x + w * 0.5
                if x0 - 20 < cx < x1 + 20:
                    keep = True
                    if cut_left is not None and cx < cut_left:
                        keep = rnd.random() < 0.25
                    if cut_right is not None and cx > cut_right:
                        keep = rnd.random() < 0.25
                    if keep:
                        jitter = rnd.uniform(-0.25, 0.25)
                        box("brick", m, (w - 1.2, 4.0, row_h - 1.2), (cx, 2.0 + jitter, z + row_h * 0.5), bevel=0.55)
                x += w


def mortar(m, x0, x1, z0, z1, depth_y=4.6):
    box("mortar", m, (x1 - x0, 1.0, z1 - z0), ((x0 + x1) * 0.5, depth_y, (z0 + z1) * 0.5))


def coping(m, x0, x1, z, period, seed, cut_left=None, cut_right=None):
    """Top course: two long dressed stones per tile with a proud lip."""
    rnd = random.Random(seed)
    for copy in (-1, 0, 1):
        for i, (bx, w) in enumerate(((x0, 14), (x0 + 14, 18))):
            cx = bx + copy * period + w * 0.5
            if cut_left is not None and cx < cut_left:
                continue
            if cut_right is not None and cx > cut_right:
                continue
            box("cope", m, (w - 0.8, 5.5, 6.4), (cx, 1.2, z + 3.4), bevel=0.7)


# --- tiles ---------------------------------------------------------------------

def tile_fill(ms):
    mortar(ms["mortar"], -20, 20, -4, 36)
    brick_rows(ms["stone"], -16, 16, 0, 4, 8, 32, seed=3)


def tile_top(ms):
    mortar(ms["mortar"], -20, 20, -4, 24)
    brick_rows(ms["stone"], -16, 16, 0, 3, 8, 32, seed=5, offset_parity=1)
    coping(ms["coping"], -16, 16, 24.0, 32, seed=5)


def tile_top_l(ms):
    mortar(ms["mortar"], -6, 20, -4, 24)
    brick_rows(ms["stone"], -16, 16, 0, 3, 8, 32, seed=7, offset_parity=1, cut_left=-6)
    coping(ms["coping"], -16, 16, 24.0, 32, seed=7, cut_left=-8)


def tile_top_r(ms):
    mortar(ms["mortar"], -20, 6, -4, 24)
    brick_rows(ms["stone"], -16, 16, 0, 3, 8, 32, seed=9, offset_parity=1, cut_right=6)
    coping(ms["coping"], -16, 16, 24.0, 32, seed=9, cut_right=8)


def tile_side_l(ms):
    mortar(ms["mortar"], -6, 20, -4, 36)
    brick_rows(ms["stone"], -16, 16, 0, 4, 8, 32, seed=11, cut_left=-6)


def tile_side_r(ms):
    mortar(ms["mortar"], -20, 6, -4, 36)
    brick_rows(ms["stone"], -16, 16, 0, 4, 8, 32, seed=13, cut_right=6)


def tile_ledge(ms):
    # 32 x 16: coping over one brick course with an iron strap underneath.
    mortar(ms["mortar"], -20, 20, 0, 10)
    brick_rows(ms["stone"], -16, 16, 2, 1, 8, 32, seed=15)
    coping(ms["coping"], -16, 16, 10.0, 32, seed=15)
    box("strap", ms["iron"], (32, 1.0, 1.6), (0, 0.6, 1.2))


def tile_pillar(ms):
    # 32 x 32 column of two dressed drums, seamless vertically.
    for z in (0, 16):
        box("drum", ms["stone"], (22, 8, 15.2), (0, 0, z + 8), bevel=0.8)
    box("groove", ms["mortar"], (24, 1, 1.4), (0, -3.0, 16))


def tile_pillar_cap(ms):
    box("cap", ms["coping"], (30, 9, 6), (0, 0, 13), bevel=0.8)
    box("neck", ms["stone"], (22, 8, 10), (0, 0, 5), bevel=0.6)


# --- backdrop layers ---------------------------------------------------------------

LAYER_W, LAYER_H = 320, 200


def layer_far(ms):
    """Distant towers: silhouettes with a few lit slit windows. Period 160."""
    rnd = random.Random(21)
    for copy in (-1, 0, 1):
        base = copy * 160
        for k, (x, w, h) in enumerate(((-60, 26, 150), (-18, 34, 190), (30, 22, 130), (66, 30, 170))):
            cx = base + x
            box("tower", ms["spire"], (w, 10, h), (cx, 40, h * 0.5))
            bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=w * 0.75, radius2=0.0, depth=w * 1.2)
            cone = bpy.context.active_object
            cone.location = (cx, 40, h + w * 0.6)
            cone.rotation_euler = (0, 0, rad(45))
            cone.data.materials.append(ms["spire"])
            for j in range(3):
                if rnd.random() < 0.7:
                    box("win", ms["window"], (2.0, 1.0, 5.0), (cx + rnd.uniform(-w * 0.3, w * 0.3), 34.5, 30 + j * 40 + rnd.uniform(-8, 8)))
        # low rampart connecting the towers
        box("rampart", ms["spire"], (160, 10, 36), (base, 42, 18))


def layer_mid(ms):
    """Arcade: pillars every 80 with stone arches; alternate bays glazed. Period 320."""
    for copy in (-1, 0, 1):
        base = copy * 320
        # entablature
        box("entab", ms["stone"], (320, 8, 12), (base, 8, 186), bevel=0.8)
        box("course", ms["coping"], (320, 9, 3), (base, 7.5, 193))
        for i in range(4):
            px = base - 160 + i * 80
            box("pillar", ms["stone"], (14, 8, 172), (px, 8, 86), bevel=0.8)
            box("cap", ms["coping"], (18, 9, 4), (px, 7.5, 174))
            box("plinth", ms["coping"], (18, 9, 6), (px, 7.5, 3))
            # arch: voussoirs along a semicircle between this pillar and the next
            cx = px + 40
            r = 33.0
            for j in range(11):
                a = math.pi * j / 10.0
                vx = cx + math.cos(a) * r
                vz = 140 + math.sin(a) * r
                box("vouss", ms["coping"], (7.5, 8, 5.5), (vx, 8, vz), rot=(0, -a + math.pi * 0.5, 0), bevel=0.4)
            if i % 2 == 1:
                # glazed bay: wall behind, rose window, lead lines
                box("bay", ms["mortar"], (66, 4, 172), (cx, 12, 86))
                box("bayface", ms["stone"], (66, 1.5, 172), (cx, 10.5, 86))
                bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=17, depth=1.0)
                disc = bpy.context.active_object
                disc.location = (cx, 9.6, 118)
                disc.rotation_euler = (rad(90), 0, 0)
                disc.data.materials.append(ms["glass"])
                for j in range(3):
                    a = j * math.pi / 3.0
                    box("lead", ms["iron"], (1.2, 1.0, 34), (cx, 9.0, 118), rot=(0, a, 0))
                bpy.ops.mesh.primitive_torus_add(major_segments=24, minor_segments=6, major_radius=17.5, minor_radius=1.3)
                ring = bpy.context.active_object
                ring.location = (cx, 9.0, 118)
                ring.rotation_euler = (rad(90), 0, 0)
                ring.data.materials.append(ms["iron"])
            else:
                # open bay: a banner hangs from the entablature
                box("rod", ms["iron"], (22, 1.2, 1.2), (cx, 6, 178))
                box("banner", ms["cloth"], (18, 0.8, 70), (cx, 6, 143))
                bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=9.5, radius2=0.0, depth=14)
                tail = bpy.context.active_object
                tail.location = (cx, 6, 101)
                tail.rotation_euler = (math.pi, 0, rad(45))
                tail.data.materials.append(ms["cloth"])
                box("sigil", ms["gold"], (6, 0.6, 6), (cx, 5.4, 150), rot=(0, rad(45), 0))
        point_light((base - 120, -20, 150), 900, (0.3, 0.7, 0.8), 6)
        point_light((base + 40, -20, 150), 900, (0.3, 0.7, 0.8), 6)


def layer_near(ms):
    """Buttresses with torch sconces, period 160 (world 320); pilaster on the seam."""
    for copy in (-1, 0, 1):
        base = copy * 160
        for px in (base - 80, base + 80):
            # pilaster split across the seam at x = +-80 (period edge) -> seamless
            box("pilaster", ms["stone"], (22, 10, 200), (px, 0, 100), bevel=0.9)
            for z in range(0, 200, 25):
                box("joint", ms["mortar"], (24, 1.0, 1.2), (px, -5.2, z))
            box("capital", ms["coping"], (30, 12, 7), (px, 0, 196))
            box("plinth", ms["coping"], (28, 12, 20), (px, 0, 10))
            # sconce: bracket, bowl, flame (bowl at z 130 = world y 400)
            box("bracket", ms["iron"], (3, 3, 11), (px, -6, 124))
            box("bowl", ms["iron"], (10, 6, 4), (px, -6, 130))
            bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=3.5, radius2=0.4, depth=12)
            fl = bpy.context.active_object
            fl.location = (px, -6, 138)
            fl.data.materials.append(ms["flame"])
            point_light((px, -14, 136), 1500, (1.0, 0.6, 0.3), 5)
        # recessed relief arch between the pilasters
        mid = base
        for j in range(13):
            a = math.pi * j / 12.0
            box("relief", ms["stone"], (9, 3, 6), (mid + math.cos(a) * 58, 3.5, 115 + math.sin(a) * 58), rot=(0, -a + math.pi * 0.5, 0), bevel=0.5)
        box("jambL", ms["stone"], (6, 3, 100), (mid - 58, 3.5, 65), bevel=0.5)
        box("jambR", ms["stone"], (6, 3, 100), (mid + 58, 3.5, 65), bevel=0.5)
        # moss clumps at the plinths
        for px in (base - 80, base + 80):
            for dx in (-16, 15):
                bpy.ops.mesh.primitive_uv_sphere_add(radius=4.5, segments=12, ring_count=6)
                s = bpy.context.active_object
                s.location = (px + dx, -6, 21)
                s.scale = (1.0, 0.6, 0.55)
                s.data.materials.append(ms["moss"])


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
            emi.inputs["Color"].default_value = (*ID_COLORS.get(m.name, (0, 0, 1)), 1.0)
            emi.inputs["Strength"].default_value = 1.0
        for link in list(nt.links):
            if link.to_node == out and link.to_socket.name == "Surface":
                nt.links.remove(link)
        nt.links.new((emi if on else bsdf).outputs[0], out.inputs["Surface"])


JOBS = {
    # name: (width, height, builder, key_dir)
    "tile_fill": (TILE, TILE, tile_fill, (58, -15, -30)),
    "tile_top": (TILE, TILE, tile_top, (58, -15, -30)),
    "tile_top_l": (TILE, TILE, tile_top_l, (58, -15, -30)),
    "tile_top_r": (TILE, TILE, tile_top_r, (58, -15, -30)),
    "tile_side_l": (TILE, TILE, tile_side_l, (58, -15, -30)),
    "tile_side_r": (TILE, TILE, tile_side_r, (58, -15, -30)),
    "tile_ledge": (TILE, 16, tile_ledge, (58, -15, -30)),
    "tile_pillar": (TILE, TILE, tile_pillar, (58, -15, -30)),
    "tile_pillar_cap": (TILE, 16, tile_pillar_cap, (58, -15, -30)),
    "layer_far": (LAYER_W, LAYER_H, layer_far, (70, 0, 0)),
    "layer_mid": (LAYER_W, LAYER_H, layer_mid, (55, -10, -25)),
    "layer_near": (LAYER_W, LAYER_H, layer_near, (55, -10, -25)),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = argv[0] if argv else "/tmp/graveflame-env-render"
    os.makedirs(out_dir, exist_ok=True)
    only = argv[1].split(",") if len(argv) > 1 else None
    meta = {}
    for name, (w, h, builder, key_dir) in JOBS.items():
        if only and name not in only:
            continue
        clear_scene()
        sc = setup(w, h, key_dir=key_dir, ambient=0.45 if name.startswith("tile") else 0.35, sun=3.4 if name.startswith("tile") else 2.6)
        ms = materials()
        builder(ms)
        for id_pass in (False, True):
            set_id_mode(id_pass)
            if id_pass:
                sc.world.node_tree.nodes.get("Background").inputs[1].default_value = 0.0
                sc.eevee.taa_render_samples = 1
                for o in list(bpy.data.objects):
                    if o.type == "LIGHT" and o.data.type == "POINT":
                        bpy.data.objects.remove(o)
            sc.render.filepath = os.path.join(out_dir, name + ("_id" if id_pass else "") + ".png")
            bpy.ops.render.render(write_still=True)
        meta[name] = {"w": w, "h": h}
    with open(os.path.join(out_dir, "env.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print("ENV_RENDER_DONE", len(meta))


if __name__ == "__main__":
    main()
