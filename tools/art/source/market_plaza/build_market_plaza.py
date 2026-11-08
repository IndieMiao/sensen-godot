"""SGODOT-218 market shell and dimensioned placeholders, approved v2.1/a9.

Blender: --background --factory-startup --python <this file>.
Room metres, Y up, +Z front. Models keep local floor pivots. No gameplay data.
"""
from pathlib import Path
import bpy, json, math, sys
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT/'tools/art'))
from landmark_kit import Kit, reset_scene
OUT=ROOT/'assets/rooms/market_plaza'
SOURCE=Path(__file__).resolve().parent
reset_scene()
PALETTE={'stone':'D9C4A3','cream':'F0E1C2','cream_light':'FFF0D2','pave':'DFCBA7',
 'gray':'B7B9B3','gray_top':'D3D5CF','pot':'C39E73','soil':'78644B',
 'leaf':'82AA55','leaf_light':'A8C873','leaf_dark':'658B45','trunk':'795F47',
 'sage':'9AAD82','mint':'B4C8A0','teal':'91B9B3','yellow':'DDC59B','wood':'A3815D',
 'iron':'5D4C38','bulb':'FFE0A3','water':'91C3CC',
 'sf_blue':'8FAEB1','sf_pink':'CFA59B','sf_cream':'E3D5B9','sf_yellow':'D7BE8D',
 'generic_sage':'B9C5BA','generic_sand':'D8CBB2','generic_ivory':'D9D6C7','generic_clay':'C6B9A5',
 'glass':'8DAEAC','door':'6F8A75','slate':'748B9C','petal_white':'F4E6C9','petal_lilac':'BBA9CC','petal_yellow':'E6C778'}
kit=Kit(OUT,PALETTE)
kit.begin('mp_ground',ao=False)
kit.box('Paving slab',(0,-.075,0),(16,.25,16),'pave',.015)
kit.begin('mp_surround',ao=False)
kit.box('Exterior ground',(0,-.12,0),(36,.24,36),'leaf',.01)
kit.begin('mp_sidewalk',ao=False)
kit.box('Sidewalk',(0,-.005,0),(2,.07,26),'pave',.01)
kit.begin('mp_edge_trim')
kit.box('Stone edge',(0,.08,0),(2,.16,.16),'cream',.025)
kit.begin('mp_gate_post')
kit.box('Foot',(0,.10,0),(.46,.20,.46),'stone',.035)
kit.box('Pier',(0,.57,0),(.34,.84,.34),'cream',.025)
kit.box('Cap',(0,1.03,0),(.46,.12,.46),'cream_light',.03)
kit.ellipsoid('Finial',(0,1.22,0),(.24,.27,.24),'cream',12,8)
kit.begin('mp_facade_placeholder',ao=False)
kit.box('Two storey volume',(0,3.18,0),(4,6.36,2.5),'gray',.02)
kit.box('Closed roof surface',(0,6.34,0),(4,.10,2.5),'gray_top',.02)
for z in [-1.2,1.2]:kit.box('Roof parapet',(0,6.45,z),(4,.1,.1),'gray_top',.015)
for x in [-1.95,1.95]:kit.box('Roof return',(x,6.45,0),(.1,.1,2.5),'gray_top',.015)

def facade(name,paint,victorian):
 kit.begin(name)
 kit.box('Shared structural body',(0,2.92,0),(4,5.84,2.5),paint,.025)
 kit.box('Stone plinth',(0,.14,0),(4.04,.28,2.54),'stone',.025)
 kit.box('Floor belt',(0,2.95,1.29),(4.1,.16,.14),'cream',.025)
 kit.box('Cornice lower',(0,5.76,1.31),(4.12,.16,.20),'cream',.025)
 kit.box('Cornice upper',(0,5.95,1.31),(4.18,.15,.26),'cream_light',.025)
 # A complete roof prism, 2.5m deep, with rear and end caps.
 kit.mesh('Slate pitched roof',[(-2,5.95,-1.25),(2,5.95,-1.25),(-2,6.5,0),(2,6.5,0),(-2,5.95,1.25),(2,5.95,1.25),
  (-2,5.86,-1.25),(2,5.86,-1.25),(-2,5.86,1.25),(2,5.86,1.25)],
  [(0,2,3,1),(2,4,5,3),(6,7,9,8),(6,0,1,7),(8,9,5,4),(6,8,4,2,0),(7,1,3,5,9)],'slate')
 kit.box('Ridge cap',(0,6.49,0),(4.04,.035,.08),'slate',.01)
 for x in [-1.87,1.87]:
  kit.box('Corner pilaster',(x,2.92,1.29),(.16,5.6,.13),'cream',.012)
 # All variants use the same central door, steps and window opening coordinates.
 kit.box('Door closed leaf',(0,1.33,1.30),(.98,2.20,.12),'door',.02)
 for x in [-.56,.56]:kit.box('Door surround',(x,1.35,1.36),(.12,2.38,.15),'cream',.015)
 kit.box('Door lintel',(0,2.52,1.36),(1.25,.14,.18),'cream_light',.02)
 for y in [.68,1.25]:kit.box('Door inset panel',(0,y,1.372),(.75,.39,.025),'door',.025)
 kit.box('Door transom',(0,2.12,1.38),(.73,.45,.025),'glass',.012)
 kit.ellipsoid('Door knob',(.32,1.25,1.415),(.055,.055,.04),'iron',8,5)
 for i in range(3):
  kit.box('Decorative step %d'%i,(0,.06+i*.08,1.75-i*.18),(1.36,.12+i*.16,.26),'stone',.02)
 def window(x,y,w,h,front=1.30):
  kit.box('Opaque glass',(x,y,front),(w,h,.08),'glass',.012)
  for xx in [x-w/2-.045,x+w/2+.045]:kit.box('Window jamb',(xx,y,front+.045),(.09,h+.18,.13),'cream',.01)
  for yy in [y-h/2-.045,y+h/2+.045]:kit.box('Window rail',(x,yy,front+.05),(w+.18,.09,.15),'cream',.012)
  kit.box('Window mullion',(x,y,front+.07),(.045,h,.10),'cream_light',.006)
  kit.box('Window transom',(x,y+.12,front+.07),(w,.045,.10),'cream_light',.006)
  kit.box('Sill',(x,y-h/2-.12,front+.12),(w+.28,.12,.28),'cream_light',.02)
 for x in [-1.25,1.25]:window(x,1.56,.68,1.28)
 kit.box('Upper bay sill',(0,3.6,1.43),(2.8,.16,.44),'cream',.025)
 for x in [-.86,0,.86]:window(x,4.48,.66,1.46,1.43)
 for x in [-1.4,1.4]:kit.box('Upper bay edge',(x,4.45,1.43),(.12,1.8,.42),paint,.02)
 kit.box('Upper bay cap',(0,5.41,1.43),(2.92,.16,.5),'cream_light',.025)
 if victorian:
  for x in [-1.5,-.5,.5,1.5]:kit.box('Victorian corbel',(x,5.64,1.42),(.16,.22,.22),'cream',.025)
  kit.box('Door pediment',(0,2.68,1.38),(1.38,.16,.2),'cream',.03)
  for x in [-.86,0,.86]:kit.ellipsoid('Upper window keystone',(x,5.29,1.52),(.16,.14,.08),'cream_light',8,5)
 # Shared flower-box skeleton; only petal colour changes between variants.
 for x,y,z in [(-1.25,.79,1.53),(1.25,.79,1.53),(0,3.43,1.62)]:
  width=.84 if y<1 else 1.5
  kit.box('Window flowerbox',(x,y,z),(width,.24,.30),'cream',.025)
  for j in range(5):
   xx=x+(j-2)*width*.17
   kit.ellipsoid('Window foliage',(xx,y+.16,z),(.24,.22,.27),'leaf' if j%2 else 'leaf_light',8,5)
   kit.ellipsoid('Window flower',(xx,y+.285,z+.04),(.14,.07,.14),('petal_lilac' if victorian else 'petal_white') if j%2 else 'petal_yellow',8,5)
for i,col in enumerate(['sf_blue','sf_pink','sf_cream','sf_yellow']):facade('facade_sf_'+str(i),col,True)
for i,col in enumerate(['generic_sage','generic_sand','generic_ivory','generic_clay']):facade('facade_generic_'+str(i),col,False)

kit.begin('mp_keeper_flowerbed')
# Room-diagonal garden band between the basin and keeper stall, physically filled
# with low plants. Its curved inner edge follows the fountain instead of hiding
# an arbitrary navigation exclusion behind an empty floor.
q0,q1=0.0,2.312;mid=(q0+q1)/2
curve=[]
for i in range(21):
 t=1.7-i*.17
 q=max(q0,-.8*math.sqrt(2)+math.sqrt(max(0,1.55**2-t*t)))
 curve.append((t,q-mid))
outline=[(-1.7,q1-mid),(1.7,q1-mid)]+curve
kit.slab('Garden stone base',outline,0,.24,'stone',bevel=.015)
kit.slab('Garden soil',outline,.235,.25,'soil',bevel=0)
for i,(a,b) in enumerate(zip(outline,outline[1:]+outline[:1])):
 length=math.dist(a,b)
 kit.box('Low garden rim %d'%i,((a[0]+b[0])/2,.21,(a[1]+b[1])/2),(length,.42,.075),'cream',.015,rot_y=-math.atan2(b[1]-a[1],b[0]-a[0]))
for ix in range(10):
 for iz in range(5):
  x=-1.5+ix/3;q=q0+.2+iz*.36
  if q<-.8*math.sqrt(2)+math.sqrt(max(0,1.58**2-x*x))+.1 or q>q1-.12:continue
  z=q-mid
  kit.ellipsoid('Low herb cushion',(x,.33,z),(.32,.21,.31),'leaf' if (ix+iz)%2 else 'leaf_light',8,5)
  if (ix+iz)%3==0:kit.ellipsoid('Low bloom',(x,.415,z),(.13,.06,.13),'petal_white' if ix%2 else 'petal_lilac',8,5)
kit.begin('mp_tree_pot')
kit.lathe('Terracotta bowl',[(.4,0),(.43,.12),(.48,.61),(.51,.64),(.51,.72),(.43,.72),(.4,.62)],'pot',20,True)
kit.cylinder('Soil',(0,.64,0),.42,.03,'soil',seg=20)
kit.cylinder('Trunk',(0,1.3,0),.075,1.35,'trunk',top=.05,seg=10)
kit.ellipsoid('Crown',(0,2.35,0),(1.45,1.5,1.4),'leaf',14,8)
for i in range(5):
 a=i*math.tau/5
 kit.ellipsoid('Crown lobe %d'%i,(math.cos(a)*.44,2.13+(i%2)*.24,math.sin(a)*.44),(.72,.85,.72),'leaf_light' if i%2 else 'leaf_dark',12,7)
kit.begin('mp_fountain_placeholder',ao=False)
kit.cylinder('Basin envelope',(0,.28,0),1.5,.56,'gray',seg=32)
kit.cylinder('Water mark',(0,.57,0),1.31,.025,'water',seg=32)
kit.cylinder('Upper envelope',(0,1.02,0),.35,.88,'gray_top',seg=16)
kit.ellipsoid('Finial',(0,1.57,0),(.38,.38,.38),'gray_top',12,8)

def stall(name,width):
 kit.begin(name,ao=False)
 # Explicit footprint and frame; canopy fabric will arrive in Huangzhong's kit.
 # Front counter leaves Mei's authored station behind it visibly hollow.
 kit.box('Counter envelope',(0,.5,.53),(width,.95,.50),'gray',.015)
 kit.box('Counter top',(0,1.015,.53),(width+.04,.08,.54),'gray_top',.01)
 for x in [-width/2+.07,width/2-.07]:
  kit.box('Rear post',(x,1.23,-.73),(.08,2.46,.08),'gray',.005)
 for z in [-.76,.76]:kit.box('Canopy extent rail',(0,2.45,z),(width,.055,.055),'gray_top',0)
 for x in [-width/2,width/2]:kit.box('Canopy side extent',(x,2.45,0),(.055,.055,1.6),'gray_top',0)
 kit.box('Footprint',(0,.018,0),(width,.035,1.6),'gray_top',0)
stall('mp_stall_placeholder',2)
stall('mp_keeper_placeholder',3.2)
kit.begin('mp_board_placeholder',ao=False)
for x in [-.42,.42]:kit.box('Board support',(x,.82,0),(.09,1.64,.09),'gray',.01)
kit.box('Blank board',(0,1.55,0),(1.12,1.12,.12),'gray_top',.03)

# Decorative cables and pennants use separate reusable 2 m modules.
kit.begin('mp_string_lights',ao=False)
for i in range(12):
 x0=-1+i/6;x1=-1+(i+1)/6
 h=lambda x:-.12*(1-x*x)
 kit.beam('Cable',(x0,h(x0),0),(x1,h(x1),0),.012,'iron')
for x in [-.8,-.4,0,.4,.8]:
 y=-.12*(1-x*x)
 kit.beam('Socket',(x,y,0),(x,y-.055,0),.025,'iron')
 kit.ellipsoid('Bulb',(x,y-.095,0),(.07,.08,.07),'bulb',8,5)
kit.begin('mp_bunting',ao=False)
for i in range(12):
 x0=-1+i/6;x1=-1+(i+1)/6;h=lambda x:-.1*(1-x*x)
 kit.beam('Cord',(x0,h(x0),0),(x1,h(x1),0),.01,'iron')
for i,x in enumerate([-.8,-.4,0,.4,.8]):
 y=-.1*(1-x*x)
 kit.mesh('Blank pennant %d'%i,[(x-.13,y,-.005),(x+.13,y,-.005),(x,y-.29,-.005),
  (x-.13,y,.005),(x+.13,y,.005),(x,y-.29,.005)],
  [(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)],['sage','teal','mint','yellow'][i%4])

# Small mobile trim keeps one bevel segment; retain editable modifiers.
for obj in bpy.data.objects:
 for modifier in obj.modifiers:
  if modifier.type=="BEVEL":modifier.segments=1
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'market_plaza.blend'))
stats={name:kit.export(name) for name in list(kit.assets)}
(OUT/'shell_asset_stats.json').write_text(json.dumps({'generator':str(Path(__file__).relative_to(ROOT)),'author':'马可波罗','assets':stats},indent=2)+'\n')
print('MARKET_SHELL_EXPORT',json.dumps(stats),flush=True)
