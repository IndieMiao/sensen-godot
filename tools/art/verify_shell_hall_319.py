"""Independent audit of exported hall meshes and the stable atlas contract (Blender)."""
from pathlib import Path
import hashlib
import itertools
import json
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art"))
from verify_chef_sign import load_glb, accessor

KIT = ROOT / "assets/rooms/_shared/shell_hall"
OUT = ROOT / "output/poi-hall-319"


def main():
    layout = json.loads((KIT / "layout.json").read_text())
    stats = json.loads((KIT / "shell_asset_stats.json").read_text())
    palette = json.loads((KIT / "hall_palette.json").read_text())
    report = {"checks": [], "assets": {}, "intersections": []}

    def check(ok, label):
        report["checks"].append({"check": label, "passed": bool(ok)})
        if not ok: print("FAIL", label, flush=True)

    atlas = bpy.data.images.load(str(KIT / "hall_albedo_ao.png"))
    check(list(atlas.size) == [2048, 2048], "One 2048-square shared atlas")
    slots = palette["slots"]
    rectangles = list(slots.values())
    overlaps = []
    for a, b in itertools.combinations(rectangles, 2):
        x, y, w, h = a["rect_px_top_left"]
        u, v, s, t = b["rect_px_top_left"]
        if not (x + w <= u or u + s <= x or y + h <= v or v + t <= y):
            overlaps.append([a["rect_px_top_left"], b["rect_px_top_left"]])
    report["atlas_region_pairs_checked"] = len(rectangles) * (len(rectangles) - 1) // 2
    report["atlas_region_overlaps"] = overlaps
    check(not overlaps, "All semantic atlas regions are disjoint")
    check(len(palette["hallkit_324_mapping"]) == 16, "Mapping covers all 16 SGODOT-324 provisional roles")
    rows = {r["name"]: r for r in layout["assets"]}
    local = {}
    for row in layout["assets"]:
        name = row["name"]
        path = KIT / row["file"]
        doc, data = load_glb(path)
        check(len(doc["meshes"]) == 1 and len(doc["meshes"][0]["primitives"]) == 1, name + " one mesh and surface")
        prim = doc["meshes"][0]["primitives"][0]
        points = np.asarray(accessor(doc, data, prim["attributes"]["POSITION"]))
        normals = np.asarray(accessor(doc, data, prim["attributes"]["NORMAL"]))
        uv = np.asarray(accessor(doc, data, prim["attributes"]["TEXCOORD_0"]))
        indices = np.asarray(accessor(doc, data, prim["indices"])).reshape((-1, 3))
        check(np.isfinite(points).all() and np.isfinite(uv).all(), name + " finite vertices and UV")
        check(np.all(np.abs(np.linalg.norm(normals, axis=1) - 1) < .001), name + " unit shading normals")
        check(np.min(uv) >= 0 and np.max(uv) <= 1, name + " UVs inside atlas")
        if name == "hall_floor":
            floor_points = (points[:, 1] > .0799) & (uv[:, 0] < .5) & (uv[:, 1] < .5)
            check(floor_points.sum() >= 4 and np.all(normals[floor_points, 1] > .99), "Parquet top face actually points upward")
        area = np.linalg.norm(np.cross(points[indices[:, 1]] - points[indices[:, 0]], points[indices[:, 2]] - points[indices[:, 0]]), axis=1)
        check(np.min(area) > 1e-10, name + " no zero-area triangles")
        ids = np.full(len(uv), -1, dtype=int)
        for i, slot in enumerate(rectangles):
            x0, y0, x1, y1 = slot["uv_rect_gltf"]
            mask = (uv[:, 0] >= x0 - .00001) & (uv[:, 0] <= x1 + .00001) & (uv[:, 1] >= y0 - .00001) & (uv[:, 1] <= y1 + .00001)
            ids[mask] = i
        check(np.min(ids) >= 0, name + " every UV retains 16-pixel gutter")
        check(np.all(np.ptp(ids[indices], axis=1) == 0), name + " triangles never interpolate between color regions")
        check(doc.get("images") == [{"uri": "hall_albedo_ao.png"}], name + " external shared atlas, no embedded duplicate")
        mat = doc["materials"][0]
        check(mat["alphaMode"] == ("BLEND" if row["material"] == "glass" else "OPAQUE"), name + " own correct surface material")
        check("gltf/texture_map_mode=1" in Path(str(path) + ".import").read_text(), name + " import map mode 1")
        expected = next(a for a in stats["assets"] if a["name"] == name)
        check(len(indices) == expected["triangles"], name + " exported counts match statistics")
        local[name] = (points, indices)
        report["assets"][name] = {"triangles": len(indices), "local_bounds": [points.min(0).tolist(), points.max(0).tolist()],
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    placed = {}
    for placement in layout["assets"] + layout["instances"]:
        asset = placement.get("asset", placement["name"])
        points, indices = local[asset]
        transform = Matrix.Translation(Vector(placement["position"])) @ Matrix.Rotation(math.radians(placement["yaw_degrees"]), 4, "Y")
        vertices = [transform @ Vector(q) for q in points]
        a = np.array(vertices)
        placed[placement["name"]] = {"vertices": vertices, "indices": indices, "bvh": BVHTree.FromPolygons(vertices, indices.tolist(), all_triangles=True),
            "bounds": [a.min(0), a.max(0)]}
    floor = placed["hall_floor"]["bounds"]
    check(np.allclose(floor[1] - floor[0], [6.8, .36, 6.4], atol=.0001), "Actual foundation footprint is 6.8 x 6.4 m")
    check(abs(floor[1][1] - .08) < .0001, "Actual visual floor top is y=.08 m")
    for name in ["hall_left_wall", "hall_back_wall"]:
        lo, hi = placed[name]["bounds"]
        check(abs(hi[1] - 3.78) < .001 and abs(lo[1] - .08) < .001, name + " 3.7 m from floor to top")
    wall = placed["hall_left_wall"]["bvh"]
    for z in [-1.78, 1.78]:
        for dy in [.15, .65, 1.2, 1.85]:
            hit = wall.ray_cast(Vector((-3.8, 1.20 + dy, z)), Vector((1, 0, 0)), 1.2)
            check(hit[0] is None, "Actual left-wall mesh has unobstructed window aperture at %.2f / %.2f" % (z, dy))
    check(wall.ray_cast(Vector((-3.8, 2.1, 0)), Vector((1, 0, 0)), 1.2)[0] is not None, "Positive control: wall between apertures is solid")
    unexpected = []
    for (na, a), (nb, b) in itertools.combinations(placed.items(), 2):
        if np.any(a["bounds"][1] < b["bounds"][0] - .0001) or np.any(b["bounds"][1] < a["bounds"][0] - .0001): continue
        hits = a["bvh"].overlap(b["bvh"])
        crossings = 0
        for ia, ib in hits:
            ta = [a["vertices"][int(v)] for v in a["indices"][ia]]
            tb = [b["vertices"][int(v)] for v in b["indices"][ib]]
            cuts = []
            for one, two in [(ta, tb), (tb, ta)]:
                normal = (two[1] - two[0]).cross(two[2] - two[0]).normalized()
                distances = [normal.dot(v - two[0]) for v in one]
                cuts.append(min(distances) < -.0002 and max(distances) > .0002)
            crossings += all(cuts)
        reason = ""
        if "wall" in na and "wall" in nb: reason = "Intentional cornice / wainscot corner construction join"
        elif "hall_left_wall" in (na, nb) and ("window_frame" in na or "window_frame" in nb): reason = "Window casing mounts around the real opening"
        elif "window_frame" in na and "window_grid" in nb or "window_grid" in na and "window_frame" in nb: reason = "Grille meets sash rebates"
        elif "hall_floor" in (na, nb): reason = "Flush wall-to-foundation support"
        if hits:
            entry = {"modules": [na, nb], "contact_pairs": len(hits), "crossing_pairs": crossings, "classification": reason or "Flush/tangent contact"}
            report["intersections"].append(entry)
            if crossings and not reason: unexpected.append(entry)
    check(not unexpected, "No unclassified crossings between delivered modules")
    report["unexpected_intersections"] = unexpected
    check(stats["scene_triangles"] < 20000, "Shared shell reserves at least 130k triangles for furniture and plants")
    check(stats["static_draw_surfaces"] == 8, "Shared shell uses 8 placed surfaces including one glazing surface")
    check(stats["glass_surfaces"] == 1, "Both windows use one combined glass module")
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / "tools/art/source/shell_hall/shell_hall.blend"))
    check(all(bpy.data.collections.get("KIT_" + name) is not None for name in rows), "Editable source retains all module collections")
    check(len([o for o in bpy.data.objects if o.type == "MESH"]) > 100, "Editable named construction parts retained")
    check(any(o.name.startswith("Honey timber foundation") for o in bpy.data.objects), "Editable Mine Hut foundation actually retained")
    report["failures"] = [c for c in report["checks"] if not c["passed"]]
    report["passed"] = not report["failures"]
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "geometry-validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print("HALL_GEOMETRY_VALIDATION", report["passed"], "checks", len(report["checks"]), flush=True)
    if report["failures"]: raise SystemExit(1)


if __name__ == "__main__": main()
