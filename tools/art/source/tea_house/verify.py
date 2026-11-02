"""Audit actual exported GLBs, external materials, shared atlas and anchor contract."""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[4]
KIT=ROOT/'assets/rooms/tea_house'
OUT=ROOT/'output/tea-216'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor


def main():
    layout=json.loads((KIT/'layout.json').read_text());stats=json.loads((KIT/'asset_stats.json').read_text())
    report={'checks':[],'assets':{},'author':'Huangzhong'}
    def check(ok,label):
        report['checks'].append({'check':label,'passed':bool(ok)})
        print('PASS' if ok else 'FAIL',label)
    for spec in layout['assets']:
        name=spec['name'];path=KIT/spec['file'];doc,blob=load_glb(path)
        check(doc.get('images')==[{'uri':'room_albedo_ao.png'}],name+': one external room atlas')
        check(len(doc.get('materials',[]))==1,name+': one material slot')
        material=doc['materials'][0]
        check(material['pbrMetallicRoughness'].get('baseColorTexture')=={'index':0},name+': actual external albedo binding')
        check(len(doc['meshes'])==1 and doc['meshes'][0]['name']==name+'_mobile',name+': named mobile mesh')
        primitives=doc['meshes'][0]['primitives'];check(len(primitives)==1,name+': one surface')
        vertices=[];triangles=0;degenerate=0;nonfinite=False;uv_invalid=0
        for primitive in primitives:
            check(primitive.get('material')==0,name+': primitive binds material slot')
            points=np.array(accessor(doc,blob,primitive['attributes']['POSITION']));vertices.extend(points)
            indices=np.array(accessor(doc,blob,primitive['indices'])).reshape(-1,3);triangles+=len(indices)
            tri=points[indices];areas=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)/2
            degenerate+=int((areas<1e-12).sum());nonfinite|=not np.isfinite(points).all()
            uv=np.array(accessor(doc,blob,primitive['attributes']['TEXCOORD_0']))
            if 'source' in spec:valid=(uv[:,0]>=.75)&(uv[:,1]>=.75)&(uv<=1.000001).all(1)
            else:valid=(uv>=-.000001).all(1)&(uv[:,0]<=.750001)&(uv[:,1]<=1.000001)
            uv_invalid+=int((~valid).sum())
        check(not nonfinite and degenerate==0,name+': finite vertices and no zero-area triangles')
        check(uv_invalid==0,name+': UVs remain in assigned atlas region')
        points=np.array(vertices)
        measured={'triangles':triangles,'surfaces':len(primitives),'bounds':[points.min(0).tolist(),points.max(0).tolist()],
                  'dimensions_m':np.ptp(points,axis=0).tolist(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        report['assets'][name]=measured
        check(triangles==next(s['triangles'] for s in stats['assets'] if s['name']==name),name+': measured triangle count matches manifest')
        check((ROOT/spec['provenance']).is_file(),name+': provenance exists')
        imported=Path(str(path)+'.import')
        check(imported.is_file() and 'gltf/texture_map_mode=1' in imported.read_text(),name+': texture_map_mode=1')
        if spec['vegetation']:
            check(not spec['cast_shadow'] and material.get('doubleSided') and material.get('alphaMode')=='MASK',name+': leaf scissor and no shadows')
        if 'source' in spec:
            old,old_blob=load_glb(ROOT/'assets/rooms/_shared/plants'/f'{spec["source"]}.glb')
            original=np.array(accessor(old,old_blob,old['meshes'][0]['primitives'][0]['attributes']['POSITION']))
            check(np.array_equal(points,original),name+': original shared plant positions retained exactly')
    placed=[a['name'] for a in layout['assets'] if not a['review_only']]+[a['asset'] for a in layout['instances']]
    measured=report['assets'];tris=sum(measured[n]['triangles'] for n in placed);surfaces=sum(measured[n]['surfaces'] for n in placed)
    plants={a['name'] for a in layout['assets'] if a['vegetation']};plant_tris=sum(measured[n]['triangles'] for n in placed if n in plants)
    check(tris==stats['scene_triangles'] and tris<=200000,'Actual placed triangles <=200000')
    check(surfaces==stats['static_draw_surfaces'] and surfaces<=60,'Actual placed surfaces <=60')
    check(plant_tris==stats['plant_triangles'] and plant_tris<=100000,'Actual placed plant triangles <=100000')
    check(Image.open(KIT/'room_albedo_ao.png').size==(2048,2048),'Exactly one 2048x2048 atlas')
    tree=next(a for a in layout['assets'] if a['name']=='corner_tree')
    tree_low=np.array(measured['corner_tree']['bounds'][0])+tree['position']
    check(tree_low[0]>=-3.10,'Actual tree canopy clears the left wall and its projecting timber')
    anchors={a['name']:a for a in layout['anchors']};names=set(anchors)
    required={'use_counter','stand_counter','npc_keeper','badge_keeper','stand_keeper','use_bench','npc_hana','stand_hana',
              'npc_lena','stand_lena','spawn','exit','badge_exit','sign_name'}
    required|={f'use_tea_table_{i}' for i in range(1,4)}|{f'seat_table{i}_{j}' for i in range(1,4) for j in range(1,4)}|{f'seat_bench_{i}' for i in range(1,4)}
    check(required<=names,'Full immutable gameplay anchor contract including four legacy seats')
    seats=[a for a in anchors.values() if a['name'].startswith('seat_')]
    check(len(seats)==12,'Exactly twelve seats')
    modules={a['name'] for a in layout['assets'] if not a['review_only']}|{a['name'] for a in layout['instances']}
    for seat in seats:
        check(abs(seat['position'][1]-.795)<1e-6 and seat.get('module') in modules,seat['name']+': world seat height and owning module')
    check(not any(name.startswith('stand_seat') or name.startswith('stand_table') for name in names),'No redundant stand anchors for seats')
    sign=anchors['sign_name']
    check(sign['size']==[1.04,.26] and np.allclose(sign['position'],[-2.3925,3.20,-2.812])
          and sign['module']=='name_sign' and sign['yaw_degrees']==180,'Blank sign and outward anchor in rear-left wall bay')
    check(np.linalg.norm(np.array(anchors['spawn']['position'])-np.array(anchors['exit']['position']))>=1.2,'Spawn at least 1.2m from exit')
    report.update({'placed_triangles':tris,'placed_surfaces':surfaces,'plant_triangles':plant_tris,
                   'passed':all(c['passed'] for c in report['checks'])})
    (OUT/'geometry-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    if not report['passed']:sys.exit(1)


if __name__=='__main__':main()
