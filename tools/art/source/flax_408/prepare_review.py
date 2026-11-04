"""Private pinned b1 review. Only this output copy gets the F2 scenery injection."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tarfile
import difflib

SRC=Path(__file__).resolve().parent; ROOT=SRC.parents[3]
OUT=ROOT/'output/flax-408'; PROJECT=OUT/'project'
BASE='174bf1a1027e3bd753f79e41df493d2b3ead3dfa'
PROJECT.mkdir(parents=True,exist_ok=True)
stamp=OUT/'runtime-base.json'
if not stamp.exists():
    proc=subprocess.Popen(['git','archive',BASE,'assets','modules','scenes','addons','project.godot','icon.svg'],cwd=ROOT,stdout=subprocess.PIPE)
    with tarfile.open(fileobj=proc.stdout,mode='r|') as archive: archive.extractall(PROJECT,filter='data')
    assert proc.wait()==0
    stamp.write_text(json.dumps({'runtime_commit':BASE,'art_base':'caef42a073ce20a7bb16b9414b9026316c9587f6'},indent=2)+'\n')
(PROJECT/'assets/avatar/source/.gdignore').touch()
config=ROOT/'assets/farm/art/flax_patch.glb.import'
if not config.exists():
    original=(ROOT/'assets/farm/art/sign.glb.import').read_text()
    resource='res://assets/farm/art/flax_patch.glb'
    original=original.replace('uid="uid://b8q1wqv6jr5dh"\n','')
    original=original.replace('sign.glb-959143c80868ce7aee6d834e0fe7a8f5', 'flax_patch.glb-'+hashlib.md5(resource.encode()).hexdigest())
    config.write_text(original.replace('res://assets/farm/art/sign.glb',resource))
for name in ['flax_patch.glb','flax_patch.glb.import']:
    shutil.copy2(ROOT/'assets/farm/art'/name,PROJECT/'assets/farm/art'/name)
shutil.copy2(SRC/'zz_spot_art_old.gd', PROJECT/'zz_spot_art_old.gd')
for name in ['review.gd','review_pond.gd','configure_imports.gd']: shutil.copy2(SRC/name,PROJECT/name)
relative='modules/ponds/pond_scenery.gd'
original=subprocess.check_output(['git','show',BASE+':'+relative],cwd=ROOT,text=True)
injection='\tvar flax := Art.instance("flax_patch", Vector3(7.9, 0, -1.1))\n\tflax.name = "FlaxF2"\n\tscene.add_child(flax)\n\treturn scene'
assert original.count('\treturn scene')==1
(PROJECT/relative).write_text(original.replace('\treturn scene',injection))
(OUT/'scenery-review.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True),
    (PROJECT/relative).read_text().splitlines(True),fromfile='b1/'+relative,tofile='review/'+relative)))
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="FlaxArtReview" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/'override.cfg').write_text('''[application]
config/name="SGODOT-408 isolated b1 art review"
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenFlax408ArtQA"
run/main_scene="res://review.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=960
window/size/viewport_height=900
window/size/window_width_override=960
window/size/window_height_override=900
window/stretch/mode="disabled"
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
textures/vram_compression/import_etc2_astc=false
textures/vram_compression/import_s3tc_bptc=true
[sensen]
network/online_qa=true
network/base_url="http://127.0.0.1:9/v1"
network/mobile_base_url="http://127.0.0.1:9/v1"
''')
print(PROJECT)
