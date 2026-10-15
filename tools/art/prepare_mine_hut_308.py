#!/usr/bin/env python3
"""Pinned Ivo mesh dependency and isolated Mine Hut review project."""
from pathlib import Path
import subprocess,shutil,json,argparse,hashlib,struct,re
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/minehut-308';FARM='ef70f8052cf547407eaa09fd881839bf2df929e3'
GODOT=shutil.which('godot') or str(Path.home()/'.local/bin/godot')
p=argparse.ArgumentParser();p.add_argument('--helmet',action='store_true');args=p.parse_args()
def gitfile(rel,dst):
 t=dst/rel;t.parent.mkdir(parents=True,exist_ok=True);t.write_bytes(subprocess.check_output(['git','show',FARM+':'+rel],cwd=ROOT))
if args.helmet:
 dest=OUT/'helmet';dest.mkdir(parents=True,exist_ok=True)
 for f in ['assets/avatar/parts/hairhat_npc_ivo_scene.tscn','assets/avatar/source/hairhat_npc_ivo/T_ivo_hairHat_D.png','modules/avatar/shaders/avatar_toon.gdshader']:gitfile(f,dest)
 (dest/'project.godot').write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
 (dest/'export.gd').write_text('''extends SceneTree
func _initialize():
 var n=load("res://assets/avatar/parts/hairhat_npc_ivo_scene.tscn").instantiate();root.add_child(n)
 for m in n.find_children("*","MeshInstance3D",true,false):
  var mat=StandardMaterial3D.new();mat.albedo_texture=load("res://assets/avatar/source/hairhat_npc_ivo/T_ivo_hairHat_D.png");m.material_override=mat
 var doc=GLTFDocument.new();var state=GLTFState.new();doc.append_from_scene(n,state);doc.write_to_filesystem(state,"res://../ivo_runtime.glb");quit()
''')
 subprocess.run([GODOT,'--headless','--path',str(dest),'--editor','--import'],check=True)
 subprocess.run([GODOT,'--headless','--path',str(dest),'--script','res://export.gd'],check=True)
 raise SystemExit(0)
# External shared atlas references let individual GLBs preview correctly too.
kit=ROOT/'assets/rooms/mine_hut'
for file in sorted(kit.glob('*.glb')):
 raw=file.read_bytes();length,kind=struct.unpack_from('<II',raw,12);d=json.loads(raw[20:20+length]);tail=raw[20+length:]
 d['images']=[{'uri':'room_albedo_ao.png'}];d['textures']=[{'source':0}]
 for m in d['materials']:m.setdefault('pbrMetallicRoughness',{})['baseColorTexture']={'index':0}
 data=json.dumps(d,separators=(',',':')).encode();data+=b' '*((-len(data))%4)
 file.write_bytes(struct.pack('<III',0x46546C67,2,20+len(data)+len(tail))+struct.pack('<II',len(data),0x4E4F534A)+data+tail)
 # Godot generates stable import metadata after staging; all knobs already constrained.
 rel='res://'+str(file.relative_to(ROOT));h=hashlib.md5(rel.encode()).hexdigest();scn='res://.godot/imported/'+file.name+'-'+h+'.scn'
 template=(ROOT/'assets/rooms/blacksmith_shop/forge_stool.glb.import').read_text()
 template=re.sub(r'uid="[^"]+"\n','',template)
 template=re.sub(r'res://.godot/imported/forge_stool.glb-[^"]+.scn',scn,template)
 template=template.replace('res://assets/rooms/blacksmith_shop/forge_stool.glb',rel)
 Path(str(file)+'.import').write_text(template)
stats=json.loads((kit/'asset_stats.json').read_text())
for asset in stats['assets']:asset['bytes']=(kit/(asset['name']+'.glb')).stat().st_size
stats['materials']=1+len(json.loads((kit/'layout.json').read_text())['material_overrides'])
stats['glb_bytes']=sum(a['bytes'] for a in stats['assets']);stats['atlas_bytes']=(kit/'room_albedo_ao.png').stat().st_size
(kit/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
subprocess.run(['python',str(ROOT/'tools/dev/scene_bench/prepare.py'),'mine_hut','--output','output/minehut-308/project'],cwd=ROOT,check=True)
dest=OUT/'project';ids=['hairhat_npc_ivo','mask16_npc_ivo','cloth1_npc_ivo','shoes3']
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',FARM,'assets/avatar/parts','assets/avatar/source'],cwd=ROOT,text=True).splitlines()
for f in paths:
 if (f.startswith('assets/avatar/parts/') and any(Path(f).name in [i+'.res',i+'_scene.tscn'] for i in ids)) or (f.endswith('.png') and any('/'+i+'/' in f for i in ids)):gitfile(f,dest)
manifest=json.loads(subprocess.check_output(['git','show',FARM+':assets/avatar/parts_manifest.json'],cwd=ROOT))
manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']+ids]
(dest/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
p=dest/'project.godot';p.write_text(p.read_text().replace('SensenSceneBench','SensenMineHut308QA').replace('res://tools/dev/scene_bench/scene_bench.tscn','res://review.tscn'))
(dest/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="MineHutReview" type="Node"]\nscript=ExtResource("1")\n')
shutil.copy2(ROOT/'tools/art/review_mine_hut_308.gd',dest/'review.gd')
print(dest)
