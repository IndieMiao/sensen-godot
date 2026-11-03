"""Read delivered GLBs, compare approved inputs, audit module bounds and UVs."""
from pathlib import Path
import hashlib
import itertools
import io
import json
import math
import subprocess
import sys
import numpy as np
from PIL import Image

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.path.insert(0,str(ROOT/"tools/art"))
from verify_chef_sign import load_glb, accessor
KIT=ROOT/"assets/rooms/poi_classroom";QA=ROOT/"output/classroom-322"

def main():
    plan=json.loads((KIT/"layout.json").read_text());stats=json.loads((KIT/"asset_stats.json").read_text())
    checks=[];meshes=[]
    def check(ok,label):
        checks.append(dict(check=label,passed=bool(ok)))
        if not ok:print("FAIL",label)
    for directory in ["assets/rooms/_shared/shell_hall","scenes/shell_hall"]:
        check(subprocess.run(["git","diff","--exit-code","HEAD","--",directory],cwd=ROOT,capture_output=True).returncode==0,"unchanged shared shell: "+directory)
    check(subprocess.run(["git","diff","--exit-code","350bd1f1","--","assets/rooms/poi_classroom/props"],cwd=ROOT,capture_output=True).returncode==0,"all approved prop files byte-identical to 350bd1f1")
    palette=json.loads((KIT/"atlas_skin.json").read_text())["slots"]
    old_atlas=np.asarray(Image.open(io.BytesIO(subprocess.check_output(["git","show","e2eedb94:assets/rooms/poi_classroom/room_albedo_ao.png"],cwd=ROOT))).convert("RGB"))
    new_atlas=np.asarray(Image.open(KIT/"room_albedo_ao.png").convert("RGB"))
    allowed=np.zeros((2048,2048),dtype=bool)
    for key in ["parquet","floor_solid","oak","oak_light"]:
        x,y,w,h=palette[key]["rect_px_top_left"];allowed[y:y+h,x:x+w]=True
    check(not np.any(np.any(old_atlas!=new_atlas,axis=2)&~allowed),"atlas edits confined to furniture and floor slots")
    bounds={}
    for spec in plan["assets"]:
        path=KIT/spec["file"];doc,blob=load_glb(path)
        old_import=subprocess.check_output(["git","show","e2eedb94:assets/rooms/poi_classroom/"+spec["file"]+".import"],cwd=ROOT)
        check(Path(str(path)+".import").read_bytes()==old_import,spec["name"]+" import and UID unchanged")
        triangles=0;surfaces=0;verts=[]
        for mesh in doc["meshes"]:
            check(mesh["name"].endswith("_mobile"),spec["name"]+" mesh suffix")
            for primitive in mesh["primitives"]:
                pos=accessor(doc,blob,primitive["attributes"]["POSITION"]);verts.append(pos)
                check(np.isfinite(pos).all(),spec["name"]+" finite vertices")
                triangles+=len(accessor(doc,blob,primitive["indices"]))//3;surfaces+=1
                if "TEXCOORD_0" in primitive["attributes"]:
                    uv=np.asarray(accessor(doc,blob,primitive["attributes"]["TEXCOORD_0"]))
                    check(np.isfinite(uv).all() and uv.min()>=0 and uv.max()<=1,spec["name"]+" UV within atlas")
        check(triangles==spec["triangles"] and surfaces==spec["surfaces"],spec["name"]+" raw mesh cost")
        if not spec["name"].startswith("props/"):
            check(doc.get("images")==[{"uri":"room_albedo_ao.png"}],spec["name"]+" one external atlas")
        array=np.concatenate(verts);lo=array.min(0);hi=array.max(0);bounds[spec["name"]]=(lo,hi)
        meshes.append(dict(name=spec["name"],triangles=triangles,surfaces=surfaces,bounds=[lo.tolist(),hi.tolist()],sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    for name,size in [("student_desk",[1.02,1.13425,.58]),("student_stool",[.48,.715,.48]),("rear_bookcase",[.9,1.5,.65])]:
        lo,hi=bounds[name];check(np.allclose(hi-lo,size,atol=.00001),name+" required dimensions")
    world={}
    rows={r["name"]:r for r in plan["placements"]}
    baseline=json.loads(subprocess.check_output(["git","show","e2eedb94:assets/rooms/poi_classroom/layout.json"],cwd=ROOT,text=True))
    check(plan["anchors"]==baseline["anchors"],"all v1 anchors unchanged")
    for row in baseline["placements"]:
        if row["name"] not in ["rear_bookcase","pendant_1","pendant_2"]:
            check(rows[row["name"]]==row,"v1 placement unchanged: "+row["name"])
    for spec in plan["assets"]:
        if spec["name"]=="rear_bookcase":continue
        old=subprocess.check_output(["git","show","e2eedb94:assets/rooms/poi_classroom/"+spec["file"]],cwd=ROOT)
        check((KIT/spec["file"]).read_bytes()==old,"v1 mesh unchanged: "+spec["name"])
    for row in rows.values():
        lo,hi=bounds[row["model"]];vertices=np.array(list(itertools.product(*zip(lo,hi))))
        a=math.radians(row["yaw_degrees"]);rotation=np.array([[math.cos(a),0,math.sin(a)],[0,1,0],[-math.sin(a),0,math.cos(a)]])
        vertices=vertices@rotation.T+row["position"];lo=vertices.min(0);hi=vertices.max(0);world[row["name"]]=(lo,hi)
        check(lo[1]>=.079,"no floor penetration: "+row["name"])
        if not row["name"].startswith("plant_") and row["model"]!="wall_sconce":
            check(lo[0]>=-3.185 and lo[2]>=-3.005,"no wall penetration beyond mounting allowance: "+row["name"])
    overlap=[]
    for a,b in itertools.combinations(world,2):
        if rows[a].get("support")==b or rows[b].get("support")==a:continue
        alo,ahi=world[a];blo,bhi=world[b]
        depth=np.minimum(ahi,bhi)-np.maximum(alo,blo)
        if np.all(depth>.003):overlap.append(dict(a=a,b=b,depth=depth.tolist()))
    check(not overlap,"distinct module AABBs do not overlap; declared support contacts excluded")
    check(stats["scene_triangles"]<=150000 and stats["static_draw_surfaces"]<=50,"placed budget")
    result=dict(passed=all(c["passed"] for c in checks),checks=checks,meshes=meshes,overlap=overlap,
        scope="Raw GLB arrays and actual transformed bounds. Connected construction parts inside a module intentionally join. Props mounted on their declared support are checked separately by check_plan and the Godot mount assertion.")
    (QA/"detail-assets.json").write_text(json.dumps(result,indent=2)+"\n")
    print("CLASSROOM_ASSETS",result["passed"],len(checks),"checks",overlap)
    if not result["passed"]:raise SystemExit(1)

if __name__=="__main__":main()
