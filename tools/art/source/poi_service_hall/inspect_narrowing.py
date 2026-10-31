"""Record the actual named 324 parts behind the approved blockout dimensions."""
from pathlib import Path
import json
import bpy

SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[3]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'output/poi-service-hall-321/dependencies/tools/art/source/hallkit_324/hallkit_324.blend'))
report={'source_commit':'104446a2a995c8a0269d12d27308b3d547b29f6e','parts':{},
        'approved_blockout_targets':{'sofa_width_m':2.30,'armchair_width_m':1.30,'seat_above_floor_m':.715,'table_diameter_m':.60,'table_height_m':.75},
        'production_rule':'Only X node scaling in blockout. After approval remodel named source parts; preserve Y/Z, seat height, and rebuild bevels and upholstery details.',
        'armchair_rule':'Final cushion remains .99m; back/base remain unchanged. Only upper arm outside edges are reduced.',
        'sofa_rule':'Director approved X adjustments to base/back/cushions; final three cushions total about 2.10m and seat centres -.70,0,.70.'}
for name in ['sofa_three_seat','armchair']:
    parts=[]
    for obj in bpy.data.collections['KIT_'+name].objects:
        if obj.type!='MESH':continue
        points=[vertex.co for vertex in obj.data.vertices]
        lo=[min(v[i] for v in points) for i in range(3)];hi=[max(v[i] for v in points) for i in range(3)]
        parts.append({'name':obj.name,'width_m':hi[0]-lo[0],
                      'bounds_y_up':[[lo[0],lo[2],-hi[1]],[hi[0],hi[2],-lo[1]]]})
    report['parts'][name]=parts
(SRC/'narrowing_assessment.json').write_text(json.dumps(report,indent=2)+'\n')
print('NARROWING_SOURCE_MEASURED',len(report['parts']['sofa_three_seat']),len(report['parts']['armchair']))
