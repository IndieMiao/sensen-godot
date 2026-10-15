#!/usr/bin/env python3
"""Stage isolated actual room kits and avatar, without game saves or networking."""
from pathlib import Path
import shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];DEST=ROOT/'output/stove-pot-282/project'
subprocess.run([sys.executable,str(ROOT/'tools/dev/scene_bench/prepare.py'),'standard_room_5','--output','output/stove-pot-282/project'],check=True,cwd=ROOT)
for path in ['scenes/basic_room','scenes/deluxe_room_10','assets/rooms/basic_room','assets/rooms/deluxe_room_10','assets/props/warming_cabinet','assets/props/stove_pot']:
 shutil.copytree(ROOT/path,DEST/path,dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.blend'))
p=DEST/'project.godot';p.write_text(p.read_text().replace('SensenSceneBench','SensenStovePot282QA').replace('res://tools/dev/scene_bench/scene_bench.tscn','res://review.tscn'))
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="StovePotReview" type="Node"]\nscript = ExtResource("1")\n')
shutil.copy2(ROOT/'tools/art/review_stove_pot.gd',DEST/'review.gd');shutil.copy2(ROOT/'tools/art/source/stove_pot_282/review-fixture.json',DEST/'review-fixture.json')
# Approved review fixture: remove ONLY the merged old stove kettle. Source
# assets and anchors are untouched; runtime integration needs the same cleanup.
from prepare_stove_pot_deluxe_fixture import prepare
prepare(DEST/'assets/rooms/deluxe_room_10/kitchen_fittings.glb')
print(DEST)
