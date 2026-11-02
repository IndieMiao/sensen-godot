"""Inspect the delivered GLB, including protection-polygon overlap and vertex channels."""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import colorsys

import numpy as np
from shapely.geometry import Polygon

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[4];QA=ROOT/"output/quarry-355"
parser=argparse.ArgumentParser();parser.add_argument("--runtime",required=True);args=parser.parse_args()
kit=Path(args.runtime)/"assets/mine/types/quarry"
raw=(kit/"backdrop.glb").read_bytes();length=struct.unpack_from("<I",raw,12)[0]
doc=json.loads(raw[20:20+length]);blob=raw[28+length:]
def array(index):
    a=doc["accessors"][index];v=doc["bufferViews"][a["bufferView"]]
    width={"SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4}[a["type"]]
    dtype={5121:np.uint8,5123:np.dtype("<u2"),5125:np.dtype("<u4"),5126:np.dtype("<f4")}[a["componentType"]]
    size=np.dtype(dtype).itemsize
    result=np.ndarray((a["count"],width),dtype=dtype,buffer=blob,offset=v.get("byteOffset",0)+a.get("byteOffset",0),strides=(v.get("byteStride",width*size),size)).copy()
    return result/np.iinfo(dtype).max if a.get("normalized") else result
checks=[]
def check(ok,label):
    checks.append({"check":label,"passed":bool(ok)})
    if not ok: print("FAIL",label)
check(len(doc["meshes"])==1 and len(doc["meshes"][0]["primitives"])==1,"one mesh / one surface")
p=doc["meshes"][0]["primitives"][0];a=p["attributes"]
vertices=array(a["POSITION"]);colors=array(a["COLOR_0"]);uv=array(a["TEXCOORD_1"])
indices=array(p["indices"]).reshape(-1,3)
check(len(indices)<=4000,"at most 4000 triangles")
check(not doc.get("images") and not doc.get("textures"),"zero textures")
check(not doc.get("skins") and not doc.get("animations"),"static backdrop")
check(all(not any(key in node for key in ["translation","scale","rotation","matrix"]) for node in doc["nodes"]),"identity transform / no baked 1 m placement")
check(all(not any(term in node.get("name","").lower() for term in ["collision","rigid","staticbody"]) for node in doc["nodes"]),"no collision nodes")
check(np.max(np.abs(colors[:,0]-colors[:,1]))<1e-6 and np.max(np.abs(colors[:,0]-colors[:,2]))<1e-6,"equal linear RGB grayscale")
check(np.allclose(colors[:,3],1),"opaque vertex alpha")
check(colors[:,:3].min()>=.419 and colors[:,:3].max()<=.961,"gray range 0.42 to 0.96")
check(uv[:,0].min()>=0 and uv[:,0].max()<=1 and uv[:,0].max()==1,"UV2.x fade retained")
check(np.all(uv[:,1]==0),"UV2.y all zero: quarry has no vein mask")
check("KHR_materials_unlit" in doc["materials"][0].get("extensions",{}),"unlit preview material")
build=json.loads((QA/"build.json").read_text())
basis=np.column_stack([build["basis"][key] for key in ["right","up","normal"]])
projected=vertices@basis
depth=projected[:,2]
check(depth.min()>=-6.971 and depth.max()<=-5.60,"within original depth range (1 mm rounding at preserved inner edge)")
inner=np.array(build["inner_vertices"])
nearest=np.sqrt(((inner[:,None,:]-vertices[None,:,:])**2).sum(axis=2)).min(axis=1)
check(nearest.max()<2e-6,"all 224 original inner-edge vertices preserved")
protected=Polygon(build["contour"]["inner"]).buffer(-2e-5)
overlap=sum(Polygon(projected[tri,:2]).intersection(protected).area for tri in indices)
check(overlap<1e-7,"no triangle enters original protection contour")
bands=json.loads((kit/"palette.json").read_text())["bands"]
check([(b["from"],b["to"]) for b in bands]==[(1,4),(5,10),(11,20),(21,30)],"exact continuous 1-30 layer bands")
def luminance(code):
    rgb=np.array([int(code[i:i+2],16)/255 for i in [1,3,5]])
    linear=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
    return float(linear@np.array([.2126,.7152,.0722]))
check(all(set(b)=={"from","to","ground","wall","backdrop_tint","fog"} for b in bands),"client palette keys")
for role in ["ground","wall","backdrop_tint"]:
    values=[luminance(b[role]) for b in bands]
    check(all(a>b for a,b in zip(values,values[1:])),role+" gets progressively darker")
check(all(luminance(b["fog"])>.005 for b in bands),"void colors stay above black")
palette_hsl=[]
for band in bands:
    row={}
    for role in ["ground","wall","backdrop_tint"]:
        code=band[role]
        h,l,s=colorsys.rgb_to_hls(*[int(code[i:i+2],16)/255 for i in [1,3,5]])
        row[role]={"h":h*360,"s":s,"l":l}
    palette_hsl.append(row)
check(all(25<=c["h"]<=32 and c["s"]>=.28 for row in palette_hsl for c in row.values()),"warm HSL hue and saturation retained in all four bands")
check(all(abs(row["ground"]["l"]-target)<.005 for row,target in zip(palette_hsl,[.65,.58,.51,.45])),"ground HSL lightness follows .65/.58/.51/.45")
report={"passed":all(c["passed"] for c in checks),"checks":checks,"triangles":len(indices),"surfaces":1,"textures":0,
    "palette_hsl":palette_hsl,
    "depth_range":depth.tolist() and [float(depth.min()),float(depth.max())],"gray_range":[float(colors[:,0].min()),float(colors[:,0].max())],
    "protected_overlap_m2":overlap,"inner_edge_max_error_m":float(nearest.max()),
    "runtime_glb_sha256":hashlib.sha256(raw).hexdigest()}
(QA/"glb-validation.json").write_text(json.dumps(report,indent=2)+"\n")
print("QUARRY_GLB",report["passed"],len(checks),"checks",len(indices),"triangles",report["depth_range"],"overlap",overlap)
if not report["passed"]: raise SystemExit(1)
