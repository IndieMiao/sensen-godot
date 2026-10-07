"""Package actual scene-review evidence and enforce the batch's declared budgets."""
from pathlib import Path
import sys,json,hashlib,struct,shutil,os
from PIL import Image,ImageDraw,ImageFont,ImageOps
ROOT=Path(__file__).resolve().parents[2];slug=sys.argv[1];card=sys.argv[2]
DOC=ROOT/'docs/design'/(slug+'-2026-10-07');OUT=Path(os.environ.get('SCENE_REVIEW_OUTPUT',ROOT/'output'/('zhaoyun-'+card+'-review-2026-10-07')));BENCH=OUT/'bench';KIT=ROOT/'assets/rooms'/slug
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',22)
def sheet(items,name,width=960,height=720):
 canvas=Image.new('RGB',(width*len(items),height+58),'#f5f0df');d=ImageDraw.Draw(canvas)
 for i,(label,im) in enumerate(items):
  canvas.paste(ImageOps.pad(im.convert('RGB'),(width,height),color='#f5f0df'),(i*width,58));d.text((i*width+18,14),label,font=font,fill='#53462f')
 canvas.save(DOC/name)
for file in [OUT/'godot.png',*OUT.glob('detail-*.png')]:shutil.copy2(file,DOC/file.name)
ref=ImageOps.pad(Image.open(DOC/'reference.png').convert('RGB'),(960,720),color='#f5f0df');actual=Image.open(OUT/'godot.png').convert('RGB').resize((960,720),Image.Resampling.LANCZOS);overlay=Image.blend(ref,actual,.5)
overlay.save(DOC/'overlay-50.png');sheet([('Figma reference',ref),('Revised Godot Mobile / Vulkan',actual),('50% direct overlay / no warp',overlay)],'comparison.png')
sheet([(s.title()+' / Blender model',Image.open(ROOT/'output'/(slug+'-2026-10-07')/(s+'.png'))) for s in ('front','side','top')],'orthographic-sheet.png',640,640)
for name in ('spawn.png','main.png','door.png','collisions.png'):shutil.copy2(BENCH/name,DOC/('bench-'+name))
for name in ('result.json','scale-measurements.json','record-result.json','video-metadata.json'):
 obj=json.loads((BENCH/name).read_text());obj.pop('pid',None);(DOC/('bench-'+name)).write_text(json.dumps(obj,indent=2)+'\n')
sheet([(label,Image.open(BENCH/f'video-{i}.png')) for i,label in enumerate(('Video 0.5s','Video 7.5s','Video 14s'))],'video-frames.png',640,480)
stats=json.loads((KIT/'asset_stats.json').read_text());layout=json.loads((KIT/'layout.json').read_text());render=json.loads((OUT/'godot-validation.json').read_text());assert stats['scene_triangles']==render['triangles'],(stats['scene_triangles'],render['triangles'])
assert stats['scene_triangles']<=200000 and stats['plant_budget_triangles']<=100000 and render['surfaces']<=60
files=[KIT/a['file'] for a in layout['assets']];shared=ROOT/'assets/rooms/_shared/plants';files += [shared/n for n in sorted({a['file'] for a in layout.get('shared_plants',[])})]
for path in files:
 data=path.read_bytes();assert data[:4]==b'glTF';size=struct.unpack_from('<I',data,12)[0];gltf=json.loads(data[20:20+size]);assert not gltf.get('images')
 assert all('NORMAL' in primitive['attributes'] and 'TEXCOORD_0' in primitive['attributes'] for mesh in gltf['meshes'] for primitive in mesh['primitives'])
files+=list(KIT.glob('*.png'))+[shared/'room_albedo_ao.png',shared/'material.tres',ROOT/'tools/art/source'/slug/(slug+'.blend'),KIT/'layout.json']
bench=json.loads((BENCH/'result.json').read_text());record=json.loads((BENCH/'record-result.json').read_text());video=json.loads((BENCH/'video-metadata.json').read_text());colour=json.loads((DOC/'colour-verification.json').read_text());assert bench['passed'] and record['passed'] and video['image_content_valid'] and colour['passed']
summary={'state':'Review','user_acceptance':'pending','reference':layout['reference'],'renderer':render,'asset_stats':stats,'camera_fit':json.loads((ROOT/'tools/art/source'/slug/'camera-review.json').read_text()),'checks':{'character_checks':len(bench['checks']),'character_passed':bench['passed'],'route_video_passed':record['passed'],'colour_passed':colour['passed'],'normals_uv_external_images':True},'video':{'duration_seconds':float(video['format']['duration']),'sha256':hashlib.sha256((BENCH/'walkthrough.mp4').read_bytes()).hexdigest()},'hashes':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},'scope':'Zhao Yun scene art revision; actual desktop rendered benchmark. No production update or physical-phone GPU claim.'}
(DOC/'verification-summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({'triangles':stats['scene_triangles'],'plants':stats['plant_budget_triangles'],'surfaces':render['surfaces'],'checks':len(bench['checks'])}))
