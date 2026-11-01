#!/usr/bin/env python3
"""Pond-only art: RGB mineral bed + alpha optical depth / 2.5 metres.

Derived from unchanged published polygons. No locations, navigation or shared
farm textures are regenerated. Requires numpy/Pillow; fixed per-template seeds.
"""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/ponds/art'
OUT.mkdir(parents=True, exist_ok=True)

def smooth(a, b, value):
    t = np.clip((value - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

def bake_bed(name, spec, seed, out=OUT, deep_centre=0.0):
    rng = np.random.default_rng(seed)
    width, height = 768, 1024
    xx, zz = np.meshgrid((np.arange(width) + .5) / width * 12,
                         -(np.arange(height) + .5) / height * 16)
    poly = np.asarray(spec['polygon'])
    distance = np.full(xx.shape, 100.0)
    inside = np.zeros(xx.shape, dtype=bool)
    for a, b in zip(poly, np.roll(poly, -1, axis=0)):
        ab = b - a
        t = np.clip(((xx-a[0])*ab[0]+(zz-a[1])*ab[1])/np.dot(ab,ab), 0, 1)
        distance = np.minimum(distance, np.hypot(xx-a[0]-t*ab[0], zz-a[1]-t*ab[1]))
        if abs(ab[1]) > 1e-8:
            inside ^= ((a[1]>zz)!=(b[1]>zz)) & (xx<ab[0]*(zz-a[1])/ab[1]+a[0])
    # The reference has a sunny, broad foreground shelf and a deeper far basin.
    # Shore distance alone makes a mint ring with the same blue at both ends.
    # Keep a continuous slope while changing its width and depth along the pond.
    far = smooth(3.5, 11.9, -zz + (xx-6)*.18)
    depth = .055 + far*.15*smooth(.02,.45,distance)
    depth += (1-np.exp(-distance*(.75+far*1.65)))*(.55+far*1.75)
    depth *= 1 - .45*(1-smooth(.18,.40,far))
    depth += far*.65*(1-smooth(.25,1.2,distance))*smooth(.02,.20,distance)
    depth += np.sin(xx*.8+zz*.6)*np.sin(zz*.7)*.045*smooth(0,1,distance)
    # SGODOT-374 (P0 open water): extra depth from about 1 m off the bank, front or back, so the middle reads as a
    # lake rather than a channel; 0 keeps the bundled beds byte-identical.
    depth += deep_centre*smooth(.9,2.6,distance)
    grain = rng.random(xx.shape)
    bed = np.empty((*xx.shape, 3))
    bed[:] = np.array([.56,.64,.57])
    bed *= .93 + grain[...,None]*.10
    # Substantial stones in separate shallow clusters, leaving quiet sand between.
    candidates = np.argwhere(inside & (distance>.16) & (distance<1.18))
    centres = []
    for attempt in range(1100):
        iy, ix = candidates[rng.integers(len(candidates))]
        cx, cz = xx[iy,ix], zz[iy,ix]
        patch = np.sin(cx*1.6+cz*.75)+np.cos(cz*2.0-cx*.45)
        if patch<-.55 or rng.random()>.65: continue
        radius = rng.uniform(.11,.27)
        if any(np.hypot(cx-px,cz-pz)<(radius+pr)*.65 for px,pz,pr in centres): continue
        centres.append((cx,cz,radius))
        x0,x1 = max(0,ix-27),min(width,ix+28)
        y0,y1 = max(0,iy-27),min(height,iy+28)
        dx,dz = xx[y0:y1,x0:x1]-cx,zz[y0:y1,x0:x1]-cz
        angle = rng.uniform(0,np.pi)
        u = (dx*np.cos(angle)-dz*np.sin(angle))/radius
        v = (dx*np.sin(angle)+dz*np.cos(angle))/(radius*rng.uniform(.65,1.1))
        r = (np.abs(u)**2.7+np.abs(v)**2.7)**(1/2.7)
        r *= 1+.035*np.sin(np.arctan2(v,u)*5+angle)
        cover = 1-smooth(.87,1,r)
        shadow = (1-smooth(.8,1.25,np.hypot(u-.16,v-.20)))*.17
        local = bed[y0:y1,x0:x1]
        local *= 1-shadow[...,None]
        top = np.sqrt(np.clip(1-r**2,0,1))
        face = .76+top*.17+np.clip(-dx/radius*.15+dz/radius*.18,-.2,.2)
        face += (grain[y0:y1,x0:x1]-.5)*.028
        tone = np.array([.64,.73,.67])*rng.uniform(.88,1.13)
        local[:] = local*(1-cover[...,None])+tone*face[...,None]*cover[...,None]
        depth[y0:y1,x0:x1] -= top*cover*radius*.45
        if len(centres)>=165: break
    rgba = np.dstack((np.clip(bed,0,1),np.clip(depth/2.5,0,1)))
    Image.fromarray(np.uint8(np.round(rgba*255))).save(out/f'{name}_bed.png')
    print(f'{name}: {len(centres)} submerged stones; {width}x{height} RGB + depth')

def bake_caustics():
    # A periodic cellular light web. Runtime waves bend it in both directions.
    n = 768
    yy,xx = np.mgrid[:n,:n]/n*5
    xx = xx+.16*np.sin(yy*2.513)+.08*np.sin(yy*6.283)
    yy = yy+.15*np.sin(xx*2.513+.6)
    gen = np.random.default_rng(929)
    nearest = np.full((n,n),100.0)
    second = nearest.copy()
    for iy in range(5):
        for ix in range(5):
            px,py = np.array([ix,iy])+gen.uniform(.15,.85,2)
            dx,dy = (xx-px+2.5)%5-2.5,(yy-py+2.5)%5-2.5
            d = np.hypot(dx,dy)
            second = np.minimum(second,np.maximum(nearest,d))
            nearest = np.minimum(nearest,d)
    ridge = second-nearest
    # Broad falloff around each focus band survives dual-layer intersection;
    # the former thin edge network reduced min blending to isolated pinpoints.
    web = np.exp(-(ridge/.25)**2)*.56 + np.exp(-(ridge/.075)**2)*.30
    Image.fromarray(np.uint8(np.clip(web,0,1)*255)).filter(ImageFilter.GaussianBlur(.75)).save(OUT/'caustic_web.png')

def res_path(path):
    return ROOT/path.removeprefix('res://') if path.startswith('res://') else Path(path)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--templates', help='a template override (P0, SGODOT-374: res://assets/p0/p0_pond_templates.json); '
                        'each bed goes to its template\'s "art" folder; the caustic web is left alone')
    parser.add_argument('--deep-centre', type=float, default=0.0, help='extra depth (m) from ~1 m off the bank')
    args = parser.parse_args()
    catalog = json.loads((ROOT/'assets/ponds/catalog.json').read_text())
    if args.templates:
        override = json.loads(res_path(args.templates).read_text())['templates']
        # The seeds follow the catalog's sorted order, as the bundled beds' do.
        for index,(name,spec) in enumerate(sorted(catalog['templates'].items())):
            if name not in override: continue
            spec = {**spec, **override[name]}
            assert list(spec.get('extent', [12, 16])) == [12, 16], name
            out = res_path(spec.get('art', 'res://assets/ponds/art/'))
            out.mkdir(parents=True, exist_ok=True)
            bake_bed(name, spec, 29092026+index, out, args.deep_centre)
    else:
        for index,(name,spec) in enumerate(sorted(catalog['templates'].items())):
            bake_bed(name,spec,29092026+index, deep_centre=args.deep_centre)
        bake_caustics()
