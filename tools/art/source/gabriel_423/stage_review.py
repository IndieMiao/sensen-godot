"""Stage an offline runtime fixture; no tracked program files are changed."""
from pathlib import Path
import argparse,subprocess,tarfile,io,shutil,json
R=Path(__file__).resolve().parents[4]
p=argparse.ArgumentParser();p.add_argument('--runtime-ref',default='8493a5c4258db3e59b2b845c83d3ee5b34724156');p.add_argument('--out',default='output/gabriel-423/rebuild-project');a=p.parse_args();P=R/a.out;P.mkdir(parents=True,exist_ok=True);(R/'output/.gdignore').touch()
archive=subprocess.check_output(['git','archive',a.runtime_ref,'modules','assets','scenes','addons','tools/pipeline','icon.svg'],cwd=R)
tarfile.open(fileobj=io.BytesIO(archive)).extractall(P,filter='data')
for rel in ['assets/avatar/source/cloth36_npc_gabriel','assets/avatar/source/hairhat0_npc_gabriel','assets/avatar/parts/cloth36_npc_gabriel.res','assets/avatar/parts/hairhat0_npc_gabriel.res','assets/avatar/parts/hairhat0_npc_gabriel_scene.tscn','assets/avatar/thumbs/cloth36_npc_gabriel.png','assets/avatar/thumbs/cloth36_npc_gabriel.png.import','assets/avatar/thumbs/hairhat0_npc_gabriel.png','assets/avatar/thumbs/hairhat0_npc_gabriel.png.import','assets/avatar/source/recipes_gabriel.json','tools/art/review_gabriel_423.gd','tools/art/verify_gabriel_423.gd','tools/art/extract_gabriel_423.gd','tools/art/bake_resident_portraits.gd']:
 src=R/rel;dst=P/rel;dst.parent.mkdir(parents=True,exist_ok=True)
 if src.is_dir():shutil.copytree(src,dst,dirs_exist_ok=True)
 else:shutil.copy2(src,dst)
manifest=P/'assets/avatar/parts_manifest.json';m=json.loads(manifest.read_text());new=[x for x in json.loads((R/'assets/avatar/parts_manifest.json').read_text())['parts'] if x['id'] in ['cloth36_npc_gabriel','hairhat0_npc_gabriel']];ids=[x['id'] for x in new]+['cloth1_npc_gabriel'];m['parts']=[x for x in m['parts'] if x['id'] not in ids]+new;manifest.write_text(json.dumps(m,indent='\t')+'\n')
npc=P/'assets/avatar/npc_only.json';n=json.loads(npc.read_text());n['npc_only']=[x for x in n['npc_only'] if x not in ids]+[x['id'] for x in new];npc.write_text(json.dumps(n,indent='\t')+'\n')
# --script must defer P0Logic until Avatar/Localization autoloads exist.
baker=P/'tools/art/bake_resident_portraits.gd';baker.write_text(baker.read_text().replace('var content := P0Logic.content()','var content: Dictionary = load("res://modules/p0/p0_logic.gd").content()'))
s=subprocess.check_output(['git','show',a.runtime_ref+':project.godot'],cwd=R,text=True).replace('config/name="SensenAvatar"','config/name="Gabriel 423 QA"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="SensenGabriel423QA"').replace('window/size/window_width_override=720','window/size/window_width_override=360').replace('window/size/window_height_override=1280','window/size/window_height_override=800').replace('https://farm.sensenjoy.cn/v1','http://127.0.0.1:9/v1').replace('https://farm.sensenjoy.cn/preview/journey/v1','http://127.0.0.1:9/v1');(P/'project.godot').write_text(s)
(P/'output').mkdir(exist_ok=True);(P/'output/.gdignore').touch();(P/'output/gabriel-looks.json').write_text(json.dumps({'gabriel':{'slots':{'hairHat':'hairhat0_npc_gabriel','cloth':'cloth36_npc_gabriel','shoes':'shoes3','glass':'glass0'}}},indent=2))
print(P)
