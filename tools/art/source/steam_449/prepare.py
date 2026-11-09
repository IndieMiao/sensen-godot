from pathlib import Path
import shutil,subprocess,hashlib,argparse,json
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
a=argparse.ArgumentParser();a.add_argument('--out',type=Path,required=True);args=a.parse_args();P=args.out.resolve()/'project';P.mkdir(parents=True,exist_ok=True)
for rel in ['assets/props/stove_pot','assets/props/cooking_pot_wait','assets/props/warming_cabinet']:shutil.copytree(ROOT/rel,P/rel,dirs_exist_ok=True)
# Reference integration host, changed only in this review fixture to expand its canvas.
host_ref=json.loads((SRC/'reference/base.json').read_text())['host_base']
ref=subprocess.check_output(['git','show',host_ref+':scenes/p0/kitchen/p0_wait_pot.gd'],cwd=ROOT,text=True)
(P/'wait_host.gd').write_text(ref.replace('Rect2(80, 150, 200, 180)','Rect2(80, 110, 200, 220)'))
shutil.copy2(SRC/'review.gd',P/'review.gd')
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="Steam449Review" type="Node"]\nscript=ExtResource("1")\n')
(P/'project.godot').write_text('''config_version=5
[application]
config/name="Steam449IsolatedReview"
config/features=PackedStringArray("4.7", "Mobile")
run/main_scene="res://review.tscn"
config/use_custom_user_dir=true
config/custom_user_dir_name="HuangzhongSteam449QA"
[display]
window/size/viewport_width=360
window/size/viewport_height=800
window/size/window_width_override=360
window/size/window_height_override=800
window/stretch/mode="disabled"
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_etc2_astc=true
textures/vram_compression/import_s3tc_bptc=true
''')
png=P/'assets/props/cooking_pot_wait/steam_puff.png';imp=Path(str(png)+'.import')
if not imp.exists():
 res='res://assets/props/cooking_pot_wait/steam_puff.png';cache='res://.godot/imported/steam_puff.png-'+hashlib.md5(res.encode()).hexdigest()+'.ctex'
 imp.write_text(f'''[remap]
importer="texture"
type="CompressedTexture2D"
path="{cache}"
[deps]
source_file="{res}"
dest_files=["{cache}"]
[params]
compress/mode=0
mipmaps/generate=true
process/fix_alpha_border=true
detect_3d/compress_to=0
''')
print(P)
