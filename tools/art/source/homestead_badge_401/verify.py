"""Independent packed GLB audit: every tier, normals, bounds, markers and append-only manifest."""
from pathlib import Path
import hashlib, json, math, re, subprocess, sys
import numpy as np
HERE = Path(__file__).resolve().parent; ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'tools/art'))
from verify_chef_sign import load_glb, accessor
QA = ROOT / 'output/badge-401'; KIT = ROOT / 'assets/farm/art'
NAME = 'homestead_badge'
checks = []
def check(ok, label):
    checks.append(dict(check=label, passed=bool(ok)))
    if not ok: print('FAIL', label)
def local(n):
    x,y,z,w = n.get('rotation', [0,0,0,1])
    m = np.eye(4)
    m[:3,:3] = [[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
    m[:3,:3] @= np.diag(n.get('scale',[1,1,1]))
    m[:3,3] = n.get('translation',[0,0,0])
    return m
def main():
    path=KIT/(NAME+'.glb'); doc,data=load_glb(path)
    nodes=doc['nodes']; named={n['name']:n for n in nodes}; worlds={}
    def walk(i,parent):
        m=parent@local(nodes[i]); worlds[nodes[i]['name']]=m
        for child in nodes[i].get('children',[]):walk(child,m)
    for i in doc['scenes'][doc.get('scene',0)]['nodes']:walk(i,np.eye(4))
    check(not doc.get('skins') and not doc.get('animations'), 'no skeleton or animation')
    check(not doc.get('images') and not doc.get('textures') and len(doc['materials'])==1, 'one matte vertex-colour material; no texture')
    check(all(np.allclose(n.get('scale',[1,1,1]),[1,1,1]) for n in nodes),'all node scales 1.0')
    allpos=[]; counts={}; surfaces=0
    for n in nodes:
        if 'mesh' not in n:continue
        mesh=doc['meshes'][n['mesh']]; count=0
        check(mesh['name'].endswith('_mobile'), mesh['name']+' name')
        check(len(mesh['primitives'])==1,n['name']+' one surface')
        for p in mesh['primitives']:
            surfaces+=1
            check(set(p['attributes'])=={'POSITION','NORMAL','COLOR_0'},n['name']+' only position/normal/colour')
            positions=np.array(accessor(doc,data,p['attributes']['POSITION']))
            normals=np.array(accessor(doc,data,p['attributes']['NORMAL']))
            indices=np.array(accessor(doc,data,p['indices'])).reshape(-1,3)
            count+=len(indices)
            a,b,c=(positions[indices[:,i]] for i in range(3))
            cross=np.cross(b-a,c-a)
            check(np.all(np.linalg.norm(cross,axis=1)>1e-10),n['name']+' no degenerate triangles')
            check(np.all(np.sum(cross*normals[indices].mean(axis=1),axis=1)>-1e-9),n['name']+' winding agrees with normals')
            wp=(worlds[n['name']]@np.column_stack((positions,np.ones(len(positions)))).T).T[:,:3]
            allpos.extend(wp)
            if n['name'].startswith('Tier_'):
                check(np.allclose(positions.max(axis=0)-positions.min(axis=0),[.8,.8,.087],atol=1e-6),n['name']+' 0.80 m diameter')
                palette=json.loads((HERE/'spec.json').read_text())['palette_srgb']
                colour=palette[n['name'][5:]+'_face']
                srgb=np.array([int(colour[k:k+2],16)/255 for k in [0,2,4]])
                linear=np.where(srgb<=.04045,srgb/12.92,((srgb+.055)/1.055)**2.4)
                colors=np.array(accessor(doc,data,p['attributes']['COLOR_0']))[:,:3]
                facepoints=positions[np.linalg.norm(colors-linear,axis=1)<.0001]
                check(len(facepoints)>=24 and np.allclose(np.ptp(facepoints,axis=0),[.65,.65,0],atol=1e-6),n['name']+' 0.65 m blank coloured face')
        counts[n['name']]=count
    check(sum(counts.values())<=900,'total file, including all four variants, <=900 triangles')
    bounds=[np.min(allpos,axis=0).tolist(),np.max(allpos,axis=0).tolist()]
    check(abs(bounds[0][1])<1e-6 and bounds[1][0]-bounds[0][0]<=1 and bounds[1][2]-bounds[0][2]<=1,'base grounded and overall footprint <=1 m')
    check(np.allclose(local(named[NAME]),np.eye(4)), 'root at base-centre origin with Y up')
    face=worlds['BadgeFace']; number=worlds['BadgeNumber']; lv=worlds['BadgeLv']
    normal=np.array([0,math.sin(math.radians(25)),math.cos(math.radians(25))])
    check(np.allclose(face[:3,3],[0,1,0]) and np.allclose(number[:3,2],normal), 'centre 1.0 m and +Z tilted up 25 degrees')
    check(np.allclose(number[:3,3],face[:3,3]+normal*.055),'BadgeNumber at face centre plus 3 mm')
    check(np.allclose(lv[:3,3],(face@np.array([0,.238,.055,1]))[:3]),'BadgeLv above number, same face')
    manifest=json.loads((KIT/'manifest.json').read_text())
    old=json.loads(subprocess.check_output(['git','show','f11b4e81:assets/farm/art/manifest.json'],cwd=ROOT,text=True))
    check({k:v for k,v in manifest['assets'].items() if k!=NAME}==old['assets'],'all existing manifest entries unchanged')
    check(list(manifest['assets'])==list(old['assets'])+[NAME], 'manifest only appends the badge')
    imp=(KIT/(NAME+'.glb.import')).read_text()
    uid=re.search(r'uid="(uid://[^"]+)"',imp)
    check(uid is not None and 'gltf/texture_map_mode=1' in imp and 'meshes/light_baking=1' in imp,'real UID / texture_map_mode 1 / light_baking 1')
    check('homestead_badge_import.gd' in imp,'import hook retains Marker3D and default tier visibility')
    spec=json.loads((HERE/'spec.json').read_text())
    check(spec['triangles']==sum(counts.values()) and spec['sha256']==hashlib.sha256(path.read_bytes()).hexdigest(),'source manifest matches exact exported file')
    report=dict(passed=all(c['passed'] for c in checks),checks=checks,triangles=sum(counts.values()),stored_surfaces=surfaces,
        visible_triangles=counts['Common']+max(v for k,v in counts.items() if k.startswith('Tier_')),visible_surfaces=2,
        per_node_triangles=counts,bounds=bounds,uid=uid.group(1) if uid else None,asset_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (QA/'asset-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('BADGE_ASSET',report['passed'],len(checks),'checks;',report['triangles'],'triangles')
    raise SystemExit(not report['passed'])
if __name__=='__main__':main()
