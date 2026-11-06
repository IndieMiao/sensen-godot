"""Independent GLB, existing UID, layout transform and repeated-join audit."""
from pathlib import Path
import hashlib,json,math,re,subprocess,sys
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];OUT=ROOT/'output/alcatraz-props-424';KIT=ROOT/'assets/landmarks/alcatraz_island'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
REF='34df9c0b6af42a85567dfb5318c6717f929a4ab8'
def transform(p):
 if 'basis_columns' in p:b=np.array(p['basis_columns']).T
 else:
  a=p['yaw'];b=np.array([[math.cos(a),0,math.sin(a)],[0,1,0],[-math.sin(a),0,math.cos(a)]])@np.diag(p['scale'])
 return b,np.array(p['position'])
def main():
 spec=json.loads((HERE/'asset_stats.json').read_text());layout=json.loads((HERE/'reference/layout-34df9c0b.json').read_text());checks=[];assets={};uids=[]
 def check(ok,text):
  checks.append(dict(check=text,passed=bool(ok)))
  if not ok:print('FAIL',text)
 for name,entry in spec['assets'].items():
  path=KIT/(name+'.glb');doc,data=load_glb(path);mesh=doc['meshes'][0];p=mesh['primitives'][0]
  check(len(doc['meshes'])==1 and len(mesh['primitives'])==1,name+': one mesh/surface')
  check(mesh['name']==name+'_mobile',name+': mobile name')
  check(not doc.get('skins') and not doc.get('animations') and not doc.get('images') and len(doc['materials'])==1,name+': static vertex colour, no textures/skeleton')
  check(set(p['attributes'])=={'POSITION','NORMAL','COLOR_0'},name+': only position/normal/colour')
  xyz=np.array(accessor(doc,data,p['attributes']['POSITION']));normals=np.array(accessor(doc,data,p['attributes']['NORMAL']));indices=np.array(accessor(doc,data,p['indices'])).reshape(-1,3)
  lo=xyz.min(axis=0);hi=xyz.max(axis=0);a,b,c=(xyz[indices[:,i]] for i in range(3));cross=np.cross(b-a,c-a)
  check(len(indices)==entry['triangles'] and len(indices)<=entry['triangle_limit'],name+': actual triangle count/budget')
  check(np.all(np.linalg.norm(cross,axis=1)>1e-10),name+': no zero-area triangles')
  check(np.all(np.sum(cross*normals[indices].mean(axis=1),axis=1)>-1e-9),name+': winding matches normals')
  check(np.allclose([lo,hi],entry['bounds'],atol=1e-6) and abs(lo[1])<1e-6,name+': authored bounds and grounded origin')
  check(all(np.allclose(n.get('scale',[1,1,1]),[1,1,1]) and np.allclose(n.get('translation',[0,0,0]),[0,0,0]) for n in doc['nodes']),name+': transforms applied, no baked scene position')
  mat=doc['materials'][0]['pbrMetallicRoughness'];check(abs(mat['roughnessFactor']-.9)<1e-6 and mat['metallicFactor']==0,name+': matte farm material')
  imp=(KIT/(name+'.glb.import')).read_text();uid=re.search(r'uid="([^"]+)"',imp).group(1)
  old=subprocess.check_output(['git','show',REF+':assets/landmarks/alcatraz_island/'+name+'.glb.import'],cwd=ROOT,text=True)
  check(uid.startswith('uid://') and uid==re.search(r'uid="([^"]+)"',old).group(1),name+': original Godot UID retained')
  check('gltf/texture_map_mode=1' in imp and 'meshes/light_baking=1' in imp,name+': import format')
  uids.append(uid);digest=hashlib.sha256(path.read_bytes()).hexdigest();check(digest==entry['sha256'],name+': manifest exact SHA')
  if name=='alc_bench':
   check(abs(hi[0]-lo[0]-1.5)<1e-6,name+': width 1.50m')
   central=xyz[(np.abs(xyz[:,0])<.751)&(np.abs(xyz[:,2])<.20)&(xyz[:,1]>.4)&(xyz[:,1]<.48)]
   check(abs(central[:,1].max()-.45)<1e-6,name+': seat surface .45m')
  if name=='alc_lamp':check(abs(hi[1]-3.5)<1e-6,name+': 3.50m height')
  if name.startswith('alc_rail'):check(abs(hi[1]-1)<1e-6,name+': 1.00m height')
  if name in ['alc_rail_straight','alc_curb']:check(abs(lo[0]+1)<1e-6 and abs(hi[0]-1)<1e-6,name+': exact 2m baseline for all layout scales')
  if name=='alc_curb':check(abs(hi[1]-.25)<1e-6,name+': updated .25m height')
  if name.startswith('alc_tree'):check(5<=hi[1]<=7,name+': real 5-7m height')
  if name=='alc_flowerbed':check(np.allclose((hi-lo)[[0,2]],[1.7,1.7],atol=1e-6),name+': real 1.7m square flowerbed')
  if name=='alc_sign':check(abs(hi[1]-1.5)<1e-6,name+': 1.5m height, blank face')
  assets[name]=dict(triangles=len(indices),surfaces=1,bounds=[lo.tolist(),hi.tolist()],uid=uid,sha256=digest)
 check(len(set(uids))==10,'ten distinct existing Godot UIDs')
 counts={name:sum(p['asset']==name for p in layout['placements']) for name in assets}
 check(sum(counts.values())==442,'442 owner placements match layout')
 check(all(p.get('owner')=='赵云' and p.get('multimesh') for p in layout['placements'] if p['asset'] in assets),'all assigned instances use MultiMesh')
 by_name={p['name']:p for p in layout['placements']}
 check(all(np.allclose(p['position'],by_name[p['name']]['position']) and p['scale']==by_name[p['name']]['scale'] for p in layout['instances']),'instances and placements positions/scales agree')
 segments=[]
 for p in layout['placements']:
  if p['asset']!='alc_rail_straight':continue
  b,at=transform(p);start=at+b@np.array([-1,0,0]);end=at+b@np.array([1,0,0]);length=np.linalg.norm((end-start)[[0,2]])
  segments.append(dict(name=p['name'],start=start.tolist(),end=end.tolist(),horizontal_length=length,slope=p.get('slope_rise_m',0),basis=b.tolist()))
  check(abs(length-2*p['scale'][0])<1e-6,p['name']+': exported length matches placement spacing')
  check(np.allclose(b[:,1],[0,1,0]),p['name']+': posts remain vertical with supplied shear')
  c=by_name[p['name'].replace('alc_rail_straight','alc_curb')];cb,cp=transform(c)
  check(np.allclose(b,cb) and np.allclose(at,cp),p['name']+': curb shares exact endpoints and slope')
 # A same-line connection is exact when neighbouring generated run segments share an endpoint.
 joins=[];transitions=[]
 for i,a in enumerate(segments):
  for b in segments[i+1:]:
   for an in ['start','end']:
    for bn in ['start','end']:
     pa,pb=np.array(a[an]),np.array(b[bn])
     if np.linalg.norm((pa-pb)[[0,2]])<1e-6:
      gap=abs(float(pa[1]-pb[1]));row={'a':a['name'],'b':b['name'],'height_gap_m':gap}
      if gap<1e-6:joins.append(row)
      elif gap<.3:transitions.append(row)
 check(len(joins)>100,'over 100 exact coincident rail/curb joins')
 # Original blockout files are not copied into the delivery tree; preview copy is hash-identical.
 stage=json.loads((OUT/'stage.json').read_text())
 for path,digest in stage['unchanged_blockout_files'].items():check(hashlib.sha256((OUT/'project'/path).read_bytes()).hexdigest()==digest,'unchanged blockout: '+path)
 check(not (KIT/'layout.json').exists(),'main island layout remains owned by Marco Polo')
 report=dict(passed=all(c['passed'] for c in checks),checks=checks,assets=assets,counts=counts,
  unique_triangles=sum(a['triangles'] for a in assets.values()),placed_triangles=sum(assets[n]['triangles']*count for n,count in counts.items()),
  exact_joins=len(joins),existing_height_transitions=transitions,segments=segments,
  tree_30_estimate_extra_triangles=27*max(assets[n]['triangles'] for n in ['alc_tree_a','alc_tree_b']))
 (OUT/'asset-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print('ALC_VERIFY',report['passed'],len(checks),'checks; unique',report['unique_triangles'],'placed',report['placed_triangles'],'joins',len(joins),'existing transitions',len(transitions))
 raise SystemExit(not report['passed'])
if __name__=='__main__':main()
