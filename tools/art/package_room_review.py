"""Collect inspectable art evidence after actual Godot and Blender rendering."""
from pathlib import Path
import hashlib
import json
import shutil
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
slug=sys.argv[1]
out=ROOT/'output'/(slug+'-2026-10-07')
docs=ROOT/'docs/design'/(slug+'-2026-10-07')
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',25)
small=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',18)

def sheet(items,filename,w=900,h=690):
    im=Image.new('RGB',(len(items)*w,h+70),'#f5f0df');d=ImageDraw.Draw(im)
    for i,(label,path) in enumerate(items):
        pic=Image.open(path).convert('RGB');pic.thumbnail((w-20,h-20),Image.Resampling.LANCZOS)
        im.paste(pic,(i*w+(w-pic.width)//2,65+(h-20-pic.height)//2))
        d.text((i*w+20,15),label,font=font,fill='#53462f')
    im.save(docs/filename)

shutil.copy2(out/'godot.png',docs/'godot.png')
sheet([('Figma reference',docs/'reference.png'),('Godot Mobile / Vulkan',out/'godot.png')],'comparison.png')
sheet([(n.capitalize()+' / Blender model',out/(n+'.png')) for n in ('front','side','top')],'orthographic-sheet.png',640,640)
stats=json.loads((ROOT/'assets/rooms'/slug/'asset_stats.json').read_text())
validation=json.loads((out/'godot-validation.json').read_text())
assert stats['scene_triangles']==validation['triangles']
files=list((ROOT/'assets/rooms'/slug).glob('*.glb'))+list((ROOT/'assets/rooms'/slug).glob('*.png'))+[ROOT/'tools/art/source'/slug/(slug+'.blend')]
layout=json.loads((ROOT/'assets/rooms'/slug/'layout.json').read_text())
if layout.get('shared_plants'):
    shared=ROOT/'assets/rooms/_shared/plants'
    files += [shared/name for name in sorted({a['file'] for a in layout['shared_plants']})]
    files += [shared/'room_albedo_ao.png',shared/'material.tres']
summary={'status':'art review candidate; user acceptance pending','asset_stats':stats,'godot':validation,
         'hashes':{str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files},
         'scope':'Art assets only; no gameplay, Android benchmark, physical-device performance or release claim.'}
(docs/'verification-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({'scene':slug,'assets':len(stats['assets']),'instances':stats['placed_instances'],'triangles':stats['scene_triangles']}))
