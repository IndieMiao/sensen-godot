from pathlib import Path
import bpy,json
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];SOURCE=ROOT/'tools/art/source/poi_church/poi_church.blend'
for name in json.loads((SRC/'copied-assets.json').read_text())['assets']:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.context.preferences.filepaths.save_version=0
 with bpy.data.libraries.load(str(SOURCE),link=False) as (a,b):b.collections=['KIT_'+name]
 c=b.collections[0];bpy.context.scene.collection.children.link(c);root=next(o for o in c.objects if o.type=='EMPTY');root.location=(0,0,0);root.rotation_euler=(0,0,0);root.scale=(1,1,1)
 for o in c.objects:o.hide_render=False;o.hide_set(False)
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
print('COPIED_NAMED_SOURCE')
