from pathlib import Path
import subprocess,shutil,tarfile,io,json,hashlib,argparse
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
ap=argparse.ArgumentParser();ap.add_argument('--template',type=Path,required=True);ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
OUT=args.out.resolve();OUT.mkdir(parents=True,exist_ok=True);P=OUT/'project';W=ROOT
if not P.exists():shutil.copytree(args.template,P,ignore=shutil.ignore_patterns('captures','reports'))
def extract(ref,paths):
 data=subprocess.check_output(['git','archive',ref,*paths],cwd=ROOT)
 with tarfile.open(fileobj=io.BytesIO(data)) as t:t.extractall(P,filter='data')
extract('069dfeb13',['scenes','modules','tests','assets/p0'])
extract('2516abd7',['assets/rooms/market_plaza','scenes/market_plaza','assets/landmarks/_shared/ground_detail','assets/landmarks/_shared/street_kit','assets/landmarks/_shared/far_backdrop'])
# All supplier props from accepted v1; new keeper uses an isolated resource path.
extract('288b47b94',['assets/rooms/market_plaza'])
N=P/'assets/review_keeper';N.mkdir(exist_ok=True)
for version in ['before','after']:
 data=subprocess.check_output(['git','show','288b47b94:assets/rooms/market_plaza/stall_keeper.glb']) if version=='before' else (W/'assets/rooms/market_plaza/stall_keeper.glb').read_bytes()
 dest=N/(version+'.glb');dest.write_bytes(data)
 cfg=(W/'assets/rooms/market_plaza/stall_keeper.glb.import').read_text()
 import re
 cfg=re.sub(r'^uid=.*\n','',cfg,flags=re.M)
 source='res://assets/review_keeper/'+version+'.glb';cache='res://.godot/imported/'+version+'.glb-'+hashlib.md5(source.encode()).hexdigest()+'.scn'
 cfg=re.sub(r'path="res://.godot/imported/[^"\n]+"',f'path="{cache}"',cfg,count=1)
 cfg=re.sub(r'source_file="[^"\n]+"',f'source_file="{source}"',cfg)
 cfg=re.sub(r'dest_files=\[[^\n]+\]',f'dest_files=["{cache}"]',cfg)
 Path(str(dest)+'.import').write_text(cfg)
table=P/'assets/p0/p0_outposts.json';d=json.loads(table.read_text())
rows=next(v for v in d.values() if isinstance(v,list))
o=next(v for v in rows if v['id']=='sh_market_1');o.update(art='market_plaza',bounds=[-8,8,-8,8],anchors='',seats=['seat_1','seat_2'])
table.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
room=P/'scenes/p0/rooms/p0_room.gd';s=room.read_text()
s=s.replace('_cam_dir = at_farm_pitch(_cam_dir)','_cam_dir = _cam_dir if layout_path.contains("market_plaza") else at_farm_pitch(_cam_dir)')
s=s.replace('_cam_size = FarmCamera.player_scale_size(view, rad_to_deg(asin(_cam_dir.y)))','_cam_size = 6.72 if layout_path.contains("market_plaza") else FarmCamera.player_scale_size(view, rad_to_deg(asin(_cam_dir.y)))')
room.write_text(s)
proj=(P/'project.godot').read_text().replace('ChurchCFinal423QA','MarketKeeper218QA').replace('HuangzhongChurchCFinal423QA','HuangzhongMarketKeeper218QA');(P/'project.godot').write_text(proj)
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://keeper_review.gd" id="1"]\n[node name="KeeperReview" type="Node"]\nscript=ExtResource("1")\n')
shutil.copy2(SRC/'keeper_opening_review.gd',P/'keeper_review.gd')
print('Isolated runtime',P)
