"""SGODOT-433 proposal: stage experiments under output, never runtime files."""
from pathlib import Path
import copy
import hashlib
import json
import math
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = ROOT/'output/alcatraz-v10-433'
QA = OUT/'project'
plan = json.loads((HERE/'proposal.json').read_text())
subprocess.run([sys.executable, str(HERE.parent/'alcatraz_island/prepare.py')], check=True)
shutil.copytree(ROOT/'output/alcatraz-424/project', QA, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('.godot','__pycache__'))
assets = QA/'assets/landmarks/alcatraz_island'
original = json.loads((assets/'layout.json').read_text())
proposal = copy.deepcopy(original)
names = {p['name']:p for p in proposal['placements']}
for name in plan['remove']:
    assert not names[name]['collision'], name
proposal['placements'] = [p for p in proposal['placements'] if p['name'] not in plan['remove']]
for delta in plan['move']:
    p = names[delta['name']]
    assert not p['collision'], p['name']
    p.update(delta)
    p['rotation_degrees'] = [0, math.degrees(p['yaw']), 0]
inputs = []
for item in plan['add']:
    p = dict(item, zone='TerraceZone', scale=[1,1,1], collision=False, multimesh=True,
             surface_group='lookout_furnishings', placeholder=False, owner='黄忠')
    p['rotation_degrees'] = [0, math.degrees(p['yaw']), 0]
    proposal['placements'].append(p)
    data = subprocess.check_output(['git','show',plan['lookout_head']+':assets/landmarks/_shared/street_kit/'+p['asset']+'.glb'])
    # QA-only aliases permit the existing island loader; production paths stay exact.
    (assets/(p['asset']+'.glb')).write_bytes(data)
    if not any(a['name']==p['asset'] for a in proposal['assets']):
        proposal['assets'].append({'name':p['asset'],'file':p['asset']+'.glb','material':'vertex_color',
                                  'cast_shadow':False})
        inputs.append({'asset':p['asset'],'head':plan['lookout_head'],'sha256':hashlib.sha256(data).hexdigest()})
for name in ['lookout_railing_2m','railing_endpost']:
    data = subprocess.check_output(['git','show',plan['lookout_head']+':assets/landmarks/_shared/street_kit/'+name+'.glb'])
    (assets/(name+'.glb')).write_bytes(data)
    if not any(row['asset']==name for row in inputs):
        inputs.append({'asset':name,'head':plan['lookout_head'],'sha256':hashlib.sha256(data).hexdigest()})
for key in ['navigation','route','walk_goals','camera','spawn','exit','anchors','boundaries','walk_bounds']:
    assert proposal[key] == original[key], key
assert [p for p in proposal['placements'] if p['collision']] == [p for p in original['placements'] if p['collision']]
for mode,data in [('before',original),('after',proposal)]:
    (QA/(mode+'.json')).write_text(json.dumps(data,separators=(',',':'))+'\n')
(assets/'layout.json').write_text(json.dumps(original,separators=(',',':'))+'\n')
shutil.copy2(HERE/'review.gd',QA/'proposal_review.gd')
shutil.copy2(HERE/'proposal.json',QA/'proposal.json')
shutil.copy2(ROOT/'docs/design/alcatraz-blockout-424-2026-11-05/v9/verification.json',QA/'baseline_views.json')
(QA/'proposal_review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://proposal_review.gd" id="1"]\n[node name="ProposalReview" type="Node"]\nscript=ExtResource("1")\n')
config = (QA/'project.godot').read_text().replace('SensenAlcatraz424ArtQA','SensenAlcatrazV10Proposal433')
config = config.replace('run/main_scene="res://review.tscn"','run/main_scene="res://proposal_review.tscn"')
(QA/'project.godot').write_text(config)
(OUT/'inputs.json').write_text(json.dumps({'island_base':plan['base'],'lookout_inputs':inputs,
    'collision_placements_identical':True,'navigation_and_camera_identical':True,
    'limits':'Proposal only. Lookout kit has two upstream visual corrections pending.'},indent=2)+'\n')
print(QA)
