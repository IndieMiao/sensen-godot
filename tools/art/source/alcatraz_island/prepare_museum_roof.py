"""Stage the current island plus merged-v9 roof control in an isolated project."""
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
QA = ROOT/'output/alcatraz-roof-424/project'
BASE = '02d5534768fc1a5557feaecb705b8f445562fd6b'
subprocess.run([sys.executable, str(HERE/'prepare.py')], check=True)
shutil.copytree(ROOT/'output/alcatraz-424/project', QA, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('.godot', '__pycache__'))
(QA/'baseline').mkdir(exist_ok=True)
(QA/'baseline/alc_museum.glb').write_bytes(subprocess.check_output([
    'git', 'show', BASE+':assets/landmarks/alcatraz_island/alc_museum.glb']))
shutil.copy2(HERE/'review_museum_roof.gd', QA/'review_museum_roof.gd')
(QA/'review_roof.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review_museum_roof.gd" id="1"]\n[node name="MuseumRoofReview" type="Node"]\nscript=ExtResource("1")\n')
config = (QA/'project.godot').read_text().replace('SensenAlcatraz424ArtQA', 'SensenAlcatrazRoof424ArtQA')
config = config.replace('run/main_scene="res://review.tscn"', 'run/main_scene="res://review_roof.tscn"')
(QA/'project.godot').write_text(config)
shutil.copy2(ROOT/'docs/design/alcatraz-blockout-424-2026-11-05/v9/verification.json', QA/'baseline/verification.json')
print(QA)
