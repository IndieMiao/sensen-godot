"""Independent audit of exported farmhouse buffers; run with ordinary Python."""
from pathlib import Path
import hashlib,json,math,sys
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor,cross,sub
SRC=Path(__file__).resolve().parent
OUT=ROOT/'output/homestead-440'
report={'checks':[],'assets':{}}
def check(ok,label):
 report['checks'].append({'check':label,'passed':bool(ok)})
 if not ok:print('FAIL',label)
manifest=json.loads((SRC/'manifest.json').read_text())
cottage_path=ROOT/'assets/farm/art/house_cottage.glb'
cottage,buffer=load_glb(cottage_path)
reference_colors=set(tuple(c[:3]) for c in accessor(cottage,buffer,cottage['meshes'][0]['primitives'][0]['attributes']['COLOR_0']))
cottage_vertices=accessor(cottage,buffer,cottage['meshes'][0]['primitives'][0]['attributes']['POSITION'])
storage,storage_buffer=load_glb(ROOT/'assets/farm/art/storage.glb')
storage_vertices=accessor(storage,storage_buffer,storage['meshes'][0]['primitives'][0]['attributes']['POSITION'])
# Exact pinned look_parts timber wing: +90deg Y, scale1.6, origin house+(-1.63,0,-.75).
legacy_left=min(min(p[0] for p in cottage_vertices),min(-1.63+1.6*p[2] for p in storage_vertices))
legacy_right=max(p[0] for p in cottage_vertices)
report['existing_lv8_timber_width_m']=legacy_right-legacy_left
report['existing_lv8_timber_x_bounds']=[legacy_left,legacy_right]
check(hashlib.sha256(cottage_path.read_bytes()).hexdigest()==manifest['cottage_palette_sha256'],'actual cottage palette source unchanged')
for key in manifest['structural_palette_keys']:
 color=manifest['palette_sampled_linear'][key]
 check(tuple(color) in reference_colors,key+': actual cottage COLOR_0 sample')
for name in ['master_farmhouse_a','master_farmhouse_b']:
 path=ROOT/'assets/farm/art'/(name+'.glb');doc,data=load_glb(path)
 entry=manifest['assets'][name]
 check(len(doc.get('meshes',[]))==1,name+': one mesh')
 prim=doc['meshes'][0]['primitives'];check(len(prim)==1,name+': one surface')
 check(len(doc.get('materials',[]))==1 and not doc.get('textures') and not doc.get('images'),name+': one vertex-color material, no textures')
 check(not doc.get('cameras') and not doc.get('animations') and 'KHR_lights_punctual' not in doc.get('extensions',{}),name+': no lights / cameras / animations')
 p=prim[0];check(set(p['attributes'])=={'POSITION','NORMAL','COLOR_0'},name+': position / normal / color only')
 vertices=accessor(doc,data,p['attributes']['POSITION']);normals=accessor(doc,data,p['attributes']['NORMAL']);colors=accessor(doc,data,p['attributes']['COLOR_0'])
 indices=[x[0] for x in accessor(doc,data,p['indices'])]
 check(len(indices)%3==0 and len(indices)//3==entry['triangles'] and len(indices)//3<=9000,name+': triangle budget / manifest')
 bounds=[[f(v[i] for v in vertices) for i in range(3)] for f in [min,max]]
 check(all(abs(bounds[j][i]-entry['bounds'][j][i])<1e-6 for i in range(3) for j in range(2)),name+': GLB bounds equal manifest')
 check(abs(bounds[0][1])<1e-6 and bounds[1][1]<=4.2,name+': grounded / chimney height <=4.2m')
 check(bounds[1][0]<=1.13001,name+': right limit no larger than cottage')
 check(bounds[0][0]>=legacy_left-1e-6,name+': left limit within measured existing Lv8 timber-wing envelope')
 check(all(n.get('scale',[1,1,1])==[1,1,1] and n.get('translation',[0,0,0])==[0,0,0] and n.get('rotation',[0,0,0,1])==[0,0,0,1] for n in doc['nodes']),name+': origin / orientation / identity transform')
 check(all(len(c)==3 or abs(c[3]-1)<1e-6 for c in colors),name+': opaque vertex color')
 check(all(math.isfinite(x) for row in vertices+normals+colors for x in row),name+': finite attributes')
 check(all(abs(sum(x*x for x in n)-1)<.002 for n in normals),name+': unit normals')
 degenerate=opposite=blocked_row14=0
 def clip(poly,axis,bound,greater):
  out=[]
  for a,b in zip(poly,poly[1:]+poly[:1]):
   inside=lambda p:(p[axis]>=bound if greater else p[axis]<=bound)
   ia,ib=inside(a),inside(b)
   if ia:out.append(a)
   if ia!=ib:
    t=(bound-a[axis])/(b[axis]-a[axis]);out.append(tuple(a[k]+t*(b[k]-a[k]) for k in range(3)))
  return out
 for k in range(0,len(indices),3):
  tri=indices[k:k+3];a,b,c=[vertices[i] for i in tri]
  n=cross(sub(b,a),sub(c,a));area=math.sqrt(sum(x*x for x in n))
  degenerate+=area<1e-10
  opposite+=sum(n[j]*sum(normals[i][j] for i in tri) for j in range(3))< -1e-9
  # Existing cottage step ends at y=.126; only additional obstruction above it is forbidden.
  clipped=clip([a,b,c],2,.97501,True)
  clipped=clip(clipped,1,.13001,True) if clipped else []
  clipped=clip(clipped,1,1.99999,False) if clipped else []
  if len(clipped)>=3:
   for j in range(1,len(clipped)-1):
    crossn=cross(sub(clipped[j],clipped[0]),sub(clipped[j+1],clipped[0]))
    if sum(x*x for x in crossn)>1e-12:blocked_row14+=1;break
 check(degenerate==0,name+': no zero-area triangles')
 check(opposite==0,name+': winding agrees with normals')
 check(blocked_row14==0,name+': no new geometry in row14 below 2m, above original doorstep')
 digest=hashlib.sha256(path.read_bytes()).hexdigest();check(digest==entry['sha256'],name+': recorded GLB hash')
 imp=Path(str(path)+'.import').read_text()
 check('nodes/root_script=null' in imp and 'uid="uid://' in imp,name+': generated import UID / root_script=null')
 report['assets'][name]={'triangles':len(indices)//3,'bounds':bounds,'bytes':path.stat().st_size,'sha256':digest,'degenerate_triangles':degenerate,'opposite_normals':opposite}
report['failures']=[x for x in report['checks'] if not x['passed']]
report['pending']=manifest.get('status')
OUT.mkdir(parents=True,exist_ok=True);(OUT/'glb-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('GLB checks:',len(report['checks']),'failures:',len(report['failures']))
raise SystemExit(bool(report['failures']))
