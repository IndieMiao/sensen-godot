"""Bake continuous trail / rock / water masks from the authoritative farm layout.
Run: uv run --with pillow python tools/art/bake_farm_ground.py
The RGB channels are data masks, not a screenshot of the farm.
"""
from pathlib import Path
import json
import hashlib
import sys
from PIL import Image, ImageDraw, PngImagePlugin, ImageFilter
ROOT = Path(__file__).resolve().parents[2]
SIZE = 1024
SCALE = 2

def path_points(points):
    out = []
    for i in range(len(points)-1):
        p0,p1,p2,p3 = points[max(0,i-1)],points[i],points[i+1],points[min(len(points)-1,i+2)]
        for step in range(8):
            t=step/8
            out.append(tuple(.5*(2*p1[a]+(-p0[a]+p2[a])*t+(2*p0[a]-5*p1[a]+4*p2[a]-p3[a])*t*t+(-p0[a]+3*p1[a]-3*p2[a]+p3[a])*t*t*t) for a in (0,1)))
    return out+[tuple(points[-1])]

def bake(layout):
    image=Image.new('RGB',(SIZE*SCALE,SIZE*SCALE))
    draw=ImageDraw.Draw(image)
    unit=SIZE*SCALE/layout['grid'][0]
    colors={'path':(255,0,0),'rock':(0,255,0),'water':(0,0,255)}
    for region in layout['regions']:
        color=colors.get(region['kind'],(0,0,0))
        if 'rect' in region:
            x,y,w,h=region['rect'];draw.rectangle((x*unit,y*unit,(x+w)*unit-1,(y+h)*unit-1),fill=color)
        elif 'ellipse' in region:
            x,y,rx,ry=region['ellipse'];draw.ellipse(((x+.5-rx)*unit,(y+.5-ry)*unit,(x+.5+rx)*unit,(y+.5+ry)*unit),fill=color)
        else:
            points=[((x+.5)*unit,(y+.5)*unit) for x,y in path_points(region['path'])]
            width=region['width']*unit
            draw.line(points,fill=color,width=round(width),joint='curve')
            for x,y in points:
                draw.ellipse((x-width/2,y-width/2,x+width/2,y+width/2),fill=color)
    image=image.resize((SIZE,SIZE),Image.Resampling.LANCZOS)
    red,green,blue=image.split()
    image=Image.merge('RGB',(red,green,blue.filter(ImageFilter.GaussianBlur(4))))
    dest=ROOT/layout['ground_texture'].removeprefix('res://')
    digest=hashlib.sha256(json.dumps({k:v for k,v in layout.items() if k!='checksum'},sort_keys=True).encode()).hexdigest()
    metadata=PngImagePlugin.PngInfo()
    metadata.add_text('layout_hash',digest)
    image.save(dest,pnginfo=metadata)
    print(dest.relative_to(ROOT))

if __name__ == '__main__':
    data=json.loads((ROOT/'assets/farm/data/farm_plot.json').read_text())
    for layout in data['layouts'].values():
        if 'ground_texture' not in layout: continue
        if '--check' in sys.argv:
            digest=hashlib.sha256(json.dumps({k:v for k,v in layout.items() if k!='checksum'},sort_keys=True).encode()).hexdigest()
            assert Image.open(ROOT/layout['ground_texture'].removeprefix('res://')).info.get('layout_hash')==digest, 'Ground texture is stale; run the baker'
        else: bake(layout)
