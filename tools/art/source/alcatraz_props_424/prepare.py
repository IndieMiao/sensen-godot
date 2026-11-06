"""Pin Marco Polo's complete walkable blockout; replace only our ten GLBs in a QA copy."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tarfile
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/alcatraz-props-424';PROJECT=QA/'project'
BLOCKOUT='34df9c0b6af42a85567dfb5318c6717f929a4ab8';KIT='assets/landmarks/alcatraz_island/'
parser=argparse.ArgumentParser();parser.add_argument('--sync-imports',action='store_true');args=parser.parse_args()
stats=json.loads((HERE/'asset_stats.json').read_text())
if args.sync_imports:
 for name in stats['assets']:shutil.copy2(PROJECT/KIT/(name+'.glb.import'),ROOT/KIT/(name+'.glb.import'))
 raise SystemExit()
PROJECT.mkdir(parents=True,exist_ok=True);(ROOT/'output/.gdignore').touch()
if not (QA/'stage.json').exists():
 proc=subprocess.Popen(['git','archive',BLOCKOUT],cwd=ROOT,stdout=subprocess.PIPE)
 with tarfile.open(fileobj=proc.stdout,mode='r|') as ar:ar.extractall(PROJECT,filter='data')
 assert proc.wait()==0
 (PROJECT/'docs/.gdignore').touch();(PROJECT/'tools/art/source/.gdignore').touch()
 original={p:hashlib.sha256((PROJECT/p).read_bytes()).hexdigest() for p in [KIT+'layout.json','scenes/landmark/alcatraz_island.gd','scenes/landmark/alcatraz_island.tscn']}
 (QA/'stage.json').write_text(json.dumps({'blockout_commit':BLOCKOUT,'art_base':subprocess.check_output(['git','rev-parse','origin/wp-3d-scene'],cwd=ROOT,text=True).strip(),'unchanged_blockout_files':original},indent=2)+'\n')
for name in stats['assets']:
 shutil.copy2(ROOT/KIT/(name+'.glb'),PROJECT/KIT/(name+'.glb'))
 if (ROOT/KIT/(name+'.glb.import')).exists():shutil.copy2(ROOT/KIT/(name+'.glb.import'),PROJECT/KIT/(name+'.glb.import'))
 # Keep the original blockout UID on first import, so consumers may replace assets safely.
for name in ['review.gd','configure.gd']:
 if (HERE/name).exists():shutil.copy2(HERE/name,PROJECT/name)
shutil.copy2(HERE/'asset_stats.json',PROJECT/'prop_stats.json')
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="ZhaoyunAlcatrazPropsReview" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/'project.godot').write_text('''config_version=5
[application]
config/name="ZhaoyunAlcatrazProps424QA"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="ZhaoyunAlcatrazProps424QA"
run/main_scene="res://review.tscn"
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=720
window/size/viewport_height=800
window/size/window_width_override=720
window/size/window_height_override=800
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
anti_aliasing/quality/msaa_3d=2
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
print(PROJECT)
