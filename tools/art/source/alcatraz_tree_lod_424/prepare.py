"""Minimal isolated native visibility_range test. No scene or production LOD changes."""
from pathlib import Path
import argparse,hashlib,json,shutil
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/alcatraz-tree-lod-424';PROJECT=QA/'project';KIT='assets/landmarks/alcatraz_island'
p=argparse.ArgumentParser();p.add_argument('--sync-imports',action='store_true');a=p.parse_args();stats=json.loads((HERE/'asset_stats.json').read_text())
if a.sync_imports:
 for name in stats['assets']:shutil.copy2(PROJECT/KIT/(name+'.glb.import'),ROOT/KIT/(name+'.glb.import'))
 raise SystemExit()
(PROJECT/KIT).mkdir(parents=True,exist_ok=True);(ROOT/'output/.gdignore').touch()
names=list(stats['assets'])+[a['near'] for a in stats['assets'].values()]
for name in names:
 for suffix in ['.glb','.glb.import']:
  path=ROOT/KIT/(name+suffix)
  if path.exists():shutil.copy2(path,PROJECT/KIT/path.name)
for name in ['review.gd','configure.gd']:
 if (HERE/name).exists():shutil.copy2(HERE/name,PROJECT/name)
shutil.copy2(HERE/'asset_stats.json',PROJECT/'lod_stats.json')
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="TreeLOD424Review" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/'project.godot').write_text('''config_version=5
[application]
config/name="ZhaoyunAlcatrazTreeLOD424QA"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="ZhaoyunAlcatrazTreeLOD424QA"
run/main_scene="res://review.tscn"
[display]
window/size/viewport_width=720
window/size/viewport_height=800
window/size/window_width_override=720
window/size/window_height_override=800
[rendering]
renderer/rendering_method="mobile"
anti_aliasing/quality/msaa_3d=2
textures/vram_compression/import_s3tc_bptc=true
''')
print(PROJECT)
