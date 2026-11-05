"""Measure actual exported geometry and the placed, single-atlas scene."""
from pathlib import Path
import json,sys,hashlib,re
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[4];KIT=ROOT/'assets/rooms/poi_church';OUT=ROOT/'output/church-423'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
def main():
 layout=json.loads((KIT/'layout.json').read_text());stats=json.loads((KIT/'asset_stats.json').read_text());rows=[];checks=[]
 def check(value,label):checks.append({'check':label,'passed':bool(value)})
 for spec in layout['assets']:
  path=KIT/spec['file'];d,b=load_glb(path);pts=[];tris=0;degenerate=0
  check(d.get('images')==[{'uri':'room_albedo_ao.png'}],spec['name']+' one external atlas')
  check(len(d['meshes'])==1 and d['meshes'][0]['name']==spec['name']+'_mobile',spec['name']+' mobile mesh name')
  check(len(d['meshes'][0]['primitives'])==1 and len(d['materials'])==1,spec['name']+' one surface/material')
  for prim in d['meshes'][0]['primitives']:
   p=np.array(accessor(d,b,prim['attributes']['POSITION']));idx=np.array(accessor(d,b,prim['indices'])).reshape(-1,3);uv=np.array(accessor(d,b,prim['attributes']['TEXCOORD_0']))
   pts.extend(p);tris+=len(idx);t=p[idx];degenerate+=int((np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1)<1e-10).sum())
   check(np.isfinite(p).all() and np.isfinite(uv).all(),spec['name']+' finite vertices/UV')
   check((uv>=-.0001).all() and (uv<=1.0001).all(),spec['name']+' UV in atlas')
  pts=np.array(pts);check(degenerate==0,spec['name']+' nondegenerate triangles')
  cfg=Path(str(path)+'.import').read_text();uid=re.search(r'uid="(uid://[a-y0-8]+)"',cfg)
  check(uid is not None and 'gltf/texture_map_mode=1' in cfg,spec['name']+' Godot UID / texture_map_mode=1')
  row={'name':spec['name'],'triangles':tris,'surfaces':1,'bounds':[pts.min(0).tolist(),pts.max(0).tolist()],'sha256':hashlib.sha256(path.read_bytes()).hexdigest()};rows.append(row)
 by={a['name']:a for a in rows};placed=[a['name'] for a in layout['assets'] if not a['review_only']]+[a['asset'] for a in layout['instances']];plant={a['name'] for a in layout['assets'] if a['vegetation']}
 actual={'triangles':sum(by[n]['triangles'] for n in placed),'surfaces':len(placed),'plant_triangles':sum(by[n]['triangles'] for n in placed if n in plant)}
 check(actual['triangles']==stats['scene_triangles'] and actual['triangles']<=200000,'Placed triangles match / <=200k')
 check(actual['surfaces']==stats['static_draw_surfaces'] and actual['surfaces']<=60,'Placed surfaces match / <=60')
 check(actual['plant_triangles']==stats['plant_triangles'] and actual['plant_triangles']<=100000,'Plants match / <=100k')
 check(Image.open(KIT/'room_albedo_ao.png').size==(2048,2048),'2048 square shared atlas')
 anchors={a['name']:a for a in layout['anchors']};check({'spawn','exit','badge_exit','cam_default'}<=set(anchors),'Required anchors')
 seats=[a for a in layout['anchors'] if a['name'].startswith('seat_')];check(4<=len(seats)<=8,'Seat count 4–8')
 for a in seats:check(abs(a['position'][1]-.795)<1e-6 and a['module'] in {p['name'] for p in layout['instances']},a['name']+' measured seat top / module')
 check(layout['camera']['size']==6.72 and anchors['cam_default']['width_m']==6.72,'Fixed camera same 6.72m width as tea/farm')
 check(layout['light_patch_alpha']<=.35,'Ground light patch alpha limit')
 report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','checks':checks,'assets':rows,'placed':actual,'passed':all(c['passed'] for c in checks)}
 (OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print('Geometry checks',len(checks),'passed',report['passed'],actual)
 for c in checks:
  if not c['passed']:print('FAIL',c['check'])
 if not report['passed']:sys.exit(1)
if __name__=='__main__':main()
