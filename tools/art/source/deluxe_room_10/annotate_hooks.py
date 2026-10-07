"""Project canonical anchors onto the current actual Godot kitchen view."""
from pathlib import Path
import json,os,hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];DOC=ROOT/'docs/design/deluxe_room_10-2026-10-07';OUT=Path(os.environ['SCENE_REVIEW_OUTPUT']);layout=json.loads((ROOT/'assets/rooms/deluxe_room_10/layout.json').read_text());view=next(v for v in layout['review_views'] if v['name']=='detail-kitchen')
source=OUT/'detail-kitchen.png';im=Image.open(source).convert('RGB');canvas=Image.new('RGB',(im.width+560,im.height),'#f5f0df');canvas.paste(im,(0,0));draw=ImageDraw.Draw(canvas)
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',21);small=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',16)
eye=np.array(view['position']);target=np.array(view['target']);forward=target-eye;forward/=np.linalg.norm(forward);right=np.cross(forward,[0,1,0]);right/=np.linalg.norm(right);up=np.cross(right,forward)
def pixel(pos):
 d=np.array(pos)-target;return (round(im.width/2+d@right*im.width/view['size']),round(im.height/2-d@up*im.width/view['size']))
anchors=[a for a in layout['anchors'] if a['name'] not in ('spawn','exit')]
for i,a in enumerate(anchors,1):
 x,y=pixel(a['position']);dy=38+(i-1)*86;color='#CA2855' if a['name'].startswith('use_stove') else '#AA5E12' if a['name'].startswith('drop_') else '#25669A'
 draw.line([(x,y),(im.width-14,dy+9),(im.width+13,dy+9)],fill=color,width=2)
 draw.ellipse((x-7,y-7,x+7,y+7),fill=color,outline='white',width=2);draw.text((x+10,y-20),str(i),font=font,fill=color)
 draw.text((im.width+22,dy-4),f'{i}  '+a['name'],font=font,fill=color)
 draw.text((im.width+22,dy+26),str(a['position'])+' m',font=small,fill='#453B2D')
 draw.text((im.width+22,dy+49),'module: '+a['module']+(' / yaw 90' if a['name']=='stand_stove' else ''),font=small,fill='#453B2D')
# The floor-pivot replacement volume sits behind the island from this camera.
slot=next(a for a in anchors if a['name']=='use_warming_cabinet');x,y,z=slot['position'];sx,sy,sz=.69,1.08,.56
corners=[pixel([x+dx*sx/2,y+dy*sy,z+dz*sz/2]) for dy in (0,1) for dx,dz in ((-1,-1),(1,-1),(1,1),(-1,1))]
for a,b in [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]:
 pa=np.array(corners[a]);pb=np.array(corners[b]);steps=max(1,round(np.linalg.norm(pb-pa)/8))
 for j in range(0,steps,2):draw.line([tuple(pa+(pb-pa)*j/steps),tuple(pa+(pb-pa)*min(j+1,steps)/steps)],fill='#25669A',width=2)
for i,line in enumerate(['WP7-B canonical layout.anchors','8: dashed cabinet behind island','9: floor stand faces stove (yaw 90)','Room spawn / exit listed in README','Godot Mobile / canonical anchor overlay']):draw.text((im.width+22,925+i*27),line,font=small,fill='#453B2D')
canvas.save(DOC/'kitchen-attachment-points.png')
(DOC/'anchor-annotation-provenance.json').write_text(json.dumps({'base_capture':str(source.relative_to(ROOT)),'base_capture_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'method':'Current Godot R2.2 capture, canonical anchors projected with the exact capture camera.','anchor_schema':'WP7-B F-03 ③','room_anchor_count':len(layout['anchors']),'detail_annotations':len(anchors)},indent=2)+'\n')
