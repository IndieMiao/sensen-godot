"""Isolated current farm-dev P0 runtime; no gameplay patch or live connection."""
from pathlib import Path
import subprocess, tarfile, io, shutil, json, hashlib
ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'output/market-generic-v2-218'; QA=OUT/'runtime'
BASE='80800a3d2'
def stage():
    OUT.mkdir(parents=True,exist_ok=True)
    if not (QA/'project.godot').exists():
        QA.mkdir()
        raw=subprocess.check_output(['git','archive',BASE,'--','assets','modules','scenes','tests','addons','tools/dev','project.godot','icon.svg','icon.svg.import'],cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(raw)) as t:t.extractall(QA,filter='data')
        p=QA/'project.godot';s=p.read_text()
        s=s.replace('config/name="SensenAvatar"','config/name="MarketGenericV2Review"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="SensenMarketGenericV2Review"')
        for a,b in [('viewport_height=640','viewport_height=800'),('window_width_override=720','window_width_override=360'),('window_height_override=1280','window_height_override=800'),('window/stretch/aspect="expand"','window/stretch/aspect="keep"'),('run/main_scene="res://scenes/city_select/city_select.tscn"','run/main_scene="res://generic_review.tscn"'),('https://farm.sensenjoy.cn/preview/journey/v1','http://127.0.0.1:9/v1'),('https://farm.sensenjoy.cn/v1','http://127.0.0.1:9/v1'),('enabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg")','enabled=PackedStringArray()')]:s=s.replace(a,b)
        p.write_text(s)
        (OUT/'runtime-base.txt').write_text(subprocess.check_output(['git','rev-parse',BASE],cwd=ROOT,text=True))
    for i in range(4):
        rel=f'assets/rooms/market_plaza/facade_generic_{i}.glb'
        shutil.copy2(ROOT/rel,QA/rel)
        shutil.copy2(ROOT/(rel+'.import'),QA/(rel+'.import'))
        # Review-only v1 files share this same runtime; scene chooses these
        # through its existing variant table after assembly, without production edits.
        (QA/f'assets/rooms/market_plaza/generic_v1_{i}.glb').write_bytes(subprocess.check_output(['git','show','76a363edf:'+rel],cwd=ROOT))
    shutil.copy2(ROOT/'assets/rooms/market_plaza/layout.json',QA/'assets/rooms/market_plaza/layout.json')
    shutil.copy2(ROOT/'tools/art/source/market_plaza/generic_review.gd',QA/'generic_review.gd')
    (QA/'generic_review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://generic_review.gd" id="1"]\n[node name="MarketReview" type="Node"]\nscript=ExtResource("1")\n')
    protected=['scenes/p0/p0_outpost.gd','scenes/p0/rooms/p0_room.gd','scenes/market_plaza/market_plaza_art.gd','assets/p0/p0_outposts.json']
    for rel in protected:assert (QA/rel).read_bytes()==subprocess.check_output(['git','show',BASE+':'+rel],cwd=ROOT),rel
    print('STAGED',QA,'runtime',BASE,flush=True)
if __name__=='__main__':stage()
