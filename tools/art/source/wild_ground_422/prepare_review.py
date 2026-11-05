"""Stage a pinned, offline game copy; never edits a runtime branch or player save."""
from pathlib import Path
import json
import re
import shutil
import subprocess
import tarfile

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[3]
OUT = ROOT / 'output/wild-ground-422'
PROJECT = OUT / 'project'
# Same native 43-degree P0 scene used in the approved 408/416 review workflow.
BASE = '67116c6df4f69062ce658c50581e72ab1779a1b4'

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT.parent / '.gdignore').touch()
    PROJECT.mkdir(exist_ok=True)
    stamp = OUT / 'runtime-base.json'
    if not stamp.exists():
        proc = subprocess.Popen(['git', 'archive', BASE, 'assets', 'modules', 'scenes',
                                 'addons', 'project.godot', 'icon.svg'], cwd=ROOT, stdout=subprocess.PIPE)
        with tarfile.open(fileobj=proc.stdout, mode='r|') as archive:
            archive.extractall(PROJECT, filter='data')
        assert proc.wait() == 0
        stamp.write_text(json.dumps({'runtime_commit': BASE, 'art_base':
            '93befb18', 'offline': True}, indent=2) + '\n')
    (PROJECT / 'project.godot').write_bytes(subprocess.check_output(
        ['git', 'show', BASE + ':project.godot'], cwd=ROOT))
    # Runtime .res parts reference source PNGs. Import those while omitting the
    # unused authoring FBXs from this disposable copy (not from the repository).
    (PROJECT / 'assets/avatar/source/.gdignore').unlink(missing_ok=True)
    for authoring in (PROJECT / 'assets/avatar/source').rglob('*.fbx'):
        authoring.unlink()
    for name in ['review.gd', 'review_pond.gd', 'pond_ground.sample.gdshader', 'configure_imports.gd',
                 'verify_maps.gd', 'android_review.gd', 'prepare_android.gd']:
        if (SRC / name).exists():
            shutil.copy2(SRC / name, PROJECT / name)
    shutil.copy2(SRC / 'reference/pond_slots_v2.json', PROJECT / 'pond_slots_v2.json')
    shutil.copytree(ROOT / 'assets/ponds/ground', PROJECT / 'assets/ponds/ground', dirs_exist_ok=True)
    for suffix in ['.glb', '.glb.import']:
        shutil.copy2(ROOT / ('assets/farm/art/flax_patch' + suffix),
                     PROJECT / ('assets/farm/art/flax_patch' + suffix))
    shutil.copy2(ROOT / 'tools/art/source/reed_clay_416/reference/zz_spot_art_old.gd',
                 PROJECT / 'scenes/p0/zz_spot_art_old.gd')
    # The supplied mock includes the current MEADOW and pebble/water exclusion.
    # Resource context is identical in each before/after pair, only the material changes.
    mock = (SRC / 'reference/pond_scenery.mock2.gd').read_text()
    a = mock.index('\t# MOCKUP v2')
    b = mock.index('\tvar pebbles :=', a)
    mock = mock[:a] + '''\tvar slots: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://pond_slots_v2.json"))
\tvar shape_slots: Dictionary = slots.shapes[str(entry.template_id)]
\tvar tree_slot: Dictionary = shape_slots.get("F1", shape_slots.get("C1", {}))
\tvar Old = load("res://scenes/p0/zz_spot_art_old.gd")
\tscene.add_child(Old.build("spot_grove", Vector3(float(tree_slot.x), 0, float(tree_slot.z))))
\tvar flax := Art.instance("flax_patch", Vector3(7.6, 0, -1.4))
\tflax.name = "ReviewFlaxF2"
\tscene.add_child(flax)
''' + mock[b:]
    (PROJECT / 'modules/ponds/pond_scenery.gd').write_text(mock)
    # Same fixed visual time for both captures; only the isolated shader copies
    # change. This keeps animated water out of the material comparison.
    for relative in ['modules/ponds/pond_water.gdshader', 'modules/ponds/pond_turf.gdshader',
                     'modules/ponds/pond_tree.gdshader', 'modules/ponds/pond_lily.gdshader']:
        payload = subprocess.check_output(['git', 'show', BASE + ':' + relative], cwd=ROOT, text=True)
        (PROJECT / relative).write_text(re.sub(r'\bTIME\b', '12.0', payload))
    (PROJECT / 'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://review.gd" id="1"]\n'
        '[node name="WildGroundReview" type="Node"]\nscript=ExtResource("1")\n')
    (PROJECT / 'override.cfg').write_text('''[application]
config/name="SGODOT-422 isolated ground review"
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenWildGround422ArtQA"
run/main_scene="res://review.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=720
window/size/viewport_height=800
window/size/window_width_override=720
window/size/window_height_override=800
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

if __name__ == '__main__':
    main()
