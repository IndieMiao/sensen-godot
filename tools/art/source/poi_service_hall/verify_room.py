"""Measure delivered buffers, original-scale reuse, imports and baked floor mapping."""
import hashlib
import json
import re
import subprocess
import numpy as np
from PIL import Image
from build_room import ROOT,SRC,OUT,KIT,DEPS,HALL,BASE,load,accessor,glb_measure,write_json

checks=[]
def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)

def arrays(path):
    doc,blob=load(path);primitive=doc['meshes'][0]['primitives'][0]
    return {key:np.array(accessor(doc,blob,index)) for key,index in primitive['attributes'].items()}


layout=json.loads((KIT/'layout.json').read_text());skin=json.loads((KIT/'room_skin.json').read_text())
stats=json.loads((KIT/'asset_stats.json').read_text());uids=[];assets={}
for name,spec in layout['assets'].items():
    path=KIT/spec['file'];doc,blob=load(path);measured=glb_measure(path);assets[name]=measured
    check(measured['mesh_names']==[name+'_mobile'],name+': named mobile mesh')
    check(measured['surfaces']==1 and measured['triangles']<=8000,name+': one surface and <=8k triangles')
    check(doc.get('images')==[{'uri':'hall_albedo_ao_n2.png'}],name+': one external skin, no embedded images')
    check(all(p.get('material')==0 for m in doc['meshes'] for p in m['primitives']),name+': imported material slot')
    check(np.allclose(measured['bounds'],spec['bounds'],atol=1e-6),name+': actual buffer bounds match manifest')
    check((SRC/'modules'/name/'reuse_provenance.json').exists(),name+': per-module provenance')
    text=(KIT/(spec['file']+'.import')).read_text();match=re.search(r'uid="(uid://[^\"]+)"',text)
    check(match is not None and 'gltf/texture_map_mode=1' in text,name+': generated UID and texture_map_mode=1')
    if match:uids.append(match.group(1))
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            xyz=np.array(accessor(doc,blob,p['attributes']['POSITION']));normals=np.array(accessor(doc,blob,p['attributes']['NORMAL']))
            indices=np.array(accessor(doc,blob,p['indices'])).reshape(-1,3);triangles=xyz[indices]
            area=np.linalg.norm(np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]),axis=1)
            check(np.all(area>1e-12) and np.isfinite(xyz).all(),name+': valid nondegenerate geometry')
            check(np.allclose(np.linalg.norm(normals,axis=1),1,atol=.001),name+': normalized normals')
check(len(uids)==len(set(uids))==16,'Sixteen unique import UIDs')
for name in ['sofa_three_seat','armchair','wall_sconce']:
    source=arrays(DEPS/HALL/(name+'.glb'));target=arrays(KIT/(name+'.glb'))
    check(np.array_equal(source['POSITION'],target['POSITION']) and np.array_equal(source['NORMAL'],target['NORMAL']),
          name+': original 324 geometry and normals byte-exact')
for name in ['peace_lily','wall_clock']:
    folder='assets/rooms/_shared/plants' if name=='peace_lily' else 'assets/rooms/post_office'
    check(np.array_equal(arrays(ROOT/folder/(name+'.glb'))['POSITION'],arrays(KIT/(name+'.glb'))['POSITION']),
          name+': original source geometry unchanged')
props=json.loads((KIT/'prop_manifest.json').read_text())
for spec in props['assets']:
    name=spec['name'];original=OUT/'baseline-props'/spec['file'];original.parent.mkdir(parents=True,exist_ok=True)
    original.write_bytes(subprocess.check_output(['git','show',BASE+':'+str((KIT/spec['file']).relative_to(ROOT))],cwd=ROOT))
    check(np.array_equal(arrays(original)['POSITION'],arrays(KIT/spec['file'])['POSITION']),name+': approved prop geometry unchanged')
check(np.allclose(assets['small_round_table']['dimensions_m'],[.60,.75,.60],atol=.0001),'Small table .60 diameter / .75 height from actual vertices')
seats=[a for a in layout['anchors'] if a['name'].startswith('seat_')]
check({s['name'] for s in seats}=={f'seat_sofa_{i}' for i in range(1,7)}|{f'seat_armchair_{i}' for i in range(1,3)},'Exact eight-seat contract')
check(all(abs(s['position'][1]-.795)<1e-6 for s in seats),'Seat Y .795, .715 above floor')
placed_triangles=sum(assets[p['asset']]['triangles'] for p in layout['placements'])
check(placed_triangles==stats['room_triangles'] and len(layout['placements'])==26,'Room budget includes every repeated placement')
check(stats['scene_triangles']==53892 and stats['scene_surfaces']==34,'Total including unchanged shell below 150k / 50 budget')
check(layout['navigation']['main_min_m']>=.7 and len(layout['navigation']['standing_positions_xz'])==16,'Measured main clearance and sixteen reachable positions')
atlas=np.asarray(Image.open(KIT/'hall_albedo_ao_n2.png').convert('RGBA'))
check(atlas.shape==(2048,2048,4),'One 2048 RGBA atlas')
plant=np.asarray(Image.open(ROOT/'assets/rooms/_shared/plants/room_albedo_ao.png').convert('RGBA'))
for row in skin['plant_tiles']:
    x,y=row['source'];a,b=row['target_px']
    check(np.array_equal(plant[y*128:(y+1)*128,x*128:(x+1)*128],atlas[b:b+128,a:a+128]),'Botanical colour/alpha tile preserved: '+str(row['source']))
doc,_=load(KIT/'peace_lily.glb')
check(doc['materials'][0]['alphaMode']=='MASK' and doc['materials'][0]['alphaCutoff']==.45 and doc['materials'][0]['doubleSided'],
      'Plant retains alpha-scissor .45 and two-sided leaves')
mapping=np.array(skin['floor']['world_uv_affine']);matrix=np.array([mapping[0],mapping[1]])
for x,z,want in [(0,2.3,[97,128,163]),(1.3,.18,[97,128,163]),(0,-2.0,[97,128,163]),(-2.7,.18,[97,128,163]),(1.1,1.8,[223,209,180])]:
    uv=(np.array([x,z])-mapping[2])@np.linalg.inv(matrix);pixel=atlas[int(uv[1]*2048),int(uv[0]*2048),:3]
    check(np.max(abs(pixel.astype(int)-want))<8,'Baked floor colour at world '+str((x,z)))
dependencies=json.loads((SRC/'room_dependencies.json').read_text())
for path,digest in dependencies['unchanged_dependency_sha256'].items():
    check(hashlib.sha256((DEPS/path).read_bytes()).hexdigest()==digest,'Pinned shared dependency preserved: '+path)
result={'passed':all(c['passed'] for c in checks),'checks':checks,'assets':assets,'statistics':stats,
        'scope':'Buffer measurements and original-asset preservation; native capsule and visibility checks are separate.'}
write_json(OUT/'room-geometry-validation.json',result)
print('N2_ROOM_GEOMETRY',len(checks),'checks',sum(not c['passed'] for c in checks),'failures')
assert result['passed']
