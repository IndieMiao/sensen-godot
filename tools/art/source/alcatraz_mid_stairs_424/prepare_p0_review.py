from pathlib import Path
import subprocess,tarfile,io,shutil
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];OUT=ROOT/'output/alcatraz-mid-stairs-424';QA=OUT/'runtime';BASE='cf82ca0ac'
if not (QA/'project.godot').exists():
 QA.mkdir(parents=True)
 archive=subprocess.check_output(['git','archive',BASE,'--','assets','modules','scenes','tests','addons','project.godot','icon.svg','icon.svg.import'],cwd=ROOT)
 with tarfile.open(fileobj=io.BytesIO(archive)) as tar:tar.extractall(QA,filter='data')
 p=QA/'project.godot';s=p.read_text().replace('config/name="SensenAvatar"','config/name="AlcatrazMidStairs424Review"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="SensenAlcatrazMidStairs424Review"')
 s=s.replace('window/size/viewport_height=640','window/size/viewport_height=800').replace('window/size/window_width_override=720','window/size/window_width_override=360').replace('window/size/window_height_override=1280','window/size/window_height_override=800').replace('window/stretch/aspect="expand"','window/stretch/aspect="keep"')
 s=s.replace('run/main_scene="res://scenes/city_select/city_select.tscn"','run/main_scene="res://mid_stairs_review.tscn"').replace('https://farm.sensenjoy.cn/preview/journey/v1','http://127.0.0.1:9/v1').replace('https://farm.sensenjoy.cn/v1','http://127.0.0.1:9/v1')
 s=s.replace('enabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg")','enabled=PackedStringArray()')
 p.write_text(s);(OUT/'runtime-base.txt').write_text(subprocess.check_output(['git','rev-parse',BASE],cwd=ROOT,text=True))
shutil.copytree(ROOT/'assets/landmarks/alcatraz_island',QA/'assets/landmarks/alcatraz_island',dirs_exist_ok=True)
# Keep the P0 integrated scripts from farm-dev byte-identical. Only stage art/data.
shutil.copy2(HERE/'review.gd',QA/'mid_stairs_review.gd')
shutil.copy2(HERE.parent/'alcatraz_island/review.gd',QA/'hud_helper.gd')
(QA/'mid_stairs_review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://mid_stairs_review.gd" id="1"]\n[node name="Review" type="Node"]\nscript=ExtResource("1")\n')
(ROOT/'output/.gdignore').touch();print('staged',QA,flush=True)
