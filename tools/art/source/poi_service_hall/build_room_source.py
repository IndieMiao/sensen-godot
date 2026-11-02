"""Editable assembled scene; original construction files remain pinned and named."""
from pathlib import Path
import json
import math
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent
KIT=ROOT/'assets/rooms/poi_service_hall'
HALL=ROOT/'output/poi-service-hall-321/dependencies/assets/rooms/_shared/shell_hall'
layout=json.loads((KIT/'layout.json').read_text())
shell=json.loads((HALL/'layout.json').read_text())
bpy.ops.wm.read_factory_settings(use_empty=True)
atlas=bpy.data.images.load(str(KIT/layout['atlas']));atlas.pack()

def vector(p):return Vector((p[0],-p[2],p[1]))

def add(name,path,at,yaw):
    collection=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(collection)
    before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(path))
    imported=set(bpy.data.objects)-before
    root=bpy.data.objects.new(name,None);collection.objects.link(root);root.location=vector(at)
    root.rotation_euler.z=math.radians(yaw);root['source_asset']=str(path.relative_to(ROOT))
    for obj in imported:
        for c in list(obj.users_collection):c.objects.unlink(obj)
        collection.objects.link(obj)
        if obj.parent not in imported:obj.parent=root
        if obj.type=='MESH':
            obj.name=name+'_mesh'
            for mat in obj.data.materials:
                if mat and mat.use_nodes:
                    for node in mat.node_tree.nodes:
                        if node.type=='TEX_IMAGE':node.image=atlas

assets={s['name']:s for s in shell['assets']}
for row in shell['assets']+shell['instances']:
    asset=assets[row.get('asset',row['name'])]
    add(row['name'],HALL/asset['file'],row['position'],row['yaw_degrees'])
for row in layout['placements']:
    add(row['name'],KIT/layout['assets'][row['asset']]['file'],row['position'],row['yaw_degrees'])
for anchor in layout['anchors']:
    obj=bpy.data.objects.new(anchor['name'],None);bpy.context.scene.collection.objects.link(obj)
    obj.location=vector(anchor['position']);obj.rotation_euler.z=math.radians(anchor['yaw_degrees'])
    obj.empty_display_type='ARROWS';obj.empty_display_size=.15;obj['module']=anchor['module']
    if 'size' in anchor:obj['size']=anchor['size']
bpy.context.scene['source_details']='service_hall_details.blend: editable named construction parts'
bpy.context.scene['source_324']='Pinned hallkit_324.blend at 104446a2: editable furniture construction'
bpy.context.scene['approved_layout']='B / 8 seats / C48 2026-11-02'
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'service_hall_room.blend'))
print('N2_ROOM_SOURCE',len(bpy.data.objects),flush=True)
