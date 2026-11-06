"""Suggest discrete colour clusters every 6.5m on the three garden terraces.
Read actual v6 ground triangles; never edit the island layout or navigation.
"""
from pathlib import Path
import hashlib,json,math,sys
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/alcatraz-garden-424';KIT=QA/'project/assets/landmarks/alcatraz_island'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
BASE='b16c31982f34a64cdd4f9c6683064edbf20837a0'
def main():
 layout=json.loads((HERE/'reference/layout-b16c3198.json').read_text());stats=json.loads((HERE/'asset_stats.json').read_text())['assets']
 ground=[]
 for name in ['alc_ground_dock','alc_ground_terraces','alc_ground_summit']:
  doc,data=load_glb(KIT/(name+'.glb'))
  for mesh in doc['meshes']:
   for p in mesh['primitives']:
    pts=np.array(accessor(doc,data,p['attributes']['POSITION']));ind=np.array(accessor(doc,data,p['indices'])).reshape(-1,3);tri=pts[ind]
    normal=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);good=normal[:,1]>1e-5;ground.extend(tri[good])
 ground=np.array(ground)
 def height(x,z):
  a=ground[:,0];u=ground[:,1]-a;v=ground[:,2]-a;dx=x-a[:,0];dz=z-a[:,2];det=u[:,0]*v[:,2]-u[:,2]*v[:,0]
  valid=np.abs(det)>1e-8;uu=np.zeros(len(a));vv=uu.copy();uu[valid]=(dx[valid]*v[valid,2]-dz[valid]*v[valid,0])/det[valid];vv[valid]=(u[valid,0]*dz[valid]-u[valid,2]*dx[valid])/det[valid]
  valid &= (uu>=-1e-6)&(vv>=-1e-6)&(uu+vv<=1.000001)
  return float(np.max((a[:,1]+uu*u[:,1]+vv*v[:,1])[valid])) if np.any(valid) else None
 def box(name,at,yaw=0):
  lo,hi=stats[name]['bounds'];c,s=math.cos(yaw),math.sin(yaw);pts=[]
  for x in [lo[0],hi[0]]:
   for z in [lo[2],hi[2]]:pts.append([at[0]+c*x+s*z,at[2]-s*x+c*z])
  p=np.array(pts);return p.min(axis=0),p.max(axis=0)
 # Conservative horizontal boxes for same-elevation existing props and path rims.
 obstacles=[]
 for p in layout['placements']:
  n=p['asset'];x,y,z=p['position'];w,d=None,None
  if n=='alc_flowerbed':w,d=1.70,1.70
  elif n=='alc_lamp':w,d=.44,.46
  elif n=='alc_sign':w,d=.78,.20
  elif n=='alc_bench':w,d=1.50,.52
  elif n=='alc_bin':w,d=.48,.48
  elif n in ['alc_tree_a','alc_tree_b']:w,d=.55,.55
  elif n=='alc_shrub':w,d=1,.8
  elif n in ['alc_rail_straight','alc_curb']:
   sx=float(p['scale'][0]);yaw=p['yaw'];w=abs(math.cos(yaw))*2*sx+abs(math.sin(yaw))*.18;d=abs(math.sin(yaw))*2*sx+abs(math.cos(yaw))*.18
  if w is not None:obstacles.append((n,y,np.array([x-w/2,z-d/2]),np.array([x+w/2,z+d/2])))
 rows=[];patches=[];rejected=[]
 def validate(name,at,yaw=0):
  lo,hi=box(name,at,yaw)
  # Real ground footprint must be at the same top elevation, including centre/corners.
  samples=[(at[0],at[2])]+[(x,z) for x in [lo[0],hi[0]] for z in [lo[1],hi[1]]]
  if any(height(x,z) is None or abs(height(x,z)-at[1])>.06 for x,z in samples):return False,'ground-height'
  for n,y,a,b in obstacles:
   if abs(y-at[1])>.3:continue
   margin=.12 if n not in ['alc_rail_straight','alc_curb'] else .08
   if np.all(hi>a-margin) and np.all(lo<b+margin):return False,'obstacle '+n
  for r in rows:
   if abs(r['position'][1]-at[1])>.1:continue
   a,b=box(r['asset'],r['position'],math.radians(r['rotation_degrees'][1]))
   if np.all(hi>a+.01) and np.all(lo<b-.01):return False,'new-piece overlap'
  return True,''
 def put(name,at,group,yaw=0):
  lo,hi=box(name,at,yaw)
  rows.append({'name':f'{name}_garden_{len(rows):03d}','asset':name,'position':[round(v,6) for v in at],'rotation_degrees':[0,round(math.degrees(yaw),6),0],'scale':[1,1,1],'zone':'TerraceZone' if 1.1<at[1]<9.9 else 'DockZone' if at[1]<1.1 else 'SummitZone','owner':'赵云','multimesh':True,'collision':False,'group':group,'footprint_xz':[lo.tolist(),hi.tolist()]})
 species=['alc_flowers_poppy','alc_flowers_lavender','alc_flowers_daisy']
 for row,(y,path_z) in enumerate([(3.25,7.5),(5.5,3),(7.75,-1.5)]):
  for station,x in enumerate([-18.5,-12,-5.5,1,5.1]):
   group=f'terrace_{row+1}_focus_{station+1}';main=species[(station+row)%3];accent=species[(station+row+1)%3]
   # Actual unpaved strip is narrow because the next level's paving overhangs it.
   # Interleave flowers and short hedge breaks on that strip, not behind the upper paving.
   before=len(rows)
   for j,n in enumerate([main,main,accent]):
    found=False
    for dx in [-.65,.10,.85,-1.4,1.6,-2.15,2.35]:
     at=[x+dx,y,path_z-2.18];yaw=0
     ok,why=validate(n,at,yaw)
     if ok:put(n,at,group,yaw);found=True;break
    if not found:rejected.append({'group':group,'asset':n,'reason':'no clear footprint in this group neighbourhood'})
   for j in range(2):
    found=False
    for dx in [-2.35,2.35,-3.35,3.35,-1.65,1.65]:
     at=[x+dx,y,path_z-2.18];ok,why=validate('alc_hedge',at)
     if ok:put('alc_hedge',at,group);found=True;break
    if not found:rejected.append({'group':group,'asset':'alc_hedge','reason':'keep gap; no clear 1m hedge slot'})
   patches.append({'name':group,'walk_station':[x,y,path_z],'main_flower':main,'added_instances':len(rows)-before,'nominal_station_gap_m':6.5,'edge_note':'Rightmost group supplements the existing stair-end flowerbed; fewer new pieces preserve clearance.' if station==4 else ''})
 for i,at in enumerate([[-24.0,1,9.0],[-25.1,3.25,5.6],[-25.2,5.5,1.1],[-25.1,7.75,-3.2]]):
  ok,why=validate('alc_planter',at)
  if ok:put('alc_planter',at,f'terrace_end_{i}')
  else:rejected.append({'asset':'alc_planter','position':at,'reason':why})
 assert len(rows)>40,(len(rows),rejected)
 assert all(p['added_instances']>=1 for p in patches),patches
 report={'author':'赵云','task':'SGODOT-424','layout_reference':BASE,'phase':'placement suggestion; scene owner integrates after review',
  'rules':['米制、Y上；新五件独立MultiMesh，不能合进主体GLB。','三条台地长直路每6.5m一个花色组，与既有长椅/花坛共同补看点；不把整条路封成连续绿墙。','所有根部和水平边角采样均在当前真实地面高度，避开原栏杆、现有道具及树干；不占可走铺装。','盆栽只放台地西侧端头；客户端接入前复核当前UI/视角，不向纯展示场景加交互。','保留原场景layout和导航；旧主体/旧小件保持v6状态，本建议不宣称替代整岛验收。'],
  'group_station_spacing_m':6.5,'route':layout['route'],'groups':patches,'instances':rows,'rejected_candidates':rejected,
  'counts':{n:sum(p['asset']==n for p in rows) for n in stats},'placed_triangles':sum(stats[p['asset']]['triangles'] for p in rows),
  'ground_files':{n:hashlib.sha256((KIT/(n+'.glb')).read_bytes()).hexdigest() for n in ['alc_ground_dock','alc_ground_terraces','alc_ground_summit']}}
 (HERE/'suggested_placements.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print('GARDEN_PLACEMENTS',len(rows),report['counts'],'rejected',len(rejected))
if __name__=='__main__':main()
