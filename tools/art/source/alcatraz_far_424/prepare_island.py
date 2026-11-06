"""Pinned Marco Polo blockout + this package, staged only under output.

The only fixture layout edit removes the three scenic-card LOD groups. Positions,
camera, navigation and all host GDScript/shaders remain byte-identical to #792.
"""
from pathlib import Path
import hashlib,json,shutil,subprocess,tarfile
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent
OUT=ROOT/'output/alcatraz-far-424';DEST=OUT/'island-project'
REF='34df9c0b6af42a85567dfb5318c6717f929a4ab8'
KIT='assets/landmarks/alcatraz_island'
DEST.mkdir(parents=True,exist_ok=True)
families=[KIT,'scenes/landmark/alcatraz_island.gd','scenes/landmark/alcatraz_island.gd.uid','scenes/landmark/alcatraz_island.tscn',
 'modules/farm/farm_camera.gd','modules/farm/scene_pan.gd','modules/farm/scene_pan.gd.uid','assets/ui/icons/game/door-open.svg']
if not (OUT/'island-base.json').exists():
 proc=subprocess.Popen(['git','archive',REF,*families],cwd=ROOT,stdout=subprocess.PIPE)
 with tarfile.open(fileobj=proc.stdout,mode='r|') as archive:archive.extractall(DEST,filter='data')
 assert proc.wait()==0
 (OUT/'island-base.json').write_text(json.dumps({'commit':REF},indent=2)+'\n')
for rel in ['assets/avatar','modules/avatar']:
 shutil.copytree(OUT/'project'/rel,DEST/rel,dirs_exist_ok=True)
# Use only our assets; never overwrite the checked-out main artist's files.
manifest=json.loads((ROOT/KIT/'alc_far_manifest.json').read_text())
for name in manifest['assets']:
 for suffix in ['.glb','.glb.import']:shutil.copy2(ROOT/KIT/(name+suffix),DEST/KIT/(name+suffix))
for name in ['alc_far_material_import.gd','alc_far_material_import.gd.uid']:
 shutil.copy2(ROOT/KIT/name,DEST/KIT/name)
raw=subprocess.check_output(['git','show',REF+':'+KIT+'/layout.json'],cwd=ROOT)
layout=json.loads(raw);cards={'alc_far_bridge','alc_far_city','alc_far_hills'}
for p in layout['placements']:
 if p['asset'] in cards:p.pop('lod_group',None)
layout['lod_groups']=[g for g in layout['lod_groups'] if g['name'] not in cards]
(DEST/KIT/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n')
changes={'source_commit':REF,'source_layout_sha256':hashlib.sha256(raw).hexdigest(),
 'review_layout_sha256':hashlib.sha256((DEST/KIT/'layout.json').read_bytes()).hexdigest(),
 'layout_edit':'Remove lod_group only for three FarZone cards; preserve all positions/camera/navigation; native tower LOD 55m unchanged',
 'host_files':{}}
for rel in ['scenes/landmark/alcatraz_island.gd',KIT+'/far_card.gdshader',KIT+'/sea.gdshader','modules/farm/farm_camera.gd']:
 if not (DEST/rel).exists():continue
 base=subprocess.check_output(['git','show',REF+':'+rel],cwd=ROOT);assert (DEST/rel).read_bytes()==base
 changes['host_files'][rel]=hashlib.sha256(base).hexdigest()
(OUT/'island-fixture.json').write_text(json.dumps(changes,ensure_ascii=False,indent=2)+'\n')
shutil.copy2(SRC/'review_island.gd',DEST/'review.gd')
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="FarIslandReview" type="Node"]\nscript=ExtResource("1")\n')
config=(OUT/'project/project.godot').read_text().replace('SensenAlcatrazFar424QA','SensenAlcatraz424CombinedQA')
(DEST/'project.godot').write_text(config)
print(DEST)
