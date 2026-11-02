"""Independent GLB contract verification for the rock-beetle graybox."""
from pathlib import Path
import argparse
import json
import struct
import numpy as np

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[4]
parser=argparse.ArgumentParser()
parser.add_argument("--runtime",required=True)
args=parser.parse_args()
kit=Path(args.runtime)/"assets/monsters/mob_rock_beetle"
raw=(kit/"mob_rock_beetle.glb").read_bytes()
n=struct.unpack_from("<I",raw,12)[0]
doc=json.loads(raw[20:20+n]); blob=raw[28+n:]
spec=json.loads((kit/"mob_rock_beetle.json").read_text())
checks=[]
def check(ok,label):
    checks.append({"check":label,"passed":bool(ok)})
    if not ok: print("FAIL",label)
def array(index):
    a=doc["accessors"][index];v=doc["bufferViews"][a["bufferView"]]
    widths={"SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4,"MAT4":16}
    dtype={5121:np.uint8,5123:np.dtype("<u2"),5125:np.dtype("<u4"),5126:np.dtype("<f4")}[a["componentType"]]
    size=np.dtype(dtype).itemsize; width=widths[a["type"]]
    offset=v.get("byteOffset",0)+a.get("byteOffset",0)
    data=np.ndarray((a["count"],width),dtype=dtype,buffer=blob,offset=offset,strides=(v.get("byteStride",width*size),size)).copy()
    if a.get("normalized"): data=data/np.iinfo(dtype).max
    return data

check(len(doc["meshes"])==1 and len(doc["meshes"][0]["primitives"])==1,"one mesh and one primitive")
p=doc["meshes"][0]["primitives"][0];a=p["attributes"]
vertices=array(a["POSITION"]);normals=array(a["NORMAL"]);weights=array(a["WEIGHTS_0"])
joints=array(a["JOINTS_0"]);mask=array(a["TEXCOORD_1"])[:,0];colors=array(a["COLOR_0"])
triangles=array(p["indices"]).size//3
check(triangles<=1500,"at most 1500 triangles")
check(len(doc["skins"])==1 and len(doc["skins"][0]["joints"])==11,"one skin with 11 bones")
names=[doc["nodes"][i]["name"] for i in doc["skins"][0]["joints"]]
check("root" in names and sum(n.startswith("leg_") for n in names)==6,"named root and six leg bones")
check(np.allclose(weights.sum(axis=1),1) and np.all((weights>.999).sum(axis=1)==1),"rigid one-bone weights")
check(np.all((mask==0)|(mask==1)) and mask.min()==0 and mask.max()==1,"UV2.x binary body mask")
check(np.isfinite(vertices).all() and np.isfinite(normals).all(),"finite vertices and normals")
check(np.max(np.abs(np.linalg.norm(normals,axis=1)-1))<.002,"smooth unit normals")
check(not doc.get("images") and not doc.get("textures"),"vertex colors without bitmap textures")
check(np.ptp(colors[:,:3])>.5,"authored face and body colors present")
bounds=[vertices.min(axis=0).tolist(),vertices.max(axis=0).tolist()]
size=vertices.max(axis=0)-vertices.min(axis=0)
check(abs(bounds[0][1])<.00001 and abs(size[1]-spec["height"])<.0001,"foot origin and JSON height match")
check(.98<size[0]<1.08 and .66<size[2]<.75 and .40<size[1]<.48,"agreed approximate proportions including feet")
root=next(i for i,node in enumerate(doc["nodes"]) if node["name"]=="root")
anims={anim["name"]:anim for anim in doc["animations"]}
check(set(anims)==set(spec["anims"]),"exact eight animation names")
check(set(spec["durations"])==set(anims),"client durations cover all exported actions")
check("hit_point" in spec and "hurt_point" not in spec and len(spec["hit_point"])==3,"client hit_point key")
check(0<spec["hit_at"]<spec["durations"]["attack"] and spec["hit_at"]==spec["anims"]["attack"]["hit_at"],"top-level client hit time")
check(all(spec["durations"][name]==data["length"] for name,data in spec["anims"].items()),"review timings agree with client durations")
loops={}
for name,anim in anims.items():
    times=[array(s["input"]) for s in anim["samplers"]]
    check(abs(max(float(t.max()) for t in times)-spec["durations"][name])<.0001,name+" GLB matches client duration")
    stable=True;seamless=True
    for channel in anim["channels"]:
        data=array(anim["samplers"][channel["sampler"]]["output"])
        if channel["target"]["node"]==root: stable=stable and np.allclose(data,data[0],atol=.00001)
        if spec["anims"][name]["loop"]:
            delta=min(float(np.max(np.abs(data[0]-data[-1]))),float(np.max(np.abs(data[0]+data[-1])))) if channel["target"]["path"]=="rotation" else float(np.max(np.abs(data[0]-data[-1])))
            seamless=seamless and delta<.0001
    check(stable,name+" root channels remain constant")
    if spec["anims"][name]["loop"]: check(seamless,name+" loop endpoints match")
    loops[name]={"root_static":bool(stable),"loop_endpoints_match":bool(seamless)}
report={"checks":checks,"passed":all(c["passed"] for c in checks),"triangles":triangles,"bounds":bounds,"size_xyz":size.tolist(),
    "width_vs_slime_diameter":float(size[0]/.8),"bones":names,"animations":loops,
    "runtime_glb_sha256":__import__("hashlib").sha256(raw).hexdigest()}
(ROOT/"output/rock-beetle-355/glb-validation.json").write_text(json.dumps(report,indent=2)+"\n")
print("BEETLE_GLB",report["passed"],len(checks),"checks",triangles,"triangles",size.tolist())
if not report["passed"]: raise SystemExit(1)
