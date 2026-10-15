#!/usr/bin/env python3
"""Stage isolated review; #434 pots pinned, no live anchors/accounts altered."""
from pathlib import Path
import subprocess,shutil,json
ROOT=Path(__file__).resolve().parents[2];DEST=ROOT/'output/kitchen-213/project';POT='ddcd8b3c5b70aded6676d15a51d8bb6851010854'
subprocess.run(['python',str(ROOT/'tools/dev/scene_bench/prepare.py'),'basic_room','--output','output/kitchen-213/project'],cwd=ROOT,check=True)
shutil.copytree(ROOT/'assets/props/warming_cabinet',DEST/'assets/props/warming_cabinet',dirs_exist_ok=True)
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',POT,'assets/props/stove_pot'],cwd=ROOT,text=True).splitlines()
for relative in paths:
 p=DEST/relative;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(subprocess.check_output(['git','show',POT+':'+relative],cwd=ROOT))
p=DEST/'project.godot';p.write_text(p.read_text().replace('SensenSceneBench','SensenKitchen213QA').replace('res://tools/dev/scene_bench/scene_bench.tscn','res://review.tscn'))
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="Kitchen213Review" type="Node"]\nscript = ExtResource("1")\n')
shutil.copy2(ROOT/'tools/art/review_kitchen_213.gd',DEST/'review.gd');shutil.copy2(ROOT/'tools/art/source/kitchen_213/contract.json',DEST/'contract.json')
print(DEST)
