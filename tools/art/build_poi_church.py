"""SGODOT-423 Grace Cathedral interior. Metres/Y-up, editable modular source."""
from pathlib import Path
import hashlib,json,math,random,sys
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/art'))
import scene_room_pipeline as p
from scene_room_pipeline import cube,cylinder,ellipsoid,lathe,tube,mesh
SRC=ROOT/'tools/art/source/poi_church';KIT=ROOT/'assets/rooms/poi_church'
F=.08;R=math.sqrt(.5);META={};ANCHORS=[]
PAL={'stone':'DCC6A7','stone_light':'EBD8BC','stone_edge':'C7AC87','stone_dark':'B39979',
 'floor':'D7BE9D','floor_light':'DEC7A9','floor_warm':'D3B38D','joint':'BDA383','maze':'B99A76',
 'wood':'BD874C','wood_light':'D5A363','wood_dark':'8D633D','gold':'D4AA5E','iron':'5D4C38',
 'cream':'F3E9D4','candle':'FFE5AB','leaf':'829260','leaf_light':'A3AF74','leaf_dark':'677A50',
 'terra':'B8825A','blue':'719ABF','blue_dark':'517995','coral':'D68F70','glass_gold':'E7BD68',
 'glass_cream':'F2DC9F','grass':'91A27C','vault':'75634F','vault_light':'978068','banner':'8F9FAD'}
def write(path,data):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def uv(u,v,y=F):return [(u+v)*R,y,(-u+v)*R]
def box(size,at=None,name=None):return {'size':size,'at':at or [0,size[1]/2,0],**({'name':name} if name else {})}
def begin(name,at=(0,0,0),yaw=0,colliders=None,material='opaque',vegetation=False,review=False):
 p.begin(name,at,yaw,colliders);META[name]={'material':material,'vegetation':vegetation,'review_only':review,'cast_shadow':material not in ['glass','light_patch'] and not vegetation}
def pointed(width,bottom,spring,top,steps=16):
 # Two quadratic segments retain the Gothic point instead of a semicircular arch.
 out=[(-width/2,bottom),(-width/2,spring)]
 for i in range(1,steps+1):
  t=i/steps;out.append((-width/2*(1-t*t),spring+(top-spring)*t))
 for i in range(1,steps+1):
  t=i/steps;out.append((width/2*(2*t-t*t),top-(top-spring)*t))
 return out+[(width/2,bottom)]
def solid(name,path,depth,z,color):
 n=len(path);vs=[(x,y,z+d) for d in [-depth/2,depth/2] for x,y in path]
 return mesh(name,vs,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],color)
def arch_rib(name,width,bottom,spring,top,z,color='stone_light',thick=.08):
 path=pointed(width,bottom,spring,top)
 tube(name,[(x,y,z) for x,y in path],thick,color,8)
def quatrefoil(at,size,color,plane='wall'):
 x,y,z=at
 for a in [0,math.pi/2,math.pi,math.pi*1.5]:
  c=(x+math.cos(a)*size*.24,y+math.sin(a)*size*.24,z)
  if plane=='floor':c=(x+math.cos(a)*size*.24,y,z+math.sin(a)*size*.24)
  o=cylinder('Four-leaf ornament',c,size*.25,.012,color,vertices=16)
  if plane=='wall':o.rotation_euler.x=math.pi/2
def floor_and_surround():
 begin('foundation',colliders=[box([10.5,.28,10.5],[0,-.06,0],'Floor')])
 cube('Cutaway stone foundation',(0,-.14,0),(10.8,.4,10.8),'stone_edge',.07)
 cube('Tile joint bed',(0,.005,0),(10.5,.07,10.5),'joint',0)
 for row in range(15):
  z=-5.25+(row+.5)*.7;x=-5.25;i=0
  while x<5.249:
   w=min(.525 if row%2 and i==0 else 1.05,5.25-x)
   cube('Stone tile %02d_%02d'%(row,i),(x+w/2,.065,z),(w-.012,.03,.688),['floor','floor_light','floor_warm','floor'][(row+i*3)%4],.004)
   x+=w;i+=1
 begin('outer_steps')
 for width,y,height in [(11.4,-.27,.16),(12.1,-.43,.16),(12.8,-.59,.16)]:
  for x in [-1,1]:cube('Exterior lateral stone step',(x*(width/2-.18),y,0),(.36,height,width),'stone',.025)
  for z in [-1,1]:cube('Exterior front back stone step',(0,y,z*(width/2-.18)),(width-.72,height,.36),'stone',.025)
 begin('grass_surround')
 cube('Low meadow surround',(0,-.76,0),(27,.18,27),'grass',.06)
 # The ground remains an authored extent, visible in overview; never a camera-facing background card.
 begin('entry_landing',[2.0,0,5.65],0,[box([1.5,.28,1.55],[0,-.06,0],'Landing')])
 cube('Continuous entry stone landing',(0,-.06,0),(1.5,.28,1.55),'stone_light',.03)
 begin('labyrinth',uv(0,4.15,F+.003),45)
 cylinder('Quiet circular limestone inset',(0,.002,0),1.34,.008,'floor_light',vertices=96)
 for j in range(7):
  radius=.27+j*.15
  gap=.12 if j%2==0 else .25;start=-math.pi/2+gap;end=3*math.pi/2-gap
  if j in [2,5]:start+=math.pi
  verts=[]
  for k in range(97):
   a=start+(end-start)*k/96
   for r in [radius-.025,radius+.025]:verts.append((r*math.cos(a),.009,r*math.sin(a)))
  mesh('Single-tone labyrinth course %d'%j,verts,[(2*i,2*i+1,2*i+3,2*i+2) for i in range(96)],'maze')
 quatrefoil((0,.011,0),.41,'maze','floor')
def wall_shell():
 for name,at,yaw in [('west_wall',[-5.25,F,0],90),('north_wall',[0,F,-5.25],0)]:
  begin(name,at,yaw,[box([10.7,8,.28],[0,4,0],name)])
  wall=cube('Warm limestone wall',(0,2.5,0),(10.7,5,.26),'stone',.015)
  for cx in [-1.9,1.15]:
   path=[(x+cx,y) for x,y in pointed(1.35,1.15,3.25,4.45)]
   p.boolean_cut(wall,solid('True pointed window opening',path,1,0,'stone'))
  for row in range(10):
   y=.25+row*.5
   # Subtle mortar strips, interrupted around actual window apertures.
   for a,b in [(-5.3,-2.64),(-1.16,.41),(1.89,5.3)]:
    cube('Quiet masonry horizontal joint',((a+b)/2,y,.139),(b-a,.012,.008),'stone_edge',0)
  cube('Stone skirting',(0,.18,.13),(10.7,.36,.26),'stone_light',.025)
  cube('Wall crown',(0,4.92,.08),(10.9,.20,.42),'stone_light',.04)
  # Tall upper fascia closes the fixed-view upper corners; it is not a roof over the camera.
  cube('Dark upper vault band',(0,6.48,-.015),(10.9,3.0,.30),'vault',.025)
  for x in [-5,-2.6,.45,3.0,5.0]:
   for y,r,h in [(.17,.25,.34),(.45,.19,.20),(2.64,.14,4.18),(4.80,.23,.25)]:
    cylinder('Rounded clustered stone pier',(x,y,.23),r,h,'stone_light',vertices=16)
   cube('Upper timber upright',(x,6.48,.18),(.18,2.98,.24),'wood_dark',.02)
  for cx in [-3.8,-.95,2.0,4.0]:
   arch_rib('Vault pointed rib',2.7,4.85,6.30,7.88,.22,'vault_light',.09)
   # Offset just-created rib to its masonry bay.
   p.b.CURRENT['objects'][-1].location.x=cx
  for y in [5.15,7.9]:cube('Continuous timber cornice',(0,y,.2),(10.9,.14,.24),'wood_dark',.025)
def window():
 begin('pointed_window',[-30,0,0],review=True,material='glass')
 solid('Geometric stained-glass backing',pointed(1.33,1.15,3.25,4.44),.03,0,'blue_dark')
 for col in range(4):
  for row in range(5):
   cube('Large geometric glass block',(-.49+col*.326,1.36+row*.36,.027),(.308,.34,.012),['coral','glass_gold','blue','glass_cream'][(row+2*col)%4],.001)
 for cx in [-.32,0,.32]:
  ellipsoid('Floral glass petal',(cx,3.55-abs(cx)*.7,.035),(.25,.65,.018),'glass_gold' if cx==0 else 'blue',16,6)
 for y in [1.15,1.55,1.91,2.27,2.63,2.99,3.25]:cube('Fine dark lead came',(0,y,.04),(1.34,.018,.018),'iron',0)
 for x in [-.66,-.33,0,.33,.66]:cube('Vertical lead came',(x,2.2,.04),(.018,2.1,.018),'iron',0)
 for i in range(8):
  a=math.tau*i/8;cx=math.cos(a)*.27;cy=2.82+math.sin(a)*.27
  ellipsoid('Small floral glass rosette petal',(cx,cy,.065),(.20,.20,.018),'glass_gold' if i%2 else 'coral',12,6)
  tube('Rosette lead outline',[(cx+.104*math.cos(math.tau*j/16),cy+.104*math.sin(math.tau*j/16),.08) for j in range(17)],.012,'iron',5)
 ellipsoid('Glass flower centre',(0,2.82,.075),(.29,.29,.02),'glass_cream',16,6)
 begin('window_surround',[-30,0,0],review=True)
 arch_rib('Gothic moulding',1.42,1.11,3.25,4.51,.09,'stone_light',.10)
 arch_rib('Inner fine window fillet',1.32,1.15,3.25,4.44,.10,'stone_edge',.025)
 cube('Deep sloping sill',(0,1.07,.14),(1.63,.16,.47),'stone_light',.025)
 for side,at,yaw in [('w',[-5.08,F,0],90),('n',[0,F,-5.08],0)]:
  for i,c in enumerate([-1.9,1.15]):
   pos=[at[0],at[1],-c] if side=='w' else [c,at[1],at[2]]
   p.instance('pointed_window',f'{side}_glass_{i+1}',pos,yaw)
   p.instance('window_surround',f'{side}_window_{i+1}',pos,yaw)
def altar():
 begin('sanctuary_steps',uv(0,-4.45,0),45,[box([4.55,.54,2.8],[0,.27,-.05],'AltarSteps')])
 for j in range(3):
  width=4.8-j*.42;depth=3.1-j*.32
  poly=[(-width/2,-depth/2),(-width/2,depth*.25),(-width*.37,depth/2),(width*.37,depth/2),(width/2,depth*.25),(width/2,-depth/2)]
  vs=[(x,y,z) for y in [j*.18,(j+1)*.18] for x,z in poly];n=6
  mesh('Three broad sanctuary risers',vs,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],'stone_light' if j%2==0 else 'stone')
 begin('altar_table',uv(0,-4.5,.54),45,[box([1.9,1.12,.85])])
 for x in [-.8,.8]:cube('Altar rounded timber leg',(x,.50,0),(.18,1,.6),'wood',.025)
 cube('Altar table top',(0,1.06,0),(1.95,.12,.85),'wood_light',.035)
 # Cloth has a visible folded drop and a four-leaf medallion, never a cross.
 mesh('Ivory linen folded cloth',[(-1.01,.68,.46),(1.01,.68,.46),(-1.01,1.13,.43),(1.01,1.13,.43),(-1.01,1.13,-.45),(1.01,1.13,-.45)],[(0,1,3,2),(2,3,5,4)],'cream','cloth')
 cube('Cream frontal runner',(0,.88,.475),(.45,.50,.014),'cream',.008)
 quatrefoil((0,.9,.487),.22,'gold')
 for x in [-.78,-.53,.53,.78]:
  lathe('Brass candle foot',(x,1.13,.1),[(0,.055),(.02,.06),(.04,.035),(.18,.018)],'gold',12)
  cylinder('Ivory tall candle',(x,1.48,.1),.028,.34,'cream',vertices=12)
  ellipsoid('Small candle flame',(x,1.68,.1),(.024,.07,.024),'candle',8,4)
 begin('apse',uv(0,-5.75,F),45)
 cube('Faceted sanctuary back wall',(0,2.45,-.03),(3.8,4.9,.20),'stone',.02)
 for x in [-1.2,0,1.2]:
  path=pointed(1.08,.65,2.25,3.05)
  tube('Blind pointed sanctuary arch',[(a+x,b,.13) for a,b in path],.045,'stone_light',8)
 begin('rose_window',uv(0,-5.60,4.12),45,material='glass')
 # Centered on the sanctuary rather than a large flat back-wall colour patch.
 o=cylinder('Rose backing',(0,0,0),.91,.04,'blue_dark',vertices=64);o.rotation_euler.x=math.pi/2
 for i in range(12):
  a=math.tau*i/12
  pts=[]
  for j in range(17):
   t=math.tau*j/16;rad=.53+.30*math.cos(t);ang=a+.15*math.sin(t)
   pts.append((rad*math.cos(ang),rad*math.sin(ang),.035))
  mesh('Rose floral petal',pts,[tuple(range(len(pts)-1))],['coral','glass_gold','blue'][i%3])
  tube('Rose tracery petal outline',pts,.021,'stone_light',6)
 tube('Round rose stone surround',[(.94*math.cos(math.tau*i/64),.94*math.sin(math.tau*i/64),.035) for i in range(65)],.09,'stone_light',10)
 quatrefoil((0,0,.065),.3,'glass_cream')
def pews():
 begin('wood_pew',[-30,0,0],review=True,colliders=[box([2.60,1.18,.65],[0,.59,0])])
 cube('Broad pew seat',(0,.67,.015),(2.60,.09,.59),'wood_light',.025,'wood')
 cube('Pew back panel',(0,.97,.285),(2.5,.55,.09),'wood',.025,'wood')
 cube('Rounded pew top rail',(0,1.255,.285),(2.58,.09,.12),'wood_light',.035,'wood')
 for x in [-1.27,1.27]:
  cube('Pew rounded end',(x,.59,0),(.12,1.18,.65),'wood',.045,'wood')
  ellipsoid('Pew soft end cap',(x,1.16,0),(.12,.34,.65),'wood_light',12,6)
  quatrefoil((x,.99,.337),.15,'wood_dark')
 for x in [-.85,.85]:
  for z in [-.22,.22]:cube('Pew grounded feet',(x,.30,z),(.12,.6,.12),'wood_dark',.015,'wood')
 for side,u in [('left',-2.10),('right',2.10)]:
  for i,v in enumerate([-1.85,-.35,1.15,2.65]):
   name=f'pew_{side}_{i+1}';at=uv(u,v)
   p.instance('wood_pew',name,at,45)
   # One near-aisle seat in each row; all eight are reachable from the central aisle.
   su=u+(1 if u<0 else -1)*.85
   ANCHORS.append({'name':f'seat_{side}_{i+1}','position':uv(su,v-.02,F+.715),'yaw_degrees':45,'module':name,'approach':uv(su,v-.67)})
def organ_and_banners():
 begin('pipe_organ',[-4.5,F,1.75],90,[box([1.55,1.1,.65],[0,.55,.15])])
 cube('Small organ oak cabinet',(0,.5,.04),(1.6,1,.68),'wood',.04,'wood')
 cube('Organ sloped keyboard ledge',(0,.99,.43),(1.6,.12,.33),'wood_light',.015,'wood')
 for i in range(24):cube('Ivory organ key',(-.70+i*.06,1.06,.43),(.056,.025,.25),'cream',.003)
 for i in range(17):
  x=-.72+i*.09;h=1.0+1.05*(1-abs(x)/.78)
  cylinder('Soft silver organ pipe',(x,1.1+h/2,-.08),.036,h,'stone_light',vertices=10)
  cube('Pipe mouth',(x,1.26,-.035),(.035,.10,.01),'gold',.002)
 begin('hanging_banner',[-30,0,0],review=True,material='cloth')
 mesh('Plain hanging fabric',[(-.30,0,0),(.30,0,0),(.30,-1.55,0),(0,-1.42,0),(-.30,-1.55,0)],[(0,1,2,3,4)],'banner','cloth')
 for x in [-.3,.3]:tube('Gold stitched vertical border',[(x,0,.012),(x,-1.55,.012)],.012,'gold',6)
 tube('Banner top rail',[(-.43,.06,0),(.43,.06,0)],.035,'gold',8)
 quatrefoil((0,-.65,.018),.22,'gold')
 p.instance('hanging_banner','west_banner',[-4.98,3.9,2.85],90)
 p.instance('hanging_banner','north_banner',[3.05,3.9,-4.98],0)
def lights_and_plants():
 begin('iron_chandelier',[-30,0,0],review=True,material='opaque')
 tube('Iron circular chandelier hoop',[(.48*math.cos(math.tau*i/32),0,.48*math.sin(math.tau*i/32)) for i in range(33)],.035,'iron',8)
 for i in range(6):
  a=math.tau*i/6;x=.48*math.cos(a);z=.48*math.sin(a)
  tube('Chandelier candle arm',[(x,0,z),(x*1.15,.10,z*1.15)],.025,'iron',6)
  cylinder('Chandelier candle',(x*1.15,.23,z*1.15),.055,.25,'candle',vertices=12)
 for i in range(3):
  a=math.tau*i/3;tube('Suspension chain',[(.42*math.cos(a),.03,.42*math.sin(a)),(0,1.15,0),(0,1.8,0)],.018,'iron',6)
 for side,u in [('left',-2.9),('right',2.9)]:p.instance('iron_chandelier','chandelier_'+side,uv(u,-2.35,4.0),0)
 begin('flower_pedestal',[-30,0,0],review=True,vegetation=True)
 cube('Floral pedestal foot',(0,.08,0),(.58,.16,.58),'stone_light',.025)
 cylinder('Floral pedestal stem',(0,.58,0),.16,.95,'stone',vertices=12)
 cube('Floral pedestal cap',(0,1.07,0),(.47,.14,.47),'stone_light',.025)
 lathe('Ceramic flower bowl',(0,1.14,0),[(0,.13),(.05,.23),(.30,.26)],'terra',16)
 rng=random.Random(423)
 for i in range(19):
  a=i*2.399;rad=.28*math.sqrt(i/19);end=(math.cos(a)*rad,1.63+rng.random()*.24,math.sin(a)*rad)
  tube('Bouquet stem',[(0,1.35,0),end],.007,'leaf_dark',5)
  for j in range(5):
   b=j*math.tau/5;ellipsoid('Cream flower petal',(end[0]+math.cos(b)*.065,end[1],end[2]+math.sin(b)*.065),(.10,.055,.10),'cream',8,4)
  ellipsoid('Flower warm centre',end,(.06,.06,.06),'glass_gold',8,4)
  ellipsoid('Bouquet oval leaf',(end[0]*.8,end[1]-.20,end[2]*.8),(.16,.08,.24),'leaf',8,4)
 for side,u in [('left',-1.65),('right',1.65)]:p.instance('flower_pedestal','flowers_'+side,uv(u,-4.55,.54),45)
 begin('leaf_planter',[-30,0,0],review=True,vegetation=True,colliders=[{'shape':'cylinder','radius':.38,'height':.8,'at':[0,.4,0]}])
 lathe('Rounded terracotta planter',(0,0,0),[(0,.22),(.05,.29),(.52,.36),(.58,.34),(.58,.29),(.47,.28)],'terra',20)
 cylinder('Planter dark soil',(0,.52,0),.29,.025,'wood_dark',vertices=20)
 for i in range(15):
  a=i*2.399;h=.75+(i%4)*.18;end=(math.cos(a)*.35,h,math.sin(a)*.35)
  tube('Leaf petiole',[(0,.52,0),end],.009,'leaf_dark',5)
  ellipsoid('Rounded olive leaf',end,(.24,.10,.40),'leaf_light' if i%3==0 else 'leaf',10,4)
 p.instance('leaf_planter','west_planter',[-4.3,F,3.7])
 p.instance('leaf_planter','north_planter',[3.55,F,-4.3])
def light_patches():
 begin('stained_light',material='light_patch')
 # Broad baked-look patches in two loose clusters, kept off the main labyrinth.
 for side in [-1,1]:
  for i in range(8):
   u=side*(3.4-(i%2)*.62);v=-2.5+(i//2)*.70
   pts=[uv(u+du,v+dv,F+.007) for du,dv in [(-.26,-.20),(.32,-.27),(.25,.22),(-.31,.28)]]
   mesh('Broad quiet coloured floor light',pts,[(0,1,2,3)],['blue','glass_gold','coral','blue'][i%4])
def finish():
 # Entry lies in the front edge's left part on screen (u<0), clear of pew ends.
 ANCHORS.extend([{'name':'spawn','position':uv(-1.8,4.15),'yaw_degrees':45},
  {'name':'exit','position':[2.0,F,5.85],'yaw_degrees':180},
  {'name':'badge_exit','position':[2.0,1.12,5.85],'yaw_degrees':180,'label':'Map','icon':'i-door'},
  {'name':'cam_default','position':[0,1.4,0],'yaw_degrees':45,'pitch_degrees':43,'width_m':6.72,'fixed':True}])
 # Bound the open diorama front, with a 1.5m opening to the landing.
 gapx=2.0
 boundaries=[box([.12,3,10.5],[5.2,1.58,0],'EastBoundary'),
  box([gapx-.75+5.25,3,.12],[(-5.25+gapx-.75)/2,1.58,5.20],'FrontLeftBoundary'),
  box([5.25-gapx-.75,3,.12],[(5.25+gapx+.75)/2,1.58,5.20],'FrontRightBoundary')]
 # Landing uses its own rotated colliders to enclose the outer end and sides.
 land=p.KITS['entry_landing']['collision']
 land.extend([box([.10,3,1.55],[-.75,1.58,0],'LandingLeft'),box([.10,3,1.55],[.75,1.58,0],'LandingRight'),box([1.5,3,.10],[0,1.58,.77],'LandingEnd')])
 routes=[{'name':'entry_to_aisle','points_xz':[[x,z] for x,y,z in [[2.0,F,5.85],[2.0,F,4.7],uv(-1.8,4.15),uv(0,4.15),uv(0,-2.6)]]}]
 for a in ANCHORS:
  if a['name'].startswith('seat_'):
   u=(a['approach'][0]-a['approach'][2])*R;v=(a['approach'][0]+a['approach'][2])*R
   routes.append({'name':'approach_'+a['name'],'points_xz':[[x,z] for x,y,z in [uv(0,v),uv(u,v)]]})
 local=[{'position':uv(u,-2.35,4.08),'color':'FFDC9C','energy':.65,'range':4.0} for u in [-2.9,2.9]]
 focus=[0,1.4,0];pitch=math.radians(43);direction=[R*math.cos(pitch),math.sin(pitch),R*math.cos(pitch)]
 p.MANIFEST_EXTRA.update({'anchors':ANCHORS,'spawn':uv(-1.8,4.15),'floor_y':F,'footprint_m':[10.5,10.5],
  'boundaries':boundaries,'local_lights':local,'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
  'preflight':{'routes':routes,'main_routes':routes[:1],'standing_positions_xz':[[x,z] for x,y,z in [uv(0,3.9),uv(0,0),uv(0,-2.6)]]},
  'light_patch_alpha':.28,'maze_contrast':'one darker limestone tone, no saturated colour',
  'camera_contract':{'fixed':True,'width_m':6.72,'pitch_degrees':43},'revision':'v1'})
 p.finalize({'position':[focus[i]+direction[i]*22 for i in range(3)],'target':focus,'size':6.72},
  {'background':'DDE8E7','ambient_color':'FFF0DC','ambient':.65,'sun_color':'FFF1D8','sun':1.0,'sun_position':[-6,9,3],'sun_target':[0,0,0],'points':[],'shadow_bias':.05,'shadow_normal_bias':.25})
 layout=json.loads((KIT/'layout.json').read_text())
 for spec in layout['assets']:
  spec.update(META[spec['name']]);spec['provenance']=f'tools/art/source/poi_church/modules/{spec["name"]}/reuse_provenance.json'
 write(KIT/'layout.json',layout)
 write(SRC/'reuse_provenance.json',{'author':'黄忠','kind':'new authored geometry using shared Basic Room modelling primitives','reference':'church_concept_v1.jpg / c_church.png approved SGODOT-423','reference_sha256':hashlib.sha256((SRC/'reference/c_church.png').read_bytes()).hexdigest(),'modules':list(META),'script':'tools/art/build_poi_church.py'})
 for spec in layout['assets']:
  write(ROOT/spec['provenance'],{'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','module':spec['name'],'kind':'new authored geometry','reference':'SGODOT-423 approved c_church.png','script':'tools/art/build_poi_church.py','units':'metres; Y-up; +Z front','changes':'Shared Basic Room modelling primitives; no legacy asset geometry copied.'})
 if '--geometry-only' not in sys.argv:p.bake_and_export()
def main():
 p.start('poi_church','SGODOT-423 / approved Grace Cathedral concept v1')
 p.b.PALETTE.update(PAL);p.BAKE_SETTINGS.update(ao_strength=.16,floor_ao_strength=.05,ao_distance=.28)
 floor_and_surround();wall_shell();window();altar();pews();organ_and_banners();lights_and_plants();light_patches();finish()
if __name__=='__main__':main()
