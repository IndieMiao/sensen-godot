"""Verify new hardwood geometry, source adaptation, import settings and manifest scope."""
from pathlib import Path
import hashlib,json,re,subprocess,sys
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];KIT=ROOT/'assets/farm/art';QA=ROOT/'output/hardwood-408'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor

def main():
    checks=[]
    def check(ok,label):
        checks.append(dict(check=label,passed=bool(ok)))
        if not ok:print('FAIL',label)
    path=KIT/'hardwood_grove.glb';doc,blob=load_glb(path);spec=json.loads((HERE/'spec.json').read_text())
    check(len(doc['meshes'])==1 and doc['meshes'][0]['name']=='hardwood_grove_mobile','single named mobile mesh')
    primitives=doc['meshes'][0]['primitives'];check(len(primitives)==1,'one surface')
    p=primitives[0];positions=np.asarray(accessor(doc,blob,p['attributes']['POSITION']));normals=np.asarray(accessor(doc,blob,p['attributes']['NORMAL']))
    colours=np.asarray(accessor(doc,blob,p['attributes']['COLOR_0']));indices=np.asarray(accessor(doc,blob,p['indices'])).reshape(-1,3)
    lo,hi=positions.min(0),positions.max(0);size=hi-lo
    check(len(indices)<=1200,'triangle budget <=1200')
    check(size[0]<=1.5 and size[2]<=1.5,'entire canopy and accessories fit 1.5m slot')
    check(abs(size[1]-2.3)<1e-5,'height 2.30m')
    check(abs(lo[1])<1e-6 and np.allclose((lo+hi)[[0,2]]/2,0,atol=1e-6),'bottom-centre origin')
    check(np.isfinite(positions).all() and np.isfinite(normals).all(),'finite geometry')
    triangles=positions[indices];areas=np.linalg.norm(np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]),axis=1)/2
    check(float(areas.min())>1e-10,'no degenerate triangles')
    check(np.allclose(np.linalg.norm(normals,axis=1),1,atol=1e-4),'unit normals')
    check(colours.shape[1]==3 or np.allclose(colours[:,3],1),'opaque vertex colours')
    check(not doc.get('images') and not doc.get('textures'),'no textures')
    check(not doc.get('skins') and not doc.get('animations'),'no skeleton or animation')
    parts=spec['parts'];check(sum(p['triangles'] for p in parts)==len(indices),'named editable part costs sum to runtime')
    check(len([p for p in parts if 'canopy' in p['name']])==3,'three original tree_0 crown volumes retained')
    check(len([p for p in parts if 'billet' in p['name']])==3,'three stacked wood billets')
    check(any('growth rings' in p['name'] for p in parts),'separate ringed stump cap')
    check(spec['reuse_provenance']['source_asset']=='tree_0' and spec['reuse_provenance']['source_triangles']==1624,'actual tree_0 provenance')
    source=ROOT/spec['reuse_provenance']['source'];check(hashlib.sha256(source.read_bytes()).hexdigest()==spec['reuse_provenance']['source_sha256'],'source blend digest')
    check(spec['harvested_variant'] is False,'healthy standing tree; no harvested-state model')
    # Horizontal stump face must point upwards rather than relying on a double-sided material.
    flat=np.all(abs(triangles[:,:,1]-.24)<1e-5,axis=1)
    top=triangles[flat];normal=np.cross(top[:,1]-top[:,0],top[:,2]-top[:,0])
    check(len(top)==156 and np.all(normal[:,1]>0),'all 156 growth-ring triangles face upwards')
    text=Path(str(path)+'.import').read_text();uid=re.search(r'^uid="(uid://[^\"]+)"',text,re.M)
    check(uid is not None,'Godot-generated import UID')
    check('gltf/texture_map_mode=1' in text and 'meshes/light_baking=1' in text,'requested texture mode and light baking')
    collisions=[]
    for other in (ROOT/'assets').rglob('*.import'):
        if other==Path(str(path)+'.import'):continue
        match=re.search(r'^uid="(uid://[^\"]+)"',other.read_text(),re.M)
        if match and match.group(1)==uid.group(1):collisions.append(str(other))
    check(not collisions,'unique import UID')
    old=json.loads(subprocess.check_output(['git','show','caef42a0:assets/farm/art/manifest.json'],cwd=ROOT))
    manifest=json.loads((KIT/'manifest.json').read_text());saved=manifest['assets'].pop('hardwood_grove')
    check(old==manifest and list(old['assets'])==list(manifest['assets']),'only one manifest append, previous entries/order retained')
    for name in ['tree_0','tree_1','tree_2','sign']:
        check((KIT/(name+'.glb')).read_bytes()==subprocess.check_output(['git','show','caef42a0:assets/farm/art/'+name+'.glb'],cwd=ROOT),'original '+name+' unchanged')
    check(saved['sha256']==hashlib.sha256(path.read_bytes()).hexdigest(),'manifest digest matches GLB')
    report=dict(passed=all(c['passed'] for c in checks),checks=checks,triangles=len(indices),surfaces=len(primitives),bounds=[lo.tolist(),hi.tolist()],dimensions_m=size.tolist(),uid=uid.group(1),asset_sha256=saved['sha256'],minimum_triangle_area=float(areas.min()))
    (QA/'asset-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('HARDWOOD_ASSET',report['passed'],len(checks),'checks',len(indices),'triangles')
    if not report['passed']:raise SystemExit(1)
if __name__=='__main__':main()
