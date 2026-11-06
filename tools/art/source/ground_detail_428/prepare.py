"""Stage an independent 20m review pad. No game scenes, layout or owner files."""
from pathlib import Path
import shutil

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[3]
OUT = ROOT / 'output/ground-detail-428'
QA = OUT / 'project'
REL = 'assets/landmarks/_shared/ground_detail'

def main():
    QA.mkdir(parents=True, exist_ok=True)
    (OUT.parent / '.gdignore').touch()
    shutil.copytree(ROOT / REL, QA / REL, dirs_exist_ok=True)
    for name in ['review.gd', 'configure_imports.gd', 'verify_resources.gd']:
        shutil.copy2(SRC / name, QA / name)
    shader = (ROOT / REL / 'ground_detail.gdshader').read_text()
    shader = shader.replace('render_mode diffuse_burley, specular_schlick_ggx;', 'render_mode unshaded;')
    shader = shader.replace('vec3 detailed = base;', 'vec3 detailed = base;\n    vec3 diagnostic = vec3(0.0);')
    shader = shader.replace('float patch = mix(broad, second, grass_secondary_mix);', '''float patch = mix(broad, second, grass_secondary_mix);
        if (patch < grass_deep_transition.x) diagnostic = vec3(1.0, 0.0, 0.0);
        if (patch > grass_deep_transition.y + 0.01 && patch < grass_sun_transition.x - 0.01) diagnostic = vec3(0.0, 1.0, 0.0);
        if (patch > grass_sun_transition.y) diagnostic = vec3(0.0, 0.0, 1.0);''')
    shader = shader.replace('detailed = mix(sand_color.rgb, wet_sand_color.rgb, wet);', '''if (kind == 4) diagnostic = vec3(1.0, 1.0, 0.0);
        if (kind == 5 && wet > 0.999 && band < 0.001) diagnostic = vec3(0.0, 1.0, 1.0);
        detailed = mix(sand_color.rgb, wet_sand_color.rgb, wet);''')
    shader = shader.replace('ALBEDO = mix(base, detailed, coverage);', 'ALBEDO = diagnostic;')
    (QA / 'diagnostic.gdshader').write_text(shader)
    (QA / 'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="SharedGroundReview" type="Node"]\nscript=ExtResource("1")\n')
    (QA / 'project.godot').write_text('''config_version=5
[application]
config/name="Shared Ground 428 QA"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenGround428QA"
run/main_scene="res://review.tscn"
[display]
window/size/viewport_width=360
window/size/viewport_height=800
window/size/window_width_override=360
window/size/window_height_override=800
window/stretch/mode="canvas_items"
window/handheld/orientation=1
window/frame_pacing/android/enable_frame_pacing=false
[input_devices]
pointing/emulate_mouse_from_touch=true
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
anti_aliasing/quality/msaa_3d=2
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
    print(QA)

if __name__ == '__main__':
    main()
