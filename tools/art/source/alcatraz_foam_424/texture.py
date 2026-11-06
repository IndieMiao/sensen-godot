"""Original periodic foam alpha: soft torn band and sparse filaments, no animation."""
from pathlib import Path
import numpy as np
from PIL import Image
S=Path(__file__).resolve().parent;R=S.parents[3];A=R/'assets/landmarks/alcatraz_island';A.mkdir(parents=True,exist_ok=True)
w,h=512,128
u=np.arange(w)[None,:]/w;v=np.linspace(0,1,h)[:,None]
center=.50+.065*np.sin(2*np.pi*(3*u+.13))+.025*np.sin(2*np.pi*11*u)
width=.13+.025*np.sin(2*np.pi*(7*u+.33))+.02*np.cos(2*np.pi*13*u)
d=(v-center)/width
broad=np.exp(-d*d*.75)
breakup=.62+.16*np.sin(2*np.pi*(4*u+.23))+.10*np.cos(2*np.pi*(7*u+v*.4))+.07*np.sin(2*np.pi*(11*u-v))
breakup=np.clip(breakup,.16,.95)
filament=np.exp(-((v-center-.13-.025*np.sin(2*np.pi*5*u))/.036)**2)
filament*=.65+.25*np.sin(2*np.pi*3*u)**2
edge=np.clip(v/.16,0,1)*np.clip((1-v)/.16,0,1);edge=edge*edge*(3-2*edge)
alpha=np.clip((broad*(.12+.25*breakup)+filament*.09)*edge,0,.48)
img=np.empty((h,w,4),dtype=np.uint8);img[:,:,:3]=(240,246,239);img[:,:,3]=np.rint(alpha*255)
# Exactly repeat across the seam, and zero along both cross-band borders.
img[:,-1]=img[:,0];img[0,:,3]=0;img[-1,:,3]=0
Image.fromarray(img).save(A/'alc_foam_soft.png')
print('FOAM_TEXTURE',w,h,'alpha max',int(img[:,:,3].max()))
