#!/usr/bin/env python3
"""Read-only ownership audit and flat UV projection of the tavern back wall."""
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from verify_chef_sign import load_glb, accessor

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / 'assets/rooms/tavern'
OUT = ROOT / 'output/npc-batch3/tavern'
OUT.mkdir(parents=True, exist_ok=True)
atlas = Image.open(KIT / 'room_albedo_ao.png').convert('RGB')
pixels = np.asarray(atlas)
ownership = {}
for path in KIT.glob('*.glb'):
    doc, binary = load_glb(path)
    mask = Image.new('L', atlas.size)
    draw = ImageDraw.Draw(mask)
    for mesh in doc['meshes']:
        for prim in mesh['primitives']:
            if 'TEXCOORD_0' not in prim['attributes']: continue
            uv = np.array(accessor(doc, binary, prim['attributes']['TEXCOORD_0']))
            ids = np.array(accessor(doc, binary, prim['indices'])).ravel().reshape(-1,3)
            for face in ids:
                draw.polygon([tuple(p) for p in uv[face] * atlas.size], fill=255)
    ownership[path.stem] = np.array(mask) > 0
wall = ownership.pop('back_wall')
other = np.logical_or.reduce(list(ownership.values()))
doc, binary = load_glb(KIT / 'back_wall.glb')
prim = doc['meshes'][0]['primitives'][0]
xyz = np.array(accessor(doc,binary,prim['attributes']['POSITION']))
uv = np.array(accessor(doc,binary,prim['attributes']['TEXCOORD_0']))
ids = np.array(accessor(doc,binary,prim['indices'])).ravel().reshape(-1,3)
def uv_key(triangle):
    return tuple(sorted(tuple(round(float(x),6) for x in point) for point in triangle))
wall_triangles = {uv_key(uv[face]) for face in ids}
batch_reports = []
layout = json.loads((KIT / 'layout.json').read_text())
for batch in layout.get('render_batches',[]):
    if batch['material'] != 'room': continue  # shared plants use a different atlas
    path = ROOT / batch['file'].removeprefix('res://')
    bd, bb = load_glb(path)
    mask = Image.new('L',atlas.size); draw = ImageDraw.Draw(mask); copies = 0
    for bm in bd['meshes']:
        for bp in bm['primitives']:
            buv = np.array(accessor(bd,bb,bp['attributes']['TEXCOORD_0']))
            bi = np.array(accessor(bd,bb,bp['indices'])).ravel().reshape(-1,3)
            for face in bi:
                if 'back_wall' in batch['sources'] and uv_key(buv[face]) in wall_triangles:
                    copies += 1
                else: draw.polygon([tuple(p) for p in buv[face]*atlas.size],fill=255)
    other |= np.array(mask)>0
    batch_reports.append({'batch':batch['name'],'same_back_wall_triangles':copies})
    if 'back_wall' in batch['sources']: assert copies == len(ids)
exclusive = wall & ~other
Image.fromarray((exclusive * 255).astype(np.uint8)).save(OUT / 'back-wall-exclusive.png')
Image.fromarray((other * 255).astype(np.uint8)).save(OUT / 'other-assets-uv.png')
guarded = Image.fromarray((other*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(17))
Image.fromarray(((wall & ~(np.array(guarded)>0))*255).astype(np.uint8)).save(OUT/'back-wall-safe-8px.png')
size = (1400,700)
image = np.full((size[1],size[0],3), 240, dtype=np.uint8)
depth = np.full(image.shape[:2], -np.inf)
uv_pixels = np.full((*image.shape[:2],2), -1.0)
# A texture inspection projection, deliberately separate from game review renders.
xy = xyz[:, :2] * [size[0]/3.2,-size[1]/1.6] + [size[0]/2,size[1]*3.75/1.6]
for face in ids:
    p = xy[face]
    x0,y0 = np.maximum(np.floor(p.min(axis=0)).astype(int),0)
    x1,y1 = np.minimum(np.ceil(p.max(axis=0)).astype(int),[size[0]-1,size[1]-1])
    if x1 < x0 or y1 < y0: continue
    xx,yy = np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5)
    a,b,c = p
    den = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
    if abs(den) < 1e-7: continue
    wa = ((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
    wb = ((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den
    wc = 1-wa-wb
    z = wa*xyz[face[0],2]+wb*xyz[face[1],2]+wc*xyz[face[2],2]
    view = depth[y0:y1+1,x0:x1+1]
    inside = (wa>=0)&(wb>=0)&(wc>=0)&(z>view)
    mapped = wa[...,None]*uv[face[0]]+wb[...,None]*uv[face[1]]+wc[...,None]*uv[face[2]]
    texels = np.clip((mapped*atlas.size).astype(int),0,np.array(atlas.size)-1)
    image[y0:y1+1,x0:x1+1][inside] = pixels[texels[...,1],texels[...,0]][inside]
    uv_pixels[y0:y1+1,x0:x1+1][inside] = mapped[inside]
    view[inside] = z[inside]
Image.fromarray(image).save(OUT/'back-wall-flat-inspection.png')
np.savez_compressed(OUT/'back-wall-projection.npz',uv=uv_pixels,depth=depth)
(OUT/'uv-ownership.json').write_text(json.dumps({
    'glb_files_scanned':len(ownership)+1,
    'back_wall_covered_pixels':int(wall.sum()),
    'back_wall_exclusive_pixels':int(exclusive.sum()),
    'back_wall_overlap_with_other_pixels':int((wall&other).sum()),
    'bounds': [xyz.min(axis=0).tolist(),xyz.max(axis=0).tolist()],
    'projection_world_xy':[-1.6,2.15,1.6,3.75],
    'glb_embedded_images':doc.get('images',[]),
    'batches':batch_reports,
},indent=2)+'\n')
print('TAVERN_UV',int(wall.sum()),'covered;',int(exclusive.sum()),'exclusive;',int((wall&other).sum()),'overlap')
