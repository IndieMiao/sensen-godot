"""Pinned b16c3198 island, only output fixture LOD/pose choices change."""
from pathlib import Path
import hashlib,json,shutil,subprocess,tarfile,re
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/alcatraz-ferry-424';P=OUT/'project';K='assets/landmarks/alcatraz_island';KIT=ROOT/K
REF='b16c31982f34a64cdd4f9c6683064edbf20837a0'
P.mkdir(parents=True,exist_ok=True)
if not (OUT/'host-ref.json').exists():
 families=[K,'scenes/landmark/alcatraz_island.gd','scenes/landmark/alcatraz_island.gd.uid','scenes/landmark/alcatraz_island.tscn','modules/farm/farm_camera.gd','modules/farm/scene_pan.gd','modules/farm/scene_pan.gd.uid','assets/ui/icons/game/door-open.svg']
 proc=subprocess.Popen(['git','archive',REF,*families],cwd=ROOT,stdout=subprocess.PIPE)
 with tarfile.open(fileobj=proc.stdout,mode='r|') as tar:tar.extractall(P,filter='data')
 assert proc.wait()==0
 for rel in ['assets/avatar','modules/avatar']:
  shutil.copytree(ROOT/'output/alcatraz-far-424/island-project'/rel,P/rel,dirs_exist_ok=True)
 (OUT/'host-ref.json').write_text(json.dumps({'ref':REF},indent=2)+'\n')
 (P/'project.godot').write_text((ROOT/'output/alcatraz-far-424/island-project/project.godot').read_text().replace('SensenAlcatraz424CombinedQA','SensenAlcatrazFerry424QA'))
for name in ['ferry','ferry_far','gull']:
 cfg=KIT/(name+'.glb.import');resource=f'res://{K}/{name}.glb'
 if not cfg.exists():
  if name!='ferry_far':txt=subprocess.check_output(['git','show',REF+':'+K+'/'+name+'.glb.import'],cwd=ROOT).decode()
  else:
   cache=f'res://.godot/imported/{name}.glb-{hashlib.md5(resource.encode()).hexdigest()}.scn'
   txt=f'[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="{cache}"\n[deps]\nsource_file="{resource}"\ndest_files=["{cache}"]\n[params]\n'
  for key,val in {'nodes/root_scale':'1.0','meshes/ensure_tangents':'true','meshes/generate_lods':'false','meshes/create_shadow_meshes':'true','meshes/light_baking':'1','animation/import':'false','gltf/texture_map_mode':'1','import_script/path':'"res://'+K+'/ferry_gull_material_import.gd"'}.items():
   txt=re.sub('^'+re.escape(key)+'=.*$',key+'='+val,txt,flags=re.M) if key+'=' in txt else txt+'\n'+key+'='+val+'\n'
  cfg.write_text(txt)
 for suffix in ['.glb','.glb.import']:shutil.copy2(KIT/(name+suffix),P/K/(name+suffix))
for name in ['ferry_gull_manifest.json','ferry_gull_material_import.gd','ferry_gull_material_import.gd.uid']:
 if (KIT/name).exists():shutil.copy2(KIT/name,P/K/name)
l=json.loads(subprocess.check_output(['git','show',REF+':'+K+'/layout.json'],cwd=ROOT));manifest=json.loads((KIT/'ferry_gull_manifest.json').read_text())
for point in l['placements']:
 if point['asset']=='ferry':point['lod_group']='ferry'
l['lod_groups'].append(manifest['ferry_lod_group']);(P/K/'layout.json').write_text(json.dumps(l,ensure_ascii=False,indent=2)+'\n')
check={'source_ref':REF,'layout_fixture_only':'add ferry lod_group; positions/rotations/scales unchanged; gull poses applied by review only','host_hashes':{}}
for rel in ['scenes/landmark/alcatraz_island.gd',K+'/sea_backdrop.gdshader',K+'/far_card.gdshader','modules/farm/farm_camera.gd']:
 raw=subprocess.check_output(['git','show',REF+':'+rel],cwd=ROOT);assert (P/rel).read_bytes()==raw;check['host_hashes'][rel]=hashlib.sha256(raw).hexdigest()
(OUT/'fixture.json').write_text(json.dumps(check,indent=2)+'\n')
for n in ['review.gd']:
 if (SRC/n).exists():shutil.copy2(SRC/n,P/n)
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="FerryGullReview" type="Node"]\nscript=ExtResource("1")\n')
print(P)
