#!/usr/bin/env python3
"""Inspect representative water colour patches, not whole-image fidelity.

The concept and game retain different pond outlines. Samples represent far,
mid and foreground water, not geometrically registered pixels or measured depth.
Run with the same 1280x800 reference camera and TIME=12 for both game renders.
Requires NumPy and Pillow.
"""
import argparse
import colorsys
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
SAMPLES = {
    'Design': [(600,300),(690,385),(530,566),(676,708),(565,772)],
    'Previous': [(569,222),(668,269),(571,379),(560,582),(520,667)],
    'Revised': [(569,222),(668,269),(571,379),(560,582),(520,667)],
}
LABELS = ['Far water','Deep basin','Middle water','Foreground shelf','Near margin']


def luminance(rgb):
    s = np.asarray(rgb) / 255
    linear = np.where(s <= .04045, s/12.92, ((s+.055)/1.055)**2.4)
    y = float(np.dot(linear,[.2126,.7152,.0722]))
    return 116*y**(1/3)-16 if y>.008856 else y*903.3


def sample(image, point):
    x,y=point
    pixels=np.asarray(image)[y-18:y+19,x-18:x+19,:3].reshape(-1,3).astype(float)
    # Reject warm bank/leaf colours and white glints, retaining cyan/blue water.
    pixels=pixels[(pixels[:,2]>pixels[:,1]*.90)&(pixels[:,1]>pixels[:,0]*1.65)&(pixels[:,2]-pixels[:,0]>55)]
    if len(pixels)<200:
        raise ValueError(f'Not enough clear water pixels at {point}')
    rgb=np.median(pixels,axis=0).astype(int).tolist()
    hsv=colorsys.rgb_to_hsv(*(np.array(rgb)/255))
    return {'point':list(point),'radius_pixels':18,'retained_pixels':len(pixels),
            'rgb':rgb,'hex':'#'+''.join(f'{v:02X}' for v in rgb),
            'hue_degrees':round(hsv[0]*360,1),'L_star':round(luminance(rgb),1)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render',type=Path,required=True)
    parser.add_argument('--previous',type=Path,default=ROOT/'output/pond-colour-2026-09-29/before/gourd-reference.png')
    parser.add_argument('--reference',type=Path,default=ROOT/'docs/design/pond-reference-2026-09-29/reference.png')
    parser.add_argument('--out',type=Path,default=ROOT/'output/pond-colour-2026-09-29')
    args=parser.parse_args(); args.out.mkdir(parents=True,exist_ok=True)
    sources={'Design':args.reference,'Previous':args.previous,'Revised':args.render}
    # Platform-independent Pillow fallback; use the host font when available.
    font_path=Path('/System/Library/Fonts/Helvetica.ttc')
    font=ImageFont.truetype(str(font_path),25) if font_path.exists() else ImageFont.load_default(size=25)
    small=ImageFont.truetype(str(font_path),19) if font_path.exists() else ImageFont.load_default(size=19)
    w,h=720,472
    sheet=Image.new('RGB',(w*3,h+500),'#f3f3ee')
    draw=ImageDraw.Draw(sheet)
    result={'method':'Median of 37x37 representative water regions; warm objects and white glints excluded. Not registered geometry or a fidelity score.','samples':{}}
    for col,(label,path) in enumerate(sources.items()):
        image=Image.open(path).convert('RGB')
        rows=[sample(image,p) for p in SAMPLES[label]]
        result['samples'][label]=rows
        annotated=image.copy(); ink=ImageDraw.Draw(annotated)
        for i,(x,y) in enumerate(SAMPLES[label]):
            ink.rectangle((x-18,y-18,x+18,y+18),outline='white',width=3)
            ink.text((x+23,y-15),str(i+1),font=font,fill='#132b36',stroke_width=1,stroke_fill='white')
        annotated.save(args.out/f'{label.lower()}-samples.png')
        fitted=ImageOps.contain(annotated,(w,h))
        sheet.paste(fitted,(col*w+(w-fitted.width)//2,64))
        draw.text((col*w+24,20),label,fill='#18363c',font=font)
        for i,row in enumerate(rows):
            yy=h+90+i*68
            draw.rounded_rectangle((col*w+24,yy,col*w+112,yy+46),radius=5,fill=tuple(row['rgb']))
            draw.text((col*w+128,yy),f'{i+1}  {LABELS[i]}   {row["hex"]}',font=small,fill='#18363c')
            draw.text((col*w+128,yy+26),f'H {row["hue_degrees"]:.1f} deg    L* {row["L_star"]:.1f}',font=small,fill='#52696e')
    for label,rows in result['samples'].items():
        result.setdefault('foreground_minus_deep_L_star',{})[label]=round(rows[3]['L_star']-rows[1]['L_star'],1)
    draw.text((24,h+460),'Representative colour patches; original pond outlines retained. These are not pixel-aligned similarity scores.',font=small,fill='#52696e')
    sheet.save(args.out/'colour-comparison.png')
    (args.out/'colour-samples.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
