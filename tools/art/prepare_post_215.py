#!/usr/bin/env python3
"""Prepare isolated Vulkan review of 215 and the supplemental 213 cam_stove.
All current runtime dependencies are pinned; no live anchors/save files edited.
"""
from pathlib import Path
import json,subprocess,shutil
ROOT=Path(__file__).resolve().parents[2];FARM='f8c3391c8c0606ae664fb8e06ad85068aa199f69';DEST=ROOT/'output/post-215/project'
def gitfile(rel):
 p=DEST/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(subprocess.check_output(['git','show',FARM+':'+rel],cwd=ROOT))
subprocess.run(['python',str(ROOT/'tools/dev/scene_bench/prepare.py'),'post_office','--output','output/post-215/project'],cwd=ROOT,check=True)
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',FARM,'assets/rooms/basic_room','scenes/basic_room','assets/props/warming_cabinet','assets/props/stove_pot','scenes/room_effects'],cwd=ROOT,text=True).splitlines()
for f in paths:gitfile(f)
for f in ['assets/p0/rooms/farmhouse.anchors.json','assets/p0/outposts/post.anchors.json','assets/p0/outpost_npcs.json']:gitfile(f)
npcs=json.loads((DEST/'assets/p0/outpost_npcs.json').read_text())['npcs'];ids=set(['body00','eyes00','hairhat0','cloth0','shoes0'])
for key in ['res_pip','res_sam','sigrid']:ids.update(npcs[key]['slots'].values())
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',FARM,'assets/avatar/parts','assets/avatar/source'],cwd=ROOT,text=True).splitlines()
for f in paths:
 if (f.startswith('assets/avatar/parts/') and any(Path(f).name in [i+'.res',i+'_scene.tscn'] for i in ids)) or (f.endswith('.png') and any('/'+i+'/' in f for i in ids)):gitfile(f)
manifest=json.loads(subprocess.check_output(['git','show',FARM+':assets/avatar/parts_manifest.json'],cwd=ROOT));manifest['parts']=[p for p in manifest['parts'] if p['id'] in ids];(DEST/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
p=DEST/'project.godot';p.write_text(p.read_text().replace('SensenSceneBench','SensenPost215Review').replace('res://tools/dev/scene_bench/scene_bench.tscn','res://review.tscn'))
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="Post215Review" type="Node"]\nscript=ExtResource("1")\n')
shutil.copy2(ROOT/'tools/art/review_post_215.gd',DEST/'review.gd')
print(DEST)
