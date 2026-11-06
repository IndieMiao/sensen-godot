"""SGODOT-423 reusable modular church kit. New assets only, no new POI layout.
Blender execution MUST be wrapped by flock ~/gs66-render.lock.
"""
from pathlib import Path
import bpy,bmesh,math,json,sys,hashlib,importlib.util
from mathutils import Vector,Matrix
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/rooms/_shared/church_kit'
spec=importlib.util.spec_from_file_location('primitives',SRC.parent/'alcatraz_far_424/build.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
PAL={'stone':'DCC6A7','stone_light':'EBD8BC','stone_edge':'C7AC87','stone_dark':'B39979','floor':'D7BE9D','floor_light':'DEC7A9','floor_warm':'D3B38D','joint':'BDA383','wood':'BD874C','wood_light':'D5A363','wood_dark':'8D633D','vault':'75634F','vault_light':'978068','blue':'719ABF','blue_dark':'517995','coral':'D68F70','glass_gold':'E7BD68','glass_cream':'F2DC9F','iron':'5D4C38','grass':'91A27C'}
p.PAL=PAL
GLASS_ROLES=['blue','blue_dark','coral','glass_gold','glass_cream','iron']
box=p.box;mesh=p.mesh;rod=p.rod
ROWS={}
def begin(name):
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.context.preferences.filepaths.save_version=0
 p.PARTS=[];p.MATS={};p.PIVOT=bpy.data.objects.new(name+' / installation pivot',None);bpy.context.scene.collection.objects.link(p.PIVOT)
 p.PIVOT['author']='黄忠';p.PIVOT['module']=name
 return name
def source_parts(collection,include=None):
 # Append editable named objects; reset only the copied collection's assembly pivot.
 source=ROOT/'tools/art/source/poi_church/poi_church.blend'
 with bpy.data.libraries.load(str(source),link=False) as (src,dst):dst.collections=['KIT_'+collection]
 col=dst.collections[0];bpy.context.scene.collection.children.link(col)
 root=next(o for o in col.objects if o.type=='EMPTY');root.location=(0,0,0);root.rotation_euler=(0,0,0);root.scale=(1,1,1)
 for o in list(col.objects):
  if o.type!='MESH':continue
  if include and not include(o):bpy.data.objects.remove(o,do_unlink=True);continue
  o.hide_render=False;o.hide_set(False);p.PARTS.append(o)
 return root

def pointed(width,bottom=1.15,spring=3.25,top=4.45,n=16):
 out=[(-width/2,bottom),(-width/2,spring)]
 for i in range(1,n+1):t=i/n;out.append((-width/2*(1-t*t),spring+(top-spring)*t))
 for i in range(1,n+1):t=i/n;out.append((width/2*(2*t-t*t),top-(top-spring)*t))
 return out+[(width/2,bottom)]
def prism(name,outline,lo,hi,role):
 n=len(outline);vs=[(x,y,z) for y in [lo,hi] for x,z in outline]
 return mesh(name,vs,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],role)
def cutter(path):
 n=len(path);vs=[(x,y,z) for z in [-.6,.6] for x,y in path]
 return mesh('temporary true opening',vs,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],'stone')
def cut(wall,obj):
 bpy.context.view_layer.update();mod=wall.modifiers.new('True modular aperture','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=obj
 bpy.context.view_layer.objects.active=wall;bpy.ops.object.modifier_apply(modifier=mod.name);p.PARTS.remove(obj);bpy.data.objects.remove(obj,do_unlink=True)
def wall_style(window=False,rose=False):
 wall=box('2m limestone core',(0,2.4,0),(2,4.8,.26),'stone')
 if window:cut(wall,cutter(pointed(1.35)))
 if rose:cut(wall,cutter([(.828*math.cos(i*math.tau/64),3.25+.828*math.sin(i*math.tau/64)) for i in range(64)]))
 # Flush end caps, no X bevel: adjacent modules have identical endpoint sections.
 box('Continuous skirting',(0,.17,.10),(2,.34,.38),'stone_light')
 box('Continuous top cornice',(0,4.70,.08),(2,.20,.42),'stone_light')
 for row in range(9):
  y=.35+row*.50
  for a,b in ([(-1,-.76),(.76,1)] if window and 1.1<y<4.5 else [(-1,-.96),(.96,1)] if rose and 2.2<y<4.3 else [(-1,1)]):
   box('Quiet horizontal masonry',((a+b)/2,y,.133),(b-a,.012,.006),'stone_edge')
 if window:
  source_parts('window_surround')
 return {'module_length_m':2,'wall_height_m':4.8,'core_thickness_m':.26,'mount_plane':'bottom centre; +Z interior','connectors':{'left':[-1,0,0],'right':[1,0,0]},'glass_mount':[0,0,.0] if window else [0,3.25,0] if rose else None}
def corner():
 outline=[(-.13,-.13),(1,-.13),(1,.13),(.13,.13),(.13,1),(-.13,1)]
 prism('Unified L corner',outline,0,4.8,'stone')
 for low,high,front,role in [(0,.34,.29,'stone_light'),(4.60,4.8,.29,'stone_light')]:
  profile=[(-.13,-.13),(1,-.13),(1,front),(front,front),(front,1),(-.13,1)];prism('Corner continuous moulding',profile,low,high,role)
 for row in range(9):
  y=.35+row*.5
  box('X arm mortar',(.565,y,.133),(.87,.012,.006),'stone_edge');box('Z arm mortar',(.133,y,.565),(.006,.012,.87),'stone_edge')
 return {'arm_length_m':1,'wall_height_m':4.8,'core_thickness_m':.26,'mount_plane':'bend at floor; arms +X and +Z','connectors':{'x_end':[1,0,0],'z_end':[0,0,1]}}
def roofband():
 box('Modular dark upper band',(0,1.2,0),(2,2.4,.26),'vault')
 for y in [.07,2.33]:box('Continuous timber fascia',(0,y,.17),(2,.14,.14),'wood_dark')
 for x in [-.96,.96]:box('Paired half seam upright',(x,1.2,.17),(.08,2.26,.14),'wood_dark')
 path=pointed(1.75,.14,1.15,2.22,n=8)
 for a,b in zip(path,path[1:]):rod('Pointed timber roof rib',(a[0],a[1],.23),(b[0],b[1],.23),.045,'vault_light',6)
 return {'module_length_m':2,'height_m':2.4,'mount_y_on_wall':4.8,'connectors':{'left':[-1,0,0],'right':[1,0,0]}}
def beam():
 box('2m straight timber tie',(0,0,0),(2,.18,.18),'wood_dark')
 return {'module_length_m':2,'mount_plane':'beam centreline','connectors':{'left':[-1,0,0],'right':[1,0,0]}}
def floor():
 box('2m square stone substrate',(0,.05,0),(2,.10,2),'joint')
 for x in range(2):
  for z in range(4):box('Quiet limestone floor tile',(-.5+x,.11,-.75+z*.5),(.988,.02,.488),['floor','floor_light','floor_warm','floor'][(x+z)%4])
 return {'module_size_m':[2,2],'height_m':.12,'top_y':.12,'mount_plane':'bottom centre; place y=-.12 for floor top0'}
def steps():
 for j in range(3):box('Broad 180mm riser '+str(j+1),(0,(j+1)*.09,-j*.15),(2,(j+1)*.18,1.5-j*.3),'stone_light' if j%2==0 else 'stone')
 return {'module_width_m':2,'riser_m':.18,'risers':3,'height_m':.54,'top_platform_m':[2,.9],'top_platform_center':[0,.54,-.30]}
def simple_source(name):
 source_parts(name)
 return {'source_collection':'KIT_'+name}
def rose_source(glass):
 def isglass(obj):return not all(m.name.startswith('stone_light') for m in obj.data.materials)
 root=source_parts('rose_window',isglass if glass else lambda o:not isglass(o));root.scale=(.92,.92,.92)
 return {'source_collection':'KIT_rose_window','uniform_scale_from_source':.92,'mount_plane':'window centre/back plane; +Z front','pair':'rose_frame' if glass else 'rose_glass'}
def role_for(mat):
 name=mat.name.split('.')[0]
 return next((k for k in sorted(PAL,key=len,reverse=True) if name==k or name.startswith(k+'_')),None)
def export(name,build,kind='vertex'):
 begin(name);extra=build();bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
 flat=bpy.data.materials.new('Church kit '+kind);flat.use_nodes=True;flat.use_backface_culling=kind!='glass'
 bs=flat.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(1,1,1,1);bs.inputs['Roughness'].default_value=.88;bs.inputs['Specular IOR Level'].default_value=.16
 vc=flat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';flat.node_tree.links.new(vc.outputs['Color'],bs.inputs['Base Color'])
 original=bpy.context.scene;scene=bpy.data.scenes.new('Export '+name);copies=[]
 for obj in p.PARTS:
  data=bpy.data.meshes.new_from_object(obj.evaluated_get(deps));data.transform(obj.matrix_world)
  colours=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
  for old_uv in list(data.uv_layers):data.uv_layers.remove(old_uv)
  uv=data.uv_layers.new(name='PaletteSlot') if kind=='glass' else None
  if uv:uv.active_render=True
  for face in data.polygons:
   mat=data.materials[face.material_index];role=role_for(mat)
   for i in face.loop_indices:
    colours.data[i].color=mat.diffuse_color
    if uv:
     assert role in GLASS_ROLES,(name,obj.name,mat.name,role)
     uv.data[i].uv=((GLASS_ROLES.index(role)+.5)/8,.5)
  data.materials.clear();data.materials.append(flat)
  for face in data.polygons:face.material_index=0
  data.color_attributes.active_color=colours;data.color_attributes.render_color_index=0
  obj2=bpy.data.objects.new(obj.name,data);scene.collection.objects.link(obj2);copies.append(obj2)
 bpy.context.window.scene=scene
 for obj in copies:obj.select_set(True)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();obj=bpy.context.object;obj.name=name;obj.data.name=name+'_mobile'
 bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free();obj.data.calc_loop_triangles()
 path=KIT/(name+'.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_normals=True,export_texcoords=kind=='glass',export_animations=False,export_cameras=False,export_lights=False)
 pts=[(v.co.x,v.co.z,-v.co.y) for v in obj.data.vertices];lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
 row={'file':path.name,'triangles':len(obj.data.loop_triangles),'surfaces':1,'bounds':[lo,hi],'dimensions_m':[hi[i]-lo[i] for i in range(3)],'material':kind,'source':str((SRC/(name+'.blend')).relative_to(ROOT)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),**extra}
 bpy.context.window.scene=original;bpy.data.scenes.remove(scene);print(name,row['triangles'],row['dimensions_m'],flush=True);return row

def main():
 builders=[('wall_straight_2m',lambda:wall_style()),('wall_corner_2m',corner),('wall_pointed_2m',lambda:wall_style(window=True)),('wall_rose_2m',lambda:wall_style(rose=True)),('roof_band_2m',roofband),('floor_tile_2m',floor),('beam_2m',beam),('steps_2m',steps),('pointed_glass',lambda:simple_source('pointed_window'),'glass'),('rose_glass',lambda:rose_source(True),'glass'),('rose_frame',lambda:rose_source(False))]
 for item in builders:ROWS[item[0]]=export(*item)
 manifest={'task':'SGODOT-423 church kit preparation','revision':'v1','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','units':'metres; Y up; +Z interior/front','grid_m':2,'wall_height_m':4.8,'assets':ROWS,'glass_palette_slots':GLASS_ROLES,'status':'Reusable pieces only; example is an isolated review fixture, no new church/POI/layout'}
 (KIT/'kit_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
