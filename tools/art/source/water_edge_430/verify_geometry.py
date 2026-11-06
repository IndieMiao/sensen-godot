"""Validate exported topology, all directed port pairs and review-layer overlap."""
from pathlib import Path
import json,sys,math,hashlib
import numpy as np
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
sys.path.insert(0,str(ROOT/'tools/art/source/alcatraz_foam_424'))
from geometry import read_glb
from PIL import Image
OUT=ROOT/'assets/landmarks/_shared/water_edge';report={'checks':[]}
def check(ok,name,**data):
 report['checks'].append({'passed':bool(ok),'check':name,**data});assert ok,(name,data)
m=json.loads((OUT/'manifest.json').read_text());geo={}
for name,r in m['assets'].items():
 g,parts=read_glb(OUT/r['file']);check(len(parts)==1,name+' single surface')
 p=parts[0];tris=p['POSITION'][p['indices']].reshape(-1,3,3);geo[name]=tris[:,:,[0,2]]
 check(len(tris)==r['triangles'] and len(tris)<=80,name+' triangle budget')
 check(np.all(p['NORMAL'][:,1]>.999),name+' normals')
 check(np.max(np.abs(p['POSITION'][:,1]))<1e-6,name+' local water Y=0')
 check(not g.get('textures') and not g.get('images'),name+' external shared texture')
def rotate(p,degrees):
 a=math.radians(degrees);return np.asarray(p)@np.array([[math.cos(a),-math.sin(a)],[math.sin(a),math.cos(a)]])
maxerr=0
for kind in ['straight','outer','inner']:
 end=np.asarray(m['assets']['water_edge_'+kind]['ports'][1]['edge_xz'])
 angle,pos={'straight':(0,[2,0]),'outer':(90,[0,-2]),'inner':(-90,[0,2])}[kind]
 for nxt in ['straight','outer','inner']:
  start=np.asarray(m['assets']['water_edge_'+nxt]['ports'][0]['edge_xz'])
  error=np.max(np.abs(end-(rotate(start,angle)+pos)));maxerr=max(maxerr,float(error))
  check(error<1e-6,kind+' to '+nxt+' exact directed port',error_m=float(error))
# Convex triangle intersection, testing positive area only (touching seams are legal).
def cross(a,b):return float(a[0]*b[1]-a[1]*b[0])
def area(poly):return abs(sum(cross(poly[i],poly[(i+1)%len(poly)]) for i in range(len(poly)))/2) if len(poly)>2 else 0

def overlap(a,b):
 if np.any(a.max(0)<=b.min(0)+1e-7) or np.any(b.max(0)<=a.min(0)+1e-7):return 0
 if cross(b[1]-b[0],b[2]-b[0])<0:b=b[::-1]
 poly=list(a)
 for i in range(3):
  p,q=b[i],b[(i+1)%3];new=[]
  for j,v in enumerate(poly):
   w=poly[(j+1)%len(poly)];dv=cross(q-p,v-p);dw=cross(q-p,w-p)
   if dv>=-1e-10:new.append(v)
   if (dv>=0)!=(dw>=0):new.append(v+(w-v)*dv/(dv-dw))
  poly=new
  if not poly:return 0
 return area(poly)
selfmax=0
for name,tris in geo.items():
 for i,a in enumerate(tris):
  for b in tris[i+1:]:selfmax=max(selfmax,overlap(a,b))
check(selfmax<1e-7,'no self overlapping foam triangles',max_area_m2=selfmax)
placements=[('straight',[-2,4],0),('outer',[0,4],0),('straight',[0,2],90),('inner',[0,0],90),('steps',[2,0],0),('straight',[4,0],0),('pile_ring',[-2.72,7],0),('pile_ring',[-1.28,7],0)]
placed=[rotate(geo['water_edge_'+name],angle)+pos for name,pos,angle in placements]
maxoverlap=0
for i,aa in enumerate(placed):
 for bb in placed[i+1:]:
  for a in aa:
   for b in bb:maxoverlap=max(maxoverlap,overlap(a,b))
check(maxoverlap<1e-7,'review foam layer count <= 1 everywhere',max_area_m2=maxoverlap)
a=np.asarray(Image.open(OUT/'water_edge_soft.png'));check(np.array_equal(a[:,0],a[:,-1]),'U seam pixel-identical')
check(a[0,:,3].max()==0 and a[-1,:,3].max()==0,'V edge fully transparent')
check(hashlib.sha256((OUT/'water_edge_soft.png').read_bytes()).hexdigest()==m['texture']['sha256'],'accepted #824 texture unchanged bytes')
report.update(passed=True,max_port_error_m=maxerr,triangle_total=m['unique_triangles'],texture_reads=1,transparent_passes=1,maximum_foam_layers=1)
(ROOT/'output/water-edge-430/geometry-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('WATER_EDGE_GEOMETRY_PASS',len(report['checks']))
