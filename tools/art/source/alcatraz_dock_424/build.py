"""SGODOT-424 dock kit, 刘备. Blender (x,-z,y) -> Godot metre/Y-up.
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
mat=bpy.data.materials.new('Alcatraz dock / matte vertex colour');mat.use_nodes=True;mat.use_backface_culling=True
bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.94;bs.inputs['Specular IOR Level'].default_value=.15
colnode=mat.node_tree.nodes.new('ShaderNodeVertexColor');colnode.layer_name='Color';mat.node_tree.links.new(colnode.outputs['Color'],bs.inputs['Base Color'])
cols={};records={};current=None
def group(name):
 global current
 current=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(current);cols[name]=current
 records[name]={'triangle_limit':400,'owner':'刘备','placeholder':False}
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
# Squat cast-iron harbour bollard, chamfered octagonal shoulder and horn.
group('alc_dock_bollard')
lathe('Cast base and taper',[(0,.235),(.07,.235),(.095,.18),(.43,.12),(.50,.175),(.57,.175),(.60,.145)],'iron',8)
lathe('Cross horn',[(-.31,.085),(-.27,.10),(.27,.10),(.31,.085)],'iron_top',8,(0,.43,0),'x')
for x,z in [(-.15,-.15),(.15,-.15),(-.15,.15),(.15,.15)]:lathe('Recessed fixing bolt',[(.07,.025),(.09,.025)],'iron_top',6,(x,0,z))
# Three compact transport crates and a real continuous polygonal rope coil.
group('alc_dock_crates')
def crate(label,c,size):
 x,y,z=c;w,h,d=size;box(label+' solid',c,size,'wood')
 # Flush front and rear inlaid boards, low-cost opaque geometry.
 for side in [-1,1]:
  zz=z+side*(d/2+.002)
  for yy in [y-h*.34,y+h*.34]:quad(label+' horizontal batten',[(x-w/2,yy-.035,zz),(x+w/2,yy-.035,zz),(x+w/2,yy+.035,zz),(x-w/2,yy+.035,zz)],'wood_light')
  zz=z+side*(d/2+.004)
  for xx in [x-w*.34,x+w*.34]:quad(label+' edge batten',[(xx-.033,y-h/2,zz),(xx+.033,y-h/2,zz),(xx+.033,y+h/2,zz),(xx-.033,y+h/2,zz)],'wood_dark')
  zz=z+side*(d/2+.006)
  for xx in [-.16,.16]:quad(label+' plank seam',[(x+xx-.004,y-h/2,zz),(x+xx+.004,y-h/2,zz),(x+xx+.004,y+h/2,zz),(x+xx-.004,y+h/2,zz)],'wood_dark')
crate('Lower crate',(-.38,.24,0),(.74,.48,.58))
crate('Upper crate',(-.40,.67,-.025),(.57,.38,.49))
crate('Side crate',(.30,.19,-.13),(.53,.38,.46))
pts=[];faces=[];count=25
for i in range(count+1):
 a=math.pi*.2+i/count*math.pi*4.4;r=.15+.0055*i
 center=Vector((.29+r*math.cos(a),.047,.36+r*math.sin(a)))
 for j in range(4):
  q=j*math.pi/2;pts.append(center+Vector((math.cos(a)*math.cos(q)*.027,math.sin(q)*.027,math.sin(a)*math.cos(q)*.027)))
for i in range(count):
 for j in range(4):faces.append((i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j))
faces += [(3,2,1,0),tuple(count*4+j for j in range(4))]
mesh('Continuous two-turn rope coil',pts,faces,'rope',True)
# Slim row of two 1.45m benches; positioned lengthwise on the pier.
group('alc_dock_shelter')
for x in [-1.53,1.53]:
 for z in [-.37,.37]:box('Ivory canopy upright',(x,1.19,z),(.075,2.38,.075),'frame')
box('Back lintel',(0,2.31,-.37),(3.16,.11,.09),'sage');box('Front lintel',(0,2.31,.37),(3.16,.11,.09),'sage')
for x in [-1.53,1.53]:beam('Short knee brace',(x,1.98,-.37),(x,2.31,.01),.055,.055,'frame')
# Solid gently pitched canopy, cream with sage cloth stripes, both sides.
for j in range(6):
 x0=-1.65+j*3.3/6;x1=x0+3.3/6
 pts=[(x0,2.36,-.50),(x1,2.36,-.50),(x1,2.55,0),(x0,2.55,0),(x0,2.36,.50),(x1,2.36,.50)]
 pts += [(x,y-.045,z) for x,y,z in pts]
 faces=[(0,1,2,3),(3,2,5,4),(6,9,8,7),(9,10,11,8),(0,6,7,1),(4,5,11,10),(0,3,4,10,9,6),(1,7,8,11,5,2)]
 mesh('Canvas stripe %02d'%j,pts,faces,'sage' if j in [0,2,3,5] else 'canvas')
for center in [-.78,.78]:
 for z in [-.17,.03,.23]:box('Seat slat',(center,.42,z),(1.45,.06,.15),'wood_light')
 for y in [.65,.86]:box('Backrest slat',(center,y,-.24),(1.45,.14,.055),'wood')
 for x in [center-.54,center+.54]:box('Bench trestle',(x,.20,.025),(.08,.40,.44),'sage')
# Blank welcome panel: bevelled octagonal silhouette, 2 posts, no text/decal.
group('alc_dock_welcome')
for x in [-.38,.38]:
 box('Welcome upright',(x,.78,0),(.075,1.56,.08),'wood_dark')
 box('Welcome foot',(x,.04,0),(.16,.08,.30),'wood_dark')
outline=[(-.52,.85),(.52,.85),(.57,.90),(.57,1.47),(.50,1.55),(-.50,1.55),(-.57,1.47),(-.57,.90)]
pts=[(x,y,z) for z in [-.065,.065] for x,y in outline]
faces=[tuple(reversed(range(8))),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
mesh('Blank board frame',pts,faces,'sage')
quad('Blank cream face',[(-.49,.94,.066),(.49,.94,.066),(.49,1.43,.066),(-.49,1.43,.066)],'sign')
quad('Blank cream back',[(.49,.94,-.066),(-.49,.94,-.066),(-.49,1.43,-.066),(.49,1.43,-.066)],'sign')
# Large tapered flower box, two instances requested. All geometry opaque.
group('alc_dock_planter')
pts=[(x*w,y,z*d) for y,w,d in [(0,.53,.25),(.48,.65,.32)] for x,z in [(-1,-1),(1,-1),(1,1),(-1,1)]]
mesh('Tapered terracotta box',pts,[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'terra')
for z in [-.30,.30]:box('Long rim',(0,.49,z),(1.34,.07,.075),'rim')
for x in [-.63,.63]:box('End rim',(x,.49,0),(.075,.07,.58),'rim')
quad('Recessed soil',[(-.58,.46,-.25),(.58,.46,-.25),(.58,.46,.25),(-.58,.46,.25)],'soil')
for i,(x,z,s) in enumerate([(-.44,0,.38),(-.16,-.06,.42),(.14,.07,.46),(.43,-.04,.36),(.04,-.18,.32)]):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1);o=bpy.context.object
 pts=[Vector((x,.61,z))+Vector((gv(t.co).x*s/2,gv(t.co).y*.24,gv(t.co).z*.25)) for t in o.data.vertices];faces=[tuple(p.vertices) for p in o.data.polygons];bpy.data.objects.remove(o,do_unlink=True)
 mesh('Leaf cushion %d'%i,pts,faces,'leaf_light' if i%2 else 'leaf',True)
for i,(x,z,h) in enumerate([(-.46,.08,.89),(-.27,-.12,1.02),(-.02,.14,.93),(.16,-.12,1.06),(.38,.12,.92),(.48,-.13,.98)]):
 lathe('Flower stem',[(.55,.011),(h,.011)],'leaf',3,(x,0,z))
 color=['white','yellow','lilac'][i%3];pts=[];faces=[]
 for k in range(5):
  a=k*math.tau/5;d=Vector((math.cos(a),0,math.sin(a)));side=Vector((-math.sin(a),0,math.cos(a)));c=Vector((x,h,z))
  pts.extend([c+d*.018,c+d*.08+side*.04+Vector((0,.018,0)),c+d*.145+Vector((0,.01,0)),c+d*.08-side*.04+Vector((0,.018,0))]);q=k*4;faces.extend([(q,q+1,q+2,q+3),(q+3,q+2,q+1,q)])
 # Separate back vertices keep glTF/BMesh from collapsing opposite faces.
 faces=faces[::2];pts=pts+pts.copy();faces+= [tuple(j+20 for j in reversed(f)) for f in faces]
 # Explicit front and back flower petals, included in the triangle budget.
 obj=mesh('Five petals %d'%i,pts,faces,color,False,False)
 mesh('Ochre flower centre',[(x,h+.03,z)]+[(x+.033*math.cos(a*math.tau/5),h+.018,z+.033*math.sin(a*math.tau/5)) for a in range(5)],[(0,1+a,1+(a+1)%5) for a in range(5)],'pollen')
for o in cols['alc_dock_welcome'].objects:
 for vert in o.data.vertices:vert.co.x*=.74
# Centre all module pivots at footprint / floor, retain individually named parts.
scene=bpy.context.scene;scene['author']='刘备';scene['task']='SGODOT-424 dock';scene['axes']='Godot metres Y-up / Blender x,-z,y'
for name,col in cols.items():
 pts=[gv(vv.co) for o in col.objects for vv in o.data.vertices]
 lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)];offset=v(((lo[0]+hi[0])/2,lo[1],(lo[2]+hi[2])/2))
 for o in col.objects:
  for vert in o.data.vertices:vert.co-=offset
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'alcatraz_dock.blend'))
for name,col in cols.items():
 export=bpy.data.scenes.new('Export '+name);bpy.context.window.scene=export;copies=[]
 for o in col.objects:
  obj=bpy.data.objects.new(o.name,o.data.copy());export.collection.objects.link(obj);obj.select_set(True);copies.append(obj)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();body=bpy.context.object;body.name=name;body.data.calc_loop_triangles();tri=len(body.data.loop_triangles)
 assert tri<=400,(name,tri)
 path=OUT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_normals=True,export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False)
 pts=[gv(vv.co) for vv in body.data.vertices];lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
 records[name].update(file=path.name,triangles=tri,surfaces=1,dimensions_m=[hi[i]-lo[i] for i in range(3)],bounds=[lo,hi],parts=len(col.objects),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytes=path.stat().st_size,pivot='ground / footprint centre',front='+Z')
 bpy.context.window.scene=scene;bpy.data.scenes.remove(export)
manifest={'task':'SGODOT-424 dock','author':'刘备','axes':'metres, Y up, +Z front / south','source_layout_commit':'b16c31982f34a64cdd4f9c6683064edbf20837a0','assets':records,'palette_srgb':P,'triangles_total':sum(a['triangles'] for a in records.values()),'material':'alc_dock_material.tres; opaque vertex colour; roughness .94 / specular .15 / metallic 0; no texture'}
(OUT/'alc_dock_manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n');print('ALC_DOCK_READY',[(k,v['triangles']) for k,v in records.items()])
