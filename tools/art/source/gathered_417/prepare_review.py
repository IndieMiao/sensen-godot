"""Pin the native b1 pond; stage only art and offline review fixtures under output."""
from pathlib import Path
import hashlib,json,shutil,subprocess,tarfile
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/gathered-417';PROJECT=OUT/'project'
BASE='67116c6df4f69062ce658c50581e72ab1779a1b4';ART_BASE='4d662915bab25d468d729a13522446f87e41675a'
NAMES=['grove','rock_pile','reed_bank','clay_pit','herb_patch','hardwood_grove','flax_patch']
PROJECT.mkdir(parents=True,exist_ok=True);stamp=OUT/'runtime-base.json'
if not stamp.exists():
    proc=subprocess.Popen(['git','archive',BASE,'assets','modules','scenes','addons','project.godot','icon.svg'],cwd=ROOT,stdout=subprocess.PIPE)
    with tarfile.open(fileobj=proc.stdout,mode='r|') as archive:archive.extractall(PROJECT,filter='data')
    assert proc.wait()==0
    critical=['scenes/p0/p0_pond.gd','scenes/p0/p0_ui.gd','modules/farm/farm_art.gd','modules/farm/crop_plant_mesh.gd','modules/mining/mine_mesh.gd']
    stamp.write_text(json.dumps({'runtime_commit':BASE,'art_base':ART_BASE,
        'files':{p:hashlib.sha256((PROJECT/p).read_bytes()).hexdigest() for p in critical}},indent=2)+'\n')
(PROJECT/'assets/avatar/source/.gdignore').touch()
for name in ['reed_bank','clay_pit','hardwood_grove','flax_patch']:
    for suffix in ['.glb','.glb.import']:shutil.copy2(ROOT/'assets/farm/art'/(name+suffix),PROJECT/'assets/farm/art'/(name+suffix))
for name in ['hardwood_grove_import.gd','hardwood_grove_import.gd.uid']:
    shutil.copy2(ROOT/'assets/farm/art'/name,PROJECT/'assets/farm/art'/name)
for name in NAMES:
    base=name+'_gathered';path=ROOT/'assets/farm/art'/(base+'.glb')
    if not path.exists():continue
    cfg=path.with_suffix('.glb.import')
    if not cfg.exists():
        original=(ROOT/'assets/farm/art/sign.glb.import').read_text().replace('uid="uid://b8q1wqv6jr5dh"\n','')
        resource='res://assets/farm/art/'+base+'.glb'
        original=original.replace('sign.glb-959143c80868ce7aee6d834e0fe7a8f5',base+'.glb-'+hashlib.md5(resource.encode()).hexdigest())
        cfg.write_text(original.replace('res://assets/farm/art/sign.glb',resource))
    for p in [path,cfg]:shutil.copy2(p,PROJECT/'assets/farm/art'/p.name)
shutil.copy2(SRC/'reference/zz_spot_art_old.gd',PROJECT/'old_art.gd')
for name in ['measure_originals.gd','review.gd','review_pond.gd','configure_imports.gd']:
    if (SRC/name).exists():shutil.copy2(SRC/name,PROJECT/name)
if (SRC/'original_metrics.json').exists():shutil.copy2(SRC/'original_metrics.json',PROJECT/'original_metrics.json')
if (SRC/'asset_stats.json').exists():shutil.copy2(SRC/'asset_stats.json',PROJECT/'asset_stats.json')
# Private mock of the agreed resource-slot clearance; actual pond files stay unchanged.
relative='modules/ponds/pond_scenery.gd'
native=subprocess.check_output(['git','show',BASE+':'+relative],cwd=ROOT,text=True)
mock=native.replace('\t\tvar scale_value := scene._rng.randf_range(.85, 1.1)',
    '\t\tif Vector2(point.x + .3, point.z + 6.6).length() < 3.0 or Vector2(point.x + .3, point.z + 9.0).length() < 3.0: continue\n\t\tvar scale_value := scene._rng.randf_range(.85, 1.1)')
for line in ['\t\tif FishingModel.contains(str(entry.id), point, .5, spec)', '\t\tif FishingModel.contains(str(entry.id), point, .10, spec)']:
    mock=mock.replace(line,'\t\tif _review_reserved(point): continue\n'+line)
mock+='\nstatic func _review_reserved(point: Vector3) -> bool:\n\tfor slot in [Vector2(-.3,-6.6),Vector2(-.3,-9.0),Vector2(7.6,-1.4)]:\n\t\tif Vector2(point.x,point.z).distance_to(slot)<1.5:return true\n\treturn false\n'
(PROJECT/relative).write_text(mock)
(OUT/'scenery-mock.json').write_text(json.dumps({'path':relative,'reason':'416 accepted 1aa399b8: decorative crowns must clear resource slots; review-only 1.5m low-decoration / 3m trunk exclusion at L1/L2',
    'original_sha256':hashlib.sha256(native.encode()).hexdigest(),'review_sha256':hashlib.sha256(mock.encode()).hexdigest()},indent=2)+'\n')
if not (PROJECT/'review.gd').exists():(PROJECT/'review.gd').write_text('extends Node\n')
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="GatheredReview" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/'override.cfg').write_text('''[application]
config/name="SGODOT-417 isolated art review"
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenGathered417ArtQA"
run/main_scene="res://review.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=960
window/size/viewport_height=900
window/size/window_width_override=960
window/size/window_height_override=900
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
