"""Stage an isolated pond review; scene placement and slot clearing stay local."""
from pathlib import Path
import argparse,difflib,json,shutil,subprocess
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/hardwood-408';PROJECT=QA/'project';KIT='assets/farm/art'
p=argparse.ArgumentParser();p.add_argument('--runtime-ref',default='2d481d66');p.add_argument('--sync-import',action='store_true');args=p.parse_args()
if args.sync_import:
    for name in ['hardwood_grove.glb.import','hardwood_grove_import.gd.uid']:shutil.copy2(PROJECT/KIT/name,ROOT/KIT/name)
    raise SystemExit()
PROJECT.mkdir(parents=True,exist_ok=True);(ROOT/'output/.gdignore').touch()
head=subprocess.check_output(['git','rev-parse',args.runtime_ref],cwd=ROOT,text=True).strip()
archive=subprocess.Popen(['git','archive',head],cwd=ROOT,stdout=subprocess.PIPE)
subprocess.run(['tar','-x','-C',str(PROJECT)],stdin=archive.stdout,check=True);archive.stdout.close();assert archive.wait()==0
(PROJECT/'docs/.gdignore').touch()
for name in ['hardwood_grove.glb','hardwood_grove.glb.import','hardwood_grove_import.gd','hardwood_grove_import.gd.uid']:
    if (ROOT/KIT/name).exists():shutil.copy2(ROOT/KIT/name,PROJECT/KIT/name)
shutil.copy2(HERE/'spec.json',PROJECT/'hardwood_spec.json')
shutil.copy2(HERE/'reference/zz_spot_art_old.gd',PROJECT/'zz_spot_art_old.gd')
for name in ['review.gd','configure.gd']:
    if (HERE/name).exists():shutil.copy2(HERE/name,PROJECT/name)
path=PROJECT/'modules/ponds/pond_scenery.gd';original=path.read_text()
needle='\tfor asset in layers: scene.add_child(Art.batch(asset, layers[asset], asset == "bush"))'
replacement='''\t# Offline SGODOT-408 review only: clear large seeded dressing at the chosen L2 slot.
\t# Filtering happens after the draws so the random sequence outside the slot is unchanged.
\tfor asset in layers:
\t\tlayers[asset] = layers[asset].filter(func(xf): return absf(xf.origin.x + .3) > 1.05 or absf(xf.origin.z + 9.0) > 1.05)
\t\tscene.add_child(Art.batch(asset, layers[asset], asset == "bush"))'''
assert original.count(needle)==1
modified=original.replace(needle,replacement)
needle='\treturn scene';assert modified.count(needle)==1
modified=modified.replace(needle,'''\tvar hardwood = load("res://assets/farm/art/hardwood_grove.glb").instantiate()
\thardwood.name = "HardwoodL2"
\thardwood.position = Vector3(-.3, 0, -9.0)
\tscene.add_child(hardwood)
\treturn scene''')
path.write_text(modified)
(QA/'pond-preview.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True),modified.splitlines(True),fromfile='b1/modules/ponds/pond_scenery.gd',tofile='isolated-preview/modules/ponds/pond_scenery.gd')))
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="Hardwood408Review" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/'override.cfg').write_text('''[application]
config/name="ZhaoyunHardwood408QA"
config/use_custom_user_dir=true
config/custom_user_dir_name="ZhaoyunHardwood408QA"
run/main_scene="res://review.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=360
window/size/viewport_height=800
window/size/window_width_override=360
window/size/window_height_override=800
[sensen]
network/base_url="http://127.0.0.1:9/v1"
network/mobile_base_url="http://127.0.0.1:9/v1"
''')
(QA/'stage.json').write_text(json.dumps(dict(runtime_head=head,pond='pond_san_francisco_03',slot='L2',slot_xz=[-.3,-9],goto_xz=[.95,-8.4],
    preview_edit='Only temporary PondScenery placement plus filtering large scatter in a 2.1m square at L2 after RNG draws; navigation, water, camera limits and spawn unchanged',
    scope='Isolated b1 copy; no game integration or network service changes committed'),indent=2)+'\n')
print(PROJECT)
