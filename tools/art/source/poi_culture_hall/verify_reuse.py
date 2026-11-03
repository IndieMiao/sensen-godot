"""Audit approved invariants, raw export geometry, and exact botanical remapping."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import numpy as np
from PIL import Image

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];KIT=ROOT/"assets/rooms/poi_culture_hall";QA=ROOT/"output/culture-hall-323"
sys.path.insert(0,str(ROOT/"tools/art"))
from verify_chef_sign import load_glb,accessor
def old(rel):return subprocess.check_output(["git","show","aee2d5d0:"+rel],cwd=ROOT)
def arrays(path):
    doc,blob=load_glb(path);positions=[];uvs=[]
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            positions+=accessor(doc,blob,primitive["attributes"]["POSITION"])
            if "TEXCOORD_0" in primitive["attributes"]:uvs+=accessor(doc,blob,primitive["attributes"]["TEXCOORD_0"])
    return doc,np.asarray(positions),np.asarray(uvs)
def main():
    plan=json.loads((KIT/"layout.json").read_text());baseline=json.loads(old("assets/rooms/poi_culture_hall/layout.json"));skin=json.loads((KIT/"atlas_skin.json").read_text())
    checks=[]
    def check(ok,label):
        checks.append(dict(check=label,passed=bool(ok)))
        if not ok:print("FAIL",label)
    detailed=plan["stage"].startswith("detail_")
    for key in ["spawn","exit","camera","rear_clear_band","review_lighting"]:check(plan[key]==baseline[key],"approved "+key+" unchanged")
    check([a for a in plan["anchors"] if a["name"]!="sign_door"]==[a for a in baseline["anchors"] if a["name"]!="sign_door"],"approved seating and navigation anchors unchanged")
    rows={r["name"]:r for r in plan["placements"]}
    for row in baseline["placements"]:
        if row["owner"]=="huangzhong" and not detailed:check(rows[row["name"]]==row,"pending prop unchanged: "+row["name"])
        if row["collidable"] and (not detailed or row["owner"]=="zhaoyun"):
            keys=["position","size","yaw_degrees","shape","collidable"]
            check(all(rows[row["name"]].get(k)==row.get(k) for k in keys),"approved collision unchanged: "+row["name"])
    if not detailed:check(not (KIT/"props").exists(),"Huangzhong final directory remains untouched")
    for path in sorted(KIT.glob("blockout_*")):
        check(path.read_bytes()==old(str(path.relative_to(ROOT))),"white asset byte-identical: "+path.name)
    for directory in ["assets/rooms/_shared/shell_hall","scenes/shell_hall","assets/rooms/_shared/plants"]:
        check(subprocess.run(["git","diff","--exit-code","HEAD","--",directory],cwd=ROOT,capture_output=True).returncode==0,"read-only library: "+directory)
    image=Image.open(KIT/"room_albedo_ao.png").convert("RGBA");plant_image=Image.open(ROOT/"assets/rooms/_shared/plants/room_albedo_ao.png").convert("RGBA")
    check(image.size==(2048,2048),"single 2048 RGBA room atlas")
    for tile in skin["botanical_tiles"]:
        x,y,w,h=tile["source_rect_px"];a=np.asarray(plant_image.crop((x,y,x+w,y+h)))
        x,y,w,h=tile["target_rect_px"];b=np.asarray(image.crop((x,y,x+w,y+h)))
        check(np.array_equal(a,b),"exact botanical RGBA tile "+str(tile["source_tile"]))
    costs=[];bounds={}
    for spec in plan["assets"]:
        if spec["name"].startswith(("blockout_","props/")):continue
        path=KIT/spec["file"];doc,pos,uv=arrays(path);lo,hi=pos.min(0),pos.max(0);bounds[spec["name"]]=(lo,hi)
        check(len(doc["meshes"])==1 and doc["meshes"][0]["name"]==spec["name"]+"_mobile",spec["name"]+" named single mesh")
        check(len(doc["meshes"][0]["primitives"])==1,spec["name"]+" single surface")
        check(doc.get("images")==[{"uri":"room_albedo_ao.png"}],spec["name"]+" sole external room atlas")
        check(np.isfinite(pos).all() and np.isfinite(uv).all() and uv.min()>=0 and uv.max()<=1,spec["name"]+" finite geometry and atlas UV")
        primitive=doc["meshes"][0]["primitives"][0];triangles=doc["accessors"][primitive["indices"]]["count"]//3
        check(triangles==spec["triangles"],spec["name"]+" raw triangle cost")
        costs.append(dict(name=spec["name"],triangles=triangles,bounds=[lo.tolist(),hi.tolist()],sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    for name,expected in [("gallery_bench",[.68,.715,1.728]),("round_stool",[.48,.715,.48])]:
        lo,hi=bounds[name];check(np.allclose(hi-lo,expected,atol=.0001) and abs(lo[1])<.0001,name+" approved seat dimensions")
    lo,hi=bounds["monstera"];at=np.array(rows["plant_pot"]["position"])
    check((lo+at)[0]>=-3.18 and (hi+at)[2]<=3.14,"foliage clears left wall and open front")
    _,wall,_=arrays(ROOT/"assets/rooms/_shared/shell_hall/hall_left_wall.glb")
    wall_front=float(wall[wall[:,1]<1.20,2].max()-3.30)
    wall_clearance=float((lo+at)[0]-wall_front)
    check(wall_clearance>.01,"all Monstera card vertices clear actual projecting wainscot")
    doc,pos,uv=arrays(KIT/"monstera.glb");_,original,source_uv=arrays(ROOT/"assets/rooms/_shared/plants/monstera.glb")
    mapping={tuple(t["source_tile"]):t for t in skin["botanical_tiles"]};mapped=[]
    for value in source_uv:
        px=value*2048;tile=mapping[tuple(np.floor(px/128).astype(int))]
        mapped.append((px-np.array(tile["source_rect_px"][:2])+np.array(tile["target_rect_px"][:2]))/2048)
    mapped=np.asarray(mapped);max_error=0.0;all_match=True
    source_positions=np.column_stack((-pos[:,2],pos[:,1],pos[:,0]))/.62
    for point,coordinate in zip(source_positions,uv):
        candidates=np.max(np.abs(original-point),axis=1)<2e-5
        if not candidates.any():all_match=False;break
        error=float(np.min(np.max(np.abs(mapped[candidates]-coordinate),axis=1)));max_error=max(max_error,error)
        if error>2e-6:all_match=False;break
    check(all_match,"every exported Monstera vertex preserves scaled/quarter-turned source position and remapped UV")
    mat=doc["materials"][0];check(mat.get("alphaMode")=="MASK" and mat.get("alphaCutoff")==.45 and mat.get("doubleSided"),"Monstera alpha scissor .45 and double-sided")
    report=dict(passed=all(c["passed"] for c in checks),checks=checks,costs=costs,botanical_max_uv_error=max_error,botanical_wainscot_clearance_m=wall_clearance,
        scope="Independent shell skin, seats, lamps and botanical source checks; display kit is audited separately for detail_v1.")
    (QA/"reuse-assets.json").write_text(json.dumps(report,indent=2)+"\n")
    print("CULTURE_REUSE_AUDIT",report["passed"],len(checks),"checks, botanical UV error",max_error)
    if not report["passed"]:raise SystemExit(1)
if __name__=="__main__":main()
