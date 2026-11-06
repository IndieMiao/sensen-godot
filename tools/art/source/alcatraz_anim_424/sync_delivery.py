"""Copy only our native Godot resources/import and regenerate motion manifest."""
from pathlib import Path
import json,hashlib
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/landmarks/alcatraz_island';OUT=ROOT/'output/alcatraz-anim-424';P=OUT/'project/assets/landmarks/alcatraz_island'
for name in ['gull.tscn','ferry.tscn','gull_animations.tres','ferry_animations.tres','ferry_flag.glb.import']:
 assert 'uid://' in (P/name).read_text();(KIT/name).write_bytes((P/name).read_bytes())
r=json.loads((OUT/'captures/godot-validation.json').read_text());flag=json.loads((SRC/'flag_measurement.json').read_text())
m={'task':'SGODOT-424','revision':'v1','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','baseline':'996528d3a273d773e1e2168361ac79a1da9f15c4','gull':{'scene':'gull.tscn','mesh':'gull.glb','triangles':284,'surfaces':1,'idle_s':8.5,'quiet_fraction':r['motion']['quiet_fraction'],'shape_targets':['preen','spread','turn_head'],'autoplay':False,'root_motion':False,'instances':3,'phase_policy':'Caller randomizes start once per independent instance; stratified offsets recommended'},'ferry':{'scene':'ferry.tscn','near':'ferry.glb','far':'ferry_far.glb','lod_distance_m':55,'idle_s':4,'bob_amplitude_m':.02,'animated_node':'BodyRig','root_motion':False,'autoplay':False,'flag':flag,'near_active_triangles':5196,'far_active_triangles':1532,'active_surfaces':2},'placements_source':'b16c3198 unchanged ferry_gull_manifest.json placements','interaction':{'clickable':False,'collision':False,'lights':False,'cameras':False},'native_resource_sha256':{name:hashlib.sha256((KIT/name).read_bytes()).hexdigest() for name in ['gull.tscn','ferry.tscn','gull_animations.tres','ferry_animations.tres','gull.glb','ferry_flag.glb']}}
(KIT/'alcatraz_anim_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
print('SYNCED animation assets and manifest')
