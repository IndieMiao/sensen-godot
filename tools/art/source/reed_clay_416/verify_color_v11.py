"""Prove v1.1 changes only selected clay RGB words, never geometry or protected colours."""
from pathlib import Path
import colorsys
import hashlib
import json
import struct
import subprocess
import sys
import numpy as np

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/reed-clay-416';KIT=ROOT/'assets/farm/art'
PATCH=json.loads((SRC/'clay_palette_v11.json').read_text());BASE=PATCH['baseline']
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
def original(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
def linear(h):
    c=np.array(list(bytes.fromhex(h)))/255
    return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
def hsv(h):return colorsys.rgb_to_hsv(*[c/255 for c in bytes.fromhex(h)])
checks=[]
def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)
old_raw=original('assets/farm/art/clay_pit.glb');new_raw=(KIT/'clay_pit.glb').read_bytes()
old_path=OUT/'clay_v1.glb';old_path.write_bytes(old_raw)
old,old_bin=load_glb(old_path);new,new_bin=load_glb(KIT/'clay_pit.glb')
check(old==new,'All GLB JSON, nodes, materials, accessors and bounds identical to v1')
p=old['meshes'][0]['primitives'][0];attrs=p['attributes'];acc=old['accessors'][attrs['COLOR_0']]
before=np.array(accessor(old,old_bin,attrs['COLOR_0']));after=np.array(accessor(new,new_bin,attrs['COLOR_0']))
allowed=set();selected=np.zeros(len(before),dtype=bool);changes={}
view=old['bufferViews'][acc['bufferView']];start=20+struct.unpack_from('<I',old_raw,12)[0]+8+view.get('byteOffset',0)+acc.get('byteOffset',0)
for role,c in PATCH['changes'].items():
    mask=np.max(abs(before[:,:3]-linear(c['before'])),axis=1)<2e-5
    selected|=mask
    check(mask.any() and np.max(abs(after[mask,:3]-linear(c['after'])))<2e-5,'Correct new linear RGB: '+role)
    for index in np.where(mask)[0]:allowed.update(range(start+int(index)*view.get('byteStride',8),start+int(index)*view.get('byteStride',8)+6))
    a=hsv(c['before']);b=hsv(c['after']);drop=1-b[1]/a[1]
    check(.15<=drop<=.20 and b[2]<a[2] and b[0]<a[0],role+': saturation -15–20%, value lower, hue toward red-ochre')
    changes[role]={**c,'before_hsv':list(a),'after_hsv':list(b),'saturation_reduction_percent':drop*100,
                   'value_reduction_percent':(1-b[2]/a[2])*100,'vertices':int(mask.sum())}
diff={i for i,(a,b) in enumerate(zip(old_raw,new_raw)) if a!=b}
check(len(old_raw)==len(new_raw) and diff and diff<=allowed,'Only approved clay RGB bytes differ in the entire GLB')
check(np.array_equal(before[~selected],after[~selected]),'Wood, spade, grass and every unselected vertex colour byte unchanged')
check(np.array_equal(before[:,3],after[:,3]),'All alpha values unchanged')
for name in ['POSITION','NORMAL']:
    check(accessor(old,old_bin,attrs[name])==accessor(new,new_bin,attrs[name]),name+' payload unchanged')
check(accessor(old,old_bin,p['indices'])==accessor(new,new_bin,p['indices']),'Triangle indices unchanged (552 triangles)')
for path in ['assets/farm/art/clay_pit.glb.import','assets/farm/art/reed_bank.glb','assets/farm/art/reed_bank.glb.import',
             'tools/art/source/reed_clay_416/reed_bank.blend']:
    check((ROOT/path).read_bytes()==original(path),'Byte-identical protected file: '+path)
old_manifest=json.loads(original('assets/farm/art/manifest.json'));now=json.loads((KIT/'manifest.json').read_text())
expected=json.loads(json.dumps(old_manifest));entry=expected['assets']['clay_pit'];entry['revision']='v1.1'
for role,c in PATCH['changes'].items():entry['palette_srgb'][role]=c['after']
entry['sha256']=hashlib.sha256(new_raw).hexdigest()
entry['clay_palette_note']='Muted red-ochre; HSV saturation reduced 17.7–18.6%, value reduced 8.7–9.2% from v1. Wood and grass unchanged.'
check(now==expected,'Manifest changes only clay colour, revision and SHA; reed/other entries unchanged')
report={'baseline':BASE,'checks':checks,'changes':changes,'changed_bytes':len(diff),'painted_vertices':int(selected.sum()),
        'protected_colour_vertices':int((~selected).sum()),'clay_sha256':entry['sha256'],'passed':all(c['passed'] for c in checks)}
(OUT/'color-validation-v11.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('CLAY_COLOR_VERIFY',report['passed'],len(checks));raise SystemExit(0 if report['passed'] else 1)
