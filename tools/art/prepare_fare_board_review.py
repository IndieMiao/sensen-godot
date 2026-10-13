#!/usr/bin/env python3
"""Stage the existing Post Office with an isolated Fare Board review fixture."""
from pathlib import Path
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'output/fare-board-275/project'
subprocess.run([sys.executable,str(ROOT/'tools/dev/scene_bench/prepare.py'),
                'post_office','--output','output/fare-board-275/project'],check=True,cwd=ROOT)
p=DEST/'project.godot'
p.write_text(p.read_text().replace('SensenSceneBench','SensenFareBoard275QA').replace(
    'res://tools/dev/scene_bench/scene_bench.tscn','res://review.tscn'))
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n'
    '[ext_resource type="Script" path="res://review.gd" id="1"]\n'
    '[node name="FareBoardReview" type="Node"]\nscript = ExtResource("1")\n')
shutil.copy2(ROOT/'tools/art/review_fare_board.gd',DEST/'review.gd')
(DEST/'review-data').mkdir(exist_ok=True)
for name in ['asset-contract.json','atlas-swatches.json']:
    shutil.copy2(ROOT/'tools/art/source/fare_board_275'/name,DEST/'review-data'/name)
