"""Audit the delivered skin, rest bounds, animation timing and constant root tracks."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys
import numpy as np

ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
parser=argparse.ArgumentParser();parser.add_argument('id');args=parser.parse_args()
DIRECTORY=ROOT/'output/monsters-355/runtime/assets/monsters'/args.id
OUT=ROOT/'output/monsters-355'/args.id
path=DIRECTORY/(args.id+'.glb');spec=json.loads((DIRECTORY/(args.id+'.json')).read_text())
doc,blob=load_glb(path);checks=[]

def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)

read=lambda index:np.array(accessor(doc,blob,index))
check(len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1,'One mesh and surface')
primitive=doc['meshes'][0]['primitives'][0];attrs=primitive['attributes']
points=read(attrs['POSITION']);normals=read(attrs['NORMAL']);indices=read(primitive['indices']).reshape(-1,3)
check(len(indices)==spec['triangles'] and len(indices)<=1500,'Actual triangle budget')
check(doc['meshes'][0]['name']==args.id+'_mobile','Named mobile mesh')
check(len(doc.get('materials',[]))==1 and not doc.get('textures') and not doc.get('images'),'One material and no textures')
check(np.allclose(np.linalg.norm(normals,axis=1),1,atol=.001),'All normals normalized')
area=np.linalg.norm(np.cross(points[indices[:,1]]-points[indices[:,0]],points[indices[:,2]]-points[indices[:,0]]),axis=1)
check((area>1e-10).all(),'No degenerate triangles')
check(np.allclose([points.min(0),points.max(0)],spec['bounds'],atol=.00001),'JSON bounds from exported vertices')
check(abs(points[:,1].max()-spec['height'])<.00001,'JSON height includes rest hover offset')
weights=read(attrs['WEIGHTS_0']);joints=read(attrs['JOINTS_0'])
check(np.allclose(weights.max(1),1) and (np.count_nonzero(weights,axis=1)==1).all(),'Exactly one 100 percent rigid influence per vertex')
check(len(doc['skins'])==1 and len(doc['skins'][0]['joints'])==spec['bones']<=16,'One skin and <=16 joints')
check((joints<spec['bones']).all(),'All joints reference the skin')
mask=read(attrs['TEXCOORD_1'])[:,0];colors=read(attrs['COLOR_0'])
check(set(np.round(mask,6))=={0,1},'UV2.x contains both binary tint regions')
check(len(colors)==len(points) and len(np.unique(colors,axis=0))>=5,'Actual vertex paint has body and face colours')
check((mask[colors[:,:3].max(1)<.08]==0).all(),'Dark eyes and mouth excluded from tint')
cheek=np.array([int('E8B0C6'[i:i+2],16)/255 for i in [0,2,4]])
cheek=((cheek+.055)/1.055)**2.4
pink=np.max(abs(colors[:,:3]-cheek),axis=1)<.006
check(pink.any() and (mask[pink]==0).all(),'Pink face patches excluded from tint')
names=[node.get('name','') for node in doc['nodes']];check(names.count('root')==1,'Exactly one root bone')
root=names.index('root');check(np.allclose(doc['nodes'][root].get('translation',[0,0,0]),[0,0,0]),'Root origin on ground')
check(set(a['name'] for a in doc['animations'])==set(spec['anims']),'Exact final animation names')
check('hit_point' in spec and 'hurt_point' not in spec,'Client hit_point key replaces hurt_point')
check(spec['durations']=={name:clip['length'] for name,clip in spec['anims'].items()},'Client durations match all animation metadata')
check(spec['hit_at']==spec['anims']['attack']['hit_at'],'Client top-level hit_at matches attack')
if 'spore' in spec['anims']:check(spec['spore_at']==spec['anims']['spore']['emit_at'],'Client spore_at matches emission time')
for animation in doc['animations']:
    name=animation['name'];expected=spec['anims'][name];duration=0.;moving=0
    for channel in animation['channels']:
        sampler=animation['samplers'][channel['sampler']];times=read(sampler['input']).ravel();values=read(sampler['output'])
        duration=max(duration,float(times.max()));moving+=int(not np.allclose(values,values[0],atol=1e-5))
        check(np.isfinite(values).all() and (np.diff(times)>0).all(),name+': valid '+channel['target']['path']+' track')
        if channel['target']['node']==root:
            check(np.allclose(values,values[0],atol=1e-6),name+': constant root '+channel['target']['path'])
        if expected.get('loop'):
            endpoint=np.allclose(values[0],values[-1],atol=1e-5)
            if channel['target']['path']=='rotation':endpoint|=np.allclose(values[0],-values[-1],atol=1e-5)
            check(endpoint,name+': loop endpoints coincide for '+channel['target']['path'])
    check(abs(duration-expected['length'])<.00001,name+': JSON timing matches glTF')
    check(abs(duration-spec['durations'][name])<.00001,name+': client duration matches glTF')
    check(moving>0,name+': has moving bone tracks')
    for event in ['hit_at','emit_at']:
        if event in expected:check(0<expected[event]<duration,name+': valid '+event)
check(.4<=spec['anims']['windup']['length']<=.7,'Windup leaves .4-.7 seconds warning')
text=(DIRECTORY/(args.id+'.glb.import')).read_text()
check(bool(re.search(r'uid="uid://[^\"]+"',text)),'Godot generated import UID retained')
check('animation/import=true' in text and 'gltf/texture_map_mode=1' in text,'Animations and external-map import settings')
check(not spec['root_motion'] and not spec['cast_shadow'],'Consumer contract: no root motion, fake shadow only')
result={'id':args.id,'stage':'blockout','passed':all(c['passed'] for c in checks),'checks':checks,
    'bounds':spec['bounds'],'triangles':len(indices),'bones':spec['bones'],'anims':spec['anims'],
    'glb_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
(OUT/'geometry-validation.json').write_text(json.dumps(result,indent=2)+'\n')
print('MONSTER_GEOMETRY',args.id,len(checks),'checks',sum(not c['passed'] for c in checks),'failures')
assert result['passed']
