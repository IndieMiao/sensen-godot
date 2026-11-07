from pathlib import Path
import json,subprocess,io
import numpy as np
from PIL import Image,ImageFilter
R=Path.cwd();D=R/'assets/avatar/source/cloth36_npc_gabriel/T_gabriel_cloth_D.png';base=subprocess.check_output(['git','show','ccd6e7f0:assets/avatar/source/cloth36_npc_gabriel/T_gabriel_cloth_D.png']);a=np.array(Image.open(io.BytesIO(base)).convert('RGBA'));h,w=a.shape[:2]
data=json.loads((R/'output/gabriel-423/cloth-uv.json').read_text());vs=np.array(data['verts']);tri=np.array(data['triangles']);uvs=np.array(data['uv'])
P=np.full((h,w,3),np.nan);part=np.full((h,w),-1,dtype=int)
parent=list(range(len(vs)))
def find(v):
 while parent[v]!=v:v=parent[v]
 return v
for face in tri:
 for vertex in face[1:]:parent[find(vertex)]=find(face[0])
which={i:find(i) for i in range(len(vs))}
for ids,uv in zip(tri,uvs):
 p=uv*[w,-h]+[0,h];lo=np.maximum(np.floor(p.min(0)).astype(int),0);hi=np.minimum(np.ceil(p.max(0)).astype(int),[w-1,h-1]);x0,y0=lo;x1,y1=hi
 xx,yy=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5);A,B,C=p;den=(B[1]-C[1])*(A[0]-C[0])+(C[0]-B[0])*(A[1]-C[1])
 if abs(den)<1e-9:continue
 wa=((B[1]-C[1])*(xx-C[0])+(C[0]-B[0])*(yy-C[1]))/den;wb=((C[1]-A[1])*(xx-C[0])+(A[0]-C[0])*(yy-C[1]))/den;wc=1-wa-wb
 inside=(wa>=-1e-6)&(wb>=-1e-6)&(wc>=-1e-6);xyz=wa[...,None]*vs[ids[0]]+wb[...,None]*vs[ids[1]]+wc[...,None]*vs[ids[2]]
 P[y0:y1+1,x0:x1+1][inside]=xyz[inside];part[y0:y1+1,x0:x1+1][inside]=which[ids[0]]
x,y,z=P.transpose(2,0,1)
out=a.copy()
# Paint out the source tie/waistcoat/chest panel motifs using one continuous black field.
yy,xx=np.mgrid[:h,:w]
# Existing independent UV islands: waistcoat, shirt/collar, tie knot and tie blade.
vest=(xx>675)&(xx<807)&(yy>580)&(yy<840)
shirt=(xx>845)&(yy>582)&(yy<884)
details=np.isin(part,[143,94,167,1565,1582,1599,707])
mask=np.array(Image.fromarray((vest|shirt|details).astype('uint8')*255).filter(ImageFilter.MaxFilter(5)))/255
out[:,:,:3]=np.rint(out[:,:,:3]*(1-mask[...,None])+np.array([43,42,46])*mask[...,None])
# Erase separate tie color; pad these isolated UV islands with the same black.
# Geometry, alpha and runtime shader remain unchanged.
for ids,color in [([143],[43,42,46]),([94],[43,42,46])]:
 detail=np.array(Image.fromarray(np.isin(part,ids).astype('uint8')*255).filter(ImageFilter.MaxFilter(3)))/255
 out[:,:,:3]=np.rint(out[:,:,:3]*(1-detail[...,None])+np.array(color)*detail[...,None])
# Retain the white band behind the neck, connect a 25 mm wide front tab below the throat.
band=(abs(x)<.068)&(z>1.176)&(z<1.198)
tab=(abs(x)<.0125)&(y<0)&(z>1.151)&(z<1.183)
white=Image.fromarray((band|tab).astype('uint8')*255).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(.55));m=np.array(white)/255
out[:,:,:3]=np.rint(out[:,:,:3]*(1-m[...,None])+np.array([244,241,232])*m[...,None])
Image.fromarray(out).save(D)
np.savez(R/'output/gabriel-423/collar-raster.npz',positions=P,part=part)
Image.fromarray(np.dstack([np.array(white),(mask*255).astype('uint8'),np.zeros((h,w),dtype='uint8')])).save(R/'output/gabriel-423/collar-v12-mask.png')
print('changed pixels',int(np.any(out!=a,axis=-1).sum()),'alpha preserved',np.array_equal(a[:,:,3],out[:,:,3]))
