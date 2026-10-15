#!/usr/bin/env python3
"""Independent packed-GLB dimensions/UV/winding/socket and real-room mesh audit.
Run in Blender for BVH and numeric utilities. Tests all nine approved stove
positions, both variants, lid travel, adjacent pairs, and true support rays.
"""
import hashlib,json,math,sys
from pathlib import Path
import argparse
import bpy,numpy as np
from mathutils import Matrix,Vector,Quaternion
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_chef_sign import load_glb,accessor
from verify_warming_cabinet import geometry,matrix,bounds
from verify_fare_board import inside_triangle
ROOT=Path(__file__).resolve().parents[2];ASSET=ROOT/'assets/props/stove_pot';SOURCE=ROOT/'tools/art/source/stove_pot_282';OUT=ROOT/'output/stove-pot-282'

def pot_geometry(variant,opening=0,at=(0,0,0),only=None,yaw=0):
    d,b=load_glb(ASSET/'stove_pot.glb');verts=[];tris=[];nodes={};groups={}
    def visit(i,parent,path):
        n=d['nodes'][i];name=n['name'];path=path+'/'+name if path else name
        q=n.get('rotation',[0,0,0,1]);p=Vector(n.get('translation',[0,0,0]));r=Quaternion((q[3],*q[:3])).to_matrix().to_4x4()
        if name=='lid':p.y+=.06*opening;r=Matrix.Rotation(math.radians(-20)*opening,4,'X')@r
        local=Matrix.Translation(p)@r@Matrix.Diagonal((*n.get('scale',[1,1,1]),1));m=parent@local;nodes[path]=m.translation[:]
        if 'mesh' in n and (only is None or only==name):
            start=len(verts);ts=len(tris)
            for pr in d['meshes'][n['mesh']]['primitives']:
                base=len(verts);verts.extend([m@Vector(p) for p in accessor(d,b,pr['attributes']['POSITION'])]);idx=[v[0]+base for v in accessor(d,b,pr['indices'])];tris.extend([idx[j:j+3] for j in range(0,len(idx),3)])
            groups[name]={'bounds':bounds(verts[start:]),'triangles':len(tris)-ts}
        for c in n.get('children',[]):visit(c,m,path)
    i=next(i for i,n in enumerate(d['nodes']) if n['name']==variant)
    visit(i,matrix(at,yaw),'');return verts,tris,nodes,groups

def tree(v,t):return BVHTree.FromPolygons(v,t,all_triangles=True)
def main():
    parser=argparse.ArgumentParser();parser.add_argument("--original-deluxe",action="store_true");args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    OUT.mkdir(parents=True,exist_ok=True)
    if not args.original_deluxe:
        from prepare_stove_pot_deluxe_fixture import prepare
        fixture_mesh=prepare(OUT/'review-fixture/kitchen_fittings.glb')
    report={'checks':[],'assets':{},'lid_travel':[],'rooms':{},'method':'Parsed GLB transforms and actual triangles; BVH intersections after AABB broad phase; support rays on real stove top; positive control. Distances are geometry, not image estimates.'}
    def check(ok,label):
        report['checks'].append({'check':label,'passed':bool(ok)})
        if not ok:print('FAIL',label,flush=True)
    c=json.loads((ASSET/'manifest.json').read_text());sw=json.loads((SOURCE/'atlas-swatches.json').read_text());fix=json.loads((SOURCE/'review-fixture.json').read_text())
    d,b=load_glb(ASSET/'stove_pot.glb');roots=[d['nodes'][i]['name'] for i in d['scenes'][d.get('scene',0)]['nodes']]
    check(sorted(roots)==['pot_big','pot_normal'],'GLB scene has exactly two variant roots')
    check(all(np.max(abs(np.array(n.get('scale',[1,1,1]))-1))<1e-6 for n in d['nodes']),'all node scales are 1')
    check('gltf/texture_map_mode=1' in (ASSET/'stove_pot.glb.import').read_text(),'import texture_map_mode=1')
    check(hashlib.sha256((ROOT/sw['atlas']).read_bytes()).hexdigest()==sw['atlas_sha256'],'shared room atlas unchanged')
    honey=sw['swatches']['honey'];sd,sb=load_glb(ROOT/honey['source_asset']);pr=sd['meshes'][honey['source_mesh']]['primitives'][honey['source_primitive']];uv=np.array(accessor(sd,sb,pr['attributes']['TEXCOORD_0']));idx=np.array(accessor(sd,sb,pr['indices'])).reshape(-1,3)
    check(inside_triangle(np.array(honey['gltf_uv']),uv[idx[honey['source_triangle']]]),'wood UV lies inside original pantry triangle')
    check(hashlib.sha256((ROOT/honey['source_asset']).read_bytes()).hexdigest()==honey['source_sha256'],'wood source pantry unchanged')
    textures={}
    for i,im in enumerate(d['images']):
        path=ASSET/im['uri'];tex=bpy.data.images.load(str(path));w,h=tex.size;pixels=np.array(tex.pixels[:]).reshape(h,w,4)[::-1];textures[i]=(w,h,pixels)
    deg=wrong=0
    for mesh in d['meshes']:
        for p in mesh['primitives']:
            mat=d['materials'][p['material']];uv=np.array(accessor(d,b,p['attributes']['TEXCOORD_0']));v=np.array(accessor(d,b,p['attributes']['POSITION']));norm=np.array(accessor(d,b,p['attributes']['NORMAL']));ix=np.array(accessor(d,b,p['indices'])).reshape(-1,3)
            cross=np.cross(v[ix[:,1]]-v[ix[:,0]],v[ix[:,2]]-v[ix[:,0]]);deg+=int((np.linalg.norm(cross,axis=1)<1e-10).sum());wrong+=int((np.sum(cross*norm[ix].sum(1),axis=1)<-1e-9).sum())
            allowed=[honey['gltf_uv']] if mat['name']=='StovePot_SharedRoomAtlas' else [[.25,.25],[.75,.25],[.25,.75],[.75,.75]]
            check(all(min(np.linalg.norm(q-a) for a in allowed)<1e-6 for q in uv),'approved constant palette UV: '+mesh['name']+'/'+mat['name'])
            check(all(np.max(abs(uv[t]-uv[t[0]]))<1e-7 for t in ix),'no UV interpolation across colors: '+mesh['name']+'/'+mat['name'])
            ti=d['textures'][mat['pbrMetallicRoughness']['baseColorTexture']['index']]['source'];w,h,pixels=textures[ti]
            check(all(pixels[int(q[1]*h)-3:int(q[1]*h)+4,int(q[0]*w)-3:int(q[0]*w)+4,:3].min()>.01 for q in np.unique(uv,axis=0)),'UV footprint nonblack and nonblank: '+mesh['name']+'/'+mat['name'])
            check(mat.get('alphaMode','OPAQUE')=='OPAQUE' and not any(mat.get('emissiveFactor',[0,0,0])),'opaque / no emission '+mat['name'])
    check(deg==0,'no degenerate triangles');check(wrong==0,'triangle winding agrees with normals')
    for variant,limit,width,height in [('pot_normal',400,.24,.14),('pot_big',700,.28,.242)]:
        v,t,n,g=pot_geometry(variant);lo,hi=np.array(bounds(v));size=hi-lo
        check(len(t)==c['variants'][variant]['triangles'] and len(t)<=limit,variant+' triangle budget')
        check(size[0]<=width+1e-6 and size[2]<=width+1e-6,variant+' diameter including ears')
        check(abs(lo[1])<1e-6 and np.max(abs((hi+lo)[[0,2]]/2))<1e-6,variant+' bottom centre origin')
        check(abs(size[1]-height)<1e-5,variant+' height')
        check(np.max(abs(np.array(n[variant+'/mouth'])-c['variants'][variant]['mouth']))<1e-6,variant+' exact mouth path/position')
        body='normal_body' if variant=='pot_normal' else 'big_body';bv,bt,_,_=pot_geometry(variant,only=body);hit=tree(bv,bt).ray_cast(Vector((0,.4,0)),Vector((0,-1,0)),1)
        check(hit[0] is not None and hit[0].y<.025,variant+' open empty interior; centre ray hits floor only')
        report['assets'][variant]={'triangles':len(t),'bounds':[lo.tolist(),hi.tolist()],'size_xyz':size.tolist(),'nodes':n,'groups':g,'interior_floor_y':hit[0].y if hit[0] else None}
    check(sum(x['triangles'] for x in report['assets'].values())<=1100,'whole GLB triangle budget')
    _,_,nodes,_=pot_geometry('pot_big');check(np.max(abs(np.array(nodes['pot_big/lid'])-c['variants']['pot_big']['lid_pivot']))<1e-6,'rear edge lid pivot');check(np.max(abs(np.array(nodes['pot_big/vent'])-c['variants']['pot_big']['vent']))<1e-6,'independent direct-child vent at outlet')
    bv,bt,_,_=pot_geometry('pot_big',only='big_body');bodytree=tree(bv,bt)
    for amount in np.linspace(0,1,11):
        lv,lt,_,_=pot_geometry('pot_big',amount,only='lid_mesh');pairs=bodytree.overlap(tree(lv,lt));gap=min(v.y for v in lv)-max(v.y for v in bv)
        check(not pairs,f'lid/body/handles clear at {amount:.1f} travel');report['lid_travel'].append({'fraction':float(amount),'triangle_intersections':len(pairs),'vertical_gap_m':gap})
    for slug,placement in c['placements'].items():
        kit=ROOT/'assets/rooms'/slug;layout=json.loads((kit/'layout.json').read_text());modules={r['name']:r for r in layout['assets']};rows=[]
        for row in layout['assets']+layout.get('instances',[]):
            if row['name'] in placement['hide']:continue
            source=modules[row.get('asset',row['name'])];rows.append((row['name'],kit/source['file'],matrix(row['position'],row.get('yaw_degrees',0),row.get('scale',[1,1,1]))))
        for row in layout.get('shared_plants',[]):rows.append((row['name'],ROOT/'assets/rooms/_shared/plants'/row['file'],matrix(row['position'],scale=row.get('scale',[1,1,1]),rotation=row.get('rotation_degrees',[0,0,0]))))
        for row in fix['anchors'][slug]['props']:
            path=kit/modules[row['from']]['file'] if 'from' in row else ROOT/row['scene'].removeprefix('res://').replace('/warming_cabinet.glb','/warming_cabinet_b.glb')
            rows.append((row['name'],path,matrix(row['position'],row.get('yaw_degrees',0),row.get('scale',1))))
        obstacles=[]
        for name,path,m in rows:
            effective=fixture_mesh if not args.original_deluxe and slug=='deluxe_room_10' and name=='kitchen_fittings' else path
            _,_,v,t,_=geometry(effective,m);obstacles.append((name,v,t,tree(v,t),np.array(bounds(v)),str(path.relative_to(ROOT)),hashlib.sha256(path.read_bytes()).hexdigest(),hashlib.sha256(effective.read_bytes()).hexdigest()))
        room={'stoves':[],'neighbor_pairs':[],'objects':[{'name':o[0],'source':o[5],'sha256':o[6],'bounds':o[4].tolist(),'effective_geometry_sha256':o[7]} for o in obstacles]}
        for number,(x,z) in enumerate(placement['xz'],1):
            at=[x,placement['y'],z];yaw=45 if slug=='standard_room_5' and number==3 else 0;records=[]
            for variant,opening in [('pot_normal',0),('pot_big',0),('pot_big',1)]:
                v,t,_,_=pot_geometry(variant,opening,at,yaw=yaw);ptree=tree(v,t);lo,hi=np.array(bounds(v));results=[]
                for name,ov,ot,otree,bb,_,_,_ in obstacles:
                    gap=np.maximum(lo-bb[1],bb[0]-hi);bad=[];support=[]
                    if (gap<=.000001).all():
                        for a,b in ptree.overlap(otree):
                            # Rounded stove coordinates have <=1 mm support tolerance;
                            # never suppress the support mesh's raised chimney geometry.
                            touch=name==placement['support'] and min(v[i].y for i in t[a])>=at[1]-.000001 and max(ov[i].y for i in ot[b])<=at[1]+.0011
                            (support if touch else bad).append((a,b))
                    if (gap<=.01).all() or name in ['range_hood','hearth','spice_rack','hanging_cookware']:
                        results.append({'name':name,'axis_separation_m':gap.tolist(),'penetrating_pairs':len(bad),'support_contact_pairs':len(support)})
                    check(not bad,f'{slug} stove {number} {variant} open={opening} clears {name}')
                records.append({'variant':variant,'open_fraction':opening,'bounds':[lo.tolist(),hi.tolist()],'nearby':results})
            support=next(o for o in obstacles if o[0]==placement['support']);samples=[]
            # Grates are open in their centres: sample the footprint in addition
            # to its centre, recording actual highest supporting metal/stone.
            for dx,dz in [(dx,dz) for dx in [-.07,-.065,-.06,-.055,-.035,0,.035,.055,.06,.065,.07] for dz in [-.07,-.065,-.06,-.055,-.035,0,.035,.055,.06,.065,.07]]:
                start=Vector((x+dx,placement['y']+.012,z+dz));hit=support[3].ray_cast(start,Vector((0,-1,0)),.15)
                if hit[0] is not None:samples.append({'offset':[dx,dz],'y':float(hit[0].y)})
            top=max(r['y'] for r in samples);check(abs(top-placement['y'])<.0011,f'{slug} stove {number} real support top within 1.1 mm rounding tolerance')
            room['stoves'].append({'stove':number,'position':at,'yaw_degrees':yaw,'support_rays':samples,'measured_support_top':top,'states':records})
        for a in range(3):
            for bidx in range(a+1,3):
                at=[placement['xz'][a][0],placement['y'],placement['xz'][a][1]];other=[placement['xz'][bidx][0],placement['y'],placement['xz'][bidx][1]]
                av,atris,_,_=pot_geometry('pot_big',at=at,yaw=45 if slug=='standard_room_5' and a==2 else 0);bv,btris,_,_=pot_geometry('pot_big',at=other,yaw=45 if slug=='standard_room_5' and bidx==2 else 0);pairs=tree(av,atris).overlap(tree(bv,btris));alo,ahi=np.array(bounds(av));blo,bhi=np.array(bounds(bv));gap=np.maximum(alo-bhi,blo-ahi)
                check(not pairs and max(gap)>0,f'{slug} Big Pots {a+1}/{bidx+1} separated');room['neighbor_pairs'].append({'stoves':[a+1,bidx+1],'axis_separation_m':gap.tolist(),'penetrating_pairs':len(pairs)})
        # Deliberately sink a pot 2 cm into the stove to exercise actual detector.
        x,z=placement['xz'][0];v,t,_,_=pot_geometry('pot_big',at=[x,placement['y']-.02,z]);support=next(o for o in obstacles if o[0]==placement['support']);hits=tree(v,t).overlap(support[3])
        check(bool(hits),slug+' positive control detects sunken pot');room['positive_control_pairs']=len(hits);report['rooms'][slug]=room
    report['sha256']=hashlib.sha256((ASSET/'stove_pot.glb').read_bytes()).hexdigest();report['failures']=[r for r in report['checks'] if not r['passed']]
    report['deluxe_fixture']='approved review fixture without built-in kettle' if not args.original_deluxe else 'unchanged room asset'
    (OUT/('original-room-validation.json' if args.original_deluxe else 'glb-validation.json')).write_text(json.dumps(report,indent=2)+'\n');print('STOVE_POT_BINARY_QA',len(report['checks']),'checks',len(report['failures']),'failures',flush=True)
    if report['failures']:raise RuntimeError('Stove pot validation failed')
if __name__=='__main__':main()
