"""Derive two <=120-triangle tree LODs from the accepted near GLBs.
Keep the original crown lobes and colour boundaries, transfer the source normals.
Run Blender under flock ~/gs66-render.lock; never rewrite a near asset.
"""
from pathlib import Path
import hashlib,json,math,sys
import bpy,bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
import build_decor_assets as K
SRC=ROOT/'tools/art/source/alcatraz_tree_lod_424';OUT=ROOT/'assets/landmarks/alcatraz_island'

def make_mesh(name,vertices,faces,collection):
 data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
 obj=bpy.data.objects.new(name,data);collection.objects.link(obj)
 return obj
def activate(obj):
 bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
def weld(obj):
 bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free();obj.data.update()
def components(obj,collection):
 data=obj.data;adj=[set() for _ in data.vertices]
 for e in data.edges:adj[e.vertices[0]].add(e.vertices[1]);adj[e.vertices[1]].add(e.vertices[0])
 groups=[];unseen=set(range(len(adj)))
 while unseen:
  stack=[unseen.pop()];group=set(stack)
  while stack:
   for j in adj[stack.pop()]:
    if j in unseen:unseen.remove(j);group.add(j);stack.append(j)
  groups.append(group)
 objects=[]
 for i,ids in enumerate(groups):
  ids=sorted(ids);mapping={j:k for k,j in enumerate(ids)};faces=[tuple(mapping[j] for j in p.vertices) for p in data.polygons if p.vertices[0] in mapping]
  objects.append(make_mesh(obj.name+f' / connected part {i+1}',[data.vertices[j].co.copy() for j in ids],faces,collection))
 bpy.data.objects.remove(obj,do_unlink=True)
 return objects
def triangles(obj):obj.data.calc_loop_triangles();return len(obj.data.loop_triangles)
def transfer(obj,points,faces,normal_values,color_values,material):
 bvh=BVHTree.FromPolygons(points,faces,all_triangles=True);data=obj.data
 normals=[];colors=[]
 for vertex in data.vertices:
  hit,normal,index,distance=bvh.find_nearest(vertex.co)
  ids=faces[index];a,b,c=[points[j] for j in ids];v0=b-a;v1=c-a;v2=hit-a
  d00=v0.dot(v0);d01=v0.dot(v1);d11=v1.dot(v1);den=d00*d11-d01*d01
  v=(d11*v2.dot(v0)-d01*v2.dot(v1))/den if abs(den)>1e-12 else 0;w=(d00*v2.dot(v1)-d01*v2.dot(v0))/den if abs(den)>1e-12 else 0;weights=[1-v-w,v,w]
  n=sum((normal_values[j]*t for j,t in zip(ids,weights)),Vector()).normalized()
  rgba=[sum(color_values[j][k]*t for j,t in zip(ids,weights)) for k in range(3)]+[1.0]
  normals.append(n);colors.append(rgba)
 for p in data.polygons:p.use_smooth=True
 data.materials.clear();data.materials.append(material)
 attribute=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER');data.color_attributes.active_color=attribute;data.color_attributes.render_color_index=0
 loop_normals=[]
 for loop in data.loops:attribute.data[loop.index].color=colors[loop.vertex_index];loop_normals.append(normals[loop.vertex_index])
 data.normals_split_custom_set(loop_normals)
def far_components(near_name,collection,source_components,ground_offset):
 K.CURRENT=collection
 palette=json.loads((OUT/'props_manifest.json').read_text())['palette_srgb']
 for key,value in palette.items():
  m=bpy.data.materials.new(key);m.diffuse_color=(*K.rgb(value),1);K.MATS[key]=m
 def shifted(p):return (p[0],p[1]+ground_offset,p[2])
 specs_a=[((.65,4.68,0),(3.8,1.12,2.75),'leaf_dark','ico'),((1.55,5.38,-.12),(3.6,1.25,2.65),'leaf','ico'),((2.0,5.92,-.08),(2.65,.96,2.12),'leaf_light','ico'),((-.65,4.60,.24),(1.50,.90,1.48),'leaf','octa'),((2.62,5.27,.40),(1.70,.94,1.65),'leaf_light','octa')]
 specs_b=[((-.75,4.50,0),(2.70,2.0,2.60),'leaf_dark','uv'),((.70,4.75,.20),(2.80,2.10,2.65),'leaf','uv'),((0,5.35,-.18),(2.65,1.85,2.55),'leaf_light','uv')]
 parts=[]
 for i,(center,size,color,shape) in enumerate(specs_a if near_name=='alc_tree_a' else specs_b):
  center=K.v(shifted(center))
  source=min(source_components,key=lambda o:(((Vector([min(v.co[k] for v in o.data.vertices) for k in range(3)])+Vector([max(v.co[k] for v in o.data.vertices) for k in range(3)]))*.5)-center).length)
  sectors=([7,7,8,6,6] if near_name=='alc_tree_a' else [10,10,10])[i]
  bpy.ops.mesh.primitive_uv_sphere_add(segments=sectors,ring_count=3,radius=1)
  obj=bpy.context.object;K.finish(obj,f'{near_name}_far / original crown lobe {i+1}',color,True)
  for axis in range(3):
   low=min(v.co[axis] for v in obj.data.vertices);high=max(v.co[axis] for v in obj.data.vertices)
   a=min(v.co[axis] for v in source.data.vertices);b=max(v.co[axis] for v in source.data.vertices)
   for vertex in obj.data.vertices:vertex.co[axis]=a+(vertex.co[axis]-low)*(b-a)/(high-low)
  low=min(v.co.z for v in obj.data.vertices);high=max(v.co.z for v in obj.data.vertices);mid=(low+high)/2
  for vertex in obj.data.vertices:
   if low+1e-5<vertex.co.z<high-1e-5:vertex.co.z=mid+(vertex.co.z-mid)*.618033989
  bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free();obj.data.update()
  parts.append((obj,source,color))
 # Remove complete faces covered by another lobe, and undersides that face
 # away at every yaw for a camera pitched >=40 degrees. The game uses 43.
 # This camera contract is explicit in the manifest; these are not underside LODs.
 hulls=[]
 for obj,source,color in parts:
  obj.data.calc_loop_triangles()
  hulls.append([((obj.data.vertices[p.vertices[1]].co-obj.data.vertices[p.vertices[0]].co).cross(obj.data.vertices[p.vertices[2]].co-obj.data.vertices[p.vertices[0]].co).normalized(), obj.data.vertices[p.vertices[0]].co.copy()) for p in obj.data.polygons])
 for i,(obj,source,color) in enumerate(parts):
  doomed=[]
  for p in obj.data.polygons:
   points=[obj.data.vertices[j].co for j in p.vertices]
   normal=(points[1]-points[0]).cross(points[2]-points[0]).normalized()
   if (normal.z*math.sin(math.radians(40))+math.hypot(normal.x,normal.y)*math.cos(math.radians(40)) < -1e-5) or any(all(all(n.dot(v-a)<-1e-5 for n,a in planes) for v in points) for k,planes in enumerate(hulls) if k!=i):doomed.append(p.index)
  bm=bmesh.new();bm.from_mesh(obj.data);bm.faces.ensure_lookup_table()
  bmesh.ops.delete(bm,geom=[bm.faces[j] for j in doomed],context='FACES');bm.to_mesh(obj.data);bm.free();obj.data.update()
 wood=[]
 if near_name=='alc_tree_a':
  centers=[(0,0,0),(.18,1.6,.02),(.60,3.15,0),(1.10,4.35,0)];radii=[.24,.18,.12,.065]
  pts=[(c[0]+r*math.cos(j*math.tau/(4 if i==0 else 3)),c[1]+(0 if i==0 else ground_offset),c[2]+r*math.sin(j*math.tau/(4 if i==0 else 3))) for i,(c,r) in enumerate(zip(centers,radii)) for j in range(4 if i==0 else 3)]
  # Four vertices retain the broad root; the upward sections use three.
  # The end caps are hidden by terrain and the lowest crown.
  faces=[(0,1,4),(1,5,4),(1,2,5),(2,6,5),(2,3,6),(3,4,6),(3,0,4)]
  faces += [(base+j,base+(j+1)%3,base+3+(j+1)%3,base+3+j) for base in [4,7] for j in range(3)]
  # Determine outward winding on a closed volume, then discard the two
  # fully occluded end caps without recalculating the open strip orientation.
  faces += [(3,2,1,0),(10,11,12)]
  trunk=K.mesh('Cypress / continuous bent trunk',pts,faces,'bark',True)
  bm=bmesh.new();bm.from_mesh(trunk.data);bm.faces.ensure_lookup_table()
  bmesh.ops.delete(bm,geom=list(bm.faces)[-2:],context='FACES');bm.to_mesh(trunk.data);bm.free();trunk.data.update();wood.append(trunk)
  branches=[((.3,2.1,0),(-.35,4.1,.55))]
 else:
  wood.append(K.rod('Round tree / preserved single trunk',shifted((0,0,0)),shifted((0,3.7,0)),.22,'bark',segments=8,top=.10))
  branches=[((0,2.7,0),v) for v in [(-1.0,4.3,0),(.95,4.5,.45)]]
 for i,(a,b) in enumerate(branches):
  a,b=Vector(shifted(a)),Vector(shifted(b));axis=(b-a).normalized();u=axis.cross(Vector((0,0,1))).normalized();v=axis.cross(u).normalized()
  vertices=[a+u*.09,a-u*.09,b+v*.035,b-v*.035]
  wood.append(K.mesh(f'{near_name} / main branch {i+1}',vertices,[(0,1,2),(1,0,3),(1,3,2),(0,2,3)],'bark_light',True))
 for obj in wood:
  activate(obj);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
  parts.append((obj,None,'bark_light' if 'branch' in obj.name else 'bark'))
 return parts

def main():
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 mat=bpy.data.materials.new('Matched near-tree matte vertex paint');mat.use_nodes=True;p=mat.node_tree.nodes['Principled BSDF'];p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18;vc=mat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';mat.node_tree.links.new(vc.outputs['Color'],p.inputs['Base Color'])
 entries={}
 for near_name in ['alc_tree_a','alc_tree_b']:
  path=OUT/(near_name+'.glb');original=path.read_bytes();digest=hashlib.sha256(original).hexdigest();doc,binary=load_glb(path);primitive=doc['meshes'][0]['primitives'][0]
  points=[K.v(p) for p in accessor(doc,binary,primitive['attributes']['POSITION'])];normals=[K.v(p) for p in accessor(doc,binary,primitive['attributes']['NORMAL'])];colors=accessor(doc,binary,primitive['attributes']['COLOR_0']);indices=[x[0] for x in accessor(doc,binary,primitive['indices'])];faces=[tuple(indices[i:i+3]) for i in range(0,len(indices),3)]
  name=near_name+'_far';collection=bpy.data.collections.new(name+' editable exposed shells');bpy.context.scene.collection.children.link(collection)
  crown_faces=[f for f in faces if colors[f[0]][1]>colors[f[0]][0]];ids=sorted({j for f in crown_faces for j in f});mapping={j:k for k,j in enumerate(ids)}
  source=make_mesh('Source crown components',[points[j] for j in ids],[tuple(mapping[j] for j in f) for f in crown_faces],collection);weld(source);sources=components(source,collection)
  authored=far_components(near_name,collection,sources,max(p.z for p in points)-(6.4 if near_name=='alc_tree_a' else 6.275));parts=[];cost={}
  for obj,source,color in authored:
   if source:
    coords={tuple(round(x,6) for x in v.co) for v in source.data.vertices};original_faces=[f for f in crown_faces if tuple(round(x,6) for x in points[f[0]]) in coords]
    transfer(obj,points,original_faces,normals,colors,mat)
   else:
    data=obj.data;attribute=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER');data.color_attributes.active_color=attribute;data.color_attributes.render_color_index=0
    rgba=(*K.rgb(json.loads((OUT/'props_manifest.json').read_text())['palette_srgb'][color]),1)
    for loop in data.loops:attribute.data[loop.index].color=rgba
    data.materials.clear();data.materials.append(mat)
   parts.append(obj);cost[obj.name]=triangles(obj)
  for source in sources:bpy.data.objects.remove(source,do_unlink=True)
  bpy.context.view_layer.update();copies=[];bpy.ops.object.select_all(action='DESELECT')
  for source in parts:
   o=source.copy();o.data=source.data.copy();bpy.context.scene.collection.objects.link(o);o.select_set(True);copies.append(o)
  bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();obj=bpy.context.object;obj.name=name;obj.data.name=name+'_mobile';tris=triangles(obj);assert tris<=120,(name,tris,cost)
  near_lo=[min(p[k] for p in points) for k in range(3)];near_hi=[max(p[k] for p in points) for k in range(3)]
  out=OUT/(name+'.glb');bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_texcoords=False,export_tangents=False,export_animations=False,export_extras=False)
  verts=[v.co.copy() for v in obj.data.vertices];lo=[min(v[k] for v in verts) for k in range(3)];hi=[max(v[k] for v in verts) for k in range(3)]
  bounds=[[lo[0],lo[2],-hi[1]],[hi[0],hi[2],-lo[1]]];near_bounds=[[near_lo[0],near_lo[2],-near_hi[1]],[near_hi[0],near_hi[2],-near_lo[1]]]
  entry={'triangles':tris,'surfaces':1,'bounds':bounds,'near_bounds':near_bounds,'near_triangles':len(faces),'near_sha256':digest,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'bytes':out.stat().st_size,'parts':cost,'near':near_name,'far':name,'switch_distance_m':40,'margin_m':0,'minimum_camera_pitch_degrees':40,'placement_rotation':'yaw only; upright Y','material_contract':{'vertex_color_is_srgb':False,'roughness':.9,'metallic':0,'specular':.18},'source':'tools/art/source/alcatraz_tree_lod_424/tree_lod.blend','generator':'tools/art/build_alcatraz_tree_lod_424.py'}
  entries[name]=entry;bpy.data.objects.remove(obj,do_unlink=True)
  assert path.read_bytes()==original
  print('TREE_LOD',name,tris,cost,bounds,flush=True)
 manifest={'author':'赵云','virtual_user_id':'8ea32e40-c0ba-4a31-864f-374a6bcbc554','assets':entries,'lod_groups':[{'name':e['near'],'near':e['near'],'far':e['far'],'switch_distance_m':40,'margin_m':0,'far_placeholder':False,'minimum_camera_pitch_degrees':40,'common_aabb':e['near_bounds']} for e in entries.values()]}
 (SRC/'asset_stats.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');(OUT/'tree_lod_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'tree_lod.blend'),compress=True)
if __name__=='__main__':main()
