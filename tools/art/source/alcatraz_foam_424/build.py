"""SGODOT-424 shore foam kit, 刘备. Blender (x,-z,y) -> Godot metre/Y-up.
Deterministic named parts remain editable; exports are single-surface prototypes.
"""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,random
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'assets/landmarks/alcatraz_island';OUT.mkdir(parents=True,exist_ok=True)
P={'iron':'56666A','iron_top':'708083','wood':'AB8257','wood_light':'C5A173','wood_dark':'795F47','rope':'C5B592','canvas':'D9D8BF','sage':'819889','frame':'CFD1BE','sign':'E5DCC2','terra':'AF7C62','rim':'C99B79','soil':'665746','leaf':'547346','leaf_light':'7C9656','white':'EEE6D1','yellow':'D9BD67','lilac':'B4A5BF','pollen':'B69550'}
def rgb(key):
 return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in [v/255 for v in bytes.fromhex(P.get(key,key))])
def v(p):return Vector((p[0],-p[2],p[1]))
def gv(p):return Vector((p.x,p.z,-p.y))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):bpy.data.collections.remove(c)
bpy.context.preferences.filepaths.save_version=0
mat=bpy.data.materials.new('Alcatraz shore props / matte vertex colour');mat.use_nodes=True;mat.use_backface_culling=True
bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.94;bs.inputs['Specular IOR Level'].default_value=.15
colnode=mat.node_tree.nodes.new('ShaderNodeVertexColor');colnode.layer_name='Color';mat.node_tree.links.new(colnode.outputs['Color'],bs.inputs['Base Color'])
cols={};records={};current=None
def group(name):
 global current
 current=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(current);cols[name]=current
 records[name]={'triangle_limit':200,'owner':'刘备','placeholder':False}
def mesh(name,pts,faces,color,smooth=False,recalc=True):
 data=bpy.data.meshes.new(name);data.from_pydata([v(p) for p in pts],[],faces);data.update()
 obj=bpy.data.objects.new(name,data);current.objects.link(obj)
 bm=bmesh.new();bm.from_mesh(data);
 if recalc:bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 bm.to_mesh(data);bm.free()
 data.materials.append(mat);attr=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
 for f in data.polygons:
  f.use_smooth=smooth
  for li in f.loop_indices:
   p=gv(data.vertices[data.loops[li].vertex_index].co)
   # Fine authored colour changes, no baked directional lighting.
   c=rgb(color) if isinstance(color,str) else color(p,f)
   attr.data[li].color=(*c,1)
 data.color_attributes.active_color=attr;data.color_attributes.render_color_index=0
 return obj
def box(name,center,size,color):
 c=Vector(center);sx,sy,sz=[q/2 for q in size]
 pts=[c+Vector((a*sx,b*sy,d*sz)) for a,b,d in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
 return mesh(name,pts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)],color)
def beam(name,a,b,width,depth,color):
 o=box(name,(0,0,0),(width,(Vector(b)-Vector(a)).length,depth),color)
 d=(v(b)-v(a)).normalized();q=Vector((0,0,1)).rotation_difference(d);mid=(v(a)+v(b))/2
 for vert in o.data.vertices:vert.co=q@vert.co+mid
 return o
def lathe(name,rings,color,n=10,offset=(0,0,0),axis='y'):
 pts=[];faces=[]
 for y,r in rings:
  for i in range(n):
   a=2*math.pi*i/n;pt=(r*math.cos(a),y,r*math.sin(a));pt=(pt[1],pt[0],pt[2]) if axis=='x' else pt
   pts.append(Vector(pt)+Vector(offset))
 for j in range(len(rings)-1):
  for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
 faces += [tuple(reversed(range(n))),tuple((len(rings)-1)*n+i for i in range(n))]
 return mesh(name,pts,faces,color,True)
def quad(name,pts,color):return mesh(name,pts,[(0,1,2,3)],color)
# Static alpha sheets: local Y=0, single upward-facing surface.
foam=bpy.data.materials.new('Alcatraz foam / shared soft alpha');foam.use_nodes=True;foam.use_backface_culling=True
nodes=foam.node_tree.nodes;links=foam.node_tree.links;nodes.clear()
tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(OUT/'alc_foam_soft.png'));tex.image.filepath='//../../../../assets/landmarks/alcatraz_island/alc_foam_soft.png'
attr=nodes.new('ShaderNodeVertexColor');attr.layer_name='Color';multiply=nodes.new('ShaderNodeMath');multiply.operation='MULTIPLY';links.new(tex.outputs['Alpha'],multiply.inputs[0]);links.new(attr.outputs['Alpha'],multiply.inputs[1])
em=nodes.new('ShaderNodeEmission');links.new(tex.outputs['Color'],em.inputs['Color']);transparent=nodes.new('ShaderNodeBsdfTransparent');mix=nodes.new('ShaderNodeMixShader');links.new(multiply.outputs[0],mix.inputs[0]);links.new(transparent.outputs[0],mix.inputs[1]);links.new(em.outputs[0],mix.inputs[2]);output=nodes.new('ShaderNodeOutputMaterial');links.new(mix.outputs[0],output.inputs['Surface'])
foam.surface_render_method='BLENDED'
def foam_mesh(name,centers,widths,closed=False):
 group(name);records[name]['triangle_limit']=80;pts=[];uvs=[];alpha=[];faces=[]
 N=len(centers)
 for i,(x,z) in enumerate(centers):
  if closed:
   a=Vector(centers[(i-1)%(N-1)]);b=Vector(centers[(i+1)%(N-1)])
  else:a=Vector(centers[max(0,i-1)]);b=Vector(centers[min(N-1,i+1)])
  t=(b-a).normalized();normal=Vector((-t.y,t.x));w=widths[i]
  for j in range(3):
   q=Vector((x,z))+normal*w*(j/2-.5);pts.append((q.x,0,q.y));uvs.append((i/(N-1)*2,j/2))
   alpha.append(1 if closed else min(1,i/1.7,(N-1-i)/1.7))
 for i in range(N-1):
  for j in range(2):faces.append((i*3+j,(i+1)*3+j,(i+1)*3+j+1,i*3+j+1))
 o=mesh('Soft broken foam ribbon',pts,faces,'FFFFFF',recalc=False)
 # Enforce up-facing planar normals independent of centreline direction.
 bm=bmesh.new();bm.from_mesh(o.data)
 for f in bm.faces:
  if f.normal.z<0:f.normal_flip()
 bm.to_mesh(o.data);bm.free();o.data.materials.clear();o.data.materials.append(foam)
 uv=o.data.uv_layers.new(name='UVMap')
 for loop in o.data.loops:
  uv.data[loop.index].uv=uvs[loop.vertex_index]
  o.data.color_attributes['Color'].data[loop.index].color=(1,1,1,alpha[loop.vertex_index])
 records[name].update(kind='static foam alpha sheet',pivot='local water plane Y=0; footprint centre',material='alc_foam_material.tres')
 # Reusable centred footprint, including arcs.
 lo=[min(q[i] for q in pts) for i in range(3)];hi=[max(q[i] for q in pts) for i in range(3)];off=v(((lo[0]+hi[0])/2,0,(lo[2]+hi[2])/2))
 for vert in o.data.vertices:vert.co-=off
 return o
N=7;foam_mesh('alc_foam_strip_a',[(-1.4+2.8*i/(N-1),.035*math.sin(i*1.2)) for i in range(N)],[.58+.05*math.sin(i*.7) for i in range(N)])
N=9;foam_mesh('alc_foam_strip_b',[(-2.4+4.8*i/(N-1),.32*(2*i/(N-1)-1)**2) for i in range(N)],[.70+.04*math.sin(i*.8) for i in range(N)])
N=7;foam_mesh('alc_foam_strip_c',[(1.15*math.cos(math.radians(-47.5+95*i/(N-1))),1.15*math.sin(math.radians(-47.5+95*i/(N-1)))) for i in range(N)],[.58]*N)
N=17;foam_mesh('alc_foam_ring',[(.90*math.cos(2*math.pi*i/(N-1)),.90*math.sin(2*math.pi*i/(N-1))) for i in range(N)],[.50+.035*math.sin(2*math.pi*3*i/(N-1)) for i in range(N)],True)
# Small painted buoy. Waterline pivot; lower bulb lies below Y=0.
group('alc_buoy')
def buoy_color(p,f):
 return rgb('C6CEC3' if .15<p.y<.32 else 'AE6C58' if p.y>.08 else '526869')
lathe('Painted buoy bulb',[(-.18,.13),(-.10,.25),(.08,.27),(.32,.22),(.48,.09),(.51,.09)],buoy_color,8)
lathe('Top neck',[(.50,.052),(.61,.052)],'526869',8)
pts=[];faces=[]
for i in range(8):
 a=2*math.pi*i/8
 for j in range(4):
  b=2*math.pi*j/4;r=.084+.020*math.cos(b);pts.append((r*math.cos(a),.68+r*math.sin(a),.020*math.sin(b)))
for i in range(8):
 for j in range(4):faces.append((i*4+j,((i+1)%8)*4+j,((i+1)%8)*4+(j+1)%4,i*4+(j+1)%4))
mesh('Mooring eye',pts,faces,'6D7B78',True)
records['alc_buoy'].update(kind='decorative floating marker, no light or interaction',pivot='waterline Y=0',material='alc_shore_props_material.tres')
# One weathered floating branch, not a stack of collectible timber.
group('alc_driftwood')
main=lathe('Bleached curved branch',[(-.76,.065),(-.58,.13),(.10,.105),(.74,.045)],'B2AB91',8,(0,.025,0),'x')
for vv in main.data.vertices:
 p=gv(vv.co);p.z+=.075*math.sin(p.x*2.9);p.y+=.025*math.cos(p.x*3);vv.co=v(p)
for idx,(a,b) in enumerate([((-.3,.04,0),(-.55,.10,-.38)),((.2,.05,.03),(.37,.08,.30))]):
 o=lathe('Worn fork %d'%idx,[(0,.055),(.6,.036),(1,.012)],'9C9C87',6,axis='x');direction=Vector(b)-Vector(a)
 q=Vector((1,0,0)).rotation_difference(v(direction).normalized())
 for vv in o.data.vertices:vv.co=q@(vv.co*direction.length)+v(a)
# Small seaweed ribbons caught along the log, shared opaque surface.
for i in range(3):
 x=-.22+i*.19;quad('Trailing kelp %d'%i,[(x,.017,.10),(x+.045,.018,.11),(x+.19,.013,.30+i*.025),(x+.12,.014,.32+i*.025)],'788773')
records['alc_driftwood'].update(kind='single bleached floating branch with three kelp ribbons',pivot='waterline Y=0; footprint centre',material='alc_shore_props_material.tres')
# All parts keep local editable coordinates. Floats are centred horizontally only.
for name in ['alc_buoy','alc_driftwood']:
 col=cols[name];pts=[gv(q.co) for o in col.objects for q in o.data.vertices];off=v(((min(p.x for p in pts)+max(p.x for p in pts))/2,0,(min(p.z for p in pts)+max(p.z for p in pts))/2))
 for o in col.objects:
  for vv in o.data.vertices:vv.co-=off
scene=bpy.context.scene;scene['author']='刘备';scene['task']='SGODOT-424 / independent shoreline foam';scene['axes']='Godot Y up / +Z south; Blender (x,-z,y)'
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'alcatraz_foam.blend'))
# A named untextured export stub avoids embedding the same alpha four times.
foam_stub=bpy.data.materials.new('Foam export stub');foam_stub.use_nodes=True;foam_stub.use_backface_culling=True
foam.name='Alcatraz foam / shared soft alpha SOURCE';foam_stub.name='Alcatraz foam / shared soft alpha'
bs=foam_stub.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*rgb('F0F6EF'),.35);bs.inputs['Roughness'].default_value=1
for name,col in cols.items():
 export=bpy.data.scenes.new('Export '+name);bpy.context.window.scene=export;copies=[]
 for obj in col.objects:
  o=bpy.data.objects.new(obj.name,obj.data.copy());export.collection.objects.link(o);o.select_set(True);copies.append(o)
  if name.startswith('alc_foam'):o.data.materials.clear();o.data.materials.append(foam_stub)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();body=bpy.context.object;body.name=name;body.data.name=name+'_mesh'
 body.data.calc_loop_triangles();tri=len(body.data.loop_triangles);assert tri<=records[name]['triangle_limit'],(name,tri)
 path=OUT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_normals=True,export_texcoords=True,export_animations=False,export_cameras=False,export_lights=False)
 pts=[gv(q.co) for q in body.data.vertices];lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
 records[name].update(file=path.name,triangles=tri,surfaces=1,bounds=[lo,hi],dimensions_m=[hi[i]-lo[i] for i in range(3)],bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
 bpy.context.window.scene=scene;bpy.data.scenes.remove(export)
manifest={'task':'SGODOT-424','author':'刘备','revision':'v1','assets':records,'unique_triangles':sum(r['triangles'] for r in records.values()),'sea_y':-.15,'foam_world_y':-.132,'foam_texture':'alc_foam_soft.png','material_contract':'Four static alpha-blended unshaded foam sheets, no animation, no depth writes, no shadow; two opaque matte vertex-colour floats. Bind external .tres through generated .import.','source':'tools/art/source/alcatraz_foam_424/alcatraz_foam.blend'}
(OUT/'alc_shore_foam_manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
print('FOAM_KIT_READY',[(n,r['triangles']) for n,r in records.items()])
