"""Measured near->far reduction. Run Blender through flock ~/gs66-render.lock.
Retain formal arched windows and silhouette; simplify small box bevels and hidden glyph faces.
All vertex colours come from the selected near GLB, never a guessed palette.
"""
from pathlib import Path
import sys,json,math,hashlib,collections,struct
import bpy,bmesh
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/landmarks/alcatraz_island'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
REF=json.loads((SRC/'reference/source.json').read_text());NEAR=SRC/REF['near_file']
def vec(p):return Vector((p[0],-p[2],p[1]))
def components(vs,idx):
 keys={};parent=[];ids=[]
 for p in vs:
  k=tuple(round(x,5) for x in p)
  if k not in keys:keys[k]=len(keys);parent.append(len(parent))
  ids.append(keys[k])
 def root(a):
  while a!=parent[a]:parent[a]=parent[parent[a]];a=parent[a]
  return a
 for a,b,c in idx:
  ra=root(ids[a]);parent[root(ids[b])]=ra;parent[root(ids[c])]=ra
 groups=collections.defaultdict(list)
 for t in idx:groups[root(ids[t[0]])].append(t)
 return list(groups.values())
def main():
 d,b=load_glb(NEAR);prim=d['meshes'][0]['primitives'][0]
 vs=accessor(d,b,prim['attributes']['POSITION']);ns=accessor(d,b,prim['attributes']['NORMAL']);cs=accessor(d,b,prim['attributes']['COLOR_0']);ix=[x[0] for x in accessor(d,b,prim['indices'])];ix=[ix[i:i+3] for i in range(0,len(ix),3)]
 assert len(d['meshes'])==1 and len(d['meshes'][0]['primitives'])==1
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.context.preferences.filepaths.save_version=0
 mat=bpy.data.materials.new('Museum far matte vertex colour');mat.use_nodes=True;mat.use_backface_culling=False
 bs=mat.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(1,1,1,1);bs.inputs['Roughness'].default_value=.94;bs.inputs['Specular IOR Level'].default_value=.15
 col=mat.node_tree.nodes.new('ShaderNodeVertexColor');col.layer_name='Color';mat.node_tree.links.new(col.outputs['Color'],bs.inputs['Base Color'])
 objects=[];parts=[];windows=[];count=0;retained_normals=collections.defaultdict(list)
 for triangles in components(vs,ix):
  ids=sorted({i for t in triangles for i in t});pts=[vs[i] for i in ids]
  lo=[min(p[j] for p in pts) for j in range(3)];hi=[max(p[j] for p in pts) for j in range(3)];dims=[hi[j]-lo[j] for j in range(3)];at=[(hi[j]+lo[j])/2 for j in range(3)]
  pane=abs(dims[0]-1.25)<1e-4 and abs(dims[1]-2.10)<1e-4 and dims[2]<1e-5
  is_box=len(triangles)==108 and min(dims)>1e-5
  major=bool(dims[0]>39 and dims[2]>9.5)
  glyph=dims[1]<.30 and dims[2]<.003 and lo[2]>5.18 and hi[2]<5.20
  method='retain exact source vertices/normals/colours'
  name='Part_%03d'%len(parts)
  selected=triangles
  if glyph:
   selected=[t for t in triangles if all(abs(vs[i][2]-hi[2])<1e-6 for i in t) and sum(ns[i][2] for i in t)>2.9]
   assert selected,('Missing front glyph',lo,hi)
   name='Sign_glyph_%03d'%len(parts);method='retain original front glyph, remove hidden 2mm extrusion/back'
  if is_box and not major:
   name='Simplified_bevel_part_%03d'%len(parts);method='replace subpixel small-box bevels with same-envelope closed cuboid'
   x0,y0,z0=lo;x1,y1,z1=hi
   vertices=[(x0,y0,z0),(x1,y0,z0),(x1,y0,z1),(x0,y0,z1),(x0,y1,z0),(x1,y1,z0),(x1,y1,z1),(x0,y1,z1)]
   faces=[(1,2,3,0),(7,6,5,4),(4,5,1,0),(5,6,2,1),(6,7,3,2),(7,4,0,3)]
   axes=[(0,-1,0),(0,1,0),(0,0,-1),(1,0,0),(0,0,1),(-1,0,0)]
   normals=[n for n in axes for _ in range(4)]
   colors=[tuple(cs[ids[0]])]*24
  else:
   ids=sorted({i for t in selected for i in t});mapping={old:i for i,old in enumerate(ids)}
   vertices=[vs[i] for i in ids];faces=[tuple(mapping[i] for i in t) for t in selected];normals=[ns[i] for t in selected for i in t];colors=[cs[i] for t in selected for i in t]
   for i in ids:retained_normals[tuple(vs[i])].append(ns[i])
   if major:name='Silhouette_exact_%03d'%len(parts)
   if pane:
    count+=1;name='Arch_glazing_%02d_x%g_y%g'%(count,at[0],at[1]);windows.append({'name':name,'near_bounds':[lo,hi],'center':at,'front_z':hi[2],'colour_linear':list(cs[ids[0]])})
  mesh=bpy.data.meshes.new(name);mesh.from_pydata([vec(v) for v in vertices],[],faces);mesh.update();mesh.materials.append(mat)
  attr=mesh.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
  for i,c in enumerate(colors):attr.data[i].color=c
  mesh.color_attributes.active_color=attr;mesh.color_attributes.render_color_index=0
  for face in mesh.polygons:face.use_smooth=True
  mesh.normals_split_custom_set([vec(n) for n in normals])
  obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj);objects.append(obj)
  mesh.calc_loop_triangles();parts.append({'name':name,'source_triangles':len(triangles),'far_triangles':len(mesh.loop_triangles),'method':method,'source_bounds':[lo,hi]})
 assert count==25,('Near layout changed; review before export',count)
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'alc_museum_far.blend'))
 for o in objects:o.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();body=bpy.context.object;body.name='alc_museum_far';body.data.name='alc_museum_far_mobile'
 # Exporter triangulates simplified cuboids while retaining all original planar arches.
 path=KIT/'alc_museum_far.glb'
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_normals=True,export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False)
 # Blender's custom-normal encoding can quantize by ~1.7e-4. Restore the
 # original packed normals for untouched structural vertices after export.
 raw=path.read_bytes();sz=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+sz]);binary=bytearray(raw[28+sz:]);primitive=doc['meshes'][0]['primitives'][0]
 positions=accessor(doc,binary,primitive['attributes']['POSITION']);normals=accessor(doc,binary,primitive['attributes']['NORMAL']);a=doc['accessors'][primitive['attributes']['NORMAL']];view=doc['bufferViews'][a['bufferView']];start=view.get('byteOffset',0)+a.get('byteOffset',0);stride=view.get('byteStride',12)
 for i,point in enumerate(positions):
  candidates=retained_normals.get(tuple(point))
  if candidates:
   chosen=min(candidates,key=lambda n:sum((n[j]-normals[i][j])**2 for j in range(3)))
   struct.pack_into('<3f',binary,start+i*stride,*chosen)
 path.write_bytes(raw[:28+sz]+binary)
 tri=sum(p['far_triangles'] for p in parts)
 report={'task':'SGODOT-424','revision':REF['revision'],'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','near_source':REF,'near_sha256':hashlib.sha256(NEAR.read_bytes()).hexdigest(),'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'near_triangles':len(ix),'triangles':tri,'ratio':tri/len(ix),'surfaces':1,'bounds':[[min(v[j] for v in vs) for j in range(3)],[max(v[j] for v in vs) for j in range(3)]],'windows':windows,'parts':parts,'placement':{'position':[0,10,-13],'yaw_degrees':0,'scale':[1,1,1]},'lod':{'near':'alc_museum','far':'alc_museum_far','switch_distance_m':55,'margin_m':0},'colour_status':REF['colour_status']}
 (KIT/'alc_museum_far_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('MUSEUM_FAR',tri,'NEAR',len(ix),'RATIO',tri/len(ix))
if __name__=='__main__':main()
