"""Measure rendered gray ore bodies and ground at the same screen pixels."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image, ImageFilter

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
OUT=ROOT/'output/mine-vein-355';CAP=OUT/'captures'
WEIGHTS=np.array([.2126,.7152,.0722])

def stats(pixels):
    rgb=pixels.astype(float)/255
    luma=rgb@WEIGHTS
    linear=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
    return {'pixels':len(rgb),'median_srgb_rgb':np.median(rgb,axis=0).tolist(),
        'median_srgb_luma':float(np.median(luma)),
        'srgb_luma_p10_p90':np.quantile(luma,[.1,.9]).tolist(),
        'median_linear_luminance':float(np.median(linear@WEIGHTS))}

report={'method':'Median Rec.709-weighted sRGB pixel brightness (not linear luminance). '
    'ID pass selects visible gray stone bodies, excluding mineral stripes. Masks eroded by one pixel. '
    'Ground sampled at identical pixels with the two ore roots and their attached shadows hidden.',
    'formula':'Y_srgb = 0.2126 R_srgb + 0.7152 G_srgb + 0.0722 B_srgb',
    'bands':[],'ore_sha256':{},'passed':True}
for band in [3,4]:
    key='band_'+str(band)
    actual=np.array(Image.open(CAP/(key+'.png')).convert('RGB'))
    ids=np.array(Image.open(CAP/(key+'_ore_masks.png')).convert('RGB'))
    ground=np.array(Image.open(CAP/(key+'_ground_under_ores.png')).convert('RGB'))
    row={'band':[21,30] if band==3 else [31,40],'ores':{},'images':{}}
    for name in [key,key+'_ore_masks',key+'_ground_under_ores']:
        row['images'][name]=hashlib.sha256((CAP/(name+'.png')).read_bytes()).hexdigest()
    for ore,color in [('iron_ore',[255,0,255]),('quartz',[0,255,0])]:
        mask=np.all(np.abs(ids.astype(int)-np.array(color))<=2,axis=2)
        mask=np.array(Image.fromarray((mask*255).astype('uint8')).filter(ImageFilter.MinFilter(3)))>0
        assert mask.sum()>300,(key,ore,int(mask.sum()))
        stone_stats=stats(actual[mask]);ground_stats=stats(ground[mask])
        delta=ground_stats['median_srgb_luma']-stone_stats['median_srgb_luma']
        row['ores'][ore]={'body':stone_stats,'ground':ground_stats,'ground_minus_body_srgb_luma':delta,'passed':delta>=.15}
        report['passed'] &= delta>=.15
    report['bands'].append(row)
for ore in ['iron_ore','quartz']:
    path=ROOT/'output/monsters-355/runtime/assets/mine/rocks'/('rock_'+ore+'.glb')
    report['ore_sha256'][ore]=hashlib.sha256(path.read_bytes()).hexdigest()
(OUT/'ore-contrast-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
raise SystemExit(0 if report['passed'] else 1)
