"""Conservative full furniture footprints before N1 detailing. Shapely buffers are capsule radii."""
from pathlib import Path
import json
import math
import sys

import numpy as np
import shapely
from shapely import affinity
from shapely.geometry import Point, box
from shapely.ops import unary_union
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
PLAN = ROOT / "tools/art/source/poi_hotel_lobby/layout_plan.json"
OUT = ROOT / "output/hotel-lobby-319/plan"


def shape(row):
    x, _, z = row["position"]
    if row["shape"] == "circle": return Point(x, z).buffer(row["radius"], quad_segs=64)
    width, _, depth = row["size"]
    dx, _, dz = row.get("shape_offset", [0, 0, 0])
    rect = box(dx - width / 2, dz - depth / 2, dx + width / 2, dz + depth / 2)
    return affinity.translate(affinity.rotate(rect, -row.get("yaw_degrees", 0), origin=(0, 0)), xoff=x, yoff=z)


def component(geometry, point):
    candidates = list(geometry.geoms) if hasattr(geometry, "geoms") else [geometry]
    return next((g for g in candidates if g.buffer(1e-6).covers(point)), None)


def main():
    plan = json.loads(PLAN.read_text())
    floor = box(*plan["inner_floor"])
    props = {r["name"]: shape(r) for r in plan["placements"] if "contained_by" not in r}
    rows = {r["name"]: r for r in plan["placements"]}
    blocked = unary_union(list(props.values()))
    spawn = Point(plan["spawn"][0], plan["spawn"][2])
    free = floor.buffer(-.25).difference(blocked.buffer(.25))
    main_free = floor.buffer(-.35).difference(blocked.buffer(.35))
    walkable = component(free, spawn)
    main_walkable = component(main_free, spawn)
    overlaps = []
    names = list(props)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            area = props[a].intersection(props[b]).area
            if area > .00005: overlaps.append({"a": a, "b": b, "area": area})
    seats = []
    sofa = rows["ring_sofa"]
    for i, angle in enumerate(sofa["seat_angles"], 1):
        a = math.radians(angle)
        seats.append({"name": "seat_sofa_" + str(i), "module": "ring_sofa", "yaw_degrees": (angle + 180) % 360,
            "position": [sofa["position"][0] + .94 * math.sin(a), .795, sofa["position"][2] + .94 * math.cos(a)],
            "stand": [sofa["position"][0] + 1.615 * math.sin(a), .08, sofa["position"][2] + 1.615 * math.cos(a)]})
    for i, name in enumerate(["armchair_back", "armchair_front"], 1):
        row = rows[name]
        a = math.radians(row["yaw_degrees"])
        seats.append({"name": "seat_armchair_" + str(i), "module": name, "yaw_degrees": (row["yaw_degrees"] + 180) % 360,
            "position": [row["position"][0] + .22 * math.sin(a), .795, row["position"][2] + .22 * math.cos(a)],
            "stand": [row["position"][0] + .80 * math.sin(a), .08, row["position"][2] + .80 * math.cos(a)]})
    for seat in seats:
        pt = Point(seat["stand"][0], seat["stand"][2])
        seat["reachable_radius_025"] = walkable is not None and walkable.covers(pt)
        seat["reachable_main_070"] = main_walkable is not None and main_walkable.covers(pt)
        seat["clearance_m"] = min(floor.boundary.distance(pt), blocked.distance(pt))
    samples = []
    if walkable is not None:
        candidates = [(x, z) for z in np.arange(-2.5, 2.91, .27) for x in np.arange(-2.6, 3.0, .27)
            if walkable.buffer(-.03).contains(Point(x, z))]
        # Farthest-first verifies one explicit set of simultaneously clear standing capsules.
        chosen = [(spawn.x, spawn.y)]
        while candidates and len(chosen) < 16:
            best = max(candidates, key=lambda p: min(math.dist(p, q) for q in chosen))
            if min(math.dist(best, q) for q in chosen) < .55: break
            chosen.append(best)
            candidates.remove(best)
        samples = [[round(x, 4), .08, round(z, 4)] for x, z in chosen]
    report = {"source": str(PLAN.relative_to(ROOT)), "method": "Shapely full furniture silhouette buffers; .35 m radius tests .70 m passages",
        "body_radius": .25, "main_passage_radius": .35, "overlaps": overlaps, "seats": seats, "standing_16": samples,
        "body_walkable_area": walkable.area if walkable is not None else 0,
        "main_walkable_area": main_walkable.area if main_walkable is not None else 0,
        "all_seats_reachable": all(s["reachable_radius_025"] for s in seats),
        "main_target": [rows["elevator"]["position"][0], .08, rows["elevator"]["position"][2] + .58],
        "main_reaches_back": main_walkable is not None and main_walkable.covers(Point(rows["elevator"]["position"][0], rows["elevator"]["position"][2] + .58))}
    report["passed"] = not overlaps and len(samples) == 16 and report["all_seats_reachable"] and report["main_reaches_back"]
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "plan-validation.json").write_text(json.dumps(report, indent=2) + "\n")
    step = .02
    x0, z0, x1, z1 = plan["inner_floor"]
    width, depth = math.ceil((x1 - x0) / step), math.ceil((z1 - z0) / step)
    zz, xx = np.mgrid[0:depth, 0:width]
    grids = []
    for radius, region in [(.25, free), (.35, main_free)]:
        mask = shapely.contains_xy(region, x0 + xx * step, z0 + zz * step).ravel()
        grids.append({"radius": radius, "blocked": np.flatnonzero(~mask).tolist()})
    fixture = {"plan": plan, "analysis": report, "grid": {"step": step, "width": width, "depth": depth, "origin": [x0, z0], "modes": grids}}
    (OUT / "physics-fixture.json").write_text(json.dumps(fixture) + "\n")
    image = Image.new("RGB", (1300, 1380), "#F4F4F1")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 19)
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    def project(x, z): return 110 + (x + 3.4) * 155, 90 + (z + 3.2) * 155
    def polygon(geo, fill, outline=None):
        for p in (list(geo.geoms) if hasattr(geo, "geoms") else [geo]):
            if p.is_empty or not hasattr(p, "exterior"): continue
            draw.polygon([project(*q) for q in p.exterior.coords], fill=fill, outline=outline)
    polygon(floor, "#D8CBB1", "#66665F")
    if main_walkable is not None: polygon(main_walkable, "#C9E8D5")
    if main_walkable is not None:
        for interior in main_walkable.interiors: draw.polygon([project(*q) for q in interior.coords], fill="#D8CBB1")
    for name, geo in props.items():
        polygon(geo, "#849981" if name == "ring_sofa" else "#C6AC83", "#5F6559")
        center = geo.centroid
        draw.text(project(center.x - .25, center.y - .06), name.replace("table_", "T_"), fill="#263E35", font=small)
    for seat in seats:
        x, y = project(seat["stand"][0], seat["stand"][2])
        draw.ellipse((x - 12, y - 12, x + 12, y + 12), fill="#FFFFFF", outline="#24794A" if seat["reachable_radius_025"] else "#D22323", width=3)
    for i, pos in enumerate(samples, 1):
        x, y = project(pos[0], pos[2])
        draw.ellipse((x - .25 * 155, y - .25 * 155, x + .25 * 155, y + .25 * 155), outline="#306CBA", width=2)
        draw.text((x - 8, y - 8), str(i), fill="#244E83", font=small)
    draw.text((60, 20), "SGODOT-319 / ZHAOYUN - Full-size circulation and standing clearance", fill="#263E35", font=font)
    lines = ["Armchair 1.50 x 0.89 m | N1 side table diameter 0.70 m, height 0.90 m",
        "Green area: reachable .70 m main-passage centers | Blue: 16 standing capsules",
        f'PASS={report["passed"]} | overlaps={len(overlaps)} | seat approaches={sum(s["reachable_radius_025"] for s in seats)}/8',
        "Red approach rings identify inaccessible positions; conservative full-height footprints."]
    for i, line in enumerate(lines): draw.text((60, 1125 + i * 40), line, fill="#263E35", font=font)
    image.save(OUT / "full-size-plan.png")
    print(json.dumps({k: v for k, v in report.items() if k not in ["standing_16", "seats"]}, indent=2))
    print("SEATS", [(s["name"], s["reachable_radius_025"], s["reachable_main_070"], round(s["clearance_m"], 3)) for s in seats])
    if not report["passed"]: sys.exit(1)


if __name__ == "__main__": main()
