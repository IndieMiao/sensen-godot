"""Export full-size neutral geometry before detailed modeling."""
from pathlib import Path
import json
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent
OUT=ROOT/'output/tea-216/blockout_assets'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0
plan=json.loads((SRC/'blockout_plan.json').read_text())
material=bpy.data.materials.new('Neutral blockout');material.diffuse_color=(.55,.60,.57,1)
sources={}
for item in plan['items']:
    kind=item['kind'];name=kind if kind in ['table','stool','plant'] else item['name']
    if name in sources:continue
    if item['radius']:
        height={'table':1.,'stool':.715,'plant':1.6}[kind]
        bpy.ops.mesh.primitive_cylinder_add(vertices=64,radius=item['radius'],depth=height,location=(0,0,height/2))
    else:
        size=item['size'];bpy.ops.mesh.primitive_cube_add(size=1,location=(0,0,size[1]/2))
        bpy.context.object.scale=(size[0],size[2],size[1])
    obj=bpy.context.object;obj.name=name;obj.data.name=name+'_blockout'
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);obj.data.materials.append(material)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,
        export_materials='EXPORT',export_animations=False,export_cameras=False,export_lights=False)
    sources[name]=obj
    bpy.ops.object.select_all(action='DESELECT')
for item in plan['items']:
    name=item['kind'] if item['kind'] in ['table','stool','plant'] else item['name']
    obj=bpy.data.objects.new(item['name']+'_placed',sources[name].data)
    bpy.context.scene.collection.objects.link(obj);x,y,z=item['position'];obj.location=(x,-z,y)
for obj in sources.values():obj.hide_set(True);obj.hide_render=True
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'tea_house_blockout.blend'))
print('TEA_BLOCKOUT_READY',len(plan['items']),len(sources))
