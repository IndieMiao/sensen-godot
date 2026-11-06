"""SGODOT-423 v1.1. Additive assets only; run Blender under gs66-render.lock.
The v1 walls, colliders and interaction layout are never regenerated.
"""
from pathlib import Path
import bpy,math,json,hashlib,struct
from mathutils import Vector
SRC=Path(__file__).resolve().parent;KIT=SRC.parent
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0
tex=bpy.data.images.load(str(KIT/'room_albedo_ao.png'),check_existing=True)
mat=bpy.data.materials.new('Church_SharedAtlas');mat.use_nodes=True
bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.88
bs.inputs['Specular IOR Level'].default_value=.16
node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=tex
mat.node_tree.links.new(node.outputs['Color'],bs.inputs['Base Color'])
COLORS={'vault':(990,392),'rib':(505,278),'wood':(921,511),'carpet':(1904,132),'grass':(1326,791)}
parts={}
def point(v):return Vector((v[0],-v[2],v[1]))
def mesh(name,vs,faces,color):
 d=bpy.data.meshes.new(name);d.from_pydata([point(v) for v in vs],[],faces);d.update()
 o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);d.materials.append(mat)
 layer=d.uv_layers.new(name='RoomAtlas');x,y=COLORS[color]
 for v in layer.data:v.uv=((x+.5)/2048,1-(y+.5)/2048)
 parts[current].append(o);return o
def box(name,at,size,color):
 x,y,z=at;w,h,d=[n/2 for n in size]
 vs=[(x+a*w,y+b*h,z+c*d) for a,b,c in [(-1,-1,-1),(1,-1,-1),(1,-1,1),(-1,-1,1),(-1,1,-1),(1,1,-1),(1,1,1),(-1,1,1)]]
 return mesh(name,vs,[tuple(reversed(f)) for f in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]],color)
def beam(name,a,b,r,color):
 a=Vector(a);b=Vector(b);axis=(b-a).normalized();u=axis.cross(Vector((0,0,1))).normalized()
 if u.length<.1:u=axis.cross(Vector((1,0,0))).normalized()
 v=axis.cross(u);vs=[tuple(p+r*(math.cos(i*math.tau/6)*u+math.sin(i*math.tau/6)*v)) for p in (a,b) for i in range(6)]
 return mesh(name,vs,[tuple(reversed(range(6))),tuple(range(6,12))]+[(i,(i+1)%6,(i+1)%6+6,i+6) for i in range(6)],color)
current='aisle_carpet';parts[current]=[]
# A single thin runner, no collision. v range -2.84 .. 2.75 leaves 6 cm to labyrinth.
box('Warm muted ochre flat aisle runner',(0,.002,0),(1.20,.004,5.59),'carpet')
current='vault_extension';parts[current]=[]
# Real exterior upper architecture: original walls are at -5.25. The upper
# enclosure moves out 2 m, extends 2 m beyond each old band end, and rises
# to close portrait follow views. Both planes have timber framing.
for side in ('north','west'):
 def xyz(x,y,z):return (x,y,z) if side=='north' else (z,y,x)
 def wallbox(name,at,size,color):
  return box(side+' '+name,xyz(*at),size if side=='north' else (size[2],size[1],size[0]),color)
 wallbox('extended upper dark vault',(0,9.745,-7.25),(14.9,3.51,.30),'vault')
 for y in (8.03,11.42):wallbox('continuous timber band',(0,y,-7.07),(14.9,.14,.18),'wood')
 for x in (-7.35,-5,-2.5,0,2.5,5,7.35):
  wallbox('upper outer pier',(x,9.745,-7.03),(.14,3.51,.20),'wood')
 for cx in (-6.2,-3.75,-1.25,1.25,3.75,6.2):
  path=[(cx-1.1,8.06),(cx-1.1,9.3),(cx-.90,10.05),(cx-.52,10.72),(cx,11.25),(cx+.52,10.72),(cx+.90,10.05),(cx+1.1,9.3),(cx+1.1,8.06)]
  for i,(a,b) in enumerate(zip(path,path[1:])):beam(side+' upper pointed rib %s %s'%(cx,i),xyz(a[0],a[1],-6.94),xyz(b[0],b[1],-6.94),.055,'rib')
 # Close the return at the original band ends; visible only beyond the old walls.
 for x in (-7.35,7.35):
  wallbox('end return',(x,9.745,-6.2),(.18,3.51,2.10),'vault')
 # A sloping timber canopy connects the old crown to the new rear fascia.
 vs=[xyz(-7.45,7.99,-5.13),xyz(7.45,7.99,-5.13),xyz(7.45,11.50,-7.10),xyz(-7.45,11.50,-7.10)]
 faces=[(0,1,2,3)] if side=='north' else [(3,2,1,0)]
 mesh(side+' upper sloped vault return',vs,faces,'vault')
 for x in (-7.35,-5,-2.5,0,2.5,5,7.35):beam(side+' sloped timber rafter',xyz(x,7.99,-5.10),xyz(x,11.50,-7.07),.065,'wood')
current='grass_extension';parts[current]=[]
box('Low meadow edge extension',(0,-.79,0),(30,.18,30),'grass')
# Editable named pieces retained in source; joined runtime copies have 1 surface.
tex.filepath='//../room_albedo_ao.png'
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'church_v11_additions.blend'))
for name,objects in parts.items():
 bpy.ops.object.select_all(action='DESELECT');copies=[]
 for o in objects:
  c=o.copy();c.data=o.data.copy();bpy.context.collection.objects.link(c);c.select_set(True);copies.append(c)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();o=bpy.context.object
 o.name=name;o.data.name=name+'_mobile'
 bpy.ops.export_scene.gltf(filepath=str(KIT/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_image_format='NONE',export_animations=False,export_cameras=False,export_lights=False)
 path=KIT/(name+'.glb');raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);binary=raw[28+n:]
 doc['images']=[{'uri':'room_albedo_ao.png'}];doc['textures']=[{'source':0,'sampler':0}];doc['samplers']=[{'magFilter':9729,'minFilter':9987,'wrapS':33071,'wrapT':33071}]
 doc['materials'][0]['pbrMetallicRoughness']['baseColorTexture']={'index':0};doc['materials'][0]['pbrMetallicRoughness']['baseColorFactor']=[1,1,1,1]
 payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4)
 path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(payload)+len(binary))+struct.pack('<I4s',len(payload),b'JSON')+payload+struct.pack('<I4s',len(binary),b'BIN\0')+binary)
 bpy.data.objects.remove(o,do_unlink=True)
print('CHURCH_INCREMENT_EXPORTED')
