"""Stage/configure/sync a minimal Godot importer. No example scene or layout.
Godot itself must be invoked under the shared render lock between these steps.
"""
from pathlib import Path
import argparse,json,re,shutil
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
QA=ROOT/'output/coast-kit/import-project';KIT=Path('assets/landmarks/_shared/coast_kit')
parser=argparse.ArgumentParser();parser.add_argument('action',choices=['stage','configure','sync','cold']);args=parser.parse_args()
names=json.loads((ROOT/KIT/'manifest.json').read_text())['assets']
if args.action=='stage':
    (QA/KIT).mkdir(parents=True,exist_ok=True);(ROOT/'output/.gdignore').touch()
    for name in names:
        for suffix in ['.glb','.glb.import']:
            p=ROOT/KIT/(name+suffix)
            if p.exists():shutil.copy2(p,QA/KIT/p.name)
    (QA/'project.godot').write_text('config_version=5\n[application]\nconfig/name="ZhaoyunCoastKit426Import"\nconfig/features=PackedStringArray("4.7", "Mobile")\n[rendering]\nrenderer/rendering_method="mobile"\n')
elif args.action=='configure':
    settings={'gltf/texture_map_mode':'1','meshes/light_baking':'1','meshes/generate_lods':'false','meshes/ensure_tangents':'false','meshes/create_shadow_meshes':'false','animation/import':'false'}
    for name in names:
        p=QA/KIT/(name+'.glb.import');text=p.read_text()
        assert re.search(r'^uid="uid://[^"]+"$',text,re.M) and 'nodes/root_script=null' in text
        for key,value in settings.items():
            text,n=re.subn('^'+re.escape(key)+r'=.*$',key+'='+value,text,flags=re.M);assert n==1,key
        p.write_text(text)
elif args.action=='sync':
    # Run only AFTER the final Godot --import. Never serialize away null defaults.
    for name in names:
        p=QA/KIT/(name+'.glb.import');text=p.read_text()
        assert re.search(r'^uid="uid://[^"]+"$',text,re.M) and 'nodes/root_script=null' in text
        assert 'gltf/texture_map_mode=1' in text and 'meshes/light_baking=1' in text
        shutil.copy2(p,ROOT/KIT/p.name)
else:
    # Only this throw-away importer cache, never other agents' caches or processes.
    if (QA/'.godot').exists():shutil.rmtree(QA/'.godot')
print(args.action,'ready:',QA)
