#!/usr/bin/env python3
"""Recolor cloth1 in its unchanged UVs; run inspect_gabriel_423.py in Blender first."""
from pathlib import Path
import json,hashlib,shutil
import numpy as np
from PIL import Image,ImageFilter
R=Path(__file__).resolve().parents[2];S=R/'assets/avatar/source/cloth1';D=R/'assets/avatar/source/cloth1_npc_gabriel';D.mkdir(parents=True,exist_ok=True)
data=json.loads((R/'output/gabriel-423/cloth-uv.json').read_text());vertices=np.array(data['verts'])
a=np.array(Image.open(S/'T_skin01_cloth_D 1.png').convert('RGBA'));h,w=a.shape[:2]
positions=np.full((h,w,3),np.nan)
for ids,uv in zip(data['triangles'],data['uv']):
 p=np.array(uv)*[w,-h]+[0,h];lo=np.maximum(np.floor(p.min(0)).astype(int),0);hi=np.minimum(np.ceil(p.max(0)).astype(int),[w-1,h-1]);x0,y0=lo;x1,y1=hi
 xx,yy=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5);A,B,C=p
 den=(B[1]-C[1])*(A[0]-C[0])+(C[0]-B[0])*(A[1]-C[1])
 if abs(den)<1e-9:continue
 wa=((B[1]-C[1])*(xx-C[0])+(C[0]-B[0])*(yy-C[1]))/den;wb=((C[1]-A[1])*(xx-C[0])+(A[0]-C[0])*(yy-C[1]))/den;wc=1-wa-wb
 inside=(wa>=-1e-6)&(wb>=-1e-6)&(wc>=-1e-6);xyz=wa[...,None]*vertices[ids[0]]+wb[...,None]*vertices[ids[1]]+wc[...,None]*vertices[ids[2]]
 positions[y0:y1+1,x0:x1+1][inside]=xyz[inside]
rgb=a[:,:,:3].astype(float);luma=rgb@np.array([.2126,.7152,.0722]);shirt=(rgb[:,:,0]-rgb[:,:,2]>15)&(rgb[:,:,1]-rgb[:,:,2]>15);pants=(rgb.max(-1)<125)&~shirt
out=a.copy();out[:,:,:3]=[43,42,46]
for mask,knots,palette in [(shirt,[160,227,255],[[31,30,34],[43,42,46],[61,59,65]]),(pants,[55,64,95],[[29,28,32],[39,38,42],[56,54,60]])]:
 for c in range(3):out[:,:,c][mask]=np.rint(np.interp(luma[mask],knots,np.array(palette)[:,c]))
x,y,z=positions.transpose(2,0,1);trim=shirt & (((abs(x)>.260)&(z>.95)&(z<1.16))|((z>.677)&(z<.706))) | (pants & (z>.545)&(z<.561))
trim=np.array(Image.fromarray(trim.astype('uint8')*255).filter(ImageFilter.MaxFilter(5)))>0
out[trim,:3]=[57,55,61]
# Existing collar strip: narrow band around its raised neckline; pointed folds remain black.
yy,xx=np.mgrid[:h,:w];u=(xx+.5)/w;v=1-(yy+.5)/h
collar=(u>.793)&(u<.832)&(v<.374)&(v>.006)
# Soft one-pixel antialiasing, no extra texture or shader pass.
mask=Image.fromarray(collar.astype('uint8')*255).filter(ImageFilter.GaussianBlur(.55));m=np.array(mask)[...,None]/255
out[:,:,:3]=np.rint(out[:,:,:3]*(1-m)+np.array([244,241,232])*m)
Image.fromarray(out).save(D/'T_gabriel_cloth_D.png')
for src,dst in [('T_skin01_cloth_D 1.png','T_gabriel_cloth_D.png')]:
 side=D/(dst+'.import')
 if side.exists():continue
 params=(S/(src+'.import')).read_text().split('[params]',1)[1]
 scene=dst.endswith('.fbx')
 if not scene:params=params.replace('compress/mode=2','compress/mode=0')
 side.write_text('[remap]\nimporter="'+('scene' if scene else 'texture')+'"\ntype="'+('PackedScene' if scene else 'CompressedTexture2D')+'"\n\n[params]'+params)
Image.fromarray(np.dstack([np.array(mask),trim.astype('uint8')*255,np.zeros((h,w),dtype='uint8')])).save(R/'tools/art/source/gabriel_423/collar-trim-mask.png')
report={'base':'cloth1','id':'cloth1_npc_gabriel','source_size':[w,h],'near_black':'#2B2A2E','collar':'#F4F1E8','trim':'#39373D','alpha_exact':bool(np.array_equal(a[:,:,3],out[:,:,3])),'fbx_reference':'res://assets/avatar/source/cloth1/SK_dt_skin01.fbx','source_fbx_sha256':hashlib.sha256((S/'SK_dt_skin01.fbx').read_bytes()).hexdigest(),'sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in D.iterdir() if p.suffix!='.import'},'geometry_edits':0,'note':'Original cloth1 short sleeves and shorts retained. Collar mask follows the existing raised collar UV strip; no symbols, letters or extra geometry.'}
(R/'tools/art/source/gabriel_423/texture-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
