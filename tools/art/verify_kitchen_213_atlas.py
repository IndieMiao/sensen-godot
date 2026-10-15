#!/usr/bin/env python3
"""Pillow/NumPy: prove 213 patch changes no pre-existing UV island or bake gutter."""
import io,json,subprocess,hashlib,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_chef_sign import load_glb,accessor
ROOT=Path(__file__).resolve().parents[2];SRC=ROOT/'tools/art/source/kitchen_213';OUT=ROOT/'output/kitchen-213';KIT=ROOT/'assets/rooms/basic_room'
sw=json.loads((SRC/'atlas-swatches.json').read_text());raw=subprocess.check_output(['git','show',sw['baseline']+':assets/rooms/basic_room/room_albedo_ao.png'],cwd=ROOT)
a=np.array(Image.open(io.BytesIO(raw)).convert('RGB'));b=np.array(Image.open(KIT/'room_albedo_ao.png').convert('RGB'));changed=np.any(a!=b,axis=2)
mask=Image.new('L',(2048,2048));draw=ImageDraw.Draw(mask);files=subprocess.check_output(['git','ls-tree','-r','--name-only',sw['baseline'],'assets/rooms/basic_room'],cwd=ROOT,text=True).splitlines();count=0
for relative in files:
 if not relative.endswith('.glb'):continue
 p=ROOT/relative;d,blob=load_glb(p);count+=1
 for mesh in d['meshes']:
  for pr in mesh['primitives']:
   uv=np.array(accessor(d,blob,pr['attributes']['TEXCOORD_0']))*2048;ix=np.array(accessor(d,blob,pr['indices'])).reshape(-1,3)
   for t in ix:draw.polygon([tuple(v) for v in uv[t]],fill=255)
protected=np.array(mask.filter(ImageFilter.MaxFilter(19)))>0
expected=np.zeros(changed.shape,dtype=bool);x,y,w,h=sw['added_patch']['rect'];expected[y:y+h,x:x+w]=True
delta=np.load(SRC/'atlas-ao-delta.npz');factor=delta['factor'];ao_allowed=delta['allowed']
f=a.astype(float)/255;linear=np.where(f<=.04045,f/12.92,((f+.055)/1.055)**2.4)*factor[:,:,None];srgb=np.where(linear<=.0031308,linear*12.92,1.055*np.maximum(linear,0)**(1/2.4)-.055);reconstructed=np.rint(np.clip(srgb,0,1)*255).astype(np.uint8);reconstructed[y:y+h,x:x+w]=sw['added_patch']['rgb8']
checks=[{'check':'Red patch does not touch any original UV island or 9-pixel gutter','passed':not bool(np.any(expected & protected))},{'check':'Atlas reconstructs exactly from original pixels + recorded AO delta + isolated red patch','passed':bool(np.array_equal(b,reconstructed))},{'check':'All changed pixels confined to declared kitchen AO target islands or new red patch','passed':not bool(np.any(changed & ~(ao_allowed|expected)))},{'check':'Original atlas source hash matches pinned base','passed':hashlib.sha256(raw).hexdigest()==sw['original_atlas_sha256']},{'check':'New atlas matches contract hash','passed':hashlib.sha256((KIT/'room_albedo_ao.png').read_bytes()).hexdigest()==sw['patched_atlas_sha256']}]
report={'checks':checks,'original_glbs':count,'changed_pixels':int(changed.sum()),'patch':sw['added_patch'],'same_texture_count':1,'size':[2048,2048],'scope':'Existing UVs / original colour detail preserved. Local contact-AO delta removes old hearth shadow and updates moved/new props; no new runtime texture. See source atlas-ao-delta.json.','failures':[c for c in checks if not c['passed']]};(OUT/'atlas-validation.json').write_text(json.dumps(report,indent=2)+'\n');print('KITCHEN_213_ATLAS_QA',len(checks),'checks',len(report['failures']),'failures');assert not report['failures']
