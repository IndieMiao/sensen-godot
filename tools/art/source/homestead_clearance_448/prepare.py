"""Stage the actual enabled #896 scene offline; never move Bench or alter navigation.
Run once before import/render. It intentionally does not start Godot or Blender.
"""
from pathlib import Path
import json,re,shutil,subprocess,tarfile
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent;Q=ROOT/'output/homestead-448';P=Q/'project'
REF='b46c6ea7531b6adfacd2b8c9854861f30578c18e'
NAMES=['porch_a','porch_b','kitchen_wing_a','kitchen_wing_b','master_farmhouse_a','master_farmhouse_b']
Q.mkdir(exist_ok=True,parents=True)
if not (Q/'runtime-stage.json').exists():
 assert not P.exists(),'Use an empty isolated output project'
 P.mkdir();proc=subprocess.Popen(['git','archive',REF],cwd=ROOT,stdout=subprocess.PIPE)
 with tarfile.open(fileobj=proc.stdout,mode='r|') as archive:archive.extractall(P,filter='data')
 assert proc.wait()==0
 (Q/'runtime-stage.json').write_text(json.dumps({'reference':REF,'scope':'Actual #896 enabled looks, isolated QA only; never move bench or scenery'},indent=2)+'\n')
assert json.loads((Q/'runtime-stage.json').read_text())['reference']==REF
(P/'docs/.gdignore').touch();(P/'tools/art/source/.gdignore').touch();(P/'qa_before').mkdir(exist_ok=True)
subprocess.run(['python3',str(SRC/'imports.py'),'stage'],cwd=ROOT,check=True)
for name in NAMES:
 for ext in ['.glb','.glb.import']:shutil.copy2(ROOT/'assets/farm/art'/(name+ext),P/'assets/farm/art'/(name+ext))
 shutil.copy2(Q/'before'/(name+'.glb'),P/'qa_before'/(name+'.glb'))
 # A separate UID for old mesh; use the same current import settings.
 old=P/'qa_before'/(name+'.glb.import')
 if not old.exists():
  config=(ROOT/'assets/farm/art'/(name+'.glb.import')).read_text()
  config=re.sub(r'^uid=.*\n','',config,flags=re.M).replace('res://assets/farm/art/','res://qa_before/')
  old.write_text(config)
(P/'override.cfg').write_text('''[application]
config/name="ZhaoyunHomestead448"
config/use_custom_user_dir=true
config/custom_user_dir_name="ZhaoyunHomestead448"
run/main_scene="res://review_448.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=360
window/size/viewport_height=800
window/size/window_width_override=360
window/size/window_height_override=800
[sensen]
network/base_url="http://127.0.0.1:9/v1"
network/mobile_base_url="http://127.0.0.1:9/v1"
''')
for a,b in [('review.gd','review_448.gd'),('review_farm.gd','review_farm.gd')]:shutil.copy2(SRC/a,P/b)
(P/'review_448.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review_448.gd" id="1"]\n[node name="Review448" type="Node"]\nscript=ExtResource("1")\n')
for name in ['make_views.ts','audit_decor.ts']:shutil.copy2(SRC/name,Q/name)
print(P,'staged; generate fixtures, import, then render under flock')
