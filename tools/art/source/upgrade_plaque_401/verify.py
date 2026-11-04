"""Raw asset/import/source-contract checks for the small 401 prop."""
from pathlib import Path
import hashlib,json,re,subprocess,sys
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];KIT=ROOT/'assets/farm/art';QA=ROOT/'output/plaque-401'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor

def main():
    checks=[]
    def check(ok,label):
        checks.append(dict(check=label,passed=bool(ok)))
        if not ok:print('FAIL',label)
    path=KIT/'upgrade_plaque.glb';doc,blob=load_glb(path)
    check(len(doc['meshes'])==1 and doc['meshes'][0]['name']=='upgrade_plaque_mobile','one named mobile mesh')
    primitives=doc['meshes'][0]['primitives'];check(len(primitives)==1,'one surface')
    p=primitives[0];positions=np.asarray(accessor(doc,blob,p['attributes']['POSITION']));normals=np.asarray(accessor(doc,blob,p['attributes']['NORMAL']))
    colors=np.asarray(accessor(doc,blob,p['attributes']['COLOR_0']));indices=np.asarray(accessor(doc,blob,p['indices'])).reshape(-1,3)
    lo,hi=positions.min(0),positions.max(0)
    check(len(indices)<=600,'triangle limit 600');check(np.allclose(hi-lo,[.5,.7,.112],atol=1e-6),'dimensions .50 x .70 x .112 m')
    check(np.isfinite(positions).all() and np.isfinite(normals).all(),'finite positions and normals')
    triangles=positions[indices];areas=np.linalg.norm(np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]),axis=1)/2
    check(areas.min()>1e-10,'no degenerate triangles')
    check(np.allclose(np.linalg.norm(normals,axis=1),1,atol=1e-4),'unit normals')
    check(not doc.get('images') and not doc.get('textures'),'vertex colours only, no textures')
    check(not doc.get('skins') and not doc.get('animations'),'no skeleton or animation')
    check(colors.shape[1]==3 or np.allclose(colors[:,3],1),'opaque vertex colours (RGB implies alpha one)')
    feet=positions[np.abs(positions[:,1])<1e-6]
    check(np.allclose((feet.min(0)+feet.max(0))/2,[0,0,0],atol=1e-6),'bottom post contact is centred on origin')
    spec=json.loads((HERE/'spec.json').read_text());marker=next(n for n in doc['nodes'] if n['name']=='PlaqueText')
    check(np.allclose(marker['translation'],[0,.43,.078],atol=1e-6),'PlaqueText position')
    check('rotation' not in marker and 'scale' not in marker,'PlaqueText identity axes and scale')
    face_triangles=triangles[np.all(np.abs(triangles[:,:,2]-.076)<1e-6,axis=1)]
    front_normals=np.cross(face_triangles[:,1]-face_triangles[:,0],face_triangles[:,2]-face_triangles[:,0])
    check(len(face_triangles)>0 and np.all(front_normals[:,2]>0),'blank front faces +Z')
    check(abs(marker['translation'][2]-hi[2]-.002)<1e-6,'marker is two millimetres outside front face')
    # The readable rectangle is a single uniform ivory surface; no lettering texture/mesh.
    rgb=np.array([int(spec['palette_srgb']['ivory'][i:i+2],16)/255 for i in (0,2,4)])
    linear=np.where(rgb<.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
    on_face=(positions[:,2]>.07599)&(normals[:,2]>.99)
    check(np.allclose(colors[on_face,:3],linear,atol=1/65535),'uniform warm ivory front; no baked lettering')
    text=(KIT/'upgrade_plaque.glb.import').read_text();uid=re.search(r'^uid="(uid://[^\"]+)"',text,re.M)
    check(uid is not None,'Godot-generated import UID');check('gltf/texture_map_mode=1' in text,'texture_map_mode=1')
    check('upgrade_plaque_import.gd' in text,'Marker3D and matte material importer attached')
    collisions=[]
    for other in (ROOT/'assets').rglob('*.import'):
        if other==Path(str(path)+'.import'):continue
        match=re.search(r'^uid="(uid://[^\"]+)"',other.read_text(),re.M)
        if match and match.group(1)==uid.group(1):collisions.append(str(other.relative_to(ROOT)))
    check(not collisions,'unique UID across existing assets')
    base=json.loads(subprocess.check_output(['git','show','caef42a0:assets/farm/art/manifest.json'],cwd=ROOT))
    manifest=json.loads((KIT/'manifest.json').read_text());current=dict(manifest);current['assets']=dict(manifest['assets']);entry=current['assets'].pop('upgrade_plaque')
    check(base==current and list(base['assets'])==list(current['assets']),'manifest only appends upgrade_plaque; existing entries/order retained')
    check(entry['triangles']==len(indices) and entry['surfaces']==len(primitives),'manifest raw cost matches')
    check(entry['sha256']==hashlib.sha256(path.read_bytes()).hexdigest(),'manifest asset digest matches')
    check((KIT/'sign.glb').read_bytes()==subprocess.check_output(['git','show','caef42a0:assets/farm/art/sign.glb'],cwd=ROOT),'original reference door sign unchanged')
    report=dict(passed=all(c['passed'] for c in checks),checks=checks,triangles=len(indices),surfaces=len(primitives),bounds=[lo.tolist(),hi.tolist()],uid=uid.group(1),minimum_triangle_area=float(areas.min()),asset_sha256=entry['sha256'])
    (QA/'asset-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PLAQUE_ASSET',report['passed'],len(checks),'checks',len(indices),'triangles',uid.group(1))
    if not report['passed']:raise SystemExit(1)

if __name__=='__main__':main()
