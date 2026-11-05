"""Package unretouched runtime frames with labels outside the 360x800 images."""
from pathlib import Path
import json
import shutil
from PIL import Image,ImageDraw,ImageFont,ImageChops

SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[3]
OUT=ROOT/'output/wild-ground-422'
DOC=ROOT/'docs/design/wild-ground-422'
DOC.mkdir(parents=True,exist_ok=True)
validation=json.loads((OUT/'captures/godot-validation.json').read_text())
assert validation['passed'] and len(validation['water_pixels'])==3
assert all(r['changed_protected_pixels']==0 for r in validation['water_pixels'])
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',20)
small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',15)
for shape in ['crescent','gourd','meander']:
    canvas=Image.new('RGB',(756,890),'#f5f2e9');d=ImageDraw.Draw(canvas)
    d.text((18,12),'SGODOT-422 / '+shape+' / default opening',fill='#33452f',font=font)
    for col,label in enumerate(['before','after']):
        name=f'{shape}_{label}_360x800.png'
        source=OUT/'captures'/name
        img=Image.open(source)
        assert img.size==(360,800)
        canvas.paste(img,(12+col*372,64))
        d.text((12+col*372,40),label.upper()+' 360 x 800',fill='#44513e',font=small)
        shutil.copy2(source,DOC/name)
    d.text((12,870),'Godot 4.7.2 / Mobile Vulkan / Steam Deck / ground study only',fill='#56634c',font=small)
    canvas.save(DOC/(shape+'_comparison.png'))
    shutil.copy2(OUT/'captures'/(shape+'_overhead.png'),DOC/(shape+'_overhead.png'))
gallery=Image.new('RGB',(1128,858),'#f5f2e9');d=ImageDraw.Draw(gallery)
for i,shape in enumerate(['crescent','gourd','meander']):
    d.text((12+i*372,12),shape+' / AFTER',font=font,fill='#33452f')
    gallery.paste(Image.open(DOC/f'{shape}_after_360x800.png'),(12+i*372,45))
gallery.save(DOC/'three_openings.png')
for name,path in [('godot-validation.json',OUT/'captures/godot-validation.json'),
                  ('map-validation.json',OUT/'map-validation.json'),
                  ('runtime-base.json',OUT/'runtime-base.json')]:
    shutil.copy2(path,DOC/name)

# A spatial diagram, explicitly labelled as such, showing why the path fades
# near the player instead of painting a false exit under the quick bar.
slots=json.loads((SRC/'reference/pond_slots_v2.json').read_text())['shapes']
templates=json.loads((SRC/'reference/p0_pond_templates.json').read_text())['templates']
manifest=json.loads((ROOT/'assets/ponds/ground/ground_manifest.json').read_text())
scale=42
canvas=Image.new('RGB',(3*650,920),'#f5f2e9');draw=ImageDraw.Draw(canvas)
for i,shape in enumerate(slots):
    ox=i*650+45;oy=75
    def xy(x,z):return (ox+(x+.9)*scale,oy+(z+17)*scale)
    t=templates[shape]
    for row,s in enumerate(t['navigation']['rows']):
        for col,c in enumerate(s):
            if c=='1':
                x,z=col*.25,-row*.25
                draw.rectangle([xy(x,z-.25),xy(x+.25,z)],fill='#a6bc78')
    draw.polygon([xy(*p) for p in t['polygon']],fill='#81bcd1')
    mask=Image.open(ROOT/f'assets/ponds/ground/{shape}_layout.png').getchannel('B')
    dry=Image.open(ROOT/'assets/ponds/ground/dry_ground_mask.png').getchannel(manifest['dry_ground_mask']['channels'].index(shape))
    mask=ImageChops.multiply(mask,dry)
    tint=Image.new('RGBA',mask.size,'#dfbc83');tint.putalpha(mask)
    tint=tint.resize((int(20*scale),int(24*scale)))
    # Restrict overlays to this shape's column, retaining the original X/Z map.
    layer=Image.new('RGBA',(650,920));layer.alpha_composite(tint,(int(xy(-4,-20)[0]-i*650),int(xy(-4,-20)[1])))
    canvas.paste(layer,(i*650,0),layer)
    draw=ImageDraw.Draw(canvas)
    for name,s in slots[shape].items():
        a,b=xy(s['x']-.75,s['z']-.75),xy(s['x']+.75,s['z']+.75)
        draw.rectangle([a,b],outline='#9a535b',width=2)
        draw.text((a[0]+2,a[1]+2),name,font=small,fill='#753b45')
        x,z=s['stand'];a=xy(x,z);draw.ellipse((a[0]-3,a[1]-3,a[0]+3,a[1]+3),fill='#faf8ed',outline='#394939')
    a=xy(6.125,-1.625);draw.ellipse((a[0]-5,a[1]-5,a[0]+5,a[1]+5),fill='#f8f2db',outline='#313b31',width=2)
    draw.text((i*650+20,15),shape+' / world XZ constraint diagram',font=font,fill='#33452f')
    draw.text((i*650+20,865),'Green: walkable / gold: actual soil mask',font=small,fill='#33452f')
    draw.text((i*650+20,887),'Red: resource footprint / dots: gathering stands',font=small,fill='#33452f')
canvas.save(DOC/'layout_constraints.png')

# Fine detail tile repeated 3x3, without resampling at the seams.
tile=Image.open(ROOT/'assets/ponds/ground/meadow_color.png').convert('RGB')
tile=tile.resize((256,256),Image.Resampling.LANCZOS)
canvas=Image.new('RGB',(768,800),'#f5f2e9')
for y in range(3):
    for x in range(3):canvas.paste(tile,(x*256,32+y*256))
ImageDraw.Draw(canvas).text((10,8),'Fine colour tile / 3 x 3 repeats / macro layout does not repeat',font=small,fill='#33452f')
canvas.save(DOC/'detail_tile_3x3.png')
print(DOC)
