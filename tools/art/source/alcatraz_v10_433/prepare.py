"""SGODOT-433 v2 proposal: stage experiments under output, never runtime files."""
from pathlib import Path
import copy,hashlib,json,math,shutil,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
OUT=ROOT/'output/alcatraz-v10-433/v2';QA=OUT/'project'
plan=json.loads((HERE/'proposal.json').read_text())
assert (OUT/'prototypes/manifest.json').exists(),'Run build_prototypes.py through flock first'
subprocess.run([sys.executable,str(HERE.parent/'alcatraz_island/prepare.py')],check=True)
shutil.copytree(ROOT/'output/alcatraz-424/project',QA,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.godot','__pycache__'))
assets=QA/'assets/landmarks/alcatraz_island'
original=json.loads((assets/'layout.json').read_text());proposal=copy.deepcopy(original)
names={p['name']:p for p in proposal['placements']}
for name in plan['remove']:assert not names[name]['collision'],name
proposal['placements']=[p for p in proposal['placements'] if p['name'] not in plan['remove']]
for delta in plan['move']:
 p=names[delta['name']];assert not p['collision'],p['name'];p.update(delta)
 p['rotation_degrees']=[0,math.degrees(p['yaw']),0]
inputs=[]
for item in plan['add']:
 p=dict(item,zone='TerraceZone',collision=False,multimesh=True,surface_group=item.get('group','lookout_furnishings'),placeholder=item.get('placeholder',False))
 p.setdefault('scale',[1,1,1]);p['rotation_degrees']=[0,math.degrees(p['yaw']),0]
 proposal['placements'].append(p)
 asset=p['asset'];filename=asset+'.glb'
 if asset.startswith('coast_'):
  source=plan['plants_head']+':assets/landmarks/_shared/coast_plants/'+filename
  data=subprocess.check_output(['git','show',source]);p['owner']='赵云'
 elif asset.startswith('v10_demo_'):
  source='proposal mockup: build_prototypes.py';data=(OUT/'prototypes'/filename).read_bytes();p['owner']='马可波罗'
 elif asset.startswith('lookout_') or asset=='railing_endpost':
  source=plan['lookout_head']+':assets/landmarks/_shared/street_kit/'+filename
  data=subprocess.check_output(['git','show',source]);p['owner']='黄忠'
 else:
  source='existing island asset';data=(ROOT/'assets/landmarks/alcatraz_island'/filename).read_bytes();p['owner']='黄忠'
 (assets/filename).write_bytes(data)
 if not any(a['name']==asset for a in proposal['assets']):proposal['assets'].append({'name':asset,'file':filename,'material':'vertex_color','cast_shadow':False})
 if not any(a['asset']==asset for a in inputs):inputs.append({'asset':asset,'source':source,'sha256':hashlib.sha256(data).hexdigest()})
for key in ['navigation','route','walk_goals','camera','spawn','exit','anchors','boundaries','walk_bounds']:assert proposal[key]==original[key],key
assert [p for p in proposal['placements'] if p['collision']]==[p for p in original['placements'] if p['collision']]
assert [p for p in proposal['placements'] if p['asset'].startswith('alc_rail_')]==[p for p in original['placements'] if p['asset'].startswith('alc_rail_')]
for mode,data in [('before',original),('after',proposal)]: (QA/(mode+'.json')).write_text(json.dumps(data,separators=(',',':'))+'\n')
(assets/'layout.json').write_text(json.dumps(original,separators=(',',':'))+'\n')
for source,target in [(HERE/'review.gd','proposal_review.gd'),(HERE/'proposal.json','proposal.json'),(ROOT/'docs/design/alcatraz-blockout-424-2026-11-05/v9/verification.json','baseline_views.json')]:shutil.copy2(source,QA/target)
(QA/'proposal_review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://proposal_review.gd" id="1"]\n[node name="ProposalReview" type="Node"]\nscript=ExtResource("1")\n')
config=(QA/'project.godot').read_text().replace('SensenAlcatraz424ArtQA','SensenAlcatrazV10Proposal433V2').replace('run/main_scene="res://review.tscn"','run/main_scene="res://proposal_review.tscn"')
(QA/'project.godot').write_text(config)
(OUT/'inputs.json').write_text(json.dumps({'island_base':plan['base'],'inputs':inputs,'collision_placements_identical':True,'cream_route_rails_identical':True,'navigation_and_camera_identical':True,'limits':'Proposal only; coast plants and generated new focal props are provisional.'},indent=2)+'\n')
print(QA)
