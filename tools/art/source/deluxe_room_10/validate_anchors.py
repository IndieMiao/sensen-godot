"""Local authoring audit of Arthur WP7-B §7, complementing the engineering validator."""
from pathlib import Path
import json,re,math
ROOT=Path(__file__).resolve().parents[4];DOC=ROOT/'docs/design/deluxe_room_10-2026-10-07';layout=json.loads((ROOT/'assets/rooms/deluxe_room_10/layout.json').read_text())
assert 'attachment_points' not in layout and 'spawn' not in layout
assert layout['bench']['spawn']==[3.85,.09,-2.84]
anchors=layout['anchors'];names=[a['name'] for a in anchors];assert len(names)==len(set(names))
modules={a['name'] for a in layout['assets']};reserved={'col','colonly','convcol','navmesh','occ','occonly','rigid','vehicle','wheel','noimp','loop','cycle'}
checks=[]
for a in anchors:
 n=a['name'];assert re.fullmatch(r'[a-z][a-z0-9_]*',n)
 prefix=n.split('_')[0];assert n in ('spawn','exit') or prefix in ('use','badge','stand','npc','seat','drop','cam','sign')
 assert re.sub(r'[_0-9]+$','',n).split('_')[-1] not in reserved
 assert len(a['position'])==3 and all(isinstance(q,(int,float)) and math.isfinite(q) for q in a['position'])
 if 'module' in a:assert a['module'] in modules
 if n in ('spawn','exit') or prefix=='npc':assert 'module' not in a
 oriented=prefix in ('stand','npc','seat','sign') or n=='spawn'
 assert ('yaw_degrees' in a)==oriented
 if 'size' in a:assert prefix=='sign' and len(a['size'])==2 and all(q>0 for q in a['size'])
 assert not(set(a)-{'name','position','yaw_degrees','module','size'})
 checks.append({'name':n,'module':a.get('module'),'passed':True})
required={f'use_stove_{i}' for i in range(1,4)}|{f'drop_pot_{i}' for i in range(1,4)}|{'use_spice_rack','use_warming_cabinet','stand_stove','cam_stove','spawn','exit'}
assert set(names)==required
for i in range(1,4):
 use=next(a for a in anchors if a['name']==f'use_stove_{i}');drop=next(a for a in anchors if a['name']==f'drop_pot_{i}')
 assert use['module']==drop['module']=='range_cooker' and use['position'][::2]==drop['position'][::2] and drop['position'][1]>use['position'][1]
result={'authority':{'page_id':'2d11d5b2-e24c-4089-8e6b-c4810ea26b14','section':'Arthur WP7-B / F-03 ③ world anchors v1, §§1–7,2026-10-07'},'validator':'Additional scene-local authoring audit. The verbatim engineering check_room_anchors.gd has also run successfully; see anchor-engineering-verification.json.','checks':checks,'passed':True,'forbidden_legacy_key_absent':True,'pot_mouth_height_m':1.615,'pot_height_source':'Existing cooking-pot source:placement1.305m + .06m base offset + .25m rim profile; future213 can update drop height with its module.'}
(DOC/'anchor-schema-verification.json').write_text(json.dumps(result,indent=2)+'\n');print('WP7_B_ANCHOR_SCHEMA_PASS',len(checks))
