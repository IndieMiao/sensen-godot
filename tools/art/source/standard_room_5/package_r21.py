"""Package R2 reference/actual-render evidence and enforce this scene's budgets."""
from pathlib import Path
import json,hashlib,struct,shutil
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4]
DOC=ROOT/'docs/design/standard_room_5-review21-2026-10-07'
OUT=ROOT/'output/zhaoyun-r21-2026-10-07';BENCH=OUT/'bench';KIT=ROOT/'assets/rooms/standard_room_5'
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',22)
for name in ['godot.png','detail-kitchen.png','detail-living.png','detail-fire.png']:
    shutil.copy2(OUT/name,DOC/name)
def sheet(items,name,width=960,height=720):
    canvas=Image.new('RGB',(width*len(items),height+60),'#f5f0df');draw=ImageDraw.Draw(canvas)
    for i,(label,im) in enumerate(items):
        pic=im.convert('RGB').resize((width,height),Image.Resampling.LANCZOS)
        canvas.paste(pic,(i*width,60));draw.text((i*width+18,15),label,font=font,fill='#53462f')
    canvas.save(DOC/name)
ref=Image.open(DOC/'reference.png').convert('RGB').resize((960,720),Image.Resampling.LANCZOS)
actual=Image.open(OUT/'godot.png').convert('RGB').resize((960,720),Image.Resampling.LANCZOS)
overlay=Image.blend(ref,actual,.5);overlay.save(DOC/'overlay-50.png')
sheet([('Figma reference',ref),('R2.1 Godot / 29.18-degree pitch',actual),('50% overlay / no warp',overlay)],'comparison-r21.png')
sheet([('R2 approved sample',Image.open(DOC/'before.png')),('R2.1 revision',actual)],'before-after.png')
sheet([(name.title()+' / Blender model',Image.open(ROOT/'output/standard_room_5-2026-10-07'/(name+'.png'))) for name in ['front','side','top']],'orthographic-sheet.png',640,640)
for name in ['spawn.png','main.png','door.png','collisions.png']:
    shutil.copy2(BENCH/name,DOC/('bench-'+name))
for name in ['result.json','scale-measurements.json','record-result.json','video-metadata.json']:
    obj=json.loads((BENCH/name).read_text());obj.pop('pid',None);(DOC/('bench-'+name)).write_text(json.dumps(obj,indent=2)+'\n')
sheet([(label,Image.open(BENCH/(f'video-{i}.png'))) for i,label in enumerate(['Video / 0.5s','Video / 7.5s','Video / 14s'])],'video-frames.png',640,480)
stats=json.loads((KIT/'asset_stats.json').read_text());layout=json.loads((KIT/'layout.json').read_text());render=json.loads((OUT/'godot-validation.json').read_text())
assert stats['scene_triangles']==render['triangles']
assert stats['scene_triangles']<=200000 and stats['plant_budget_triangles']<=100000 and stats['static_draw_surfaces']<=60
files=[KIT/a['file'] for a in layout['assets']];shared=ROOT/'assets/rooms/_shared/plants'
files += [shared/name for name in sorted({a['file'] for a in layout['shared_plants']})]
for path in files:
    data=path.read_bytes();assert data[:4]==b'glTF';size=struct.unpack_from('<I',data,12)[0];gltf=json.loads(data[20:20+size]);assert not gltf.get('images')
    assert all('NORMAL' in primitive['attributes'] and 'TEXCOORD_0' in primitive['attributes'] for mesh in gltf['meshes'] for primitive in mesh['primitives'])
files += list(KIT.glob('*.png'))+[shared/'room_albedo_ao.png',shared/'material.tres',ROOT/'tools/art/source/standard_room_5/standard_room_5.blend',KIT/'layout.json']
bench=json.loads((BENCH/'result.json').read_text());record=json.loads((BENCH/'record-result.json').read_text());video=json.loads((BENCH/'video-metadata.json').read_text())
assert bench['passed'] and record['passed'] and video['image_content_valid']
colour=json.loads((DOC/'colour-verification.json').read_text());cloth=json.loads((DOC/'cloth-uv-verification.json').read_text());assert colour['passed'] and cloth['passed']
summary={'revision':'R2.1','state':'Review','user_acceptance':'pending','reference':{'file':'OMLTC3yw3u2WDjOZhLnhaR','node':'545:2969'},
         'renderer':render,'asset_stats':stats,'shared_plant_revision':'a054d81 (R2.1, geometry budget inherited from R2)' ,'camera_fit':json.loads(Path(__file__).with_name('camera-r2.json').read_text()),
         'checks':{'rendered_character_checks':len(bench['checks']),'character_passed':bench['passed'],'route_video_passed':record['passed'],'colour_passed':colour['passed'],'cloth_uv_passed':cloth['passed'],'no_embedded_images':True},
         'video':{'duration_seconds':float(video['format']['duration']),'sha256':hashlib.sha256((BENCH/'walkthrough.mp4').read_bytes()).hexdigest(),'samples_visually_reviewed':True},
         'hashes':{str(file.relative_to(ROOT)):hashlib.sha256(file.read_bytes()).hexdigest() for file in files},
         'scope':'Zhao Yun Standard Room R2.1 finishing; no other artist scene edit, Android performance claim or production update.'}
(DOC/'verification-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({'triangles':stats['scene_triangles'],'plant_triangles':stats['plant_budget_triangles'],'surfaces':stats['static_draw_surfaces'],'checks':len(bench['checks'])}))
