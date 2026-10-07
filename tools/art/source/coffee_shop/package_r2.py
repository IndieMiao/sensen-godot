"""Reproducible R2 review package from actual runtime captures and exported geometry."""
from pathlib import Path
import json,shutil,hashlib,struct,subprocess,sys
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];doc=ROOT/'docs/design/coffee_shop-2026-10-07';out=ROOT/'output/coffee_shop'/(sys.argv[1] if len(sys.argv)>1 else 'r2')
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',23)
def fit(path,size):
 im=Image.open(path).convert('RGB');im.thumbnail(size,Image.Resampling.LANCZOS);canvas=Image.new('RGB',size,'#f4f0e2');canvas.paste(im,((size[0]-im.width)//2,(size[1]-im.height)//2));return canvas
reference=fit(doc/'reference.png',(900,900));runtime=fit(out/'godot-whole.png',(900,900));canvas=Image.new('RGB',(2700,980),'#f4f0e2');draw=ImageDraw.Draw(canvas)
for i,(im,label) in enumerate(((reference,'Figma 545:2956 | complete reference'),(runtime,out.name.upper()+' Godot Mobile/Vulkan | fixed model scale'),(Image.blend(reference,runtime,.5),'50% reference / 50% runtime | no warp'))):
 canvas.paste(im,(i*900,70));draw.text((i*900+20,20),label,font=font,fill='#504733')
canvas.save(doc/'comparison.png',optimize=True)
before=out/'baseline/godot-whole.png'
if not before.exists():
 before.parent.mkdir(parents=True,exist_ok=True);before.write_bytes(subprocess.check_output(['git','show','b3bc947:docs/design/coffee_shop-2026-10-07/godot-whole.png'],cwd=ROOT))
pair=Image.new('RGB',(1800,970),'#f4f0e2');draw=ImageDraw.Draw(pair)
for i,(path,label) in enumerate(((before,'R1 | before / original camera'),(out/'godot-whole.png',out.name.upper()+' | revised; dimensions retained'))):
 pair.paste(fit(path,(900,900)),(900*i,60));draw.text((900*i+20,15),label,font=font,fill='#504733')
pair.save(doc/'revision-before-after.jpg',quality=94)
ortho=Image.new('RGB',(1920,704),'#f4f0e2');draw=ImageDraw.Draw(ortho)
for i,name in enumerate(('front','side','top')):
 ortho.paste(fit(out/f'model-{name}.png',(640,640)),(i*640,64));draw.text((i*640+20,20),'Actual R2 model | '+name,font=font,fill='#504733')
ortho.save(doc/'orthographic.png',optimize=True)
for name in ('godot-whole.png','godot-detail.png','godot-detail-plants.png','godot-verification.json'):shutil.copy2(out/name,doc/name)
room=ROOT/'assets/rooms/coffee_shop';plants=ROOT/'assets/rooms/_shared/plants';stats=json.loads((room/'asset_stats.json').read_text());ps=json.loads((plants/'asset_stats.json').read_text());layout=json.loads((room/'layout.json').read_text());checked=[]
for path in list(room.glob('*.glb'))+list((room/'batches').glob('*.glb'))+list(plants.glob('*.glb')):
 b=path.read_bytes();magic,version,size=struct.unpack_from('<III',b);assert magic==0x46546c67 and version==2 and size==len(b)
 g=json.loads(b[20:20+struct.unpack_from('<I',b,12)[0]]);assert not g.get('images');assert len(g['meshes'])==1 and len(g['meshes'][0]['primitives'])==1
 checked.append(str(path.relative_to(ROOT)))
render=json.loads((out/'godot-verification.json').read_text());budget=stats['scene_budget'];assert render['static_surfaces']==budget['after']['static_surfaces']
result={'revision':'R2.1' if out.name=='r21' else 'R2','renderer':render,'glb_checks':{'passed':True,'single_surface_no_embedded_images':True,'files':checked},'budget':budget,'shared_plants':{'unique_triangles':ps['unique_triangles'],'leaf_triangle_max':ps['leaf_triangle_max'],'r1_comparison':ps['r1_comparison']},'reference_sha256':hashlib.sha256((doc/'reference.png').read_bytes()).hexdigest(),'comparison':'full-frame letterbox, direct 50% blend, no geometric warp','visual_acceptance':'pending Review','scale_decision':'All accepted 179 dimensions retained; Basic Room unchanged'}
(doc/'revision-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print('R2_PACKAGE',json.dumps(budget['after']))
