"""Inspect source UV length ratios on the actual folded throw in Blender."""
from pathlib import Path
import json,bpy,math
ROOT=Path(__file__).resolve().parents[4]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/art/source/standard_room_5/standard_room_5.blend'))
results=[]
for prefix in ['Square gingham sofa throw','Folded striped kitchen towel']:
    obj=next(o for o in bpy.context.scene.objects if o.name.startswith(prefix))
    uv=obj.data.uv_layers['MetricClothUV'];ratios=[]
    for polygon in obj.data.polygons:
        loops=list(polygon.loop_indices)
        for i,li in enumerate(loops):
            other=loops[(i+1)%len(loops)];a=obj.data.vertices[obj.data.loops[li].vertex_index].co;b=obj.data.vertices[obj.data.loops[other].vertex_index].co
            edge=(b-a).length;duv=(uv.data[other].uv-uv.data[li].uv).length
            if duv>.0001:ratios.append(edge/duv)
    record={'source_object':obj.name,'uv_layer':'MetricClothUV','minimum_3d_length_per_uv_metre':min(ratios),'maximum_3d_length_per_uv_metre':max(ratios),'checked_edges':len(ratios),'cell_size_metres':obj.get('checked_cell_metres'),'passed':min(ratios)>.90 and max(ratios)<1.10}
    results.append(record)
out=ROOT/'docs/design/standard_room_5-review21-2026-10-07/cloth-uv-verification.json'
out.write_text(json.dumps({'passed':all(x['passed'] for x in results),'checks':results,'scope':'Source surface-to-UV metric ratios; visual bake inspection remains required.'},indent=2)+'\n')
print(json.dumps(results,indent=2));assert all(x['passed'] for x in results)
