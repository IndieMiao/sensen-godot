"""Compare the two revised groups against v1 buffers and protect every other asset."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import numpy as np

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4];OUT=ROOT/'output/culture-props-323'
KIT=ROOT/'assets/rooms/poi_culture_hall/props';BASE='6d21e183e53b182cfda5c06220b247dfdcf061e7'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
old=json.loads(subprocess.check_output(['git','show',BASE+':assets/rooms/poi_culture_hall/props/prop_manifest.json'],cwd=ROOT))
new=json.loads((KIT/'prop_manifest.json').read_text());oldspec={s['name']:s for s in old['assets']}
checks=[];records=[];preserved={}
def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)
def baseline(relative):return subprocess.check_output(['git','show',BASE+':'+str(relative)],cwd=ROOT)
def read_mesh(path):
    doc,data=load_glb(path);primitive=doc['meshes'][0]['primitives'][0];a=primitive['attributes']
    return np.array(accessor(doc,data,a['POSITION'])),np.array(accessor(doc,data,a['COLOR_0']))
def hash_bytes(data):return hashlib.sha256(data).hexdigest()
for path in sorted(KIT.glob('*')):
    if path.is_file() and path.name not in ['case_exhibits_1.glb','case_exhibits_2.glb','prop_manifest.json']:
        prior=baseline(path.relative_to(ROOT));preserved[path.name]={'v1':hash_bytes(prior),'current':hash_bytes(path.read_bytes())}
check(all(v['v1']==v['current'] for v in preserved.values()),'All six other GLBs, every import UID and material hook are byte-identical to v1')
rgb=np.array(list(bytes.fromhex('E4D7BF')))/255
stand_color=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
for s in new['assets']:
    if not s['name'].startswith('case_exhibits_'):continue
    before=oldspec[s['name']]
    path=OUT/('v1_'+s['file']);path.write_bytes(baseline((KIT/s['file']).relative_to(ROOT)))
    previous,_=read_mesh(path);current,colors=read_mesh(KIT/s['file'])
    stand=np.max(abs(colors[:,:3]-stand_color),axis=1)<.00004
    check(s['origin']==before['origin'] and s['display_assignment']==before['display_assignment'],s['name']+': group origin and placement unchanged')
    check(s['surfaces']==1,s['name']+': one surface retained')
    for component,prior in zip(s['components'],before['components']):
        at=np.array(prior['position']);b=np.array(prior['bounds'])+at
        body=previous[np.all(previous>=b[0]-1e-5,axis=1)&np.all(previous<=b[1]+1e-5,axis=1)]
        expected=(body-at)*1.4+at+[0,.06,0]
        eb=np.array(component['exhibit_bounds'])+at
        actual=current[(~stand)&np.all(current>=eb[0]-1e-5,axis=1)&np.all(current<=eb[1]+1e-5,axis=1)]
        distances=np.linalg.norm(expected[:,None,:]-actual[None,:,:],axis=2)
        error=max(distances.min(axis=0).max(),distances.min(axis=1).max())
        check(error<1e-5,component['name']+': actual old vertices scaled 1.4x about original center and lifted .06m')
        check(component['position']==prior['position'],component['name']+': slot position unchanged')
        radius=component['pedestal_radius_m'];base=current[stand&(abs(current[:,2]-at[2])<=radius+1e-5)]
        check(len(base)>0 and abs(base[:,1].min())<1e-5 and abs(base[:,1].max()-.06)<1e-5,component['name']+': actual pedestal height .06m and floor contact')
        check(abs(actual[:,1].min()-.06)<1e-5,component['name']+': exhibit rests on pedestal top')
        records.append({'component':component['name'],'scale':1.4,'slot':component['position'],
            'pedestal_height_m':.06,'vertex_transform_max_error_m':float(error),
            'exhibit_bounds':eb.tolist(),'pedestal_radius_m':radius})
    check(np.all(current[:,1]+1<=1.485+1e-5),s['name']+': under glass hood interior limit')
check(new['placed_surfaces']==old['placed_surfaces']==11,'Placed surface count remains 11')
report={'base_commit':BASE,'checks':checks,'components':records,'preserved_files':preserved,
    'passed':all(c['passed'] for c in checks)}
(OUT/'exhibits-revision-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(len(checks),'revision checks; passed:',report['passed']);raise SystemExit(0 if report['passed'] else 1)
