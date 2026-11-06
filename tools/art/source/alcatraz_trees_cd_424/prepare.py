"""Isolated published v7 island; tree replacements live only in the review script."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tarfile
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/alcatraz-trees-cd-424';PROJECT=QA/'project'
BASE='bf0c31b1c871011008b455434d167224d14de59c';KIT='assets/landmarks/alcatraz_island/'
parser=argparse.ArgumentParser();parser.add_argument('--sync-imports',action='store_true');a=parser.parse_args()
stats=json.loads((HERE/'asset_stats.json').read_text())
if a.sync_imports:
 for name in stats['assets']:shutil.copy2(PROJECT/KIT/(name+'.glb.import'),ROOT/KIT/(name+'.glb.import'))
 raise SystemExit()
PROJECT.mkdir(parents=True,exist_ok=True);(ROOT/'output/.gdignore').touch()
if not (QA/'stage.json').exists():
 proc=subprocess.Popen(['git','archive',BASE],cwd=ROOT,stdout=subprocess.PIPE)
 with tarfile.open(fileobj=proc.stdout,mode='r|') as ar:ar.extractall(PROJECT,filter='data')
 assert proc.wait()==0
 (PROJECT/'docs/.gdignore').touch();(PROJECT/'tools/art/source/.gdignore').touch()
 originals={p:hashlib.sha256((PROJECT/p).read_bytes()).hexdigest() for p in [KIT+'layout.json','scenes/landmark/alcatraz_island.gd','scenes/landmark/alcatraz_island.tscn']}
 (QA/'stage.json').write_text(json.dumps({'blockout_commit':BASE,'unchanged_files':originals,'note':'Published v7 original scene and layout retained; before/after tree replacements happen only inside the review script.'},indent=2)+'\n')
for name in stats['assets']:
 for suffix in ['.glb','.glb.import']:
  p=ROOT/KIT/(name+suffix)
  if p.exists():shutil.copy2(p,PROJECT/KIT/p.name)
for name in ['review.gd','configure.gd','lod_review.gd']:
 if (HERE/name).exists():shutil.copy2(HERE/name,PROJECT/name)
for src,dest in [('asset_stats.json','trees_cd_stats.json'),('suggested_replacements.json','trees_cd_replacements.json')]:
 if (HERE/src).exists():shutil.copy2(HERE/src,PROJECT/dest)
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="AlcatrazTreesCD424Review" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/'project.godot').write_text('''config_version=5
[application]
config/name="ZhaoyunAlcatrazTreesCD424QA"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="ZhaoyunAlcatrazTreesCD424QA"
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

lod={'assets':{}}
for name,e in stats['assets'].items():
 if name.endswith('_far'):
  n=name.removesuffix('_far');lod['assets'][name]={**e,'near':n,'near_triangles':stats['assets'][n]['triangles'],'near_bounds':stats['assets'][n]['bounds']}
(PROJECT/'lod_stats.json').write_text(json.dumps(lod,indent=2)+'\n')
(PROJECT/'lod_review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://lod_review.gd" id="1"]\n[node name="TreeCDLODReview" type="Node"]\nscript=ExtResource("1")\n')
