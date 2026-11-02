"""Prepare an isolated review/depth-test project; never patch runtime code."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import struct
from urllib.parse import unquote

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
RUNTIME=ROOT/'output/monsters-355/runtime'
OUT=ROOT/'output/mine-vein-355';PROJECT=OUT/'project';PROJECT.mkdir(parents=True,exist_ok=True)
classes={}
for folder in ['modules','scenes','addons/gdUnit4']:
    for path in (RUNTIME/folder).rglob('*.gd'):
        match=re.search(r'^class_name\s+(\w+)',path.read_text(),re.M)
        if match:classes[match.group(1)]=path.relative_to(RUNTIME)
autoload={'Localization':'modules/ui/localization.gd','Avatar':'modules/avatar/avatar_service.gd',
    'AppRouter':'modules/ui/app_router.gd','Net':'modules/net/net_service.gd','Voice':'modules/net/voice_session.gd'}
queue=[Path(p) for p in ['tests/p0/test_p0_mine_backdrop_depth.gd','modules/mining/mine_combat.gd',
    'modules/mining/mine_backdrop.gd','modules/mining/mine_art.gd','assets/avatar/demo_denylist.json',
    'assets/monsters/material_import.gd','icon.svg',*autoload.values()]]
queue += [Path(p.removeprefix('res://')) for p in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text())]
queue += [p.relative_to(RUNTIME) for p in (RUNTIME/'modules/avatar').rglob('*.gd')]
queue += [Path('assets/ui/icons/lucide/'+name+'.svg') for name in ['circle-check','circle','chevron-down']]
queue += [p.relative_to(RUNTIME) for p in (RUNTIME/'assets/p0/icons').rglob('*') if p.is_file()]
seen=set()
while queue:
    rel=queue.pop();source=RUNTIME/rel
    if rel in seen or not source.is_file():continue
    seen.add(rel);target=PROJECT/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
    for suffix in ['.import','.uid']:
        side=Path(str(source)+suffix)
        if side.exists():
            shutil.copy2(side,Path(str(target)+suffix));queue.append(side.relative_to(RUNTIME))
    if source.suffix=='.glb':
        raw=source.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
        gltf=json.loads(raw[20:20+length])
        for image in gltf.get('images',[]):
            uri=image.get('uri','')
            if uri and not uri.startswith(('data:','http:','https:')):
                queue.append((source.parent/unquote(uri)).resolve().relative_to(RUNTIME))
    if source.suffix in ['.gd','.tscn','.tres','.gdshader','.import']:
        text=source.read_text()
        queue += [Path(p) for p in re.findall(r'res://([^"\s]+)',text) if not p.endswith('/')]
        queue += [path for name,path in classes.items() if re.search(r'\b'+name+r'\b',text)]
shutil.copytree(RUNTIME/'addons/gdUnit4',PROJECT/'addons/gdUnit4',dirs_exist_ok=True)
for directory in ['assets/monsters/mob_cave_bat','assets/monsters/mob_shroomling','assets/monsters/mob_rock_beetle',
        'assets/monsters/slime_king','assets/mine/rocks','assets/mine/props','assets/mine/types/vein']:
    shutil.copytree(RUNTIME/directory,PROJECT/directory,dirs_exist_ok=True)
parts=json.loads((RUNTIME/'assets/avatar/parts_manifest.json').read_text())
parts['parts']=[p for p in parts['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(PROJECT/'assets/avatar/parts_manifest.json').write_text(json.dumps(parts,indent=2)+'\n')

resource='res://assets/mine/types/vein/backdrop.glb'
config=RUNTIME/'assets/mine/types/vein/backdrop.glb.import'
if not config.exists():
    text=(RUNTIME/'assets/mine/backdrop/mine_backdrop.glb.import').read_text()
    text=re.sub(r'^uid=".*"\n','',text,flags=re.M)
    text=text.replace('res://assets/mine/backdrop/mine_backdrop.glb',resource)
    old_cache=re.search(r'^path="(.*)"',text,re.M)[1]
    new_cache='res://.godot/imported/backdrop.glb-'+hashlib.md5(resource.encode()).hexdigest()+'.scn'
    config.write_text(text.replace(old_cache,new_cache))
shutil.copy2(config,PROJECT/'assets/mine/types/vein/backdrop.glb.import')

patches={}
path=PROJECT/'modules/mining/mine_backdrop.gd';text=path.read_text()
text=text.replace('res://assets/mine/backdrop/mine_backdrop.glb',resource)
text=text.replace('const VOID :=','static var VOID :=')
text=text.replace('return TINTS.get(floor_n, TINTS[2])',
    'return ProjectSettings.get_setting("mine_vein/backdrop_tint", TINTS.get(floor_n, TINTS[2]))')
text=text.replace('mat.set_shader_parameter("void_tint", VOID)',
    'mat.set_shader_parameter("void_tint", VOID)\n\tmat.set_shader_parameter("vein_mask", 1.0)')
path.write_text(text);patches[str(path.relative_to(PROJECT))]='Review-only asset path / palette tint / void'
path=PROJECT/'modules/mining/mine_backdrop.gdshader';text=path.read_text()
text=text.replace('mix(COLOR.rgb * floor_tint, void_tint, clamp(UV2.x, 0.0, 1.0))',
    'mix(mix(COLOR.rgb * floor_tint, COLOR.rgb, UV2.y * vein_mask), void_tint, UV2.x)')
text=text.replace('uniform vec3 floor_tint','uniform float vein_mask = 0.0;\nuniform vec3 floor_tint')
path.write_text(text);patches[str(path.relative_to(PROJECT))]='Exact approved UV2.y mineral-mask formula'
path=PROJECT/'modules/mining/mine_art.gd';text=path.read_text()
for field in ['ground','wall']:
    old=f'var {field}: Color = '+('FLOOR_COLORS' if field=='ground' else 'WALL_COLORS')+'[number - 1]'
    assert old in text
    text=text.replace(old,f'var {field}: Color = ProjectSettings.get_setting("mine_vein/{field}", '+('FLOOR_COLORS' if field=='ground' else 'WALL_COLORS')+'[number - 1])')
path.write_text(text);patches[str(path.relative_to(PROJECT))]='Review-only palette ground and wall colours'
path=PROJECT/'tests/p0/test_p0_mine_backdrop_depth.gd';text=path.read_text()
text=text.replace('\t\t\tvar case: Dictionary = await _sweep(size, floor_n)',
    '\t\t\tprint("VEIN_DEPTH_BEGIN ",size," floor ",floor_n)\n\t\t\tvar case: Dictionary = await _sweep(size, floor_n)\n\t\t\tprint("VEIN_DEPTH_DONE ",size," floor ",floor_n," views ",case.views," margin ",case.worst.far_margin)')
path.write_text(text);patches[str(path.relative_to(PROJECT))]='Progress logging only; test assertions, density and camera code unchanged'
for filename in ['review.gd']:
    if (SRC/filename).exists():shutil.copy2(SRC/filename,PROJECT/filename)
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="VeinReview" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-355 vein isolated review"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenVein355"
boot_splash/show_image=false
[autoload]
'''+''.join(f'{name}="*res://{path}"\n' for name,path in autoload.items())+'''
[display]
window/size/viewport_width=720
window/size/viewport_height=900
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
textures/vram_compression/import_s3tc_bptc=true
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
[sensen]
network/base_url="http://127.0.0.1:9"
network/mobile_base_url="http://127.0.0.1:9"
[gdunit4]
settings/test/test_timeout_seconds=7200
''')
report={'runtime_base':subprocess.check_output(['git','-C',str(RUNTIME),'rev-parse','HEAD'],text=True).strip(),
    'temporary_patches':patches,'files':{str(p):hashlib.sha256((RUNTIME/p).read_bytes()).hexdigest() for p in sorted(seen)}}
(OUT/'dependencies.json').write_text(json.dumps(report,indent=2)+'\n')
print(PROJECT,len(seen),'dependencies')
