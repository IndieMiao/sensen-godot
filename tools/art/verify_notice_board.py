#!/usr/bin/env python3
"""Audit exported binary meshes, source construction and exact triangle overlap.

Run with Blender --background --factory-startup --python (absolute script path).
The actual GLB data is decoded directly; BVH uses exported triangles, not proxies.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_chef_sign import load_glb, accessor, cross, sub

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/"assets/farm/art"
SOURCE=ROOT/"tools/art/source/notice_board_284"


def geometry(name,offset=(0,0,0)):
    doc,data=load_glb(ART/(name+".glb"))
    primitive=doc["meshes"][0]["primitives"][0]
    positions=accessor(doc,data,primitive["attributes"]["POSITION"])
    positions=[tuple(p[i]+offset[i] for i in range(3)) for p in positions]
    indices=[v[0] for v in accessor(doc,data,primitive["indices"])]
    triangles=[indices[i:i+3] for i in range(0,len(indices),3)]
    return doc,data,primitive,positions,triangles


def main():
    report={"checks":[],"neighbours":[]}
    def check(ok,label):
        report["checks"].append({"check":label,"passed":bool(ok)})
        if not ok:print("FAIL",label,flush=True)
    doc,data,p,positions,triangles=geometry("notice_board")
    entry=json.loads((ART/"manifest.json").read_text())["assets"]["notice_board"]
    check(len(doc["meshes"])==1 and len(doc["meshes"][0]["primitives"])==1,"One GLB mesh and one surface")
    check(len(doc.get("materials",[]))==1 and not doc.get("images") and not doc.get("textures"),"One material, zero textures")
    check(set(p["attributes"])=={"POSITION","NORMAL","COLOR_0"},"Position, normal and vertex color only")
    check(len(triangles)==entry["triangles"] and len(triangles)<=1200,"Triangle budget and manifest")
    normals=accessor(doc,data,p["attributes"]["NORMAL"])
    colors=accessor(doc,data,p["attributes"]["COLOR_0"])
    check(all(len(c)==3 or c[3]==1 for c in colors),"Opaque vertex colors")
    palette=json.loads((SOURCE/"palette-provenance.json").read_text())
    expected={tuple(v["linear_rgba"][:3]) for v in palette.values()}
    check(set(tuple(c[:3]) for c in colors)==expected,"Exported palette exactly equals copied source values")
    for name,record in palette.items():
        path=ROOT/record["asset"]
        d,b=load_glb(path);pr=d["meshes"][0]["primitives"][0]
        samples=accessor(d,b,pr["attributes"]["COLOR_0"])
        check(tuple(record["linear_rgba"][:3])==samples[record["source_vertex"]][:3] and hashlib.sha256(path.read_bytes()).hexdigest()==record["sha256"],"Exact palette provenance: "+name)
    d,b,pr,_,_=geometry("well")
    well_colors=accessor(d,b,pr["attributes"]["COLOR_0"])
    check(tuple(palette["roof_green"]["linear_rgba"][:3]) in well_colors,"Roof green also exists exactly in well.glb")
    bad_normals=degenerate=0
    for tri in triangles:
        a,b,c=[positions[i] for i in tri]
        normal=cross(sub(b,a),sub(c,a))
        if math.sqrt(sum(x*x for x in normal))<1e-10:degenerate+=1
        average=[sum(normals[i][j] for i in tri) for j in range(3)]
        if sum(a*b for a,b in zip(normal,average))< -1e-9:bad_normals+=1
    relief=max(p[2] for p in positions if .95<=p[1]<=1.39)-.06
    check(relief<=.012001,"Actual board region including pin heads protrudes <= 0.012 m from cork")
    report["maximum_board_relief_m"]=relief
    check(degenerate==0,"Zero degenerate triangles")
    check(bad_normals==0,"Triangle winding agrees with shading normals")
    check(all(n.get("scale",[1,1,1])==[1,1,1] and n.get("rotation",[0,0,0,1])==[0,0,0,1] for n in doc["nodes"]),"Identity scale and orientation in GLB nodes")
    for name,at in [("board_center",[0,1.17,.06]),("mark",[0,1.75,0])]:
        node=next((n for n in doc["nodes"] if n.get("name")==name),{})
        translation=node.get("translation",[])
        check(len(translation)==3 and max(abs(x-y) for x,y in zip(translation,at))<1e-6,"Exact socket: "+name)
    bvh=BVHTree.FromPolygons(positions,triangles,all_triangles=True,epsilon=1e-7)
    for name,offset in [("storage",(-.65,0,0)),("well",(0,0,1.30))]:
        _,_,_,other,other_triangles=geometry(name,offset)
        other_bvh=BVHTree.FromPolygons(other,other_triangles,all_triangles=True,epsilon=1e-7)
        hits=bvh.overlap(other_bvh)
        check(len(hits)==0,"Actual GLB triangle/BVH intersections = 0: "+name)
        report["neighbours"].append({"asset":name,"offset":offset,"triangles":len(other_triangles),"intersecting_triangle_pairs":len(hits),"sha256":hashlib.sha256((ART/(name+".glb")).read_bytes()).hexdigest()})
    # Positive control: the same real storage shifted into the left post must hit.
    _,_,_,other,other_triangles=geometry("storage",(-.50,0,0))
    bad_hits=bvh.overlap(BVHTree.FromPolygons(other,other_triangles,all_triangles=True,epsilon=1e-7))
    check(len(bad_hits)>0,"Overlap detector positive control: shifted storage intersects left post")
    report["positive_control_intersections"]=len(bad_hits)
    # Source checks ensure the editable construction is part of the handoff.
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/"notice_board.blend"))
    objects=list(bpy.data.collections["notice_board"].objects)
    papers=[o for o in objects if o.name.startswith("Paper ")]
    pins=[o for o in objects if o.name.startswith("Pin ")]
    check(len(papers)==4 and len(pins)==4,"Four named editable blank papers and four round pins")
    for paper in papers:
        size=[max(v.co[i] for v in paper.data.vertices)-min(v.co[i] for v in paper.data.vertices) for i in range(3)]
        check(.10-1e-6<=size[0]<=.16+1e-6 and .12-1e-6<=size[2]<=.18+1e-6 and abs(size[1]-.005)<1e-6,"Paper dimensions and 0.005 m depth: "+paper.name)
        check(abs(math.degrees(paper.rotation_euler.y))<=8,"Paper tilt within 8 degrees: "+paper.name)
    check(all(o.name.startswith(("Structure /","Foot /","Board /","Canopy /","Paper ","Pin ")) or o.type=="EMPTY" for o in objects),"All editable construction objects named")
    report["asset"]={"triangles":len(triangles),"surfaces":1,"sha256":hashlib.sha256((ART/"notice_board.glb").read_bytes()).hexdigest(),"bounds":entry["bounds"]}
    report["failures"]=[c for c in report["checks"] if not c["passed"]]
    out=ROOT/"output/notice-board-284/glb-validation.json"
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(report,indent=2)+"\n")
    print("NOTICE_BINARY_QA",len(report["checks"]),"checks",len(report["failures"]),"failures",flush=True)
    if report["failures"]:raise RuntimeError("Notice Board audit failed")


if __name__=="__main__":main()
