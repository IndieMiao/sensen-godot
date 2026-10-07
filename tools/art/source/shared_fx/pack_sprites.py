"""Pack rendered R2.1 cloud sprites and original curved cartoon flame silhouettes."""
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
ROOT=Path(__file__).resolve().parents[4];out=ROOT/'assets/rooms/_shared/fx';out.mkdir(exist_ok=True)
strip=Image.new('RGBA',(1024,256))
for i in range(4):strip.paste(Image.open(ROOT/f'output/shared-fx/smoke-{i}.png').convert('RGBA'),(i*256,0))
strip.save(out/'smoke_strip.png')
# Smooth closed teardrops with different tip bends, gradient follows accepted orange/red direction.
strip=Image.new('RGBA',(1024,256));size=1024
for i,bend in enumerate([-.11,.15,.05,-.06]):
 mask=Image.new('L',(size,size));points=[]
 for side in [-1,1]:
  seq=np.linspace(0,1,150);seq=seq if side==-1 else seq[::-1]
  for t in seq:
   radius=(.09+.18*np.sin(np.pi*t)**.8)*(1-t**1.6)
   cx=.5+bend*t*t+.045*np.sin(t*6+i)*t
   points.append(((cx+side*radius)*size,(.88-.78*t)*size))
 ImageDraw.Draw(mask).polygon(points,fill=255);mask=mask.filter(ImageFilter.GaussianBlur(3)).resize((256,256),Image.Resampling.LANCZOS)
 y,x=np.mgrid[0:256,0:256];t=np.clip((.88-y/256)/.78,0,1)
 stops=[(0,'C7300C'),(.25,'EF4F10'),(.52,'FFA62F'),(.78,'FF8B22'),(1,'EB5515')];rgb=np.zeros((256,256,3))
 for (a,ha),(b,hb) in zip(stops,stops[1:]):
  ca=np.array([int(ha[j:j+2],16) for j in (0,2,4)]);cb=np.array([int(hb[j:j+2],16) for j in (0,2,4)]);w=np.clip((t-a)/(b-a),0,1);region=(t>=a)&(t<=b);rgb[region]=(ca+(cb-ca)*w[...,None])[region]
 arr=np.dstack([rgb,np.array(mask)]).astype('uint8');strip.paste(Image.fromarray(arr),(i*256,0))
strip.save(out/'flame_strip.png')
x,y=np.meshgrid(np.linspace(-1,1,64),np.linspace(-1,1,64));a=np.clip((1-np.sqrt(x*x+y*y))/.24,0,1);spark=np.ones((64,64,4),dtype=np.uint8)*255;spark[:,:,3]=(a*255).astype('uint8');Image.fromarray(spark).save(out/'spark.png')
