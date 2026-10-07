"""Stage an art-only Mobile renderer project, import the actual GLBs, save review views.
Usage: python3 tools/art/source/coffee_shop/render_r1.py
Needs a working DISPLAY/XAUTHORITY; does not alter the production project.
"""
from pathlib import Path
import os, shutil, subprocess, sys

ROOT=Path(__file__).resolve().parents[4]
slug=sys.argv[2] if len(sys.argv)>2 else 'coffee_shop'
assert slug.replace('_','').isalnum()
revision=sys.argv[1] if len(sys.argv)>1 else 'r1'
assert revision in ('r1','r2','r21')
out=ROOT/'output'/slug/revision
stage=out/'godot-project'
out.mkdir(parents=True,exist_ok=True)
(ROOT/'output/.gdignore').touch()
for family in ('assets/rooms','scenes'):
    shutil.copytree(ROOT/family/slug,stage/family/slug,dirs_exist_ok=True)
if slug!='coffee_shop':
    shutil.copytree(ROOT/'scenes/coffee_shop',stage/'scenes/coffee_shop',dirs_exist_ok=True)
shutil.copytree(ROOT/'assets/rooms/_shared/plants',stage/'assets/rooms/_shared/plants',dirs_exist_ok=True,ignore=shutil.ignore_patterns('source','*.md'))
shutil.copy2(ROOT/'tools/art/source/coffee_shop/render_r1.gd',stage/'render_review.gd')
(stage/'project.godot').write_text('''config_version=5
[application]
config/name="Shop Art Review"
[rendering]
renderer/rendering_method="mobile"
textures/default_filters/use_nearest_mipmap_filter=false
textures/vram_compression/import_etc2_astc=true
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
''')
def run(args,name):
    with (out/name).open('w') as f:
        subprocess.run(['godot','--disable-vsync','--max-fps','60','--path',str(stage),*args],stdout=f,stderr=subprocess.STDOUT,check=True)
run(['--headless','--editor','--import'],'import.log')
for folder in (slug, '_shared/plants'):
    imp=stage/'assets/rooms'/folder/'room_albedo_ao.png.import'
    s=imp.read_text().replace('compress/mode=0','compress/mode=2').replace('mipmaps/generate=false','mipmaps/generate=true')
    imp.write_text(s)
    shutil.copy2(imp,ROOT/'assets/rooms'/folder/imp.name)
run(['--headless','--editor','--import'],'reimport.log')
run(['--rendering-method','mobile','--rendering-driver','vulkan','--script','res://render_review.gd','--',slug,str(out)],'render.log')
print((out/'godot-verification.json').read_text())
