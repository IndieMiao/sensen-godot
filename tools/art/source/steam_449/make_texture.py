"""One128pxRGBA steam puff; warm white core,~2px cool rim at28–42px display (449v1.2)."""
from pathlib import Path
from PIL import Image
import math
ROOT=Path(__file__).resolve().parents[4]
N=128;im=Image.new('RGBA',(N,N))
for y in range(N):
 for x in range(N):
  xx=(x+.5-N/2)/(N/2-2);yy=(y+.5-N/2)/(N/2-2)
  a=math.atan2(yy,xx);r=math.hypot(xx,yy)/(1+.055*math.sin(3*a)+.035*math.cos(5*a))
  rim=max(0,min(1,(r-.88)/.055));rim=rim*rim*(3-2*rim)
  rgb=[round(white*(1-rim)+grey*rim) for white,grey in zip((255,248,240),(217,222,227))]
  if r<.65:
   t=max(0,min(1,r/.65));alpha=1-.45*t*t*(3-2*t)
  elif r<.94:alpha=.55+min(1,(r-.65)/.22)*.215
  else:
   t=max(0,min(1,(r-.94)/.06));alpha=.765*(1-t*t*(3-2*t))
  im.putpixel((x,y),(*rgb,round(max(0,alpha)*255)))
p=ROOT/'assets/props/cooking_pot_wait/steam_puff.png';im.save(p);print(p)
