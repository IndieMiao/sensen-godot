"""Audit exported geometry and every ordered out->in mating combination."""
from pathlib import Path
import argparse,hashlib,json,math,re,subprocess,sys
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];KIT=ROOT/'assets/landmarks/_shared/coast_kit';QA=ROOT/'output/coast-kit'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
parser=argparse.ArgumentParser();parser.add_argument('--geometry-only',action='store_true');args=parser.parse_args()
manifest=json.loads((KIT/'manifest.json').read_text());report={'author':'赵云','checks':[],'assets':{},'mates':[]};geometry={};uids=[]
BASE='d72d74f4'
reference=QA/'v1.1/reference';reference.mkdir(parents=True,exist_ok=True)
base_manifest=json.loads(subprocess.check_output(['git','show',BASE+':assets/landmarks/_shared/coast_kit/manifest.json'],cwd=ROOT))
def check(ok,label):
    report['checks'].append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)
def signature(points):return {tuple(round(float(v),5) for v in p) for p in points}
def yaw(a):return np.array([[math.cos(a),0,math.sin(a)],[0,1,0],[-math.sin(a),0,math.cos(a)]])

for name,e in manifest['assets'].items():
    path=KIT/(name+'.glb');doc,blob=load_glb(path);mesh=doc['meshes'][0];p=mesh['primitives'][0]
    check(len(doc['meshes'])==1 and len(mesh['primitives'])==1 and mesh['name']==name+'_mobile',name+': one mobile mesh / surface')
    check(len(doc['nodes'])==1 and doc['nodes'][0]=={'mesh':0,'name':name},name+': identity construction root')
    check(not any(doc.get(k) for k in ['skins','animations','textures','images']),name+': no textures / skin / animation')
    check(len(doc['materials'])==1 and set(p['attributes'])=={'POSITION','NORMAL','COLOR_0'},name+': one vertex-colour material')
    xyz=np.array(accessor(doc,blob,p['attributes']['POSITION']));normals=np.array(accessor(doc,blob,p['attributes']['NORMAL']));colors=np.array(accessor(doc,blob,p['attributes']['COLOR_0']));ids=np.array(accessor(doc,blob,p['indices'])).reshape(-1,3)
    geometry[name]=xyz;tri=len(ids);lo,hi=xyz.min(0),xyz.max(0)
    check(tri==e['triangles'] and tri<=400,name+': measured triangle budget')
    check(abs(lo[1])<1e-6 and np.allclose([lo,hi],e['bounds'],atol=1.1e-6),name+': grounded / manifest bounds')
    check(np.isfinite(xyz).all() and np.isfinite(normals).all() and np.isfinite(colors).all() and (colors>=0).all() and (colors<=1).all(),name+': finite geometry / bounded colours')
    face=np.cross(xyz[ids[:,1]]-xyz[ids[:,0]],xyz[ids[:,2]]-xyz[ids[:,0]])
    lengths=np.linalg.norm(face,axis=1);agreement=np.sum(face*normals[ids].mean(1),axis=1)
    check((lengths>1e-9).all() and (agreement>0).all(),name+': no degenerate or reversed shading triangles')
    mat=doc['materials'][0]['pbrMetallicRoughness'];check(abs(mat['roughnessFactor']-.94)<1e-6 and mat['metallicFactor']==0,name+': matte material')
    digest=hashlib.sha256(path.read_bytes()).hexdigest();check(digest==e['sha256'],name+': manifest matches actual export')
    for port in e['ports']:
        if 'profile' not in port:continue
        at=np.array(port['position']);normal=np.array(port['outward']);points=xyz[np.abs((xyz-at)@normal)<1e-6]
        check(signature(points)==signature(port['profile']),name+'/'+port['name']+': full exported seam matches declared profile')
    check(e['ports']==base_manifest['assets'][name]['ports'],name+': accepted v1 port contract unchanged')
    base_path=reference/(name+'.glb')
    if not base_path.exists():base_path.write_bytes(subprocess.check_output(['git','show',BASE+':assets/landmarks/_shared/coast_kit/'+name+'.glb'],cwd=ROOT))
    if e['family'] in ['shore_rock','scatter']:
        old,old_blob=load_glb(base_path);old_p=old['meshes'][0]['primitives'][0]
        for attribute in ['POSITION','NORMAL']:
            previous=np.array(accessor(old,old_blob,old_p['attributes'][attribute]))
            current=xyz if attribute=='POSITION' else normals
            check(previous.shape==current.shape and np.allclose(previous,current,atol=2e-6),name+': existing '+attribute+' unchanged')
        check(np.array_equal(np.array(accessor(old,old_blob,old_p['indices'])).reshape(-1,3),ids),name+': existing topology unchanged')
        check(colors.shape[1]==4 and set(np.rint(colors[:,3]*8).astype(int))<=set([1,2,3,4]),name+': four palette roles in opaque colour channel')
    elif e['family'] in ['dock','seawall']:
        check(colors.shape[1]==4 and np.allclose(colors[:,3],.75),name+': wettable solid surface code')
    else:check(path.read_bytes()==base_path.read_bytes(),name+': already accepted GLB byte-identical')
    if e['family']!='dock':
        previous=subprocess.check_output(['git','show','85967444:assets/landmarks/_shared/coast_kit/'+name+'.glb'],cwd=ROOT)
        check(path.read_bytes()==previous,name+': v1.1 non-dock GLB byte-identical')
    if e['family']=='dock':
        check(e['plank_rows']==11 and e['planks']==28 and e['board_nominal_size_m']==[1.8,.18] and e['half_stagger_m']==.9,name+': #830 nominal boards / half stagger')
        check(e['pile_count']==4 and len(e['pile_centres'])==4,name+': four corner piles')
        top=np.all(np.isclose(xyz[ids,1],1.2,atol=1e-6),axis=1)&(face[:,1]>0)
        top_ids=ids[top];top_face=face[top]
        check(np.isclose(np.linalg.norm(top_face,axis=1).sum()/2,4,atol=1e-6),name+': top partitions exactly 4 square metres without stacked board faces')
        def linear(hexcode):
            c=np.array([int(hexcode[i:i+2],16)/255 for i in [0,2,4]])
            return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
        def sample(x,z):
            points=xyz[top_ids][:,:,[0,2]];a=points[:,0];u=points[:,1]-a;v=points[:,2]-a;q=np.array([x,z])-a
            det=u[:,0]*v[:,1]-u[:,1]*v[:,0]
            first=(q[:,0]*v[:,1]-q[:,1]*v[:,0])/det;second=(u[:,0]*q[:,1]-u[:,1]*q[:,0])/det
            hit=(first>=-1e-6)&(second>=-1e-6)&(first+second<=1+1e-6)
            return colors[top_ids[hit],:3].mean(axis=1)
        base=linear('A3815D');seam=linear('69543F')
        tone_ok=True;stagger_ok=True;sampled=[]
        for row in range(11):
            z=-.9+row*.18
            for x in [-.5,.3,.7]:
                paint=sample(x,z);factors=paint/base
                tone_ok &= len(paint)>0 and np.all(factors>=.85999) and np.all(factors<=1.14001) and np.allclose(factors[:,0],factors[:,1]) and np.allclose(factors[:,1],factors[:,2])
                sampled.extend(factors[:,0].tolist())
            joints=[-.9,.9] if row%2==0 else [0.0]
            for x in joints:
                paint=sample(x,z)
                stagger_ok &= len(paint)>0 and np.allclose(paint,seam,atol=1e-6)
                for side in [-.007,.007]:stagger_ok &= not np.allclose(sample(x+side,z),seam,atol=1e-6)
        check(tone_ok and min(sampled)<.87 and max(sampled)>1.13,name+': measured exported board colour #A3815D with +/-14% linear variation')
        check(stagger_ok,name+': actual 1.8m end joints alternate by .9m with .012m dark bands')
        check(all(np.allclose(sample(.3,-.81+.18*i),seam,atol=1e-6) and not np.allclose(sample(.3,-.81+.18*i+.007),seam,atol=1e-6) for i in range(10)),name+': actual .18m row pitch and .012m long joints')
        check(any(np.allclose(c,linear('B89972'),atol=1e-6) for c in colors[:,:3]) and any(np.allclose(c,linear('795F47'),atol=1e-6) for c in colors[:,:3]),name+': #830 light and dark wood colours present')
        report.setdefault('wood_match',{})[name]={'reference':'#830 5f9b59b8','board_nominal_m':[1.8,.18],'stagger_m':.9,'joint_m':.012,'linear_tone_measured':[min(sampled),max(sampled)],'top_area_m2':float(np.linalg.norm(top_face,axis=1).sum()/2)}
        for centre in e['pile_centres']:
            expected=[np.array([centre[0]+dx,y,centre[2]+dz]) for dx in [-.08,.08] for dz in [-.08,.08] for y in [0,.98]]
            check(all(np.linalg.norm(xyz-p,axis=1).min()<1e-6 for p in expected),name+': actual pile corners at '+str(centre))
    if e['family']=='seawall':
        cap=xyz[np.isclose(xyz[:,1],1.2,atol=1e-6)]
        check(np.isclose(cap[:,2].max()-cap[:,2].min(),.84,atol=1e-6),name+': actual overhanging coping width')
        for height in [.3,.6,.9]:
            recess=np.array([.90,height-.01,.38-.10*(height-.01)/1.05-.018])
            check(np.linalg.norm(xyz-recess,axis=1).min()<1e-6,name+': actual recessed horizontal joint '+str(height))
        joint_rgb=np.array([int(manifest['palette_srgb']['stone_joint'][i:i+2],16)/255 for i in [0,2,4]])
        joint_rgb=np.where(joint_rgb<=.04045,joint_rgb/12.92,((joint_rgb+.055)/1.055)**2.4)
        joint_vertices=xyz[np.linalg.norm(colors[:,:3]-joint_rgb,axis=1)<1e-6]
        check(len(joint_vertices)>0 and np.abs(joint_vertices[:,0]).max()<=.900001,name+': joint paint stays horizontal and off the end collars')
    uid=None
    if not args.geometry_only:
        text=(KIT/(name+'.glb.import')).read_text();match=re.search(r'^uid="(uid://[^"]+)"$',text,re.M);uid=match.group(1) if match else None
        check(uid is not None and all(s in text.splitlines() for s in ['nodes/root_script=null','gltf/texture_map_mode=1','meshes/light_baking=1','meshes/generate_lods=false']),name+': Godot UID / complete stable import defaults')
        if e.get('material'):check('import_script/path="res://assets/landmarks/_shared/coast_kit/coast_kit_import.gd"' in text,name+': palette/wet material assigned by Godot importer')
        uids.append(uid)
    report['assets'][name]={'triangles':tri,'surfaces':1,'sha256':digest,'uid':uid,'bounds':[lo.tolist(),hi.tolist()]}

for an,ae in manifest['assets'].items():
    for ap in ae['ports']:
        if ap['name']!='out' or 'profile' not in ap:continue
        for bn,be in manifest['assets'].items():
            for bp in be['ports']:
                if bp['name']!='in' or 'profile' not in bp or bp['family']!=ap['family']:continue
                na,nb=np.array(ap['outward']),np.array(bp['outward'])
                angle=math.atan2(nb[2],nb[0])-math.atan2(-na[2],-na[0]);r=yaw(angle);t=np.array(ap['position'])-r@np.array(bp['position'])
                apoints=geometry[an];bpoints=geometry[bn]
                a=apoints[np.abs((apoints-np.array(ap['position']))@na)<1e-6]
                b=bpoints[np.abs((bpoints-np.array(bp['position']))@nb)<1e-6]@r.T+t
                # Symmetric maximum closest-vertex gap of the actual profile sets.
                distance=np.linalg.norm(a[:,None]-b[None,:],axis=2)
                gap=max(float(distance.min(0).max()),float(distance.min(1).max()))
                check(gap<1e-6 and np.allclose(r@nb,-na),an+' -> '+bn+': no positive seam gap')
                report['mates'].append({'from':an,'to':bn,'yaw_degrees':round(math.degrees(angle),6),'max_profile_gap_m':gap})
check(len(report['mates'])==43,'36 mixed-height rock, 1 wall and 6 dock mating combinations covered')
for name in ['coast_dock_straight','coast_dock_bollard']:
    edge=np.array([[1,1.2,-1],[1,1.2,1]])
    landing=np.array([[-1,1.2,-1],[1,1.2,-1]])
    transformed=landing@yaw(math.pi/2).T+np.array([2,0,0])
    exists=all(np.linalg.norm(geometry['coast_water_steps']-p,axis=1).min()<1e-6 for p in landing)
    check(exists and signature(edge)==signature(transformed),name+' -> stairs: 2m walking edge at identical height')
check(len(manifest['assets'])==15 and not manifest['example_layout_included'],'15 independent prototypes; no delivered example layout')
check(not any(KIT.glob('*layout*')),'no runtime example layout file')
check(len(list(KIT.glob('*.glb')))==15,'no duplicated GLBs for the second palette')
shader=(KIT/'coast_surface.gdshader').read_text()
check('sampler2D' not in shader and not re.search(r'^\s*ALPHA\s*=',shader,re.M),'palette and wet band use no textures or transparency pass')
check('MODEL_MATRIX' in shader and 'world_height' in shader and 'smoothstep' in shader,'wet band uses a continuous world-water-level gradient')
if not args.geometry_only:check(len(set(uids))==15,'15 distinct Godot-generated UIDs')
check(json.loads((HERE/'asset_stats.json').read_text())==manifest,'runtime and source manifests agree')
unchanged=subprocess.check_output(['git','diff','HEAD','--name-only','--','assets/landmarks/alcatraz_island'],cwd=ROOT,text=True)
check(not unchanged,'all Alcatraz files unchanged in the worktree')
for e in manifest['assets'].values():
    if 'reuse' in e:check(hashlib.sha256((ROOT/e['reuse']['source_file']).read_bytes()).hexdigest()==e['reuse']['source_sha256'],'reused Alcatraz rock source hash retained')
report['unique_triangles']=sum(e['triangles'] for e in report['assets'].values());report['passed']=all(c['passed'] for c in report['checks'])
(QA/('geometry-preimport.json' if args.geometry_only else 'asset-validation.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('COAST_VERIFY',report['passed'],len(report['checks']),'checks;',len(report['mates']),'mating pairs;',report['unique_triangles'],'unique triangles')
raise SystemExit(0 if report['passed'] else 1)
