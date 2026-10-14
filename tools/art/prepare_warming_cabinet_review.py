#!/usr/bin/env python3
"""Isolated Basic + Standard review with fixed source anchors; no account/save state."""
from pathlib import Path
import shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'output/warming-cabinet-282/project'
subprocess.run([sys.executable,str(ROOT/'tools/dev/scene_bench/prepare.py'),'standard_room_5','--output','output/warming-cabinet-282/project'],check=True,cwd=ROOT)
for path in ['scenes/basic_room','assets/rooms/basic_room','assets/props/warming_cabinet']:
 shutil.copytree(ROOT/path,DEST/path,dirs_exist_ok=True)
p=DEST/'project.godot';p.write_text(p.read_text().replace('SensenSceneBench','SensenWarming282QA').replace('res://tools/dev/scene_bench/scene_bench.tscn','res://review.tscn'))
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="WarmingCabinetReview" type="Node"]\nscript = ExtResource("1")\n')
shutil.copy2(ROOT/'tools/art/review_warming_cabinet.gd',DEST/'review.gd')
shutil.copy2(ROOT/'tools/art/source/warming_cabinet_282/review-fixture.json',DEST/'review-fixture.json')
# Exact import options of the existing room kit; let Godot generate unique UIDs.
for variant in ['a','b']:
 path=DEST/f'assets/props/warming_cabinet/warming_cabinet_{variant}.glb.import'
 if not path.exists():
  path.write_text('[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n[params]\nnodes/root_scale=1.0\nnodes/apply_root_scale=true\nmeshes/generate_lods=false\nmeshes/force_disable_compression=true\ngltf/embedded_image_handling=1\n')
print(DEST)
