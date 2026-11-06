"""SGODOT-424 ferry near/far + one gull mesh with three static poses.
Run Blender under flock ~/gs66-render.lock. Never rebuild the island layout.
"""
from pathlib import Path
import sys,math,json,hashlib,importlib.util
import bpy,bmesh
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/landmarks/alcatraz_island'
spec=importlib.util.spec_from_file_location('far_primitives',SRC.parent/'alcatraz_far_424/build.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.PAL={'ivory':'F1EEE1','white':'FFF7E6','shadow':'D7D9CF','hull':'537E8D','stripe':'7E9CA3','glass':'527D8A','glass_light':'96B8BB','deck':'C9AF88','funnel':'667E84','funnel_top':'45585B','ring':'D98559','rope':'DAC9A7','wing':'CDD3D0','tip':'647275','beak':'E2BA60','eye':'34444A','foot':'D3A36D'}
box=p.box;rod=p.rod;mesh=p.mesh;v=p.v

def hull(name,outline,rings,role):
 pts=[(x*sx,y,z*sz) for y,sx,sz in rings for x,z in outline];n=len(outline)
 faces=[tuple(reversed(range(n))),tuple(range((len(rings)-1)*n,len(rings)*n))]
 for j in range(len(rings)-1):
  for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
 return mesh(name,pts,faces,role)
def ellipsoid(name,at,size,role,n=10,rings=5):
 pts=[(at[0],at[1]-size[1]/2,at[2])];faces=[]
 for j in range(1,rings):
  a=-math.pi/2+math.pi*j/rings
  for i in range(n):
   b=i*math.tau/n;pts.append((at[0]+size[0]/2*math.cos(a)*math.cos(b),at[1]+size[1]/2*math.sin(a),at[2]+size[2]/2*math.cos(a)*math.sin(b)))
 top=len(pts);pts.append((at[0],at[1]+size[1]/2,at[2]))
 for i in range(n):faces.append((0,1+(i+1)%n,1+i));faces.append((top,1+(rings-2)*n+i,1+(rings-2)*n+(i+1)%n))
 for j in range(rings-2):
  for i in range(n):a=1+j*n+i;b=1+j*n+(i+1)%n;faces.append((a,b,b+n,a+n))
 return mesh(name,pts,faces,role,True)
def rail_path(name,points,y,far):
 for a,b in zip(points,points[1:]):
  rod(name+' rounded top',(a[0],y+.92,a[1]),(b[0],y+.92,b[1]),.055,'ivory',4 if far else 6)
  if not far:rod(name+' lower bar',(a[0],y+.43,a[1]),(b[0],y+.43,b[1]),.032,'ivory',4)
 for x,z in points:rod(name+' upright',(x,y,z),(x,y+.92,z),.045,'ivory',4)
def lifering(x,y,z,far):
 n=8 if far else 14;m=4 if far else 6;pts=[];faces=[];roles=[]
 for i in range(n):
  a=i*math.tau/n
  for j in range(m):
   b=j*math.tau/m;r=.40+.095*math.cos(b);pts.append((x+r*math.cos(a),y+r*math.sin(a),z+.095*math.sin(b)))
 for i in range(n):
  for j in range(m):faces.append((i*m+j,((i+1)%n)*m+j,((i+1)%n)*m+(j+1)%m,i*m+(j+1)%m));roles.append('ring' if (i*4//n)%2==0 else 'white')
 mesh('Coral and ivory lifebuoy',pts,faces,roles,True)
def ferry(far=False):
 outline=[(-12.5,0),(-11.8,-1.35),(-10.2,-2.55),(-8.5,-3.10),(10.8,-3.10),(12.15,-2.65),(12.5,-1.85),(12.5,1.85),(12.15,2.65),(10.8,3.1),(-8.5,3.1),(-10.2,2.55),(-11.8,1.35)]
 hull('Rounded blue passenger hull',outline,[(-1,.86,.68),(-.65,.96,.90),(.85,1,1),(1.20,1,1)],'hull')
 hull('Ivory gunwale',outline,[(1.20,1,1),(1.43,1,1)],'ivory')
 hull('Warm exposed lower deck',outline,[(1.43,.98,.96),(1.48,.98,.96)],'deck')
 # Two separate passenger levels, softened deck ledges and forward wheelhouse.
 bevel=0 if far else .10
 box('Lower passenger cabin',(1.0,2.60,0),(18.4,2.24,4.60),'ivory',bevel)
 box('Lower deck roof',(1.0,3.82,0),(19.1,.20,5.35),'white',bevel)
 box('Upper passenger salon',(2.15,4.83,0),(12.8,1.84,4.03),'ivory',bevel)
 box('Upper salon roof',(2.15,5.84,0),(13.5,.20,4.60),'white',bevel)
 box('Front wheelhouse',(-5.35,4.86,0),(3.50,1.90,3.75),'ivory',bevel)
 box('Wheelhouse roof',(-5.35,5.88,0),(3.9,.16,4.1),'white',bevel)
 for side in (-1,1):
  for x in [-6.3,-4.3,-2.3,-.3,1.7,3.7,5.7,7.7]:
   box('Lower unbarred passenger pane',(x,2.77,side*2.309),(1.28,1.10,.035),'glass',0 if far else .085)
  for x in [-3, -.8,1.4,3.6,5.8,7.2]:
   box('Upper passenger pane',(x,4.98,side*2.024),(1.28,.88,.035),'glass',0 if far else .065)
  box('Wheelhouse side glass',(-5.35,5.06,side*1.89),(2.35,.84,.035),'glass',0 if far else .045)
  if not far:
   for x in [-6.3,-2.3,1.7,5.7]:box('Window quiet sky reflection',(x-.32,3.16,side*2.33),(.58,.10,.018),'glass_light')
   for x in [-3,1.4,5.8]:box('Upper sky reflection',(x-.30,5.30,side*2.045),(.60,.10,.018),'glass_light')
  box('Cabin sill blue stripe',(1,1.91,side*2.32),(17.8,.13,.04),'stripe')
  box('Upper cabin blue stripe',(2.15,4.30,side*2.035),(12.3,.12,.035),'stripe')
  for x in [-7.7,9.45]:box('Passenger door',(x,2.54,side*2.325),(.58,1.70,.04),'shadow',0 if far else .03)
  for x in ([-4.2,6.1] if not far else [-4.2]):lifering(x,2.14,side*2.44,far)
  if not far:
   for x in [-9,-2,5,11]:
    ellipsoid('Hanging ivory fender',(x,.65,side*3.17),(.34,.85,.30),'rope',8,4)
    rod('Fender tie',(x,1.65,side*3.05),(x,1.02,side*3.17),.025,'rope',4)
 for z in [-1.13,0,1.13]:box('Forward bridge windshield',(-7.111,5.05,z),(.035,.89,.87),'glass',0 if far else .045)
 for z in [-1.35,0,1.35]:box('Lower bow cabin glazing',(-8.211,2.83,z),(.035,1.02,.95),'glass',0 if far else .06)
 # Funnel stays comfortably within hull length; broad, simple cap, no smoke particles.
 p.lathe('Blue grey funnel',[(5.94,.73),(6.12,.76),(7.45,.62),(7.63,.66)],'funnel',8 if far else 16,center=(6.05,0,0))
 p.lathe('Funnel dark lip',[(7.50,.67),(7.68,.67)],'funnel_top',8 if far else 16,center=(6.05,0,0))
 # Thin top insert reads as a dark chimney mouth, rather than an extra object.
 if not far:
  p.lathe('Funnel opening',[(7.686,.49),(7.69,.49)],'funnel_top',12,center=(6.05,0,0))
  rod('Short navigation mast',(-4.6,5.96,0),(-4.6,7.15,0),.045,'ivory',6)
  rod('Mast crossbar',(-4.6,6.85,-.50),(-4.6,6.85,.50),.035,'ivory',6)
 # Rounded rails: broad outer path on open bow/stern + upper promenade.
 bow=[(-8.45,-2.91),(-10.05,-2.41),(-11.5,-1.25),(-12.12,0),(-11.5,1.25),(-10.05,2.41),(-8.45,2.91)]
 stern=[(9.50,-2.91),(11.70,-2.5),(12.10,-1.7),(12.10,1.7),(11.70,2.5),(9.50,2.91)]
 rail_path('Open bow rail',bow,1.48,far);rail_path('Stern rail',stern,1.48,far)
 for side in [-1,1]:
  rail_path('Upper promenade rail',[(x,side*2.55) for x in ([-8.20,1,10.20] if far else [-8.20,-5,-2,1,4,7,10.20])],3.94,far)
 rail_path('Promenade rear return',[(10.20,-2.55),(10.20,0),(10.20,2.55)],3.94,far)
 if not far:
  for x in [10.0,11.0]:
   box('Stern deck bollard foot',(x,1.55,0),(.45,.14,.65),'funnel',.03)
   rod('Low stern mooring cleat',(x,1.62,-.28),(x,1.62,.28),.055,'funnel',6)
 return {'style':'25m white passenger ferry; two cabin levels, blue hull, rounded rails, funnel and lifebuoys','long_axis':'X; bow -X, matching b16c3198 original','origin':'original ferry waterline-axis centre; y=0; submerged hull to -1m','cast_shadow':False,'clickable':False,'lod_switch_m':55}

def make_gull():
 # Named source parts define shape-key masks after merging. Feet stay fixed.
 ellipsoid('Torso',(0,.27,0),(.28,.32,.46),'white',12,6)
 ellipsoid('Head',(0,.47,-.18),(.22,.22,.22),'white',10,5)
 mesh('Beak',[(-.055,.45,-.26),(.055,.45,-.26),(.045,.49,-.26),(-.045,.49,-.26),(0,.46,-.40)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(0,3,2,1)],'beak')
 for side in [-1,1]:
  mesh('Eye',[(side*.107,.505,-.205),(side*.112,.48,-.205),(side*.105,.482,-.23)],[(0,1,2)],'eye')
  rod('Leg',(side*.075,.035,0),(side*.075,.15,0),.017,'foot',4)
  mesh('Webbed foot',[(side*.075-.05,0,.025),(side*.075+.05,0,.025),(side*.075+.065,0,-.08),(side*.075,0,-.11),(side*.075-.065,0,-.08)],[(0,1,2,3,4)],'foot')
  wing=[(side*.075,.38,-.10),(side*.195,.31,-.04),(side*.19,.22,.21),(side*.12,.19,.33),(side*.09,.17,.23),(side*.075,.23,.08)]
  # Broad root intersects torso. Tip corners keep a simple feather silhouette.
  pts=wing+[(x+side*.018,y,z) for x,y,z in wing]
  faces=[(0,1,2,5),(2,3,4,5),(6,11,8,7),(8,11,10,9)]+[(i,(i+1)%6,(i+1)%6+6,i+6) for i in range(6)]
  mesh('Wing_L' if side<0 else 'Wing_R',pts,faces,['wing','tip','wing','tip']+['wing']*6)
 mesh('Tail',[(-.09,.21,.18),(.09,.21,.18),(.11,.16,.37),(-.11,.16,.37),(0,.26,.20)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(0,3,2,1)],'tip')
 return {'style':'quiet perched gull, ivory body, grey wings, muted ochre beak/feet','poses':['stand','preen','spread'],'front':'-Z, matching original gull; no placement yaw changes','cast_shadow':False,'clickable':False,'animation':None,'pose_selection':'stand: both weights 0; preen: preen=1; spread: spread=1; never both at once'}

def export(name,builder):
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.context.preferences.filepaths.save_version=0
 p.PARTS=[];p.MATS={};p.PIVOT=bpy.data.objects.new(name+' / original placement pivot',None);bpy.context.scene.collection.objects.link(p.PIVOT)
 p.PIVOT['task']='SGODOT-424';p.PIVOT['author']='黄忠';extra=builder();bpy.context.view_layer.update()
 source=bpy.context.scene;deps=bpy.context.evaluated_depsgraph_get()
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
 flat=bpy.data.materials.new('Ferry gull matte vertex colour');flat.use_nodes=True
 q=flat.node_tree.nodes['Principled BSDF'];q.inputs['Base Color'].default_value=(1,1,1,1);q.inputs['Roughness'].default_value=.94;q.inputs['Specular IOR Level'].default_value=.15
 c=flat.node_tree.nodes.new('ShaderNodeVertexColor');c.layer_name='Color';flat.node_tree.links.new(c.outputs['Color'],q.inputs['Base Color'])
 exp=bpy.data.scenes.new('Export');copies=[]
 for obj in p.PARTS:
  d=bpy.data.meshes.new_from_object(obj.evaluated_get(deps));d.transform(obj.matrix_world)
  col=d.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
  for f in d.polygons:
   color=d.materials[f.material_index].diffuse_color
   for i in f.loop_indices:col.data[i].color=color
  d.materials.clear();d.materials.append(flat)
  for f in d.polygons:f.material_index=0
  d.color_attributes.active_color=col;d.color_attributes.render_color_index=0
  o=bpy.data.objects.new(obj.name,d);exp.collection.objects.link(o);copies.append(o)
  if name=='gull':g=o.vertex_groups.new(name=obj.name.split('.')[0]);g.add(list(range(len(d.vertices))),1,'REPLACE')
 bpy.context.window.scene=exp
 for o in copies:o.select_set(True)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();body=bpy.context.object;body.name=name;body.data.name=name+'_mobile'
 bm=bmesh.new();bm.from_mesh(body.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free()
 if name=='gull':
  basis=body.shape_key_add(name='stand');preen=body.shape_key_add(name='preen');spread=body.shape_key_add(name='spread')
  for i,vert in enumerate(body.data.vertices):
   group=body.vertex_groups[vert.groups[0].group].name if vert.groups else ''
   # Blender coordinates -> Godot for easily auditable pose dimensions.
   x,y,z=vert.co.x,vert.co.z,-vert.co.y
   if group.startswith(('Head','Beak','Eye')):
    # Turn back into the right shoulder while keeping the root/feet still.
    preen.data[i].co=v((.115+(x*.75),.345+(y-.47)*.8,.13-(z+.18)*.8))
   if group.startswith('Wing_'):
    side=-1 if x<0 else 1
    # Same broad shoulder root, outstretched quiet curved feather silhouette.
    folded=[(.075,.38,-.10),(.195,.31,-.04),(.19,.22,.21),(.12,.19,.33),(.09,.17,.23),(.075,.23,.08)]
    openwing=[(.065,.36,-.08),(.34,.44,-.02),(.64,.40,.13),(.61,.33,.23),(.35,.28,.18),(.065,.24,.08)]
    candidates=[(Vector((a+(0.018 if layer else 0),b,c)),j,layer) for layer in (0,1) for j,(a,b,c) in enumerate(folded)]
    original=Vector((abs(x),y,z));_,j,layer=min(candidates,key=lambda t:(t[0]-original).length)
    a,b,c=openwing[j];spread.data[i].co=v((side*a,b+.018*layer,c))
  bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'gull_export_poses.blend'))
 body.data.calc_loop_triangles();tri=len(body.data.loop_triangles);path=KIT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_normals=True,export_texcoords=False,export_animations=False,export_morph=True,export_morph_normal=True,export_cameras=False,export_lights=False)
 coords=[(q.co.x,q.co.z,-q.co.y) for q in body.data.vertices];lo=[min(q[i] for q in coords) for i in range(3)];hi=[max(q[i] for q in coords) for i in range(3)]
 row={'file':name+'.glb','triangles':tri,'surfaces':1,'bounds':[lo,hi],'dimensions_m':[hi[i]-lo[i] for i in range(3)],'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'source':str((SRC/(name+'.blend')).relative_to(ROOT)),**extra}
 if name=='gull':
  row['pose_bounds']={}
  for key in body.data.shape_keys.key_blocks:
   coords=[(q.co.x,q.co.z,-q.co.y) for q in key.data];row['pose_bounds'][key.name]=[[min(q[i] for q in coords) for i in range(3)],[max(q[i] for q in coords) for i in range(3)]]
 bpy.context.window.scene=source;bpy.data.scenes.remove(exp);print(name,tri,row['dimensions_m'],flush=True);return row

def main():
 KIT.mkdir(parents=True,exist_ok=True)
 entries={n:export(n,b) for n,b in [('ferry',lambda:ferry(False)),('ferry_far',lambda:ferry(True)),('gull',make_gull)]}
 layout=json.loads((SRC/'reference/layout-b16c3198.json').read_text());points=[x for x in layout['placements'] if x['asset'] in ['ferry','gull']]
 manifest={'task':'SGODOT-424','revision':'v1','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','units':'metres / Y up / unit transforms','host_ref':'b16c31982f34a64cdd4f9c6683064edbf20837a0','palette_srgb':p.PAL,'assets':entries,'placements':points,'ferry_lod_group':{'name':'ferry','near':'ferry','far':'ferry_far','switch_distance_m':55,'margin_m':0},'gull_pose_by_instance':{'gull_000':'stand','gull_001':'preen','gull_002':'spread'},'interaction':'decorative; no collision, click target, particles or locomotion'}
 (KIT/'ferry_gull_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
