from pathlib import Path
import json,subprocess,shutil,tarfile,hashlib
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/alcatraz-tower-color-424';P=OUT/'project';KIT='assets/landmarks/alcatraz_island';HOST='bf0c31b1c871011008b455434d167224d14de59c'
manifest=json.loads((SRC/'colour-map.json').read_text())
if not P.exists():shutil.copytree(ROOT/'output/alcatraz-ferry-424/project',P)
if not (OUT/'host-ref.json').exists():
 paths=[KIT,'scenes/landmark/alcatraz_island.gd','scenes/landmark/alcatraz_island.gd.uid','scenes/landmark/alcatraz_island.tscn','modules/farm/farm_camera.gd','modules/farm/scene_pan.gd','modules/farm/scene_pan.gd.uid','assets/ui/icons/game/door-open.svg']
 proc=subprocess.Popen(['git','archive',HOST,*paths],cwd=ROOT,stdout=subprocess.PIPE)
 with tarfile.open(fileobj=proc.stdout,mode='r|') as tar:tar.extractall(P,filter='data')
 assert proc.wait()==0
 (OUT/'host-ref.json').write_text(json.dumps({'ref':HOST},indent=2)+'\n')
for name in manifest['assets']:
 for ext in ['.glb','.glb.import']:shutil.copy2(ROOT/KIT/(name+ext),P/KIT/(name+ext))
 # Independent before resources use accepted original GLB bytes and their import
 # settings (only resource path/UID changed by Godot for the fixture copy).
 before=P/'before';before.mkdir(exist_ok=True);raw=subprocess.check_output(['git','show',manifest['base']+':'+KIT+'/'+name+'.glb'],cwd=ROOT);(before/(name+'.glb')).write_bytes(raw)
 cfg=before/(name+'.glb.import')
 if not cfg.exists():
  resource='res://before/'+name+'.glb';cache=f'res://.godot/imported/{name}.glb-{hashlib.md5(resource.encode()).hexdigest()}.scn'
  cfg.write_text(f'[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="{cache}"\n[deps]\nsource_file="{resource}"\ndest_files=["{cache}"]\n[params]\nnodes/root_script=null\nmeshes/generate_lods=false\nmeshes/light_baking=1\nanimation/import=false\ngltf/texture_map_mode=1\nimport_script/path="res://{KIT}/alc_far_material_import.gd"\n')
# Use the text-free far sign in both colour controls. Its change is reviewed separately.
for ext in ['.glb','.glb.import']:shutil.copy2(ROOT/KIT/('alc_museum_far'+ext),P/KIT/('alc_museum_far'+ext))
for file in SRC.glob('*.gd'):shutil.copy2(file,P/file.name)
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="TowerColourReview" type="Node"]\nscript=ExtResource("1")\n')
p=P/'project.godot';p.write_text(p.read_text().replace('SensenAlcatrazFerry424QA','SensenTowerColour424QA'))
files=['scenes/landmark/alcatraz_island.gd',KIT+'/layout.json',KIT+'/sea_backdrop.gdshader',KIT+'/far_card.gdshader']
checks={}
for path in files:
 raw=subprocess.check_output(['git','show',HOST+':'+path],cwd=ROOT);assert (P/path).read_bytes()==raw;checks[path]=hashlib.sha256(raw).hexdigest()
(OUT/'fixture.json').write_text(json.dumps({'host':HOST,'host_hashes':checks,'overlay':'four tower COLOR_0 variants + synchronized museum pictogram far; no host scene/layout/shader edits'},indent=2)+'\n')
print(P)
