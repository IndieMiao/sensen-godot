"""Stage a pinned, isolated b1 pond; only the art fixture is changed locally."""
from pathlib import Path
import json,shutil,subprocess,tarfile
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/wild-422';PROJECT=QA/'project'
BASE='a43500f36c1b5a13729187c686e0f68a2011fbad'
PROJECT.mkdir(parents=True,exist_ok=True);(ROOT/'output/.gdignore').touch()
if not (QA/'stage.json').exists():
 proc=subprocess.Popen(['git','archive',BASE],cwd=ROOT,stdout=subprocess.PIPE)
 with tarfile.open(fileobj=proc.stdout,mode='r|') as ar:ar.extractall(PROJECT,filter='data')
 assert proc.wait()==0
 (PROJECT/'docs/.gdignore').touch();(PROJECT/'tools/art/source/.gdignore').touch()
 (QA/'stage.json').write_text(json.dumps(dict(runtime_head=BASE,art_base='93befb18cd5af7e30a966d2c112279287b71b3e2',scope='Private P0Pond fixture, native lighting/player/HUD/camera. No runtime gameplay files committed.'),indent=2)+'\n')
stats=json.loads((HERE/'asset_stats.json').read_text())
for name in list(stats['assets'])+['flax_patch','reed_bank','hardwood_grove']:
 for suffix in ['.glb','.glb.import']:
  path=ROOT/'assets/farm/art'/(name+suffix)
  if path.exists():shutil.copy2(path,PROJECT/'assets/farm/art'/path.name)
for name in ['hardwood_grove_import.gd','hardwood_grove_import.gd.uid']:
 path=ROOT/'assets/farm/art'/name
 if path.exists():shutil.copy2(path,PROJECT/'assets/farm/art'/name)
for name in ['review.gd','review_pond.gd','configure.gd','scatter.gd','perimeter_trees.gd','density.json']:
 if (HERE/name).exists():shutil.copy2(HERE/name,PROJECT/name)
shutil.copy2(HERE/'reference/pond_slots_v2.json',PROJECT/'pond_slots_v2.json')
shutil.copy2(ROOT/'tools/art/source/reed_clay_416/reference/zz_spot_art_old.gd',PROJECT/'zz_spot_art_old.gd')
shutil.copy2(HERE/'asset_stats.json',PROJECT/'wild_asset_stats.json')
# Retain the native meadow plane/turf. Legacy flower/bush batches are replaced by the
# proposed decorations, so old blue flowers cannot be confused with the flax fixture.
p=PROJECT/'modules/ponds/pond_scenery.gd'
original=subprocess.check_output(['git','show',BASE+':modules/ponds/pond_scenery.gd'],cwd=ROOT,text=True)
original=original.replace('for asset in layers: scene.add_child(Art.batch(asset, layers[asset], asset == "bush"))','for asset in ["grass_clump"]: scene.add_child(Art.batch(asset, layers[asset], false))')
p.write_text(original)
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="Wild422Review" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/'override.cfg').write_text('''[application]
config/name="ZhaoyunWild422QA"
config/use_custom_user_dir=true
config/custom_user_dir_name="ZhaoyunWild422QA"
run/main_scene="res://review.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=720
window/size/viewport_height=800
window/size/window_width_override=720
window/size/window_height_override=800
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
textures/vram_compression/import_s3tc_bptc=true
[sensen]
network/online_qa=true
network/base_url="http://127.0.0.1:9/v1"
network/mobile_base_url="http://127.0.0.1:9/v1"
''')
print(PROJECT)
