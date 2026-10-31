"""Populate N2 prop swatches without modifying the pinned shared hall atlas."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw
from dependencies import ROOT,SRC,DEPS,HALL,write_json

KIT=ROOT/'assets/rooms/poi_service_hall'
KIT.mkdir(parents=True,exist_ok=True)
palette=json.loads((DEPS/HALL/'hall_palette.json').read_text())
overrides={'cloth_green':'435B76','print_landscape':'6180A3','print_portrait':'BC4536','sky':'78A8C9'}
source=DEPS/HALL/palette['atlas']
image=Image.open(source).convert('RGB');draw=ImageDraw.Draw(image)
for name,color in overrides.items():
    x,y,w,h=palette['slots'][name]['rect_px_top_left']
    draw.rectangle((x,y,x+w-1,y+h-1),fill='#'+color)
image.save(KIT/'hall_albedo_ao_n2.png')
write_json(KIT/'prop_palette.json',{'source':'assets/rooms/_shared/shell_hall/hall_palette.json',
    'source_atlas_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'phase':'Prop colours only; shell skin not applied',
    'slots':palette['slots'],'overrides':overrides,'uv_layout_unchanged':True})
print(KIT/'hall_albedo_ao_n2.png')
