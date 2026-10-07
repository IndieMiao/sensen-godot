"""Annotate real Godot kitchen capture using its actual camera projection."""
from pathlib import Path
import json,os
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];DOC=ROOT/'docs/design/deluxe_room_10-2026-10-07';OUT=Path(os.environ['SCENE_REVIEW_OUTPUT']);layout=json.loads((ROOT/'assets/rooms/deluxe_room_10/layout.json').read_text());view=next(x for x in layout['review_views'] if x['name']=='detail-kitchen')
im=Image.open(OUT/'detail-kitchen.png').convert('RGB');canvas=Image.new('RGB',(im.width+470,im.height),'#f5f0df');canvas.paste(im,(0,0));d=ImageDraw.Draw(canvas);font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',22);small=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',17)
eye=np.array(view['position']);target=np.array(view['target']);f=target-eye;f/=np.linalg.norm(f);right=np.cross(f,[0,1,0]);right/=np.linalg.norm(right);up=np.cross(right,f)
def pixel(position):
 delta=np.array(position)-target;return (round(im.width/2+delta@right*im.width/view['size']),round(im.height/2-delta@up*im.width/view['size']))
for i,p in enumerate(layout['attachment_points'],1):
 x,y=pixel(p['position']);dy=70+(i-1)*126
 color='#CB255A' if i<4 else '#2165A1'
 d.line([(x,y),(im.width-24,dy+10),(im.width+14,dy+10)],fill=color,width=2)
 d.ellipse((x-8,y-8,x+8,y+8),fill=color,outline='white',width=2);d.text((x+11,y-22),str(i),font=font,fill=color)
 d.text((im.width+22,dy-2),f'{i}  '+p['name'],font=font,fill=color)
 d.text((im.width+22,dy+34),'Y up / metres',font=small,fill='#453B2D');d.text((im.width+22,dy+61),str(p['position']),font=small,fill='#453B2D')
# X-ray wireframe makes the replaceable cabinet's volume legible behind island.
slot=next(p for p in layout['attachment_points'] if p['name']=='warmer_slot');x,y,z=slot['position'];sx,sy,sz=slot['size']
corners=[pixel([x+dx*sx/2,y+dy*sy,z+dz*sz/2]) for dy in (0,1) for dx,dz in ((-1,-1),(1,-1),(1,1),(-1,1))]
for a,b in [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]:
 pa=np.array(corners[a]);pb=np.array(corners[b]);distance=np.linalg.norm(pb-pa);steps=max(1,round(distance/8))
 for j in range(0,steps,2):d.line([tuple(pa+(pb-pa)*j/steps),tuple(pa+(pb-pa)*min(j+1,steps)/steps)],fill='#2165A1',width=2)
d.text((im.width+22,808),'6: dashed volume behind island',font=small,fill='#2165A1')
r=json.loads((DOC/'kitchen-hooks-verification.json').read_text());d.text((im.width+22,860),f'Pendant bottom: {r["pendant_shade_bottom_y"]:.2f} m',font=font,fill='#453B2D');d.text((im.width+22,900),f'Above avatar head: {r["shade_above_avatar_m"]:.2f} m',font=small,fill='#453B2D');d.text((im.width+22,937),'Prep surface clear: 0.50 m',font=small,fill='#453B2D');d.text((im.width+22,974),'Empty / Marker3D mounts only',font=small,fill='#453B2D');canvas.save(DOC/'kitchen-attachment-points.png')
