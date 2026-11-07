"""Join evaluated named source parts while preserving imported kit vertex paint."""
import hashlib,json
import bpy

def export_asset(name,collection,material,kit):
 bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
 deps=bpy.context.evaluated_depsgraph_get();copies=[];components={}
 for source in collection.objects:
  if source.type!='MESH':continue
  data=bpy.data.meshes.new_from_object(source.evaluated_get(deps),depsgraph=deps)
  group=components.setdefault(source.get('component','main'),{'triangles':0,'vertices':[],'source_parts':0})
  group['triangles']+=sum(len(p.vertices)-2 for p in data.polygons);group['source_parts']+=1
  group['vertices'].extend(tuple(source.matrix_world@v.co) for v in data.vertices)
  attr=data.color_attributes.get('Color')
  if attr is None:
   original=data.color_attributes.active_color
   attr=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
   for face in data.polygons:
    for idx in face.loop_indices:
     if original:
      ci=data.loops[idx].vertex_index if original.domain=='POINT' else idx
      attr.data[idx].color=original.data[ci].color
     else:attr.data[idx].color=data.materials[face.material_index].diffuse_color
  data.color_attributes.active_color=attr;data.color_attributes.render_color_index=list(data.color_attributes).index(attr)
  for other in list(data.color_attributes):
   if other!=attr:data.color_attributes.remove(other)
  data.materials.clear();data.materials.append(material)
  for f in data.polygons:f.material_index=0
  for uv in list(data.uv_layers):data.uv_layers.remove(uv)
  obj=bpy.data.objects.new(source.name+' export',data);bpy.context.scene.collection.objects.link(obj);obj.matrix_world=source.matrix_world.copy();obj.select_set(True);copies.append(obj)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();obj=bpy.context.object;obj.name=name
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
 triangulate=obj.modifiers.new('Fixed diagonals','TRIANGULATE');triangulate.quad_method='FIXED';triangulate.ngon_method='CLIP';bpy.ops.object.modifier_apply(modifier=triangulate.name)
 data=obj.data;data.calc_loop_triangles();triangles=len(data.loop_triangles)
 assert triangles<=9000,(name,triangles)
 lo=[min(v.co[i] for v in data.vertices) for i in range(3)];hi=[max(v.co[i] for v in data.vertices) for i in range(3)]
 bounds=[[round(lo[0],6),round(lo[2],6),round(-hi[1],6)],[round(hi[0],6),round(hi[2],6),round(-lo[1],6)]]
 path=kit.OUT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_attributes=False,export_cameras=False,export_lights=False,export_animations=False,export_extras=False,export_texcoords=False,export_tangents=False)
 kit.canonical_triangle_order(path)
 entry={'triangles':triangles,'surfaces':1,'bytes':path.stat().st_size,'bounds':bounds,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),**kit.META[name]}
 for group in components.values():
  vertices=group.pop('vertices');a=[min(v[i] for v in vertices) for i in range(3)];b=[max(v[i] for v in vertices) for i in range(3)]
  group['bounds']=[[round(a[0],6),round(a[2],6),round(-b[1],6)],[round(b[0],6),round(b[2],6),round(-a[1],6)]]
 entry['components']=components
 bpy.data.objects.remove(obj,do_unlink=True);bpy.data.meshes.remove(data)
 return entry
