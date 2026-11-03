"""Assemble the approved N3 display kit without rewriting supplier assets."""
from copy import deepcopy
from pathlib import Path
import hashlib
import json
import math
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
KIT = ROOT / "assets/rooms/poi_culture_hall"
APPROVED_PROPS_COMMIT = "c46e8e374867bb083032d519776b6614bd74a674"
sys.path.insert(0, str(ROOT / "tools/art"))
from verify_chef_sign import load_glb


def dump(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def transform(point, row):
    a = math.radians(row.get("yaw_degrees", 0))
    x, y, z = point
    return [row["position"][0] + x * math.cos(a) + z * math.sin(a),
            row["position"][1] + y,
            row["position"][2] - x * math.sin(a) + z * math.cos(a)]


def assemble():
    plan = json.loads((KIT / "layout.json").read_text())
    white = json.loads((HERE / "layout_plan.json").read_text())
    placeholders = {r["name"]: r for r in white["placements"]}
    manifest = json.loads((KIT / "props/prop_manifest.json").read_text())
    assets = {a["name"]: a for a in manifest["assets"]}
    rows = [deepcopy(r) for r in plan["placements"] if r["owner"] == "zhaoyun"]
    placed = {r["name"]: r for r in rows}

    def place(asset_name, name, position, yaw=0, **extra):
        spec = assets[asset_name]
        row = dict(name=name, model="props/" + asset_name, position=position,
                   size=spec["dimensions_m"], yaw_degrees=yaw, model_scale=[1, 1, 1],
                   bounds=spec["bounds"], origin=spec["origin"],
                   role=spec["description"], owner="huangzhong",
                   collidable=bool(spec.get("colliders")),
                   colliders=deepcopy(spec.get("colliders", [])), **extra)
        rows.append(row)
        placed[name] = row
        return row

    for name in assets["display_cabinet"]["instance_ids"]:
        old = placeholders[name]
        place("display_cabinet", name, old["position"], old["yaw_degrees"],
              support_height=assets["display_cabinet"]["display_height_m"])
    old = placeholders["display_plinth"]
    place("exhibit_plinth", "display_plinth", old["position"], old["yaw_degrees"],
          support_height=assets["exhibit_plinth"]["display_height_m"])
    for spec in manifest["assets"]:
        assignment = spec.get("display_assignment")
        if not assignment:
            continue
        parent = placed[assignment["container"]]
        place(spec["name"], assignment["instance_name"], transform(assignment["position"], parent),
              parent["yaw_degrees"] + assignment["yaw_degrees"], support=parent["name"],
              support_local_position=assignment["position"])
    old = placeholders["floor_mosaic"]
    place("floor_mosaic", "floor_mosaic", old["position"], old["yaw_degrees"], shape="circle")

    # The supplier now owns the relative six-frame arrangement. Keep the approved
    # gallery centre, converting the white boxes' bottom pivots to a back-centre.
    frames = [placeholders[f"artwork_{i}"] for i in range(1, 7)]
    centre = [sum(r["position"][0] for r in frames) / 6,
              (min(r["position"][1] for r in frames) + max(r["position"][1] + r["size"][1] for r in frames)) / 2,
              min(r["position"][2] - r["size"][2] / 2 for r in frames)]
    place("artwork_set", "artwork_set", centre)
    old = placeholders["name_sign"]
    sign = place("name_sign", "name_sign", [old["position"][0], old["position"][1] + old["size"][1] / 2,
                                             old["position"][2] - old["size"][2] / 2], old["yaw_degrees"])
    local_anchor = next(a for a in assets["name_sign"]["anchors"] if a["name"] == "sign_door")
    for anchor in plan["anchors"]:
        if anchor["name"] == "sign_door":
            anchor.update(position=transform(local_anchor["position"], sign), size=local_anchor["size"],
                          yaw_degrees=sign["yaw_degrees"] + local_anchor["yaw_degrees"], module="name_sign")

    own_assets = [a for a in plan["assets"] if not a["name"].startswith(("props/", "blockout_"))]
    prop_assets = [dict(a, name="props/" + a["name"], file="props/" + a["file"],
                        supplier_asset=a["name"]) for a in manifest["assets"]]
    plan.update(stage="detail_v1.1", placements=rows, assets=own_assets + prop_assets, models={},
                source_ownership=dict(zhaoyun="Hall skin, six reusable modules, assembly and validation",
                                      huangzhong="Approved props and editable sources copied byte-for-byte; individual glass materials retained"),
                props_dependency=dict(branch="wp-3d-scene-huangzhong-culture-323", commit=APPROVED_PROPS_COMMIT,
                                      manifest="props/prop_manifest.json", technical_approval="Base display kit: 323 8d679529 / 7aa982a6",
                                      integration_authorization="Director v1.1 dispatch: integrate Huangzhong's recoloured mosaic after push; supplier delivery 443e7292",
                                      revision=manifest["revision"], notes="1.4x exhibits with .06 m pedestals; mosaic v1.2 warm cream/terracotta concentric colour rings, geometry unchanged"),
                height_assumptions=dict(case_top=1.50, case_display_surface=1.00, plinth_top=1.10,
                                        artwork_group_center_y=centre[1], artwork_group_height=1.25,
                                        sign_center_y=sign["position"][1], track_y=3.49))
    costs = {}
    for asset in plan["assets"]:
        path = KIT / asset["file"]
        doc, _ = load_glb(path)
        primitives = [p for m in doc["meshes"] for p in m["primitives"]]
        raw = dict(triangles=sum(doc["accessors"][p["indices"]]["count"] // 3 for p in primitives),
                   surfaces=len(primitives), sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        assert all(asset[k] == raw[k] for k in raw), (asset["name"], raw)
        costs[asset["name"]] = raw
    shell = json.loads((ROOT / "assets/rooms/_shared/shell_hall/shell_asset_stats.json").read_text())
    stats = dict(stage="detail_v1.1", assets=plan["assets"], shared_shell=shell,
                 scene_triangles=shell["scene_triangles"] + sum(costs[r["model"]]["triangles"] for r in rows),
                 static_draw_surfaces=shell["static_draw_surfaces"] + sum(costs[r["model"]]["surfaces"] for r in rows),
                 atlas=dict(file="room_albedo_ao.png", size=[2048, 2048], botanical_alpha_scissor=.45,
                            supplier_props="linear vertex colours; no additional textures"),
                 props_dependency=plan["props_dependency"])
    assert stats["scene_triangles"] <= 150000 and stats["static_draw_surfaces"] <= 50
    dump(KIT / "layout.json", plan)
    dump(KIT / "asset_stats.json", stats)
    print("CULTURE_ASSEMBLY", stats["scene_triangles"], "triangles", stats["static_draw_surfaces"], "surfaces", len(rows), "placements")
    return plan


if __name__ == "__main__":
    assemble()
