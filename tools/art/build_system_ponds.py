#!/usr/bin/env python3
"""Bake immutable game locations, shared shore/navigation and water-distance art.

The published catalog is the authority: running this tool never moves existing
locations. A deliberate new layout requires a new template ID/revision.
"""
import hashlib
import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/ponds'
SEED = 'journey-system-ponds-20260924-v1'
CONTROLS = {
    'crescent': [(8.9,4.7),(9.8,6.3),(9.6,9.9),(8.6,11.7),(6.7,12.2),(4.2,11.7),(2.5,10.4),(2.3,8.8),(3.3,7.5),(4.8,7.4),(4.4,8.9),(5.9,9.5),(7.7,8.8),(7.8,6.7)],
    'gourd': [(4,3.8),(6.5,3.4),(7.7,4.6),(7.3,6.5),(7.9,7.6),(9.6,8.5),(9.7,10.8),(7.9,12),(4.8,12.2),(2.6,11.3),(2.2,9.4),(3.1,7.7),(4.4,6.6),(3.1,5.3)],
    'meander': [(3.2,3.6),(5.2,3.2),(8.6,4.8),(9.5,6.5),(8.3,7.7),(6,7.8),(5,9),(5.9,10.2),(8.2,10.8),(8.5,12.1),(6,12.7),(3.1,11.4),(2.1,9),(3.1,7.1),(5.8,6.6),(6.4,6),(4.9,5.3),(2.9,5)],
}
# Small curated generation envelopes. They describe game placement, not real ponds.
ZONES = {
    'los_angeles': [(34.1348,-118.2941),(34.0871,-118.2347),(34.1632,-118.3858),
                    (34.0619,-118.3590),(34.0188,-118.2867),(34.0719,-118.2481)],
    'shanghai': [(31.2145,121.5558),(31.3230,121.5520),(31.1435,121.3733),
                 (31.2244,121.4207),(31.2070,121.4348),(31.2803,121.4614)],
}

def smooth(points):
    out = []
    for i, b in enumerate(points):
        a, c, d = points[(i-1)%len(points)], points[(i+1)%len(points)], points[(i+2)%len(points)]
        for step in range(5):
            t = step/5
            p = [.5*((2*b[j])+(-a[j]+c[j])*t+(2*a[j]-5*b[j]+4*c[j]-d[j])*t*t+(-a[j]+3*b[j]-3*c[j]+d[j])*t*t*t) for j in range(2)]
            out.append([round(p[0],4), round(-p[1],4)])
    return out

def inside(poly, p):
    result = False
    for a,b in zip(poly, poly[1:]+poly[:1]):
        if (a[1]>p[1]) != (b[1]>p[1]) and p[0] < (b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]: result = not result
    return result

def distance(poly, p):
    best = float('inf')
    for a,b in zip(poly, poly[1:]+poly[:1]):
        dx,dy = b[0]-a[0],b[1]-a[1]
        t = max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy)))
        best = min(best, math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy))
    return best

def png(path, width, height, pixels):
    def chunk(kind, data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    raw=b''.join(b'\0'+pixels[y*width*4:(y+1)*width*4] for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))

def main():
    DEST.mkdir(exist_ok=True)
    prior = json.loads((DEST/'catalog.json').read_text()) if (DEST/'catalog.json').exists() else {}
    templates={}
    for key,controls in CONTROLS.items():
        poly=smooth(controls); cell=.25; rows=[]
        for y in range(64):
            row=''
            for x in range(48):
                p=((x+.5)*cell,-(y+.5)*cell)
                row += '1' if 3<=x<45 and 3<=y<61 and not inside(poly,p) and distance(poly,p)>cell*math.sqrt(2)/2+.10 else '0'
            rows.append(row)
        templates[key]={'id':key,'revision':1,'extent':[12,16],'polygon':poly,
                        'navigation':{'cell':cell,'rows':rows,'spawn':[6.125,-1.625]},
                        'fish_profile':'street_lake'}
        pixels=bytearray()
        for y in range(256):
            for x in range(192):
                p=((x+.5)/192*12,-(y+.5)/256*16)
                wet=inside(poly,p); d=distance(poly,p)
                pixels.extend([round(min(1,d/2)*255) if wet else 0,255 if wet else 0,0,255])
        png(DEST/(key+'_shore.png'),192,256,bytes(pixels))
        # A compact dimensional POI preview uses the exact same water outline.
        points=' '.join(f'{p[0]*20:.2f},{(16+p[1])*14:.2f}' for p in poly)
        svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<defs><linearGradient id="land" x2="0" y2="1"><stop stop-color="#c5dca8"/><stop offset="1" stop-color="#91b782"/></linearGradient><linearGradient id="water" x2="0.4" y2="1"><stop stop-color="#9bded2"/><stop offset="1" stop-color="#42a49c"/></linearGradient></defs>
<ellipse cx="128" cy="207" rx="103" ry="24" fill="#284b46" opacity=".16"/>
<g transform="translate(8 11)"><rect x="10" y="33" width="220" height="175" rx="65" fill="#71955f"/><rect x="10" y="24" width="220" height="175" rx="65" fill="url(#land)"/>
<polygon points="{points}" fill="url(#water)" stroke="#e2d7ad" stroke-width="6" stroke-linejoin="round"/>
<path d="M58 48l-3-19m8 20l3-17M187 170l-3-17m8 17l3-13" stroke="#64874d" stroke-width="4" stroke-linecap="round"/>
<ellipse cx="45" cy="167" rx="10" ry="6" fill="#cecbb6"/><ellipse cx="184" cy="43" rx="13" ry="8" fill="#e2ddbd"/>
<path d="M83 193q20-11 36-6" stroke="#e8dfbd" stroke-width="9" fill="none" stroke-linecap="round"/></g></svg>'''
        (DEST/(key+'.svg')).write_text(svg)
    locations=[]; names=['Willow','Clover','Fern','Pebble','Reed','Blossom']; types=list(CONTROLS)
    for region,zones in ZONES.items():
        for i,(lat,lng) in enumerate(zones):
            identity=f'pond_{region}_{i+1:02d}'
            digest=hashlib.sha256(f'{SEED}:{identity}'.encode()).digest()
            dy=(int.from_bytes(digest[:4],'big')/2**32-.5)*35
            dx=(int.from_bytes(digest[4:8],'big')/2**32-.5)*35
            # Seed-shuffled bags retain randomness while exposing all three shapes in each city.
            variants=sorted(types,key=lambda t:hashlib.sha256(f'{SEED}:{region}:{i//3}:{t}'.encode()).digest())
            locations.append({'id':identity,'region_id':region,'name':names[i]+' Pond','kind':'pond','category':'Fishing pond',
                              'lat':round(lat+dy/111320,7),'lng':round(lng+dx/(111320*math.cos(math.radians(lat))),7),
                              'template_id':variants[i%3],'decoration_seed':int.from_bytes(digest[9:13],'big'),
                              'layout_revision':1,'generation_version':1,'enabled':True})
    # Existing records are immutable across regeneration; new envelopes only append.
    existing={p['id']:p for p in prior.get('locations',[])}
    locations=[existing.pop(p['id'],p) for p in locations]+list(existing.values())
    for key,old in prior.get('templates',{}).items():
        if key in templates and templates[key] != old: raise ValueError(f'Publish a new template revision instead of changing {key}')
    catalog={'version':1,'world_seed':SEED,'room_capacity':16,'templates':templates,'locations':locations}
    (DEST/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'locations':len(locations),'templates':list(templates),'assignments':{r:[p['template_id'] for p in locations if p['region_id']==r] for r in ZONES}}))

if __name__ == '__main__': main()
