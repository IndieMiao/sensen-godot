"""424 repeat props. Run under flock ~/gs66-render.lock. Godot metres, Y up, +Z front.
Exports ten single-mesh/single-surface local-pivot modules; never rewrites island layout.
"""
from pathlib import Path
import hashlib,json,math,struct,sys
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/art'))
import build_decor_assets as K
SRC=ROOT/'tools/art/source/alcatraz_props_424';OUT=ROOT/'assets/landmarks/alcatraz_island'
PALETTE={'wood':'BD8D51','wood_light':'DBAD69','wood_edge':'A87946','paint':'536F6A','paint_light':'75908A',
 'stone':'DBC8AA','stone_top':'F0DFC2','stone_side':'C6B293','soil':'7F7450',
 'globe':'FFF2C9','globe_top':'FFF9DE','bark':'98754B','bark_light':'B59260',
 'leaf_dark':'6F873E','leaf':'90A448','leaf_light':'AABC5A','yellow':'ECCB59','white':'FFF0D2','lilac':'B8A5CF','pollen':'C8A453','bin_dark':'5E695B'}
LAYOUT=json.loads((SRC/'reference/layout-34df9c0b.json').read_text())

def box(name,at,size,color,bevel=0):return K.box(name,at,size,color,bevel)
def tube(name,a,b,r,color,n=6,top=None):return K.rod(name,a,b,r,color,segments=n,top=top)
def surface_colors(o,roles):
 for role in roles:o.data.materials.append(K.MATS[role])
 for p in o.data.polygons:
  if p.normal.z>.5:p.material_index=1
  elif p.normal.z<-.5 and len(roles)>1:p.material_index=2
def bench():
 # Width exactly 1.50; three rounded seat boards top out at Y=.45.
 for i,z in enumerate([-.17,-.01,.15]):box(f'Bench / rounded seat plank {i+1}',(0,.4125,z),(1.5,.075,.145),'wood_light',.008)
 for i,y in enumerate([.64,.83]):box(f'Bench / back board {i+1}',(0,y,-.235),(1.5,.16,.055),'wood_light')
 for side in [-1,1]:
  for z in [-.16,.16]:box(f'Bench / leg {side}/{z}',(side*.56,.18,z),(.065,.36,.07),'paint')
  box(f'Bench / back upright {side}',(side*.56,.64,-.24),(.06,.55,.065),'paint')
  box(f'Bench / arm {side}',(side*.64,.62,-.015),(.075,.055,.47),'wood')
def lamp():
 # Ordinary park globe, opaque warm ivory, no special gameplay beacon.
 K.lathe('Lamp / stepped foot',[(.19,0),(.19,.06),(.13,.10),(.10,.27),(.065,.34)],'paint',segments=8)
 tube('Lamp / slender painted post',(0,.30,0),(0,2.97,0),.061,'paint',8,.045)
 K.lathe('Lamp / globe collar',[(.075,2.88),(.11,2.92),(.14,2.96),(.12,3.0)],'paint_light',segments=8)
 K.ellipsoid('Lamp / cream frosted globe',(0,3.235,0),(.46,.53,.46),'globe',segments=10,rings=6)
def rail_straight():
 for side in [-1,1]:
  o=box(f'Park stone rail / square post {side}',(side*.92,.5,0),(.16,1,.18),'stone');surface_colors(o,['stone_top','stone_side'])
 for i,y in enumerate([.50,.88]):
  o=box(f'Park stone rail / horizontal rail {i+1}',(0,y,0),(2,.12,.12),'stone');surface_colors(o,['stone_top','stone_side'])
def rail_corner():
 o=box('Park rail corner / origin post',(0,.5,0),(.18,1,.18),'stone');surface_colors(o,['stone_top','stone_side'])
 for y in [.50,.88]:
  o=box(f'Corner arm +X / {y}',(.25,y,0),(.5,.12,.12),'stone');surface_colors(o,['stone_top','stone_side'])
  o=box(f'Corner arm +Z / {y}',(0,y,.25),(.12,.12,.5),'stone');surface_colors(o,['stone_top','stone_side'])
def curb():
 # Extruded section keeps exactly X +/-1 for scaled flat and sloping junctions.
 cross=[(-.09,0),(.09,0),(.09,.22),(.06,.25),(-.06,.25),(-.09,.22)]
 points=[(x,y,z) for x in [-1,1] for z,y in cross];n=len(cross)
 faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 o=K.mesh('Curb / 2m limestone with bevelled top',points,faces,'stone')
 o.data.materials.append(K.MATS['stone_top']);o.data.materials.append(K.MATS['stone_side'])
 for p in o.data.polygons:p.material_index=1 if p.index in [4,5,6] else 2 if p.index<2 else 0
def crown(name,at,size,color):
 return K.ellipsoid(name,at,size,color,segments=10,rings=5)
def cushion(name,at,size,color):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1)
 o=bpy.context.object;o.location=K.v(at);o.scale=(size[0]/2,size[2]/2,size[1]/2)
 return K.finish(o,name,color,True)
def tree_a():
 # One root and swept woody silhouette; flat overlapping canopies lean to +X.
 trunk=[(0,0,0),(.18,1.6,.02),(.60,3.15,0),(1.10,4.35,0)]
 for i,(a,b) in enumerate(zip(trunk,trunk[1:])):tube(f'Cypress / bent trunk segment {i+1}',a,b,[.24,.18,.12][i],'bark',7,[.18,.12,.065][i])
 for i,(start,end) in enumerate([((.3,2.1,0),(-.35,4.1,.55)),((.60,3.15,0),(1.85,4.6,-.25)),((.60,3.15,0),(.55,4.8,-.75))]):tube(f'Cypress / wind branch {i+1}',start,end,.09,'bark_light',5,.035)
 for i,(at,size) in enumerate([((.65,4.68,0),(3.8,1.12,2.75)),((1.55,5.38,-.12),(3.6,1.25,2.65)),((2.0,5.92,-.08),(2.65,.96,2.12))]):crown(f'Cypress / swept crown {i+1}',at,size,['leaf_dark','leaf','leaf_light'][i])
 # Offset edge lobes break the tiered oval silhouette into a coastal wind-swept canopy.
 crown('Cypress / windward edge foliage',(-.65,4.60,.24),(1.50,.90,1.48),'leaf')
 crown('Cypress / leeward edge foliage',(2.62,5.27,.40),(1.70,.94,1.65),'leaf_light')
def tree_b():
 tube('Round tree / single trunk',(0,0,0),(0,3.70,0),.22,'bark',8,.10)
 for i,end in enumerate([(-1.0,4.3,0),(.95,4.5,.45),(.12,4.7,-.9)]):tube(f'Round tree / branch {i+1}',(0,2.7,0),end,.085,'bark_light',5,.035)
 for i,(at,size) in enumerate([((-.75,4.50,0),(2.70,2.0,2.60)),((.70,4.75,.20),(2.80,2.10,2.65)),((0,5.35,-.18),(2.65,1.85,2.55))]):crown(f'Round tree / rounded canopy {i+1}',at,size,['leaf_dark','leaf','leaf_light'][i])
def flower(name,at,color):
 # Compact solid six-petal bloom, silhouette visible without alpha cards.
 x,y,z=at;n=24
 points=[(x,y+.025,z),(x,y-.012,z)]
 for j in range(n):
  a=j*math.tau/n;r=.075 if j%4==0 else .16
  points.append((x+r*math.cos(a),y,z+r*math.sin(a)))
 o=K.mesh(name,points,[(0,2+j,2+(j+1)%n) for j in range(n)]+[(1,2+(j+1)%n,2+j) for j in range(n)],color,True)
 cushion(name+' / warm centre',(x,y+.035,z),(.07,.045,.07),'pollen')
def flowerbed():
 # True 1.70 x1.70 square bed: low planter makes new footprint explicit to integration.
 for side in [-1,1]:
  box(f'Flowerbed / east-west rim {side}',(0,.14,side*.78),(1.70,.28,.14),'stone')
  box(f'Flowerbed / north-south rim {side}',(side*.78,.14,0),(.14,.28,1.42),'stone')
 box('Flowerbed / soil',(0,.16,0),(1.40,.16,1.40),'soil')
 for i,(x,z) in enumerate([(-.43,-.39),(.42,-.39),(-.42,.43),(.40,.40),(0,0)]):
  cushion(f'Flowerbed / low foliage cushion {i+1}',(x,.35,z),(.62,.36,.59),'leaf' if i%2 else 'leaf_light')
 for i,(x,z,y) in enumerate([(-.42,-.4,.55),(.4,-.35,.53),(-.37,.4,.56),(.4,.43,.52),(0,.02,.60)]):flower(f'Flowerbed / bloom {i+1}',(x,y,z),['white','yellow','lilac','white','yellow'][i])
def bin_prop():
 # Small stone litter bin with a dark side opening; never an interactive chest.
 box('Bin / stone pedestal',(0,.035,0),(.45,.07,.45),'stone_side')
 for side in [-1,1]:box(f'Bin / side {side}',(side*.18,.385,0),(.09,.70,.43),'stone')
 box('Bin / back',(0,.385,-.17),(.27,.70,.09),'stone')
 box('Bin / front lower',(0,.245,.17),(.27,.42,.09),'stone')
 box('Bin / lintel',(0,.66,.17),(.27,.12,.09),'stone')
 box('Bin / dark interior',(0,.50,-.04),(.27,.31,.05),'bin_dark')
 box('Bin / cap',(0,.765,0),(.47,.07,.47),'stone_top',.012)
def sign():
 # Blank park information board, no highlight ring, arrow, badge or prompt icon.
 box('Sign / simple timber post',(0,.61,-.04),(.10,1.22,.10),'wood_edge')
 box('Sign / quiet framed board',(0,1.255,0),(.76,.49,.09),'wood')
 box('Sign / completely blank muted panel',(0,1.255,.049),(.66,.38,.014),'stone_side')

BUILDERS=[('alc_bench',bench,300),('alc_lamp',lamp,300),('alc_rail_straight',rail_straight,60),('alc_rail_corner',rail_corner,60),('alc_curb',curb,60),('alc_tree_a',tree_a,600),('alc_tree_b',tree_b,600),('alc_flowerbed',flowerbed,500),('alc_bin',bin_prop,300),('alc_sign',sign,300)]
def main():
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 K.OUT=OUT;OUT.mkdir(parents=True,exist_ok=True)
 for role,value in PALETTE.items():
  m=bpy.data.materials.new(role);m.diffuse_color=(*K.rgb(value),1);m.use_nodes=True;p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=m.diffuse_color;p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18;K.MATS[role]=m
 material=bpy.data.materials.new('Farm matte vertex paint');material.use_nodes=True;p=material.node_tree.nodes['Principled BSDF'];p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18
 vc=material.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';material.node_tree.links.new(vc.outputs['Color'],p.inputs['Base Color'])
 entries={}
 for index,(name,build,budget) in enumerate(BUILDERS):
  K.begin(name,[1,1],budget,generator='tools/art/build_alcatraz_props_424.py',author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',pivot='corner post foot; arms +X/+Z .50m' if name=='alc_rail_corner' else 'installation/ground centre',front='+Z',collision='none in GLB; client owns collider sizes')
  build();bpy.context.view_layer.update()
  # Root Y=0 for tapered/tilted tree; root XZ=0 is intentionally kept, even for the windswept crown.
  pts=[o.matrix_world@v.co for o in K.CURRENT.objects for v in o.data.vertices];lowest=min(v.z for v in pts)
  for o in K.CURRENT.objects:o.location.z-=lowest
  entry=K.export_asset(name,K.CURRENT,material)
  path=OUT/(name+'.glb');raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);tail=raw[20+n:];doc['meshes'][0]['name']=name+'_mobile'
  encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
  path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
  entry.update(bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source='tools/art/source/alcatraz_props_424/alcatraz_props.blend',instances_in_layout=sum(p['asset']==name for p in LAYOUT['placements']),material_contract={'vertex_color_is_srgb':False,'roughness':.9,'metallic':0,'specular':.18})
  entries[name]=entry
  for o in K.CURRENT.objects:o.location+=Vector(((index%5)*6,(index//5)*8,0))
  print('ALC_PROP',name,entry['triangles'],entry['bounds'],flush=True)
 data={'author':'赵云','reference_layout_commit':'34df9c0b6af42a85567dfb5318c6717f929a4ab8','palette_srgb':PALETTE,'assets':entries}
 (SRC/'asset_stats.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 # Do not overwrite Marco Polo's island manifest/layout: this manifest only describes this prop kit.
 (OUT/'props_manifest.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'alcatraz_props.blend'),compress=True)
if __name__=='__main__':main()
