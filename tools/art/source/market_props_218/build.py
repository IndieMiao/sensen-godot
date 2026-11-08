"""SGODOT-218 market props. Run with flock ~/gs66-render.lock blender -b --python ...
Metres, Godot Y up / +Z front. --stage blockout or final; never writes scene layout.
"""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,sys,importlib.util
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/rooms/market_plaza'
spec=importlib.util.spec_from_file_location('primitives',SRC.parent/'alcatraz_far_424/build.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
PAL={'wood':'A3815D','wood_light':'B89972','wood_dark':'795F47','seam':'685640','metal':'5D4C38','sage':'91A680','sage_dark':'738D67','teal':'83AFB1','mint':'A3BFA4','yellow':'E4C887','canvas':'F1E8D5','canvas_shade':'DED4BF','stone':'DDC9A8','stone_light':'EEE0C6','stone_dark':'C0AA88','water':'7CBAC6','foam':'D4EAE2','leaf':'85A163','leaf_dark':'628650','leaf_light':'A4B36E','tomato':'CC8466','carrot':'D5A35F','pear':'BEC977','fish':'B2C5CD','fish_dark':'6D939D','bread':'CEA56E','bread_light':'E6CB99','spice':'B6976C','lavender':'B5ACCC','flower_cream':'F0DDA3','soil':'8C7762','pot':'BA9776','paper':'F4EBD5','lamp':'F1D89D','whitebox':'D8D5CC'}
box=p.box;mesh=p.mesh;rod=p.rod;lathe=p.lathe
STAGE=sys.argv[sys.argv.index('--stage')+1] if '--stage' in sys.argv else 'final'
LIMITS={'stall_keeper':2500,'stall_veg':1500,'stall_fish':1500,'stall_bakery':1500,'stall_spice':1500,'stall_tools':1500,'flower_cart':1500,'market_board':600,'fountain':2000,'produce_crate':300,'basket':300,'flower_tub':300}
BOUNDS={'stall_keeper':[3.2,3.10,1.6],**{n:[2,2.55,1.6] for n in LIMITS if n.startswith('stall_') and n!='stall_keeper'},'flower_cart':[2,2.35,1.4],'market_board':[1.2,1.8,.3],'fountain':[3,2.12,3],'produce_crate':[.62,.43,.44],'basket':[.46,.56,.46],'flower_tub':[.68,.86,.68]}
def start(name):
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.context.preferences.filepaths.save_version=0
 p.PARTS=[];p.MATS={};p.PAL=PAL if STAGE=='final' else {k:PAL['whitebox'] for k in PAL}
 p.PIVOT=bpy.data.objects.new(name+' / floor centre',None);bpy.context.scene.collection.objects.link(p.PIVOT)
 p.PIVOT['author']='黄忠';p.PIVOT['stage']=STAGE

def ico(name,at,scale,role):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=p.v(at));o=bpy.context.object;o.name=name;o.parent=p.PIVOT;o.scale=(scale[0],scale[2],scale[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for f in o.data.polygons:f.use_smooth=True
 o.data.materials.append(p.mat(role));p.PARTS.append(o);return o

def tube(name,points,r,role,n=5):
 pts=[Vector(x) for x in points];verts=[]
 for i,c in enumerate(pts):
  axis=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized();a=axis.cross(Vector((1,0,0)))
  if a.length<.01:a=axis.cross(Vector((0,0,1)))
  a.normalize();b=axis.cross(a).normalized();verts.extend(c+r*(math.cos(j*math.tau/n)*a+math.sin(j*math.tau/n)*b) for j in range(n))
 faces=[]
 for i in range(len(pts)-1):
  for j in range(n):faces.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
 faces += [tuple(reversed(range(n))),tuple(range((len(pts)-1)*n,len(pts)*n))]
 return mesh(name,verts,faces,role,True)

def canopy(w,d,top,color,stripes=6):
 # Each stripe is an actual closed thin prism: visible underside and capped side ends.
 edge=top-.27
 profile=[(-d/2,edge),(-d*.26,top-.09),(0,top),(d*.26,top-.09),(d/2,edge)]
 if STAGE=='final':profile=[(-d/2,edge),(0,top),(d/2,edge)]
 outline=[(z,y) for z,y in profile]+[(z,y-.035) for z,y in reversed(profile)]
 for j in range(stripes):
  a=-w/2+j*w/stripes;b=a+w/stripes;role=color if j%2==0 else 'canvas';n=len(outline)
  vs=[(x,y,z) for x in [a,b] for z,y in outline]
  faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
  mesh('Closed striped canopy panel %02d'%j,vs,faces,role)
  # Broad rounded scallop at both ends, genuine cloth thickness.
  segments=4 if STAGE=='final' else 6
  outline2=[(a,edge-.02),(b,edge-.02)]+[(b-(b-a)*t/segments,edge-.105-.105*math.sin(math.pi*t/segments)) for t in range(segments+1)]
  for front in [-1,1]:
   n2=len(outline2);z=front*(d/2-.016)
   vs=[(x,y,z+dz) for dz in [-.016,.016] for x,y in outline2]
   faces=[tuple(reversed(range(n2))),tuple(range(n2,2*n2))]+[(i,(i+1)%n2,(i+1)%n2+n2,i+n2) for i in range(n2)]
   mesh('Scalloped front valance' if front>0 else 'Scalloped back valance',vs,faces,role)
 # Soft warm wood underside spars; no open paper planes.
 for z in [-d/2+.09,d/2-.09]:box('Under-canopy crossbar',(0,edge-.07,z),(w-.16,.08,.07),'wood_dark')


def keeper_canopy(w,d):
 # v1.1 option A: front-high sloping fabric roof, closed 35mm thick panels.
 # World camera looks along local +Z at33deg. Front scallops stay above head rays.
 back_top=2.60;front_top=3.10
 def roof_y(z):return back_top+(z+d/2)/d*(front_top-back_top)
 for j in range(8):
  a=-w/2+j*w/8;b=a+w/8;role='sage' if j%2==0 else 'canvas'
  outline=[(-d/2,back_top),(d/2,front_top),(d/2,front_top-.035),(-d/2,back_top-.035)]
  n=len(outline);vs=[(x,y,z) for x in [a,b] for z,y in outline]
  mesh('Keeper closed rising canopy stripe %02d'%j,vs,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],role)
  for front in [-1,1]:
   edge=front_top if front>0 else back_top
   profile=[(a,edge-.02),(b,edge-.02)]+[(b-(b-a)*t/6,edge-.09-.09*math.sin(math.pi*t/6)) for t in range(7)]
   n=len(profile);z=front*(d/2-.016)
   vs=[(x,y,z+dz) for dz in [-.016,.016] for x,y in profile]
   mesh('Keeper front scallop' if front>0 else 'Keeper back scallop',vs,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],role)
 for z in [-.69,.69]:
  y=roof_y(z)-.095
  box('Keeper sloped roof crossbar',(0,y,z),(w-.16,.08,.07),'wood_dark')
  for x in [-w/2+.10,w/2-.10]:
   top=roof_y(z)-.05
   box('Keeper high front upright' if z>0 else 'Keeper low rear upright',(x,top/2,z),(.10,top,.10),'wood',.012)

def tray(x,z,y,w=.50,d=.42):
 box('Inset produce tray',(x,y,z),(w,.055,d),'wood_dark')
 for xx in [-1,1]:box('Tray side',(x+xx*(w/2-.015),y+.065,z),(.03,.13,d),'wood_light')
 for zz in [-1,1]:box('Tray end',(x,y+.065,z+zz*(d/2-.015)),(w-.06,.13,.03),'wood')

def small_fruit(x,y,z,kind,i=0):
 if kind=='carrot':
  lathe('Short bunch carrot',[(0,.015),(.17,.045),(.21,.035)],'carrot',5,(x,y-.03,z))
  mesh('Carrot leaf fan',[(x-.07,y+.16,z),(x,y+.32,z),(x+.07,y+.16,z),(x,y+.21,z+.05)],[(0,1,3),(1,2,3),(2,0,3),(0,2,1)],'leaf_dark')
 else:ico('Round market produce',(x,y,z),(.075,.085,.075),kind)

def produce(x,z,y,kind='pear',count=6):
 for i in range(count):small_fruit(x+(i%3-1)*.135,y+(i//6)*.1,z+(i//3%2-.5)*.14,kind,i)

def lantern(x,z,y):
 lathe('Warm hanging lantern',[(0,.075),(.025,.10),(.18,.09),(.205,.055)],'lamp',6,(x,y,z))
 lathe('Lantern cap',[(.185,.11),(.22,.105),(.25,.045)],'metal',6,(x,y,z))
 lathe('Lantern foot',[(0,.095),(.025,.10)],'metal',6,(x,y,z))
 for dx in [-.075,.075]:rod('Lantern frame',(x+dx,y+.015,z),(x+dx,y+.19,z),.009,'metal',4)
 rod('Short lantern drop',(x,y+.25,z),(x,y+.42,z),.012,'metal',5)

def stall(name):
 keeper=name=='stall_keeper';w,h,d=BOUNDS[name]
 if keeper and STAGE=='blockout':h=2.85
 if keeper and STAGE=='final':keeper_canopy(w,d)
 else:
  canopy(w,d,2.85 if keeper else h,{'stall_keeper':'sage','stall_veg':'sage','stall_fish':'teal','stall_bakery':'yellow','stall_spice':'mint','stall_tools':'teal'}[name],8 if keeper else 6)
  for x in [-w/2+.10,w/2-.10]:
   for z in [-.69,.69]:box('Rounded timber canopy upright',(x,(h-.29)/2,z),(.10,h-.29,.10),'wood',.012)
 # Counter rear face z=.06; reserved Mei standing rectangle z=-.76..+.04 (0.80m).
 deck_y=1.05;counter_w=w-.24
 box('Solid cabinet',(0,.50,.38),(counter_w,.86,.64),'wood_dark',.015)
 box('Thick rounded countertop',(0,1.015,.38),(counter_w+.06,.07,.68),'wood_light',.012)
 box('Lower cabinet plinth',(0,.09,.38),(counter_w+.04,.12,.66),'wood',.01)
 for j in range(9 if keeper else 5):
  n=9 if keeper else 5;xx=(j-(n-1)/2)*(counter_w/n)
  box('Front vertical timber board %02d'%j,(xx,.51,.709),(counter_w/n-.012,.76,.018),'sage_dark' if keeper else ['wood','wood_light','wood'][j%3])
 # Back panel is modeled, inset front cabinet never occupies the rear work lane.
 box('Cabinet back panel',(0,.52,.054),(counter_w-.08,.74,.014),'wood')
 for x in [-counter_w/2,counter_w/2]:box('Cabinet side panel',(x,.52,.38),(.018,.74,.60),'wood')
 if STAGE=='blockout':return {'counter_height_m':deck_y,'keeper_clearance_local_m':{'min':[-1.40,0,-.76],'max':[1.40,1.85,.04]} if keeper else None}
 # Every stall carries distinct real merchandise. No text, price marks or pictograms.
 if name in ['stall_keeper','stall_veg']:
  locations=[-.97,-.32,.32,.97] if keeper else [-.53,0,.53]
  for j,x in enumerate(locations):
   tray(x,.39,1.09,.56 if keeper else .50,.44)
   produce(x,.39,1.22,['tomato','pear','carrot','leaf_light'][j%4],6)
  if keeper:
   for x in [-1.37,1.37]:lantern(x,.69,2.55)
   # Small side foliage, kept behind/front posts and outside Mei's central stand area.
   for x in [-1.40,1.40]:
    for k in range(4):ico('Trimmed climbing market foliage',(x,1.15+k*.21,-.61),(.11,.14,.105),'leaf' if k%2 else 'leaf_light')
 elif name=='stall_fish':
  tray(0,.36,1.09,1.55,.47)
  for i in range(4):
   x=-.54+i*.35;z=.37+(i%2)*.03
   body=ico('Whole fish on pale tray',(x,1.21,z),(.095,.06,.22),'fish');
   mesh('Fish forked tail',[(x,1.22,z-.15),(x-.095,1.21,z-.31),(x,1.21,z-.27),(x+.095,1.21,z-.31),(x,1.25,z-.19)],[(0,1,2),(0,2,3),(0,4,1),(0,3,4),(1,4,2),(2,4,3)],'fish_dark')
   box('Quiet fish side stripe',(x,1.257,z),(.028,.012,.23),'fish_dark')
 elif name=='stall_bakery':
  for x in [-.53,0,.53]:tray(x,.37,1.09,.49,.45)
  for i in range(6):
   x=-.66+(i%3)*.53;z=.26+i//3*.20
   o=ico('Golden oval bread loaf',(x+.10,1.22,z),(.16,.10,.09),'bread' if i%2 else 'bread_light')
   for k in [-.05,.05]:box('Bread baked score',(x+.10+k,1.306,z),(.017,.008,.09),'bread_light')
 elif name=='stall_spice':
  for j,x in enumerate([-.56,0,.56]):
   lathe('Open spice crock',[(0,.12),(.025,.16),(.24,.18),(.29,.17),(.29,.13),(.22,.12)],'pot',8,(x,1.05,.38))
   lathe('Broad spice mound',[(0,.125),(.06,.08),(.085,0)],['spice','sage_dark','carrot'][j],8,(x,1.285,.38))
 elif name=='stall_tools':
  box('Back rail for tools',(0,1.73,-.68),(1.70,.09,.065),'wood_dark')
  for j,x in enumerate([-.60,-.20,.20,.60]):
   rod('Tool wooden handle',(x,1.22,-.61),(x,1.68,-.61),.024,'wood_light',6)
   if j in [0,3]:box('Broad hoe blade',(x,1.23,-.58),(.19,.12,.045),'metal',.01)
   else:
    for dx in [-.065,0,.065]:rod('Rounded fork tine',(x+dx,1.18,-.60),(x+dx,1.37,-.60),.014,'metal',5)
    box('Fork bridge',(x,1.37,-.60),(.16,.025,.035),'metal')
  tray(-.40,.38,1.09,.6,.42)
  for i in range(3):box('Small folded tool roll',(-.57+i*.16,1.21,.37),(.11,.11,.30),'sage')
  lathe('Small watering can',[(0,.15),(.22,.15),(.24,.10)],'teal',8,(.5,1.06,.38))
  rod('Watering can spout',(.60,1.12,.38),(.80,1.32,.38),.035,'teal',6)
 return {'counter_height_m':deck_y,'keeper_clearance_local_m':{'min':[-1.30,0,-.76],'max':[1.30,1.85,.04]} if keeper else None,'canopy_complete_underside':True}

def bloom(at,r=.10,role='flower_cream'):
 x,y,z=at
 for i in range(5):
  a=i*math.tau/5
  mesh('Five petal flower',[(x,y,z),(x+r*math.cos(a-.33),y+.018,z+r*math.sin(a-.33)),(x+r*1.2*math.cos(a),y,z+r*1.2*math.sin(a)),(x+r*math.cos(a+.33),y+.018,z+r*math.sin(a+.33)),(x,y-.012,z)],[(0,1,2),(0,2,3),(4,2,1),(4,3,2),(0,4,1),(0,3,4)],role)
 lathe('Flower warm centre',[(0,.025),(.016,0)],'yellow',5,(x,y+.015,z))

def flower_cart():
 canopy(2,1.4,2.35,'mint',6)
 for x in [-.85,.85]:
  for z in [-.56,.56]:box('Cart roof support',(x,1.28,z),(.075,1.59,.075),'wood')
 box('Cart broad flower bed',(0,.77,0),(1.72,.22,1.05),'wood',.025)
 box('Inset cart soil',(0,.895,0),(1.58,.03,.90),'soil')
 for x in [-.93,.93]:
  wheel=lathe('Large cart wooden wheel',[(0,.27),(.05,.27),(.055,.21),(.01,.21)],'wood_light',12)
  wheel.rotation_euler.y=math.pi/2;wheel.location=p.v((x,.27,0))
  # cylinder axis mapped to local X; wheel thickness contained in 2.0m canopy.
  for a in [0,math.pi/3,2*math.pi/3]:rod('Cart wheel spoke',(x,.27-.23*math.cos(a),-.23*math.sin(a)),(x,.27+.23*math.cos(a),.23*math.sin(a)),.016,'wood_dark',4)
 for x in [-.64,.64]:box('Cart grounded foot',(x,.345,.43),(.08,.69,.08),'wood_dark')
 rod('Continuous wheel axle',(-.95,.27,0),(.95,.27,0),.028,'metal',6)
 for x in [-.75,.75]:rod('Wheel-to-bed timber bracket',(x,.27,0),(x,.70,0),.038,'wood_dark',6)
 if STAGE=='final':
  for j in range(5):
   x=(j-2)*.30;z=(j%2-.5)*.38
   lathe('Small flower pot',[(0,.10),(.20,.14),(.23,.14)],'pot',7,(x,.90,z))
   ico('Cart leaf cluster',(x,1.18,z),(.19,.17,.18),'leaf_light' if j%2 else 'leaf')
   bloom((x,1.33,z),.10,'lavender' if j%2 else 'flower_cream')
 return {'canopy_complete_underside':True,'front':'+Z','triangle_budget_note':'Conservative ordinary-stall budget used (1500)'}

def board():
 for x in [-.46,.46]:
  box('Noticeboard timber post',(x,.88,0),(.10,1.76,.12),'wood',.015)
  box('Stable low board foot',(x,.04,0),(.20,.08,.30),'wood_dark',.01)
 box('Noticeboard back',(0,1.14,0),(1.20,1.03,.12),'wood_dark',.02)
 box('Warm cork writing panel',(0,1.15,.07),(1.04,.86,.025),'wood')
 for x in [-.56,.56]:box('Frame side',(x,1.14,.09),(.08,1.03,.05),'wood_light',.012)
 box('Frame lower rail',(0,.66,.09),(1.16,.08,.05),'wood_light',.012)
 # shallow curved lintel, within exact1.2x1.8 outer dimensions
 pts=[(-.60,1.67),(-.40,1.75),(0,1.80),(.40,1.75),(.60,1.67),(.60,1.59),(.40,1.67),(0,1.72),(-.40,1.67),(-.60,1.59)]
 n=len(pts);vs=[(x,y,z) for z in [-.09,.12] for x,y in pts];mesh('Arched blank timber cap',vs,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],'wood_light')
 if STAGE=='final':
  for i,(x,y,ww,hh,angle) in enumerate([(-.29,1.28,.28,.35,-5),(.04,1.13,.24,.33,5),(.31,.94,.21,.26,-3)]):
   o=box('Completely blank note %d'%i,(x,y,.093),(ww,hh,.012),'paper');o.rotation_euler.y=math.radians(angle)
 return {'blank_badge_reserved_local_m':{'min':[.24,1.35,.105],'max':[.49,1.56,.15]},'notes':'Blank papers; upper right panel clear, ! belongs to runtime UI'}

def fountain():
 lathe('Circular plinth',[(0,1.42),(.10,1.50),(.16,1.50),(.23,1.40)],'stone',24 if STAGE=='final' else 32)
 lathe('Lower carved stone basin',[(.18,1.28),(.33,1.40),(.48,1.40),(.54,1.34),(.54,1.20),(.45,1.15),(.29,1.10)],'stone_light',24 if STAGE=='final' else 32)
 lathe('Lower pool opaque water',[(.365,1.16),(.375,1.16)],'water',24 if STAGE=='final' else 32)
 lathe('Turned fountain stem',[(.36,.34),(.44,.37),(.55,.28),(.80,.19),(1.03,.23),(1.13,.33),(1.18,.36)],'stone',20)
 lathe('Upper scalloped bowl',[(1.10,.32),(1.19,.56),(1.34,.67),(1.43,.64),(1.43,.52),(1.32,.44),(1.28,.29)],'stone_light',24)
 lathe('Upper water surface',[(1.345,.51),(1.35,.51)],'water',24)
 lathe('Top spout pedestal',[(1.33,.17),(1.47,.22),(1.55,.16),(1.72,.13)],'stone',16)
 lathe('Round finial',[(1.65,0),(1.69,.13),(1.80,.20),(1.95,.15),(2.03,0)],'stone_light',16)
 if STAGE=='final':
  for j in range(4):
   a=(j+.5)*math.tau/4
   points=[]
   for t in [0,.25,.50,.75,1]:
    r=.48+t*.53;y=1.37+.20*math.sin(t*math.pi)-t*t*1.0
    points.append((r*math.cos(a),y,r*math.sin(a)))
   tube('Quiet static water arc',points,.017,'foam',5)
   lathe('Small water landing ring',[(.38,.10),(.39,.12),(.39,.085),(.38,.075)],'foam',8,(1.01*math.cos(a),0,1.01*math.sin(a)))
 return {'radius_m':1.5,'tiers':2,'water':'Opaque matte vertex-colour pools plus static arcs; no transparency, particles, animation or lights','flower_tub_instances':4,'flower_tub_is_separate_asset':True}

def crate():
 box('Crate base',(0,.035,0),(.62,.07,.44),'wood_dark')
 for x in [-.27,.27]:
  for z in [-.18,.18]:box('Crate corner cleat',(x,.18,z),(.06,.30,.06),'wood_dark')
 for y in [.13,.25]:
  for z in [-.20,.20]:box('Crate long plank',(0,y,z),(.62,.10,.04),'wood_light' if y>.2 else 'wood')
  for x in [-.29,.29]:box('Crate short plank',(x,y,0),(.04,.10,.36),'wood')
 if STAGE=='final':
  for x,z in [(-.16,0),(0,.03),(.16,-.02)]:ico('Produce inside reusable crate',(x,.32,z),(.09,.11,.09),'pear')
 return {}

def basket():
 lathe('Woven hollow basket',[(0,.15),(.04,.19),(.25,.225),(.32,.23),(.35,.21),(.35,.18),(.29,.18),(.06,.12)],'wood_light',10)
 for y,r in [(.10,.202),(.20,.218)]:lathe('Broad woven band',[(y,r),(y+.025,r+.002)],'wood',10)
 tube('Arched basket handle',[(.19*math.cos(a),.32+.22*math.sin(a),0) for a in [i*math.pi/8 for i in range(9)]],.015,'wood_dark',4)
 return {}

def flower_tub():
 lathe('Terracotta flower tub',[(0,.19),(.05,.21),(.35,.25),(.40,.27),(.44,.26),(.44,.22),(.37,.21)],'pot',6)
 lathe('Inset potting soil',[(.38,.21),(.385,.21)],'soil',8)
 for i,(x,z) in enumerate([(-.13,0),(.13,0),(0,.12)]):ico('Broad quiet leaf cluster',(x,.58,z),(.19,.17,.18),'leaf' if i%2 else 'leaf_light')
 if STAGE=='final':
  for i,(x,z) in enumerate([(-.12,-.06),(.13,.02),(0,.14)]):bloom((x,.74+(i%2)*.06,z),.09,'flower_cream' if i<2 else 'lavender')
 return {'repeat_count_by_fountain':4}

BUILDERS={**{n:(lambda n=n:stall(n)) for n in LIMITS if n.startswith('stall_')},'flower_cart':flower_cart,'market_board':board,'fountain':fountain,'produce_crate':crate,'basket':basket,'flower_tub':flower_tub}
def export(name,builder):
 start(name);extra=builder();bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
 # Editable source keeps named parts and un-applied bevels.
 blend=SRC/(('blockout/' if STAGE=='blockout' else '')+name+'.blend');blend.parent.mkdir(exist_ok=True)
 bpy.ops.wm.save_as_mainfile(filepath=str(blend),compress=True)
 mat=bpy.data.materials.get('Market matte vertex colour') or bpy.data.materials.new('Market matte vertex colour');mat.use_nodes=True;mat.use_backface_culling=True
 bs=mat.node_tree.nodes['Principled BSDF'];bs.inputs['Roughness'].default_value=.88;bs.inputs['Specular IOR Level'].default_value=.15
 vc=mat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';mat.node_tree.links.new(vc.outputs['Color'],bs.inputs['Base Color'])
 original=bpy.context.scene;scene=bpy.data.scenes.new('Export '+name);copies=[]
 for obj in p.PARTS:
  data=bpy.data.meshes.new_from_object(obj.evaluated_get(deps));data.transform(obj.matrix_world)
  for uv in list(data.uv_layers):data.uv_layers.remove(uv)
  cols=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
  for f in data.polygons:
   color=data.materials[f.material_index].diffuse_color
   for i in f.loop_indices:cols.data[i].color=color
  data.materials.clear();data.materials.append(mat)
  for f in data.polygons:f.material_index=0
  data.color_attributes.active_color=cols;data.color_attributes.render_color_index=0
  ob=bpy.data.objects.new(obj.name,data);scene.collection.objects.link(ob);copies.append(ob)
 bpy.context.window.scene=scene
 for ob in copies:ob.select_set(True)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();ob=bpy.context.object;ob.name=name;ob.data.name=name+'_mobile'
 bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7);bm.to_mesh(ob.data);bm.free();ob.data.calc_loop_triangles()
 count=len(ob.data.loop_triangles)
 pts=[(v.co.x,v.co.z,-v.co.y) for v in ob.data.vertices];lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
 print('MARKET_CHECK',name,count,'limit',LIMITS[name],'bounds',lo,hi,flush=True)
 assert count<=LIMITS[name],(name,count,LIMITS[name])
 assert abs(lo[1])<1e-6,(name,'floor',lo[1])
 assert all(hi[i]-lo[i]<=BOUNDS[name][i]+1e-5 for i in range(3)),(name,'bounds',lo,hi,BOUNDS[name])
 path=KIT/(name+'.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_normals=True,export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False)
 row={'name':name,'file':path.name,'triangles':count,'triangle_limit':LIMITS[name],'surfaces':1,'bounds':[lo,hi],'dimensions_m':[hi[i]-lo[i] for i in range(3)],'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'source':str(blend.relative_to(ROOT)),**extra}
 bpy.context.window.scene=original;bpy.data.scenes.remove(scene);return row

def main():
 KIT.mkdir(parents=True,exist_ok=True)
 only=sys.argv[sys.argv.index('--only')+1] if '--only' in sys.argv else None
 if only:
  old=json.loads((KIT/'asset_stats.json').read_text());assert old['stage']==STAGE
  changed=export(only,BUILDERS[only]);rows=[changed if r['name']==only else r for r in old['assets']]
 else:rows=[export(n,b) for n,b in BUILDERS.items()]
 (KIT/'asset_stats.json').write_text(json.dumps({'assets':rows,'stage':STAGE,'units':'metres, Y up, front +Z, floor-centre origin','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','unique_triangles':sum(x['triangles'] for x in rows),'palette_srgb':PAL},ensure_ascii=False,indent=2)+'\n')
 print('MARKET_COMPLETE',STAGE,len(rows),sum(x['triangles'] for x in rows),flush=True)
if __name__=='__main__':main()
