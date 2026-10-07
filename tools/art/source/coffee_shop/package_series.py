"""Package actual scene captures. References are letterboxed, never geometrically warped."""
from pathlib import Path
import sys,json,shutil,struct,hashlib
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];slug=sys.argv[1];rev=sys.argv[2] if len(sys.argv)>2 else 'r1';out=ROOT/'output'/slug/rev;doc=ROOT/'docs/design'/(slug+'-2026-10-07');ev=ROOT/'output/scene-bench'/slug/'evidence'
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',22)
def fit(file,size):
 im=Image.open(file).convert('RGB');im.thumbnail(size,Image.Resampling.LANCZOS);can=Image.new('RGB',size,'#eee7df');can.paste(im,((size[0]-im.width)//2,(size[1]-im.height)//2));return can
ref=fit(doc/'reference.png',(800,800));run=fit(out/'godot-whole.png',(800,800));can=Image.new('RGB',(2400,870),'#eee7df');draw=ImageDraw.Draw(can)
for i,(im,label) in enumerate(((ref,'Original Figma reference'),(run,rev.upper()+' Godot Mobile / Vulkan'),(Image.blend(ref,run,.5),'50% direct overlay; no warp'))):
 can.paste(im,(i*800,65));draw.text((i*800+18,20),label,font=font,fill='#4d4543')
can.save(doc/'comparison.png',optimize=True)
orth=Image.new('RGB',(1800,660),'#eee7df');draw=ImageDraw.Draw(orth)
for i,name in enumerate(('front','side','top')):
 orth.paste(fit(out/f'model-{name}.png',(600,600)),(i*600,60));draw.text((i*600+20,15),'Actual model: '+name,font=font,fill='#4d4543')
orth.save(doc/'orthographic.png',optimize=True)
for name in ('godot-whole.png','godot-detail.png','godot-detail-plants.png','godot-verification.json'):shutil.copy2(out/name,doc/name)
checked=[]
layout=json.loads((ROOT/'assets/rooms'/slug/'layout.json').read_text())
files=[ROOT/'assets/rooms'/slug/a['file'] for a in layout['assets']]+[ROOT/a['file'].removeprefix('res://') for a in layout.get('render_batches',[])]+[ROOT/a['file'].removeprefix('res://') for a in layout.get('shared_plants',[])]
for file in set(files):
 raw=file.read_bytes();assert struct.unpack_from('<I',raw)[0]==0x46546c67 and len(raw)==struct.unpack_from('<I',raw,8)[0]
 g=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]]);assert not g.get('images');assert len(g['meshes'])==1 and len(g['meshes'][0]['primitives'])==1;checked.append(str(file.relative_to(ROOT)))
stats=json.loads((ROOT/'assets/rooms'/slug/'asset_stats.json').read_text());render=json.loads((out/'godot-verification.json').read_text());budget=stats['scene_budget']['after'];assert render['static_surfaces']==budget['static_surfaces']
result={'revision':rev,'reference_sha256':hashlib.sha256((doc/'reference.png').read_bytes()).hexdigest(),'renderer':render,'budget':stats['scene_budget'],'glb_checks':{'passed':True,'single_surface_no_embedded_images':True,'files':sorted(checked)},'visual_acceptance':'Pending art director Review; metrics do not establish reference fidelity.'}
(doc/'revision-verification.json').write_text(json.dumps(result,indent=2)+'\n')
if (ev/'result.json').exists():
 bench=json.loads((ev/'result.json').read_text());assert bench['passed']
 for n in ['spawn.png','main.png','door.png','collisions.png','result.json','scale-measurements.json','record-result.json','video-metadata.json']:
  if (ev/n).exists():shutil.copy2(ev/n,doc/('bench-'+n))
print('PACKAGE_READY',slug,budget)
