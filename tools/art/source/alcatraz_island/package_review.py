"""Archive reviewed captures, add a clearly identified top-view annotation layer."""
from pathlib import Path
import json
import hashlib
import shutil
import struct
import re
import ast
from PIL import Image, ImageDraw, ImageFont

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
REVIEW=ROOT/'output/alcatraz-424/review'
DOC=ROOT/'docs/design/alcatraz-blockout-424-2026-11-05'
ASSETS=ROOT/'assets/landmarks/alcatraz_island'
QA=ROOT/'output/alcatraz-424/project'
verification=json.loads((REVIEW/'verification.json').read_text())
assert verification['status']=='pass',verification['failures']
DOC.mkdir(parents=True,exist_ok=True);(DOC/'.gdignore').touch()
for p in REVIEW.glob('*.png'):shutil.copy2(p,DOC/p.name)
shutil.copy2(REVIEW/'verification.json',DOC/'verification.json')
layout=json.loads((ASSETS/'layout.json').read_text())
manifest=json.loads((ASSETS/'manifest.json').read_text())
font='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
f=ImageFont.truetype(font,18);small=ImageFont.truetype(font,15)
im=Image.open(REVIEW/'04-top-layout.png').convert('RGB');d=ImageDraw.Draw(im)
def point(v):return (500+v[0]*1000/27,600+(v[2]-1)*1000/27)
route=[point(v) for v in layout['route']]
walk_path=[]
for i in range(1,len(layout['route'])):
    walk_path.extend(point(v) for v in ast.literal_eval(verification['route_%d_path'%i]['evidence']))
d.line(walk_path,fill='#306581',width=4)
for i in [0,4,8]:
    x,y=route[i];d.ellipse((x-8,y-8,x+8,y+8),fill='#306581',outline='white',width=2)
def label(text,xy,target=None):
    if target:d.line([xy,target],fill='#263b44',width=2)
    b=d.textbbox(xy,text,font=f)
    d.rounded_rectangle((b[0]-5,b[1]-4,b[2]+5,b[3]+4),radius=4,fill='#f4f3ec')
    d.text(xy,text,font=f,fill='#263b44')
label('ALCATRAZ / B / BLOCKOUT 01',(22,18))
d.text((22,48),'Rendered top view + annotation layer. Metres; north is up.',font=small,fill='#263b44')
label('Visitor centre',(420,118),point([0,5.6,-10.2]))
label('Lighthouse',(22,180),point([-7,5.6,-9]))
label('Water tower',(800,180),point([7,5.6,-10.5]))
label('03  Summit +5.6 m',(22,305),route[8])
label('02  Mid-hill +2.4 m',(22,720),route[4])
label('Garden / no navigation',(20,550),point([-5,2.4,2]))
label('Ruins',(800,620),point([2.2,2.4,3.5]))
label('Scenic bridge',(800,790),point([8,.1,4.8]))
label('01  Dock +0.8 m',(800,1050),route[0])
label('Ferry / decorative',(22,1060),point([3.3,.2,13.9]))
label('Map exit',(660,1145),point(layout['exit']))
d.text((22,1163),'Nav extent 17.5 x 22.5 m | 3 flights x 1.6 m | edge clearance 0.25 m',font=small,fill='#263b44')
im.save(DOC/'04-top-layout.png')

checks=[];hashes={}
for name in manifest['assets']:
    p=ASSETS/(name+'.glb');b=p.read_bytes()
    size,kind=struct.unpack_from('<II',b,12);g=json.loads(b[20:20+size])
    primitives=[v for m in g['meshes'] for v in m['primitives']]
    assert len(g['meshes'])==1 and len(primitives)==1,name
    assert all('COLOR_0' in v['attributes'] and 'NORMAL' in v['attributes'] for v in primitives),name
    assert re.search(r'uid="uid://[a-y0-8]+"',(ASSETS/(name+'.glb.import')).read_text()),name
    assert b==(QA/'assets/landmarks/alcatraz_island'/p.name).read_bytes(),name
    hashes[p.name]=hashlib.sha256(b).hexdigest()
    checks.append(name)
for name in ['alcatraz_island.gd','alcatraz_island.tscn']:
    assert (ROOT/'scenes/landmark'/name).read_bytes()==(QA/'scenes/landmark'/name).read_bytes(),name
assert sum(1 for p in layout['placements'] if p['asset']=='gull')==3
evidence={'author':'马可波罗','issue':'SGODOT-424','stage':'B blockout 1',
    'unique_glbs':len(checks),'unique_triangles':sum(x['triangles'] for x in manifest['assets'].values()),
    'placed_triangles':sum(manifest['assets'][p['asset']]['triangles'] for p in layout['placements']),
    'placed_mesh_instances':len(layout['placements']),'unique_surfaces':len(checks),
    'glb_bytes':sum(x['bytes'] for x in manifest['assets'].values()),'navigation_cells':layout['nav_connected_cells'],
    'runtime_source_and_assets_equal':True,'vertex_color_normals_single_surface_uid_checks':checks,'asset_sha256':hashes,
    'reference':'tools/art/source/alcatraz_island/reference/provenance.json',
    'captures':{p.name:{'pixels':list(Image.open(p).size),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in DOC.glob('0*.png')},
    'top_layout_annotation':'Labels and route over actual rendered top view; raw screenshot remains in output.',
    'limits':['Desktop Vulkan Mobile / RTX 2060 only.','Programmatic walk and gesture regression, no Android input claim.',
              'No physical phone performance, map-entry integration, release, or whitebox approval is claimed.']}
(DOC/'asset-validation.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:evidence[k] for k in ['unique_glbs','unique_triangles','placed_triangles','navigation_cells']},ensure_ascii=False))
