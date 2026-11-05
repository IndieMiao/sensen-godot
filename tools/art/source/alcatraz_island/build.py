"""SGODOT-424 B: editable, deliberately untextured layout blockout.

Run with: flock ~/gs66-render.lock blender --background --factory-startup --python /ABS/PATH/build.py
Godot metres, Y up, north -Z. Module pivots are floor centres. No gameplay data.
"""
from pathlib import Path
import json
import math
import random
import sys
import bpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'tools/art'))
from landmark_kit import Kit, reset_scene

OUT = ROOT / 'assets/landmarks/alcatraz_island'
reset_scene()
random.seed(424)
kit = Kit(OUT, {'stone':'b5b6b3', 'garden':'8d9690', 'road':'e5e3db',
    'building':'dbdcd7', 'roof':'acb1b2', 'glass':'78868a', 'wood':'b8b3a6',
    'dark':'727d80', 'bird':'eeede6', 'bridge':'c76845', 'far':'b4c2c8'})
placements = []
obstacles = []

def place(asset, pos=(0,0,0), yaw=0, scale=1, collision=True):
    placements.append({'asset':asset,'position':list(pos),'yaw':yaw,'scale':scale,'collision':collision})

def box(name, p, size, color='building', bevel=.04):
    return kit.box(name,p,size,color,bevel)

def prism(name, points, bottom, top, color):
    n=len(points)
    verts=[(x,y,z) for y in [bottom,top] for x,z in points]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
    return kit.mesh(name,verts,faces,color)

# Deliberate height bands. Gardens are darker than the walkable paving.
bands=[('shore',-.45,.70,[(-7,10),(-8,5),(-9.6,-5),(-9.6,-10),(-7,-14),(7,-14),(9.6,-10),(9.6,-5),(5,6),(7,10)]),
       ('lower',.70,.80,[(-6,9),(-6,3),(-9.4,-5),(-9.4,-10),(-7,-13.8),(7,-13.8),(9.4,-10),(9.4,-5),(5,3),(4,9)]),
       ('middle',.8,2.4,[(-5.5,5.5),(-6,-3),(-9.3,-5),(-9.3,-10),(-7,-13.6),(7,-13.6),(9.3,-10),(9.3,-5),(5,-2),(4,5.5)]),
       ('upper',2.4,4.0,[(-5.5,.5),(-9.2,-5),(-9.2,-10),(-7,-13.4),(7,-13.4),(9.2,-10),(9.2,-5),(4,.5)]),
       ('summit',4.0,5.6,[(-9,-4.5),(-9,-10),(-7,-13),(7,-13),(9,-10),(9,-4.5)])]
for name,lo,hi,poly in bands:
    kit.begin('island_'+name)
    # In world XZ these clockwise polygons produce an upward top after conversion.
    prism(name+'_cliff',list(reversed(poly)),lo,hi-.12,'stone')
    prism(name+'_garden',list(reversed(poly)),hi-.12,hi,'garden')
    place('island_'+name)

# (x0,x1,z0,z1,y); the route has three stair flights and broad turning landings.
flats=[(4.75,7.25,10,15,.8), (0,7.25,9,11.5,.8),
       (.25,2.75,8.5,10.5,.8), (-4,.25,4.5,6.5,2.4), (.25,2.75,4.5,5.5,2.4),
       (-4,-1.5,3.5,5.5,2.4), (-4,-1.5,-.5,.5,4.0), (-1.5,3,-.5,1.5,4.0),
       (.5,3,-1.5,.5,4.0), (-9,9,-8,-4.5,5.6)]
# x0,x1, north z, south z, upper y, lower y
stairs=[(.25,2.75,5.5,8.5,2.4,.8),(-4,-1.5,.5,3.5,4,2.4),(.5,3,-4.5,-1.5,5.6,4)]
kit.begin('walkways')
for i,(x0,x1,z0,z1,y) in enumerate(flats[1:]):
    box('paved_landing_%02d'%i,((x0+x1)/2,y-.09,(z0+z1)/2),(x1-x0,.24,z1-z0),'road',.015)
place('walkways')
kit.begin('stairs')
for j,(x0,x1,z0,z1,hi,lo) in enumerate(stairs):
    for i in range(10):
        step=(z1-z0)/10
        y=lo+(hi-lo)*(10-i)/10
        box('flight_%d_tread_%02d'%(j+1,i),((x0+x1)/2,(y+lo-.14)/2,z0+(i+.5)*step),
            (x1-x0,y-lo+.2,step+.005),'road',.008)
    for x in [x0-.10,x1+.10]:
        kit.beam('flight_%d_stone_edge'%j,(x,hi+.34,z0),(x,lo+.34,z1),.18,'stone',.30)
place('stairs')

kit.begin('dock')
for i in range(20): box('deck_plank_%02d'%i,(0,-.10,-2.5+(i+.5)*.25),(2.5,.2,.235),'wood',.008)
for x in [-1.35,1.35]:
    for z in [0,2.3]: box('timber_pile',(x,-.4,z),(.22,1.7,.22),'wood',.015)
place('dock',(6,.8,12.5))

kit.begin('visitor_center')
box('museum_volume',(0,1.7,0),(8,3.4,4.2))
box('flat_roof',(0,3.47,0),(8.25,.16,4.45),'roof')
box('public_entry_frame',(0,.95,2.16),(1.2,1.9,.16))
box('public_entry_glazing',(0,.85,2.26),(.8,1.65,.04),'glass',0)
for x in [-3.2,-2.1,-1,1,2.1,3.2]:
    for y in [1,2.5]: box('unbarred_museum_window',(x,y,2.13),(.48,.95,.04),'glass',.03)
for x in [-3.5,3.5]:box('corner_pilaster',(x,1.7,2.17),(.22,3.4,.16))
place('visitor_center',(0,5.6,-10.2))
obstacles.append({'name':'visitor_center','min':[-4,5.6,-12.3],'max':[4,9.2,-8.1]})

kit.begin('lighthouse')
kit.cylinder('tapered_tower',(0,2.6,0),.72,5.2,'building',top=.43,seg=16)
kit.cylinder('lantern_gallery',(0,5.25,0),.85,.18,'road',seg=16)
kit.cylinder('lantern_glass',(0,5.7,0),.48,.75,'glass',seg=12)
kit.cylinder('lantern_cap',(0,6.2,0),.7,.35,'building',top=0,seg=16)
place('lighthouse',(-7,5.6,-9))

kit.begin('water_tower')
for x in [-.7,.7]:
    for z in [-.7,.7]:
        kit.beam('support_leg',(x*1.2,0,z*1.2),(x,3,z),.15,'wood')
for z in [-.7,.7]:
    kit.beam('cross_brace',(-.7,.4,z),(.7,2.7,z),.1,'wood')
    kit.beam('cross_brace',(.7,.4,z),(-.7,2.7,z),.1,'wood')
kit.cylinder('tank',(0,3.5,0),1,1.2,'wood',seg=16)
kit.cylinder('tank_roof',(0,4.3,0),1.12,.4,'roof',top=0,seg=16)
place('water_tower',(7,5.6,-10.5))

kit.begin('ruins')
for x,h in [(-1.8,1.5),(-.8,2.2),(.3,2.5),(1.7,1.6)]:
    box('remaining_pier',(x,h/2,0),(.40,h,.35),'stone')
box('surviving_lintel',(-.25,1.8,0),(2.8,.32,.35),'stone')
box('broken_side_wall',(1.7,.55,-.75),(.35,1.1,1.5),'stone')
place('ruins',(2.2,2.4,3.5))

kit.begin('ferry')
# Static display boat. Kept left of the dock, away from the lower-right HUD zone.
prism('hull',[(-1,1.9),(-1,-1.4),(-.65,-2),( .65,-2),(1,-1.4),(1,1.9)],-.4,.4,'building')
box('lower_deck',(0,.6,0),(1.8,.5,3.5))
box('cabin',(0,1.05,.25),(1.35,.55,2.0))
box('cabin_roof',(0,1.37,.25),(1.55,.12,2.2),'roof')
for x in [-.69,.69]:
    for z in [-.4,.2,.8]: box('ferry_window',(x,1.08,z),(.03,.30,.38),'glass',.02)
kit.cylinder('short_funnel',(0,1.6,.65),.16,.45,'dark',seg=12)
place('ferry',(3.3,.2,13.9),collision=False)

kit.begin('bench')
box('seat',(0,.45,0),(1.5,.13,.48),'wood')
box('back',(0,.8,-.2),(1.5,.55,.1),'wood')
for x in [-.55,.55]:box('feet',(x,.2,0),(.10,.4,.40),'dark')
for pos,yaw in [((.1,.8,11.2),0),((-4.7,2.4,5.5),math.pi/2),((3.9,5.6,-6),-math.pi/2)]:
    place('bench',pos,yaw)

kit.begin('lamp')
kit.cylinder('post',(0,.85,0),.055,1.7,'dark',seg=8)
kit.ellipsoid('globe',(0,1.78,0),(.28,.28,.28),'bird',seg=10,rings=6)
for p in [(-.4,.8,9.2),(-4.5,2.4,3.7),(3.3,4,-.8),(-3.7,5.6,-5.3)]:place('lamp',p)

kit.begin('gull')
kit.ellipsoid('body',(0,.12,0),(.32,.24,.45),'bird',seg=10,rings=6)
kit.ellipsoid('head',(0,.29,-.18),(.19,.19,.19),'bird',seg=8,rings=6)
box('beak',(0,.28,-.29),(.08,.06,.13),'wood',.01)
for p in [(7.35,1.25,10.8),(-4.3,2.75,5.8),(3.3,4.35,-.8)]:place('gull',p,collision=False)

kit.begin('golden_gate_backdrop',ao=False)
# Compressed scenic miniature offshore: visible through the opening's east bay gap.
box('bridge_deck',(0,.45,0),(3.4,.08,.22),'bridge',.01)
for x in [-.95,.95]:
    for z in [-.11,.11]:box('red_tower',(x,.85,z),(.11,1.7,.10),'bridge',.01)
    for y in [.6,1.2,1.6]:box('tower_crossbeam',(x,y,0),(.14,.08,.36),'bridge',.01)
for z in [-.16,.16]:
    pts=[]
    for i in range(33):
        x=-1.7+i*3.4/32
        y=.65+.95*(abs(x)/.95)**2 if abs(x)<.95 else 1.6-(abs(x)-.95)*1.25
        pts.append((x,y,z))
    for a,b in zip(pts,pts[1:]):kit.beam('suspension_cable',a,b,.025,'bridge')
    for i in range(15):
        x=-1.6+i*3.2/14
        y=.65+.95*(abs(x)/.95)**2 if abs(x)<.95 else 1.6-(abs(x)-.95)*1.25
        kit.beam('hanger',(x,.49,z),(x,y,z),.018,'bridge')
place('golden_gate_backdrop',(8,.10,4.8),scale=.55,collision=False)

kit.begin('city_backdrop',ao=False)
for i in range(38):
    x=-35+i*1.8;h=random.uniform(1,3.3)
    box('skyline_%02d'%i,(x,h/2,random.uniform(-1.5,1.5)),(random.uniform(.8,1.5),h,1.3),'far',0)
kit.cylinder('transamerica',(2,3.4,0),.65,6.8,'far',top=0,seg=4)
place('city_backdrop',(0,-.3,-18),scale=.5,collision=False)

# Continuous ramp navigation; visible treads have 0.16 m risers.
def surface(x,z):
    for x0,x1,z0,z1,hi,lo in stairs:
        if x0-1e-5<=x<=x1+1e-5 and z0-1e-5<=z<=z1+1e-5:
            return hi+(lo-hi)*(z-z0)/(z1-z0)
    for x0,x1,z0,z1,y in flats:
        if x0-1e-5<=x<=x1+1e-5 and z0-1e-5<=z<=z1+1e-5:return y
    return None

# Cut collision footprints and rail the outside of walkable strips.
def blocked(x,z):
    for p in placements:
        if p['asset']=='bench':
            px,py,pz=p['position']
            sx,sz=(.95,.52) if abs(p['yaw'])<.01 else (.52,.95)
            if abs(x-px)<sx and abs(z-pz)<sz:return True
    return False

verts=[];polys=[];cells={};index={};step=.25
for ix in range(-36,36):
    for iz in range(-56,61):
        x,z=ix*step,iz*step
        # Actor-centre clearance is represented in nav; edge strips remain visually paved.
        samples=[surface(x+dx,z+dz) for dx,dz in [(0,0),(step,0),(step,step),(0,step)]]
        if any(y is None for y in samples):continue
        if surface(x+.125,z+.125) is None or blocked(x+.125,z+.125):continue
        if max(samples)-min(samples)>.2:continue
        ids=[]
        for (vx,vz),y in zip([(ix,iz),(ix+1,iz),(ix+1,iz+1),(ix,iz+1)],samples):
            key=(vx,round(y,5),vz)
            if key not in index:index[key]=len(verts);verts.append([vx*step,round(y,5),vz*step])
            ids.append(index[key])
        cells[(ix,iz)]=len(polys);polys.append(list(reversed(ids)))

walk_cells=cells.copy()
# One 0.25 m border cell is excluded for the avatar's body clearance.
retained={p:i for p,i in cells.items() if all(q in cells for q in
    [(p[0]+1,p[1]),(p[0]-1,p[1]),(p[0],p[1]+1),(p[0],p[1]-1)])}
polys=[polys[i] for i in retained.values()]
cells={p:i for i,p in enumerate(retained)}
kit.begin('path_edges',ao=False)
for ix,iz in walk_cells:
    x,z=(ix+.5)*step,(iz+.5)*step
    # Edge rails end at the actual dock landing; open south end is the Map entrance.
    if z>10.9:continue
    for dx,dz in [(1,0),(-1,0),(0,1),(0,-1)]:
        if (ix+dx,iz+dz) in walk_cells:continue
        y=surface(x,z)
        box('pale_stone_curb',(x+dx*step/2,y+.17,z+dz*step/2),
            (.10 if dx else step,.34,step if dx else .10),'stone',.005)
place('path_edges')

# Graph connectivity is a source check; runtime independently checks NavigationServer paths.
seen=set();todo=[next(iter(cells))]
while todo:
    p=todo.pop()
    if p in seen:continue
    seen.add(p)
    todo.extend(q for q in [(p[0]+1,p[1]),(p[0]-1,p[1]),(p[0],p[1]+1),(p[0],p[1]-1)] if q in cells and q not in seen)
discarded_nav_cells=len(cells)-len(seen)
# Clearance erosion can leave a single isolated corner beside a bench; omit it.
assert discarded_nav_cells<=2,(len(seen),len(cells))
polys=[polys[i] for p,i in cells.items() if p in seen]
cells={p:i for i,p in enumerate(p for p in cells if p in seen)}

layout={'revision':'B blockout 1','units':'metres, Y up, north -Z','placements':placements,
    'spawn':[6,.8,13.6],'exit':[6,.8,14.5], 'cam0':[6,.8,13.6],
    'review_points':{'opening':[6,.8,13.6],'mid_hill':[-2.75,2.4,4.5],'visitor_center':[0,5.6,-5.8]},
    'navigation':{'vertices':verts,'polygons':polys,'cell':step},'obstacles':obstacles,
    'route':[[6,.8,13.6],[6,.8,10],[1.5,.8,9],[1.5,2.4,5.8],[-2.75,2.4,4.5],[-2.75,4,.8],[1.75,4,-1],[1.75,5.6,-4.6],[0,5.6,-5.8]],
    'stairs':[{'flight':i+1,'lower':s[5],'upper':s[4],'width':s[1]-s[0],'run':s[3]-s[2],'risers':10} for i,s in enumerate(stairs)],
    'camera':{'pitch':45,'width':7,'zoom_min':.8,'zoom_max':1.4},
    'sea_size':512,'nav_connected_cells':len(seen),'clearance_m':.25,'discarded_nav_corner_cells':discarded_nav_cells,
    'notes':['Grey values are navigation/volume cues, not final color approval.',
             'Golden Gate is a deliberately compressed offshore scenic miniature for dock visibility.',
             'Boat and gulls are decorative, without interaction or navigation.']}
(OUT/'layout.json').write_text(json.dumps(layout,separators=(',',':'))+'\n')
manifest={'generator':'tools/art/source/alcatraz_island/build.py','reference':'c_alc.png supplied 2026-11-05',
          'phase':'whitebox only','assets':{}}
for name in kit.assets:
    manifest['assets'][name]=kit.export(name,ao_radius=.18)
    print('ALCATRAZ_ASSET',name,manifest['assets'][name],flush=True)
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')

# Editable named modules and actual arranged scene, without destructive joins on the source.
assembly=bpy.data.collections.new('Alcatraz_Blockout_Assembly')
bpy.context.scene.collection.children.link(assembly)
for i,p in enumerate(placements):
    obj=bpy.data.objects.new('%02d_%s'%(i,p['asset']),None)
    obj.instance_type='COLLECTION';obj.instance_collection=kit.assets[p['asset']]
    obj.location=kit.v(p['position']);obj.rotation_euler.z=p['yaw'];obj.scale=(p['scale'],)*3
    assembly.objects.link(obj)
for col in kit.assets.values():bpy.context.scene.collection.children.unlink(col)
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'alcatraz_blockout.blend'))
print('ALCATRAZ_DONE',len(kit.assets),'assets;',len(cells),'connected nav cells',flush=True)
