#!/usr/bin/env python3
"""Create a scene-independent daylight HDR environment for pond reflections.

This is an authored procedural latitude/longitude radiance map, not a screen
texture. The sun stays in Godot's DirectionalLight3D, so it is not counted twice.
Requires NumPy and Pillow. No third-party image assets or network dependencies.
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/ponds/art'
W, H = 1024, 512
u,v=np.meshgrid((np.arange(W)+.5)/W,(np.arange(H)+.5)/H)
longitude=u*2*np.pi-np.pi
latitude=np.pi*.5-v*np.pi
sky_y=np.sin(latitude)

def smooth(a,b,x):
    t=np.clip((x-a)/(b-a),0,1)
    return t*t*(3-2*t)

# A clear blue zenith, warmer horizon and muted meadow/trees below the horizon.
horizon=np.array([.90,1.08,1.13])
zenith=np.array([.21,.43,.77])
height=smooth(.0,.92,np.maximum(sky_y,0))
rgb=horizon[None,None,:]*(1-height[...,None])+zenith[None,None,:]*height[...,None]
# Broad irregular clouds have enough angular shape to read in moving normals.
# Periodic longitude harmonics close the seam and avoid a sliding screen decal.
cloud=np.sin(longitude*3+.45*np.sin(latitude*4))*.42
cloud+=np.sin(longitude*7-latitude*8+.7)*.23
cloud+=np.cos(longitude*11+latitude*13+1.4)*.13
cloud+=np.sin(longitude*17-latitude*18+.9)*.06
cloud+=.20*np.sin(latitude*9+.6)
cloud=smooth(.00,.51,cloud)*smooth(.08,.31,sky_y)*(1-smooth(.90,1.0,sky_y))
cloud_light=np.array([5.1,5.4,5.5])
rgb=rgb*(1-cloud[...,None])+cloud_light[None,None,:]*cloud[...,None]
# A restrained treeline breaks the reflected horizon without baking pond objects.
canopy=.06+.06*np.sin(longitude*9)**2+.04*np.sin(longitude*19+.4)**2
forest=(1-smooth(canopy-.05,canopy+.035,sky_y))*(1-smooth(.0,.1,-sky_y))
rgb=rgb*(1-forest[...,None]) + np.array([.12,.20,.11])*forest[...,None]
ground=smooth(-.025,-.15,sky_y)
rgb=rgb*(1-ground[...,None])+np.array([.21,.26,.12])*ground[...,None]

# Radiance RGBE, legal RLE literal scanlines. Godot imports linear HDR radiance.
maximum=rgb.max(axis=2)
mantissa,exponent=np.frexp(maximum)
scale=mantissa*256/np.maximum(maximum,1e-12)
rgbe=np.concatenate((np.clip(rgb*scale[...,None],0,255).astype(np.uint8),(exponent+128).astype(np.uint8)[...,None]),axis=2)
OUT.mkdir(parents=True,exist_ok=True)
with (OUT/'pond_daylight.hdr').open('wb') as f:
    f.write(f'#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y {H} +X {W}\n'.encode())
    for row in rgbe:
        f.write(bytes([2,2,W>>8,W&255]))
        for c in range(4):
            for start in range(0,W,127):
                chunk=row[start:start+127,c].tobytes()
                f.write(bytes([len(chunk)]));f.write(chunk)
# Tonemapped preview is for reviewing the authored environment, not rendering it.
preview=rgb/(1+rgb)
preview=np.where(preview<=.0031308,preview*12.92,1.055*preview**(1/2.4)-.055)
review=ROOT/'output/pond-reflection-2026-09-29'
review.mkdir(parents=True,exist_ok=True)
Image.fromarray(np.uint8(np.clip(preview,0,1)*255)).save(review/'environment-preview.png')
print('Saved 1024x512 linear HDR environment; sun supplied by scene light.')
