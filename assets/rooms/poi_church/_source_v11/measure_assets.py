from pathlib import Path
import sys,json,hashlib,shutil,numpy as np
K=Path(__file__).resolve().parent.parent;R=K.parents[2];sys.path.insert(0,str(R/'tools/art'))
from verify_chef_sign import load_glb,accessor
s=json.loads((K/'asset_stats.json').read_text());rows={a['name']:a for a in s['assets']}
for name in ('aisle_carpet','vault_extension','grass_extension'):
 f=K/(name+'.glb');d,b=load_glb(f);p=d['meshes'][0]['primitives'][0];v=np.array(accessor(d,b,p['attributes']['POSITION']))
 rows[name]={'name':name,'file':f.name,'triangles':len(accessor(d,b,p['indices']))//3,'surfaces':len(d['meshes'][0]['primitives']),'bounds':[v.min(0).tolist(),v.max(0).tolist()],'dimensions_m':np.ptp(v,axis=0).tolist(),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()}
s['assets']=list(rows.values());l=json.loads((K/'layout.json').read_text());placed=[a['name'] for a in l['assets'] if not a['review_only']]+[a['asset'] for a in l['instances']]
s['scene_triangles']=sum(rows[a]['triangles'] for a in placed);s['static_draw_surfaces']=sum(rows[a]['surfaces'] for a in placed);s['placed_modules']=len(placed);s['unique_triangles']=sum(a['triangles'] for a in rows.values())
(K/'asset_stats.json').write_text(json.dumps(s,indent=2)+'\n')
print(s["scene_triangles"],s["static_draw_surfaces"])
