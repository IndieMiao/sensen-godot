"""Conservative furniture footprints; capsule-centre connectivity at .25 and .35 m."""
from pathlib import Path
import json
import math
import numpy as np
import shapely
from shapely.geometry import Point,box
from shapely.ops import unary_union
from shapely.affinity import rotate

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/"output/classroom-322"
def shape(row):
    x,_,z=row["position"];w,h,d=row["size"]
    geometry=Point(x,z).buffer(w/2,quad_segs=48) if row["model"] in ["blockout_student_stool","blockout_cylinder"] else box(x-w/2,z-d/2,x+w/2,z+d/2)
    return rotate(geometry,-row.get("yaw_degrees",0),origin=(x,z))
def component(region,point):
    return next((p for p in getattr(region,"geoms",[region]) if p.covers(point)),None)
def main():
    plan=json.loads((ROOT/"assets/rooms/poi_classroom/layout.json").read_text())
    floor=box(*plan["inner_floor"]);rows={r["name"]:r for r in plan["placements"] if r["collidable"]}
    shapes={name:shape(row) for name,row in rows.items()};blocked=unary_union(list(shapes.values()))
    overlap=[]
    support=[]
    all_rows={r["name"]:r for r in plan["placements"]}
    for row in plan["placements"]:
        if "support" not in row:continue
        parent=all_rows[row["support"]]
        supported=shape(parent).covers(shape(row)) and abs(row["position"][1]-parent["position"][1]-parent["size"][1])<.001
        support.append({"name":row["name"],"support":parent["name"],"passed":supported})
    for i,name in enumerate(shapes):
        assert floor.covers(shapes[name]),(name,"outside floor")
        for other in list(shapes)[:i]:
            area=shapes[name].intersection(shapes[other]).area
            if area>1e-7:overlap.append([name,other,area])
    spawn=Point(plan["spawn"][0],plan["spawn"][2]);seats=[a for a in plan["anchors"] if a["name"].startswith("seat_")]
    targets=[{"name":s["name"],"position":s["stand"]} for s in seats]
    targets += [{"name":"central_aisle","position":[.50,.08,.55]},
                {"name":"reading_aisle","position":[-1.43,.08,-.73]},
                {"name":"right_aisle","position":[2.75,.08,-.50]},
                {"name":"teaching_cross_aisle","position":plan["main_target"]},
                {"name":"exit","position":plan["exit"],"main_position":[.50,.08,2.74]}]
    regions={r:component(floor.buffer(-r-.003).difference(blocked.buffer(r+.003,quad_segs=48)),spawn) for r in [.25,.35]}
    results=[]
    for radius,region in regions.items():
        for target in targets:
            at=target.get("main_position",target["position"]) if radius==.35 else target["position"]
            p=Point(at[0],at[2])
            results.append({"radius":radius,"target":target["name"],"position":at,"reachable":region is not None and region.covers(p),
                "clearance_m":min(floor.boundary.distance(p),blocked.distance(p))})
    region=regions[.25];chosen=[(spawn.x,spawn.y)]
    candidates=[(float(x),float(z)) for z in np.arange(-2.7,2.91,.16) for x in np.arange(-2.9,3.1,.16) if region is not None and region.buffer(-.025).contains(Point(x,z))]
    while candidates and len(chosen)<16:
        p=max(candidates,key=lambda p:min(math.dist(p,q) for q in chosen))
        if min(math.dist(p,q) for q in chosen)<.55:break
        chosen.append(p);candidates.remove(p)
    corridors={"central":shapes["desk_2"].bounds[0]-shapes["desk_1"].bounds[2],
        "reading_corner":shapes["desk_1"].bounds[0]-shapes["proxy_cushion_2"].bounds[2],
        "left_longitudinal":shapes["desk_3"].bounds[0]-shapes["low_cabinet_1"].bounds[2],
        "right_longitudinal":floor.bounds[2]-shapes["desk_4"].bounds[2],
        "front_cross":floor.bounds[3]-shapes["stool_5"].bounds[3],
        "teaching_cross":shapes["desk_1"].bounds[1]-shapes["proxy_teacher_desk"].bounds[3]}
    report={"passed":not overlap and all(r["reachable"] for r in results) and all(r["passed"] for r in support) and len(chosen)==16 and min(corridors.values())>=.7,
        "method":"Full-height furniture footprints, Shapely capsule-centre buffers; main aisles .35m radius",
        "overlap":overlap,"support":support,"routes":results,"main_corridors_m":corridors,
        "standing_16":[[round(x,4),.08,round(z,4)] for x,z in chosen],"seat_count":len(seats),
        "seat_surface_y":.795,"seat_height_above_floor":.715,
        "scope":"Longitudinal and front/rear cross aisles. Desk/stool pockets are seating areas, approached from centre aisle."}
    step=.02;x0,z0,x1,z1=plan["inner_floor"];width=round((x1-x0)/step)+1;depth=round((z1-z0)/step)+1
    zz,xx=np.mgrid[0:depth,0:width];modes=[]
    for radius,region in regions.items():
        mask=shapely.contains_xy(region,x0+xx*step,z0+zz*step).ravel() if region else np.zeros(width*depth,dtype=bool)
        modes.append({"radius":radius,"blocked":np.flatnonzero(~mask).tolist()})
    QA.mkdir(parents=True,exist_ok=True)
    (QA/"plan-validation.json").write_text(json.dumps(report,indent=2)+"\n")
    fixture={"plan":plan,"analysis":report,"targets":targets,"grid":{"step":step,"width":width,"depth":depth,"origin":[x0,z0],"modes":modes}}
    (QA/"navigation-fixture.json").write_text(json.dumps(fixture)+"\n")
    print("CLASSROOM_PLAN",report["passed"],"corridors",corridors,"standing",len(chosen))
    print("TARGETS",[(r["target"],r["radius"],r["reachable"],round(r["clearance_m"],3)) for r in results])
    if not report["passed"]:raise SystemExit(1)
if __name__=="__main__":main()
