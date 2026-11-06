"""Roof-only far LOD update pinned to #835. Run Blender with shared flock."""
from pathlib import Path
import sys,json,hashlib,subprocess,struct,collections,importlib.util,math
import bpy,bmesh
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/landmarks/alcatraz_island';OUT=ROOT/'output/museum-far-roof-424'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
spec=importlib.util.spec_from_file_location('old_far',SRC.parent/'alcatraz_museum_far_424/build.py');old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
REF=json.loads((SRC/'provenance.json').read_text());CONTRACT=json.loads((SRC/'contract.json').read_text())
COLORS=CONTRACT['colors_srgb'];objects=[];parts=[];normal_lookup=collections.defaultdict(list)
def linear(h):return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in [x/255 for x in bytes.fromhex(h)])+(1,)
def vec(v):return Vector((v[0],-v[2],v[1]))
def read_asset(name):
 path=OUT/('baseline_'+name);path.write_bytes((SRC/'reference'/name).read_bytes())
 d,b=load_glb(path);p=d['meshes'][0]['primitives'][0]
 return d,accessor(d,b,p['attributes']['POSITION']),accessor(d,b,p['attributes']['NORMAL']),accessor(d,b,p['attributes']['COLOR_0']),[list(x) for x in zip(*[iter([i[0] for i in accessor(d,b,p['indices'])])]*3)]
def put(name,vertices,faces,normals,colors,method):
 me=bpy.data.meshes.new(name);me.from_pydata([vec(v) for v in vertices],[],faces);me.update();me.materials.append(MAT)
 ca=me.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
 for i,c in enumerate(colors):ca.data[i].color=c
 me.color_attributes.active_color=ca;me.color_attributes.render_color_index=0
 for face in me.polygons:face.use_smooth=True
 me.normals_split_custom_set([vec(n) for n in normals])
 ob=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(ob);objects.append(ob)
 loop=0
 for face in faces:
  for index in face:normal_lookup[tuple(vertices[index])].append(tuple(normals[loop]));loop+=1
 me.calc_loop_triangles()
 bounds=[[min(v[j] for v in vertices) for j in range(3)],[max(v[j] for v in vertices) for j in range(3)]]
 parts.append({'name':name,'far_triangles':len(me.loop_triangles),'method':method,'source_bounds':bounds})
def keep(name,v,n,c,triangles,method):
 ids=sorted({i for t in triangles for i in t});mapping={i:j for j,i in enumerate(ids)}
 put(name,[v[i] for i in ids],[tuple(mapping[i] for i in t) for t in triangles],[n[i] for t in triangles for i in t],[c[i] for t in triangles for i in t],method)
def box(name,at,size,role):
 x0,y0,z0=[at[i]-size[i]/2 for i in range(3)];x1,y1,z1=[at[i]+size[i]/2 for i in range(3)]
 v=[(x0,y0,z0),(x1,y0,z0),(x1,y0,z1),(x0,y0,z1),(x0,y1,z0),(x1,y1,z0),(x1,y1,z1),(x0,y1,z1)]
 f=[(1,2,3,0),(7,6,5,4),(4,5,1,0),(5,6,2,1),(6,7,3,2),(7,4,0,3)]
 norms=[(0,-1,0),(0,1,0),(0,0,-1),(1,0,0),(0,0,1),(-1,0,0)]
 put(name,v,f,[n for n in norms for _ in range(4)],[linear(COLORS[role])]*24,'roof cuboid from near contract')
def plane(name,points,role,normal=(0,1,0)):
 # Deliberately flat geometry with the near pane normal retained for its lighting.
 put(name,points,[(0,1,2,3)],[normal]*4,[linear(COLORS[role])]*4,'flat roof colour patch')
def horizontal(name,x,z,w,d,y,role,normal=(0,1,0)):
 plane(name,[(x-w/2,y,z-d/2),(x-w/2,y,z+d/2),(x+w/2,y,z+d/2),(x+w/2,y,z-d/2)],role,normal)
def flattened(points,y):
 # Bake the approved default-camera pane projection onto a flat colour patch.
 # The unchanged3.8x2m cream base still fixes each skylight's exactX/Z centre.
 pitch=math.radians(43);yaw=math.radians(14.5)
 direction=(math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch))
 return [(x-direction[0]*(height-y)/direction[1],y,z-direction[2]*(height-y)/direction[1]) for x,height,z in points]

def main():
 global MAT
 OUT.mkdir(parents=True,exist_ok=True);fd,fv,fn,fc,fi=read_asset('alc_museum_far.glb');nd,nv,nn,nc,ni=read_asset('alc_museum.glb')
 assert hashlib.sha256((OUT/'baseline_alc_museum.glb').read_bytes()).hexdigest()==CONTRACT['stats']['sha256']
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.context.preferences.filepaths.save_version=0
 MAT=bpy.data.materials.new('Museum far matte vertex colour');MAT.use_nodes=True;MAT.use_backface_culling=False
 bs=MAT.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(1,1,1,1);bs.inputs['Roughness'].default_value=.94;bs.inputs['Specular IOR Level'].default_value=.15
 col=MAT.node_tree.nodes.new('ShaderNodeVertexColor');col.layer_name='Color';MAT.node_tree.links.new(col.outputs['Color'],bs.inputs['Base Color'])
 removed=0;retained=0
 for index,triangles in enumerate(old.components(fv,fi)):
  ids={i for t in triangles for i in t};low=min(fv[i][1] for i in ids)
  if low>=8.37:removed+=len(triangles);continue
  keep('Preserved_nonroof_%03d'%index,fv,fn,fc,triangles,'exact previous far non-roof triangles');retained+=len(triangles)
 # The roof slab is silhouette geometry: copy its exact108 near triangles.
 selected=[]
 for triangles in old.components(nv,ni):
  pts=[nv[i] for t in triangles for i in t];lo=[min(p[j] for p in pts) for j in range(3)];hi=[max(p[j] for p in pts) for j in range(3)]
  if abs(lo[1]-8.38)<.0001 and abs(hi[1]-8.58)<.0001:selected=triangles;break
 assert len(selected)==108
 keep('Roof_slab_exact_near',nv,nn,nc,selected,'exact near roof slab silhouette/colour')
 box('Roof_recessed_slate',(0,8.60,0),(39.1,.06,9.1),'museum_roof_slate')
 for z in [-4.84,4.84]:
  box('Cream_parapet_long_'+str(z),(0,8.77,z),(40,.26,.32),'museum_roof_cream')
  box('Cream_coping_long_'+str(z),(0,8.93,z),(40,.06,.32),'museum_roof_cream')
 for x in [-19.84,19.84]:
  box('Cream_parapet_end_'+str(x),(x,8.77,0),(.32,.26,9.4),'museum_roof_cream')
  box('Cream_coping_end_'+str(x),(x,8.93,0),(.32,.06,9.36),'museum_roof_cream')
 pane_normals={}
 for role in ['museum_skylight_blue','museum_skylight_shade','museum_skylight_glint']:
  wanted=linear(COLORS[role]);candidates=[nn[i] for i,c in enumerate(nc) if max(abs(c[j]-wanted[j]) for j in range(3))<.0001 and nn[i][1]>.5]
  assert candidates,role;pane_normals[role]=candidates[0]
 for i,skylight in enumerate(CONTRACT['skylights'],1):
  x,z=skylight['centre_xz'];w,d=skylight['curb_size_xz']
  horizontal('Skylight_%d_cream_base'%i,x,z,w,d,8.704,'museum_roof_cream')
  front=[(x-1.75,8.72,z+.87),(x+1.75,8.72,z+.87),(x+1.75,8.96,z),(x-1.75,8.96,z)]
  back=[(x-1.75,8.72,z-.87),(x-1.75,8.96,z),(x+1.75,8.96,z),(x+1.75,8.72,z-.87)]
  plane('Skylight_%d_front_blue'%i,flattened(front,8.708),'museum_skylight_blue',pane_normals['museum_skylight_blue'])
  plane('Skylight_%d_back_blue'%i,flattened(back,8.708),'museum_skylight_shade',pane_normals['museum_skylight_shade'])
  ridge=[(x-1.81,8.96,z-.0275),(x-1.81,8.96,z+.0275),(x+1.81,8.96,z+.0275),(x+1.81,8.96,z-.0275)]
  plane('Skylight_%d_cream_divider'%i,flattened(ridge,8.712),'museum_roof_cream')
  reflection=[(x-1.35,z+.15),(x-.65,z+.72),(x+.10,z+.72),(x-.75,z+.15)]
  plane('Skylight_%d_sky_glint'%i,flattened([(px,8.96-(pz-z)*(.24/.87)+.002,pz) for px,pz in reflection],8.714),'museum_skylight_glint',pane_normals['museum_skylight_glint'])
 for i,vent in enumerate(CONTRACT['vents'],1):
  x,z=vent['centre_xz']
  box('Vent_%d_body'%i,(x,vent['body_center_y'],z),vent['body_size_xyz'],'museum_vent_body')
  box('Vent_%d_cap'%i,(x,vent['cap_center_y'],z),vent['cap_size_xyz'],'museum_vent_body')
  w,h,depth=vent['inset_size_xyz'];y=vent['inset_center_y'];front=z+vent['inset_offset_z']+depth/2
  plane('Vent_%d_dark_slot'%i,[(x-w/2,y-h/2,front),(x+w/2,y-h/2,front),(x+w/2,y+h/2,front),(x-w/2,y+h/2,front)],'museum_vent_shadow',(0,0,1))
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'alc_museum_far.blend'))
 for ob in objects:ob.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();ob=bpy.context.object;ob.name='alc_museum_far';ob.data.name='alc_museum_far_mobile'
 path=KIT/'alc_museum_far.glb'
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_normals=True,export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False)
 raw=path.read_bytes();sz=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+sz]);binary=bytearray(raw[28+sz:]);prim=doc['meshes'][0]['primitives'][0]
 positions=accessor(doc,binary,prim['attributes']['POSITION']);normals=accessor(doc,binary,prim['attributes']['NORMAL']);a=doc['accessors'][prim['attributes']['NORMAL']];view=doc['bufferViews'][a['bufferView']];start=view.get('byteOffset',0)+a.get('byteOffset',0);stride=view.get('byteStride',12)
 # Float32 positions from authored boxes may have rounded once on Blender input.
 rounded={tuple(round(x,5) for x in pos):candidates for pos,candidates in normal_lookup.items()}
 for i,pos in enumerate(positions):
  candidates=rounded.get(tuple(round(x,5) for x in pos))
  if candidates:
   chosen=min(candidates,key=lambda n:sum((n[j]-normals[i][j])**2 for j in range(3)));struct.pack_into('<3f',binary,start+i*stride,*chosen)
 path.write_bytes(raw[:28+sz]+binary)
 manifest=json.loads((SRC/'reference/alc_museum_far_manifest.json').read_text())
 count=sum(x['far_triangles'] for x in parts);bounds=[[min(v[j] for v in positions) for j in range(3)],[max(v[j] for v in positions) for j in range(3)]]
 manifest.update({'revision':'roof_v1','near_source':{'git_ref':REF['parent_head'],'path':'assets/landmarks/alcatraz_island/alc_museum.glb','contract':'tools/art/source/museum_far_roof_424/contract.json'},'near_sha256':CONTRACT['stats']['sha256'],'near_triangles':len(ni),'triangles':count,'ratio':count/len(ni),'bounds':bounds,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'parts':parts,'colour_status':'Roof/vents match ebce1cec; skylights are flat patches with near pane lighting normals','roof_contract':CONTRACT,'preserved_nonroof_triangles':retained,'replaced_old_roof_triangles':removed,'source':'tools/art/source/museum_far_roof_424/alc_museum_far.blend'})
 (KIT/'alc_museum_far_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 global_manifest=json.loads((KIT/'manifest.json').read_text());global_manifest['assets']['alc_museum_far'].update({'triangles':count,'bytes':path.stat().st_size,'sha256':manifest['sha256'],'source':manifest['source']});(KIT/'manifest.json').write_text(json.dumps(global_manifest,indent=2)+'\n')
 print('FAR_ROOF',count,'previous',len(fi),'retained_nonroof',retained,'removed_old_roof',removed,'near',len(ni),'bounds',bounds,flush=True)

if __name__=='__main__':main()
