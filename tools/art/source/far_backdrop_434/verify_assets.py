"""Independent exported GLB, import, silhouette preservation and budget checks."""
from pathlib import Path
import hashlib, json, re, sys
import numpy as np

SRC=Path(__file__).resolve().parent; ROOT=SRC.parents[3]
KIT=ROOT/'assets/landmarks/_shared/far_backdrop'; OUT=ROOT/'output/far-backdrop-434'
sys.path.insert(0,str(ROOT/'tools/art/source/alcatraz_foam_424'))
from geometry import read_glb

manifest=json.loads((KIT/'manifest.json').read_text()); checks=[]; uids=[]
def check(ok,label):
    checks.append({'passed':bool(ok),'check':label})
    assert ok,label

def triangles(path):
    p=read_glb(path)[1][0]
    tris=np.round(p['POSITION'][p['indices']].reshape(-1,3,3),6)
    return sorted(tuple(sorted(tuple(v) for v in tri)) for tri in tris)

for name,spec in manifest['assets'].items():
    path=KIT/spec['file']; gltf,meshes=read_glb(path); p=meshes[0]
    check(len(gltf['meshes'])==len(meshes)==len(gltf['materials'])==1,name+': one mesh / surface / material')
    check(not any(gltf.get(k) for k in ['images','textures','skins','animations']),name+': no texture / rig / animation')
    pos=p['POSITION']; idx=p['indices']; color=p['COLOR_0']
    check(len(idx)//3==spec['triangles'],name+': actual triangles match manifest')
    check(np.max(abs(pos[:,2]))<1e-7,name+': flat XY card')
    check(abs(pos[:,1].min())<1e-6 and abs(pos[:,0].min()+pos[:,0].max())<1e-6,name+': bottom-centre local pivot')
    check(np.isfinite(pos).all() and np.isfinite(color).all(),name+': finite coordinates / weights')
    check(np.min(color)>=0 and np.max(color)<=1 and np.max(abs(color[:,:3].sum(axis=1)-1))<.001,name+': linear RGB weights sum to one')
    check(np.min(color[:,3])==1,name+': no translucent vertex layers')
    t=pos[idx].reshape(-1,3,3); area=np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1)
    check(area.min()>1e-9,name+': no degenerate triangles')
    check(hashlib.sha256(path.read_bytes()).hexdigest()==spec['sha256'],name+': exported hash')
    cfg=(KIT/(name+'.glb.import')).read_text()
    check('nodes/root_script=null' in cfg and 'import_script/path="res://assets/landmarks/_shared/far_backdrop/far_card_import.gd"' in cfg,name+': local importer and null root script')
    uid=re.search(r'^uid="(uid://[^"]+)"',cfg,re.M).group(1);uids.append(uid)
check(len(set(uids))==6,'six independent Godot UIDs')
for name,old in [('far_city_high','alc_far_city'),('far_hills_a','alc_far_hills'),('far_bridge','alc_far_bridge')]:
    check(triangles(KIT/(name+'.glb'))==triangles(ROOT/'assets/landmarks/alcatraz_island'/(old+'.glb')),name+': original triangle positions preserved exactly to 1e-6 m')
counts={k:v['triangles'] for k,v in manifest['assets'].items()}
check(counts['far_city_low']<counts['far_city_medium']<counts['far_city_high'],'three city densities have distinct geometry')
check(manifest['assets']['far_city_low']['source_parts']==17,'low density keeps 17 separated waterfront blocks')
check(triangles(KIT/'far_hills_a.glb')!=triangles(KIT/'far_hills_b.glb'),'two distinct hill silhouettes')
combos={k:sum(counts[n] for n in v) for k,v in manifest['recommended_combinations'].items()}
check(max(combos.values())<=826,'both combinations within original triangle budget')
for rel,digest in json.loads((SRC/'reference/provenance.json').read_text())['source_hashes'].items():
    check(hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()==digest,rel+': original unchanged')
report={'passed':True,'checks':checks,'assets':manifest['assets'],'combination_triangles':combos,
        'uid_count':len(set(uids)),'new_textures':0,'source_weights':'RGB sum=1, alpha=1'}
(OUT/'geometry-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('FAR_GEOMETRY_PASS',len(checks),combos)
