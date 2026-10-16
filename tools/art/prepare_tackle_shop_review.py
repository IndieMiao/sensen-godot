#!/usr/bin/env python3
"""Stage SGODOT-214 and its existing Avatar fixture; configure real imports."""
from pathlib import Path
import subprocess, sys, shutil, hashlib, re
ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'output/tackle-214/project'
KIT=ROOT/'assets/rooms/tackle_shop'
old_importer=DEST/'assets/rooms/tackle_shop/material_import.gd'
importer_changed=not old_importer.exists() or old_importer.read_bytes()!=(KIT/'material_import.gd').read_bytes()
template=(ROOT/'assets/rooms/post_office/fare_board.glb.import').read_text()
def keep_uid(path,text):
    if path.exists():
        match=re.search(r'^uid=.*$',path.read_text(),flags=re.M)
        if match:text=text.replace('[remap]','[remap]\n\n'+match[0],1)
    return text
for glb in KIT.glob('*.glb'):
    relative='res://'+str(glb.relative_to(ROOT))
    imported='res://.godot/imported/'+glb.name+'-'+hashlib.md5(relative.encode()).hexdigest()+'.scn'
    text=re.sub(r'^uid=.*\n','',template,flags=re.M)
    text=re.sub(r'^path=.*$',f'path="{imported}"',text,flags=re.M)
    text=re.sub(r'^source_file=.*$',f'source_file="{relative}"',text,flags=re.M)
    text=re.sub(r'^dest_files=.*$',f'dest_files=["{imported}"]',text,flags=re.M)
    text=text.replace('import_script/path=""','import_script/path="res://assets/rooms/tackle_shop/material_import.gd"')
    target=glb.with_suffix('.glb.import');target.write_text(keep_uid(target,text))
tex_template=(ROOT/'assets/rooms/post_office/room_albedo_ao.png.import').read_text()
relative='res://assets/rooms/tackle_shop/room_albedo_ao.png'
old_hash='997785034d14b09892f961fb83fb2e97'
text=tex_template.replace(old_hash,hashlib.md5(relative.encode()).hexdigest()).replace('rooms/post_office/','rooms/tackle_shop/')
text=re.sub(r'^uid=.*\n','',text,flags=re.M)
target=KIT/'room_albedo_ao.png.import';target.write_text(keep_uid(target,text))
subprocess.run([sys.executable,str(ROOT/'tools/dev/scene_bench/prepare.py'),'tackle_shop','--output',str(DEST)],check=True)
if importer_changed:
    # Invalidate only this task's generated scene caches after importer changes.
    # Godot can otherwise retain scenes from a previous failed post-import.
    for glb in KIT.glob('*.glb'):
        for cached in (DEST/'.godot/imported').glob(glb.name+'-*.scn'):cached.unlink()
project=DEST/'project.godot'
project.write_text(project.read_text().replace('SensenSceneBench','SensenTackle214QA'))
shutil.copy2(ROOT/'tools/art/review_tackle_shop.gd',DEST/'review.gd')
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="TackleReview" type="Node"]\nscript = ExtResource("1")\n')
print(DEST)
