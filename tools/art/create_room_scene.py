"""Create a scene-specific assembler from the established read-only art contract."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
slug=sys.argv[1]
dst=ROOT/'scenes'/slug;dst.mkdir(exist_ok=True)
text=(ROOT/'scenes/standard_room_5/standard_room_5_art.gd').read_text().replace('standard_room_5/',slug+'/')
text=text.replace('asset.name == "window_garden"','str(asset.name).ends_with("garden")')
text=text.replace('asset.name == "fire"','asset.name == "fire" or str(asset.name).ends_with("_glow")')
text=text.replace('var fire: Node3D','var fire: Node3D\nvar variant_materials: Dictionary = {}')
text=text.replace('container.position = _vec(placement.position)',
                  'container.position = _vec(placement.position)\n\tcontainer.scale = _vec(placement.get("scale", [1.0,1.0,1.0]))')
text=text.replace('\t_set_material(model, applied)', '''\tif asset.name == "display_glass":
\t\tapplied = material.duplicate()
\t\tapplied.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
\t\tapplied.albedo_color = Color(0.90, 0.97, 1.0, 0.12)
\t\tapplied.roughness = 0.14
\t\tapplied.cull_mode = BaseMaterial3D.CULL_DISABLED
\t\t_disable_shadows(model)
\tvar variant_key := "plain"
\tif str(asset.name).ends_with("garden"): variant_key = "garden"
\tif asset.name == "fire" or str(asset.name).ends_with("_glow"): variant_key = "glow"
\tif asset.name == "display_glass": variant_key = "glass"
\tif variant_materials.has(variant_key): applied = variant_materials[variant_key]
\telse: variant_materials[variant_key] = applied
\t_set_material(model, applied)''')
(dst/(slug+'_art.gd')).write_text(text)
(dst/(slug+'_art.tscn')).write_text('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scenes/'+slug+'/'+slug+'_art.gd" id="1"]\n\n[node name="'+''.join(x.title() for x in slug.split('_'))+'Art" type="Node3D"]\nscript = ExtResource("1")\n')
