"""Final layout evidence: actual #792 blockout, unchanged host code and our seven GLBs."""
from pathlib import Path
import hashlib,json,shutil,subprocess
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent
OUT=ROOT/'output/alcatraz-far-424';CAP=OUT/'island-captures';KIT=ROOT/'assets/landmarks/alcatraz_island'
DOC=ROOT/'docs/design/alcatraz-far-424-2026-11-06/v1.1';DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-424_far_v1.1_';FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
manifest=json.loads((KIT/'alc_far_manifest.json').read_text());geo=json.loads((OUT/'geometry-validation.json').read_text());render=json.loads((CAP/'validation.json').read_text())
assert geo['passed'] and render['passed']
for name in ['opening_360','mid_hill','summit','summit_wide']:
 shutil.copy2(CAP/(PREFIX+name+'.png'),DOC/(PREFIX+name+'.png'))
raw=Image.open(CAP/(PREFIX+'opening_360.png')).convert('RGB')
zoom=raw.crop((0,40,180,155)).resize((720,460),Image.Resampling.NEAREST)
detail=Image.new('RGB',(760,550),'#F4F2E9');detail.paste(zoom,(20,55));d=ImageDraw.Draw(detail)
d.text((20,13),'黄忠 · 码头开场桥 / 原图局部 4×',font=ImageFont.truetype(FONT,23),fill='#314D55')
d.text((20,520),'34df9c0b 白模 + 本包；默认 43° / 14.5° / 6.72 m',font=ImageFont.truetype(FONT,18),fill='#314D55')
detail.save(DOC/(PREFIX+'opening_bridge_detail.png'))
unchanged={}
for name in ['alc_lighthouse','alc_lighthouse_far','alc_watertower','alc_watertower_far']:
 for suffix in ['.glb','.glb.import']:
  p=KIT/(name+suffix);old=subprocess.check_output(['git','show','c56e4c64:'+str(p.relative_to(ROOT))],cwd=ROOT)
  assert p.read_bytes()==old;unchanged[str(p.relative_to(ROOT))]=hashlib.sha256(old).hexdigest()
# Every reviewed replacement must equal the delivered GLB, and every host source
# must equal the pinned blockout. Only the documented card LOD layout edit differs.
fixture=json.loads((OUT/'island-fixture.json').read_text())
for name,spec in manifest['assets'].items():
 p=KIT/spec['file'];assert p.read_bytes()==(OUT/'island-project/assets/landmarks/alcatraz_island'/p.name).read_bytes()
for rel,digest in fixture['host_files'].items():assert hashlib.sha256((OUT/'island-project'/rel).read_bytes()).hexdigest()==digest
data={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','geometry':geo,'combined_blockout':render,'fixture':fixture,
 'placement':json.loads((KIT/'alc_far_placement.json').read_text()),'unchanged_tower_sha256':unchanged,'passed':True}
(DOC/(PREFIX+'validation.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
items=[]
for p in sorted(DOC.glob(PREFIX+'*')):
 row={'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
 if p.suffix=='.png':row['size']=list(Image.open(p).size);assert max(row['size'])<=1600
 items.append(row)
(DOC/'media-manifest.json').write_text(json.dumps(items,ensure_ascii=False,indent=2)+'\n');print('Packaged',len(items),'layout review files')
