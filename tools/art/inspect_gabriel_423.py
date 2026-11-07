import bpy,json
from pathlib import Path
root=Path(__file__).resolve().parents[2]
(root/"output/gabriel-423").mkdir(parents=True,exist_ok=True)
(root/"output/.gdignore").touch()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(root/'assets/avatar/source/cloth1/SK_dt_skin01.fbx'))
for o in bpy.context.scene.objects:
 if o.type!='MESH': continue
 m=o.data;m.calc_loop_triangles()
 print('MESH',o.name,len(m.vertices),len(m.loop_triangles),'TRANSFORM',o.matrix_world)
 v=[list(o.matrix_world@x.co) for x in m.vertices]
 print('BOUNDS',[(min(x[i] for x in v),max(x[i] for x in v)) for i in range(3)])
 if o.name.lower()=='cloth':
  d={'verts':v,'triangles':[list(t.vertices) for t in m.loop_triangles], 'uv':[[list(m.uv_layers.active.data[i].uv) for i in t.loops] for t in m.loop_triangles]}
  (root/'output/gabriel-423/cloth-uv.json').write_text(json.dumps(d))
