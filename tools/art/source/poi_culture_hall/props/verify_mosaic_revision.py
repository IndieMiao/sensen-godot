"""Independent byte-level geometry preservation and radial-colour audit for v1.2."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess
import sys
import numpy as np

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4];OUT=ROOT/'output/culture-mosaic-323'
KIT=ROOT/'assets/rooms/poi_culture_hall/props';BASE='85b0656588f7f2cea516f42e677c47ab466e1295'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
OUT.mkdir(parents=True,exist_ok=True);checks=[]
def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)
def baseline(path):return subprocess.check_output(['git','show',BASE+':'+str(path.relative_to(ROOT))],cwd=ROOT)
def sha(data):return hashlib.sha256(data).hexdigest()
path=KIT/'floor_mosaic.glb';before=baseline(path);after=path.read_bytes()
old_path=OUT/'floor_mosaic_v1.1.glb';old_path.write_bytes(before)
doc,data=load_glb(path);old_doc,old_data=load_glb(old_path)
check(doc==old_doc,'Entire GLB JSON, accessors, materials, node transforms and mesh metadata unchanged')
check(len(after)==len(before)==29420,'GLB byte length unchanged')
p=doc['meshes'][0]['primitives'][0];attrs=p['attributes']
points=np.array(accessor(doc,data,attrs['POSITION']));colors=np.array(accessor(doc,data,attrs['COLOR_0']))
old_colors=np.array(accessor(old_doc,old_data,attrs['COLOR_0']))
idx=np.array(accessor(doc,data,p['indices'])).reshape(-1,3)
check(len(idx)==524 and len(doc['meshes'][0]['primitives'])==1,'524 triangles / one surface retained')
check(np.allclose(points.max(axis=0)-points.min(axis=0),[1.94,.008,1.94],atol=1e-6),'Actual vertex bounds 1.94 x .008 x 1.94m')
attr=doc['accessors'][attrs['COLOR_0']];view=doc['bufferViews'][attr['bufferView']]
binary_start=28+struct.unpack_from('<I',after,12)[0]
start=binary_start+view.get('byteOffset',0)+attr.get('byteOffset',0);stride=view.get('byteStride',8)
allowed=np.zeros(len(after),dtype=bool)
for i in range(attr['count']):allowed[start+i*stride:start+i*stride+6]=True
changed=np.frombuffer(after,dtype=np.uint8)!=np.frombuffer(before,dtype=np.uint8)
check(np.any(changed) and not np.any(changed&~allowed),'Only COLOR_0 RGB bytes changed; geometry/normals/indices/alpha byte-identical')
check(np.array_equal(colors[:,3],old_colors[:,3]),'Vertex alpha unchanged')
expected_hex=['D39A6E','F1DDBC','E2A77A','F1DDBC','E2A77A','D3BB9A']
ranges=[(0,.14),(.14,.30),(.30,.62),(.62,.90),(.90,.97)]
radius=np.linalg.norm(points[:,[0,2]],axis=1);top=points[:,1]>.0075;stats=[]
def linear(hex_value):
    c=np.array(list(bytes.fromhex(hex_value)))/255
    return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
for i,(lo,hi) in enumerate(ranges+[(0,.97)]):
    mask=(top&(radius>=lo-1e-5)&(radius<=hi+1e-5)) if i<5 else ~top
    check(mask.any() and np.max(abs(colors[mask,:3]-linear(expected_hex[i])))<=1/65535,
          f'Uniform authored sRGB #{expected_hex[i]} across radial band {i}')
    stats.append({'band':i,'radius_m':[lo,hi],'srgb':'#'+expected_hex[i],'vertices':int(mask.sum())})
check(np.all(np.max(abs(colors[idx]-colors[idx[:,0]][:,None,:]),axis=(1,2))<1e-6),'Every stone triangle is flat-coloured, without angular checkerboarding or gradients')
preserved={}
for item in sorted(KIT.iterdir()):
    if item.is_file() and item.name not in ['floor_mosaic.glb','prop_manifest.json']:
        prior=baseline(item);preserved[item.name]={'before':sha(prior),'after':sha(item.read_bytes())}
check(all(v['before']==v['after'] for v in preserved.values()),'All seven other GLBs, imports/UIDs and material hook unchanged')
old_manifest=json.loads(baseline(KIT/'prop_manifest.json'));manifest=json.loads((KIT/'prop_manifest.json').read_text())
old_spec=next(s for s in old_manifest['assets'] if s['name']=='floor_mosaic')
spec=next(s for s in manifest['assets'] if s['name']=='floor_mosaic')
for key in ['origin','bounds','dimensions_m','triangles','surfaces','colliders']:
    check(spec[key]==old_spec[key],'Manifest preserves '+key)
check(spec['sha256']==sha(after),'Manifest hash matches delivered GLB')
check(manifest['placed_triangles']==old_manifest['placed_triangles']==6140 and manifest['placed_surfaces']==11,'Whole kit remains 6,140 placed triangles / 11 surfaces')
project=OUT/'project/assets/rooms/poi_culture_hall/props/floor_mosaic.glb'
if project.exists():check(project.read_bytes()==after,'Rendered project uses exact delivered GLB')
report={'base_commit':BASE,'checks':checks,'bands':stats,'changed_rgb_bytes':int(changed.sum()),
    'before_sha256':sha(before),'after_sha256':sha(after),'preserved_files':preserved,'passed':all(c['passed'] for c in checks)}
(OUT/'color-geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(len(checks),'checks; changed RGB bytes:',int(changed.sum()),'passed:',report['passed']);raise SystemExit(0 if report['passed'] else 1)
