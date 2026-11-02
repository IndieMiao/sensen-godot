"""Editable neutral blockouts, one Blender scene per candidate; no detailed art."""
from pathlib import Path
import json
import math
import sys
import bpy
from mathutils import Vector,Matrix

SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[3]
DEPS=ROOT/'output/poi-service-hall-321/dependencies'
HALL=DEPS/'assets/rooms/_shared/shell_hall'
DATA=json.loads((SRC/'blockout_layouts.json').read_text())
SHELL=json.loads((HALL/'layout.json').read_text())


def vec(p):return Vector((p[0],-p[2],p[1]))


def mat(name,color):
    existing=bpy.data.materials.get(name)
    if existing:return existing
    material=bpy.data.materials.new(name);material.diffuse_color=(*color,1);material.use_nodes=True
    shader=material.node_tree.nodes['Principled BSDF'];shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Roughness'].default_value=.9
    return material


def load_model(scene,path,name,position,yaw,scale=(1,1,1),material=None):
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported=list(set(bpy.data.objects)-before)
    transforms={obj:obj.matrix_world.copy() for obj in imported if obj.type=='MESH'}
    root=bpy.data.objects.new(name,None);scene.collection.objects.link(root)
    root.location=vec(position);root.rotation_euler.z=math.radians(yaw)
    root['blockout_only']=True;root['source_asset']=str(path.relative_to(ROOT))
    scale_matrix=Matrix.Diagonal((scale[0],scale[2],scale[1],1))
    for obj,transform in transforms.items():
        obj.parent=root;obj.matrix_parent_inverse=Matrix.Identity(4);obj.matrix_basis=scale_matrix@transform
        obj.name=name+'__'+obj.name
        if material:
            obj.data.materials.clear();obj.data.materials.append(material)
            for face in obj.data.polygons:face.material_index=0
    for obj in imported:
        if obj.type!='MESH':bpy.data.objects.remove(obj,do_unlink=True)
    return root


def primitive(name,position,size,material,kind='box',yaw=0):
    if kind=='cylinder':
        bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=size[0]/2,depth=size[1],location=vec(position))
    else:
        bpy.ops.mesh.primitive_cube_add(size=1,location=vec(position));bpy.context.object.scale=(size[0],size[2],size[1])
    obj=bpy.context.object;obj.name=name;obj.rotation_euler.z=math.radians(yaw);obj.data.materials.append(material)
    obj['blockout_only']=True
    return obj


def main():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version=0
    white=mat('Blockout shell',(.70,.72,.70));seating=mat('Blockout seats',(.30,.39,.44));prop=mat('Blockout props',(.51,.57,.59))
    foliage=mat('Blockout foliage',(.40,.49,.34));first=None
    for plan in DATA['layouts']:
        scene=bpy.data.scenes.new('N2_'+plan['id']);bpy.context.window.scene=scene
        if first is None:first=scene
        assets={a['name']:a for a in SHELL['assets']}
        for spec in SHELL['assets']+SHELL['instances']:
            asset=assets[spec.get('asset',spec['name'])]
            load_model(scene,HALL/asset['file'],spec['name'],spec['position'],spec['yaw_degrees'],material=white)
        for item in plan['items']:
            if item['asset']=='small_round_table':
                x,y,z=item['position']
                for part,radius,height,center in [('top',.3,.05,.725),('stem',.055,.65,.375),('foot',.18,.05,.025)]:
                    primitive(item['name']+'_'+part,(x,y+center,z),(radius*2,height,radius*2),prop,'cylinder')
                continue
            path=ROOT/'assets/rooms/_shared/plants/peace_lily.glb' if item['asset']=='peace_lily' else HALL/(item['source_asset']+'.glb')
            load_model(scene,path,item['name'],item['position'],item['yaw_degrees'],item['scale'],foliage if item['asset']=='peace_lily' else seating)
        for item in plan['fixed']:primitive(item['name'],item['position'],item['size'],prop,item['kind'],item['yaw_degrees'])
        for anchor in plan['anchors']:
            obj=bpy.data.objects.new(anchor['name'],None);scene.collection.objects.link(obj)
            obj.location=vec(anchor['position']);obj.rotation_euler.z=math.radians(anchor['yaw_degrees'])
            obj.empty_display_type='ARROWS';obj.empty_display_size=.18;obj['module']=anchor['module']
        camera_data=bpy.data.cameras.new('43 degree overview');camera=bpy.data.objects.new('Review camera',camera_data)
        scene.collection.objects.link(camera);camera_data.type='ORTHO';camera_data.ortho_scale=10.6
        pitch=math.radians(43);yaw=math.radians(45);focus=vec((0,1.1,.35))
        camera.location=focus+vec((math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch)))*22
        camera.rotation_euler=(focus-camera.location).to_track_quat('-Z','Y').to_euler();scene.camera=camera
        scene['scope']='White blockout only. Shared shell unmodified. A2 uses approved X-only preview scaling.'
    bpy.context.window.scene=first
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'service_hall_blockouts.blend'))
    print('N2_SOURCE_READY',len(DATA['layouts']))


if __name__=='__main__':main()
