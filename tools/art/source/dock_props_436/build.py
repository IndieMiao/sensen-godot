"""SGODOT-436 dock props. Run Blender under flock ~/gs66-render.lock."""
from pathlib import Path
import bpy,math,json,importlib.util,sys
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/landmarks/_shared/dock_props'
spec=importlib.util.spec_from_file_location('street',SRC.parent/'street_kit_429/build.py');s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)
s.SRC=SRC;s.KIT=KIT
s.PAL={'wood':'A3815D','wood_light':'B89972','wood_dark':'795F47','wood_seam':'69543F','metal':'5D4C38','metal_light':'6D5746','cream':'F0E1C2','stone':'CBB48F','teal':'35696A','glass':'86B0B3','roof':'748B9C','roof_shade':'5E7383','rope':'B7A68D','rope_light':'C9BA9E','rope_dark':'96866F','red':'C76845','lamp':'F2DC9F','dark':'3F463D'}
p=s.p;box=s.box;rod=s.rod;lathe=s.lathe;mesh=s.mesh

def roof(name,w,d,eave,ridge):
 v=[(-w/2,eave,-d/2),(w/2,eave,-d/2),(w/2,eave,d/2),(-w/2,eave,d/2),(-w/2,ridge,0),(w/2,ridge,0)]
 mesh(name,v,[(0,4,5,1),(4,3,2,5),(0,3,4),(1,5,2),(0,1,2,3)],['roof_shade','roof','roof','roof','wood_dark'])
 for z in [-d/2,d/2]:box('Cream roof edge',(0,eave,z),(w,.065,.065),'cream',.01)

def ticket_booth():
 box('Booth foundation',(0,.06,0),(1.8,.12,1.5),'stone',.025)
 for x in [-.82,.82]:
  for z in [-.66,.66]:box('Timber corner post',(x,1.20,z),(.13,2.16,.13),'wood_dark',.015)
 box('Rear cream wall',(0,1.15,-.66),(1.64,2.04,.08),'cream')
 for x in [-.82,.82]:box('Cream side wall',(x,1.15,0),(.08,2.04,1.32),'cream')
 box('Counter lower wood wall',(0,.60,.66),(1.64,.96,.08),'wood')
 for x in [-.72,.72]:box('Service opening jamb',(x,1.57,.68),(.12,.90,.11),'wood_dark',.012)
 box('Service opening lintel',(0,2.06,.68),(1.56,.10,.11),'wood_dark',.012)
 box('Broad ticket counter',(0,1.08,.72),(1.74,.08,.36),'wood_light',.018)
 box('Inner shallow shelf',(0,1.12,-.38),(1.45,.065,.25),'wood')
 roof('Small pitched kiosk roof',2.0,1.70,2.29,2.60)
 box('Blank header sign frame',(0,2.12,.745),(1.10,.31,.045),'wood_dark',.012)
 box('Unlettered graphic field',(0,2.12,.772),(.96,.23,.014),'teal')
 for x in [-.56,-.28,0,.28,.56]:box('Quiet lower front board joint',(x,.60,.704),(.012,.82,.007),'wood_seam')
 return {'front':'+Z service opening','countertop_y_m':1.12,'graphic_area_m':[.96,.23],'graphic_center_m':[0,2.12,.78],'content':'Blank graphic field only; no lettering or NPC/interaction anchors'}

def waiting_shelter():
 for x in [-1.0,1.0]:
  for z in [-.64,.64]:box('Shelter timber post',(x,1.13,z),(.13,2.26,.13),'wood_dark',.016)
 for z in [-.64,.64]:box('Shelter upper beam',(0,2.23,z),(2.26,.15,.14),'wood',.016)
 roof('Pitched waiting roof',2.4,1.75,2.31,2.60)
 for x in [-.70,.70]:box('Bench trestle',(x,.31,-.12),(.20,.62,.43),'wood_dark',.016)
 for j in range(3):box('Waiting bench seat slat',(0,.6825,-.12+(j-1)*.17),(1.82,.065,.16),'wood_light' if j==1 else 'wood',.012)
 for x in [-.75,.75]:rod('Bench back support',(x,.64,-.39),(x,1.20,-.44),.03,'metal',4)
 for j in range(2):box('Waiting bench back board',(0,.94+j*.17,-.44),(1.82,.13,.06),'wood',.012)
 for x in [-1,1]:rod('Shelter knee brace',(x,1.96,-.64),(x*.7,2.19,-.64),.035,'wood_dark',4)
 return {'front':'+Z','seat_height_m':.715,'seat_width_m':1.82,'content':'Shelter with decorative waiting bench; no seat anchors'}

def gangplank():
 box('Gangway solid deck core',(0,.04,0),(2.4,.08,1.2),'wood_seam')
 for i in range(14):
  x0=-1.19+i*.18;x1=min(x0+.168,1.19)
  if x1>x0:box('Cross-grain anti-slip board',((x0+x1)/2,.09,0),(x1-x0,.02,1.18),'wood_light' if i%4==0 else 'wood')
 for x in [-1.195,1.195]:box('Flush end edge',(x,.09,0),(.01,.02,1.2),'wood_light')
 for z in [-.56,.56]:
  for x in [-1.12,0,1.12]:rod('Gangway guard post',(x,.07,z),(x,1.03,z),.027,'metal',6)
  rod('Round top handrail',(-1.2,1.03,z),(1.2,1.03,z),.027,'metal',6)
  box('Timber foot guard',(0,.18,z),(2.4,.10,.055),'wood_dark')
  box('Side hinge plate',(-1.12,.07,z),(.15,.07,.075),'metal')
 return {'axis':'+X boarding direction','deck_y_m':.10,'deck_size_m':[2.4,1.2],'ports':{'dock':[-1.2,.1,0],'boat':[1.2,.1,0]},'coast_426_connection':{'asset':'coast_dock_end','dock_terminal':[1,1.2,0],'root_offset_for_unrotated_dock':[2.2,1.1,0],'terminal_bumper_clearance_each_side_m':.13},'content':'Level demonstration; adjust host transform about dock connector for other boat heights'}

def torus(name,at,rx,ry,r,normal,role,n=16,k=4,bands=False):
 # Use an explicit planar frame, so coils and the lifebuoy never twist.
 normal=Vector(normal).normalized();u=Vector((1,0,0));u=(u-normal*u.dot(normal)).normalized();v=normal.cross(u)
 pts=[]
 for i in range(n):
  a=i*math.tau/n;centre=Vector(at)+rx*math.cos(a)*u+ry*math.sin(a)*v
  radial=(math.cos(a)*u+math.sin(a)*v).normalized()
  for j in range(k):t=j*math.tau/k;pts.append(centre+r*(math.cos(t)*radial+math.sin(t)*normal))
 faces=[];roles=[]
 for i in range(n):
  for j in range(k):faces.append((i*k+j,i*k+(j+1)%k,((i+1)%n)*k+(j+1)%k,((i+1)%n)*k+j));roles.append('red' if bands and i%4<2 else role)
 return mesh(name,pts,faces,roles,True)

def sweep(name,points,r,normal,role,n=4):
 points=[Vector(v) for v in points];normal=Vector(normal);pts=[]
 for i,point in enumerate(points):
  axis=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized();a=(normal-axis*normal.dot(axis)).normalized();b=axis.cross(a)
  for j in range(n):t=j*math.tau/n;pts.append(point+r*(math.cos(t)*a+math.sin(t)*b))
 faces=[(i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j) for i in range(len(points)-1) for j in range(n)]
 faces += [tuple(reversed(range(n))),tuple(range((len(points)-1)*n,len(points)*n))]
 return mesh(name,pts,faces,role,True)

def lifebuoy():
 for x in [-.24,.24]:box('Low stabilising foot',(x,.045,0),(.18,.09,.50),'metal',.015)
 rod('Lifebuoy upright',(0,.04,0),(0,1.61,0),.045,'metal',8)
 box('Ring mounting crossbar',(0,1.38,0),(.47,.065,.065),'metal',.012)
 torus('Cream lifebuoy and four red bands',(0,1.13,.09),.27,.27,.075,(0,0,1),'cream',16,6,True)
 torus('Small suspension hook',(0,1.48,.06),.048,.065,.012,(0,0,1),'metal',8,4)
 return {'front':'+Z','lifebuoy_outer_diameter_m':.69,'content':'Static stand, no lettering'}

def rope_flat():
 points=[]
 for i in range(51):
  t=i/50;a=t*math.tau*2.75;radius=.075+.225*t;points.append((radius*math.cos(a),.028,radius*math.sin(a)))
 points.extend([(.10,.028,-.34),(.22,.028,-.34),(.33,.028,-.28)])
 sweep('One continuous flat rope coil',points,.028,(0,1,0),'rope',4)
 return {'content':'Flat2.75-turn coil with quiet loose end'}

def rope_bound():
 for z in [-.052,0,.052]:torus('Upright oval rope loop',(0,.24,z),.30,.20,.025,(0,0,1),'rope',16,4)
 # One binding around the right side gathers the three layers.
 normal=(1,0,0);pts=[(.29,.24+.055*math.cos(i*math.tau/10),.12*math.sin(i*math.tau/10)) for i in range(11)]
 sweep('Binding on rope bundle',pts,.013,normal,'rope_dark',4)
 return {'content':'Bound upright oval bundle; place against cargo or on crate'}

def crate_closed():
 box('Closed crate dark seams',(0,.41,0),(.84,.82,.84),'wood_dark')
 for x in [-.38,.38]:
  for z in [-.38,.38]:box('Crate corner strip',(x,.425,z),(.075,.85,.075),'wood_light',.008)
 for side in [-1,1]:
  for j in range(4):
   box('Crate front/back board',(0,.13+j*.19,side*.428),(.70,.174,.025),'wood' if j%2==0 else 'wood_light')
   box('Crate side board',(side*.428,.13+j*.19,0),(.025,.174,.70),'wood' if j%2 else 'wood_light')
 for j in range(4):box('Closed lid plank',((j-1.5)*.19,.8375,0),(.18,.025,.70),'wood' if j%2 else 'wood_light')
 for sign in [-1,1]:
  ob=box('Front diagonal crate brace',(0,.425,.452),(1.0,.065,.025),'wood_dark',.008);ob.rotation_euler.y=sign*math.radians(43)
 return {'lid':'closed','stack_top_y_m':.85}

def crate_open():
 for j in range(4):box('Open crate floor plank',((j-1.5)*.29,.035,0),(.28,.07,.78),'wood')
 for x in [-.55,.55]:
  for z in [-.35,.35]:box('Open crate corner',(x,.25,z),(.085,.50,.085),'wood_light',.008)
 for y in [.15,.29,.43]:
  for z in [-.365,.365]:box('Open crate long side slat',(0,y,z),(1.02,.10,.045),'wood')
  for x in [-.565,.565]:
   if y<.4:box('Open crate end slat',(x,y,0),(.045,.10,.64),'wood')
   else:
    for z in [-.23,.23]:box('End slat around handhold',(x,y,z),(.045,.10,.18),'wood')
 for z in [-.365,.365]:box('Open crate top rim',(0,.495,z),(1.18,.05,.065),'wood_light',.008)
 for x in [-.565,.565]:box('Open crate end rim',(x,.495,0),(.065,.05,.79),'wood_light',.008)
 return {'lid':'open','content':'Empty cargo crate with open handholds'}

def barrel(open_top=False):
 n=12
 profile=[(0,.26),(.07,.285),(.20,.32),(.59,.32),(.73,.28),(.78,.255)]
 if open_top:profile=[(0,.31),(.08,.345),(.25,.39),(.70,.39),(.89,.35),(.95,.345),(.95,.295),(.85,.28),(.12,.26)]
 ob=lathe('Wooden stave barrel',profile,'wood',n)
 ob.data.materials.append(p.mat('wood_light'))
 for face in ob.data.polygons:
  if face.index%n in [2,7]:face.material_index=1
 for y,r in ([(.17,.325),(.63,.314)] if not open_top else [(.20,.388),(.76,.378)]):lathe('Dark iron barrel hoop',[(y-.025,r),(y+.025,r)],'metal',n)
 if not open_top:
  for z in [-.08,.08]:box('Quiet lid board seam',(0,.781,z),(.46,.004,.009),'wood_seam')
 else:lathe('Dark inner floor',[(.12,.255),(.122,.255)],'wood_dark',n)
 return {'lid':'open' if open_top else 'closed','content':'Wood staves and two dark hoops, no markings'}

def net_rack():
 for x in [-.68,.68]:
  box('Rack stable foot',(x,.05,0),(.18,.10,.55),'wood_dark',.014)
  box('Net rack upright',(x,.87,0),(.085,1.64,.085),'wood_dark',.012)
 box('Net hanging crossbeam',(0,1.70,0),(1.52,.10,.10),'wood_light',.014)
 # Clip both diagonal families into the same1.20x1.05m rectangle.
 for slope in [-1,1]:
  for c in [-1.0,-.75,-.50,-.25,0,.25,.50,.75,1.0]:
   intersections=[]
   for x in [-.60,.60]:
    y=slope*x+c
    if -.525<=y<=.525:intersections.append((x,y))
   for y in [-.525,.525]:
    x=(y-c)/slope
    if -.60<x<.60:intersections.append((x,y))
   if len(intersections)!=2:continue
   points=[]
   for i in range(3):
    t=i/2;x=intersections[0][0]*(1-t)+intersections[1][0]*t;y=intersections[0][1]*(1-t)+intersections[1][1]*t
    points.append((x,1.06+y-.07*(1-(x/.6)**2),.07))
   sweep('Diamond fishing net cord',points,.013,(0,0,1),'rope',4)
 for x in [-.475,.025,.525]:
  y=1.585-.07*(1-(x/.6)**2)
  rod('Net suspension cord',(x,y,.07),(x,1.70,0),.014,'rope_dark',4)
 return {'front':'+Z','content':'Open geometric diamond net, suspended at three upper knots; no alpha texture or fish'}

def beacon():
 box('Beacon stone mounting foot',(0,.08,0),(.32,.16,.32),'stone',.025)
 lathe('Small dark beacon pole',[(.16,.105),(.25,.085),(1.76,.055),(1.80,.10)],'metal',10)
 lathe('Warm beacon lantern',[(1.78,.13),(1.85,.16),(2.12,.16),(2.17,.12)],'lamp',8)
 for a in [0,math.pi/2,math.pi,math.pi*1.5]:rod('Lantern corner frame',(.16*math.cos(a),1.84,.16*math.sin(a)),(.16*math.cos(a),2.13,.16*math.sin(a)),.016,'metal',4)
 lathe('Beacon cap',[(2.13,.21),(2.18,.21),(2.28,.08),(2.30,0)],'roof',8)
 return {'content':'Static opaque warm lantern; no light/emission node','front':'+Z'}

BUILDERS=[('ticket_booth',ticket_booth),('waiting_shelter',waiting_shelter),('boarding_gangplank',gangplank),('lifebuoy_stand',lifebuoy),('rope_coil_flat',rope_flat),('rope_coil_bound',rope_bound),('wood_crate_closed',crate_closed),('wood_crate_open',crate_open),('wood_barrel_closed',lambda:barrel(False)),('wood_barrel_open',lambda:barrel(True)),('fishing_net_rack',net_rack),('beacon_pole',beacon)]

def main():
 KIT.mkdir(parents=True,exist_ok=True);only=sys.argv[sys.argv.index('--only')+1] if '--only' in sys.argv else None
 rows=json.loads((KIT/'manifest.json').read_text())['assets'] if only else {}
 for name,builder in BUILDERS:
  if only and name!=only:continue
  row=s.export(name,builder);row['source']=str((SRC/(name+'.blend')).relative_to(ROOT));rows[name]=row
  folder=SRC/'modules'/name;folder.mkdir(parents=True,exist_ok=True)
  (folder/'reuse_provenance.json').write_text(json.dumps({'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','task':'SGODOT-436','module':name,'geometry':'New editable geometry; existing assets untouched','palette':'#830 wood / Alcatraz cream and roof / street-kit dark metal','source':row['source'],'generator':'tools/art/source/dock_props_436/build.py'},ensure_ascii=False,indent=2)+'\n')
 m={'task':'SGODOT-436','revision':'v1','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','units':'metres; Y up; bottom-centre origin; +Z front except gangplank +X','palette_srgb':s.PAL,'assets':rows,'unique_triangles':sum(r['triangles'] for r in rows.values()),'unique_surfaces':len(rows),'scope':'Dock props only; ferry landing is review-only, no layout/game integration'}
 (KIT/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':main()
