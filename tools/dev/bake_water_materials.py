"""Deterministic seamless bed, wave and caustic maps; no baked camera or game screenshot."""
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]/'assets/farm/art/water'
ROOT.mkdir(parents=True,exist_ok=True)
N=512
rng=np.random.default_rng(190919)
y,x=np.mgrid[0:N,0:N].astype(float);uv=np.stack((x/N,y/N),-1)
def smooth(a,b,v):
 t=np.clip((v-a)/(b-a),0,1);return t*t*(3-2*t)
def noise(scale,seed):
 gen=np.random.default_rng(seed);v=gen.normal(size=(N,N));f=np.fft.fft2(v);ky,kx=np.mgrid[-N//2:N//2,-N//2:N//2]
 filt=np.exp(-(kx*kx+ky*ky)/(scale*scale));v=np.fft.ifft2(f*np.fft.ifftshift(filt)).real
 return (v-v.min())/(v.max()-v.min())
def cells(count,seed,warp=0):
 gen=np.random.default_rng(seed);first=np.full((N,N),999.);second=first.copy();ident=np.zeros((N,N),dtype=int);dx0=np.zeros((N,N));dy0=dx0.copy()
 coord=uv*count
 if warp:coord=coord+np.stack((noise(4,seed+1)-.5,noise(5,seed+2)-.5),-1)*warp
 floor=np.floor(coord).astype(int);frac=coord-floor;points=gen.uniform(.04,.96,(count,count,2))
 for dy in [-1,0,1]:
  for dx in [-1,0,1]:
   index=(floor+np.array([dx,dy]))%count;delta=np.array([dx,dy])+points[index[:,:,1],index[:,:,0]]-frac;d=np.sum(delta*delta,axis=-1);closer=d<first
   second=np.where(closer,first,np.minimum(second,d));first=np.where(closer,d,first)
   ident=np.where(closer,index[:,:,1]*count+index[:,:,0],ident);dx0=np.where(closer,delta[:,:,0],dx0);dy0=np.where(closer,delta[:,:,1],dy0)
 return np.sqrt(first),np.sqrt(second),ident,dx0,dy0
first,second,idx,dx,dy=cells(9,40,.48)
gap=second-first;mask=smooth(.04,.16,gap);h=smooth(0,.27,gap)*np.maximum(0,1-first*.65)
palette=np.array([[.61,.62,.55],[.47,.54,.51],[.71,.69,.57],[.52,.59,.58],[.76,.75,.65],[.57,.56,.48]])
colors=palette[rng.integers(0,len(palette),9*9)][idx]
shade=.80+np.clip(dx*.20-dy*.24,-.18,.18)+h*.18
fine=noise(120,8);vein=noise(35,4)
colors=colors*shade[:,:,None]*(.97+.045*fine[:,:,None])+(vein[:,:,None]-.5)*.02
sand=np.stack([.46+.035*fine,.48+.035*fine,.38+.03*fine],-1)
colors=sand*(1-mask[:,:,None])+colors*mask[:,:,None]
Image.fromarray(np.uint8(np.clip(colors,0,1)*255),'RGB').save(ROOT/'pebble_bed.png')
# Packed wave slopes in RG, broad cloud/canopy noise in B; periodic on all borders.
height=noise(14,31)*.6+noise(32,32)*.28+noise(68,33)*.12
sx=(np.roll(height,-1,1)-np.roll(height,1,1))*9;sy=(np.roll(height,-1,0)-np.roll(height,1,0))*9
Image.fromarray(np.uint8(np.clip(np.stack((sx+.5,sy+.5,noise(7,17)),-1),0,1)*255),'RGB').save(ROOT/'surface_flow.png')
first,second,_,_,_=cells(8,83,1.9)
line=(1-smooth(.008,.090,second-first))**1.25
line*=.5+.5*noise(18,74)
Image.fromarray(np.uint8(np.clip(line,0,1)*255),'L').save(ROOT/'caustics.png')
print('Baked three seamless 512px water material maps.')
