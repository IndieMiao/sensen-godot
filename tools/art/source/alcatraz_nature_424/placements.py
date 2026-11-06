"""Suggested points only: never rewrites the scene owner's layout.json."""
from pathlib import Path
import json,math,random
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'assets/landmarks/alcatraz_island'
def main():
 layout=json.loads((SRC/'reference/blockout_layout.json').read_text());manifest=json.loads((OUT/'alc_nature_manifest.json').read_text())
 rng=random.Random(42466);points=[]
 # The actual v3 terrain outline (including sloping sides), ordered clockwise.
 outline=[(-24,14),(24,14),(25,7.5),(27,3),(29,-1.5),(30,-6),(30,-17),(27,-20),(-27,-20),(-30,-17),(-30,-6),(-29,-1.5),(-27,3),(-25,7.5)]
 # Walk surfaces include corridors even where individual navigation cells were removed.
 walks=[(-23.5,-20.5,13.5,20),(-24,-18,10.5,14),(-23.5,9.5,6,9),(-23.5,9.5,1.5,4.5),(-23.5,9.5,-3,0),(-28,28,-8,-4.5),(-23.5,-20.5,7.5,12),(6.5,9.5,3,7.5),(-23.5,-20.5,-1.5,3),(6.5,9.5,-6,-1.5)]
 def near_walk(x,z,r):return any(a-r<x<b+r and c-r<z<d+r for a,b,c,d in walks)
 def add(name,pos,zone,scale=1,yaw=None):
  points.append({'name':name+'_%03d'%sum(p['asset']==name for p in points),'asset':name,'position':[round(a,4) for a in pos],
   'rotation_degrees':[0,round(rng.uniform(0,360) if yaw is None else yaw,3),0],'scale':[scale]*3,'zone':zone,
   'owner':'刘备','placeholder':False,'collision':False,'multimesh':True,'cast_shadow':False})
 for a,b in zip(outline,outline[1:]+outline[:1]):
  dx,dz=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dz);normal=(-dz/length,dx/length)
  for i in range(max(1,int(length/2.15))):
   t=(i+.5)/max(1,int(length/2.15));x=a[0]+dx*t;z=a[1]+dz*t
   name=rng.choices(['alc_rock_a','alc_rock_b','alc_rock_c'],[2,4,4])[0];s=rng.uniform(.86,1.06)
   # South bay stays open for ferry and dock; no rock in their footprints.
   if z>12 and -25<x<7:continue
   if near_walk(x,z,1.6):continue
   x+=normal[0]*.35;z+=normal[1]*.35
   add(name,(x,-.62,z),'DockZone',round(s,3))
 # Garden bands are flat in this blockout. Placement uses their actual height;
 # final sloping terrain must be raycast/reseated by the owner after remeshing.
 bands=[(-23,23,9.3,13.4,1,'DockZone'),(-24,24,4.8,5.7,3.25,'TerraceZone'),
        (-26,26,.35,1.15,5.5,'TerraceZone'),(-28,28,-4.2,-3.4,7.75,'TerraceZone'),
        (-28,28,-19.1,-18.6,10,'SummitZone')]
 for bi,(x0,x1,z0,z1,y,zone) in enumerate(bands):
  for i in range(int((x1-x0)/2.2)):
   x=x0+(i+.5)*2.2+rng.uniform(-.35,.35);z=rng.uniform(z0,z1)
   name='alc_shrub_a' if i%3 else 'alc_shrub_b';s=round(rng.uniform(.8,1.05),3)
   dim=manifest['assets'][name]['dimensions_m'];radius=math.hypot(dim[0],dim[2])/2*s
   if near_walk(x,z,radius+.25):continue
   if any(math.hypot(x-p['position'][0],z-p['position'][2])<radius+1 for p in layout['placements'] if abs(p['position'][1]-y)<.6):continue
   if y==1 and x< -16:continue
   add(name,(x,y-.035,z),zone,s)
 # Grass sprigs fill the same bands, keeping substantial visible earth between.
 for x0,x1,z0,z1,y,zone in bands:
  for i in range(int((x1-x0)/1.15)):
   x=x0+(i+.5)*1.15+rng.uniform(-.25,.25);z=rng.uniform(z0,z1)
   if near_walk(x,z,.65):continue
   if any(math.hypot(x-p['position'][0],z-p['position'][2])<.8 for p in points if abs(p['position'][1]-y)<.2):continue
   if any(math.hypot(x-p['position'][0],z-p['position'][2])<1 for p in layout['placements'] if abs(p['position'][1]-y)<.6):continue
   if y==1 and x< -16:continue
   add('alc_grass_tuft',(x,y-.01,z),zone,round(rng.uniform(.85,1.1),3))
 result={'task':'SGODOT-424','owner':'刘备','source_layout_commit':'34df9c0b6af42a85567dfb5318c6717f929a4ab8','status':'suggested; merge once with owner placements, never append twice',
  'axes':layout['axes'],'sea_y':-.15,'points':points,'navigation_unchanged':True,'notes':['No collisions or interactions. Keep decorative foliage low.','Rocks embed into island foot at Y=-0.62. Ground-centre origin remains Y=0 in each GLB.','Plants sit on v3 flat garden bands; re-seat after owner changes terrain.','Full island bounds extend slightly at shoreline; existing walking boundaries are untouched.','Cast shadows disabled in review for small repeated nature; final scene owner controls policy.']}
 result['counts']={n:sum(p['asset']==n for p in points) for n in manifest['assets']}
 result['placed_triangles']=sum(manifest['assets'][p['asset']]['triangles'] for p in points)
 (OUT/'alc_nature_placements.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n');print(result['counts'],result['placed_triangles'])
if __name__=='__main__':main()
