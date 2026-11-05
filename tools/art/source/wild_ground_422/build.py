"""Deterministic painted ground maps, in Godot world X/Z metres. No AI/photo inputs.

RGB = deep meadow / sunlit meadow / sand-and-bare-earth weights; A = flat pebbles.
The ordinary meadow is the residual colour. Layout maps NEVER repeat.
"""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[3]
DEST = ROOT / 'assets/ponds/ground'
SIZE = 1024
ORIGIN = (-4., -20.)
EXTENT = (20., 24.)
PALETTE = {'ordinary': [.35, .455, .15], 'deep': [.235, .35, .105],
           'sunlit': [.49, .555, .235], 'soil': [.65, .54, .355],
           'pebble': [.72, .67, .53]}

def smooth(a, b, v):
    t = np.clip((v-a)/(b-a), 0, 1)
    return t*t*(3-2*t)

def field(seed, scale):
    rng = np.random.default_rng(seed)
    n = gaussian_filter(rng.normal(size=(SIZE, SIZE)).astype(np.float32), scale)
    return n / max(float(n.std()), .00001)

def world_grid():
    x = ORIGIN[0] + (np.arange(SIZE, dtype=np.float32)+.5) * EXTENT[0]/SIZE
    z = ORIGIN[1] + (np.arange(SIZE, dtype=np.float32)+.5) * EXTENT[1]/SIZE
    return np.meshgrid(x, z)

def sample(a, x, z):
    ix = np.clip(((x-ORIGIN[0])/EXTENT[0]*SIZE).astype(int), 0, SIZE-1)
    iz = np.clip(((z-ORIGIN[1])/EXTENT[1]*SIZE).astype(int), 0, SIZE-1)
    return a[iz, ix]

def tile():
    """Soft little leaf strokes, wrapped at every edge, without large tile landmarks."""
    rng = np.random.default_rng(42211)
    image = Image.new('RGB', (SIZE, SIZE), (165, 184, 111))
    draw = ImageDraw.Draw(image)
    for _ in range(22000):
        x, y = rng.uniform(0, SIZE, 2)
        rx, ry = rng.uniform(2, 6), rng.uniform(3, 12)
        light = int(rng.integers(-16, 17))
        color = tuple(int(np.clip(c+light, 0, 255)) for c in (165, 184, 111))
        for dx in (-SIZE, 0, SIZE):
            for dy in (-SIZE, 0, SIZE):
                if -14 < x+dx < SIZE+14 and -14 < y+dy < SIZE+14:
                    draw.ellipse((x+dx-rx,y+dy-ry,x+dx+rx,y+dy+ry),fill=color)
    a = np.asarray(image).astype(np.float32)
    n = gaussian_filter(rng.normal(size=(SIZE,SIZE)), 8, mode='wrap')
    n /= n.std()
    a += n[...,None]*1.8
    # Matching border texels also make conventional texture viewers show a clean seam.
    a[-1,:,:] = a[0,:,:]
    a[:,-1,:] = a[:,0,:]
    Image.fromarray(np.uint8(np.clip(a,0,255))).save(DEST/'meadow_color.png')

def build():
    DEST.mkdir(parents=True, exist_ok=True)
    tile()
    slots = json.loads((SRC/'reference/pond_slots_v2.json').read_text())['shapes']
    templates = json.loads((SRC/'reference/p0_pond_templates.json').read_text())['templates']
    x,z = world_grid()
    # Metre-scale domains are warped before evaluation, so the large patches have
    # scalloped irregular edges without a visible noise-cell lattice.
    warp = field(4221,19)*.26
    fine = field(4222,3)*.055
    xx = x + warp + .23*np.sin(z*1.13 + x*.47)
    zz = z + field(4223,17)*.22
    broad = field(4224,45)
    deep = smooth(.20,.66, broad + .26*np.sin(xx*1.52+zz*.73) + fine*1.8)*.84
    sun = smooth(.05,.66, -broad + .32*np.cos(zz*1.07-xx*.9) + fine*1.5)*.78
    # Foreground composition: quiet ordinary grass, deep green islands and warm
    # sun patches; retain the same material hierarchy on the distant banks.
    for cx,cz,rx,rz in [(3.1,1.0,1.0,1.6),(9.1,.5,.85,1.2),(4.8,-2.4,.8,.7),
                        (10.6,-5.1,.7,1.5),(1.4,-9.8,.6,1.2),(6.1,-16.6,1.6,.6)]:
        oval=((xx-cx)/rx)**2+((zz-cz)/rz)**2
        patch=(1-smooth(.5,1.2,oval+fine*2))*.84
        deep=np.maximum(deep,patch)
        sun*=1-patch
    grass_sum = np.maximum(1,deep+sun)
    deep/=grass_sum;sun/=grass_sum
    # Fade macro layout at its extent; the repeated fine grass supplies the large
    # original 256m backdrop without extending a road beyond the game bounds.
    domain = smooth(0,1.2,np.minimum.reduce([x-ORIGIN[0],ORIGIN[0]+EXTENT[0]-x,
                                           z-ORIGIN[1],ORIGIN[1]+EXTENT[1]-z]))
    deep*=domain;sun*=domain
    manifest={'version':1,'task':'SGODOT-422','seed':422,'world_origin_xz':ORIGIN,
        'world_extent_xz':EXTENT,'map_size':[SIZE,SIZE],
        'uv':'(world.xz - vec2(-4,-20)) / vec2(20,24); top PNG row is z=-20',
        'channels':{'r':'deep grass weight','g':'sunlit grass weight',
                    'b':'path / bare earth weight','a':'painted flat pebble coverage'},
        'palette_linear':PALETTE,'detail_tile_metres':4.8,'pebble_geometry_height_m':0,
        'slot_source_sha256':hashlib.sha256((SRC/'reference/pond_slots_v2.json').read_bytes()).hexdigest(),
        'templates_source_sha256':hashlib.sha256((SRC/'reference/p0_pond_templates.json').read_bytes()).hexdigest(),
        'shapes':{}}
    for shape,t in templates.items():
        nav=np.array([[c=='1' for c in row] for row in t['navigation']['rows']])
        cell=t['navigation']['cell']
        ix=np.floor(x/cell).astype(int);iz=np.floor(-z/cell).astype(int)
        in_rect=(ix>=0)&(ix<nav.shape[1])&(iz>=0)&(iz<nav.shape[0])
        walk=in_rect & nav[np.clip(iz,0,nav.shape[0]-1),np.clip(ix,0,nav.shape[1]-1)]
        nav_dist=distance_transform_edt(walk,sampling=(EXTENT[1]/SIZE,EXTENT[0]/SIZE))
        nav_safe=smooth(.20,.56,nav_dist)
        water_image=Image.new('L',(SIZE,SIZE))
        points=[((p[0]-ORIGIN[0])/EXTENT[0]*SIZE,(p[1]-ORIGIN[1])/EXTENT[1]*SIZE) for p in t['polygon']]
        ImageDraw.Draw(water_image).polygon(points,fill=255)
        water=np.array(water_image)>0
        shore_dist=distance_transform_edt(~water,sampling=(EXTENT[1]/SIZE,EXTENT[0]/SIZE))
        shore_safe=smooth(.43,.78,shore_dist)
        slot_safe=np.ones_like(x); decor_safe=np.ones_like(x); stand_safe=np.ones_like(x)
        for s in slots[shape].values():
            # A 1.5m square footprint plus a .15m buffer; path also avoids the
            # gathering stand. Scattered dirt and stones use the wider 1.5m radius.
            box=np.maximum(abs(x-s['x']),abs(z-s['z']))
            slot_safe*=smooth(.90,1.12,box)
            decor_safe*=smooth(1.5,1.75,np.hypot(x-s['x'],z-s['z']))
            stand_safe*=smooth(.30,.46,np.hypot(x-s['stand'][0],z-s['stand'][1]))
        # The path bends through the unchanged spawn and ends naturally at the
        # reachable shore; there is no painted invitation into unwalkable space.
        centre=6.125+.38*np.sin((z+1.625)*3.1)
        radius=.43+.065*np.sin(z*5.4)
        path=(1-smooth(radius-.10,radius+.18,abs(x-centre)+fine))
        path*=smooth(-4.45,-4.0,z)*(1-smooth(-1.12,-.92,z))
        path*=nav_safe*shore_safe*slot_safe*stand_safe
        dirt=np.zeros_like(x)
        for cx,cz,rx,rz in [(2.2,-1.8,.42,.28),(9.3,-1.1,.36,.28),
                            (1.1,-4.9,.30,.46),(10.9,-5.6,.36,.52),
                            (1.1,-11.5,.36,.40),(10.6,-11.8,.40,.45),
                            (3.0,-15.0,.45,.35),(8.9,-15.0,.48,.33)]:
            oval=((xx-cx)/rx)**2+((zz-cz)/rz)**2
            dirt=np.maximum(dirt,(1-smooth(.35,1.25,oval+fine*2))*.83)
        dirt*=nav_safe*shore_safe*decor_safe*stand_safe
        soil=np.maximum(path,dirt)
        pebble=np.zeros_like(x)
        rng=np.random.default_rng(42240+list(templates).index(shape))
        placed=[]
        for _ in range(12000):
            px=float(rng.uniform(.85,11.15));pz=float(rng.uniform(-15.1,-1.05))
            sx=np.array(px);sz=np.array(pz)
            if sample(soil,sx,sz)<.48 or sample(decor_safe,sx,sz)<.98:continue
            if any(np.hypot(px-a,pz-b)<.48 for a,b,*_ in placed):continue
            rx=float(rng.uniform(.035,.065));rz=float(rng.uniform(.025,.045))
            dist=((x-px)/rx)**2+((z-pz)/rz)**2
            ink=(1-smooth(.58,1.06,dist))*(.86+.10*np.clip((z-pz)/rz,-1,1))
            pebble=np.maximum(pebble,ink*soil)
            placed.append([px,pz,rx,rz])
            if len(placed)>=30:break
        mask=np.stack([deep,sun,soil,pebble],axis=-1)
        name=f'{shape}_layout.png'
        Image.fromarray(np.uint8(np.round(np.clip(mask,0,1)*255))).save(DEST/name)
        manifest['shapes'][shape]={'layout':name,'pebbles_xz_radii':placed,
            'soil_max_outside_walk':float(soil[~walk].max()),
            'soil_pixels':int((soil>.1).sum()),'path_ends_before_boundary_m':.20,
            'resource_footprint_half_m':.90,'gather_stand_clear_m':.30,
            'scattered_dirt_pebble_resource_clear_m':1.5}
    manifest['files']={p.name:{'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
                             'bytes':p.stat().st_size} for p in sorted(DEST.glob('*.png'))}
    (DEST/'ground_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({k:len(v['pebbles_xz_radii']) for k,v in manifest['shapes'].items()}))

if __name__=='__main__':build()
