"""Retain explicit fine-geometry and mobile texture settings in source and review."""
from pathlib import Path
import shutil
import sys
ROOT=Path(__file__).resolve().parents[2]
slug=sys.argv[1]
kit=ROOT/'assets/rooms'/slug
staged=ROOT/'output'/(slug+'-2026-10-07')/'godot-project/assets/rooms'/slug
for f in staged.glob('*.import'):
    text=f.read_text()
    if f.name.endswith('.png.import'):
        text=text.replace('compress/mode=0','compress/mode=2').replace('mipmaps/generate=false','mipmaps/generate=true')
    else:
        text=text.replace('meshes/generate_lods=true','meshes/generate_lods=false').replace('meshes/force_disable_compression=false','meshes/force_disable_compression=true')
    f.write_text(text);shutil.copy2(f,kit/f.name)
print('Mobile atlas and fine geometry import settings retained:',slug)
