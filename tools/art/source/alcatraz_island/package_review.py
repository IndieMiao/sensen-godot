"""Archive reviewed captures, add a clearly identified top-view annotation layer."""
from pathlib import Path
import json
import hashlib
import shutil
import struct
import re
import ast
from collections import Counter
from PIL import Image, ImageDraw, ImageFont

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
REVIEW=ROOT/'output/alcatraz-424/v5/review'
DOC=ROOT/'docs/design/alcatraz-blockout-424-2026-11-05/v5'
ASSETS=ROOT/'assets/landmarks/alcatraz_island'
QA=ROOT/'output/alcatraz-424/project'
verification=json.loads((REVIEW/'verification.json').read_text())
assert verification['status']=='pass',verification['failures']
sweep=json.loads((REVIEW/'wide-sweep.json').read_text())
assert sweep['status']=='pass',sweep['failures']
DOC.mkdir(parents=True,exist_ok=True);(DOC/'.gdignore').touch()
expected={name+'.png' for name in verification['view_metrics']}
for p in DOC.rglob('*.png'):
    if str(p.relative_to(DOC)) not in expected and p.name!='07-route-contact-sheet.png':p.unlink()
for name in sorted(expected):
    src=REVIEW/name;dst=DOC/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
shutil.copy2(REVIEW/'verification.json',DOC/'verification.json')
shutil.copy2(REVIEW/'wide-sweep.json',DOC/'wide-sweep.json')
layout=json.loads((ASSETS/'layout.json').read_text())
assert json.loads((ASSETS/'placement_points.json').read_text())['instances']==layout['instances']
manifest=json.loads((ASSETS/'manifest.json').read_text())
font='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
f=ImageFont.truetype(font,18);small=ImageFont.truetype(font,15)
im=Image.open(REVIEW/'04-top-layout.png').convert('RGB');d=ImageDraw.Draw(im)
def point(v):return (500+v[0]*1000/74,600+v[2]*1000/74)
route=[point(v) for v in layout['walk_goals']]
walk_path=[]
for i in range(1,len(layout['walk_goals'])):
    walk_path.extend(point(v) for v in ast.literal_eval(verification['route_%d_path'%i]['evidence']))
d.line(walk_path,fill='#285b80',width=4)
for x,y in route:d.ellipse((x-6,y-6,x+6,y+6),fill='#285b80',outline='white',width=2)
def label(text,xy,target=None):
    if target:d.line([xy,target],fill='#263b44',width=2)
    b=d.textbbox(xy,text,font=f)
    d.rounded_rectangle((b[0]-5,b[1]-4,b[2]+5,b[3]+4),radius=4,fill='#f4f3ec')
    d.text(xy,text,font=f,fill='#263b44')
label('ALCATRAZ / V5 / ACCEPTED TOWERS + PLACEMENTS',(22,18))
d.text((22,48),'Rendered top view + actual navigation path. North is up.',font=small,fill='#263b44')
label('Island / dock footprint: 60 x 40 m',(310,170))
d.line([(point([-30,0,0])[0],210),(point([30,0,0])[0],210)],fill='#263b44',width=2)
for x in [-30,30]:
    px=point([x,0,0])[0];d.line([(px,203),(px,217)],fill='#263b44',width=2)
label('15 m lighthouse',(20,250),point([-25,10,-11.5]))
label('40 m museum / 9 m high',(370,280),point([0,10,-13]))
label('12 m water tower',(780,250),point([25,10,-14]))
label('SummitZone / +10 m',(760,545),route[-1])
label('TerraceZone / 4 flights',(735,645),point([10,5.5,3]))
label('Mid-hill / +5.5 m',(730,690),route[1])
label('Ruins',(780,750),point([16,3.25,5]))
label('DockZone / +1 m',(20,920),route[0])
label('25 m ferry / decoration',(580,930),point([-7,0,19]))
label('Map exit',(250,990),point(layout['exit']))
length=verification['route_about_120m']['evidence']
d.text((22,1040),f'Actual walk via mid-hill: {length:.1f} m | four flights: 15 x 0.15 m each',font=f,fill='#263b44')
d.text((22,1070),'Camera width 6.72 m / farm avatar unchanged (nominal 1.75 m)',font=f,fill='#263b44')
d.text((22,1100),'FarZone: card anchors 20 m seaward, fake elevation/depth; see opening.',font=small,fill='#263b44')
d.line([(22,1160),(22+1000/74*10,1160)],fill='#263b44',width=4)
d.text((22,1170),'10 m',font=small,fill='#263b44')
im.save(DOC/'04-top-layout.png')

checks=[];hashes={};dimensions={}
for name in manifest['assets']:
    p=ASSETS/(name+'.glb');b=p.read_bytes()
    size,kind=struct.unpack_from('<II',b,12);g=json.loads(b[20:20+size])
    primitives=[v for m in g['meshes'] for v in m['primitives']]
    assert len(g['meshes'])==1 and len(primitives)==1,name
    assert all('COLOR_0' in v['attributes'] and 'NORMAL' in v['attributes'] for v in primitives),name
    assert re.search(r'uid="uid://[a-y0-8]+"',(ASSETS/(name+'.glb.import')).read_text()),name
    assert b==(QA/'assets/landmarks/alcatraz_island'/p.name).read_bytes(),name
    hashes[p.name]=hashlib.sha256(b).hexdigest()
    acc=g['accessors'][primitives[0]['attributes']['POSITION']]
    dimensions[name]={'min':acc['min'],'max':acc['max'],'size':[b-a for a,b in zip(acc['min'],acc['max'])]}
    checks.append(name)
for name in ['layout.json','manifest.json','placement_points.json','sea_backdrop.gdshader','far_card.gdshader']:
    assert (ASSETS/name).read_bytes()==(QA/'assets/landmarks/alcatraz_island'/name).read_bytes(),name
assert re.fullmatch(r'uid://[a-y0-8]+\s*',(ASSETS/'sea_backdrop.gdshader.uid').read_text())
for name in ['alcatraz_island.gd','alcatraz_island.tscn']:
    assert (ROOT/'scenes/landmark'/name).read_bytes()==(QA/'scenes/landmark'/name).read_bytes(),name
assert sum(1 for p in layout['placements'] if p['asset']=='gull')==3
for asset,axis,expected in [('alc_museum',0,40),('alc_museum',1,9),('alc_lighthouse',1,15),('alc_watertower',1,12),('ferry',0,25),('alc_bench',0,1.5),('alc_lamp',1,3.5)]:
    assert abs(dimensions[asset]['size'][axis]-expected)<.02,(asset,dimensions[asset])
assert sum(manifest['assets'][p['asset']]['triangles'] for p in layout['placements'])<=300000
assert verification['total_surface_budget_with_multimesh']['evidence']<=80
evidence={'author':'马可波罗','issue':'SGODOT-424','stage':'B blockout v5 accepted towers and vegetation placements',
    'unique_glbs':len(checks),'unique_triangles':sum(x['triangles'] for x in manifest['assets'].values()),
    'placed_triangles':sum(manifest['assets'][p['asset']]['triangles'] for p in layout['placements']),
    'placed_mesh_instances':len(layout['placements']),'unique_surfaces':len(checks),
    'glb_bytes':sum(x['bytes'] for x in manifest['assets'].values()),'navigation_cells':layout['nav_connected_cells'],'zones':layout['zones']+['FarZone'],'repeat_instances':len(layout['instances']),'lod_groups':layout['lod_groups'],'walk_bounds':layout['walk_bounds'],'dimensions_m':layout['dimensions_m'],
    'actual_walk_m':verification['route_about_120m']['evidence'],'direct_walk_m':verification['direct_route_about_120m']['evidence'],
    'live_surfaces_including_avatar_and_distant_layer':verification['total_surface_budget_with_multimesh']['evidence'],
    'live_triangles_including_avatar_and_distant_layer':verification['total_triangle_budget_with_multimesh']['evidence'],
    'view_metrics':{name:{k:v for k,v in row.items() if k!='samples'} for name,row in verification['view_metrics'].items()},'runtime_source_and_assets_equal':True,'vertex_color_normals_single_surface_uid_checks':checks,'asset_sha256':hashes,'exported_module_bounds_m':dimensions,
    'reference':'tools/art/source/alcatraz_island/reference/provenance.json',
    'instance_counts':dict(Counter(p['asset'] for p in layout['instances'])),
    'instance_owners':dict(Counter(p['owner'] for p in layout['instances'])),
    'detail_max_view_width_m':{a['name']:a['max_view_width_m'] for a in layout['assets'] if 'max_view_width_m' in a},
    'captures':{str(p.relative_to(DOC)):{'pixels':list(Image.open(p).size),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in DOC.rglob('*.png')},
    'top_layout_annotation':'Labels and route over actual rendered top view; raw screenshot remains in output.',
    'limits':['Desktop Vulkan Mobile / RTX 2060 only.','Programmatic walk and gesture regression, no Android input claim.',
              'No physical phone performance, map-entry integration, release, or whitebox approval is claimed.']}
(DOC/'asset-validation.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:evidence[k] for k in ['unique_glbs','unique_triangles','placed_triangles','navigation_cells']},ensure_ascii=False))

# Route contact sheet and a compact CSV retain every full-size source frame.
import csv,math
photos=sorted((DOC/'route').glob('*.png'))
cols=math.ceil(len(photos)/4);sheet=Image.new('RGB',(cols*180,1600),'#e6e3d8');draw=ImageDraw.Draw(sheet)
font_small=ImageFont.truetype(font,12)
for i,p in enumerate(photos):
    x=i%cols*180;y=i//cols*400
    sheet.paste(Image.open(p).resize((180,400)),(x,y));draw.rectangle((x,y,x+180,y+18),fill='#fff8e8');draw.text((x+3,y+2),p.stem,font=font_small,fill='#182833')
sheet.save(DOC/'07-route-contact-sheet.png')
with (DOC/'view-budgets.csv').open('w',newline='') as file:
    fields=['view','visible_triangles','visible_draw_calls','shadow_draw_calls','canvas_draw_calls','total_draw_calls','global_draw_calls']
    writer=csv.DictWriter(file,fieldnames=fields,lineterminator="\n");writer.writeheader()
    for name,row in verification['view_metrics'].items():writer.writerow({'view':name,**{k:row[k] for k in fields[1:]}})

assert len(photos)==verification['route_screens']
evidence['captures']={str(p.relative_to(DOC)):{'pixels':list(Image.open(p).size),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in DOC.rglob('*.png')}
for image_info in evidence['captures'].values():assert max(image_info['pixels'])<=1600
(DOC/'asset-validation.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
