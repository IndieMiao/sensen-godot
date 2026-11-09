"""SGODOT-448: decode delivered triangles, regression-test the bench and roof,
and list footprint cells independently of the modelling helper."""
from pathlib import Path
from collections import Counter
import json,sys,math,re,hashlib,colorsys
import numpy as np
from shapely.geometry import Polygon
ROOT=Path(__file__).resolve().parents[4];Q=ROOT/'output/homestead-448';KIT=ROOT/'assets/farm/art';sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
HOUSE=np.array([6.175,0,-10.725]);CELL=.65
NAMES=['porch_a','porch_b','kitchen_wing_a','kitchen_wing_b','master_farmhouse_a','master_farmhouse_b']
r={'author':'赵云','checks':[],'assets':{},'cells':{},'roof':{}}
def check(ok,label):
 r['checks'].append({'passed':bool(ok),'check':label})
 if not ok:print('FAIL',label)
def read(p):
 d,b=load_glb(p);pr=d['meshes'][0]['primitives'][0];v=np.array(accessor(d,b,pr['attributes']['POSITION']));n=np.array(accessor(d,b,pr['attributes']['NORMAL']));c=np.array(accessor(d,b,pr['attributes']['COLOR_0']))[:,:3];ids=np.array(accessor(d,b,pr['indices'])).reshape(-1,3);return d,v,n,c,ids
D={n:read(KIT/(n+'.glb')) for n in NAMES};old={n:read(Q/'before'/(n+'.glb')) for n in NAMES}
def clip(poly,axis,bound,positive):
 out=[]
 for a,b in zip(poly,poly[1:]+poly[:1]):
  da=(a[axis]-bound)*(1 if positive else -1);db=(b[axis]-bound)*(1 if positive else -1)
  if da>=0:out.append(a)
  if (da>=0)!=(db>=0):out.append(a+(b-a)*da/(da-db))
 return out
def in_box(tri,rect):
 x0,z0,x1,z1=rect;poly=list(tri)
 for ax,low,high in [(0,x0+1e-6,x1-1e-6),(2,z0+1e-6,z1-1e-6)]:
  if not poly:return False
  poly=clip(poly,ax,low,True)
  if not poly:return False
  poly=clip(poly,ax,high,False)
 return len(poly)>=3 and any(np.linalg.norm(np.cross(poly[j]-poly[0],poly[j+1]-poly[0]))>1e-10 for j in range(1,len(poly)-1))
def count_box(data,rect):return sum(in_box(tri,rect) for tri in data[1][data[4]])
def sig(data):
 _,v,n,c,ids=data;verts=[tuple(a)+tuple(b)+tuple(d) for a,b,d in zip(v,n,c)];out=Counter()
 for ix in ids:
  t=tuple(verts[i] for i in ix);out[min(t,t[1:]+t[:1],t[2:]+t[:2])]+=1
 return out
protected=(-2.925,-.825,-1.625,.825);front=(-2.925,.325,-1.625,.975)
for name,data in D.items():
 d,v,n,c,ids=data;imp=(KIT/(name+'.glb.import')).read_text();oldimp=(Q/'before'/(name+'.glb.import')).read_text();uid=lambda x:re.search(r'^uid="([^"]+)"$',x,re.M).group(1)
 check(uid(imp)==uid(oldimp),name+': original UID preserved')
 check('nodes/root_script=null' in imp and 'meshes/create_shadow_meshes=true' in imp,name+': root_script + shadow meshes')
 check(len(d['meshes'])==1 and len(d['meshes'][0]['primitives'])==1,name+': single surface')
 check(not any(d.get(k) for k in ['textures','images','skins','animations','cameras']),name+': vertex-paint static prop only')
 r['assets'][name]={'triangles':len(ids),'before_triangles':len(old[name][4]),'uid':uid(imp),'sha256':hashlib.sha256((KIT/(name+'.glb')).read_bytes()).hexdigest()}
 if 'wing' in name or 'farmhouse' in name:
  hits=count_box(data,protected);oldhits=count_box(old[name],protected);fronthits=count_box(data,front)
  check(hits==0,name+': entire bench +0.5m buffer clear')
  check(fronthits==0,name+': bench front-row cells clear')
  check(oldhits>0,name+': regression reproduces original penetration')
  r['assets'][name].update(protected_triangle_hits=hits,before_hits=oldhits,front_row_hits=fronthits)
for look in ['a','b']:
 main='master_farmhouse_'+look;wing='kitchen_wing_'+look;before=sig(old[main]);beforewing=sig(old[wing]);after=sig(D[main]);afterwing=sig(D[wing]);check(not beforewing-before and not afterwing-after,main+': source wing exactly embedded');check(before-beforewing==after-afterwing,main+': every non-wing position/normal/colour unchanged')
# Cells touched by actual projected geometry. Wall candidates are tall near-ground vertical faces.
for name in ['kitchen_wing_a','kitchen_wing_b']:
 _,v,n,c,ids=D[name];world=v+HOUSE;allcells=set();wallcells=set()
 for tri,ns in zip(world[ids],n[ids]):
  wall=tri[:,1].min()<.2 and np.ptp(tri[:,1])>.25 and abs(ns[:,1].mean())<.1
  for x in range(math.floor(tri[:,0].min()/CELL),math.floor(tri[:,0].max()/CELL)+1):
   for y in range(math.floor(-tri[:,2].max()/CELL),math.floor(-tri[:,2].min()/CELL)+1):
    if in_box(tri,(x*CELL,-(y+1)*CELL,(x+1)*CELL,-y*CELL)):
     allcells.add((x,y))
     if wall:wallcells.add((x,y))
 r['cells'][name]={'all_geometry':sorted(allcells),'wall_geometry':sorted(wallcells)}
# Exact triangle/triangle roof intersections, with AABB culling and both edge directions.
def segment_hit(a,b,tri):
 direction=b-a;e1=tri[1]-tri[0];e2=tri[2]-tri[0];h=np.cross(direction,e2);det=e1@h
 if abs(det)<1e-10:return False
 inv=1/det;s=a-tri[0];u=inv*(s@h);q=np.cross(s,e1);vv=inv*(direction@q);t=inv*(e2@q)
 return -.000001<=u<=1.000001 and vv>=-.000001 and u+vv<=1.000001 and -.000001<=t<=1.000001
def intersect(a,b):
 if any(segment_hit(t[i],t[(i+1)%3],other) for t,other in [(a,b),(b,a)] for i in range(3)):return True
 na=np.cross(a[1]-a[0],a[2]-a[0]);nb=np.cross(b[1]-b[0],b[2]-b[0]);na/=np.linalg.norm(na);nb/=np.linalg.norm(nb)
 if np.linalg.norm(np.cross(na,nb))<1e-6 and abs((b[0]-a[0])@na)<1e-6:
  axes=[i for i in range(3) if i!=np.argmax(abs(na))];return Polygon(a[:,axes]).intersection(Polygon(b[:,axes])).area>1e-10
 return False
house=read(KIT/'house_cottage.glb');hv=house[1];hc=house[3];hi=house[4];roofmask=((hc[hi][:,:,0]>hc[hi][:,:,2]*7).all(1)&(hv[hi][:,:,1].min(1)>1.1));roof=hv[hi][roofmask];lo=roof.min(1);high=roof.max(1)
def roof_hits(data):
 hits=0
 for tri in data[1][data[4]]:
  possible=np.where(((tri.max(0)>=lo-1e-6)&(tri.min(0)<=high+1e-6)).all(1))[0]
  if any(intersect(tri,roof[i]) for i in possible):hits+=1
 return hits
for name in ['porch_a','porch_b']:
 hits=roof_hits(D[name]);before=roof_hits(old[name]);check(hits==0,name+': no cottage-roof intersection');r['roof'][name]={'intersecting_triangles':hits,'before':before}
old_top=float(old['porch_a'][1][:,1].max());house_roof_top=float(roof[:,:,1].max())
check(old_top>house_roof_top+.1,'roof regression reproduces old porch crest above main roof')
r['roof']['old_porch_a_top_m']=old_top;r['roof']['main_roof_top_m']=house_roof_top
# Upward ray gaps for top-facing orange vertices on the actual hood's highest wall edge.
def upward_gap(p):
 a=roof[:,0];e1=roof[:,1]-a;e2=roof[:,2]-a;direction=np.array([0.,1.,0.]);h=np.cross(direction,e2);det=(e1*h).sum(1);valid=abs(det)>1e-10;inv=np.zeros_like(det);inv[valid]=1/det[valid];s=p-a;u=inv*(s*h).sum(1);q=np.cross(s,e1);vv=inv*(q*direction).sum(1);t=inv*(e2*q).sum(1);valid&=(u>=-1e-6)&(vv>=-1e-6)&(u+vv<=1.000001)&(t>1e-6);return float(t[valid].min()) if valid.any() else None
for name in ['porch_a','porch_b']:
 _,v,n,c,ids=D[name];select=(v[:,2]>=.825)&(v[:,2]<=.831)&(n[:,1]>.1)&(c[:,0]>7*c[:,2])&(v[:,1]>.8);gaps=[upward_gap(p) for p in v[select]];gaps=[g for g in gaps if g is not None];check(bool(gaps) and min(gaps)>.09 and max(gaps)<.14,name+': measured wall-edge roof gap about0.10m');r['roof'][name]['wall_edge_gap_range_m']=[min(gaps),max(gaps)] if gaps else None
palette=json.loads((ROOT/'tools/art/source/homestead_looks_439/asset_stats.json').read_text())['palette_srgb'];r['roof_paint']={}
for base in ['orange','orange_light']:
 rgb=lambda s:tuple(int(s[i:i+2],16)/255 for i in [0,2,4]);hsv0=colorsys.rgb_to_hsv(*rgb(palette[base]));hsv1=colorsys.rgb_to_hsv(*rgb(palette['porch_'+base]));ratio=hsv1[2]/hsv0[2];dh=abs(hsv1[0]-hsv0[0])*360;check(abs(ratio-.85)<.005 and dh<.5,'roof '+base+': value -15%, hue preserved within8-bit rounding');r['roof_paint'][base]={'before':palette[base],'after':palette['porch_'+base],'value_ratio':ratio,'hue_delta_degrees':dh}
r['passed']=all(x['passed'] for x in r['checks']);(Q/'clearance-validation.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print('CLEARANCE',r['passed'],len(r['checks']),'checks');print('CELLS',r['cells']);print('ROOF',r['roof']);raise SystemExit(0 if r['passed'] else 1)
