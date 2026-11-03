"""N3 rear-band, support, direct-route and capsule-centre checks."""
from pathlib import Path
import json
import math
import numpy as np
import shapely
from shapely.geometry import Point,box,LineString
from shapely.ops import unary_union
from shapely.affinity import rotate

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/"output/culture-hall-323"
def shape(row):
    x,_,z=row["position"];w,h,d=row["size"]
    geometry=Point(x,z).buffer(w/2,quad_segs=48) if row.get("shape")=="circle" else box(x-w/2,z-d/2,x+w/2,z+d/2)
    return rotate(geometry,-row.get("yaw_degrees",0),origin=(x,z))
def component(region,point):return next((p for p in getattr(region,"geoms",[region]) if p.covers(point)),None)
def main():
    plan=json.loads((ROOT/"assets/rooms/poi_culture_hall/layout.json").read_text());floor=box(*plan["inner_floor"])
    all_rows={r["name"]:r for r in plan["placements"]};rows={k:r for k,r in all_rows.items() if r["collidable"]}
    shapes={name:shape(row) for name,row in rows.items()};blocked=unary_union(list(shapes.values()));overlap=[];support=[]
    for row in all_rows.values():
        if "support" not in row:continue
        parent=all_rows[row["support"]]
        supported=shape(parent).covers(shape(row)) and abs(row["position"][1]-parent["position"][1]-parent.get("support_height",parent["size"][1]))<.001
        support.append(dict(name=row["name"],support=parent["name"],passed=supported))
    for i,name in enumerate(shapes):
        assert floor.covers(shapes[name]),(name,"outside floor")
        for other in list(shapes)[:i]:
            area=shapes[name].intersection(shapes[other]).area
            if area>1e-7:overlap.append([name,other,area])
    band=box(*plan["rear_clear_band"])
    band_obstacles=[r["name"] for r in all_rows.values() if r["position"][1]<.10 and shape(r).intersection(band).area>1e-6]
    spawn=Point(plan["spawn"][0],plan["spawn"][2]);seats=[a for a in plan["anchors"] if a["name"].startswith("seat_")]
    targets=[dict(name=s["name"],position=s["stand"]) for s in seats]+plan["review_targets"]
    targets.append(dict(name="exit",position=plan["exit"],main_position=[plan["exit"][0],.08,2.74]))
    # Extra 12 mm prevents a grid diagonal from clipping near-touching circles.
    regions={r:component(floor.buffer(-r-.012).difference(blocked.buffer(r+.012,quad_segs=48)),spawn) for r in [.25,.35]}
    results=[];direct=[]
    for radius,region in regions.items():
        for target in targets:
            at=target.get("main_position",target["position"]) if radius==.35 else target["position"];point=Point(at[0],at[2])
            results.append(dict(radius=radius,target=target["name"],reachable=region is not None and region.covers(point),clearance_m=min(floor.boundary.distance(point),blocked.distance(point))))
            if target.get("direct"):
                line=LineString([spawn,point]);corridor=line.buffer(radius+.012,cap_style="round")
                direct.append(dict(radius=radius,target=target["name"],passed=floor.covers(corridor) and not corridor.intersects(blocked),length_m=line.length))
    region=regions[.25];chosen=[(spawn.x,spawn.y)]
    candidates=[(float(x),float(z)) for z in np.arange(-2.7,2.91,.16) for x in np.arange(-2.9,3.1,.16) if region is not None and region.buffer(-.025).contains(Point(x,z))]
    while candidates and len(chosen)<16:
        p=max(candidates,key=lambda p:min(math.dist(p,q) for q in chosen))
        if min(math.dist(p,q) for q in chosen)<.55:break
        chosen.append(p);candidates.remove(p)
    gaps=dict(bench_case1=shapes["glass_case_1"].bounds[0]-shapes["bench"].bounds[2],
        case2_plinth=shapes["display_plinth"].bounds[1]-shapes["glass_case_2"].bounds[3],
        between_cases=shapes["glass_case_2"].bounds[0]-shapes["glass_case_1"].bounds[2],
        rear_band_depth=2.0,case2_rear_edge_from_wall=shapes["glass_case_2"].bounds[1]+3.0,
        case2_rear_edge_from_skirting=shapes["glass_case_2"].bounds[1]-plan["rear_skirting_front_z"],
        plinth_distance_from_entry_centerline=shapes["display_plinth"].bounds[0]-plan["spawn"][0])
    report=dict(passed=not overlap and not band_obstacles and all(s["passed"] for s in support) and all(r["reachable"] for r in results)
        and all(d["passed"] for d in direct) and len(chosen)==16 and gaps["bench_case1"]>=.7 and gaps["case2_plinth"]>=.7,
        overlap=overlap,support=support,rear_band_obstacles=band_obstacles,rear_band=plan["rear_clear_band"],routes=results,direct_routes=direct,
        clearances_m=gaps,standing_16=[[round(x,4),.08,round(z,4)] for x,z in chosen],seat_count=len(seats),seat_surface_y=.795,
        method="Conservative object footprints, .25/.35 m radius capsule centre buffers plus 12 mm grid safety; straight swept corridors for three entrance targets.")
    step=.02;x0,z0,x1,z1=plan["inner_floor"];width=round((x1-x0)/step)+1;depth=round((z1-z0)/step)+1
    zz,xx=np.mgrid[0:depth,0:width];modes=[]
    for radius,region in regions.items():
        mask=shapely.contains_xy(region,x0+xx*step,z0+zz*step).ravel() if region else np.zeros(width*depth,dtype=bool)
        modes.append(dict(radius=radius,blocked=np.flatnonzero(~mask).tolist()))
    QA.mkdir(parents=True,exist_ok=True)
    (QA/"plan-validation.json").write_text(json.dumps(report,indent=2)+"\n")
    (QA/"navigation-fixture.json").write_text(json.dumps(dict(plan=plan,analysis=report,targets=targets,grid=dict(step=step,width=width,depth=depth,origin=[x0,z0],modes=modes)))+"\n")
    print("CULTURE_PLAN_CHECK",report["passed"],gaps,"band obstacles",band_obstacles,"overlap",overlap)
    if not report["passed"]:raise SystemExit(1)
if __name__=="__main__":main()
