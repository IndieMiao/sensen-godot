"""Isolated P0 runtime on farm-dev; before assets stored under review-only names."""
from pathlib import Path
import subprocess,io,tarfile,shutil,json
ROOT=Path(__file__).resolve().parents[4];HERE=Path(__file__).resolve().parent;OUT=ROOT/'output/market-facade-seams-218';QA=OUT/'runtime'
BASE='827720f0a';ART='c7a0a4b6a'
def main():
 OUT.mkdir(exist_ok=True,parents=True)
 if not (QA/'project.godot').exists():
  QA.mkdir(exist_ok=True)
  raw=subprocess.check_output(['git','archive',BASE,'--','assets','modules','scenes','tests','addons','tools/dev','project.godot','icon.svg','icon.svg.import'],cwd=ROOT)
  with tarfile.open(fileobj=io.BytesIO(raw)) as t:t.extractall(QA,filter='data')
  cache=Path('/home/zhangshaoji/.herdr/worktrees/sensen-godot/wt-3d-makeboluo-market-generic-v2/output/market-generic-v2-218/runtime/.godot')
  if cache.exists():shutil.copytree(cache,QA/'.godot',dirs_exist_ok=True)
  p=QA/'project.godot';s=p.read_text().replace('config/name="SensenAvatar"','config/name="MarketFacadeSeamsReview"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="SensenMarketFacadeSeamsReview"')
  for a,b in [('viewport_height=640','viewport_height=800'),('window_width_override=720','window_width_override=360'),('window_height_override=1280','window_height_override=800'),('window/stretch/aspect="expand"','window/stretch/aspect="keep"'),('run/main_scene="res://scenes/city_select/city_select.tscn"','run/main_scene="res://seam_review.tscn"'),('https://farm.sensenjoy.cn/preview/journey/v1','http://127.0.0.1:9/v1'),('https://farm.sensenjoy.cn/v1','http://127.0.0.1:9/v1'),('enabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg")','enabled=PackedStringArray()')]:s=s.replace(a,b)
  p.write_text(s);(OUT/'runtime-base.txt').write_text(subprocess.check_output(['git','rev-parse',BASE],cwd=ROOT,text=True))
 for path in (ROOT/'assets/rooms/market_plaza').glob('facade_*.glb'):
  rel=path.relative_to(ROOT);shutil.copy2(path,QA/rel);shutil.copy2(str(path)+'.import',str(QA/rel)+'.import')
  (QA/rel.parent/('before_'+path.name)).write_bytes(subprocess.check_output(['git','show',ART+':'+str(rel)],cwd=ROOT))
 shutil.copy2(ROOT/'assets/rooms/market_plaza/layout.json',QA/'assets/rooms/market_plaza/layout.json')
 shutil.copy2(HERE/'review.gd',QA/'seam_review.gd')
 (QA/'seam_review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://seam_review.gd" id="1"]\n[node name="SeamReview" type="Node"]\nscript=ExtResource("1")\n')
 print('SEAM_REVIEW_STAGED',BASE)
if __name__=='__main__':main()
