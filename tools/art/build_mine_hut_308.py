#!/usr/bin/env python3
"""SGODOT-308: named editable Mine Hut; Godot metres/Y-up helpers.
blender -b --factory-startup --python tools/art/build_mine_hut_308.py
Helmet dependency: run prepare_mine_hut_308.py --helmet first (pinned farm-dev).
No original room, NPC source, shared atlas or anchors are modified.
"""
from pathlib import Path
import sys,json,math,random,hashlib
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
import numpy as np
from mathutils import Vector,Matrix
import scene_room_pipeline as p
from scene_room_pipeline import begin,cube,ellipsoid,cylinder,tube,mesh,lathe,leaf,plant
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'tools/art/source/mine_hut'
FARM='ef70f8052cf547407eaa09fd881839bf2df929e3'
PROVENANCE=[]
PAL={'oak':'BB6C54','oak_light':'D18C6A','oak_edge':'96513E','oak_dark':'644136','oak_end':'C47C5D',
 'floor':'CC8968','floor_light':'D79774','floor_shade':'C18060','joint':'A96B52',
 'plaster':'E9B9AA','plaster_light':'EFC8BD','stone':'92968C','iron':'41464A','iron_edge':'666B69',
 'linen':'EAE0D5','leaf':'63834C','leaf_light':'86A369','leaf_dark':'486F42','terra':'AE7651'}
def collide(size,at=None):return [{'at':at or [0,size[1]/2,0],'size':size}]
def current(name):p.b.CURRENT=p.KITS[name]
def remove(name,tokens):
 k=p.KITS[name]
 for o in list(k['objects']):
  if any(t.lower() in o.name.lower() for t in tokens):k['objects'].remove(o);bpy.data.objects.remove(o,do_unlink=True)
def reuse(name,original,at,yaw=0,scale=(1,1,1),remove_names=()):
 k=p.reuse(name,at,yaw,source='blacksmith_shop',original=original);current(name)
 remove(name,remove_names)
 # Each original editable part remains separate; geometry is only scaled/recoloured.
 for o in k['objects']:
  o.location=Vector((o.location.x*scale[0],o.location.y*scale[2],o.location.z*scale[1]))
  o.scale=Vector((o.scale.x*scale[0],o.scale.y*scale[2],o.scale.z*scale[1]))
  for slot in o.material_slots:
   src=slot.material
   if not src:continue
   key=next((x for x in sorted(PAL,key=len,reverse=True) if src.name.startswith(x+'_')),None)
   if key:slot.material=p.b.material(key)
 for c in k['collision']:
  c['at']=[c['at'][i]*scale[i] for i in range(3)];c['size']=[c['size'][i]*scale[i] for i in range(3)]
 PROVENANCE.append({'asset':name,'source_kit':'blacksmith_shop','source_collection':'KIT_'+original,'scale_xyz':scale,'removed_parts':remove_names})
 return k

def beam(name,a,b,width,depth,color='oak'):
 mid=(Vector(a)+Vector(b))/2;o=cube(name,mid,(width,(Vector(b)-Vector(a)).length,depth),color,.025)
 o.rotation_euler=(p.v(b)-p.v(a)).to_track_quat('Z','Y').to_euler();return o

def rock(name,at,size,color='stone',sub=1):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=p.v(at));o=bpy.context.object
 o.scale=(size[0]/2,size[2]/2,size[1]/2);o.rotation_euler=(random.uniform(-.3,.3),random.uniform(-.3,.3),random.random()*2)
 p.b.finish(o,name,color,smooth=False)
 mod=o.modifiers.new('Worn rock corners','BEVEL');mod.width=.025;mod.segments=2
 mod=o.modifiers.new('Rock face normals','WEIGHTED_NORMAL');mod.keep_sharp=True
 return o

def polygon_slab(name,pts,y,thick,color):
 n=len(pts);vs=[(x,yy,z) for yy in [y,y+thick] for x,z in pts]
 fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 o=mesh(name,vs,fs,color);mod=o.modifiers.new('Soft stone or hide edge','BEVEL');mod.width=min(.04,thick*.45);mod.segments=2
 return o

def shell():
 begin('room_shell',(0,0,0),collision=collide([6.8,.34,6.4],[0,-.088,0]))
 cube('Honey timber foundation',(0,-.10,0),(6.8,.36,6.4),'oak',.09)
 cube('Fine warm floor seams',(0,.030,0),(6.57,.08,6.15),'joint',0)
 for row in range(18):
  z=-3.06+(row+.5)*6.12/18;x=-3.28;col=0
  while x<3.279:
   length=min(1.65 if col or row%2==0 else .83,3.28-x)
   cube('Orange oak floor plank %02d %02d'%(row,col),(x+length/2,.056,z),(length-.010,.052,6.12/18-.008),['floor','floor_light','floor_shade','floor'][(row+col*3)%4],.007)
   x+=length;col+=1
 for z in [-3.15,3.15]:cube('Floor rim',(0,.008,z),(6.8,.148,.1),'oak_light',.016)
 for x in [-3.35,3.35]:cube('Floor side rim',(x,.008,0),(.1,.148,6.2),'oak_light',.016)
 begin('left_wall',(-3.29,0,0),90,collide([6.2,3.30,.16],[0,1.65,0]))
 cube('Warm cream west plaster',(0,1.69,0),(6.2,3.22,.16),'plaster',.02)
 for x in [-2.98,2.98]:
  cube('Orange timber upright',(x,1.65,.09),(.20,3.3,.24),'oak',.045)
  cube('Post square foot',(x,.20,.12),(.29,.24,.30),'oak_light',.025)
 cube('West upper beam',(0,3.27,.06),(6.39,.26,.28),'oak',.055)
 cube('West skirting',(0,.22,.11),(6.1,.20,.12),'oak_light',.02)
 begin('back_wall',(0,0,-3.09),collision=[{'at':[0,1.65,-.04],'size':[6.6,3.3,.16]}])
 # True opening cut in new wall, visually capped only deep inside the tunnel.
 wall=cube('Warm cream rear plaster',(0,1.69,0),(6.58,3.22,.16),'plaster',.02)
 cut=p.arch_solid('Mine entrance wall aperture',2.16,.075,1.70,.66,1.0,0,'iron');cut.location.x=-.30;p.b.boolean_cut(wall,cut)
 for x in [-3.19,3.19]:cube('Rear timber upright',(x,1.65,.10),(.20,3.3,.26),'oak',.045)
 cube('Rear upper beam',(0,3.27,.06),(6.75,.26,.28),'oak',.055)
 for x,w in [(-2.35,1.55),(2.0,2.35)]:cube('Rear skirting clear of mine',(x,.22,.11),(w,.20,.12),'oak_light',.02)


def mine():
 begin('mine_entrance',(-.30,.082,-2.72),collision=[{'at':[0,1.18,.03],'size':[2.72,2.36,.55]}])
 # Closed rear cap, floor and irregular side stones make a short, deep-looking recess.
 p.arch_solid('Deep charcoal mine recess',2.18,0,1.70,.66,.035,-.42,'302C2A')
 cube('Dark mine floor',(0,.018,-.18),(2.18,.035,.51),'66594B',.008)
 for side in [-1,1]:
  for j in range(5):
   y=.23+j*.43;x=side*(1.15+random.uniform(-.04,.04))
   rock('Rock jamb %s %s'%(side,j),(x,y,.01),(.49,.52,.51),['92968C','A5A293','858B80'][j%3],2)
 for j in range(7):
  a=math.pi*j/6;rock('Crown stone %02d'%j,(1.14*math.cos(a),1.72+.62*math.sin(a),.0),(.50,.52,.50),['A5A293','92968C','B1AA98'][j%3],2)
 for x in [-.99,.99]:cube('Rough mine timber jamb',(x,1.08,.20),(.21,2.16,.25),'oak_edge',.045)
 cube('Heavy lintel',(0,2.25,.20),(2.54,.25,.31),'oak',.05)
 # X boards occupy two depth planes with a nailed crossing, avoiding z-fighting.
 for idx,(a,b) in enumerate([((-.94,.35,.37),(.94,2.17,.37)),((-.94,2.17,.53),(.94,.35,.53))]):
  beam('Closed mine cross brace '+str(idx),a,b,.21,.16,'oak')
  for t in [.08,.50,.92]:
   v=Vector(a).lerp(Vector(b),t);ellipsoid('Iron brace bolt',(v.x,v.y,v.z+.09),(.062,.062,.024),'iron_edge',10,6)
 for i in range(8):
  x=-1.02+i*.29;ellipsoid('Sparse moss on lintel',(x,2.397,.21),(.22,.045,.24),'sage_dark' if i%2 else 'sage',10,6)
 for j in range(5):
  z=.49-j*.22;cube('Old rail sleeper',(0,.034,z),(1.15,.068,.12),'oak_dark',.018)
 for x in [-.39,.39]:cube('Mine iron rail',(x,.092,-.02),(.045,.048,1.19),'iron_edge',.009)
 # Cart remains behind the crossed timbers. Open box and four visible wheels.
 for x in [-.29,.29]:
  for z in [-.27,.14]:
   o=cylinder('Cart iron wheel',(x,.22,z),.12,.065,'iron_edge',vertices=12);o.rotation_euler.y=math.pi/2
 cube('Wooden cart bottom',(0,.34,-.06),(.65,.09,.57),'oak_edge',.02)
 for j in range(3):
  y=.41+j*.105
  for x in [-.34,.34]:cube('Cart side boards',(x,y,-.06),(.055,.095,.65),'oak',.012)
  for z in [-.37,.25]:cube('Cart end boards',(0,y,z),(.72,.095,.055),'oak',.012)
 for x in [-.33,.33]:
  for z in [-.36,.24]:cube('Cart iron corner',(x,.52,z),(.05,.40,.05),'iron_edge',.006)
 for i in range(8):rock('Cart ore',(random.uniform(-.22,.22),.65+random.uniform(0,.07),random.uniform(-.23,.12)),(.20,.23,.20),['989A92','7B807C','B0AA9B'][i%3])
 for side in [-1,1]:
  x=side*1.20-.30;y=2.0;z=-1.96
  reuse('mine_lantern_'+str(side),'forge_lantern',(x,y,z));reuse('mine_lantern_glow_'+str(side),'lantern_glow',(x,y,z))
  begin('mine_lantern_hanger_'+str(side),(x,y,z))
  tube('Wall lantern bracket',[(0,.43,-.58),(0,.62,-.58),(0,.62,.02),(0,.52,.02)],.025,'iron_edge',8)
  tube('Closed suspension ring',[(.042*math.sin(a),.51+.045*math.cos(a),.02) for a in [j*math.tau/16 for j in range(17)]],.013,'iron_edge',6)


def stove():
 begin('hearth_stones',(-2.28,.083,-.62))
 pts=[(-.64,-.85),(.57,-.87),(.77,-.55),(.67,-.16),(.81,.17),(.56,.85),(.04,.91),(-.56,.75),(-.73,.32)]
 polygon_slab('Irregular grey hearth slab',pts,0,.055,'9A9B92')
 for a,b in [((-.5,-.18),(.67,-.27)),((-.18,-.84),(-.08,.85))]:
  dx=b[0]-a[0];dz=b[1]-a[1];l=math.hypot(dx,dz);ox=-dz/l*.003;oz=dx/l*.003
  mesh('Fine slab joint',[(a[0]-ox,.0551,a[1]-oz),(a[0]+ox,.0551,a[1]+oz),(b[0]+ox,.0551,b[1]+oz),(b[0]-ox,.0551,b[1]-oz)],[(0,1,2,3)],'777C76')
 begin('grilling_stove',(-2.78,.138,-.62),90,collide([.87,1.18,.59],[0,.59,0]))
 for x in [-.33,.33]:
  for z in [-.21,.21]:cube('Stove square metal foot',(x,.18,z),(.09,.36,.09),'iron',.015)
 cube('Stove ash drawer',(0,.39,0),(.83,.23,.58),'iron',.025)
 cube('Drawer pull',(0,.39,.315),(.22,.034,.048),'iron_edge',.01)
 cube('Stove firebox back',(0,.73,-.265),(.85,.50,.05),'iron',.01)
 for x in [-.40,.40]:cube('Stove firebox side',(x,.73,0),(.06,.50,.55),'iron',.01)
 cube('Stove coal tray',(0,.54,0),(.85,.07,.57),'iron_edge',.015)
 for i in range(9):tube('Grill bar',[(-.35+i*.088,.68,-.22),(-.35+i*.088,.68,.24)],.014,'iron_edge',6)
 # A low open hood, unlike the forbidden masonry forge.
 mesh('Sloping metal stove hood',[(-.47,1.03,-.31),(.47,1.03,-.31),(.47,1.03,.33),(-.47,1.03,.33),(-.15,1.32,-.16),(.15,1.32,-.16),(.15,1.32,.12),(-.15,1.32,.12)],[(0,1,2,3),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0),(4,7,6,5)],'iron_edge')
 cube('Vertical dark chimney',(0,2.04,-.07),(.22,1.44,.21),'iron',.018)
 for y in [1.38,2.40,2.75]:cube('Chimney collar',(0,y,-.07),(.26,.075,.25),'iron_edge',.008)
 for j,z in enumerate([-.10,.13]):
  ellipsoid('Salt grilled fish body '+str(j),(0,.76,z),(.61,.13,.14),'D7BB88',16,8)
  mesh('Fish tail '+str(j),[(-.26,.76,z),(-.43,.77,z-.12),(-.43,.77,z+.12),(-.26,.79,z)],[(0,1,2),(1,3,2),(0,3,1),(0,2,3)],'C29B63')
  ellipsoid('Fish eye '+str(j),(.23,.813,z+.037),(.024,.009,.024),'6D5944',8,6)
  for x in [-.15,-.03,.09]:tube('Fish grill mark',[(x,.815,z-.037),(x+.025,.824,z+.04)],.008,'9B7447',5)
 begin('stove_embers',(-2.78,.138,-.62),90)
 for i in range(16):rock('Warm ember',(random.uniform(-.33,.33),.60,random.uniform(-.22,.22)),(.10,.06,.10),['C75E2D','F1A04E','E0B776'][i%3])
 begin('firewood',(-2.53,.082,-1.85),collision=collide([.64,.53,.55]))
 for j in range(3):
  for i in range(3-j):
   x=-.2+i*.20+j*.10;y=.10+j*.16
   o=cylinder('Stacked cut firewood',(x,y,0),.095,.52,'oak_edge',vertices=10);o.rotation_euler.x=math.pi/2
   o=cylinder('Light cut log end',(x,y,.263),.078,.012,'oak_light',vertices=10);o.rotation_euler.x=math.pi/2
 begin('square_stool',(-2.17,.139,-.05),15,collide([.42,.48,.42]))
 cube('Little square stool seat',(0,.44,0),(.44,.08,.43),'oak_light',.025)
 for x in [-.14,.14]:
  for z in [-.14,.14]:beam('Square stool leg',(x*1.2,0,z*1.2),(x,.43,z),.065,.065,'oak')


def sorting():
 reuse('sorting_bench','back_tool_bench',(2.0,.082,-2.44),scale=(1.16,1,1.07))
 # Source top is 0.938? measured from evaluated source below; dressing derives it.
 k=p.KITS['sorting_bench'];bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();inv=k['root'].matrix_world.inverted()
 top=max((inv@o.matrix_world@Vector(v)).z for o in k['objects'] for v in o.evaluated_get(deps).bound_box)
 k['collision']=collide([1.67,top,.62])
 begin('sorting_tray',(2.0,.082+top,-2.44))
 cube('Sorting tray base',(0,.032,-.07),(1.43,.064,.42),'oak_edge',.014)
 for z in [-.275,.135]:cube('Tray long lip',(0,.11,z),(1.43,.16,.024),'oak',.008)
 for x in [-.70,-.235,.235,.70]:cube('Tray compartment divider',(x,.11,-.07),(.022,.16,.40),'oak',.006)
 for slot,col in [(-.47,'858D8B'),(0,'4D5454'),(.47,'64A38C')]:
  for i in range(3):rock('Verdigris copper ore' if slot>0 else 'Sorted ore',(slot+random.uniform(-.10,.10),.19,-.07+random.uniform(-.07,.07)),(.18,.24,.18),col)
 begin('quartz_and_tools',(2.0,.082+top,-2.44))
 for i in range(5):
  x=.42+i*.06;z=.23+(i%2)*.035;h=.18+.09*(i%3)
  o=cylinder('Pink white quartz crystal',(x,h/2+.02,z),.054,h,'E9D4CE' if i%2 else 'F2E4DC',vertices=5)
  o.rotation_euler.y=(-.2+i*.1)
  bpy.ops.mesh.primitive_cone_add(vertices=5,radius1=.054,radius2=0,depth=.08,location=p.v((x,h+.06,z)));p.b.finish(bpy.context.object,'Quartz crystal pointed termination','F2E4DC')
 for x in [-.55,-.28]:rock('Loose work stone',(x,.05,.22),(.10,.10,.08),'A5A69D')
 tube('Small mineral hammer handle',[(-.05,.035,.25),(.20,.035,.23)],.018,'oak_light',8)
 cube('Small mineral hammer head',(.19,.047,.23),(.06,.07,.15),'iron_edge',.01)
 tube('Small chisel',[(-.19,.04,.20),(-.01,.04,.32)],.014,'iron_edge',6)
 reuse('round_stool','forge_stool',(2.36,.0878,-1.65))['collision']=collide([.56,.661,.56])
 reuse('rock_crate','metal_ingot_crate',(-2.29,.082,1.66),scale=(.70,.90,.85),remove_names=('Stacked iron ingot',))
 current('rock_crate')
 for i in range(8):rock('Crate grey rock',(random.uniform(-.25,.25),.36+random.uniform(-.03,.08),random.uniform(-.18,.18)),(.23,.25,.22),['89958A','A0A79E','778477'][i%3])
 reuse('salt_crate','left_floor_crate',(-2.64,.082,-2.40),remove_names=('Crated spare steel',))
 current('salt_crate')
 for i in range(9):rock('Pink rock salt',(random.uniform(-.23,.23),.46+random.uniform(-.02,.10),random.uniform(-.15,.15)),(.14,.19,.15),'EBD8CB' if i%2 else 'E3C4B8')
 reuse('rock_barrel','quench_barrel',(2.70,.082,.65),scale=(.69,.72,.69),remove_names=('Quenching water',))
 current('rock_barrel')
 for i in range(9):rock('Barrel round stone',(random.uniform(-.20,.20),.62+random.uniform(0,.06),random.uniform(-.20,.20)),(.20,.22,.19),'929A96')
 reuse('wood_stump','stump',(2.66,.082,1.66),scale=(.58,.55,.58))
 begin('low_cabinet',(2.64,.082,-.55),collision=collide([.62,.72,.58]))
 cube('Low cabinet box',(0,.37,0),(.60,.65,.55),'oak',.035)
 cube('Low cabinet thick top',(0,.72,0),(.68,.08,.62),'oak_light',.02)
 for x in [-.15,.15]:
  cube('Small cabinet door',(x,.37,.286),(.28,.52,.045),'oak_light',.014)
  ellipsoid('Cabinet bronze knob',(x*.35,.40,.321),(.045,.045,.035),'brass',10,6)
 # Four lanterns total: two mine, one shelf, one cabinet.
 reuse('cabinet_lantern','forge_lantern',(2.64,1.05201,-.55));reuse('cabinet_lantern_glow','lantern_glow',(2.64,1.05201,-.55))


def wall_details():
 reuse('left_shelf','right_wall_shelf',(-2.97,1.96,.78),90,remove_names=('Glazed ceramic mug','Tea surface','Mug handle','Small painted leaf'))
 current('left_shelf');p.mug((-.22,.06,.015),'iron_edge')
 reuse('shelf_lantern','forge_lantern',(-2.90,2.22501,.51));reuse('shelf_lantern_glow','lantern_glow',(-2.90,2.22501,.51))
 begin('hanging_pan',(-3.04,1.26,.88),90)
 # pan disk faces room; handle vertically upward.
 o=cylinder('Cast iron frying pan',(0,0,.045),.18,.045,'iron',vertices=24);o.rotation_euler.x=math.pi/2
 tube('Pan rim',[(.18*math.cos(a),.18*math.sin(a),.075) for a in [i*math.tau/24 for i in range(25)]],.014,'iron_edge',6)
 tube('Pan handle',[(0,.17,.04),(0,.48,.04)],.031,'iron_edge',8)
 begin('garlic_and_herbs',(-3.03,2.34,-1.45),90)
 for x in [-.19,.19]:tube('Bound hanging cord',[(x,.17,0),(x,-.12,.03)],.013,'oak_light',6)
 for j in range(5):
  ellipsoid('Hanging garlic bulb',(-.19+(.035 if j%2 else -.035),-.02-j*.083,.07),(.11,.10,.10),'linen',10,6)
 for j in range(12):
  x=.19+random.uniform(-.15,.15)
  tube('Dried grass stalk',[(.19,.08,0),(.19+(x-.19)*.4,-.13,.02),(x,-.54+random.uniform(-.03,.06),.04)],.009,'B8A06C',5)
 begin('mine_plan',(1.45,2.09,-2.94))
 cube('Plain parchment mine plan',(0,0,0),(.67,.65,.03),'DCC79C',.015)
 for points in [[(-.26,.14),(-.12,.03),(.02,.12),(.21,.09)],[(.02,.12),(.06,.27)],[(.02,.12),(.06,-.05),(.20,-.20)],[(-.12,.03),(-.16,-.18),(-.03,-.25)],[(.06,-.05),(.27,-.04)]]:
  tube('Line only tunnel diagram',[(x,y,.018) for x,y in points],.009,'9B7052',5)
 for x in [-.29,.29]:
  for y in [-.28,.28]:ellipsoid('Map pin',(x,y,.025),(.027,.027,.016),'brass',8,6)
 begin('wall_pickaxe',(2.12,1.80,-2.87))
 tube('Pickaxe wooden haft',[(0,-.37,0),(0,.39,0)],.031,'oak_edge',8)
 tube('Pickaxe curved iron head',[(-.32,.26,.01),(-.20,.40,.01),(0,.43,.01),(.20,.37,.01),(.32,.23,.01)],.045,'iron_edge',8)
 begin('wall_short_axe',(2.66,1.94,-2.87))
 tube('Short axe haft',[(0,-.30,0),(.025,.24,0)],.033,'oak_edge',8)
 mesh('Short broad axe blade',[(-.025,.12,-.045),(-.025,.28,-.045),(.25,.33,-.012),(.25,.03,-.012),(-.025,.12,.045),(-.025,.28,.045),(.25,.33,.012),(.25,.03,.012)],[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],'iron_edge')
 begin('coiled_rope',(2.79,1.28,-2.94))
 for j in range(4):tube('Coiled hemp rope',[(math.cos(a)*(.15+j*.022),math.sin(a)*(.24+j*.018),.02+j*.009) for a in [i*math.tau/32 for i in range(33)]],.015,'BD925B',6)
 tube('Rope loose ends',[(.03,.24,.02),(.17,-.30,.04),(.12,-.48,.06)],.015,'BD925B',6)
 # Exact game mesh, only rigid placement changed. Keep its hair too: direct reuse.
 begin('ivo_wall_helmet',(2.65,2.65,-2.57))
 path=ROOT/'output/minehut-308/ivo_runtime.glb';assert path.exists(),'Run prepare_mine_hut_308.py --helmet first'
 bpy.ops.import_scene.gltf(filepath=str(path));objs=list(bpy.context.selected_objects);meshes=[o for o in objs if o.type=='MESH'];bpy.context.view_layer.update()
 allv=[o.matrix_world@v.co for o in meshes for v in o.data.vertices];lo=Vector(tuple(min(v[i] for v in allv) for i in range(3)));hi=Vector(tuple(max(v[i] for v in allv) for i in range(3)));center=(lo+hi)/2
 for o in meshes:
  o.data.transform(o.matrix_world);o.data.transform(Matrix.Translation(-center));o.parent=None;o.matrix_world=Matrix.Identity(4)
  for c in list(o.users_collection):c.objects.unlink(o)
  p.KITS['ivo_wall_helmet']['collection'].objects.link(o);o.parent=p.KITS['ivo_wall_helmet']['root'];o.name='Ivo original helmet and short hair / exact runtime geometry';p.KITS['ivo_wall_helmet']['objects'].append(o)
 for o in objs:
  if o not in meshes:bpy.data.objects.remove(o,do_unlink=True)
 # Pin the textured dependency within source, not another runtime atlas.
 for o in meshes:
  for mat in o.data.materials:
   if mat and mat.use_nodes:
    for node in mat.node_tree.nodes:
     if node.type=='TEX_IMAGE' and node.image:node.image.pack()
 tube('Helmet hanging iron peg',[(0,-.04,-.445),(0,-.04,-.24),(0,.03,-.24)],.015,'iron_edge',8)
 PROVENANCE.append({'asset':'ivo_wall_helmet','commit':FARM,'source':'assets/avatar/parts/hairhat_npc_ivo_scene.tscn','geometry':'exact mesh and UV, rigid transform only; texture baked into single room atlas'})


def sacks_and_rug():
 begin('tied_sack',(-1.94,.082,-1.72),collision=collide([.35,.58,.35]))
 lathe('Tied burlap sack',(0,0,0),[(0,.13),(.08,.19),(.30,.19),(.45,.085),(.51,.07),(.58,.12)],'C5A478',16)
 for y in [.45,.47]:tube('Sack binding',[(.079*math.cos(a),y,.079*math.sin(a)) for a in [i*math.tau/20 for i in range(21)]],.012,'oak_edge',6)
 begin('stone_sack',(1.97,.082,.76),collision=collide([.48,.58,.48]))
 lathe('Open beige stone bag',(0,0,0),[(0,.16),(.08,.22),(.33,.23),(.52,.18),(.55,.18),(.55,.155),(.44,.15)],'D9C6A4',20)
 for i in range(8):rock('Bag rounded stone',(random.uniform(-.10,.10),.52+random.uniform(-.02,.05),random.uniform(-.10,.10)),(.10,.12,.11),'B6B3A7')
 begin('white_hide_rug',(0,.084,.65))
 # Whole asymmetrical hide silhouette with neck, legs and soft scalloped edges.
 pts=[(-.16,-.76),(-.30,-.77),(-.36,-.55),(-.60,-.52),(-.83,-.70),(-1,-.65),(-.95,-.48),(-.73,-.27),(-.70,-.06),(-.76,.17),(-.96,.40),(-1,.59),(-.82,.71),(-.62,.58),(-.37,.51),(-.21,.67),(-.11,.8),(.08,.78),(.22,.63),(.34,.50),(.63,.58),(.84,.71),(.98,.56),(.95,.38),(.75,.17),(.70,-.08),(.76,-.29),(.98,-.5),(.95,-.69),(.77,-.74),(.55,-.54),(.33,-.53),(.2,-.72)]
 # One continuous softly pillowed skin, with shallow folds and a lobed hide perimeter.
 vs=[(0,.052,0)];fs=[];n=len(pts)
 for ring in range(1,6):
  r=ring/5
  for j,(x,z) in enumerate(pts):vs.append((x*r,.016+.036*(1-r*r)+.004*math.sin(j*1.9)*r,z*r))
 for j in range(n):fs.append((0,1+j,1+(j+1)%n))
 for ring in range(4):
  for j in range(n):fs.append((1+ring*n+j,1+ring*n+(j+1)%n,1+(ring+1)*n+(j+1)%n,1+(ring+1)*n+j))
 mesh('Single soft white hide with natural folds',vs,fs,'E8DCD2',smooth=True)
 for side in [-1,1]:
  begin('entry_plant_'+str(side),(side*1.14,.082,2.54),collision=collide([.5,.58,.5]))
  plant(scale=1.1)
 begin('exit_steps',(0,0,3.25),collision=[{'at':[0,-.06,0],'size':[1.45,.28,.65]}])
 polygon_slab('Exit threshold stone',[(-.73,-.31),(.70,-.31),(.77,.17),(.50,.32),(-.58,.28),(-.80,.05)],-.20,.28,'A3A39A')
 polygon_slab('Outer stone step',[(-.57,.29),(.60,.30),(.69,.68),(.38,.83),(-.48,.78),(-.68,.58)],-.31,.23,'949A93')
 begin('exit_pickaxe_sign',(1.16,.082,3.02),-5,collide([.76,1.11,.18],[0,.555,0]))
 cube('Sign short post',(0,.34,0),(.13,.68,.14),'oak_edge',.022)
 cube('Wood pictogram sign',(0,.80,0),(.76,.58,.09),'oak',.04)
 cube('Pictogram darker inset',(0,.80,.053),(.61,.43,.022),'oak_dark',.035)
 for side in [-1,1]:
  a=(side*-.16,.66,.072);b=(side*.14,.94,.072);tube('Crossed pick haft',[a,b],.020,'linen',7)
  tube('Crossed pick head',[(side*.01,.99,.072),(side*.14,.97,.072),(side*.24,.86,.072)],.026,'linen',7)


def pad_atlas():
 # Reload the saved PNG: Cycles' live bake image can retain unextended edge tiles.
 # Only exactly empty texels change; authored/baked pixels remain byte-identical.
 path=ROOT/'assets/rooms/mine_hut/room_albedo_ao.png'
 tex=bpy.data.images.load(str(path),check_existing=False)
 pixels=np.array(tex.pixels[:],dtype=np.float32).reshape((2048,2048,4))
 valid=pixels[:,:,:3].max(2)>0
 original=valid.copy();count=0
 for _ in range(128):
  if valid.all():break
  sums=np.zeros_like(pixels);counts=np.zeros((2048,2048),dtype=np.float32)
  for axis,shift in [(0,1),(0,-1),(1,1),(1,-1)]:
   mask=np.roll(valid,shift,axis)
   if axis==0:mask[0 if shift==1 else -1,:]=False
   else:mask[:,0 if shift==1 else -1]=False
   sums+=np.roll(pixels,shift,axis)*mask[:,:,None];counts+=mask
  fill=~valid & (counts>0);pixels[fill]=sums[fill]/counts[fill,None];valid|=fill;count+=int(fill.sum())
 assert valid.all(),'Atlas padding did not converge'
 tex.pixels.foreach_set(pixels.ravel());tex.update();tex.filepath_raw=str(path);tex.file_format='PNG';tex.save()
 print('ATLAS_EMPTY_TEXELS_EXTENDED',count,flush=True)

def build():
 p.start('mine_hut','SGODOT-308 / Stark approved v1.1');random.seed(308)
 p.b.PALETTE.update(PAL)
 shell();mine();stove();sorting();wall_details();sacks_and_rug()
 p.BAKE_SETTINGS.update(ao_distance=.36,ao_strength=.32,floor_ao_strength=.24)
 # Default authored perspective matches other isometric room kits; gameplay width is explicit.
 yaw=45;pitch=43;target=Vector((0,1.25,0));off=Vector((math.sin(math.radians(yaw))*math.cos(math.radians(pitch)),math.sin(math.radians(pitch)),math.cos(math.radians(yaw))*math.cos(math.radians(pitch))))*15
 lamps=[{'name':n,'position':at,'color':'FFD298','energy':e,'range':r} for n,at,e,r in [('mine_left',[-1.50,2.02,-1.80],1.0,2.0),('mine_right',[.90,2.02,-1.80],1.0,2.0),('shelf',[-2.65,2.22,.51],.85,1.8),('cabinet',[2.64,1.05,-.39],.85,1.8),('stove',[-2.35,.90,-.62],1.15,1.7)]]
 p.MANIFEST_EXTRA.update({'revision':'SGODOT-308 v1','floor_y':.082,'footprint':[6.8,6.4],
  'local_lights':lamps,'material_overrides':{n:{'emission':'FFD095','emission_use_atlas':True,'emission_energy':.7} for n in p.KITS if 'glow' in n or n=='stove_embers'},
  'suggested_anchors':{n:{'position':at,'yaw_degrees':yaw if n=='npc_ivo' else 0} for n,at in [('npc_ivo',[1.40,.082,-.84]),('stand_ivo',[.80,.082,.05]),('spawn',[0,.082,2.55]),('exit',[0,.082,3.08]),('badge_exit',[0,.70,3.08])]},
  'interactions':['npc_ivo','exit'],'mine_enterable':False,'nameplate_clearance':{'center':[1.4,2.18,-.84],'size':[1.0,.55,.65]},
  'gameplay_camera':{'pitch_degrees':43,'yaw_degrees':45,'size':6.72,'target':[0,1.15,0],'native_width':360},
  'spawn':[0,.082,2.55],'boundaries':[{'name':'front_left','at':[-1.99,1,3.22],'size':[2.48,2,.08]},{'name':'front_right','at':[1.99,1,3.22],'size':[2.48,2,.08]},{'name':'cut_right','at':[3.32,1,0],'size':[.08,2,6.4]}],
  'source_dependencies':{'art_base':'154ce6421448e26e42ee225ba7018638ae756394','avatar_commit':FARM},
  'reference':'SGODOT-308_stark-minehut.png + SGODOT-308_huowu-annot.png; checklist v1.1 authoritative'})
 lighting={'background':'D8CBB8','ambient_color':'EEE4D3','ambient':.55,'sun_color':'FFE5C9','sun':.65,'sun_position':[-2,7,5]}
 p.finalize({'position':list(target+off),'target':list(target),'size':12.4,'pitch_degrees':43,'yaw_degrees':45},lighting)
 (SOURCE/'reuse_provenance.json').write_text(json.dumps({'source_blend_sha256':hashlib.sha256((ROOT/'tools/art/source/blacksmith_shop/blacksmith_shop.blend').read_bytes()).hexdigest(),'reused':PROVENANCE},indent=2)+'\n')
 p.complete()
 if '--geometry-only' not in sys.argv:pad_atlas()
if __name__=='__main__':build()
