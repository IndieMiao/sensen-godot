"""Create a scene-specific assembler from the established read-only art contract."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
slug=sys.argv[1]
dst=ROOT/'scenes'/slug;dst.mkdir(exist_ok=True)
text=(ROOT/'scenes/standard_room_5/standard_room_5_art.gd').read_text().replace('standard_room_5/',slug+'/')
text=text.replace('asset.name == "window_garden"','str(asset.name).ends_with("garden")')
text=text.replace('\t_set_material(model, applied)', '''\tif asset.name == "display_glass":
\t\tapplied = material.duplicate()
\t\tapplied.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
\t\tapplied.albedo_color = Color(0.90, 0.97, 1.0, 0.12)
\t\tapplied.roughness = 0.14
\t\tapplied.cull_mode = BaseMaterial3D.CULL_DISABLED
\t\t_disable_shadows(model)
\t_set_material(model, applied)''')
(dst/(slug+'_art.gd')).write_text(text)
(dst/(slug+'_art.tscn')).write_text('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scenes/'+slug+'/'+slug+'_art.gd" id="1"]\n\n[node name="'+''.join(x.title() for x in slug.split('_'))+'Art" type="Node3D"]\nscript = ExtResource("1")\n')
