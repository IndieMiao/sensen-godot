from pathlib import Path
from PIL import Image
import numpy as np,json
O=Path(__file__).resolve().parents[4]/'output/church-423-v11';C=O/'captures';rows=[]
for mag in sorted(C.glob('*_magenta.png')):
 f=C/(mag.name.replace('_magenta',''));a=np.array(Image.open(f));b=np.array(Image.open(mag));d=np.abs(a.astype(int)-b.astype(int));m=d[:,:,:3].max(2)>0
 row={'name':f.name,'different_pixels':int(m.sum()),'maximum_channel_difference':int(d.max()),'corner_pixels':{name:int(m[y:y+32,x:x+32].sum()) for name,x,y in [('tl',0,0),('tr',328,0),('bl',0,768),('br',328,768)]}}
 rows.append(row)
 if m.any():print('FAIL',row)
print('COVERAGE',len(rows),'passed',all(r['different_pixels']==0 for r in rows))
(O/'coverage-validation.json').write_text(json.dumps({'method':'background-only colour toggle, fixed geometry/lights/camera; full native 360x800 pixels','cases':rows,'passed':len(rows)>=31 and all(r['different_pixels']==0 for r in rows)},indent=2)+'\n')
if (C/'godot-validation.json').exists():
 r=json.loads((C/'godot-validation.json').read_text());print('GODOT',r['passed'],'checks',len(r['checks']));print('FOLLOW',r['follow_cases'])
