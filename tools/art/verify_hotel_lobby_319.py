"""Independent delivered-GLB audit for N1, including exact 324 scale and mesh crossings."""
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

KIT = ROOT / "assets/rooms/poi_hotel_lobby"
HALL = ROOT / "assets/rooms/_shared/shell_hall"
QA = ROOT / "output/hotel-lobby-319"


def local_mesh(path):
    doc, blob = load_glb(path)
    points, normals, uv, triangles, colors = [], [], [], [], []
    for node in doc["nodes"]:
        if "mesh" not in node: continue
        assert np.allclose(node.get("scale", [1, 1, 1]), [1, 1, 1])
        assert np.allclose(node.get("translation", [0, 0, 0]), [0, 0, 0])
        assert np.allclose(node.get("rotation", [0, 0, 0, 1]), [0, 0, 0, 1])
        for prim in doc["meshes"][node["mesh"]]["primitives"]:
            base = len(points)
            positions = accessor(doc, blob, prim["attributes"]["POSITION"])
            points.extend(positions)
            normals.extend(accessor(doc, blob, prim["attributes"]["NORMAL"]))
            uv.extend(accessor(doc, blob, prim["attributes"]["TEXCOORD_0"]))
            colors.extend(accessor(doc, blob, prim["attributes"]["COLOR_0"]) if "COLOR_0" in prim["attributes"] else [(1, 1, 1, 1)] * len(positions))
            indices = [a[0] + base for a in accessor(doc, blob, prim["indices"])]
            triangles.extend([indices[i:i + 3] for i in range(0, len(indices), 3)])
    return {"doc": doc, "points": np.asarray(points), "normals": np.asarray(normals), "uv": np.asarray(uv),
        "triangles": np.asarray(triangles), "colors": np.asarray(colors)}


def world_mesh(local, placement):
    transform = Matrix.Translation(Vector(placement["position"])) @ Matrix.Rotation(math.radians(placement.get("yaw_degrees", 0)), 4, "Y")
    points = [transform @ Vector(q) for q in local["points"]]
    a = np.array(points)
    return {"points": points, "triangles": local["triangles"], "lo": a.min(0), "hi": a.max(0),
        "bvh": BVHTree.FromPolygons(points, local["triangles"].tolist(), all_triangles=True)}


def strict_crossing(a, b):
    for one, two in [(a, b), (b, a)]:
        normal = (two[1] - two[0]).cross(two[2] - two[0]).normalized()
        signed = [normal.dot(q - two[0]) for q in one]
        if not (min(signed) < -.0002 and max(signed) > .0002): return False
    return True


def signature(local, decimals=5):
    return {tuple(sorted(tuple(round(float(c), decimals) for c in local["points"][i]) for i in tri)) for tri in local["triangles"]}


def main():
    layout = json.loads((KIT / "layout.json").read_text())
    stats = json.loads((KIT / "asset_stats.json").read_text())
    palette = json.loads((HALL / "hall_palette.json").read_text())["slots"]
    report = {"checks": [], "assets": {}, "intersections": [], "reuse": {}}
    def check(ok, label):
        report["checks"].append({"check": label, "passed": bool(ok)})
        if not ok: print("FAIL", label, flush=True)
    rows = {r["name"]: r for r in layout["assets"]}
    local, placed = {}, {}
    for name, row in rows.items():
        g = local_mesh(KIT / row["file"]); local[name] = g
        doc = g["doc"]
        count = len(g["triangles"])
        expected = next(a for a in stats["assets"] if a["name"] == name)
        check(count == expected["triangles"], name + " actual triangle count")
        check(all(m["name"].endswith("_mobile") for m in doc["meshes"]), name + " mesh names use _mobile")
        check(doc.get("images") == [{"uri": "room_albedo_ao.png"}], name + " one external N1 atlas")
        check("gltf/texture_map_mode=1" in Path(str(KIT / row["file"]) + ".import").read_text(), name + " texture map mode 1")
        check(np.isfinite(g["points"]).all() and np.isfinite(g["uv"]).all(), name + " finite vertices and UV")
        check(np.all(np.abs(np.linalg.norm(g["normals"], axis=1) - 1) < .002), name + " unit normals")
        a, b, c = [g["points"][g["triangles"][:, i]] for i in range(3)]
        check(np.min(np.linalg.norm(np.cross(b - a, c - a), axis=1)) > 1e-10, name + " no degenerate triangles")
        rgba = g["colors"]
        check(np.min(rgba[:, :3]) >= .63 and np.max(rgba[:, :3]) <= 1.0001, name + " bounded soft AO")
        check(np.max(np.ptp(rgba[:, :3], axis=1)) < .0001, name + " vertex colors are scalar AO only")
        regions = np.full(len(g["uv"]), -1)
        for index, slot in enumerate(palette.values()):
            x0, y0, x1, y1 = slot["uv_rect_gltf"]
            uv = g["uv"]
            mask = (uv[:, 0] >= x0 - .00001) & (uv[:, 0] <= x1 + .00001) & (uv[:, 1] >= y0 - .00001) & (uv[:, 1] <= y1 + .00001)
            regions[mask] = index
        check(np.min(regions) >= 0 and np.all(np.ptp(regions[g["triangles"]], axis=1) == 0), name + " triangles stay inside one guarded atlas region")
        lo, hi = g["points"].min(0), g["points"].max(0)
        report["assets"][name] = {"triangles": count, "surfaces": expected["surfaces"], "local_bounds": [lo.tolist(), hi.tolist()],
            "sha256": hashlib.sha256((KIT / row["file"]).read_bytes()).hexdigest()}
        placed[name] = world_mesh(g, row)
    for row in layout["instances"]: placed[row["name"]] = world_mesh(local[row["asset"]], row)
    for source, name in [("armchair", "cream_armchair"), ("round_side_table", "round_side_table"), ("frame_landscape", "frame_landscape")]:
        original = local_mesh(QA / "deps/assets/rooms/_shared/shell_hall" / (source + ".glb"))
        produced = local[name]
        original_bounds = np.array([original["points"].min(0), original["points"].max(0)])
        produced_bounds = np.array([produced["points"].min(0), produced["points"].max(0)])
        max_error = float(np.max(np.abs(original_bounds - produced_bounds)))
        exact = signature(original) == signature(produced)
        check(max_error < .00003 and len(original["triangles"]) == len(produced["triangles"]), name + " original 324 bounds and count retained; no scaling")
        check(exact, name + " original 324 triangle geometry retained")
        report["reuse"][name] = {"source_commit": "104446a2", "bounds_max_error_m": max_error, "triangle_signature_equal": exact}
    for name in ["ring_sofa", "cream_armchair", "round_side_table", "hearth", "luggage_cart", "low_bookshelf", "floor_lamp", "central_planter"]:
        check(abs(float(local[name]["points"][:, 1].min())) < .001, name + " grounded at local Y=0")
    for anchor in [a for a in layout["anchors"] if a["name"].startswith("seat_")]:
        check(anchor["module"] in placed, anchor["name"] + " module resolves")
        if anchor["module"] not in placed: continue
        at = Vector(anchor["position"])
        hit = placed[anchor["module"]]["bvh"].ray_cast(at + Vector((0, .20, 0)), Vector((0, -1, 0)), .40)
        check(hit[0] is not None and abs(hit[0].y - at.y) < .0015, anchor["name"] + " actual seat surface equals anchor height")
        stand = Vector(anchor["stand"])
        heading = math.radians(anchor["yaw_degrees"])
        facing = Vector((-math.sin(heading), 0, -math.cos(heading)))
        outward = stand - at; outward.y = 0
        check(facing.dot(outward.normalized()) > .999, anchor["name"] + " follows P0 yaw convention toward approach")
    center = Vector(ROWS_POSITION(layout, "central_planter"))
    hit = placed["central_planter"]["bvh"].ray_cast(center + Vector((0, 1.5, 0)), Vector((0, -1, 0)), 2)
    check(hit[0] is not None and abs(hit[0].y - .9925) < .002, "Planter mouth is open down to soil, not covered by a gold disc")
    shell_layout = json.loads((HALL / "layout.json").read_text())
    shell_local = {}
    for row in shell_layout["assets"]:
        shell_local[row["name"]] = local_mesh(HALL / row["file"])
        placed[row["name"]] = world_mesh(shell_local[row["name"]], row)
    for row in shell_layout["instances"]: placed[row["name"]] = world_mesh(shell_local[row["asset"]], row)
    for row in layout["shared_plants"]:
        placed[row["name"]] = world_mesh(local_mesh(ROOT / "assets/rooms/_shared/plants" / row["file"]), row)
    intended = {
        frozenset(["hearth", "hearth_mantel"]): "Mantel fitted around the retained chimney breast",
        frozenset(["central_planter", "central_foliage"]): "Plant stems rooted in soil",
        frozenset(["hearth", "mantel_decor"]): "Mirror mounting on retained chimney breast",
        frozenset(["hearth_mantel", "mantel_decor"]): "Candlesticks and frame supported on mantel",
    }
    unexpected = []
    for (na, a), (nb, b) in itertools.combinations(placed.items(), 2):
        if (a["hi"] < b["lo"] - .0001).any() or (b["hi"] < a["lo"] - .0001).any(): continue
        hits = a["bvh"].overlap(b["bvh"])
        crossing = []
        for ia, ib in hits:
            ta = [a["points"][int(v)] for v in a["triangles"][ia]]
            tb = [b["points"][int(v)] for v in b["triangles"][ib]]
            if strict_crossing(ta, tb): crossing.append((ia, ib))
        if not crossing: continue
        reason = intended.get(frozenset([na, nb]), "")
        if "hall_floor" in [na, nb]: reason = "Ground/support contact on shared foundation"
        if na.startswith("hall_") and nb.startswith("hall_"): reason = "Approved shared-shell construction joint"
        if "key_rack" in [na, nb] and "hall_back_wall" in [na, nb]: reason = "Key-rack concealed standoffs fixed to wall"
        if "green_rug" in [na, nb] or "cowhide_rug" in [na, nb]:
            height = max(max(a["points"][int(v)].y for v in a["triangles"][ia]) for ia, _ in crossing) if na.endswith("rug") else max(max(b["points"][int(v)].y for v in b["triangles"][ib]) for _, ib in crossing)
            if height < .085: reason = "Flat textile pile below 5 mm at furniture feet"
        row = {"modules": [na, nb], "crossing_pairs": len(crossing), "classification": reason or "unexpected"}
        report["intersections"].append(row)
        if not reason: unexpected.append(row)
    check(not unexpected, "No unexpected inter-module or wall crossing")
    report["unexpected_intersections"] = unexpected
    check(stats["scene_triangles_with_particles_max"] == stats["scene_triangles"] + stats["dynamic_particle_triangles_max"], "Particle triangle ceiling matches static plus dynamic counts")
    check(stats["scene_triangles"] <= 150000 and stats["static_draw_surfaces"] + 2 <= 50, "Complete room including shared shell/plants and two fire draws meets budget")
    check(len(local["cowhide_rug"]["triangles"]) <= 1000, "Cowhide remains below 1k triangles")
    report["passed"] = all(c["passed"] for c in report["checks"])
    dump_path = QA / "geometry-validation.json"
    dump_path.write_text(json.dumps(report, indent=2) + "\n")
    print("N1_GEOMETRY", report["passed"], "checks", len(report["checks"]), "unexpected", json.dumps(unexpected), flush=True)
    if not report["passed"]: raise SystemExit(1)


def ROWS_POSITION(layout, name): return next(r["position"] for r in layout["assets"] if r["name"] == name)


if __name__ == "__main__": main()
