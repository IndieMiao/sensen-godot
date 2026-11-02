"""Independent GLB contract and v1-to-v1.1 preservation verification."""
from pathlib import Path
import argparse
import json
import struct
import subprocess
import ast
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
def array(index, document=None, binary=None):
    document=doc if document is None else document
    binary=blob if binary is None else binary
    a=document["accessors"][index];v=document["bufferViews"][a["bufferView"]]
    widths={"SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4,"MAT4":16}
    dtype={5121:np.uint8,5123:np.dtype("<u2"),5125:np.dtype("<u4"),5126:np.dtype("<f4")}[a["componentType"]]
    size=np.dtype(dtype).itemsize; width=widths[a["type"]]
    offset=v.get("byteOffset",0)+a.get("byteOffset",0)
    data=np.ndarray((a["count"],width),dtype=dtype,buffer=binary,offset=offset,strides=(v.get("byteStride",width*size),size)).copy()
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
rig_node=next(node for node in doc["nodes"] if node["name"]=="RockBeetleRig")
mesh_index=next(i for i,node in enumerate(doc["nodes"]) if node.get("mesh")==0)
check(rig_node.get("scale")==[1.25]*3 and mesh_index in rig_node["children"] and
      not any(key in doc["nodes"][mesh_index] for key in ["translation","rotation","scale","matrix"]),
      "static uniform 1.25 rig scale with identity mesh transform")
# Blender bakes scaled skin vertices and cancels that scale in inverse binds.
parents={child:i for i,node in enumerate(doc["nodes"]) for child in node.get("children",[])}
def rest_matrix(index):
    node=doc["nodes"][index]
    assert not any(key in node for key in ["matrix","rotation"])
    matrix=np.diag([*node.get("scale",[1,1,1]),1.0])
    matrix[:3,3]=node.get("translation",[0,0,0])
    return rest_matrix(parents[index])@matrix if index in parents else matrix
binds=array(doc["skins"][0]["inverseBindMatrices"]).reshape(-1,4,4).transpose(0,2,1)
rest_skins=np.array([rest_matrix(index)@binds[i] for i,index in enumerate(doc["skins"][0]["joints"])])
check(np.allclose(rest_skins,np.eye(4),atol=1e-6),"bind matrices cancel baked rig scale in rest skin")
vertices=np.array([(rest_skins[joints[i,weights[i].argmax()]]@np.append(v,1))[:3] for i,v in enumerate(vertices)])
local_vertices=vertices/1.25
bounds=[vertices.min(axis=0).tolist(),vertices.max(axis=0).tolist()]
size=vertices.max(axis=0)-vertices.min(axis=0)
check(abs(bounds[0][1])<.00001 and abs(size[1]-spec["height"])<.0001,"foot origin and JSON height match")
check(size[0]<=1.10 and 1.17<size[2]<1.44 and .60<size[1]<.65,"v1.1 enlarged body with tucked leg width")
def rgb(code):
    values=np.array([int(code[i:i+2],16)/255 for i in [0,2,4]])
    return np.where(values<=.04045,values/12.92,((values+.055)/1.055)**2.4)
shell_mask=np.zeros(len(vertices),dtype=bool)
for role in ["shell","rim","bump"]:
    shell_mask |= np.all(np.abs(colors[:,:3]-rgb(spec["palette"][role]))<.002,axis=1)
dominant=joints[np.arange(len(vertices)),weights.argmax(axis=1)]
shell_mask &= dominant==names.index("body")
shell_vertices=vertices[shell_mask]
shell_size=shell_vertices.max(axis=0)-shell_vertices.min(axis=0)
check(abs(shell_size[0]-1.025)<.001 and abs(shell_size[2]-1.225)<.001,"carapace and rim exactly 1.25 times v1")
radius=float(np.max(np.linalg.norm(vertices[:,[0,2]],axis=1)))
check(radius<=spec["radius"] and np.isclose(spec["radius"],.58*1.25),"radius covers tucked footprint and equals v1 times 1.25")
check(np.allclose(spec["hit_point"],[0,.35,.05]),"hit_point equals v1 times 1.25")
old_path="assets/monsters/mob_rock_beetle/mob_rock_beetle"
old_raw=subprocess.check_output(["git","show","688f42e2:"+old_path+".glb"],cwd=args.runtime)
old_n=struct.unpack_from("<I",old_raw,12)[0]
old_doc=json.loads(old_raw[20:20+old_n]);old_blob=old_raw[28+old_n:]
old_attributes=old_doc["meshes"][0]["primitives"][0]["attributes"]
old_vertices=array(old_attributes["POSITION"],old_doc,old_blob)
old_colors=array(old_attributes["COLOR_0"],old_doc,old_blob)
leg_mask=np.array([names[i].startswith("leg_") for i in dominant])
check(local_vertices.shape==old_vertices.shape and np.allclose(local_vertices[~leg_mask],old_vertices[~leg_mask],atol=1e-6),
      "all non-leg geometry including antennae unchanged before global scale")
head_color=np.all(np.abs(old_colors[:,:3]-rgb("A18B7D"))<.002,axis=1)
check(np.allclose(colors[~head_color],old_colors[~head_color],atol=1e-6) and
      np.allclose(colors[head_color,:3],rgb("C9A087"),atol=.002),"only head base colour changes to light warm brown")
old_import=subprocess.check_output(["git","show","688f42e2:"+old_path+".glb.import"],cwd=args.runtime)
check((kit/"mob_rock_beetle.glb.import").read_bytes()==old_import,"import file and UID byte-identical to approved v1")
old_source=subprocess.check_output(["git","show","d4401f94:tools/art/source/monsters/mob_rock_beetle/build.py"],cwd=ROOT,text=True)
def action_source(source):
    return [ast.dump(node) for node in ast.parse(source).body if isinstance(node,ast.FunctionDef) and node.name in ["pose","animations"]]
check(action_source(old_source)==action_source((HERE/"build.py").read_text()),"source pose and animation curve generation unchanged")
baseline=json.loads(subprocess.check_output(["git","show","bf5279c3:assets/monsters/mob_rock_beetle/mob_rock_beetle.json"],cwd=args.runtime))
check(spec["durations"]==baseline["durations"] and spec["hit_at"]==baseline["hit_at"],"approved action timings and contact event unchanged")
check(set(names)=={"root","body","head","ant_l","ant_r","leg_l_1","leg_l_2","leg_l_3","leg_r_1","leg_r_2","leg_r_3"},"approved 11 bone names unchanged")
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
    old_anim=next(a for a in old_doc["animations"] if a["name"]==name)
    def channels(document,animation,binary):
        result={}
        for channel in animation["channels"]:
            target=channel["target"];node=document["nodes"][target["node"]]
            sampler=animation["samplers"][channel["sampler"]]
            values=array(sampler["output"],document,binary)
            if target["path"]=="translation": values=values-np.array(node.get("translation",[0,0,0]))
            result[(node["name"],target["path"])]=(array(sampler["input"],document,binary),values)
        return result
    current=channels(doc,anim,blob);previous=channels(old_doc,old_anim,old_blob)
    check(current.keys()==previous.keys() and all(np.allclose(current[key][j],previous[key][j],atol=1e-6) for key in current for j in [0,1]),
          name+" exported motion unchanged relative to rest pivots")
    if spec["anims"][name]["loop"]: check(seamless,name+" loop endpoints match")
    loops[name]={"root_static":bool(stable),"loop_endpoints_match":bool(seamless)}
report={"checks":checks,"passed":all(c["passed"] for c in checks),"triangles":triangles,"bounds":bounds,"size_xyz":size.tolist(),
    "shell_size_xyz":shell_size.tolist(),"measured_radius":radius,"metadata_radius":spec["radius"],
    "width_vs_slime_diameter":float(size[0]/.8),"bones":names,"animations":loops,
    "runtime_glb_sha256":__import__("hashlib").sha256(raw).hexdigest()}
(ROOT/"output/rock-beetle-355/glb-validation.json").write_text(json.dumps(report,indent=2)+"\n")
print("BEETLE_GLB",report["passed"],len(checks),"checks",triangles,"triangles",size.tolist())
if not report["passed"]: raise SystemExit(1)
