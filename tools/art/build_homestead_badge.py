"""SGODOT-401 C63 A: editable four-tier farm badge; blank faces, no baked text.

blender --background --python /absolute/path/tools/art/build_homestead_badge.py
Godot metres, Y up, +Z front. Shared base + one visible tier = two surfaces.
"""
from pathlib import Path
import hashlib
import json
import math
import sys
import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art"))
import build_decor_assets as kit

SOURCE = ROOT / "tools/art/source/homestead_badge_401"
OUT = ROOT / "assets/farm/art"
NAME = "homestead_badge"
PALETTE = {"post": "B58551", "stone": "BFB8A5", "stone_light": "CEC6B3",
           "wood_ring": "AA713D", "wood_face": "F6E6CB",
           "bronze_ring": "D68A47", "bronze_face": "F9E8CC",
           "silver_ring": "ABB3BC", "silver_face": "F9F8F3",
           "gold_ring": "D9AC36", "gold_face": "F0D45A"}


def vertex_material():
    mat = bpy.data.materials.new("Farm matte vertex paint")
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = .9
    shader.inputs["Specular IOR Level"].default_value = .18
    color = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    color.layer_name = "Color"
    mat.node_tree.links.new(color.outputs["Color"], shader.inputs["Base Color"])
    return mat


def badge(tier):
    # A 0.65 m clear disc, 0.80 m outer rim, softly bevelled outer silhouette.
    # Four closed 24-gon loops: 188 triangles including the hidden back cap.
    rings = [(.325, .052), (.389, .052), (.400, .039), (.400, -.035)]
    n = 24
    vertices = [(r * math.cos(i * math.tau / n), r * math.sin(i * math.tau / n), z)
                for r, z in rings for i in range(n)]
    faces = [tuple(range(n))]
    for row in range(3):
        faces.extend((row*n+i, row*n+(i+1)%n, (row+1)*n+(i+1)%n, (row+1)*n+i) for i in range(n))
    faces.append(tuple(reversed(range(3*n, 4*n))))
    obj = kit.mesh("Tier_" + tier + " / blank medallion", vertices, faces, tier + "_ring")
    obj.data.materials.append(kit.MATS[tier + "_face"])
    obj.data.polygons[0].material_index = 1
    return obj


def export_mesh(sources, name, mat, parent):
    bpy.ops.object.select_all(action="DESELECT")
    deps = bpy.context.evaluated_depsgraph_get()
    copies = []
    for source in sources:
        data = bpy.data.meshes.new_from_object(source.evaluated_get(deps), depsgraph=deps)
        obj = bpy.data.objects.new(name + " export", data)
        bpy.context.scene.collection.objects.link(obj)
        obj.matrix_world = source.matrix_world.copy()
        obj.select_set(True)
        copies.append(obj)
    bpy.context.view_layer.objects.active = copies[0]
    if len(copies) > 1:
        bpy.ops.object.join()
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    tri = obj.modifiers.new("Fixed export triangulation", "TRIANGULATE")
    tri.quad_method = "FIXED"; tri.ngon_method = "CLIP"
    bpy.ops.object.modifier_apply(modifier=tri.name)
    data = obj.data
    colors = data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    data.color_attributes.active_color = colors
    data.color_attributes.render_color_index = 0
    for face in data.polygons:
        rgba = data.materials[face.material_index].diffuse_color
        for index in face.loop_indices:
            colors.data[index].color = rgba
        face.material_index = 0
    data.materials.clear(); data.materials.append(mat)
    for uv in list(data.uv_layers):
        data.uv_layers.remove(uv)
    obj.name = name; data.name = name + "_mobile"
    obj.parent = parent
    data.calc_loop_triangles()
    return obj, len(data.loop_triangles)


def empty(name, parent=None, at=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = kit.v(at); obj.parent = parent
    obj.empty_display_type = "ARROWS"; obj.empty_display_size = .08
    return obj


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    SOURCE.mkdir(parents=True, exist_ok=True); (SOURCE / ".gdignore").touch()
    for key, value in PALETTE.items():
        mat = bpy.data.materials.new(key)
        mat.diffuse_color = (*kit.rgb(value), 1)
        mat.use_nodes = True
        shader = mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = mat.diffuse_color
        shader.inputs["Roughness"].default_value = .9
        kit.MATS[key] = mat
    kit.begin("Editable common timber and stone foot", [1, 1], 900)
    # Reuse #746 single-post construction, scaled to the approved 0.60 m timber.
    kit.box("Single timber post / #746 construction resized", (0, .40, .09), (.14, .60, .14), "post", .008)
    # Five icosahedral river stones: 100 triangles; floor-flat bottom, 0.50 m footprint.
    for i in range(5):
        angle = i * math.tau / 5 + math.pi / 2
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1)
        stone = bpy.context.object
        for vertex in stone.data.vertices:
            p = vertex.co
            p.x = p.x * .108 + .145 * math.cos(angle)
            p.y = p.y * .108 + .145 * math.sin(angle)
            p.z = max(0, p.z * .095 + .075)
        kit.finish(stone, "Stone foot / pebble %d" % (i+1), "stone_light" if i % 2 else "stone", True)
    base_sources = list(kit.CURRENT.objects)
    mat = vertex_material()
    root = empty(NAME)
    face = empty("BadgeFace", root, (0, 1.0, 0))
    face.rotation_euler.x = -math.radians(25)
    output = [root, face]
    common, common_tris = export_mesh(base_sources, "Common", mat, root)
    output.append(common)
    tier_tris = {}
    for tier in ("wood", "bronze", "silver", "gold"):
        kit.begin("Editable " + tier + " medallion", [1, 1], 900)
        source = badge(tier)
        obj, tris = export_mesh([source], "Tier_" + tier, mat, face)
        output.append(obj); tier_tris[tier] = tris
        # Show the editable tiers beside each other in the .blend, not overlapping.
        source.location.x = (-1.5 + len(tier_tris)) * 1.0
        source.location.z = 1.0
        source.rotation_euler.x = -math.radians(25)
    number = empty("BadgeNumber", face, (0, 0, .055))
    lv = empty("BadgeLv", face, (0, .238, .055))
    output.extend([number, lv])
    bpy.ops.object.select_all(action="DESELECT")
    for obj in output: obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    path = OUT / (NAME + ".glb")
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
        export_yup=True, export_materials="EXPORT", export_attributes=False, export_cameras=False,
        export_lights=False, export_animations=False, export_extras=False, export_texcoords=False,
        export_tangents=False)
    total = common_tris + sum(tier_tris.values())
    assert total <= 900, total
    entry = dict(triangles=total, visible_triangles=common_tris+max(tier_tris.values()),
        surfaces=2, surfaces_scope="simultaneously visible: shared base + exactly one tier",
        stored_surfaces=5, materials=1, common_triangles=common_tris, tier_triangles=tier_tris,
        bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        generator="tools/art/build_homestead_badge.py", source="tools/art/source/homestead_badge_401/homestead_badge.blend",
        units="metres", front="+Z", pivot="stone base bottom centre", author="赵云",
        virtual_user_id="8ea32e40-c0ba-4a31-864f-374a6bcbc554", palette_srgb=PALETTE,
        diameter_m=.8, clear_face_diameter_m=.65, disc_centre_y_m=1.0, tilt_x_degrees=-25,
        timber_height_m=.60, tier_levels=dict(wood=[2,4], bronze=[5,9], silver=[10,14], gold=[15,17]),
        default_tier="wood", material_contract=dict(roughness=.9, metallic=0, specular=.18, vertex_color_is_srgb=False),
        sockets={"BadgeNumber":dict(parent="BadgeFace",position=[0,0,.055],type="Marker3D",surface_offset_m=.003),
                 "BadgeLv":dict(parent="BadgeFace",position=[0,.238,.055],type="Marker3D",surface_offset_m=.003)},
        provenance=dict(timber="upgrade_plaque #746 / 2761ba4c single timber post, resized; geometry regenerated",stone="New five-pebble base from approved concept A",medallion="New C63 A model; four blank vertex-colour variants"))
    manifest_path = OUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["assets"][NAME] = entry
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (SOURCE / "spec.json").write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n")
    for obj in output: bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "homestead_badge.blend"), compress=True)
    print("HOMESTEAD_BADGE", total, "stored triangles;", entry["visible_triangles"], "visible; 2 visible surfaces / 5 stored")


if __name__ == "__main__": main()
