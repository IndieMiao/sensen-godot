"""Stage only the unmodified mine/avatar dependency closure and delivered monster."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil

ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent
RUNTIME=ROOT/'output/monsters-355/runtime'
parser=argparse.ArgumentParser();parser.add_argument('id');args=parser.parse_args()
OUT=ROOT/'output/monsters-355'/args.id
PROJECT=OUT/'project';PROJECT.mkdir(parents=True,exist_ok=True)
classes={}
for path in list((RUNTIME/'modules').rglob('*.gd'))+list((RUNTIME/'scenes').rglob('*.gd')):
    match=re.search(r'^class_name\s+(\w+)',path.read_text(),re.M)
    if match:classes[match.group(1)]=path.relative_to(RUNTIME)
seen=set();queue=[Path(p) for p in ['modules/mining/mine_art.gd','modules/mining/mine_combat.gd',
    'modules/farm/farm_camera.gd','modules/avatar/avatar_service.gd','assets/avatar/demo_denylist.json']]
queue += [Path(p.removeprefix('res://')) for p in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text())]
queue += [p.relative_to(RUNTIME) for p in (RUNTIME/'modules/avatar').rglob('*.gd')]
queue += [Path('assets/ui/icons/lucide/'+name+'.svg') for name in ['circle-check','circle','chevron-down']]
while queue:
    rel=queue.pop()
    if rel in seen:continue
    source=RUNTIME/rel
    if not source.is_file():continue
    seen.add(rel);target=PROJECT/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
    for suffix in ['.import','.uid']:
        side=Path(str(source)+suffix)
        if side.exists():shutil.copy2(side,Path(str(target)+suffix))
    if source.suffix in ['.gd','.tscn','.tres','.gdshader']:
        text=source.read_text()
        queue += [Path(p) for p in re.findall(r'res://([^"\s]+)',text) if not p.endswith('/')]
        queue += [path for name,path in classes.items() if re.search(r'\b'+name+r'\b',text)]
model_dir=RUNTIME/'assets/monsters'/args.id
shutil.copy2(SRC/'material_import.gd',RUNTIME/'assets/monsters/material_import.gd')
(PROJECT/'assets/monsters').mkdir(parents=True,exist_ok=True)
shutil.copy2(SRC/'material_import.gd',PROJECT/'assets/monsters/material_import.gd')
helper_uid=RUNTIME/'assets/monsters/material_import.gd.uid'
if helper_uid.exists():shutil.copy2(helper_uid,PROJECT/'assets/monsters/material_import.gd.uid')
elif (SRC/'material_import.gd.uid').exists():
    shutil.copy2(SRC/'material_import.gd.uid',helper_uid)
    shutil.copy2(helper_uid,PROJECT/'assets/monsters/material_import.gd.uid')
shutil.copytree(model_dir,PROJECT/'assets/monsters'/args.id,dirs_exist_ok=True)
config=model_dir/(args.id+'.glb.import')
if not config.exists():
    resource='res://assets/monsters/'+args.id+'/'+args.id+'.glb'
    cache='res://.godot/imported/'+args.id+'.glb-'+hashlib.md5(resource.encode()).hexdigest()+'.scn'
    config.write_text(f'''[remap]
importer="scene"
importer_version=1
type="PackedScene"
path="{cache}"
[deps]
source_file="{resource}"
dest_files=["{cache}"]
[params]
nodes/root_scale=1.0
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=0
skins/use_named_skins=true
animation/import=true
animation/fps=60
animation/remove_immutable_tracks=false
animation/trimming=false
materials/extract=0
gltf/texture_map_mode=1
''')
text=config.read_text()
if 'import_script/path=' in text:
    text=re.sub(r'import_script/path="[^\"]*"','import_script/path="res://assets/monsters/material_import.gd"',text)
else:text+='import_script/path="res://assets/monsters/material_import.gd"\n'
config.write_text(text)
shutil.copy2(config,PROJECT/'assets/monsters'/args.id/config.name)
manifest=json.loads((RUNTIME/'assets/avatar/parts_manifest.json').read_text())
manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(PROJECT/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for name in ['review.gd','configure.gd']:shutil.copy2(SRC/name,PROJECT/name)
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="MonsterReview" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/'project.godot').write_text(f'''config_version=5
[application]
config/name="SGODOT-355 {args.id} art fixture"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenMonster355_{args.id}"
boot_splash/show_image=false
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=960
window/size/viewport_height=800
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
lights_and_shadows/directional_shadow/size=2048
[monster_review]
identity="{args.id}"
''')
(OUT/'dependencies.json').write_text(json.dumps({'runtime_base':'0beeca15','files':{str(p):hashlib.sha256((RUNTIME/p).read_bytes()).hexdigest() for p in sorted(seen)}},indent=2)+'\n')
print(PROJECT,len(seen),'dependencies')
