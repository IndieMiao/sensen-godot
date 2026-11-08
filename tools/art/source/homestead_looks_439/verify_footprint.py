"""Audit named part AABBs against actual Vulkan-read farm instances.
Positive separation is conservative proof of no intersection; overlap is only a candidate.
"""
from pathlib import Path
import json,math
ROOT=Path(__file__).resolve().parents[4];QA=ROOT/'output/homestead-439';SRC=Path(__file__).resolve().parent
s=json.loads((SRC/'asset_stats.json').read_text());n=json.loads((QA/'native-layout.json').read_text())
assert n['renderer']=='mobile' and all(n['fences'][look] for look in ['a','b'])
def intersects(a,b):return all(min(a[1][i],b[1][i])-max(a[0][i],b[0][i])>1e-5 for i in range(3))
def distance(a,b):return math.sqrt(sum(max(a[0][i]-b[1][i],b[0][i]-a[1][i],0)**2 for i in range(3)))
def shifted(bounds,dx):return [[p[0]+dx,p[1],p[2]] for p in bounds]
bench=next(o for o in n['existing_props'] if o['name']=='Bench');mail=next(o for o in n['existing_props'] if o['name']=='Mailbox')
bush=next(o for o in n['scenery'] if math.dist(o['origin'],[-1.75,0,-.9])<.001)
r={'author':'赵云','runtime_reference':'8493a5c4','house_anchor_cell':[9,16],'house_world':n['house'],'cell_m':.65,'assets':{},'checks':[],
'method':'Named component AABBs versus actual Vulkan transform readback. Positive gap guarantees separation; overlapping boxes are candidates, not exact triangle intersections.',
'required_scenery_moves':[
 {'object':'Bench','from_anchor':[5,16],'to_anchor':[3,16],'delta':[-1.3,0,0],'from_relative_house':bench['origin'],'to_relative_house':[-3.575,0,0],'note':'Lv8: program must update anchor, own footprint and interaction point together; preview only in this PR'},
 {'object':'left house Bush','from_relative_house':bush['origin'],'to_relative_house':[-3.25,0,-.9],'delta':[-1.5,0,0],'note':'Lv8: keep original basis; alter after deterministic scenery generation'}],
'replaced_visual_paving':{'when':'Lv5 porch visible','asset':'stepping_stone','source_indices':[3,4],'relative_z':[1.75,1.49],'note':'Two original visual stepping stones hidden in review; new <=.036m flush landing replaces them. Third stone at z2.01 is the retained transition. No walk mask or rock_points edit.'},
'small_vegetation_note':'Below are bbox contact candidates. Grass inside the new wing should be filtered during program integration, after random generation so seed910 and collision rocks remain identical. Review only moved Bench/Bush and hid the two stepping stones; other flowers/grass remain unchanged.',
'protected_row14':'Cells (4,14),(5,14),(7,14),(8,14),(9,14),(10,14),(11,14); geometry clipping recorded separately in asset-validation.json'}
for name,parts in s['components'].items():
 row={'sha256':s['assets'][name]['sha256'],'fence_clearances_m':{},'mailbox_clearance_m':min(distance(p['bounds'],mail['bounds']) for p in parts),
 'bench_before_overlap_components':[p['name'] for p in parts if intersects(p['bounds'],bench['bounds'])],
 'bench_after_clearance_m':min(distance(p['bounds'],shifted(bench['bounds'],-1.3)) for p in parts),
 'bush_before_overlap_components':[p['name'] for p in parts if intersects(p['bounds'],bush['bounds'])],
 'bush_after_clearance_m':min(distance(p['bounds'],shifted(bush['bounds'],-1.5)) for p in parts),'scenery_bbox_candidates':[]}
 for look,fs in n['fences'].items():
  gap=min(distance(p['bounds'],f['bounds']) for p in parts for f in fs)
  row['fence_clearances_m'][look]=gap;r['checks'].append({'check':name+': separated from '+look+' fence','passed':gap>1e-5})
 for label in ['mailbox_clearance_m','bench_after_clearance_m','bush_after_clearance_m']:
  r['checks'].append({'check':name+': '+label,'passed':row[label]>1e-5})
 for o in n['scenery']:
  hits=[p['name'] for p in parts if intersects(p['bounds'],o['bounds'])]
  if hits:row['scenery_bbox_candidates'].append({**o,'components':hits})
 r['assets'][name]=row
r['passed']=all(c['passed'] for c in r['checks']);(QA/'footprint-validation.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
for name,row in r['assets'].items():print(name,'fences',row['fence_clearances_m'],'mailbox',round(row['mailbox_clearance_m'],4))
print('HOMESTEAD_FOOTPRINT',r['passed'],len(r['checks']),'checks');raise SystemExit(0 if r['passed'] else 1)
