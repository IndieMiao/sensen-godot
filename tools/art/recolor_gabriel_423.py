#!/usr/bin/env python3
"""Texture-only cloth36 and hairhat0 variants; UV masks derived from unchanged donor geometry."""
from pathlib import Path
import io,json,hashlib,subprocess
import numpy as np
from PIL import Image,ImageFilter
R=Path(__file__).resolve().parents[2]
RUNTIME="8493a5c4258db3e59b2b845c83d3ee5b34724156"
D=R/'assets/avatar/source/cloth36_npc_gabriel';D.mkdir(parents=True,exist_ok=True)
data=json.loads((R/'output/gabriel-423/cloth-uv.json').read_text());vertices=np.array(data['verts'])
a=np.array(Image.open(io.BytesIO(subprocess.check_output(['git','show',RUNTIME+':assets/avatar/source/cloth36_npc_sigrid/T_skin36_cloth_D.png'],cwd=R))).convert('RGBA'));h,w=a.shape[:2]
positions=np.full((h,w,3),np.nan)
for ids,uv in zip(data['triangles'],data['uv']):
 p=np.array(uv)*[w,-h]+[0,h];lo=np.maximum(np.floor(p.min(0)).astype(int),0);hi=np.minimum(np.ceil(p.max(0)).astype(int),[w-1,h-1]);x0,y0=lo;x1,y1=hi
 xx,yy=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5);A,B,C=p
 den=(B[1]-C[1])*(A[0]-C[0])+(C[0]-B[0])*(A[1]-C[1])
 if abs(den)<1e-9:continue
 wa=((B[1]-C[1])*(xx-C[0])+(C[0]-B[0])*(yy-C[1]))/den;wb=((C[1]-A[1])*(xx-C[0])+(A[0]-C[0])*(yy-C[1]))/den;wc=1-wa-wb
 inside=(wa>=-1e-6)&(wb>=-1e-6)&(wc>=-1e-6);xyz=wa[...,None]*vertices[ids[0]]+wb[...,None]*vertices[ids[1]]+wc[...,None]*vertices[ids[2]]
 positions[y0:y1+1,x0:x1+1][inside]=xyz[inside]
rgb=a[:,:,:3].astype(float);luma=rgb@np.array([.2126,.7152,.0722])
blue=(rgb[:,:,2]>rgb[:,:,0]*1.15)&(rgb[:,:,2]>rgb[:,:,1]*1.1)
out=a.copy();out[:,:,:3]=[43,42,46]
# Preserve painted folds in the blue coat/trousers. Neutralize former shirt/tie/brass detail.
for c,base in enumerate([43,42,46]):
 out[:,:,c][blue]=np.rint(np.clip(base+(luma[blue]-54)*.38,26,64))
nonblue=~blue
for c,base in enumerate([40,39,43]):
 out[:,:,c][nonblue]=np.rint(base+(luma[nonblue]-128)*.025)
x,y,z=positions.transpose(2,0,1)
trim=((abs(x)>.413)&(z>1.07))|((z>.665)&(z<.687)&(abs(x)<.21))|((z>.104)&(z<.124))
trim=np.array(Image.fromarray(trim.astype('uint8')*255).filter(ImageFilter.MaxFilter(5)))>0
out[trim,:3]=[57,55,61]
collar=(abs(x)<.068)&((z>1.176)&(z<1.198))
mask=Image.fromarray(collar.astype('uint8')*255).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(.55));m=np.array(mask)[...,None]/255
out[:,:,:3]=np.rint(out[:,:,:3]*(1-m)+np.array([244,241,232])*m)
Image.fromarray(out).save(D/'T_gabriel_cloth_D.png')
H=R/'assets/avatar/source/hairhat0_npc_gabriel';H.mkdir(exist_ok=True)
hair=np.array(Image.open(R/'assets/avatar/source/hairhat0/T_base_boy_hairHat_D.png').convert('RGBA'));hl=hair[:,:,:3]@np.array([.2126,.7152,.0722]);ho=hair.copy()
for c,base in enumerate([231,229,223]):ho[:,:,c]=np.rint(np.clip(base+(hl-205)*.72,105,248))
Image.fromarray(ho).save(H/'T_gabriel_hairHat_D.png')
for folder,name,params in [(D,'T_gabriel_cloth_D.png',subprocess.check_output(['git','show',RUNTIME+':assets/avatar/source/cloth36_npc_sigrid/T_skin36_cloth_D.png.import'],cwd=R,text=True)),(H,'T_gabriel_hairHat_D.png',(R/'assets/avatar/source/hairhat0/T_base_boy_hairHat_D.png.import').read_text())]:
 side=folder/(name+'.import')
 if not side.exists():side.write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]'+params.split('[params]',1)[1])
Image.fromarray(np.dstack([np.array(mask),trim.astype('uint8')*255,np.zeros((h,w),dtype='uint8')])).save(R/'tools/art/source/gabriel_423/collar-trim-mask.png')
report={'revision':'v1.1','base':'cloth36_npc_sigrid / cloth36','id':'cloth36_npc_gabriel','source_size':[w,h],'near_black':'#2B2A2E','collar':'#F4F1E8','trim':'#39373D','alpha_exact':bool(np.array_equal(a[:,:,3],out[:,:,3])),'hair_alpha_exact':bool(np.array_equal(hair[:,:,3],ho[:,:,3])),'source_fbx_sha256':hashlib.sha256((D/'SK_dt_skin36.fbx').read_bytes()).hexdigest(),'geometry_edits':0,'note':'cloth36 geometry/rig unchanged, FBX source texture links repointed; long sleeves and trousers. Existing glass0; neutral warm-white hairhat0 texture variant. No added geometry or symbols.'}
(R/'tools/art/source/gabriel_423/texture-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
