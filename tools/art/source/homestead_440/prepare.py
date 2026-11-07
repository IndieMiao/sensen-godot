"""Stage the real pinned farm in an isolated project. No production checkout or saves."""
from pathlib import Path
import subprocess,tarfile,shutil,json,hashlib
ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent
OUT=ROOT/'output/homestead-440';QA=OUT/'project'
REF=json.loads((SRC/'reference/provenance.json').read_text())['runtime_reference']
QA.mkdir(parents=True,exist_ok=True);(OUT.parent/'.gdignore').touch()
if not (QA/'PINNED_SOURCE.txt').exists():
 proc=subprocess.Popen(['git','archive',REF,'assets','modules','scenes','addons','project.godot','icon.svg','icon.svg.import','tests/p0/fixtures/home_view_355.json'],cwd=ROOT,stdout=subprocess.PIPE)
 with tarfile.open(fileobj=proc.stdout,mode='r|') as tar:tar.extractall(QA,filter='data')
 assert proc.wait()==0
 (QA/'PINNED_SOURCE.txt').write_text(REF+'\n')
# User data and every network transport are isolated by review.gd before the real farm starts.
# Start from the pinned configuration every time, so staging is idempotent.
project=subprocess.check_output(['git','show',REF+':project.godot'],cwd=ROOT,text=True)
import re
project=re.sub(r'run/main_scene=.*', 'run/main_scene="res://review.tscn"',project)
project=re.sub(r'config/name=.*','config/name="Homestead 440 Offline Art Review"',project)
project=re.sub(r'config/custom_user_dir_name=.*','config/custom_user_dir_name="SensenHomestead440QA"',project)
if 'config/custom_user_dir_name=' not in project:project=project.replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="SensenHomestead440QA"')
project=re.sub(r'window/size/viewport_width=.*','window/size/viewport_width=360',project)
project=re.sub(r'window/size/viewport_height=.*','window/size/viewport_height=800',project)
project=re.sub(r'window/size/window_width_override=.*','window/size/window_width_override=360',project)
project=re.sub(r'window/size/window_height_override=.*','window/size/window_height_override=800',project)
project=re.sub(r'\[editor_plugins\]\s*enabled=.*', '[editor_plugins]\nenabled=PackedStringArray()',project)
project += '\n[sensen]\nnetwork/online_qa=true\n'
(QA/'project.godot').write_text(project)
(QA/'assets/p0/demo_server.json').unlink(missing_ok=True)
for name in ['master_farmhouse_a','master_farmhouse_b']:
 for suffix in ['.glb','.glb.import']:
  p=ROOT/'assets/farm/art'/(name+suffix)
  if p.exists():shutil.copy2(p,QA/'assets/farm/art'/p.name)
for name in ['porch_a','porch_b','kitchen_wing_a','kitchen_wing_b']:
 for suffix in ['.glb','.glb.import']:
  p=SRC/'reference/439'/(name+suffix);shutil.copy2(p,QA/'assets/farm/art'/p.name)
for name in ['review.gd','review.tscn','verify.gd','review-view.json']:
 if (SRC/name).exists():shutil.copy2(SRC/name,QA/name)
print(QA)
