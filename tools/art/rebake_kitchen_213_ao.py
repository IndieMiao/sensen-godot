#!/usr/bin/env python3
"""Rebake only contact-AO delta caused by 213 placement changes, fixed original UVs.
Blender: bake old/new AO in actual GLB geometry; Pillow script applies ratio.
No wall/floor meshes, positions, base colours, UVs or original detail are edited.
"""
import json,sys,subprocess,math
from pathlib import Path
import bpy
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/kitchen-213';KIT=ROOT/'assets/rooms/basic_room';BASE='154ce6421448e26e42ee225ba7018638ae756394'
TARGETS=['room_shell','window_wall','back_wall','sink_cabinet','utensil_crock','wall_shelf','shelf_plant']

def load(path,at,yaw):
 before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(path));objs=list(set(bpy.data.objects)-before)
 transform=Matrix.Translation(Vector((at[0],-at[2],at[1])))@Matrix.Rotation(math.radians(yaw),4,'Z')
 for o in objs:
  if o.parent not in objs:o.matrix_world=transform@o.matrix_world
 return [o for o in objs if o.type=='MESH']

def bake(version):
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 old=json.loads(subprocess.check_output(['git','show',BASE+':assets/rooms/basic_room/layout.json'],cwd=ROOT));new=json.loads((KIT/'layout.json').read_text());layout=old if version=='old' else new;by={r['name']:r for r in layout['assets']};target=[]
 for row in layout['assets']+layout.get('instances',[]):
  src=by[row.get('asset',row['name'])];objs=load(KIT/src['file'],row['position'],row.get('yaw_degrees',0))
  if row['name'] in TARGETS:target+=objs
  # Fire is in both variants, matching the original bake's occluder set.
 if version=='new':load(ROOT/'assets/props/warming_cabinet/warming_cabinet_b.glb',[-2.85,.082,-1.69],90)
 bpy.ops.object.select_all(action='DESELECT')
 for o in target:o.select_set(True)
 bpy.context.view_layer.objects.active=target[0];bpy.ops.object.join();obj=bpy.context.object;obj.name='Fixed original UV targets'
 image=bpy.data.images.new('AO_'+version,width=2048,height=2048,alpha=False);image.colorspace_settings.name='sRGB'
 mat=bpy.data.materials.new('Contact AO ratio');mat.use_nodes=True;nt=mat.node_tree;nt.nodes.clear()
 ao=nt.nodes.new('ShaderNodeAmbientOcclusion');ao.samples=64;ao.inputs['Distance'].default_value=.68
 mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MIX';mix.inputs[0].default_value=.58;mix.inputs[1].default_value=(1,1,1,1);nt.links.new(ao.outputs['Color'],mix.inputs[2])
 emit=nt.nodes.new('ShaderNodeEmission');nt.links.new(mix.outputs[0],emit.inputs[0]);out=nt.nodes.new('ShaderNodeOutputMaterial');nt.links.new(emit.outputs[0],out.inputs['Surface']);tex=nt.nodes.new('ShaderNodeTexImage');tex.image=image;nt.nodes.active=tex
 obj.data.materials.clear();obj.data.materials.append(mat)
 for f in obj.data.polygons:f.material_index=0
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=False;scene.cycles.seed=213;scene.render.threads_mode='FIXED';scene.render.threads=6
 scene.render.bake.margin=8;scene.render.bake.use_clear=True
 print('BAKING_213_AO',version,flush=True);bpy.ops.object.bake(type='EMIT');image.filepath_raw=str(OUT/('ao-'+version+'.png'));image.file_format='PNG';image.save()
for version in (['new'] if '--new-only' in sys.argv else ['old','new']):bake(version)
