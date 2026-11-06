from pathlib import Path
import json,hashlib,shutil
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/rooms/_shared/church_kit';OUT=ROOT/'output/church-kit-427-v11';P=OUT/'project';REL=KIT.relative_to(ROOT)
if not P.exists():shutil.copytree(ROOT/'output/church-kit-423/project',P)
# Hide the old room in the isolated project scan; reused avatar stays in this cached fixture.
for directory in ['assets/rooms/tea_house','assets/rooms/_shared']:
 old=P/directory
 if old.exists():(old/'.gdignore').touch()
# A parent .gdignore would hide our new kit too, so remove only this fixture's copied shared guard.
shared=P/'assets/rooms/_shared/.gdignore'
if shared.exists():shared.unlink()
for d in (P/'assets/rooms/_shared').iterdir():
 if d.is_dir() and d.name!='church_kit':(d/'.gdignore').touch()
for name in ['classic','meadow']:
 (KIT/('glass_palette_'+name+'.tres')).write_text('[gd_resource type="ShaderMaterial" load_steps=3 format=3]\n[ext_resource type="Shader" path="res://'+str(REL)+'/stained_glass.gdshader" id="1"]\n[ext_resource type="Texture2D" path="res://'+str(REL)+'/glass_palette_'+name+'.png" id="2"]\n[resource]\nshader = ExtResource("1")\nshader_parameter/palette_texture = ExtResource("2")\nshader_parameter/glow_strength = 0.12\n')
(KIT/'opaque_vertex.tres').write_text('[gd_resource type="StandardMaterial3D" format=3]\n[resource]\nvertex_color_use_as_albedo = true\nroughness = 0.88\nmetallic_specular = 0.16\n')
(KIT/'opaque_atlas.tres').write_text('[gd_resource type="StandardMaterial3D" load_steps=2 format=3]\n[ext_resource type="Texture2D" path="res://assets/rooms/poi_church/room_albedo_ao.png" id="1"]\n[resource]\nalbedo_texture = ExtResource("1")\nroughness = 0.88\nmetallic_specular = 0.16\n')
for file in KIT.glob('*.glb'):
 cfg=Path(str(file)+'.import')
 if not cfg.exists():
  resource='res://'+str(file.relative_to(ROOT));cache=f'res://.godot/imported/{file.name}-{hashlib.md5(resource.encode()).hexdigest()}.scn'
  cfg.write_text(f'[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="{cache}"\n[deps]\nsource_file="{resource}"\ndest_files=["{cache}"]\n[params]\nnodes/root_script=null\nmeshes/ensure_tangents=true\nmeshes/generate_lods=false\nmeshes/create_shadow_meshes=true\nmeshes/light_baking=1\nanimation/import=false\ngltf/texture_map_mode=1\nimport_script/path="res://{REL}/church_kit_import.gd"\n')
for file in KIT.glob('*.png'):
 cfg=Path(str(file)+'.import')
 if not cfg.exists():
  pal=file.name.startswith('glass_palette');resource='res://'+str(file.relative_to(ROOT))
  cfg.write_text(f'[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n[deps]\nsource_file="{resource}"\n[params]\ncompress/mode={0 if pal else 2}\nmipmaps/generate={"false" if pal else "true"}\ndetect_3d/compress_to={0 if pal else 2}\n')
# Refresh only this isolated fixture's kit and its single shared dependency.
if (P/REL).exists():shutil.rmtree(P/REL)
shutil.copytree(KIT,P/REL)
dep=P/'assets/rooms/poi_church'
if dep.exists():shutil.rmtree(dep)
dep.mkdir(parents=True)
for name in ['room_albedo_ao.png','room_albedo_ao.png.import']:
 shutil.copy2(ROOT/'assets/rooms/poi_church'/name,dep/name)
for file in SRC.glob('*.gd'):shutil.copy2(file,P/file.name)
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="ChurchKitReview" type="Node"]\nscript=ExtResource("1")\n')
p=P/'project.godot';p.write_text(p.read_text().replace('SensenChurch423QA','SensenChurchKit423QA').replace('res://tools/dev/scene_bench/scene_bench.tscn','res://review.tscn'))
p.write_text(p.read_text().replace('textures/vram_compression/import_etc2_astc=false','textures/vram_compression/import_etc2_astc=true'))
assert 'textures/vram_compression/import_etc2_astc=true' in p.read_text()
print(P)
