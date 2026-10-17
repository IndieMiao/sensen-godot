#!/usr/bin/env python3
"""Stage the real P0RoomNav and its code dependencies for isolated art QA."""
from pathlib import Path
import re,json,subprocess,shutil,hashlib
ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'output/tackle-214/project'
REV='f8c3391c8c0606ae664fb8e06ad85068aa199f69'
relative=Path('modules/p0/p0_room_nav.gd')
payload=subprocess.check_output(['git','show',REV+':'+str(relative)],cwd=ROOT)
target=DEST/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(payload)
index={}
for path in (ROOT/'modules').rglob('*.gd'):
    content=path.read_text();match=re.search(r'^class_name\s+(\w+)',content,re.M)
    if match:index[match[1]]=path
pending=[ROOT/'modules/blueprint/blueprint.gd'];seen=set()
files={str(relative):hashlib.sha256(payload).hexdigest()}
while pending:
    path=pending.pop()
    if path in seen:continue
    seen.add(path);relative=path.relative_to(ROOT);target=DEST/relative
    target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
    files[str(relative)]=hashlib.sha256(path.read_bytes()).hexdigest()
    if path.suffix not in ('.gd','.gdshader','.gdshaderinc'):continue
    content=path.read_text()
    for name,dependency in index.items():
        if dependency not in seen and re.search(r'\b'+name+r'\b',content):pending.append(dependency)
    for match in re.findall(r'["\']res://([^"\']+)["\']',content):
        dependency=ROOT/match
        if dependency.is_file() and dependency not in seen:pending.append(dependency)
fixture={'nav_revision':REV,'nav_path':'modules/p0/p0_room_nav.gd','staged_source_sha256':files}
(DEST/'nav-review-sources.json').write_text(json.dumps(fixture,indent=2)+'\n')
shutil.copy2(ROOT/'tools/art/verify_tackle_assembly.gd',DEST/'verify_tackle_assembly.gd')
print('NATIVE_NAV_STAGED',len(files),'files')
