"""Small vertex-colour pennant, one surface and one gentle flutter shape."""
from pathlib import Path
import json,math,sys,importlib.util,hashlib
import bpy,bmesh
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/landmarks/alcatraz_island'
spec=importlib.util.spec_from_file_location('ferry_builder',SRC.parent/'alcatraz_ferry_424/build.py');f=importlib.util.module_from_spec(spec);spec.loader.exec_module(f)
p=f.p
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.context.preferences.filepaths.save_version=0
p.PARTS=[];p.MATS={};p.PIVOT=bpy.data.objects.new('Stern pennant / pole base',None);bpy.context.scene.collection.objects.link(p.PIVOT)
f.rod('Short cream stern flagpole',(0,0,0),(0,1.65,0),.025,'ivory',8)
# Six broad cloth segments; flag remains within original ferry footprint when mounted.
pts=[]
for i in range(7):
 x=.02+.80*i/6
 for j in range(3):
  y=1.10+.45*j/2
  if i==6 and j==1:xcut=.10
  else:xcut=0
  pts.append((x-xcut,y,.035*(i/6)*math.sin(i*1.05)))
faces=[];roles=[]
for i in range(6):
 for j in range(2):faces.append((i*3+j,(i+1)*3+j,(i+1)*3+j+1,i*3+j+1));roles.append('ring' if i<2 else 'ivory')
f.mesh('Muted coral and cream pennant',pts,faces,roles,True)
source=bpy.context.scene;bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();copies=[]
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'ferry_flag_parts.blend'))
flat=bpy.data.materials.new('Ferry flag matte vertex colour');flat.use_nodes=True;flat.use_backface_culling=False
bs=flat.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(1,1,1,1);bs.inputs['Roughness'].default_value=.94;bs.inputs['Specular IOR Level'].default_value=.15
vc=flat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';flat.node_tree.links.new(vc.outputs['Color'],bs.inputs['Base Color'])
export=bpy.data.scenes.new('Flag export')
for obj in p.PARTS:
 d=bpy.data.meshes.new_from_object(obj.evaluated_get(deps));d.transform(obj.matrix_world);col=d.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
 for face in d.polygons:
  color=d.materials[face.material_index].diffuse_color
  for i in face.loop_indices:col.data[i].color=color
 d.materials.clear();d.materials.append(flat)
 for face in d.polygons:face.material_index=0
 d.color_attributes.active_color=col;d.color_attributes.render_color_index=0
 o=bpy.data.objects.new(obj.name,d);export.collection.objects.link(o);copies.append(o)
bpy.context.window.scene=export
for o in copies:o.select_set(True)
bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();o=bpy.context.object;o.name='ferry_flag';o.data.name='ferry_flag_mobile'
o.shape_key_add(name='rest');flutter=o.shape_key_add(name='flutter')
for i,v in enumerate(o.data.vertices):
 if v.co.x>.03:
  # Offset only the cloth's horizontal depth; root/pole never move.
  flutter.data[i].co.y=-.035*(v.co.x/.82)*math.sin(v.co.x/.82*math.tau+1.2)
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'ferry_flag.blend'))
path=KIT/'ferry_flag.glb';bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_normals=True,export_texcoords=False,export_animations=False,export_morph=True,export_morph_normal=True,export_cameras=False,export_lights=False)
o.data.calc_loop_triangles();entry={'file':path.name,'triangles':len(o.data.loop_triangles),'surfaces':1,'mount_position':[11.2,1.48,2.5],'pole_height_m':1.65,'cloth_size_m':[.80,.45],'flutter_depth_m':.035,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
(SRC/'flag_measurement.json').write_text(json.dumps(entry,indent=2)+'\n');print('FLAG',entry)
