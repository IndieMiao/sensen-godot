#!/usr/bin/env python3
"""Independent GLB byte/UV audit and actual room-mesh BVH overlap checks.
Run with Blender --background --factory-startup --python (absolute path).
"""
import hashlib,json,math,sys
from pathlib import Path
import bpy,numpy as np
from mathutils import Matrix,Vector,Quaternion,Euler
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_chef_sign import load_glb,accessor
from verify_fare_board import inside_triangle
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/warming-cabinet-282'
ASSET=ROOT/'assets/props/warming_cabinet'
SOURCE=ROOT/'tools/art/source/warming_cabinet_282'

def matrix(at=(0,0,0),yaw=0,scale=(1,1,1),rotation=None):
    r=Euler(tuple(math.radians(x) for x in rotation),'YXZ').to_matrix().to_4x4() if rotation else Matrix.Rotation(math.radians(yaw),4,'Y')
    if isinstance(scale,(float,int)):scale=[scale]*3
    return Matrix.Translation(Vector(at))@r@Matrix.Diagonal((*scale,1))

def geometry(path,placement=None):
    doc,data=load_glb(path);verts=[];tris=[];groups={};placement=placement or Matrix.Identity(4)
    def node(index,parent):
        n=doc['nodes'][index]
        if 'matrix' in n:local=Matrix(np.array(n['matrix']).reshape(4,4).T.tolist())
        else:
            r=n.get('rotation',[0,0,0,1]);local=Matrix.Translation(Vector(n.get('translation',[0,0,0])))@Quaternion((r[3],*r[:3])).to_matrix().to_4x4()@Matrix.Diagonal((*n.get('scale',[1,1,1]),1))
        m=parent@local
        if 'mesh' in n:
            first=len(verts)
            for p in doc['meshes'][n['mesh']]['primitives']:
                points=[m@Vector(p) for p in accessor(doc,data,p['attributes']['POSITION'])];base=len(verts);verts.extend(points)
                ids=[r[0]+base for r in accessor(doc,data,p['indices'])];tris.extend([ids[i:i+3] for i in range(0,len(ids),3)])
            groups[n['name']]=verts[first:]
        for child in n.get('children',[]):node(child,m)
    for i in doc['scenes'][doc.get('scene',0)]['nodes']:node(i,placement)
    return doc,data,verts,tris,groups

def bounds(v):
    a=np.array(v);return [a.min(0).tolist(),a.max(0).tolist()]

def main():
    report={'checks':[],'assets':{},'swatches':[],'rooms':{},'method':'GLB scene transforms -> actual triangle BVHs. All kit modules, instances, shared plants and approved seasoning props. AABB separation plus surface intersections; wall/back clearance also measured.'}
    def check(ok,label):
        report['checks'].append({'check':label,'passed':bool(ok)})
        if not ok:print('FAIL',label,flush=True)
    c=json.loads((ASSET/'manifest.json').read_text());sw=json.loads((SOURCE/'atlas-swatches.json').read_text());fixture=json.loads((SOURCE/'review-fixture.json').read_text())
    check(hashlib.sha256((ASSET/'room_albedo_ao.png').read_bytes()).hexdigest()==sw['atlas_sha256']==hashlib.sha256((ROOT/sw['source_atlas']).read_bytes()).hexdigest(),'Main atlas is byte-identical to Deluxe and placeholder atlas')
    tex=bpy.data.images.load(str(ASSET/'room_albedo_ao.png'));w,h=tex.size;pixels=np.array(tex.pixels[:]).reshape(h,w,4)[::-1]
    choices=[]
    for name,row in sw['swatches'].items():
        p=ROOT/row['source_asset'];d,b=load_glb(p);pr=d['meshes'][row['source_mesh']]['primitives'][row['source_primitive']]
        uv=np.array(accessor(d,b,pr['attributes']['TEXCOORD_0']));ix=np.array(accessor(d,b,pr['indices'])).reshape(-1,3)
        check(inside_triangle(np.array(row['gltf_uv']),uv[ix[row['source_triangle']]]),name+' sample inside original asset UV triangle')
        check(hashlib.sha256(p.read_bytes()).hexdigest()==row['source_sha256'],name+' original source mesh unchanged')
        x,y=row['pixel_xy'];patch=pixels[y-3:y+4,x-3:x+4]
        check(patch.shape==(7,7,4) and patch[:,:,:3].min()>.01 and patch[:,:,3].min()>.99,name+' atlas patch nonblack / nonblank')
        choices.append(row['gltf_uv']);report['swatches'].append({'name':name,**row})
    shared={}
    for option in ['a','b']:
        path=ASSET/f'warming_cabinet_{option}.glb';d,b,v,t,g=geometry(path);lo,hi=np.array(bounds(v));size=hi-lo
        check(np.max(abs(size-[.56,1.32,.50]))<1e-6,option+' packed GLB dimensions')
        check(np.max(abs(lo-[-.28,0,0]))<1e-6,option+' grounded back-plane pivot')
        check(len(t)==c['variants'][option]['triangles'] and len(t)<=1500,option+' exported triangle count')
        check(all(n.get('scale',[1,1,1])==[1,1,1] and n.get('rotation',[0,0,0,1])==[0,0,0,1] for n in d['nodes']),option+' no rotated / scaled imported nodes')
        check(len(g)==(9 if option=='a' else 8),option+' only cabinet, six dishes, glass cues and optional pane')
        check(not d.get('extensions',{}).get('KHR_lights_punctual'),option+' no real-time light')
        for name,at in c['sockets'].items():
            n=next((n for n in d['nodes'] if n.get('name')==name),{})
            check('mesh' not in n and np.max(abs(np.array(n.get('translation',[999]*3))-at))<1e-6,option+' exact empty socket '+name)
        degenerate=bad=0;signature={}
        for n in d['nodes']:
            if 'mesh' not in n:continue
            entries=[]
            for p in d['meshes'][n['mesh']]['primitives']:
                positions=np.array(accessor(d,b,p['attributes']['POSITION']));normals=np.array(accessor(d,b,p['attributes']['NORMAL']));uv=np.array(accessor(d,b,p['attributes']['TEXCOORD_0']));idx=np.array(accessor(d,b,p['indices'])).reshape(-1,3)
                edges=positions[idx];cross=np.cross(edges[:,1]-edges[:,0],edges[:,2]-edges[:,0]);degenerate+=int((np.linalg.norm(cross,axis=1)<1e-10).sum());bad+=int((np.sum(cross*normals[idx].sum(1),axis=1)<-1e-9).sum())
                material=d['materials'][p['material']];name=material['name']
                allowed=choices if name=='Warming_SharedAtlas' else [[.25,.25],[.75,.25],[.25,.75],[.75,.75]] if name=='Warming_InteriorFood' else [[.5,.5]]
                check(all(min(np.linalg.norm(q-a) for a in allowed)<1e-6 for q in uv),option+' UVs sample approved palette centres: '+n['name']+'/'+name)
                check(all(np.max(abs(uv[tri]-uv[tri[0]]))<1e-7 for tri in idx),option+' constant UV per triangle: '+n['name']+'/'+name)
                check(not material.get('emissiveFactor') or max(material['emissiveFactor'])==0,option+' material has no emission '+name)
                entries.append((name,hashlib.sha256(positions.tobytes()+normals.tobytes()+uv.tobytes()+idx.tobytes()).hexdigest()))
            signature[n['name']]=entries
        check(degenerate==0,option+' no degenerate triangles');check(bad==0,option+' triangle winding agrees with normals')
        for name in ['cabinet','highlights']+[f'dish_{i}' for i in range(1,7)]:
            if option=='a':shared[name]=signature[name]
            else:check(shared[name]==signature[name],'A/B byte-identical geometry/material/UV: '+name)
        report['assets'][option]={'triangles':len(t),'size':size.tolist(),'bounds':[lo.tolist(),hi.tolist()],'nodes':list(g),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    for slug,pose in c['placements'].items():
        kit=ROOT/'assets/rooms'/slug;layout=json.loads((kit/'layout.json').read_text());modules={r['name']:r for r in layout['assets']};rows=[]
        for row in layout['assets']+layout.get('instances',[]):
            source=modules[row.get('asset',row['name'])];rows.append((row['name'],kit/source['file'],matrix(row['position'],row.get('yaw_degrees',0),row.get('scale',[1,1,1]))))
        for row in layout.get('shared_plants',[]):rows.append((row['name'],ROOT/'assets/rooms/_shared/plants'/row['file'],matrix(row['position'],scale=row.get('scale',[1,1,1]),rotation=row.get('rotation_degrees',[0,0,0]))))
        for row in fixture['anchors'][slug]['props']:rows.append((row['name'],kit/modules[row['from']]['file'],matrix(row['position'],row['yaw_degrees'],row['scale'])))
        _,_,v,t,_=geometry(ASSET/'warming_cabinet_a.glb',matrix(pose['position'],pose['yaw_degrees']));tree=BVHTree.FromPolygons(v,t,all_triangles=True);lo,hi=np.array(bounds(v));results=[]
        for name,path,transform in rows:
            _,_,v2,t2,_=geometry(path,transform);lo2,hi2=np.array(bounds(v2));separation=np.maximum(lo-hi2,lo2-hi) # positive if separated on an axis
            pairs=[];floor=[]
            other=BVHTree.FromPolygons(v2,t2,all_triangles=True)
            if (separation<=0).all():
                for a,b in tree.overlap(other):
                    # Layout floor is Y .0825, specified mounting Y .082. This
                    # existing 0.5 mm support contact is not a room obstacle.
                    floor_touch=name=='room_shell' and min(v[i].y for i in t[a])>=pose['position'][1]-.000001 and max(v2[i].y for i in t2[b])<=pose['position'][1]+.0006
                    (floor if floor_touch else pairs).append((a,b))
            check(not pairs,slug+' no penetrating mesh intersections: '+name)
            results.append({'name':name,'source':str(path.relative_to(ROOT)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bounds':[lo2.tolist(),hi2.tolist()],'axis_separation_m':separation.tolist(),'penetrating_pairs':len(pairs),'floor_support_pairs':len(floor)})
        # Positive control pushes the full cabinet back through the real west wall.
        wall=next(r for r in rows if r[0]=='window_wall');_,_,wv,wt,_=geometry(wall[1],wall[2]);shifted=[p-Vector((.30,0,0)) for p in v]
        hits=BVHTree.FromPolygons(shifted,t,all_triangles=True).overlap(BVHTree.FromPolygons(wv,wt,all_triangles=True))
        check(bool(hits),slug+' overlap detector catches deliberate wall penetration')
        wall_tree=BVHTree.FromPolygons(wv,wt,all_triangles=True)
        gaps=[]
        for yy in [.18,.60,1.0,1.3]:
            for zz in [-.20,0,.20]:
                start=Vector((pose['position'][0],yy,pose['position'][2]+zz))
                hit=wall_tree.ray_cast(start,Vector((-1,0,0)),.40)
                gaps.append(float(hit[3]) if hit[0] is not None else None)
        check(all(g is not None and g>.001 for g in gaps),slug+' twelve back-plane rays confirm wall/skirting clearance >1 mm')
        report['rooms'][slug]={'wall_clearance_rays_m':gaps,'pose':pose,'world_bounds':[lo.tolist(),hi.tolist()],'objects':results,'positive_control_intersections':len(hits)}
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'warming_cabinet.blend'))
    objects=[o for o in bpy.data.objects if o.type=='MESH']
    check(len([o for o in objects if 'single vertical mullion' in o.name])==1,'Source has one vertical door mullion')
    check(not any('horizontal mullion' in o.name for o in objects),'Source has no horizontal door mullion')
    check(len([o for o in objects if 'honey ledge' in o.name])==3,'Source has three shelves')
    check(len([o for o in objects if 'rounded foot' in o.name])==4,'Source has four named rounded feet')
    check(not any(o.type in ['FONT','LIGHT'] for o in bpy.data.objects),'Source has no text or lights')
    report['failures']=[r for r in report['checks'] if not r['passed']]
    (OUT/'glb-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('WARMING_BINARY_QA',len(report['checks']),'checks',len(report['failures']),'failures',flush=True)
    if report['failures']:raise RuntimeError('Warming cabinet validation failed')
if __name__=='__main__':main()
