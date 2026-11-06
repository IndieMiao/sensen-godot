"""SGODOT-424 / 刘备. Six matte nature prototypes, Godot metres / Y up.
Run Blender with an absolute script path. Rebuild overwrites the named .blend.
"""
from pathlib import Path
import bpy,bmesh,math,random,json,hashlib
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
OUT=ROOT/'assets/landmarks/alcatraz_island'
PALETTE={'stone':'B7AD98','stone_light':'C6BDAA','stone_shade':'9F998B',
         'leaf_deep':'66804A','leaf_mid':'7D9453','leaf_sun':'99A965',
         'grass_root':'758746','grass_tip':'ADB677'}
def linear(h):
 return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in [v/255 for v in bytes.fromhex(h)])
def v(p):return Vector((p[0],-p[2],p[1]))
def gv(p):return Vector((p.x,p.z,-p.y))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):bpy.data.collections.remove(c)
bpy.context.preferences.filepaths.save_version=0
mat=bpy.data.materials.new('Alcatraz nature / matte vertex colour');mat.use_nodes=True;mat.use_backface_culling=True
bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=.94
bsdf.inputs['Metallic'].default_value=0;bsdf.inputs['Specular IOR Level'].default_value=.15
paint=mat.node_tree.nodes.new('ShaderNodeVertexColor');paint.layer_name='Color'
mat.node_tree.links.new(paint.outputs['Color'],bsdf.inputs['Base Color'])
collections={};records={}
def collection(name):
 c=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(c);collections[name]=c
 return c
def finish(obj,name,c,color_fn,soft=.7):
 obj.name=name
 for col in list(obj.users_collection):col.objects.unlink(obj)
 c.objects.link(obj)
 bpy.context.view_layer.objects.active=obj;obj.select_set(True)
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()
 obj.data.materials.clear();obj.data.materials.append(mat)
 for f in obj.data.polygons:f.use_smooth=True
 attr=obj.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
 normals=[]
 for face in obj.data.polygons:
  for li in face.loop_indices:
   vert=obj.data.vertices[obj.data.loops[li].vertex_index]
   attr.data[li].color=(*color_fn(gv(vert.co),face),1)
   normals.append(tuple((vert.normal*soft+face.normal*(1-soft)).normalized()))
 obj.data.color_attributes.active_color=attr;obj.data.color_attributes.render_color_index=0
 if soft<1:obj.data.normals_split_custom_set(normals)
 obj.select_set(False)
 return obj

def rock(name,dims,seed):
 c=collection(name);rng=random.Random(seed)
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3,radius=1)
 obj=bpy.context.object
 # Broad mineral shoulders, blunt top, irregular footprint; no crystalline spikes.
 for vert in obj.data.vertices:
  p=vert.co.copy();f=1+.08*math.sin(p.x*3.1+seed)+.05*math.cos(p.y*4.4-p.z*2.7)
  p*=f;p.z=max(-.66,p.z);p.x+=.12*p.z+.06*p.y*p.z
  vert.co=p
 dec=obj.modifiers.new('Broad 180-triangle silhouette','DECIMATE');dec.ratio=.5625
 bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=dec.name)
 coords=[gv(p.co) for p in obj.data.vertices];lo=[min(p[i] for p in coords) for i in range(3)];hi=[max(p[i] for p in coords) for i in range(3)]
 for vert,p in zip(obj.data.vertices,coords):
  q=[(p[i]-lo[i])/(hi[i]-lo[i])*dims[i] for i in range(3)];q[0]-=dims[0]/2;q[2]-=dims[2]/2;vert.co=v(q)
 base=Vector(linear(PALETTE['stone']));light=Vector(linear(PALETTE['stone_light']));dark=Vector(linear(PALETTE['stone_shade']))
 def color(p,face):
  h=p.y/dims[1];grain=.5+.5*math.sin(p.x*3.6+p.z*2.3+seed)
  return dark.lerp(base,min(1,h*3+.25)).lerp(light,.13*grain+.12*max(0,h-.25))
 finish(obj,'Rounded mineral mass / '+name,c,color,.50)
 records[name]={'triangle_limit':200,'intended_dimensions_m':dims,'kind':'shore rock','parts':['Rounded mineral mass']}

rock('alc_rock_a',(.95,.70,.84),4241)
rock('alc_rock_b',(1.85,1.18,1.42),4242)
rock('alc_rock_c',(2.80,2.08,2.24),4243)

def shrub(name,scale,warm,seed,count):
 c=collection(name);rng=random.Random(seed)
 base=Vector(linear(PALETTE['leaf_mid' if warm else 'leaf_deep']));light=Vector(linear(PALETTE['leaf_sun' if warm else 'leaf_mid']))
 for i in range(count):
  central=i==0;a=i*2.39996+.4
  center=Vector((0,.39,0)) if central else Vector((math.cos(a)*(.29 if i<5 else .18),.23+rng.uniform(-.03,.10),math.sin(a)*.22))
  size=Vector((.58,.52,.55)) if central else Vector((.48,.40,.43))
  center*=scale;size*=scale
  bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1)
  obj=bpy.context.object
  for vert in obj.data.vertices:
   p=gv(vert.co);p.x*=size.x*.5;p.y*=size.y*.5;p.z*=size.z*.5
   p.x+=p.y*.18;p+=center;vert.co=v(p)
  def color(p,face):return base.lerp(light,.20+.40*max(0,min(1,p.y/(.7*scale))))
  finish(obj,'Leaf cushion %02d'%i,c,color,.88)
 # Plant base is floor level, not a mud pedestal. Normalize footprint centre.
 coords=[gv(vv.co) for o in c.objects for vv in o.data.vertices]
 lo=[min(p[i] for p in coords) for i in range(3)];hi=[max(p[i] for p in coords) for i in range(3)]
 offset=v(((lo[0]+hi[0])/2,lo[1],(lo[2]+hi[2])/2))
 for o in c.objects:
  for vert in o.data.vertices:vert.co-=offset
 records[name]={'triangle_limit':200,'kind':'low warm-green shrub' if warm else 'low deep-green shrub','leaf_cushions':count}
shrub('alc_shrub',1,False,4244,7)
shrub('alc_shrub_b',1.28,True,4245,9)
c=collection('alc_grass_tuft');rng=random.Random(4246)
for i in range(6):
 a=i*2.39996;length=rng.uniform(.29,.44);reach=rng.uniform(.16,.29);w=rng.uniform(.065,.09)
 direction=Vector((math.cos(a),0,math.sin(a)));side=Vector((-math.sin(a),0,math.cos(a)))
 base=direction*.04;mid=base+direction*reach*.45+Vector((0,length*.52,0));tip=base+direction*reach+Vector((0,length,0))
 pts=[base-side*w*.40,base+side*w*.40,mid-side*w,mid+Vector((0,.018,0)),mid+side*w,tip]
 # Five folded front triangles and separate back vertices (10 per blade).
 faces=[(0,1,3),(0,3,2),(1,4,3),(2,3,5),(3,4,5)]
 faces+= [tuple(j+6 for j in reversed(f)) for f in faces]
 pts=pts+pts
 data=bpy.data.meshes.new('folded blade');data.from_pydata([v(p) for p in pts],[],faces);data.update()
 obj=bpy.data.objects.new('Blade %02d'%i,data);c.objects.link(obj)
 # Explicit two-sided sheets: retain authored winding, flat folded normals.
 obj.data.materials.append(mat);attr=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
 root=Vector(linear(PALETTE['grass_root']));tipc=Vector(linear(PALETTE['grass_tip']))
 for f in data.polygons:
  for li in f.loop_indices:
   y=gv(data.vertices[data.loops[li].vertex_index].co).y;attr.data[li].color=(*root.lerp(tipc,.2+.7*y/.44),1)
 data.color_attributes.active_color=attr;data.color_attributes.render_color_index=0
records['alc_grass_tuft']={'triangle_limit':60,'kind':'six folded grass blades, explicit backs','blades':6}
# Normalize tuft pivot to footprint centre.
pts=[gv(vv.co) for o in c.objects for vv in o.data.vertices];off=v(((min(p.x for p in pts)+max(p.x for p in pts))/2,0,(min(p.z for p in pts)+max(p.z for p in pts))/2))
for o in c.objects:
 for vert in o.data.vertices:vert.co-=off
# All authored parts remain separately editable, grouped by prototype.
scene=bpy.context.scene;scene['task']='SGODOT-424';scene['author']='刘备';scene['units']='Godot metres, Y-up; Blender x,-z,y'
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'alcatraz_nature.blend'))
for name,col in collections.items():
 export=bpy.data.scenes.new('Export '+name);bpy.context.window.scene=export;copies=[]
 for obj in col.objects:
  o=bpy.data.objects.new(obj.name,obj.data.copy());export.collection.objects.link(o);o.select_set(True);copies.append(o)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();body=bpy.context.object;body.name=name;body.data.name=name+'_mesh'
 body.data.calc_loop_triangles();tri=len(body.data.loop_triangles);assert tri<=records[name]['triangle_limit']
 path=OUT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,
   export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_normals=True,
   export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False)
 coords=[gv(vert.co) for vert in body.data.vertices];lo=[min(p[i] for p in coords) for i in range(3)];hi=[max(p[i] for p in coords) for i in range(3)]
 records[name].update(file=path.name,triangles=tri,surfaces=1,bounds=[lo,hi],dimensions_m=[hi[i]-lo[i] for i in range(3)],
   bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),pivot='bottom / footprint centre',owner='刘备',placeholder=False)
 bpy.context.window.scene=scene;bpy.data.scenes.remove(export)
manifest={'task':'SGODOT-424','author':'刘备','virtual_user_id':'0fb1de1f-ead5-443b-9537-54cbac113260',
 'axes':'metres; Y up; +Z south; Blender (x,-z,y)','generator':'tools/art/source/alcatraz_nature_424/build.py',
 'source':'tools/art/source/alcatraz_nature_424/alcatraz_nature.blend','palette_srgb':PALETTE,
 'material':'linear COLOR_0, roughness .94, metallic 0, specular .15; opaque, no images, no external shader',
 'godot_material':'res://assets/landmarks/alcatraz_island/alc_nature_material.tres (bound by each generated .glb.import)',
 'assets':records,'triangles_total':sum(r['triangles'] for r in records.values())}
(OUT/'alc_nature_manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
print('ALC_NATURE_READY',[(n,r['triangles']) for n,r in records.items()],flush=True)
