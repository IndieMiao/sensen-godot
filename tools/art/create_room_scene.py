"""Generate an explicit art assembler; no transformations of another scene."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
slug=sys.argv[1]
assert slug in ('deluxe_room_10','farm_tools_store','bakery','post_office','tavern','blacksmith_shop')
dst=ROOT/'scenes'/slug;dst.mkdir(exist_ok=True)
text=(ROOT/'tools/art/templates/room_art.gd.txt').read_text().replace('__SLUG__',slug)
(dst/(slug+'_art.gd')).write_text(text)
(dst/(slug+'_art.tscn')).write_text('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scenes/'+slug+'/'+slug+'_art.gd" id="1"]\n\n[node name="'+''.join(x.title() for x in slug.split('_'))+'Art" type="Node3D"]\nscript = ExtResource("1")\n')
