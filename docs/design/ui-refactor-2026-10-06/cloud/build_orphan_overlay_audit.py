#!/usr/bin/env python3
"""Generate a read-only graph audit. Never writes/deletes Figma nodes or state."""
from pathlib import Path
import json,re
p=Path(__file__).resolve().parent;s=json.loads((p/'state.json').read_text());protected=set()
def ids(v):
 if isinstance(v,str)and re.fullmatch(r'(?:I)?\d+:\d+(?:;.*)?',v):protected.add(v)
 elif isinstance(v,dict):
  for x in v.values():ids(x)
 elif isinstance(v,list):
  for x in v:ids(x)
for key,value in s.items():
 if key.lower().endswith('screens')or key in ['screens','rows','sections','kit','components','componentSets']:ids(value)
avatar=p/'avatar/state.json'
if avatar.exists():
 a=json.loads(avatar.read_text());ids(a.get('avatar',{}).get('views',{}));ids(a.get('avatar',{}).get('saved',{}));ids(a.get('avatar',{}).get('continuations',{}));ids(a.get('avatar',{}).get('variantSet'));ids(a.get('assetFrameId'))
config={'pageId':s['pageId'],'mainScreens':s['screens'],'protectedIds':sorted(protected)}
source=(p/'orphan-overlay-audit.source.js').read_text();out=p/'orphan-overlay-audit.js';out.write_text('const AUDIT_INPUT='+json.dumps(config,separators=(',',':'))+';\n'+source);print(json.dumps({'file':str(out),'characters':len(out.read_text()),'mainScreens':len(s['screens']),'protectedIds':len(protected),'readOnly':True}))
