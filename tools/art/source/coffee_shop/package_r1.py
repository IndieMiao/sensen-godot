"""Package actual R1 Godot renders and source-budget evidence. No image generation."""
from pathlib import Path
import json, shutil, hashlib, struct
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];doc=ROOT/'docs/design/coffee_shop-2026-10-07';out=ROOT/'output/coffee_shop/r1';assets=ROOT/'assets/rooms/coffee_shop';plants=ROOT/'assets/rooms/_shared/plants'
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',23)
small=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',17)
def fit(path,size):
    src=Image.open(path).convert('RGB');src.thumbnail(size,Image.Resampling.LANCZOS);dst=Image.new('RGB',size,'#f2f3e8');dst.paste(src,((size[0]-src.width)//2,(size[1]-src.height)//2));return dst
# Equal image scale/presentation, no warp or independent object alignment.
reference=fit(doc/'reference.png',(900,900));runtime=fit(out/'godot-whole.png',(900,900))
canvas=Image.new('RGB',(2700,980),'#f4f4e9');d=ImageDraw.Draw(canvas)
for i,(im,label) in enumerate([(reference,'Figma 545:2956 | full reference'),(runtime,'Godot Mobile/Vulkan | R1 full scene'),(Image.blend(reference,runtime,.5),'50% reference + 50% Godot | no warp')]):
    canvas.paste(im,(i*900,70));d.text((i*900+22,20),label,font=font,fill='#35473b')
canvas.save(doc/'comparison.png',optimize=True)
# Preserve prior revision in Git; compact visual before/after stays in this review record.
before=fit(out/'baseline/whole.png',(700,700));after=fit(out/'godot-whole.png',(700,700));change=Image.new('RGB',(1400,760),'#f4f4e9');d=ImageDraw.Draw(change)
for i,(im,label) in enumerate([(before,'Before review'),(after,'R1 | revised art')]):change.paste(im,(700*i,60));d.text((700*i+20,17),label,font=font,fill='#35473b')
change.save(doc/'revision-before-after.jpg',quality=94)
ortho=Image.new('RGB',(1920,704),'#f4f4e9');d=ImageDraw.Draw(ortho)
for i,name in enumerate(('front','side','top')):
    ortho.paste(fit(out/f'model-{name}.png',(640,640)),(i*640,64));d.text((i*640+20,20),'Actual model | '+name,font=font,fill='#35473b')
ortho.save(doc/'orthographic.png',optimize=True)
for name in ('godot-whole.png','godot-detail.png','godot-detail-plants.png','godot-verification.json'):shutil.copy2(out/name,doc/name)
layout=json.loads((assets/'layout.json').read_text());stats=json.loads((assets/'asset_stats.json').read_text());plant_stats=json.loads((plants/'asset_stats.json').read_text())
checked=[]
for folder,record in [(assets,stats),(plants,plant_stats)]:
    for a in record['assets']:
        blob=(folder/(a['name']+'.glb')).read_bytes();magic,version,size=struct.unpack_from('<III',blob);assert magic==0x46546c67 and version==2 and size==len(blob)
        gltf=json.loads(blob[20:20+struct.unpack_from('<I',blob,12)[0]]);assert not gltf.get('images');assert len(gltf['meshes'])==1 and len(gltf['meshes'][0]['primitives'])==1
        checked.append(str((folder/(a['name']+'.glb')).relative_to(ROOT)))
pc={a['name']:a['triangles'] for a in plant_stats['assets']};placed=sum(pc[p['asset']] for p in layout['shared_plants']);unique=sum(pc[n] for n in {p['asset'] for p in layout['shared_plants']})
result={'scope':'R1 art resource and actual renderer checks; benchmark reported separately','renderer':json.loads((out/'godot-verification.json').read_text()),'glb_checks':{'pass':True,'files':checked,'single_surface_no_embedded_images':True},'budget':{'room_unique_triangles':stats['unique_triangles'],'room_placed_triangles':stats['scene_triangles'],'used_shared_plant_unique_triangles':unique,'placed_plant_triangles':placed,'total_placed_triangles':stats['scene_triangles']+placed,'static_surfaces':stats['static_draw_surfaces']+len(layout['shared_plants']),'atlases':2,'atlas_resolution':[2048,2048]},'reference_sha256':hashlib.sha256((doc/'reference.png').read_bytes()).hexdigest(),'comparison':'full-frame letterbox, identical 900px panels, direct 50% blend, no perspective warp','visual_acceptance':'pending user sample review'}
(doc/'revision-verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result['budget'],indent=2))
