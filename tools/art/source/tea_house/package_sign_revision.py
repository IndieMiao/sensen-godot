"""Deliver one signed default-camera image and the focused v1.1 evidence."""
from pathlib import Path
import hashlib
import json
from PIL import Image
from package_review import label

ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'output/tea-216'
DOC=ROOT/'docs/design/tea_house-2026-11-01'
PREFIX='SGODOT-216_tea_v1.1_'
AUTHOR='5281cd25-6a49-4df8-9802-f3e534956e80'

records={key:json.loads((OUT/path).read_text()) for key,path in [
    ('geometry','geometry-validation.json'),('source','source-validation.json'),
    ('preservation','sign-v1.1-preservation.json'),('godot','captures/sign-v1.1-godot.json')]}
assert all(record['passed'] for record in records.values())
source=OUT/'captures/v1.1_default_43deg_360.png'
assert (OUT/'captures/sign-v1.1-godot.json').stat().st_mtime>=source.stat().st_mtime
image=label(Image.open(source).convert('RGB'),'茶馆 / 招牌移位 v1.1',
    '43° / 6.72m / 360px；招牌位于后墙左段。',revision='v1.1')
picture=DOC/(PREFIX+'default_43deg_360.png');image.save(picture)
validation=DOC/(PREFIX+'validation.json')
validation.write_text(json.dumps({'author':'黄忠','virtual_user_id':AUTHOR,'passed':True,**records},ensure_ascii=False,indent=2)+'\n')
media=[{'file':path.name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'virtual_user_id':AUTHOR} for path in [picture,validation]]
(DOC/(PREFIX+'media-manifest.json')).write_text(json.dumps(media,indent=2)+'\n')
print(json.dumps({'files':len(media),'sign':records['godot']['sign']},indent=2))
