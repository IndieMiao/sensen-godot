"""Stage only art dependencies; pin current farm camera evidence without gameplay."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'output/sprinkler-244'
PROJECT = OUT/'project'
FARM = 'f4bb293bb8800ca96624912815bc8acae2943285'
PROJECT.mkdir(parents=True, exist_ok=True)
assert (ROOT/'output/.gdignore').exists()


def copy(relative):
    source, target = ROOT/relative, PROJECT/relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, target, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__', '*.blend', '*.py'))
    else: shutil.copy2(source, target)


for relative in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):
    copy(relative.removeprefix('res://'))
for relative in ['modules/avatar', 'assets/avatar/demo_denylist.json', 'modules/farm/farm_art.gd',
                 'modules/farm/crop_plant_mesh.gd', 'modules/farm/shaders',
                 'tools/art/review_sprinkler.gd']:
    copy(relative)
for filename in ['plot.glb', 'plot.glb.import', 'sprinkler.glb', 'manifest.json', 'meadow.png', 'meadow.png.import']:
    copy('assets/farm/art/'+filename)
for filename in ['sprinkler.glb.import']:
    source = ROOT/'assets/farm/art'/filename
    if source.exists(): copy(str(source.relative_to(ROOT)))
    else:
        template = (ROOT/'assets/farm/art/greenhouse_base.glb.import').read_text()
        template = re.sub(r'uid="[^"]+"\n', '', template)
        relative = 'res://assets/farm/art/sprinkler.glb'
        target = 'res://.godot/imported/sprinkler.glb-'+hashlib.md5(relative.encode()).hexdigest()+'.scn'
        template = re.sub(r'res://\.godot/imported/greenhouse_base\.glb-[^\"]+\.scn', target, template)
        template = template.replace('res://assets/farm/art/greenhouse_base.glb', relative)
        template = template.replace('meshes/force_disable_compression=false', 'meshes/force_disable_compression=true')
        (PROJECT/'assets/farm/art'/filename).write_text(template)

dependencies = {}
for relative in ['modules/farm/farm_camera.gd', 'scenes/p0/p0_farm.tscn', 'scenes/p0/p0_farm.gd',
                 'scenes/p0/p0_farm_facilities.gd', 'modules/p0/p0_garden.gd']:
    data = subprocess.check_output(['git', 'show', FARM+':'+relative], cwd=ROOT)
    evidence = OUT/'source-evidence'/relative
    evidence.parent.mkdir(parents=True, exist_ok=True); evidence.write_bytes(data)
    dependencies[relative] = hashlib.sha256(data).hexdigest()
    if relative == 'modules/farm/farm_camera.gd':
        (PROJECT/relative).write_bytes(data)
for relative in ['assets/farm/art/plot.glb', 'modules/farm/farm_art.gd', 'modules/farm/crop_plant_mesh.gd']:
    original = subprocess.check_output(['git', 'show', FARM+':'+relative], cwd=ROOT)
    assert original == (ROOT/relative).read_bytes(), relative
    dependencies[relative] = hashlib.sha256(original).hexdigest()
references=PROJECT/'references'
references.mkdir(exist_ok=True)
reference_manifest={}
for revision,commit in [('v1','a9f7d142'),('v1_1','cf97f40b')]:
    data=subprocess.check_output(['git','show',commit+':assets/farm/art/sprinkler.glb'],cwd=ROOT)
    (references/('sprinkler_'+revision+'.glb')).write_bytes(data)
    reference_manifest[revision]={'commit':commit,'sha256':hashlib.sha256(data).hexdigest()}
reference_manifest['v1_2']={'source':'assets/farm/art/sprinkler.glb',
                           'sha256':hashlib.sha256((ROOT/'assets/farm/art/sprinkler.glb').read_bytes()).hexdigest()}
(references/'manifest.json').write_text(json.dumps(reference_manifest,indent=2)+'\n')
manifest = json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())
manifest['parts'] = [p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(PROJECT/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
(PROJECT/'project.godot').write_text('''config_version=5
[application]
config/name="Sprinkler 244 Offline Art Review"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenHuangzhongSprinkler244QA"
run/main_scene="res://review.tscn"
boot_splash/show_image=false
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=960
window/size/viewport_height=720
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
''')
(PROJECT/'review.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tools/art/review_sprinkler.gd" id="1"]
[node name="SprinklerReview" type="Node"]
script=ExtResource("1")
''')
(OUT/'source-evidence.json').write_text(json.dumps({'farm_commit': FARM, 'files': dependencies}, indent=2)+'\n')
print(PROJECT)
