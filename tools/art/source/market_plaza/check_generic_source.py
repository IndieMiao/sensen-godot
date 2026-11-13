"""Blender read-only check of fixed generic door/step/box/window coordinates."""
from pathlib import Path
import bpy,json
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'docs/design/market-generic-v2-218-2026-11-13';OUT.mkdir(parents=True,exist_ok=True)
def snapshot(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    result={}
    for i in range(4):
        col=bpy.data.collections[f'facade_generic_{i}'];groups={}
        for tag in ['Door closed leaf','Door surround','Door lintel','Door inset panel','Door transom','Door knob','Decorative step','Window flowerbox']:
            values=[]
            for obj in col.objects:
                if not obj.name.startswith(tag):continue
                values.append([round(float(v),5) for v in [*obj.location,*obj.dimensions]])
            groups[tag]=sorted(values)
        glass=[obj for obj in col.objects if obj.name.startswith(('Opaque glass','Flush opaque glass'))]
        # Upper windows are flattened in depth only, as requested (no bay).
        groups['window_x_height']=sorted([[round(o.location.x,5),round(o.location.z,5)] for o in glass])
        result[str(i)]=groups
    return result
old=snapshot(ROOT/'output/market-generic-v2-218/baseline_market.blend')
new=snapshot(ROOT/'tools/art/source/market_plaza/market_plaza.blend')
assert old==new,'A fixed door/step/flowerbox or window XY moved'
(OUT/'source-bone-check.json').write_text(json.dumps({'baseline':'76a363edf','matched':True,'shared_coordinates_blender':new},indent=2)+'\n')
print('SOURCE_BONE_PASS 4 modules: doors/steps/flowerboxes exact; window x,height exact')
