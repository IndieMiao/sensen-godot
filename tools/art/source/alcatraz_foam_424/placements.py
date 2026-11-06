"""Sample the actual host coastline at water height; add independent decorative instances."""
from pathlib import Path
import json,math,hashlib,numpy as np
from geometry import triangles,section,exterior
S=Path(__file__).resolve().parent;R=S.parents[3];A=R/'assets/landmarks/alcatraz_island';Q=R/'output/alcatraz-foam-424/project/assets/landmarks/alcatraz_island'
M=json.loads((A/'alc_shore_foam_manifest.json').read_text());L=json.loads((S/'reference/blockout_layout.json').read_text());P=json.loads((S/'provenance.json').read_text())
rows=[];excluded=[];counts={}
right=np.array([.96814764,0,-.25038]);up=np.array([-.170759,.731354,-.660275]);target=np.array(L['camera']['target']);pixel=360/6.72

def add(asset,pos,yaw=0,scale=(1,1,1),reason='',source=None):
 if isinstance(scale,(float,int)):scale=(scale,1,scale)
 pos=[round(float(x),5) for x in pos];scale=[float(x) for x in scale];a=math.radians(yaw);c,s=math.cos(a),math.sin(a);rotation=np.array([[c,0,s],[0,1,0],[-s,0,c]])
 import itertools
 corners=np.array(list(itertools.product(*zip(*M['assets'][asset]['bounds']))))*scale;corners=corners@rotation.T+pos-target
 xy=np.stack([180+corners@right*pixel,400-corners@up*pixel],axis=1);lo=xy.min(axis=0);hi=xy.max(axis=0)
 # Opening bridge / city + 10px buffer. Fixed camera, no screen-space shader masks.
 if lo[0]<180 and hi[0]>0 and lo[1]<160 and hi[1]>45:
  excluded.append({'asset':asset,'position':pos,'reason':'default opening bridge/city exclusion strip'});return
 i=counts.get(asset,0);counts[asset]=i+1
 row={'name':asset+'_%03d'%i,'asset':asset,'position':pos,'rotation_degrees':[0,round(yaw,5),0],'scale':scale,'zone':'DockZone','owner':'刘备','placeholder':False,'collision':False,'interaction':False,'cast_shadow':False,'multimesh':True,'purpose':reason}
 if abs(scale[0]-scale[2])>.00001:
  row['basis_columns']=(rotation@np.diag(scale)).T.round(8).tolist()
 if source:row['contact_source']=source
 rows.append(row)
# Use all three terrain meshes; internal band walls disappear via outermost crossing.
sea=-.15;foam_y=-.132
segments=np.concatenate([section(triangles(Q/(n+'.glb')),sea) for n in ['alc_ground_dock','alc_ground_terraces','alc_ground_summit']])
coast=exterior(segments);dist=np.linalg.norm(np.roll(coast,-1,axis=0)-coast,axis=1);length=float(dist.sum());arc=np.r_[0,np.cumsum(dist)]
# Uniform physical spacing, rotating both short and long ribbons around the exterior.
def at(t):
 t=t%length;i=min(len(coast)-1,np.searchsorted(arc,t,side='right')-1);f=(t-arc[i])/max(dist[i],1e-8);return coast[i]*(1-f)+coast[(i+1)%len(coast)]*f
cursor=0;i=0
while cursor<length:
 asset='alc_foam_strip_b' if i%4==1 else 'alc_foam_strip_a';span=4.8 if asset.endswith('b') else 2.8
 mid=at(cursor+span*.5);before=at(cursor+span*.5-.45);after=at(cursor+span*.5+.45);t=(after-before);t/=np.linalg.norm(t);out=np.array([t[1],-t[0]])
 center=mid+out*.20;yaw=math.degrees(math.atan2(-t[1],t[0]));add(asset,(center[0],foam_y,center[1]),yaw,reason='island waterline, sampled actual terrain at sea Y=-.15')
 cursor+=span*.92;i+=1
# Ring all 36 v3 rocks from their actual water cross-sections, not the old placeholders.
nature=json.loads((Q/'alc_nature_placements.json').read_text())
for rock in nature['points']:
 if not rock['asset'].startswith('alc_rock'):continue
 tri=triangles(Q/(rock['asset']+'.glb'))*np.array(rock['scale']);sec=section(tri,sea-rock['position'][1]);points=sec.reshape(-1,2);lo=points.min(axis=0);hi=points.max(axis=0);center=(lo+hi)/2;half=(hi-lo)/2
 yaw=rock['rotation_degrees'][1];angle=math.radians(yaw);c,s=math.cos(angle),math.sin(angle);offset=np.array([center[0]*c+center[1]*s,-center[0]*s+center[1]*c]);pos=np.array(rock['position'])
 add('alc_foam_ring',(pos[0]+offset[0],foam_y,pos[2]+offset[1]),yaw,((half[0]+.08)/.88,1,(half[1]+.08)/.88),'rock contact ring',rock['name'])
# Actual six piling centres from d7b57574 dock generator. Small rings hug each .22m pile.
for x in [-23.6,-20.4]:
 for z in [15.25,18.25,19.85]:add('alc_foam_ring',(x,foam_y,z),scale=.22,reason='dock pile contact',source='dock_000')
# Place the short curve from actual corner sections; local +Z follows the tangent.
for approximate in [(-24.4,14.15),(24.4,14.15),(-29.8,-18.2),(29.8,-18.2)]:
 nearest=int(np.argmin(np.linalg.norm(coast-np.array(approximate),axis=1)));mid=coast[nearest];t=at(arc[nearest]+.65)-at(arc[nearest]-.65);t/=np.linalg.norm(t);out=np.array([t[1],-t[0]]);center=mid+out*.12
 add('alc_foam_strip_c',(center[0],foam_y,center[1]),math.degrees(math.atan2(t[0],t[1])),reason='short arc seated on actual coastline corner')
# Low floating props stay away from the bridge strip, dock route and right-lower controls.
for pos,yaw in [((-25.0,sea,18.6),-18),((18.5,sea,15.9),21)]:add('alc_buoy',pos,yaw,reason='decorative floating harbour marker')
for pos,yaw in [((-25.3,sea,15.2),-42),((29.9,sea,5.2),35),((-9.2,sea,-21.3),-18)]:add('alc_driftwood',pos,yaw,reason='single floating bleached branch')
result={'task':'SGODOT-424','owner':'刘备','status':'additive suggestion; independent water overlays, never replace sea material','host_commit':P['host_commit'],'nature_commit':P['nature_commit'],'dock_commit':P['dock_commit'],'axes':'metres, Y up, +Z south; waterline pivots','sea_y':sea,'foam_y':foam_y,'foam_separation_m':.018,'coastline_length_m':length,'coastline_sample_source':'outermost section of actual three host terrain GLBs at sea Y=-.15','points':rows,'counts':counts,'batches':len(counts),'placed_triangles':sum(M['assets'][r['asset']]['triangles'] for r in rows),'excluded_for_bridge':excluded,'notes':['All items are decorative, no interaction/collision or shadows.','Use .import-bound shared materials; foam alpha blend, no depth writes, render_priority=1 after unchanged sea.','Four foam meshes are static, single-surface. No UV animation, shader TIME, water displacement or sea material modification.','Use basis_columns when provided: it preserves local anisotropic ring scale under rotation, per host transform contract.','Host coastline remesh or water-level change requires regenerating contact placements.','Do not restore v2 rock placements: this table uses #801 v3.','Transparent batches may overlap mildly at joins; avoid stacking duplicate placement sets.']}
(A/'alc_shore_foam_placements.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
(S/'reference/coastline.json').write_text(json.dumps({'host_commit':P['host_commit'],'sea_y':sea,'length_m':length,'section_points_xz':coast.round(5).tolist()},indent=2)+'\n')
print('SHORE_PLACEMENTS',counts,'triangles',result['placed_triangles'],'excluded',len(excluded),'coastline',round(length,2))
