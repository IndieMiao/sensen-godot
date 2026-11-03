"""Editable assembled scene, copied from approved sources without exporting GLBs."""
from pathlib import Path
import json
import math
import sys
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
KIT = ROOT / "assets/rooms/poi_culture_hall"
sys.path.insert(0, str(ROOT / "tools/art"))
from verify_chef_sign import load_glb, accessor


def v(at):
    return Vector((at[0], -at[2], at[1]))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    main_scene = bpy.context.scene
    main_scene.name = "N3 Culture Hall assembled v1"
    source_scene = bpy.data.scenes.new("Editable module templates")
    templates = {}

    def read(path, names):
        with bpy.data.libraries.load(str(path), link=False) as (available, loaded):
            loaded.collections = ["KIT_" + name for name in names]
        for name, collection in zip(names, loaded.collections):
            assert collection is not None, (path, name)
            source_scene.collection.children.link(collection)
            collection.hide_render = False
            collection.hide_viewport = False
            templates[name] = collection

    layout = json.loads((KIT / "layout.json").read_text())
    own = [a["name"] for a in layout["assets"] if not a["name"].startswith("props/")]
    read(HERE / "culture_hall_reuse.blend", own)
    props = [a["supplier_asset"] for a in layout["assets"] if a["name"].startswith("props/")]
    read(HERE / "props/culture_props.blend", props)
    shell = json.loads((ROOT / "assets/rooms/_shared/shell_hall/layout.json").read_text())
    read(ROOT / "tools/art/source/shell_hall/shell_hall.blend", [a["name"] for a in shell["assets"]])
    bpy.context.window.scene = source_scene
    bpy.context.view_layer.update()
    matrices = {n: {o.name: o.matrix_world.copy() for o in c.objects} for n, c in templates.items()}
    bpy.context.window.scene = main_scene

    def place(name, template_name, at, yaw, target=None):
        collection = bpy.data.collections.new(name)
        main_scene.collection.children.link(collection)
        root = bpy.data.objects.new(name, None)
        collection.objects.link(root)
        root.location = v(at)
        root.rotation_euler.z = math.radians(yaw)
        if target is not None:
            root.rotation_euler = (v(target) - root.location).to_track_quat("Y", "Z").to_euler()
        root["module"] = template_name
        original = templates[template_name]
        old_root = next(o for o in original.objects if o.type == "EMPTY" and o.parent is None)
        inverse = matrices[template_name][old_root.name].inverted()
        for obj in original.objects:
            if obj.type != "MESH":
                continue
            duplicate = obj.copy()
            duplicate.data = obj.data.copy()
            duplicate.name = name + " / " + obj.name
            collection.objects.link(duplicate)
            duplicate.parent = root
            duplicate.matrix_parent_inverse = Matrix.Identity(4)
            duplicate.matrix_local = inverse @ matrices[template_name][obj.name]
        return collection

    # Swap only copied shell materials/images; the shared source is read-only.
    atlas = bpy.data.images.load(str(KIT / "room_albedo_ao.png"))
    atlas.pack()
    for name in own:
        for obj in templates[name].objects:
            if obj.type != "MESH":
                continue
            for material in obj.data.materials:
                if material and material.use_nodes:
                    for node in material.node_tree.nodes:
                        if node.type == "TEX_IMAGE":
                            node.image = atlas
    material_map = {}
    for spec in shell["assets"] + shell["instances"]:
        col = place(spec["name"], spec.get("asset", spec["name"]), spec["position"], spec["yaw_degrees"])
        for obj in col.objects:
            if obj.type != "MESH":
                continue
            for slot in obj.material_slots:
                material = slot.material
                if material is None:
                    continue
                if material.name not in material_map:
                    copy = material.copy()
                    copy.name = "N3 shell / " + material.name
                    if copy.use_nodes:
                        for node in copy.node_tree.nodes:
                            if node.type == "TEX_IMAGE":
                                node.image = atlas
                    material_map[material.name] = copy
                slot.material = material_map[material.name]
    for row in layout["placements"]:
        place(row["name"], row["model"].split("/")[-1], row["position"], row["yaw_degrees"], row.get("target"))
    markers = bpy.data.collections.new("Runtime anchors")
    main_scene.collection.children.link(markers)
    for spec in layout["anchors"]:
        obj = bpy.data.objects.new(spec["name"], None)
        markers.objects.link(obj)
        obj.location = v(spec["position"])
        obj.rotation_euler.z = math.radians(spec.get("yaw_degrees", 0))
        obj.empty_display_type = "ARROWS"
        obj.empty_display_size = .15
        for key in ["size", "module", "stand"]:
            if key in spec:
                obj[key] = spec[key]
    main_scene["runtime_authority"] = "layout.json and immutable approved GLBs; this source does not re-export suppliers"
    main_scene["supplier_commit"] = layout["props_dependency"]["commit"]
    main_scene.unit_settings.system = "METRIC"
    bpy.context.view_layer.update()
    checks = []
    graph = bpy.context.evaluated_depsgraph_get()
    expected = {r["name"]: KIT / (r["model"] + ".glb") for r in layout["placements"]}
    for row in shell["assets"] + shell["instances"]:
        expected[row["name"]] = ROOT / "assets/rooms/_shared/shell_hall" / (row.get("asset", row["name"]) + ".glb")
    for name, path in expected.items():
        collection = bpy.data.collections[name]
        root = next(o for o in collection.objects if o.type == "EMPTY" and o.parent is None)
        inverse = root.matrix_world.inverted()
        points = []
        for obj in collection.objects:
            if obj.type != "MESH":
                continue
            mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(graph), depsgraph=graph)
            for vertex in mesh.vertices:
                q = inverse @ obj.matrix_world @ vertex.co
                points.append((q.x, q.z, -q.y))
            bpy.data.meshes.remove(mesh)
        doc, blob = load_glb(path)
        actual = [p for m in doc["meshes"] for primitive in m["primitives"] for p in accessor(doc, blob, primitive["attributes"]["POSITION"])]
        source_bounds = [[fn(p[i] for p in points) for i in range(3)] for fn in [min, max]]
        export_bounds = [[fn(p[i] for p in actual) for i in range(3)] for fn in [min, max]]
        error = max(abs(a-b) for x,y in zip(source_bounds, export_bounds) for a,b in zip(x,y))
        checks.append(dict(name=name, bounds_max_error_m=error, passed=error<2e-5))
    report = dict(passed=all(c["passed"] for c in checks), checks=checks,
                  scope="Evaluate editable source meshes in each placed local pivot and compare with approved GLB bounds")
    (ROOT / "output/culture-hall-323/assembly-source.json").write_text(json.dumps(report, indent=2)+"\n")
    assert report["passed"], [c for c in checks if not c["passed"]]
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE / "culture_hall_v1.blend"), compress=True)
    print("CULTURE_ASSEMBLY_SOURCE", len(layout["placements"]), "placed modules, shell and runtime anchors")


if __name__ == "__main__":
    main()
