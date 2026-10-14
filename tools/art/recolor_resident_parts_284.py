#!/usr/bin/env python3
"""Reproducible NPC texture variants (Pillow + numpy). No image generation."""
from pathlib import Path
import json,shutil
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'assets/avatar/source'
OUT=ROOT/'tools/art/source/resident_parts_284'
def rgb(h):return np.array([int(h[i:i+2],16) for i in (0,2,4)],float)
def curve(pixels,mask,shadow,mid,light):
    lum=pixels[...,:3].astype(float)@np.array([.2126,.7152,.0722])
    q=np.percentile(lum[mask],[4,65,99.5]);q[1]=max(q[1],q[0]+1);q[2]=max(q[2],q[1]+1)
    colors=np.array([rgb(shadow),rgb(mid),rgb(light)])
    out=np.stack([np.interp(lum,q,colors[:,i]) for i in range(3)],axis=-1)
    return out,q.tolist()
def run():
    report={}
    granny=SRC/'hairhat80_npc_granny_wu';granny.mkdir(exist_ok=True)
    base=SRC/'hairhat80_npc_ama';shutil.copy2(base/'SM_hairHat80.fbx',granny/'SM_hairHat80.fbx')
    im=Image.open(base/'T_skin68_hairHat_D.png').convert('RGBA');p=np.array(im);r,g,b=p[:,:,:3].astype(float).transpose(2,0,1)
    pin=g>r+12;hair=~pin
    silver,qh=curve(p,hair,'B9B4AC','E4E0D8','F2EFE9')
    red,qp=curve(p,pin,'7A2A25','A63830','B8473D')
    # Green and brown are disjoint islands in the original; preserve alpha and
    # remap their luminance curves instead of painting out the strand shading.
    dst=p.copy();dst[:,:,:3]=np.uint8(np.rint(np.where(pin[:,:,None],red,silver)))
    Image.fromarray(dst).save(granny/'T_granny_wu_hairHat_D.png')
    report['granny']={'size':im.size,'hair_luminance_knots':qh,'pin_luminance_knots':qp,'alpha_exact':bool(np.array_equal(p[:,:,3],dst[:,:,3])),'hair_unique_colors':len(np.unique(dst[:,:,:3][hair],axis=0))}
    beard=SRC/'mask16_npc_ivo';beard.mkdir(exist_ok=True)
    im=Image.open(SRC/'mask16_npc_kai/T_skin34_mask_2_D.png').convert('RGBA');p=np.array(im)
    grey,q=curve(p,np.ones(p.shape[:2],bool),'7F7A73','A9A49C','BCB7AE');dst=p.copy();dst[:,:,:3]=np.uint8(np.rint(grey))
    Image.fromarray(dst).save(beard/'T_ivo_mask_D.png');report['beard']={'size':im.size,'luminance_knots':q,'alpha_exact':bool(np.array_equal(p[:,:,3],dst[:,:,3]))}
    hat=SRC/'hairhat_npc_ivo';hat.mkdir(exist_ok=True)
    im=Image.open(SRC/'hairhat51/T_skin40_hairHat_D.png').convert('RGBA');p=np.array(im);r,g,b=p[:,:,:3].astype(float).transpose(2,0,1)
    grey,q=curve(p,(r<135)&(r>g*1.15),'8C877F','B8B3AB','C9C5BD');hair=p.copy();hair[:,:,:3]=np.uint8(np.rint(grey))
    w,h=im.size;atlas=Image.new('RGBA',(w,h),'#C99A3AFF')
    atlas.paste(Image.fromarray(hair).resize((w//2,h//2),Image.Resampling.LANCZOS),(0,h//2))
    # Blender UV centres: cap (.75,.75), band (.875,.625), brass (.625,.25), lens (.875,.25).
    atlas.paste('#9E7628FF',(3*w//4,h//4,w,h//2))
    atlas.paste('#9B7B46FF',(w//2,h//2,3*w//4,h))
    atlas.paste('#F3E6C4FF',(3*w//4,h//2,w,h))
    atlas.save(hat/'T_ivo_hairHat_D.png');report['hat']={'size':im.size,'same_size_as':'hairhat51','hair_luminance_knots':q,'palette':{'cap':'C99A3A','band':'9E7628','brass':'9B7B46','lens':'F3E6C4','hair_mid':'B8B3AB'}}
    (OUT/'texture-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':run()
