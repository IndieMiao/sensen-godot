#!/usr/bin/env python3
"""Lou: one atlas for cloth1 white shirt, reused dark trousers and wine/black details."""
import argparse
from pathlib import Path
import numpy as np
from PIL import Image

parser=argparse.ArgumentParser()
parser.add_argument('--runtime-root',type=Path,required=True)
args=parser.parse_args()
src=args.runtime_root/'assets/avatar/source'
dest=src/'cloth1_npc_lou';dest.mkdir(parents=True,exist_ok=True)
shirt=np.array(Image.open(src/'cloth1/T_skin01_cloth_D 1.png').convert('RGBA'))
lum=shirt[...,:3].astype(float) @ [.2126,.7152,.0722]
shirt[...,:3]=np.clip(lum[...,None]*np.array([.97,.97,.955]),0,255).astype(np.uint8)
pants=np.array(Image.open(src/'cloth36_npc_sigrid/T_skin36_cloth_D.png').convert('RGBA'))
lum=pants[...,:3].astype(float) @ [.2126,.7152,.0722]
shade=np.interp(lum,[15,55,100,255],[22,48,78,150])
pants[...,:3]=np.clip(shade[...,None]*np.array([1,.99,1.04]),0,255).astype(np.uint8)
atlas=Image.new('RGBA',(1024,1024),'#6b2e3d')
atlas.paste(Image.fromarray(shirt).resize((1024,512),Image.Resampling.LANCZOS),(0,0))
atlas.paste(Image.fromarray(pants).resize((512,512),Image.Resampling.LANCZOS),(0,512))
palette=['6B2E3D','51232E','242329','B7A48C','EAE9E2','783648','353239','92798A']
pixels=np.array(atlas)
for i,color in enumerate(palette):
    pixels[512:1024,512+i*64:512+(i+1)*64,:3]=[int(color[j:j+2],16) for j in (0,2,4)]
Image.fromarray(pixels).save(dest/'T_lou_cloth01_D.png')
for old,new in [('SK_dt_skin01.fbx','SK_dt_skin01.fbx'),('T_skin01_cloth_D 1.png','T_lou_cloth01_D.png')]:
    path=dest/(new+'.import')
    if not path.exists():
        params=(src/'cloth1'/(old+'.import')).read_text().split('[params]\n',1)[1]
        importer,kind=('scene','PackedScene') if new.endswith('.fbx') else ('texture','CompressedTexture2D')
        path.write_text(f'[remap]\nimporter="{importer}"\ntype="{kind}"\n\n[params]\n'+params)
print('LOU_ATLAS_READY')
