"""One native-size red-mine frame for the enlarged quartz headpiece."""
from pathlib import Path
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'output/mine-kit-355/headgear'
DOC=ROOT/'docs/design/mine-kit-355-2026-11-02/headgear/v1.2'
DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-355_slime_king_v1.2_'
font=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',19)
small=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',16)
godot=json.loads((OUT/'captures/godot-validation.json').read_text())
glb=json.loads((OUT/'glb-validation.json').read_text())
assert godot['passed'] and glb['passed']
source=Image.open(OUT/'captures/quartz_cluster_red_mine_43deg.png').convert('RGB')
assert source.size==(360,800)
out=Image.new('RGB',(360,978),'#F1F4F3');draw=ImageDraw.Draw(out)
draw.text((12,10),'SGODOT-355 / Quartz v1.2',font=font,fill='#23352E')
draw.text((12,39),'Red mine / 43 deg / game zoom .8',font=small,fill='#23352E')
out.paste(source,(0,70))
draw.text((12,880),'280 tris / king r=.85 / player H=1.745m',font=small,fill='#23352E')
draw.text((12,906),'Height above head: .703m at r=1',font=small,fill='#23352E')
draw.text((12,932),'In game: .597m above head',font=small,fill='#23352E')
draw.text((263,952),'【黄忠】',font=small,fill='#23352E')
path=DOC/(PREFIX+'quartz_red_mine_43deg.png');out.save(path)
paths=[path]
path=DOC/(PREFIX+'validation.json')
path.write_text(json.dumps({'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
    'manifest':json.loads((ROOT/'tools/art/source/monsters/slime_king/manifest.json').read_text()),
    'glb':glb,'godot':godot,'dependencies':json.loads((OUT/'dependencies.json').read_text())},ensure_ascii=False,indent=2)+'\n');paths.append(path)
media=[{'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'author':'黄忠',
    'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in paths]
(DOC/(PREFIX+'media-manifest.json')).write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print(DOC,len(media),'attachments')
