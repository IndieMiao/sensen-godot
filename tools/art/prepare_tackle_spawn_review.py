#!/usr/bin/env python3
"""Stage a spawn-follow art review with the existing, pinned Finn outfit.

Reads farm-dev resources from Git; never checks them out over the art branch.
The original standalone room/benchmark project is reused.
"""
from pathlib import Path
import subprocess,json,sys,shutil,hashlib
ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'output/tackle-214/project'
REV='f8c3391c8c0606ae664fb8e06ad85068aa199f69'
def git_file(path):return subprocess.check_output(['git','show',REV+':'+path],cwd=ROOT)
if not (DEST/'project.godot').exists():
    subprocess.run([sys.executable,str(ROOT/'tools/art/prepare_tackle_shop_review.py')],check=True)
source=json.loads(git_file('assets/p0/outpost_npcs.json'))
finn=source['npcs']['finn']
catalog=json.loads(git_file('assets/avatar/parts_manifest.json'))
manifest=json.loads((DEST/'assets/avatar/parts_manifest.json').read_text())
required=set(finn['slots'].values())
manifest['parts']=[p for p in manifest['parts'] if p['id'] not in required]
extra=[p for p in catalog['parts'] if p['id'] in required]
assert len(extra)==len(required)
manifest['parts'].extend(extra)
(DEST/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
queue=[p['res'] for p in extra];seen=set();copied={}
scanner=DEST/'spawn_dependency_scan.gd'
scanner.write_text('''extends SceneTree
func _initialize():
 var paths=JSON.parse_string(FileAccess.get_file_as_string("res://spawn-dependencies.json"))
 var out={}
 for p in paths:
  out[p]=Array(ResourceLoader.get_dependencies(p))
 FileAccess.open("res://spawn-dependency-result.json",FileAccess.WRITE).store_string(JSON.stringify(out))
 quit()
''')
while queue:
    batch=[]
    for resource in queue:
        if resource in seen:continue
        seen.add(resource);relative=resource.removeprefix('res://');target=DEST/relative
        if resource in [p['res'] for p in extra] or not target.exists():
            payload=git_file(relative);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(payload)
            copied[relative]=hashlib.sha256(payload).hexdigest()
        if target.suffix in ('.res','.tres','.scn','.tscn'):batch.append(resource)
    if not batch:break
    (DEST/'spawn-dependencies.json').write_text(json.dumps(batch))
    result=subprocess.run(['godot','--headless','--path',str(DEST),'--script','res://spawn_dependency_scan.gd'],capture_output=True,text=True)
    if result.returncode:raise RuntimeError(result.stdout+result.stderr)
    found=json.loads((DEST/'spawn-dependency-result.json').read_text())
    queue=[d.split('::')[-1] for dependencies in found.values() for d in dependencies if d.split('::')[-1].startswith('res://')]
fixture={'source_revision':REV,'finn':finn,'copied_resource_sha256':copied,
         'camera_contract':'Requested spawn-centered follow; 43 degree pitch; kit yaw; 6.72 m width; no fixed-room focus or fitting.'}
(DEST/'spawn-review-fixture.json').write_text(json.dumps(fixture,ensure_ascii=False,indent=2)+'\n')
shutil.copy2(ROOT/'tools/art/review_tackle_shop.gd',DEST/'review_tackle_shop.gd')
shutil.copy2(ROOT/'tools/art/review_tackle_spawn.gd',DEST/'spawn_review.gd')
(DEST/'spawn_review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://spawn_review.gd" id="1"]\n[node name="SpawnFollowReview" type="Node"]\nscript = ExtResource("1")\n')
print('SPAWN_REVIEW_STAGED',len(copied),'Finn resources from',REV)
