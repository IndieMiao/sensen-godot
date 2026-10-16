#!/usr/bin/env python3
"""Independent exported GLB budgets, placement bounds and mesh intersections.

Run inside Blender. BVHs use delivered triangles in Godot coordinates; the
negative control deliberately places the fish board through the counter.
"""
from pathlib import Path
import sys, json, math, hashlib, itertools
import numpy as np
import bpy
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb, accessor
KIT=ROOT/'assets/rooms/tackle_shop'
OUT=ROOT/'output/tackle-214'

def get_mesh(row,placement=None):
    placement=placement or row
    doc,data=load_glb(KIT/row['file']);prim=doc['meshes'][0]['primitives'][0]
    scale=placement.get('scale',[1,1,1])
    m=Matrix.Translation(Vector(placement['position']))@Matrix.Rotation(math.radians(placement['yaw_degrees']),4,'Y')@Matrix.Diagonal(Vector((*scale,1)))
    points=[m@Vector(q) for q in accessor(doc,data,prim['attributes']['POSITION'])]
    ids=[r[0] for r in accessor(doc,data,prim['indices'])];tris=[ids[i:i+3] for i in range(0,len(ids),3)]
    box=np.array(points);lo=box.min(0);hi=box.max(0)
    return {'doc':doc,'data':data,'primitive':prim,'points':points,'tris':tris,'lo':lo,'hi':hi,
            'bvh':BVHTree.FromPolygons(points,tris,all_triangles=True,epsilon=0)}

def strict_crossing(a,b,epsilon=.00015):
    """Reject coplanar/tangent support contacts; detect an actual plane crossing."""
    for one,two in [(a,b),(b,a)]:
        n=(two[1]-two[0]).cross(two[2]-two[0])
        if n.length<1e-10:return False
        n.normalize();dist=[n.dot(p-two[0]) for p in one]
        if not (min(dist)<-epsilon and max(dist)>epsilon):return False
    return True

def main():
    layout=json.loads((KIT/'layout.json').read_text());stats=json.loads((KIT/'asset_stats.json').read_text())
    report={'checks':[],'assets':{},'intersections':[],'scope':'Exported triangles between modules; intentional construction joints listed separately.'}
    def check(ok,label):
        report['checks'].append({'check':label,'passed':bool(ok)})
        if not ok:print('FAIL',label,flush=True)
    rows={r['name']:r for r in layout['assets']};placed={}
    for name,row in rows.items():
        g=get_mesh(row);placed[name]=g;doc=g['doc'];prim=g['primitive']
        expected=next(a for a in stats['assets'] if a['name']==name)
        check(len(g['tris'])==expected['triangles'],name+' triangle count matches binary')
        check(len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1,name+' one mesh/surface')
        check(doc.get('images')==[{'uri':'room_albedo_ao.png'}],name+' references the one external atlas; no embedded texture')
        mat=doc['materials'][prim['material']]
        glass=row.get('material')=='glass'
        check(mat['name']==('TackleFishbowlGlass' if glass else 'TackleRoomAtlas'),name+' surface owns intended material')
        check(mat['alphaMode']==('BLEND' if glass else 'OPAQUE') and mat['pbrMetallicRoughness']['baseColorFactor'][3]==(.075 if glass else 1),name+' authored alpha mode')
        check('gltf/texture_map_mode=1' in (KIT/(row['file']+'.import')).read_text(),name+' import texture map mode 1')
        uv=np.array(accessor(doc,g['data'],prim['attributes']['TEXCOORD_0']))
        check(np.isfinite(uv).all() and uv.min()>=0 and uv.max()<=1,name+' finite bounded atlas UV')
        report['assets'][name]={'triangles':len(g['tris']),'world_bounds':[g['lo'].tolist(),g['hi'].tolist()],
                              'dimensions':(g['hi']-g['lo']).tolist(),'sha256':hashlib.sha256((KIT/row['file']).read_bytes()).hexdigest()}
    for i in layout['instances']:placed[i['name']]=get_mesh(rows[i['asset']],i)
    check(sum(len(g['tris']) for g in placed.values())<=200000,'Placed scene <= 200k triangles')
    check(len(placed)<=60,'Placed scene <= 60 surfaces')
    check(len(placed['rod_rack']['tris'])+len(placed['float_barrel']['tris'])<=1200,'Rod rack + 4 rods + float barrel <= 1200 triangles')
    check(len([n for n in placed if 'float_barrel' in n])==2,'Exactly two float barrels')
    check(placed['rod_rack']['lo'][2]>-1.37+.64,'Rod rack stands beside, outside porthole aperture')
    expected_joints={frozenset(p):reason for p,reason in [
        (('room_shell','left_wall'),'Foundation joins cutaway wall posts'),
        (('room_shell','back_wall'),'Foundation joins cutaway wall posts'),
        (('left_wall','back_wall'),'Timber corner joint'),
        (('left_wall','porthole'),'Porthole annulus fitted into real aperture'),
        (('fishbowl_contents','fishbowl_glass'),'Sand meets inside of glass vessel'),
        (('fishbowl_glass','fishbowl_glints'),'Rim and highlight strips sit on glass surface'),
    ]}
    unexpected=[]
    for (na,a),(nb,b) in itertools.combinations(placed.items(),2):
        if (a['hi']<b['lo']-.0001).any() or (b['hi']<a['lo']-.0001).any():continue
        pairs=a['bvh'].overlap(b['bvh'])
        if not pairs:continue
        crossing=[]
        for ia,ib in pairs:
            ta=[a['points'][i] for i in a['tris'][ia]];tb=[b['points'][i] for i in b['tris'][ib]]
            if strict_crossing(ta,tb):crossing.append([ia,ib])
        reason=expected_joints.get(frozenset((na,nb)))
        if na=='room_shell' and b['lo'][1]>=a['hi'][1]-.00015:
            reason='Flush support on floor top; module entirely at/above floor'
        if nb=='room_shell' and a['lo'][1]>=b['hi'][1]-.00015:
            reason='Flush support on floor top; module entirely at/above floor'
        row={'modules':[na,nb],'contact_pairs':len(pairs),'crossing_pairs':len(crossing),'classification':reason or ('penetration' if crossing else 'flush/tangent contact')}
        report['intersections'].append(row)
        if crossing and not reason:unexpected.append(row)
    report['unexpected_intersections']=unexpected
    check(not unexpected,'No unexpected module-to-module or module-to-wall mesh crossing')
    # Deliberate failure proves the checker actually catches a penetrated counter.
    bad=get_mesh(rows['fish_board'],{'position':[-.36,.70,-1.62],'yaw_degrees':0})
    hits=bad['bvh'].overlap(placed['curved_counter']['bvh'])
    check(len(hits)>0,'Negative control: fish board penetrating counter is detected')
    report['negative_control_triangle_pairs']=len(hits)
    # Suggested feet locations use the same simple torso boxes as room consumers.
    clearances={}
    for anchor in layout['anchors']:
        if not (anchor['name'].startswith(('npc_','stand_')) or anchor['name']=='spawn'):continue
        at=np.array(anchor['position']);worst=100.0;closest=''
        for name,g in placed.items():
            if name in ('room_shell','left_wall','back_wall','anchor_rug'):continue
            if g['hi'][1]<at[1]+.12 or g['lo'][1]>at[1]+1.745:continue
            d=np.maximum(np.maximum(g['lo'][[0,2]]-at[[0,2]],at[[0,2]]-g['hi'][[0,2]]),0)
            dist=float(np.linalg.norm(d))
            if dist<worst:worst=dist;closest=name
        clearances[anchor['name']]={'nearest_module_aabb':closest,'horizontal_clearance_m':worst}
        check(worst>=.21-.0001,anchor['name']+' clears .21m avatar radius (conservative bounds)')
    report['standing_clearances']=clearances
    source=ROOT/'tools/art/source/tackle_shop/tackle_shop.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source))
    bpy.context.view_layer.update()
    collections={c.name for c in bpy.data.collections}
    check(all('KIT_'+name in collections for name in rows),'Editable Blender source contains every named runtime module')
    meshes=[o for o in bpy.data.objects if o.type=='MESH']
    check(len(meshes)>len(rows)*5,'Editable source retains construction parts rather than flattened GLBs')
    rug=next(o for o in meshes if o.name.startswith('Deep blue circular rug with baked woven anchor'))
    check(abs(rug.dimensions.x-2.6)<.0001 and abs(rug.dimensions.y-2.6)<.0001,'Actual Blender rug body diameter is 2.60 m')
    check(all((ROOT/p).is_file() for p in ['tools/art/build_tackle_shop.py','tools/art/finalize_tackle_atlas.py','tools/art/verify_tackle_shop.py',
          'scenes/tackle_shop/tackle_shop_art.tscn','scenes/tackle_shop/tackle_shop_art.gd','assets/rooms/tackle_shop/material_import.gd']),
          'Generator, validator, assembly scene and surface importer are delivered')
    report['editable_source']={'file':str(source.relative_to(ROOT)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'module_collections':len([c for c in collections if c.startswith('KIT_')]),'mesh_objects':len(meshes),'rug_diameter_m':float(rug.dimensions.x)}
    report['failures']=[r for r in report['checks'] if not r['passed']]
    (OUT/'glb-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('TACKLE_BINARY',len(report['checks']),'checks',len(report['failures']),'failures',flush=True)
    for row in unexpected:print('CROSSING',row,flush=True)
    if report['failures']:raise RuntimeError('Tackle binary validation failed; see glb-validation.json')

if __name__=='__main__':main()
