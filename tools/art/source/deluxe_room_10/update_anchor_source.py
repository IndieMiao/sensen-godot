"""Metadata-only migration to WP7-B anchors. Preserves accepted mesh data."""
from pathlib import Path
import json,bpy,math,hashlib
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[4];src=Path(__file__).parent
bpy.ops.wm.open_mainfile(filepath=str(src/'deluxe_room_10.blend'));bpy.context.preferences.filepaths.save_version=0
def mesh_digest():
 h=hashlib.sha256()
 for obj in sorted([o for o in bpy.context.scene.objects if o.type=='MESH'],key=lambda o:o.name):
  h.update(obj.name.encode());h.update(str([list(row) for row in obj.matrix_world]).encode());h.update(str([list(v.co) for v in obj.data.vertices]).encode());h.update(str([list(p.vertices) for p in obj.data.polygons]).encode())
 return h.hexdigest()
bpy.context.view_layer.update();before=mesh_digest()
for c in list(bpy.data.collections):
 if c.name in ('ATTACHMENT_POINTS','WORLD_ANCHORS'):
  for obj in list(c.objects):bpy.data.objects.remove(obj,do_unlink=True)
  bpy.data.collections.remove(c)
collection=bpy.data.collections.new('WORLD_ANCHORS');bpy.context.scene.collection.children.link(collection)
for a in json.loads((src/'kitchen-anchors.json').read_text()):
 obj=bpy.data.objects.new(a['name'],None);collection.objects.link(obj);x,y,z=a['position'];obj.location=(x,-z,y);obj.rotation_euler.z=math.radians(a.get('yaw_degrees',0));obj.empty_display_type='ARROWS';obj.empty_display_size=.16
 if 'module' in a:obj['module']=a['module']
bpy.context.view_layer.update();after=mesh_digest();assert before==after
bpy.ops.wm.save_as_mainfile(filepath=str(src/'deluxe_room_10.blend'))
(ROOT/'docs/design/deluxe_room_10-2026-10-07/anchor-source-preservation.json').write_text(json.dumps({'mesh_geometry_and_placement_before':before,'after':after,'identical':True,'change':'Empties migrated only; no room meshes, materials, lights or camera altered.'},indent=2)+'\n')
print('ANCHOR_SOURCE_MIGRATED_MESHES_IDENTICAL')
