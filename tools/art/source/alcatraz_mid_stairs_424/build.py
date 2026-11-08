"""Incremental physical stairs/landings and clipped ground. Run Blender with flock.
Imported base GLBs are pinned to the accepted art head; other assets are not exported.
"""
from pathlib import Path
import bpy,sys,json,subprocess,math,hashlib
from mathutils import Vector,Matrix
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];OUT=ROOT/'assets/landmarks/alcatraz_island'
sys.path.insert(0,str(ROOT/'tools/art'));from landmark_kit import Kit,reset_scene
reset_scene();palette=json.loads((HERE.parent/'alcatraz_island/palette.json').read_text())['colors'];kit=Kit(OUT,palette)
C=json.loads((HERE/'construction.json').read_text());flights=C['flights']
kit.begin('alc_mid_stairs',ao=False)
def block(name,x0,x1,z0,z1,low,high):
 # Separate top colour keeps the existing terrain shader's road/stone distinction.
 v=[(x,y,z) for y in [low,high] for x,z in [(x0,z0),(x0,z1),(x1,z1),(x1,z0)]]
 obj=kit.mesh(name,v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'stone_shade')
 obj.data.materials.append(kit.mats['road']);obj.data.polygons[1].material_index=1
 return obj
for s in flights:
 for i in range(15):
  xa=s['x0']+i*.3 if s['east_up'] else s['x1']-i*.3;xb=xa+.3 if s['east_up'] else xa-.3
  block(f'mid{s["id"]}_tread_{i+1:02d}',min(xa,xb),max(xa,xb),s['z0'],s['z1'],s['low']-.2,s['low']+(i+1)*.15)
 for kind,y in [('lower',s['low']),('upper',s['high'])]:
  a,b,c,d=s[kind+'_platform'];block(f'mid{s["id"]}_{kind}_landing',a,b,c,d,s['low']-.2,y)
kit.begin('alc_railing_endpost',ao=False)
kit.box('Matching stone terminal',(0,.49,0),(.18,.98,.18),'stone',.012)
kit.box('Terminal cap',(0,1.0,0),(.22,.08,.22),'stone_light',.012)
kit.box('Terminal foot',(0,.05,0),(.22,.10,.22),'stone',.012)
for obj in bpy.data.objects:
 for mod in obj.modifiers:
  if mod.type=='BEVEL':mod.segments=1
stats=(json.loads((HERE/'geometry_report.json').read_text())['assets']
       if '--terraces-only' in sys.argv else {name:kit.export(name) for name in kit.assets})
# Subtract the exact construction volumes from existing triangle surfaces, with
# interpolated vertex colour/UV. No broad rebuild, recolouring or ground UV reset.
# The new closed stairs/landing solids fill these openings; top-mouth cuts remove
# the former retaining-wall face and its trimesh collision at each crossing.
BASE='edd184d65'
cutters=[]
for s in flights:
 for label,r in [('flight',[s['x0'],s['x1'],s['z0'],s['z1']]),('lower',s['lower_platform']),('upper',s['upper_platform'])]:
  cutters.append({'name':f'mid{s["id"]}_{label}','min':[r[0],s['low']-.15,r[2]],'max':[r[1],s['high']+.03,r[3]]})
def split(poly,axis,value):
 inside=[];outside=[]
 for a,b in zip(poly,poly[1:]+poly[:1]):
  da=a['p'][axis]-value;db=b['p'][axis]-value
  # A vertex on the cutting plane belongs to BOTH half-polygons. Successive
  # neighbouring cutters share planes; assigning their boundary vertices only
  # to one side collapsed otherwise untouched road triangles to two vertices.
  if da<=1e-7:inside.append(a)
  if da>=-1e-7:outside.append(a)
  if (da < -1e-7 and db > 1e-7) or (da > 1e-7 and db < -1e-7):
   t=da/(da-db);v={k:[x+(y-x)*t for x,y in zip(a[k],b[k])] for k in a};inside.append(v);outside.append(v)
 return inside,outside
def subtract(poly,cut):
 remainder=poly;kept=[]
 for axis in range(3):
  # Keep below minimum; continue clipping the part inside the box.
  below,above=split(remainder,axis,cut['min'][axis])
  if len(below)>=3:kept.append(below)
  remainder=above
  if len(remainder)<3:return kept
  below,above=split(remainder,axis,cut['max'][axis])
  if len(above)>=3:kept.append(above)
  remainder=below
  if len(remainder)<3:return kept
 return kept
report={}
for name in ['alc_ground_terraces','alc_ground_summit']:
 temp=ROOT/'output/alcatraz-mid-stairs-424'/('baseline_'+name+'.glb');temp.parent.mkdir(parents=True,exist_ok=True);temp.write_bytes(subprocess.check_output(['git','show',BASE+':assets/landmarks/alcatraz_island/'+name+'.glb'],cwd=ROOT))
 before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(temp));imported=set(bpy.data.objects)-before
 objects=[o for o in imported if o.type=='MESH'];assert len(objects)==1
 obj=objects[0];mesh=obj.data;mesh.calc_loop_triangles();color=mesh.color_attributes.active_color;uv=mesh.uv_layers.active
 fragments=[];touched=0
 for tri in mesh.loop_triangles:
  poly=[]
  for li in tri.loops:
   vi=mesh.loops[li].vertex_index;p=obj.matrix_world@mesh.vertices[vi].co
   v={'p':[p.x,p.z,-p.y],'n':list((obj.matrix_world.to_3x3() @ mesh.corner_normals[li].vector).normalized())}
   if color:v['c']=list(color.data[li if color.domain=='CORNER' else vi].color)
   if uv:v['uv']=list(uv.data[li].uv)
   poly.append(v)
  pieces=[poly]
  for cut in cutters:
   next_parts=[]
   for piece in pieces:
    lo=[min(v['p'][k] for v in piece) for k in range(3)];hi=[max(v['p'][k] for v in piece) for k in range(3)]
    if any(hi[k]<cut['min'][k]+1e-7 or lo[k]>cut['max'][k]-1e-7 for k in range(3)):next_parts.append(piece)
    else:next_parts.extend(subtract(piece,cut))
   pieces=next_parts
  if pieces!=[poly]:touched+=1
  fragments.extend(pieces)
 verts=[];faces=[];records=[]
 for poly in fragments:
  for i in range(1,len(poly)-1):
   chosen=[poly[0],poly[i],poly[i+1]];pa,pb,pc=[Vector(v['p']) for v in chosen]
   if (pb-pa).cross(pc-pa).length<1e-9:continue
   faces.append(tuple(range(len(verts),len(verts)+3)))
   for v in chosen:verts.append((v['p'][0],-v['p'][2],v['p'][1]));records.append(v)
 data=bpy.data.meshes.new(name+'_openings');data.from_pydata(verts,[],faces);data.update();original_materials=list(mesh.materials)
 for m in original_materials:data.materials.append(m)
 if color:
  ca=data.color_attributes.new(name=color.name,type='FLOAT_COLOR',domain='CORNER');data.color_attributes.active_color=ca;data.color_attributes.render_color_index=data.color_attributes.find(color.name)
  for i,v in enumerate(records):ca.data[i].color=v['c']
 if uv:
  ua=data.uv_layers.new(name=uv.name)
  for i,v in enumerate(records):ua.data[i].uv=v['uv']
 obj.data=data;obj.parent=None;obj.matrix_world=Matrix.Identity(4);obj.name=name
 for f in data.polygons:f.use_smooth=True
 data.normals_split_custom_set([v['n'] for v in records])
 bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
 # The incremental top-face repair exports only terraces; keep the already
 # verified summit bytes (its geometry is also present in the editable blend).
 if '--terraces-only' not in sys.argv or name=='alc_ground_terraces':
  bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_attributes=False,export_vertex_color='ACTIVE',export_cameras=False,export_lights=False,export_animations=False)
 report[name]={'source':BASE,'input_triangles':len(mesh.loop_triangles),'cut_triangles':touched,'output_triangles':len(faces),'vertex_colors_preserved':bool(color),'uv_preserved':bool(uv)}
 stats[name]={'triangles':len(faces),'bytes':(OUT/(name+'.glb')).stat().st_size}
# Editable reconstruction: named treads/landings, terminals, cut ground and named cutters.
col=bpy.data.collections.new('Opening_Volumes_reference');bpy.context.scene.collection.children.link(col)
for cut in cutters:
 a,b=cut['min'],cut['max'];bpy.ops.mesh.primitive_cube_add(size=1,location=kit.v([(a[k]+b[k])/2 for k in range(3)]));o=bpy.context.object;o.name=cut['name']+'_cutter';o.scale=(b[0]-a[0],b[2]-a[2],b[1]-a[1]);o.display_type='WIRE';o.hide_render=True
 for c in list(o.users_collection):c.objects.unlink(o)
 col.objects.link(o)
col.hide_render=True
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'alcatraz_mid_stairs.blend'))
for name,row in stats.items():row.update(sha256=hashlib.sha256((OUT/(name+'.glb')).read_bytes()).hexdigest(),source='tools/art/source/alcatraz_mid_stairs_424/alcatraz_mid_stairs.blend',author='马可波罗')
manifest=json.loads((OUT/'manifest.json').read_text());manifest['assets'].update(stats);(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(HERE/'geometry_report.json').write_text(json.dumps({'cutters':cutters,'ground':report,'assets':stats},indent=2)+'\n')
print('MID_STAIRS_GEOMETRY',json.dumps(report),flush=True)
