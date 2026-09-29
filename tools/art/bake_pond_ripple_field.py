#!/usr/bin/env python3
"""Original periodic noise for the two-layer water technique discussed by Josh/Jasper.

R stores smooth scalar height; G/B store its signed U/V derivatives / 18.
No downloaded tutorial/game textures are included. Requires NumPy and Pillow.
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
N=512
rng=np.random.default_rng(30092026)
k=np.fft.fftfreq(N)*N
radius=np.sqrt(k[:,None]**2+k[None,:]**2)
spectrum=np.exp(-(radius/7.0)**2)*(1-np.exp(-(radius/2.0)**2))
field=np.fft.ifft2(np.fft.fft2(rng.normal(size=(N,N)))*spectrum).real
field=(field-field.mean())/field.std()
detail_filter=np.exp(-(radius/16.0)**2)*(1-np.exp(-(radius/8.0)**2))
detail=np.fft.ifft2(np.fft.fft2(rng.normal(size=(N,N)))*detail_filter).real
field=field*.90+(detail-detail.mean())/detail.std()*.22
field=.5+.18*(field-field.mean())/field.std()
field=np.clip(field,.015,.985)
du=(np.roll(field,-1,1)-np.roll(field,1,1))*N*.5
dv=(np.roll(field,-1,0)-np.roll(field,1,0))*N*.5
packed=np.stack((field,.5+du/36,.5+dv/36),axis=-1)
out=ROOT/'assets/ponds/art/pond_ripple_field.png'
Image.fromarray(np.uint8(np.clip(packed,0,1)*255)).save(out)
print('Saved periodic scalar field + matching derivatives:',out)
