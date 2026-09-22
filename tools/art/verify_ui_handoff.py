#!/usr/bin/env python3
from pathlib import Path
from PIL import Image
from pypdf import PdfReader
import json,re,hashlib,zipfile,shutil
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/ui-handoff-2026-09-16';PACK=OUT/'Sensen-0.11.0-UI设计交接'
items=json.loads((PACK/'界面清单.json').read_text());pages=json.loads((OUT/'pdf-pages.json').read_text());proof=json.loads((OUT/'stitch-verification.json').read_text())
assert len(items)==138 and len({i['id'] for i in items})==138
assert proof['passed'] and proof['scroll_surfaces']==56
reader=PdfReader(PACK/'街角四季-0.11.0-界面图册.pdf');assert len(reader.pages)==232
assert len(reader.outline)==138
for i,page in enumerate(reader.pages):
 text=page.extract_text();assert text and len(text)>40,i
 assert '\ufffd' not in text,i
 assert str(i+1).zfill(3) in text,i
for r in items:
 assert r['title'] and r['entry'] and r['description']
 assert (PACK/'screens'/r['image']).is_file()
 for f in r['full_images']:
  with Image.open(PACK/'full'/f['file']) as im:assert list(im.size)==f['size']
 for scroll in r['scrolls']:
  assert scroll['parts'][0]['offset']==0
  assert scroll['parts'][-1]['offset']>=scroll['max']-1
  for part in scroll['parts']:assert (PACK/'segments'/part['file']).is_file()
text=(PACK/'index.html').read_text()
for ref in re.findall(r'(?:src|href)="([^"]+)"',text):
 if not ref.startswith('#'): assert (PACK/ref).is_file(),ref
(PACK/'截图校验.json').write_text(json.dumps({'screens':138,'scroll_surfaces':56,'pdf_pages':232,'items':[{'id':r['id'],'sha256':hashlib.sha256((PACK/'screens'/r['image']).read_bytes()).hexdigest()} for r in items]},ensure_ascii=False,indent=2))
# Single forwardable package. Temporary capture APK, logs and test profiles stay outside it.
zip_path=OUT/'Sensen-0.11.0-UI美术交接.zip'
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
 for file in sorted(PACK.rglob('*')):
  if file.is_file():archive.write(file,file.relative_to(PACK.parent))
with zipfile.ZipFile(zip_path) as z:
 assert z.testzip() is None
 assert not any(n.endswith('.apk') or '/private/' in n for n in z.namelist())
(ROOT/'output/pdf').mkdir(exist_ok=True)
shutil.copyfile(PACK/'街角四季-0.11.0-界面图册.pdf',ROOT/'output/pdf/sensen-0.11.0-ui-handoff.pdf')
report={'passed':True,'screens':138,'main_screens':sum(not r['category'].startswith('09') for r in items),'appendix_screens':sum(r['category'].startswith('09') for r in items),'scroll_surfaces':56,'pdf_pages':len(reader.pages),'zip_bytes':zip_path.stat().st_size,'zip_sha256':hashlib.sha256(zip_path.read_bytes()).hexdigest(),'zip':str(zip_path)}
(OUT/'delivery-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False))
