"""SGODOT-319 shared hall shell, adapted from the editable Mine Hut foundation.

Blender --background --factory-startup --python <absolute path to this file>.
Godot metres / Y up / front +Z. A fixed atlas contract reserves furniture colors
for SGODOT-324; shell-only AO never includes hotel furniture or direct light.
"""
from pathlib import Path
import hashlib
import json
import math
import re
import struct
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scene_room_pipeline as p

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / "assets/rooms/_shared/shell_hall"
SOURCE = ROOT / "tools/art/source/shell_hall"
QA = ROOT / "output/poi-hall-319"
FLOOR_Y = 0.08
WALL_H = 3.7
WINDOW_Z = [-1.78, 1.78]
HOLE_W, HOLE_H, SILL_Y = 1.24, 2.04, 1.20
COLORS = {
    "parquet": "CB8655", "plaster": "E7CBB0", "panel": "652E18",
    "cornice": "672F1A", "skirting": "723A20", "window": "BE7839",
    "wood_dark": "551B0A", "wood_mid": "7B4023", "oak": "BE8747",
    "oak_light": "D59A53", "oak_edge": "AF7338", "brass": "C0924A",
    "linen": "EFE4CB", "sky": "D8E7E4", "sage": "567247",
    "iron": "494137", "porcelain": "F2E7D4", "sage_dark": "2B4726",
    "linen_green": "9FAB78", "petal": "FFF2D4", "print_portrait": "EFE4CB",
    "print_landscape": "EFE4CB", "glass": "EEF4EB", "stone": "C6B6A1",
    "plaster_solid": "E7CBB0", "wainscot_solid": "652E18", "cornice_solid": "672F1A",
    "window_solid": "BE7839", "floor_solid": "CB8655", "soil": "51402C",
    "leaf": "56873D", "leaf_light": "82AA4F", "leaf_dark": "365B2A",
    "terra": "BE754D", "terra_light": "D9905D", "leather": "964B25",
    "cloth_green": "2B4726", "accent_gold": "CFAB66",
}
REGIONS = {
    "parquet": [0, 0, 1024, 1024], "plaster": [1024, 0, 1024, 512],
    "panel": [1024, 512, 512, 512], "cornice": [1536, 512, 256, 256],
    "skirting": [1792, 512, 256, 256], "window": [1536, 768, 512, 256],
}
SWATCHES = list(COLORS)[6:]
for index, name in enumerate(SWATCHES):
    REGIONS[name] = [index % 8 * 256, 1024 + index // 8 * 256, 256, 256]


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def tile_uv(name, padding=16):
    x, y, w, h = REGIONS[name]
    return [(x + padding) / 2048, (y + padding) / 2048,
            (x + w - padding) / 2048, (y + h - padding) / 2048]


def color(name):
    # Byte-image buffers are encoded sRGB; shader sockets use p.rgb's linear RGB.
    return np.array([int(COLORS[name][i:i + 2], 16) / 255 for i in (0, 2, 4)])


def tagged_cube(name, at, size, role, bevel=.012):
    obj = p.cube(name, at, size, role, bevel)
    obj["hall_color_role"] = role
    return obj


def parquet_image():
    """Rasterize a 4:1 herringbone bond, 0.64 x 0.16 m, without photo grain."""
    size = 1024
    y, x = np.mgrid[0:size, 0:size]
    xx = (x + .5) / size * 6.6 - 3.3
    zz = (y + .5) / size * 6.2 - 3.1
    u = (xx + zz) / math.sqrt(2)
    v = (zz - xx) / math.sqrt(2)
    width, ratio = .16, 4
    u, v = u / width, v / width
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgb = rgba[:, :, :3]
    rgb[:] = color("parquet")
    filled = np.zeros((size, size), dtype=bool)
    for a in range(-15, 16):
        for b in range(-55, 56):
            ox, oy = a * ratio + b, a * ratio - b
            for vertical in [False, True]:
                px, py = (ox + ratio, oy) if vertical else (ox, oy)
                sx, sy = (1, ratio) if vertical else (ratio, 1)
                du, dv = u - px, v - py
                mask = (du >= 0) & (du < sx) & (dv >= 0) & (dv < sy)
                if not mask.any(): continue
                assert not (filled & mask).any()
                filled |= mask
                edge = np.minimum(np.minimum(du, sx - du), np.minimum(dv, sy - dv)) * width
                variation = 1 + .07 * math.sin(a * 17.71 + b * 7.37 + vertical * 2.5)
                seam = .68 + .32 * np.clip(edge / .005, 0, 1)
                along = dv if vertical else du
                cross = du if vertical else dv
                stroke = 1 + .012 * np.sin(cross * 23 + np.sin(along * .6))
                rgb[mask] = color("parquet") * (variation * seam * stroke)[mask, None]
    assert filled.all()
    image = bpy.data.images.new("Hall authored herringbone - 640 x 160 mm", width=size, height=size, alpha=False)
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(rgba.ravel())
    image.pack()
    return image


def foundation():
    kit = p.reuse("hall_floor", (0, 0, 0), source="mine_hut", original="room_shell")
    retained = []
    for obj in kit["objects"][:]:
        if obj.name.startswith("Honey timber foundation"):
            obj.data.materials.clear()
            obj.data.materials.append(p.material("wood_mid"))
            # Keep the source foundation's footprint, bevels and named mesh;
            # lower its top to clear the new planar parquet and rim.
            obj.scale.z = .32 / .36
            obj.location.z = -.12
            obj["hall_color_role"] = "wood_mid"
            retained.append(obj)
        else:
            bpy.data.objects.remove(obj, do_unlink=True)
    assert len(retained) == 1
    kit["objects"] = retained
    kit["collision"] = [dict(at=[0, -.10, 0], size=[6.8, .36, 6.4])]
    p.b.CURRENT = kit
    tagged_cube("Parquet underlay", (0, .050, 0), (6.6, .05, 6.2), "wood_mid", 0)
    obj = p.mesh("Herringbone floor surface", [(-3.3, .08, -3.1), (-3.3, .08, 3.1),
        (3.3, .08, 3.1), (3.3, .08, -3.1)], [(0, 1, 2, 3)], "parquet")
    obj["hall_color_role"] = "parquet"
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.reverse_faces(bm, faces=[face for face in bm.faces if face.normal.z < 0])
    bm.to_mesh(obj.data)
    bm.free()
    uv = obj.data.uv_layers.new(name="ParquetSource")
    for loop in obj.data.loops:
        q = obj.data.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = ((q.x + 3.3) / 6.6, (-q.y + 3.1) / 6.2)
    mat = obj.data.materials[0]
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = parquet_image()
    coords = mat.node_tree.nodes.new("ShaderNodeUVMap")
    coords.uv_map = "ParquetSource"
    mat.node_tree.links.new(coords.outputs["UV"], node.inputs["Vector"])
    mat.node_tree.links.new(node.outputs["Color"], mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    for z in [-3.15, 3.15]:
        tagged_cube("Floor perimeter rail", (0, .025, z), (6.8, .11, .10), "oak_edge", .012)
    for x in [-3.35, 3.35]:
        tagged_cube("Floor perimeter side rail", (x, .025, 0), (.10, .11, 6.2), "oak_edge", .012)


def walls():
    for name, at, yaw, length, windows in [
        ("hall_left_wall", (-3.3, .08, 0), 90, 6.4, True),
        ("hall_back_wall", (.10, .08, -3.1), 0, 6.6, False),
    ]:
        p.begin(name, at, yaw, [dict(at=[0, WALL_H / 2, 0], size=[length, WALL_H, .20])])
        wall = tagged_cube("Hall plaster with real apertures" if windows else "Hall uninterrupted plaster",
            (0, WALL_H / 2, 0), (length, WALL_H, .20), "plaster", .018)
        if windows:
            for z in WINDOW_Z:
                cut = tagged_cube("Temporary common rectangular window aperture", (-z, SILL_Y - .08 + HOLE_H / 2, 0),
                    (HOLE_W, HOLE_H, .8), "plaster", 0)
                p.boolean_cut(wall, cut)
        tagged_cube("Continuous dark wood wainscot backing", (0, .52, .115), (length, 1.04, .03), "panel", .008)
        count = 8 if windows else 9
        step = length / count
        for i in range(count):
            cx = -length / 2 + step * (i + .5)
            w, h = step - .13, .69
            for dx in [-w / 2, w / 2]:
                tagged_cube("Raised wainscot upright %02d" % i, (cx + dx, .54, .147), (.031, h, .034), "panel", .007)
            for dy in [-h / 2, h / 2]:
                tagged_cube("Raised wainscot cross rail %02d" % i, (cx, .54 + dy, .147), (w, .031, .034), "panel", .007)
        tagged_cube("Thick skirting base", (0, .095, .152), (length, .19, .105), "skirting", .015)
        tagged_cube("Skirting eased upper bead", (0, .202, .155), (length, .035, .11), "skirting", .008)
        tagged_cube("Wainscot chair rail", (0, 1.035, .155), (length, .075, .12), "panel", .012)
        tagged_cube("Cornice deep fascia", (0, 3.52, .133), (length, .19, .13), "cornice", .018)
        tagged_cube("Cornice upper ogee step", (0, 3.635, .151), (length, .062, .17), "cornice", .012)
        tagged_cube("Cornice lower bead", (0, 3.405, .151), (length, .045, .17), "cornice", .009)


def windows():
    center_y = SILL_Y + HOLE_H / 2
    at = (-3.2, center_y, WINDOW_Z[0])
    p.begin("hall_window_frame", at, 90)
    for x in [-HOLE_W / 2, HOLE_W / 2]:
        tagged_cube("Window casing upright", (x, 0, .015), (.12, HOLE_H + .14, .13), "window", .018)
        tagged_cube("Window reveal jamb", (x * .94, 0, -.095), (.045, HOLE_H, .15), "window", .008)
    for y in [-HOLE_H / 2, HOLE_H / 2]:
        tagged_cube("Window casing horizontal", (0, y, .015), (HOLE_W, .12, .13), "window", .016)
    tagged_cube("Projecting rounded window sill", (0, -HOLE_H / 2 - .065, .055), (HOLE_W + .28, .095, .30), "window", .025)
    tagged_cube("Short window sill apron", (0, -HOLE_H / 2 - .15, .035), (HOLE_W + .02, .075, .08), "window", .012)
    p.instance("hall_window_frame", "hall_window_frame_front", (-3.2, center_y, WINDOW_Z[1]), 90)
    p.begin("hall_window_grid", at, 90)
    inner_w, inner_h = HOLE_W - .14, HOLE_H - .14
    for i in [1, 2]:
        tagged_cube("Window mullion %d" % i, (-inner_w / 2 + inner_w * i / 3, 0, .012), (.034, inner_h, .045), "window", .006)
    for i in [1, 2, 3]:
        tagged_cube("Window transom %d" % i, (0, -inner_h / 2 + inner_h * i / 4, .016), (inner_w, .034, .045), "window", .006)
    tagged_cube("Window sash meeting rail", (0, 0, .031), (inner_w, .052, .065), "window", .007)
    p.instance("hall_window_grid", "hall_window_grid_front", (-3.2, center_y, WINDOW_Z[1]), 90)
    # Both apertures share one separately exportable glass surface.
    p.begin("hall_window_glass", (0, 0, 0))
    for z in WINDOW_Z:
        x = -3.218
        obj = p.mesh("Clear window glazing", [(x, SILL_Y + .06, z - HOLE_W / 2 + .06),
            (x, SILL_Y + HOLE_H - .06, z - HOLE_W / 2 + .06),
            (x, SILL_Y + HOLE_H - .06, z + HOLE_W / 2 - .06),
            (x, SILL_Y + .06, z + HOLE_W / 2 - .06)], [(0, 1, 2, 3)], "glass")
        obj["hall_color_role"] = "glass"
        obj.visible_shadow = False


def contract():
    entries = {}
    for name, region in REGIONS.items():
        uv = tile_uv(name)
        entries[name] = {"hex_srgb": COLORS[name], "rect_px_top_left": region,
            "safe_rect_px_top_left": [region[0] + 16, region[1] + 16, region[2] - 32, region[3] - 32],
            "uv_rect_gltf": uv, "uv_rect_blender": [uv[0], 1 - uv[3], uv[2], 1 - uv[1]],
            "kind": "shell_baked" if name in list(COLORS)[:6] else "solid_reuse_swatch",
            "recolor": "Replace base RGB in this fixed region; preserve local AO modulation."}
    write_json(KIT / "hall_palette.json", {"schema_version": 1, "atlas": "hall_albedo_ao.png", "size": [2048, 2048],
        "status": "SGODOT-319 shell v1 pending art-director review", "uv_origin_gltf": "top-left",
        "gutter_px": 16, "slots": entries,
        "hallkit_324_mapping": {name: name for name in ["oak", "oak_light", "oak_edge", "brass", "linen", "sky",
            "sage", "iron", "porcelain", "sage_dark", "linen_green", "petal", "print_portrait", "print_landscape", "glass", "stone"]},
        "skin_contract": "Same geometry and UVs across N1-N4. Recolor semantic regions; room-specific contact AO is not baked into this shared shell.",
        "reserved_for_furniture": SWATCHES})


def bake_export():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.render.bake.margin = 8
    scene.render.bake.margin_type = "EXTEND"
    scene.render.bake.use_clear = False
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    work = bpy.data.collections.new("TEMP_EXPORT")
    scene.collection.children.link(work)
    originals = list(scene.objects)
    names = list(p.KITS)
    copies = []
    for ki, name in enumerate(names):
        for obj in p.KITS[name]["objects"]:
            data = bpy.data.meshes.new_from_object(obj.evaluated_get(deps), depsgraph=deps)
            data.transform(obj.matrix_world)
            attr = data.attributes.new("kit_id", "INT", "FACE")
            for item in attr.data: item.value = ki
            copy = bpy.data.objects.new("Bake_" + obj.name, data)
            work.objects.link(copy)
            copies.append(copy)
    for obj in originals:
        obj.hide_render = True
        obj.hide_set(True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in copies: obj.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    modifier = joined.modifiers.new("Stable export triangles", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    joined.data.uv_layers.new(name="HallAtlas")
    joined.data.uv_layers.active_index = len(joined.data.uv_layers) - 1
    joined.data.uv_layers.active.active_render = True
    for mi, mat in enumerate(joined.data.materials):
        role = mat.name.split("_matte_")[0]
        assert role in REGIONS, (mat.name, role)
        faces = [f for f in joined.data.polygons if f.material_index == mi]
        if not faces: continue
        if role in SWATCHES:
            u0, v0, u1, v1 = tile_uv(role)
            for face in faces:
                for li in face.loop_indices:
                    joined.data.uv_layers.active.data[li].uv = ((u0 + u1) / 2, 1 - (v0 + v1) / 2)
            continue
        for face in joined.data.polygons: face.select = face.material_index == mi
        bpy.context.tool_settings.mesh_select_mode = (False, False, True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=.008, area_weight=.5, scale_to_bounds=True)
        bpy.ops.object.mode_set(mode="OBJECT")
        u0, v0, u1, v1 = tile_uv(role)
        for face in faces:
            for li in face.loop_indices:
                uv = joined.data.uv_layers.active.data[li].uv
                uv[:] = (u0 + uv.x * (u1 - u0), 1 - v1 + uv.y * (v1 - v0))
    tex = bpy.data.images.new("Hall_Albedo_LocalAO", width=2048, height=2048, alpha=False)
    tex.colorspace_settings.name = "sRGB"
    pixels = np.ones((2048, 2048, 4), dtype=np.float32)
    for role, (x, y, w, h) in REGIONS.items(): pixels[2048 - y - h:2048 - y, x:x + w, :3] = color(role)
    tex.pixels.foreach_set(pixels.ravel())
    for mat in joined.data.materials:
        role = mat.name.split("_matte_")[0]
        nt = mat.node_tree
        shader = nt.nodes.get("Principled BSDF")
        image = nt.nodes.new("ShaderNodeTexImage")
        image.image = tex
        nt.nodes.active = image
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.samples = 16
        ao.inputs["Distance"].default_value = .22
        soft = nt.nodes.new("ShaderNodeMixRGB")
        soft.inputs[0].default_value = .32
        soft.inputs[1].default_value = (1, 1, 1, 1)
        nt.links.new(ao.outputs["Color"], soft.inputs[2])
        multiply = nt.nodes.new("ShaderNodeMixRGB")
        multiply.blend_type = "MULTIPLY"
        multiply.inputs[0].default_value = 1
        base = shader.inputs["Base Color"]
        if base.is_linked: nt.links.new(base.links[0].from_socket, multiply.inputs[1])
        else: multiply.inputs[1].default_value = base.default_value
        nt.links.new(soft.outputs[0], multiply.inputs[2])
        emission = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(multiply.outputs[0], emission.inputs[0])
        nt.links.new(emission.outputs[0], nt.nodes.get("Material Output").inputs["Surface"])
    print("HALL_BAKE_START", len(joined.data.polygons), flush=True)
    bpy.ops.object.bake(type="EMIT")
    # Furniture swatches are intentionally unoccluded, independent of shell placement.
    tex.pixels.foreach_get(pixels.ravel())
    for role in SWATCHES:
        x, y, w, h = REGIONS[role]
        pixels[2048 - y - h:2048 - y, x:x + w, :3] = color(role)
    tex.pixels.foreach_set(pixels.ravel())
    tex.update()
    tex.filepath_raw = str(KIT / "hall_albedo_ao.png")
    tex.file_format = "PNG"
    tex.save()
    opaque = bpy.data.materials.new("HallShellAtlas")
    opaque.use_nodes = True
    node = opaque.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = tex
    opaque.node_tree.links.new(node.outputs["Color"], opaque.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    data = joined.data
    normal = data.corner_normals
    uv = data.uv_layers.active.data
    kit_ids = data.attributes["kit_id"].data
    stats = {"atlas": {"file": "hall_albedo_ao.png", "size": [2048, 2048], "purpose": "Authored color + shell-local contact AO; no baked direct light or furniture AO"}, "assets": []}
    for ki, name in enumerate(names):
        faces = [f for f in data.polygons if kit_ids[f.index].value == ki]
        root = p.KITS[name]["root"]
        inv = root.matrix_world.inverted()
        rot = inv.to_3x3()
        ids = sorted({vi for f in faces for vi in f.vertices})
        mapping = {old: new for new, old in enumerate(ids)}
        out = bpy.data.meshes.new(name + "_mesh")
        out.from_pydata([inv @ data.vertices[i].co for i in ids], [], [[mapping[i] for i in f.vertices] for f in faces])
        out.update()
        layer = out.uv_layers.new(name="HallAtlas")
        normals, li_out = [], 0
        for new, old in zip(out.polygons, faces):
            new.use_smooth = old.use_smooth
            for li in old.loop_indices:
                layer.data[li_out].uv = uv[li].uv
                normals.append((rot @ normal[li].vector).normalized())
                li_out += 1
        out.normals_split_custom_set(normals)
        out.materials.append(opaque)
        obj = bpy.data.objects.new(name, out)
        work.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        path = KIT / (name + ".glb")
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_apply=True,
            export_yup=True, export_texcoords=True, export_normals=True, export_materials="EXPORT",
            export_image_format="NONE", export_animations=False, export_cameras=False, export_lights=False)
        patch_glb(path, name == "hall_window_glass")
        out.calc_loop_triangles()
        stats["assets"].append({"name": name, "triangles": len(out.loop_triangles), "surfaces": 1,
            "vertices": len(out.vertices), "bytes": path.stat().st_size})
        bpy.data.objects.remove(obj, do_unlink=True)
    lookup = {a["name"]: a["triangles"] for a in stats["assets"]}
    stats.update(unique_triangles=sum(lookup.values()), scene_triangles=sum(lookup.values()) + sum(lookup[i["asset"]] for i in p.INSTANCES),
        static_draw_surfaces=len(names) + len(p.INSTANCES), materials=2, glass_surfaces=1,
        placed_instances=len(names) + len(p.INSTANCES), reference_budget=dict(scene_triangles=150000, static_draw_surfaces=50))
    write_json(KIT / "shell_asset_stats.json", stats)
    texture_import = KIT / "hall_albedo_ao.png.import"
    if not texture_import.exists():
        rel = "res://" + str((KIT / "hall_albedo_ao.png").relative_to(ROOT))
        template = (ROOT / "assets/rooms/tackle_shop/room_albedo_ao.png.import").read_text()
        template = re.sub(r'uid="[^\"]+"\n', "", template)
        template = template.replace("res://assets/rooms/tackle_shop/room_albedo_ao.png", rel)
        template = re.sub(r"room_albedo_ao.png-[a-f0-9]+", "hall_albedo_ao.png-" + hashlib.md5(rel.encode()).hexdigest(), template)
        texture_import.write_text(template)
    print("HALL_EXPORT_READY", stats["scene_triangles"], stats["static_draw_surfaces"], flush=True)


def patch_glb(path, glass):
    raw = path.read_bytes()
    length = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + length])
    tail = raw[20 + length:]
    doc["images"] = [{"uri": "hall_albedo_ao.png"}]
    doc["textures"] = [{"source": 0, "sampler": 0}]
    doc["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}]
    doc["materials"] = [{"name": "HallWindowGlass" if glass else "HallShellAtlas",
        "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, .12 if glass else 1], "baseColorTexture": {"index": 0},
            "metallicFactor": 0, "roughnessFactor": .28 if glass else .82}, "alphaMode": "BLEND" if glass else "OPAQUE",
        "doubleSided": glass, "extensions": {"KHR_materials_specular": {"specularFactor": .48}}}]
    doc["extensionsUsed"] = sorted(set(doc.get("extensionsUsed", [])) | {"KHR_materials_specular"})
    encoded = json.dumps(doc, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 4)
    path.write_bytes(struct.pack("<III", 0x46546C67, 2, 20 + len(encoded) + len(tail)) + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded + tail)
    template = (ROOT / "assets/rooms/mine_hut/room_shell.glb.import").read_text()
    template = re.sub(r'uid="[^\"]+"\n', "", template)
    rel = "res://" + str(path.relative_to(ROOT))
    imported = "res://.godot/imported/" + path.name + "-" + hashlib.md5(rel.encode()).hexdigest() + ".scn"
    template = re.sub(r'res://.godot/imported/room_shell.glb-[^\"]+.scn', imported, template)
    template = template.replace("res://assets/rooms/mine_hut/room_shell.glb", rel)
    template = re.sub(r"gltf/texture_map_mode=\d+", "gltf/texture_map_mode=1", template)
    import_path = Path(str(path) + ".import")
    if not import_path.exists(): import_path.write_text(template)


def main():
    p.start("shell_hall", "SGODOT-315 R3 approved main 2026-10-31")
    p.OUT, p.SOURCE, p.QA = KIT, SOURCE, QA
    for path in [KIT, SOURCE, QA]: path.mkdir(parents=True, exist_ok=True)
    (SOURCE / ".gdignore").touch()
    p.b.PALETTE.update(COLORS)
    foundation()
    walls()
    windows()
    p.MANIFEST_EXTRA.update(floor_y=FLOOR_Y, footprint=[6.8, 6.4], wall_height=WALL_H,
        texture="hall_albedo_ao.png", palette="hall_palette.json", revision="SGODOT-319 shell v1",
        dimensions={"source": "Unspecified heights inferred from approved main; pending shell review",
            "window_aperture_width": HOLE_W, "window_aperture_height": HOLE_H, "window_sill_y": SILL_Y,
            "window_centers_z": WINDOW_Z, "window_panes": [3, 4], "wainscot_top_y": 1.1525,
            "cornice_bottom_y": 3.4625, "cornice_top_y": 3.746, "plank_size": [.64, .16],
            "wall_top_y": 3.78, "wall_thickness": .20, "floor_top_y": .08},
        anchors=[dict(name="spawn", position=[0, .08, 2.5], yaw_degrees=180, module="hall_floor"),
            dict(name="exit", position=[0, .08, 2.88], yaw_degrees=180, module="hall_floor"),
            dict(name="badge_exit", position=[0, .55, 3.0], yaw_degrees=0, module="hall_floor")],
        boundaries=[dict(name="cut_right", at=[3.38, 1.08, 0], size=[.04, 2, 6.4]),
            dict(name="cut_front", at=[0, 1.08, 3.18], size=[6.8, 2, .04])],
        openings=[dict(name="window_%d" % i, position=[-3.3, SILL_Y + HOLE_H / 2, z],
            size=[.20, HOLE_H, HOLE_W], frame="hall_window_frame", grid="hall_window_grid") for i, z in enumerate(WINDOW_Z, 1)],
        contract_notes=["No front wall, door or wall-end square columns.", "Cut-edge colliders are invisible containment; exit anchor is inside the front edge.",
            "No hotel-specific furniture, sign, light, camera or environment in reusable art."])
    target = Vector((0, 2.0, 0))
    cam = target + Vector((math.cos(math.radians(43)) / math.sqrt(2), math.sin(math.radians(43)), math.cos(math.radians(43)) / math.sqrt(2))) * 20
    p.finalize({"position": list(cam), "target": list(target), "size": 11.0, "pitch_degrees": 43, "yaw_degrees": 45,
        "near": .1, "far": 40.0},
        {"background": "B5A18B", "ambient_color": "FFF1DC", "ambient": .40, "sun_color": "FFF2DA", "sun": 1.2,
            "sun_position": [-6, 4, -1], "sun_target": [0, 0, 0], "shadow_bias": .15, "shadow_normal_bias": .8,
            "shadow_mode": "orthogonal_single", "shadow_distance": 30, "angular_distance": .4})
    layout = json.loads((KIT / "layout.json").read_text())
    for row in layout["assets"]:
        row["material"] = "glass" if row["name"] == "hall_window_glass" else "opaque"
        row["cast_shadow"] = row["name"] not in ("hall_window_glass", "hall_floor")
    write_json(KIT / "layout.json", layout)
    contract()
    origins = {}
    for name in p.KITS:
        origin = {"module": name, "author": "ZHAOYUN", "task": "SGODOT-319", "reference": "SGODOT-315_Hotel_Lobby_Main_2026-10-31.png"}
        if name == "hall_floor":
            origin.update(source="tools/art/source/mine_hut/mine_hut.blend", source_module="room_shell", retained_object="Honey timber foundation",
                source_sha256=hashlib.sha256((ROOT / "tools/art/source/mine_hut/mine_hut.blend").read_bytes()).hexdigest(),
                changes=["Retain 6.8 x 6.4 footprint and editable bevelled foundation", "Lower foundation top to .04 m", "Replace straight planks with authored 0.64 x 0.16 m herringbone", "Remap all UVs to HallAtlas"])
        else:
            origin.update(source="tools/art/build_basic_room.py + scene_room_pipeline.py", reuse_kind="Construction helpers; new hall geometry", changes=["Two 3.7 m walls without end columns", "Rectangular true window apertures; casing and grille are separate local-pivot modules", "Semantic HallAtlas UVs"])
        origins[name] = origin
        write_json(KIT / "provenance" / name / "reuse_provenance.json", origin)
    write_json(KIT / "shell_reuse_provenance.json", origins)
    if "--geometry-only" not in sys.argv: bake_export()


if __name__ == "__main__": main()
