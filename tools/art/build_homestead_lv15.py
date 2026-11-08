"""SGODOT-440. Two whole farmhouses, metres / Y-up / +Z front.
Blender --background --factory-startup --python /absolute/path/to/this_file.py
Only the two new GLBs and own source/manifest are written.
"""
from pathlib import Path
import json,math,sys,random,hashlib
import bpy,bmesh
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_decor_assets as kit
from verify_chef_sign import load_glb,accessor
ROOT=kit.ROOT;SRC=ROOT/'tools/art/source/homestead_440'
sys.path.insert(0,str(SRC))
from export_mesh import export_asset
PALETTE={
 'plaster':'f0edd0','plaster_shade':'d9d4ae','cream':'fff4d2',
 'wood':'a87948','wood_light':'cba067','wood_dark':'675139',
 'green':'437d64','green_light':'6a9b6a','glass':'82c5c6','glass_dark':'548f99',
 'orange':'e7954e','orange_light':'f4ad60','orange_dark':'cf7f40',
 'stone':'a5ad98','stone_light':'c4c6b1','stone_shade':'8e9588',
 'leaf':'6d9a44','leaf_light':'97b75b','leaf_dark':'4e824d',
 'flower':'fff5df','pink':'e68c9e','yellow':'f1ce58','soil':'785c40','roof_dark':'454956'}
B=kit.box;M=kit.mesh

def beam(name,a,b,width,color='wood',depth=None):return kit.beam(name,a,b,width,color,depth=depth,radius=0)

def omit_tile_underside(obj):
 # The solid roof slab already closes the underside. Retain the visible tile
 # tops and all four rims; use the saved triangles on the unseen facades.
 bm=bmesh.new();bm.from_mesh(obj.data)
 bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.normal.z<-.9],context='FACES')
 bm.to_mesh(obj.data);bm.free()

def facade_part(name,origin,normal,offset,size,color,raised=False):
 # Local u is horizontal as seen from outside; v is up; w points out of wall.
 # Wall-backed details omit their buried back face, not a visible house face.
 nx,nz=normal
 def at(u,v,w):return (origin[0]+nz*u+nx*w,origin[1]+v,origin[2]-nx*u+nz*w)
 u,v,w=offset;a,b,depth=size
 corners=[(-a/2,-b/2),(a/2,-b/2),(a/2,b/2),(-a/2,b/2)]
 verts=[at(u+x,v+y,w+depth/2) for x,y in corners]
 faces=[(0,1,2,3)]
 if raised:
  verts += [at(u+x,v+y,w-depth/2) for x,y in corners]
  faces += [(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
 return M(name,verts,faces,color)

def secondary_window(origin,normal,width=.40,height=.42):
 # Same green surround, cream muntins and shutters as the front, with relief
 # only on frame/sill. Flat paint details have no texture or extra surface.
 def p(name,offset,size,color,raised=False):return facade_part(name,origin,normal,offset,size,color,raised)
 p('Side rear green surround',(0,0,.025),(width+.10,height+.10,.05),'green',True)
 p('Side rear blue green pane',(0,0,.052),(width,height,0),'glass')
 p('Side rear vertical muntin',(0,0,.055),(.022,height,0),'cream')
 p('Side rear horizontal muntin',(0,0,.056),(width,.023,0),'cream')
 p('Side rear sky accent',(-width*.22,height*.25,.057),(width*.26,.019,0),'cream')
 p('Side rear sill',(0,-height/2-.045,.025),(width+.14,.06,.075),'wood_light',True)
 for s in [-1,1]:
  p('Side rear green shutter',(s*(width/2+.075),0,.057),(.09,height+.04,0),'green')
  for k in range(3):p('Side rear louvre',(s*(width/2+.075),-height*.28+k*height*.28,.060),(.075,.02,0),'green_light')

def rear_facade(variant):
 normal=(0,-1)
 for x in [-.43,.43]:secondary_window((x,2.62,-.828),normal,.36,.42)
 secondary_window((.44,.82,-.828),normal,.38,.42)
 secondary_window((-.861,2.62,-.15),(-1,0),.40,.40)
 # Closed utility door is facade detail only; no new path, step or interaction.
 origin=(-.38,.54,-.828)
 facade_part('Rear utility door green frame',origin,normal,(0,0,.025),(.55,.94,.05),'green',True)
 facade_part('Rear utility oak door',origin,normal,(0,0,.052),(.43,.84,0),'wood_light')
 for x in [-.10,0,.10]:facade_part('Rear door plank seam',origin,normal,(x,0,.054),(.008,.78,0),'wood')
 facade_part('Rear door brass latch',origin,normal,(.14,-.02,.059),(.035,.035,.012),'yellow',True)
 if variant=='a':
  for x in [-.815,.815]:B('Rear oak corner post',(x,1.525,-.836),(.085,2.85,.06),'wood',0)
  for y in [1.60,2.92]:
   B('Rear timber rail',(0,y,-.842),(1.74,.09,.055),'wood',0)
   B('Left upper timber rail',(-.867,y,0),(.055,.09,1.65),'wood',0)
  for z in [-.79,0,.79]:B('Left upper timber upright',(-.866,2.25,z),(.055,1.36,.075),'wood',0)
  beam('Rear diagonal timber',(-.76,1.68,-.852),(-.14,2.22,-.852),.065,'wood')
  beam('Left diagonal timber',(-.866,1.65,-.72),(-.866,2.22,-.10),.065,'wood')
  for z in [-.78,.78]:beam('Left gable timber',(-.865,2.96,z),(-.865,3.67,0),.06,'wood')
  beam('Left gable centre post',(-.865,2.96,0),(-.865,3.67,0),.06,'wood')
 else:
  # Shallow bevels around the window/door; mortar stays on the existing wall.
  facade_part('Rear stone mortar backing',(0,.83,-.822),normal,(0,0,0),(1.70,1.43,0),'stone_shade')
  for row in range(6):
   for col in range(5):
    x=-.68+col*.34;y=.235+row*.239
    if x<-.09 and y<1.04:continue
    if x>.10 and .51<y<1.12:continue
    facade_part('Rear cut stone',(x,y,-.825),normal,(0,0,.02),(.323,.222,.04),'stone_light' if (row+col)%4==0 else 'stone',True)

def window(x,y,z,width=.37,height=.40,side=False,flowers=False,flower_raise=0):
 def part(name,offset,size,color,r=0):
  p=(x+offset[2],y+offset[1],z-offset[0]) if side else (x+offset[0],y+offset[1],z+offset[2])
  s=(size[2],size[1],size[0]) if side else size
  return B(name,p,s,color,r)
 part('Green window surround',(0,0,0),(width+.10,height+.10,.065),'green',.006)
 part('Blue green glazing',(0,0,.04),(width,height,.018),'glass')
 part('Cream vertical muntin',(0,0,.054),(.022,height,.016),'cream')
 part('Cream horizontal muntin',(0,0,.055),(width,.023,.018),'cream')
 part('Glazing sky accent',(-width*.22,height*.25,.052),(width*.26,.019,.008),'cream')
 part('Window sill',(0,-height/2-.045,.045),(width+.17,.06,.16),'wood_light',.008)
 for s in [-1,1]:
  part('Painted green shutter',(s*(width/2+.075),0,.036),(.09,height+.04,.025),'green')
  for k in range(3):part('Shutter louvre',(s*(width/2+.075),-height*.28+k*height*.28,.052),(.075,.02,.013),'green_light')
 if flowers:
  flower_box(x,y-height/2-.16+flower_raise,z+.09,width+.20)

def flower_box(x,y,z,w):
 B('Flower box front',(x,y,z+.10),(w,.14,.07),'wood_light',.012)
 B('Flower box soil',(x,y+.034,z),(w-.05,.03,.17),'soil')
 for s in [-1,1]:B('Flower box end',(x+s*(w/2-.025),y,z),(.05,.14,.23),'wood',.008)
 for i in range(4):
  px=x+(i-1.5)*w*.22
  kit.ellipsoid('Clipped leafy cushion',(px,y+.11,z),(.15,.14,.18),'leaf_dark' if i%2 else 'leaf',8,4)
  for j in range(1):
   kit.ellipsoid('Small cream pink flower',(px+(j-.5)*.045,y+.18+.018*(i%2),z+.055*j),(.047,.028,.048),'flower' if (i+j)%3 else 'pink',6,3)

def roof(cx,cz,width,depth,eave,peak,across=False,rows=5,cols=9,name='Orange tiled roof'):
 """Gable axis along Z, or along X for main upper roof. Discrete flat clay tiles."""
 # Coordinates (u,height,v): u runs down slope, v along ridge.
 def pos(u,y,v):return (cx+v,y,cz+u) if across else (cx+u,y,cz+v)
 half=(depth if across else width)/2;ridge_len=width if across else depth
 length=math.hypot(half,peak-eave);ang=math.atan2(peak-eave,half)
 for side in [-1,1]:
  verts=[pos(0,peak,-ridge_len/2),pos(side*half,eave,-ridge_len/2),pos(side*half,eave,ridge_len/2),pos(0,peak,ridge_len/2)]
  verts += [(x,y-.065,z) for x,y,z in verts]
  M(name+' slab',verts,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],'orange_dark')
  for row in range(rows):
   t=(row+.5)/rows
   for col in range(cols):
    along=-ridge_len/2+(col+.5)*ridge_len/cols
    tile=B(name+' individual clay tile',pos(side*half*t,peak-(peak-eave)*t+.018,along),
      (ridge_len/cols-.006,.036,length/rows+.025) if across else (length/rows+.025,.036,ridge_len/cols-.006),
      'orange_light' if (row*7+col)%5==0 else 'orange',0)
    if across:tile.rotation_euler.x=side*ang
    else:tile.rotation_euler.y=side*ang
    omit_tile_underside(tile)
  for end in [-1,1]:beam(name+' gable verge',pos(0,peak+.04,end*ridge_len/2),pos(side*(half+.025),eave+.025,end*ridge_len/2),.065,'orange')
 beam(name+' ridge cap',pos(0,peak+.055,-ridge_len/2-.025),pos(0,peak+.055,ridge_len/2+.025),.09,'orange_light')

def dormer(x):
 # Front-facing dormers on main roof slope. Back edges penetrate the roof so no gap.
 z=.66;y=3.38;w=.43
 B('Dormer green-grey cheek body',(x,y-.07,z-.16),(w,.38,.44),'plaster',.009)
 M('Dormer triangular face',[(x-w/2,3.55,z+.065),(x+w/2,3.55,z+.065),(x,3.77,z+.065),
   (x-w/2,3.55,z-.42),(x+w/2,3.55,z-.42),(x,3.77,z-.42)],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)],'plaster')
 roof(x,z-.12,.62,.66,3.54,3.79,rows=2,cols=3,name='Dormer orange tile')
 window(x,3.39,z+.07,.24,.28,flowers=False)

def masonry_wall(cx,cy,cz,width,height,side=False):
 rng=random.Random(440+round(cx*100)+round(cz*100))
 rows=max(1,round(height/.25));rh=height/rows
 for j in range(rows):
  n=max(2,round(width/.33));step=width/n
  limits=[-width/2]+[-width/2+(i+.5*(j%2))*step for i in range(1,n+1) if -width/2+(i+.5*(j%2))*step<width/2-.02]+[width/2]
  for a,b in zip(limits,limits[1:]):
   xx=(a+b)/2;hh=rh-.016
   at=(cx,cy-height/2+(j+.5)*rh,cz-xx) if side else (cx+xx,cy-height/2+(j+.5)*rh,cz)
   size=(.085,hh,b-a-.013) if side else (b-a-.013,hh,.085)
   if side and abs(at[2]+.12)<.34 and .43<at[1]<1.02:continue
   stone_course(at,size,rng.choice(['stone','stone_light','stone','stone_shade']),side)

def chimney(x,z,base,top,stone=False):
 B('Chimney masonry body',(x,(base+top)/2,z),(.24,top-base,.27),'stone',.015)
 for j in range(max(1,int((top-base)/.19))):
  y=base+.095+j*.19
  B('Chimney front masonry joint',(x,y,z+.14),(.23,.013,.01),'stone_light',0)
  B('Chimney side masonry joint',(x+.125,y,z),(.01,.013,.26),'stone_light',0)
 B('Chimney cap',(x,top+.025,z),(.34,.07,.36),'stone_light',.015)
 B('Dark flue opening',(x,top+.064,z),(.19,.009,.20),'roof_dark',0)

def stone_course(at,size,color,side=False):
 # Truncated front edges, 10 triangles per stone. Buried back face omitted.
 w,h,depth=(size[2],size[1],size[0]) if side else size
 r=min(.025,w*.14,h*.14)
 verts=[]
 for z,ww,hh in [(-depth/2,w,h),(depth/2,w-2*r,h-2*r)]:
  for x,y in [(-ww/2,-hh/2),(ww/2,-hh/2),(ww/2,hh/2),(-ww/2,hh/2)]:
   verts.append((at[0]+z,at[1]+y,at[2]-x) if side else (at[0]+x,at[1]+y,at[2]+z))
 return M('Chamfered masonry course',verts,[(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],color)

def source_component(name,component):
 # Reuse the exact approved 439 buffers at their already-baked house origin.
 # Build a named editable mesh with original normals and AO vertex colours.
 folder=SRC/'reference/439';meta=json.loads((folder/'provenance.json').read_text())
 path=folder/(name+'.glb');digest=hashlib.sha256(path.read_bytes()).hexdigest()
 assert digest==meta['files'][path.name]['sha256']
 doc,data=load_glb(path);p=doc['meshes'][0]['primitives'][0]
 assert len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1
 assert all(n.get('scale',[1,1,1])==[1,1,1] and n.get('translation',[0,0,0])==[0,0,0] and n.get('rotation',[0,0,0,1])==[0,0,0,1] for n in doc['nodes'])
 xyz=accessor(doc,data,p['attributes']['POSITION']);normals=accessor(doc,data,p['attributes']['NORMAL']);colors=accessor(doc,data,p['attributes']['COLOR_0']);indices=[x[0] for x in accessor(doc,data,p['indices'])]
 mesh=bpy.data.meshes.new(name+' / exact 439 mesh')
 mesh.from_pydata([kit.v(v) for v in xyz],[],[indices[i:i+3] for i in range(0,len(indices),3)]);mesh.update()
 for face in mesh.polygons:face.use_smooth=True
 mesh.normals_split_custom_set_from_vertices([kit.v(n) for n in normals])
 attr=mesh.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
 for loop in mesh.loops:
  c=colors[loop.vertex_index];attr.data[loop.index].color=(*c[:3],c[3] if len(c)>3 else 1)
 mesh.color_attributes.active_color=attr;mesh.color_attributes.render_color_index=0
 mesh.materials.append(bpy.data.materials['Farm vertex paint'])
 obj=bpy.data.objects.new('439 / '+name+' / original geometry and vertex colour',mesh);kit.CURRENT.objects.link(obj)
 obj['component']=component;obj['source_commit']=meta['commit'];obj['source_sha256']=digest
 obj['source_file']=str(path.relative_to(ROOT))
 return {'name':name,'owner':'赵云','commit':meta['commit'],'sha256':digest,'triangles':len(indices)//3,'transform':'identity / house anchor / no offset','editable_source':meta['editable_source']}

def main_house(variant):
 name='master_farmhouse_'+variant
 kit.begin(name,[0,0],9000,pivot='Identical cottage anchor at ground (0,0,0)',front='+Z',units='m',generator='tools/art/build_homestead_lv15.py')
 B('Original foundation',(0,.065,0),(1.84,.13,1.78),'stone',.035)
 B('Ground-floor plaster over unchanged door',(0,.865,0),(1.71,1.48,1.64),'plaster',.025)
 B('Original base course',(0,.205,0),(1.75,.16,1.68),'plaster_shade',.015)
 # Keep the exact cottage entrance dimensions and x/z anchor.
 x=-.35;z=.795;h=.84;w=.45
 B('Unmoved green door frame',(x,h/2+.10,z),(w+.14,h+.09,.10),'green',.015)
 B('Unmoved oak door',(x,h/2+.075,z+.06),(w,h,.045),'wood_light',.01)
 for k in [-1,0,1]:B('Door plank seam',(x+k*w*.23,h/2+.06,z+.086),(.008,h*.88,.008),'wood',0)
 kit.ellipsoid('Original brass handle',(x+w*.30,h*.47,z+.105),(.043,.043,.03),'yellow',8,4)
 B('Unmoved cottage doorstep',(x,.066,z+.16),(w+.25,.12,.35),'stone_light',.025)
 window(.49,.76,.83,.37,.4)
 window(.87,.74,-.12,.48,.44,side=True)
 B('Second storey plaster',(0,2.255,0),(1.71,1.39,1.64),'plaster',.023)
 # Main roof ridge crosses the facade; real twin dormers face the field.
 for side in [-1,1]:
  x=side*.855
  M('Upper side gable',[(x,2.94,-.82),(x,2.94,.82),(x,3.69,0)],[(0,1,2)] if side==1 else [(2,1,0)],'plaster')
 roof(0,0,2.195,2.108,2.94,3.76,across=True)
 for x in [-.43,.43]:
  window(x,2.62,.836,.36,.42,flowers=True,flower_raise=.17 if variant=='a' else 0)
  dormer(x)
 window(.868,2.62,-.15,.40,.40,side=True)
 if variant=='a':
  for x in [-.815,.815]:B('Front oak post',(x,1.525,.84),(.085,2.85,.085),'wood',.008)
  for z in [-.79,0,.79]:B('Side oak upright',(.868,2.25,z),(.08,1.36,.075),'wood',.008)
  for y in [1.60,2.92]:
   B('Facade timber rail',(0,y,.849),(1.74,.09,.08),'wood',.007)
   B('Side timber rail',(.87,y,0),(.08,.09,1.65),'wood',.007)
  beam('Side diagonal half timber',(.874,1.65,-.72),(.874,2.22,-.10),.065,'wood')
  beam('Gable timber angle',(.875,2.96,-.78),(.875,3.67,0),.06,'wood')
  beam('Gable timber angle',(.875,3.67,0),(.875,2.96,.78),.06,'wood')
  beam('Gable centre king post',(.875,2.96,0),(.875,3.67,0),.06,'wood')
  chimney(-.66,-.39,3.20,4.04)
 else:
  # Ground-floor stones are placed around, never over, the unchanged entrance and window.
  masonry_wall(-.73,.85,.858,.24,1.44)
  masonry_wall(.13,.23,.858,.22,.22)
  masonry_wall(.13,1.03,.858,.22,.28)
  masonry_wall(.79,.85,.858,.17,1.44)
  masonry_wall(.48,.26,.858,.52,.28)
  masonry_wall(.48,1.28,.858,.52,.50)
  masonry_wall(-.35,1.28,.858,.55,.50)
  masonry_wall(.875,.83,0,1.64,1.44,side=True)
  # Covering the side window stones is avoided by a clean recessed opening.
  for o in list(kit.CURRENT.objects):
   if o.name.startswith('Rounded cut-stone') and o.location.x>.87:
    p=o.location
    # Blender y=-Godot z, z=Godot y.
    if abs(-p.y+.12)<.34 and .43<p.z<1.02:bpy.data.objects.remove(o,do_unlink=True)
  B('Stone storey cornice',(0,1.60,0),(1.79,.11,1.72),'stone_light',.018)
  chimney(-.66,-.39,3.15,4.12,True)
 rear_facade(variant)
 for obj in kit.CURRENT.objects:obj['component']='main'
 kit.META[name]['source_components']=[source_component('porch_'+variant,'porch'),source_component('kitchen_wing_'+variant,'kitchen_wing')]
 kit.META[name].pop('footprint_cells',None)
 kit.META[name]['sockets']={'door':[-.35,.495,.855],
  'chimney':[-.66,4.1085 if variant=='a' else 4.1885,-.39],
  'kitchen_wing_anchor':[0,0,0],'kitchen_wing_reference_center':[-1.63,0,-.75]}
 return name

def main():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for c in list(bpy.data.collections):bpy.data.collections.remove(c)
 bpy.context.preferences.filepaths.save_version=0
 cottage,buffer=load_glb(ROOT/'assets/farm/art/house_cottage.glb')
 cottage_colors=sorted(set(tuple(c[:3]) for c in accessor(cottage,buffer,cottage['meshes'][0]['primitives'][0]['attributes']['COLOR_0'])))
 structural=set(PALETTE)-{'leaf','leaf_light','leaf_dark','flower','pink','soil'}
 samples={}
 for key,h in PALETTE.items():
  color=kit.rgb(h)
  if key in structural:color=min(cottage_colors,key=lambda c:sum((c[i]-color[i])**2 for i in range(3)))
  samples[key]=list(color)
  mat=bpy.data.materials.new(key);mat.diffuse_color=(*color,1);mat.use_nodes=True
  mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=mat.diffuse_color
  mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.9
  kit.MATS[key]=mat
 material=bpy.data.materials.new('Farm vertex paint');material.use_nodes=True
 shader=material.node_tree.nodes['Principled BSDF'];shader.inputs['Roughness'].default_value=.9;shader.inputs['Specular IOR Level'].default_value=.18
 color=material.node_tree.nodes.new('ShaderNodeVertexColor');color.layer_name='Color';material.node_tree.links.new(color.outputs['Color'],shader.inputs['Base Color'])
 for variant in ['a','b']:main_house(variant)
 manifest={'author':'刘备','task':'SGODOT-440','units':'m','assets':{},'palette_target_srgb':PALETTE,'door_center':[-.35,.495,.855],'status':'Exact 439 components reused from #858 head 262533a76cf8cef31d52782698f5837611aea6dd; geometry / normals / vertex colours independently compared','module_contract':{'house_anchor':[9,16],'house_footprint':[8,15,4,3],'grid_m':.65,'house_front_m':1.13,'wing_anchor':[0,0,0],'wing_reference_center':[-1.63,0,-.75],'porch_ground_max_z':.975,'porch_floor_max_y':.05,'porch_clearance_min_y':2.0,'attachments_placement':'All four at house anchor with identity transform; no legacy offsets','lv8_combined_x_envelope':[-2.4250001907348633,1.6349704265594482]}}
 manifest['palette_sampled_linear']=samples
 manifest['structural_palette_keys']=sorted(structural)
 manifest['cottage_palette_sha256']=hashlib.sha256((ROOT/'assets/farm/art/house_cottage.glb').read_bytes()).hexdigest()
 manifest['structural_palette_source']='Nearest actual COLOR_0 values from unchanged house_cottage.glb, before runtime lighting; vegetation uses the existing farm kit palette.'
 for name,collection in kit.ASSETS.items():
  manifest['assets'][name]=export_asset(name,collection,material,kit)
  for obj in collection.objects:obj.name=name+' / '+obj.get('component','main')+' / '+obj.name
 (SRC/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'homestead_lv15.blend'))
 print('HOMESTEAD_MODEL',json.dumps(manifest['assets']))
if __name__=='__main__':main()
