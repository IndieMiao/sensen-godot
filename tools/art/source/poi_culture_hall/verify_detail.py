"""Verify the supplier handoff, real bounds, support and final-room invariants."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys
import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
KIT = ROOT / "assets/rooms/poi_culture_hall"
QA = ROOT / "output/culture-hall-323"
sys.path.insert(0, str(ROOT / "tools/art"))
from verify_chef_sign import load_glb, accessor
from assemble_v1 import APPROVED_PROPS_COMMIT, transform


def main():
    plan = json.loads((KIT / "layout.json").read_text())
    manifest = json.loads((KIT / "props/prop_manifest.json").read_text())
    rows = {r["name"]: r for r in plan["placements"]}
    assets = {a["name"]: a for a in plan["assets"]}
    specs = {a["name"]: a for a in manifest["assets"]}
    baseline = json.loads(subprocess.check_output(["git", "show", "fa0f5e08:assets/rooms/poi_culture_hall/layout.json"], cwd=ROOT))
    checks, measurements = [], {}

    def check(ok, label):
        checks.append(dict(check=label, passed=bool(ok)))
        if not ok:
            print("FAIL", label)

    pinned_files = {}
    for directory in ["assets/rooms/poi_culture_hall/props", "tools/art/source/poi_culture_hall/props"]:
        files = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", APPROVED_PROPS_COMMIT, directory], cwd=ROOT, text=True).splitlines()
        check(set(files) == {str(p.relative_to(ROOT)) for p in (ROOT / directory).rglob("*") if p.is_file()}, "supplier file inventory: " + directory)
        for name in files:
            original = subprocess.check_output(["git", "show", APPROVED_PROPS_COMMIT + ":" + name], cwd=ROOT)
            data = (ROOT / name).read_bytes()
            check(data == original, "supplier byte-identical: " + name)
            pinned_files[name] = hashlib.sha256(data).hexdigest()
    for old in baseline["placements"]:
        if old["owner"] == "zhaoyun":
            check(rows[old["name"]] == old, "approved independent placement unchanged: " + old["name"])
    for old in baseline["assets"]:
        if old["name"].startswith("blockout_"):
            continue
        for suffix in ["", ".import"]:
            rel = "assets/rooms/poi_culture_hall/" + old["file"] + suffix
            check((ROOT / rel).read_bytes() == subprocess.check_output(["git", "show", "fa0f5e08:" + rel], cwd=ROOT), "approved independent file unchanged: " + old["file"] + suffix)
    check(not any(r["model"].startswith("blockout_") for r in rows.values()), "no gray proxy instances")
    check(not any(re.fullmatch(r"artwork_[1-6]|case_[12]_exhibit_[1-3]", n) for n in rows), "old six-frame and six-exhibit placements removed")
    check(len([r for r in rows.values() if r["owner"] == "huangzhong"]) == 9, "nine supplier instances")
    check(sum(len(specs[n]["components"]) for n in ["case_exhibits_1", "case_exhibits_2"]) == 6, "six individual cabinet exhibits inside two groups")

    geometry, uids, costs = {}, {}, {}
    for key, spec in assets.items():
        path = KIT / spec["file"]
        doc, blob = load_glb(path)
        primitives = [p for m in doc["meshes"] for p in m["primitives"]]
        points = np.concatenate([np.asarray(accessor(doc, blob, p["attributes"]["POSITION"])) for p in primitives])
        geometry[key] = points
        triangles = sum(len(accessor(doc, blob, p["indices"])) // 3 for p in primitives)
        costs[key] = dict(triangles=triangles, surfaces=len(primitives))
        check(np.isfinite(points).all(), key + " finite vertices")
        check(len(doc["meshes"]) == 1 and doc["meshes"][0]["name"] == key.split("/")[-1] + "_mobile", key + " named single mobile mesh")
        check(triangles == spec["triangles"] and len(primitives) == spec["surfaces"], key + " raw cost")
        check(np.allclose([points.min(0), points.max(0)], spec["bounds"], atol=2e-6), key + " raw bounds match manifest")
        if key.startswith("props/"):
            check(not doc.get("images") and not doc.get("textures"), key + " vertex colour without extra textures")
            check(all("COLOR_0" in p["attributes"] for p in primitives), key + " authored vertex colours")
        text = Path(str(path) + ".import").read_text()
        match = re.search(r'^uid="(uid://[^\"]+)"', text, re.M)
        check(match is not None and match.group(1) not in uids.values(), key + " unique import UID")
        if match:
            uids[str(Path(str(path) + ".import"))] = match.group(1)
        check("gltf/texture_map_mode=1" in text, key + " texture_map_mode=1")
    for path in (ROOT / "assets").rglob("*.import"):
        if str(path) in uids:
            continue
        match = re.search(r'^uid="(uid://[^\"]+)"', path.read_text(), re.M)
        if match and match.group(1) in uids.values():
            check(False, "UID collision outside kit: " + str(path))

    support = []
    for spec in manifest["assets"]:
        assignment = spec.get("display_assignment")
        if not assignment:
            continue
        row, parent = rows[assignment["instance_name"]], rows[assignment["container"]]
        check(np.allclose(row["position"], transform(assignment["position"], parent)), row["name"] + " supplier local mount")
        check(np.allclose(row["model_scale"], [1, 1, 1]), row["name"] + " supplier size retained")
        points = geometry[row["model"]] + np.asarray(assignment["position"])
        container = specs[assignment["container_asset"]]
        top = container["display_height_m"]
        check(abs(points[:, 1].min() - top) < 1e-5, row["name"] + " bottom rests on actual display surface")
        if "interior_bounds" in container:
            lo, hi = np.asarray(container["interior_bounds"])
            clearance = np.minimum(points.min(0) - lo, hi - points.max(0))
            check(clearance.min() >= -1e-5, row["name"] + " inside glass hood")
            support.append(dict(name=row["name"], clearance_to_hood_xyz=clearance.tolist()))
        else:
            lo, hi = np.asarray(container["bounds"])
            check(np.all(points.min(0)[[0, 2]] >= lo[[0, 2]]) and np.all(points.max(0)[[0, 2]] <= hi[[0, 2]]), row["name"] + " supported within plinth")
    for name in ["glass_case_1", "glass_case_2", "display_plinth"]:
        row = rows[name]
        spec = specs[row["model"].split("/")[-1]]
        check(row["colliders"] == spec["colliders"], name + " exact supplier colliders")
        old = next(r for r in baseline["placements"] if r["name"] == name)
        check(row["position"] == old["position"] and row["yaw_degrees"] == old["yaw_degrees"], name + " approved floor pivot and facing unchanged")

    shell = json.loads((ROOT / "assets/rooms/_shared/shell_hall/layout.json").read_text())
    wall_spec = next(a for a in shell["assets"] if a["name"] == "hall_back_wall")
    doc, blob = load_glb(ROOT / "assets/rooms/_shared/shell_hall" / wall_spec["file"])
    wall = np.concatenate([np.asarray(accessor(doc, blob, p["attributes"]["POSITION"])) for m in doc["meshes"] for p in m["primitives"]]) + wall_spec["position"]
    front = float(wall[wall[:, 1] < .38, 2].max())
    case = rows["glass_case_2"]
    back = float(geometry[case["model"]][:, 2].min() + case["position"][2])
    clearance = back - front
    check(clearance >= 2, "actual case2 mesh clears actual back-wall skirting by 2 m")
    measurements["rear_clearance"] = dict(skirting_front_z=front, case2_back_z=back, net_m=clearance)
    for name in ["artwork_set", "name_sign"]:
        row = rows[name]
        world = geometry[row["model"]] + row["position"]
        check(world[:, 2].min() >= -3 and world[:, 0].min() >= -3.2 and world[:, 0].max() <= 3.4, name + " clears wall plane and ends")
        check(world[:, 1].min() > 1.1525 and world[:, 1].max() < 3.4625, name + " between wainscot and cornice")
        measurements[name + "_world_bounds"] = [world.min(0).tolist(), world.max(0).tolist()]
    anchor = next(a for a in plan["anchors"] if a["name"] == "sign_door")
    local = specs["name_sign"]["anchors"][0]
    check(np.allclose(anchor["position"], transform(local["position"], rows["name_sign"])) and anchor["size"] == local["size"], "runtime sign mount and writable area match supplier")
    statistics = json.loads((KIT / "asset_stats.json").read_text())
    totals = dict(triangles=statistics["shared_shell"]["scene_triangles"] + sum(costs[r["model"]]["triangles"] for r in rows.values()),
                  surfaces=statistics["shared_shell"]["static_draw_surfaces"] + sum(costs[r["model"]]["surfaces"] for r in rows.values()))
    check(totals == dict(triangles=statistics["scene_triangles"], surfaces=statistics["static_draw_surfaces"]), "total instanced budget from raw GLB indices")
    report = dict(passed=all(c["passed"] for c in checks), checks=checks, measurements=measurements,
                  support=support, totals=totals, import_uids=uids,
                  approved_supplier_commit=APPROVED_PROPS_COMMIT, supplier_files_sha256=pinned_files)
    (QA / "detail-assets.json").write_text(json.dumps(report, indent=2) + "\n")
    print("CULTURE_DETAIL_AUDIT", report["passed"], len(checks), "checks", totals, "rear net", clearance)
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
