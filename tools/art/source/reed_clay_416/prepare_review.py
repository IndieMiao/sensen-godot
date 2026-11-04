"""Private b1 pond review with pinned, unmodified comparison assets."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tarfile

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/reed-clay-416';PROJECT=OUT/'project'
BASE='67116c6df4f69062ce658c50581e72ab1779a1b4';ART_BASE='e7469d07390c7a75bc56fa18a7fec69a3b41bbb9'
FLAX='c017910220cc74c51e54834806b2e915b330d8a1';HARDWOOD='aee148bfd72fe1874063e3048d0d67152dea3b3f'
PROJECT.mkdir(parents=True,exist_ok=True)
stamp=OUT/'runtime-base.json'
if not stamp.exists():
    proc=subprocess.Popen(['git','archive',BASE,'assets','modules','scenes','addons','project.godot','icon.svg'],cwd=ROOT,stdout=subprocess.PIPE)
    with tarfile.open(fileobj=proc.stdout,mode='r|') as archive:archive.extractall(PROJECT,filter='data')
    assert proc.wait()==0
    critical=['scenes/p0/p0_pond.gd','scenes/p0/p0_ui.gd','modules/farm/farm_art.gd','modules/mining/mine_mesh.gd','modules/farm/crop_plant_mesh.gd']
    stamp.write_text(json.dumps({'runtime_commit':BASE,'art_base':ART_BASE,
        'files':{p:hashlib.sha256((PROJECT/p).read_bytes()).hexdigest() for p in critical}},indent=2)+'\n')
(PROJECT/'assets/avatar/source/.gdignore').touch()
for name in ['reed_bank','clay_pit']:
    cfg=ROOT/'assets/farm/art'/(name+'.glb.import')
    if not cfg.exists():
        original=(ROOT/'assets/farm/art/sign.glb.import').read_text().replace('uid="uid://b8q1wqv6jr5dh"\n','')
        resource='res://assets/farm/art/'+name+'.glb'
        original=original.replace('sign.glb-959143c80868ce7aee6d834e0fe7a8f5',name+'.glb-'+hashlib.md5(resource.encode()).hexdigest())
        cfg.write_text(original.replace('res://assets/farm/art/sign.glb',resource))
    for suffix in ['.glb','.glb.import']:shutil.copy2(ROOT/'assets/farm/art'/(name+suffix),PROJECT/'assets/farm/art'/(name+suffix))
comparison={}
for revision,names in [(FLAX,['flax_patch.glb','flax_patch.glb.import']),
                       (HARDWOOD,['hardwood_grove.glb','hardwood_grove.glb.import','hardwood_grove_import.gd','hardwood_grove_import.gd.uid'])]:
    for name in names:
        relative='assets/farm/art/'+name
        payload=subprocess.check_output(['git','show',revision+':'+relative],cwd=ROOT)
        (PROJECT/relative).write_bytes(payload)
        comparison[relative]={'commit':revision,'sha256':hashlib.sha256(payload).hexdigest()}
snapshot=json.loads(stamp.read_text());snapshot['comparison_assets']=comparison;snapshot['art_base']=ART_BASE
stamp.write_text(json.dumps(snapshot,indent=2)+'\n')
for name in ['review.gd','review_pond.gd','review_spot_factory.gd','configure_imports.gd']:
    shutil.copy2(SRC/name,PROJECT/name)
shutil.copy2(SRC/'reference/zz_spot_art_old.gd',PROJECT/'scenes/p0/zz_spot_art_old.gd')
mock=(SRC/'reference/pond_scenery.mock2.gd').read_text()
mock=mock.replace('load("res://scenes/p0/zz_spot_art_old.gd")','load("res://review_spot_factory.gd")')
(PROJECT/'modules/ponds/pond_scenery.gd').write_text(mock)
slots={'pond_san_francisco_03':[['spot_reed_bank',-.3,-6.6,0,1]],
       'pond_san_francisco_01':[['spot_clay_bank',7.6,-1.4,0,1]]}
(PROJECT/'zz_slots.json').write_text(json.dumps(slots,indent=2)+'\n')
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="ReedClayReview" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/'override.cfg').write_text('''[application]
config/name="SGODOT-416 isolated b1 review"
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenReedClay416ArtQA"
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
