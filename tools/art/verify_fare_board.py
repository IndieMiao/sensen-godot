#!/usr/bin/env python3
"""Independent GLB/UV audit and exact room-triangle overlap checks in Blender."""
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree

sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_chef_sign import load_glb,accessor,cross,sub
ROOT=Path(__file__).resolve().parents[2]
KIT=ROOT/'assets/rooms/post_office'
SOURCE=ROOT/'tools/art/source/fare_board_275'


def geometry(name,at=(0,0,0),yaw=0):
    path=KIT/(name+'.glb');doc,data=load_glb(path);prim=doc['meshes'][0]['primitives'][0]
    positions=accessor(doc,data,prim['attributes']['POSITION'])
    m=Matrix.Translation(Vector(at))@Matrix.Rotation(math.radians(yaw),4,'Y')
    points=[m@Vector(p) for p in positions]
    ids=[row[0] for row in accessor(doc,data,prim['indices'])]
    triangles=[ids[i:i+3] for i in range(0,len(ids),3)]
    return doc,data,prim,points,triangles


def inside_triangle(p,t):
    a,b,c=t;v0=c-a;v1=b-a;v2=p-a
    den=v0[0]*v1[1]-v1[0]*v0[1]
    if abs(den)<1e-14:return False
    u=(v2[0]*v1[1]-v1[0]*v2[1])/den
    v=(v0[0]*v2[1]-v2[0]*v0[1])/den
    return u>=-1e-6 and v>=-1e-6 and u+v<=1.000001


def main():
    out=ROOT/'output/fare-board-275';out.mkdir(parents=True,exist_ok=True)
    report={'checks':[],'swatches':[],'intersections':[]}
    def check(ok,label):
        report['checks'].append({'check':label,'passed':bool(ok)})
        if not ok:print('FAIL',label,flush=True)
    contract=json.loads((SOURCE/'asset-contract.json').read_text())
    provenance=json.loads((SOURCE/'atlas-swatches.json').read_text())
    atlas=ROOT/provenance['atlas']
    check(hashlib.sha256(atlas.read_bytes()).hexdigest()==provenance['atlas_sha256'],'Existing atlas SHA-256 unchanged')
    doc,data,prim,points,triangles=geometry('fare_board')
    uv=np.array(accessor(doc,data,prim['attributes']['TEXCOORD_0']))
    check(len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1,'One merged mesh / one surface')
    check(len(doc['materials'])==1 and doc['materials'][0]['name']=='RoomKit_SharedAtlas','Single RoomKit_SharedAtlas material')
    check(not doc.get('images') and not doc.get('textures'),'Kit convention: no duplicate embedded texture; runtime binds shared atlas')
    check(set(prim['attributes'])=={'POSITION','NORMAL','TEXCOORD_0'},'Positions/normals/UV only; no vertex colors or extra texture channels')
    check(len(triangles)==contract['triangles'] and len(triangles)<=800,'Exported triangle count / budget')
    box=np.array(points);lo=box.min(axis=0);hi=box.max(axis=0)
    check(np.max(np.abs(hi-lo-[.90,.65,.07]))<1e-6,'Actual GLB dimensions 0.90 x 0.65 x 0.07')
    check(abs(lo[2])<1e-6 and abs((lo[0]+hi[0])/2)<1e-6 and abs((lo[1]+hi[1])/2)<1e-6,'Back centre pivot and forward +Z geometry')
    check(all(n.get('scale',[1,1,1])==[1,1,1] and n.get('rotation',[0,0,0,1])==[0,0,0,1] for n in doc['nodes']),'Identity exported node scales and orientations')
    for name,target in contract['sockets'].items():
        node=next((n for n in doc['nodes'] if n.get('name')==name),{})
        got=node.get('translation',[])
        check(len(got)==3 and np.max(np.abs(np.array(got)-target))<1e-6,'Exact empty: '+name)
    normals=accessor(doc,data,prim['attributes']['NORMAL']);degenerate=bad=0
    for t in triangles:
        a,b,c=[points[i] for i in t];n=(b-a).cross(c-a)
        if n.length<1e-10:degenerate+=1
        average=Vector(tuple(sum(normals[i][j] for i in t) for j in range(3)))
        if n.dot(average)<-1e-9:bad+=1
    check(degenerate==0,'No degenerate mesh triangles')
    check(bad==0,'Triangle winding agrees with shading normals')
    choices={tuple(r['gltf_uv']) for r in provenance['swatches'].values()}
    check(set(map(tuple,uv))==choices,'Every exported UV is one of the six existing swatch centres')
    check(all(len({tuple(uv[i]) for i in t})==1 for t in triangles),'Each triangle samples one constant atlas point: no wood grain / no UV interpolation across islands')
    image=bpy.data.images.load(str(atlas));w,h=image.size
    pixels=np.array(image.pixels[:],dtype=np.float32).reshape(h,w,4)[::-1]
    for name,record in provenance['swatches'].items():
        path=ROOT/record['source_asset'];d,b=load_glb(path);p=d['meshes'][0]['primitives'][0]
        source_uv=np.array(accessor(d,b,p['attributes']['TEXCOORD_0']))
        indices=np.array(accessor(d,b,p['indices'])).reshape(-1,3)
        point=np.array(record['gltf_uv']);matching=[j for j,t in enumerate(indices) if inside_triangle(point,source_uv[t])]
        check(bool(matching) and hashlib.sha256(path.read_bytes()).hexdigest()==record['source_sha256'],'UV lies within actual source asset triangle: '+name)
        x,y=record['pixel_xy_top_left'];patch=pixels[y-3:y+4,x-3:x+4]
        check(patch.shape==(7,7,4) and float(patch[:,:,:3].sum(axis=2).min())>.01 and float(patch[:,:,3].min())>.99,'7x7 atlas footprint contains no black/blank pixels: '+name)
        report['swatches'].append({'name':name,'source_asset':record['source_asset'],'source_triangle':matching[0] if matching else None,'gltf_uv':record['gltf_uv'],'pixel_xy':record['pixel_xy_top_left'],'rgb8':record['rgb8'],'safe_radius_px':3})
    # Exact exported mesh placement, not collider boxes. Flush back-to-wall contact
    # is allowed within 0.1 mm; any penetration in front-facing geometry fails.
    layout=json.loads((KIT/'layout.json').read_text())
    placed={row['name']:row for row in layout['assets']}
    _,_,_,world,tris=geometry('fare_board',contract['placement']['position'],90)
    bvh=BVHTree.FromPolygons(world,tris,all_triangles=True,epsilon=0)
    for name in ['room_shell','window_wall','post_office_sign','postal_counter','magazine_rack','counter_computer','sorting_cabinet']:
        row=placed[name];_,_,_,other,other_tris=geometry(name,row['position'],row['yaw_degrees'])
        other_bvh=BVHTree.FromPolygons(other,other_tris,all_triangles=True,epsilon=0)
        contacts=bvh.overlap(other_bvh)
        penetrating=[];touches=[]
        for ia,ib in contacts:
            tri_a=[world[i] for i in tris[ia]];tri_b=[other[i] for i in other_tris[ib]]
            flush=name in ['room_shell','window_wall'] and all(abs(p.x+3.21)<.0001 for p in tri_b) and min(p.x for p in tri_a)>=-3.2101
            (touches if flush else penetrating).append((ia,ib))
        check(not penetrating,'No penetrating triangle overlap: '+name)
        report['intersections'].append({'name':name,'raw_contact_pairs':len(contacts),'flush_wall_contact_pairs':len(touches),'penetrating_pairs':len(penetrating)})
        if name=='window_wall':
            # Cast from the planned board front to the wall for each back-corner
            # and centre. Positive signed distance confirms solid support plane.
            distances=[]
            for y in [1.325,1.65,1.975]:
                for z in [-2.10,-1.65,-1.20]:
                    hit=other_bvh.ray_cast(Vector((-3.10,y,z)),Vector((-1,0,0)),.3)
                    distances.append(float(hit[0].x+3.21) if hit[0] else None)
            check(all(x is not None and abs(x)<.0001 for x in distances),'Nine wall rays confirm solid mounting surface at X=-3.21')
            report['wall_plane_errors_m']=distances
        if name=='post_office_sign':
            gap=min(p.y for p in other)-max(p.y for p in world)
            check(gap>=.1,'Board top below actual postal sign by >= 0.1 m')
            report['sign_vertical_gap_m']=gap
    # Detector positive control moves the board through the real counter.
    row=placed['postal_counter'];_,_,_,other,ot=geometry('postal_counter',row['position'],row['yaw_degrees'])
    _,_,_,bad_points,bt=geometry('fare_board',(-.58,1.30,-.54),0)
    bad_hits=BVHTree.FromPolygons(bad_points,bt,all_triangles=True).overlap(BVHTree.FromPolygons(other,ot,all_triangles=True))
    check(bool(bad_hits),'Positive control detects deliberately misplaced board inside counter')
    report['positive_control_pairs']=len(bad_hits)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'fare_board.blend'))
    objects=list(bpy.data.collections['fare_board'].objects)
    bars=sorted([o for o in objects if '/ blank ivory bar' in o.name],key=lambda o:o.name)
    dots=[o for o in objects if '/ colored round dot' in o.name]
    check(len(bars)==7 and len(dots)==7,'Seven named blank bars and seven colored dots')
    check(all(o.type in ['MESH','EMPTY'] for o in objects),'No text objects or curves in editable source')
    centres=[]
    for obj in bars:
        ys=[v.co.z for v in obj.data.vertices];centres.append((min(ys)+max(ys))/2)
        check(abs(max(ys)-min(ys)-.030)<1e-6,'Actual bar height 0.030 m: '+obj.name)
    check(all(abs(centres[i]-centres[i+1]-.065)<1e-6 for i in range(6)),'Seven actual bar centres have 0.065 m pitch')
    report['asset']={'triangles':len(triangles),'surfaces':1,'bounds':[lo.tolist(),hi.tolist()],'sha256':hashlib.sha256((KIT/'fare_board.glb').read_bytes()).hexdigest()}
    report['failures']=[c for c in report['checks'] if not c['passed']]
    (out/'glb-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('FARE_BINARY_QA',len(report['checks']),'checks',len(report['failures']),'failures',flush=True)
    if report['failures']:raise RuntimeError('Fare Board validation failed')


if __name__=='__main__':main()
