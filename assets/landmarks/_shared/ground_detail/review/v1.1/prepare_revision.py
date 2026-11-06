from pathlib import Path
import sys,subprocess,shutil
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'tools/art/source/ground_detail_428').is_dir());SRC=ROOT/'tools/art/source/ground_detail_428';OUT=ROOT/'output/ground-detail-428-v11'
sys.path.insert(0,str(SRC));import prepare
prepare.OUT=OUT;prepare.QA=OUT/'project';prepare.main()
qa=prepare.QA
review=(qa/'review.gd').read_text()
review=review.replace('if name=="sand_close":', 'if name=="wood_close":target=Vector3(0,0.25,0);width=3.6;vp.size=Vector2i(1000,750)\n if name=="sand_close":')
review=review.replace('["default","whole","grass_close","hard_close","sand_close"]','["default","wood_close","sand_close"]')
(qa/'review.gd').write_text(review)
# Preserve v1 read-only in the isolated QA project for exact same-camera controls.
old=qa/'baseline';old.mkdir(exist_ok=True)
rel='assets/landmarks/_shared/ground_detail/'
for name in ['ground_detail.gdshader','ground_palette_example.tres']:
 data=subprocess.check_output(['git','show','54b76f78f:'+rel+name],cwd=ROOT)
 if name.endswith('.tres'):data=data.replace((rel+'ground_detail.gdshader').encode(),b'baseline/ground_detail.gdshader')
 (old/name).write_bytes(data)
review=review.replace('terrain.material_override=material;await capture(view)', 'terrain.material_override=load("res://baseline/ground_palette_example.tres");await capture(view+"-before")\n  terrain.material_override=material;await capture(view)')
review=review.replace('428-v1','428-v1.1')
(qa/'review.gd').write_text(review)
print('Revision project ready',qa)
