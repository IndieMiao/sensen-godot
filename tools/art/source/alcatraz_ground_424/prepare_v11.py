"""Stage v1.1 and frozen #827 v1 for matched grass-only comparison."""
from pathlib import Path
import subprocess,shutil
import prepare
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
OUT=ROOT/'output/alcatraz-ground-424-v11';QA=OUT/'project'
V1='91c563b16b651c1013d0290e70d611884376ab0f'
def main():
 prepare.OUT=OUT;prepare.QA=QA;prepare.main()
 baseline=QA/'baseline_ground';baseline.mkdir(exist_ok=True)
 for name in ['alc_ground_detail.gdshader','alc_ground_fields.png','alc_terrain_detail.tres']:
  data=subprocess.check_output(['git','show',V1+':assets/landmarks/alcatraz_island/ground/'+name],cwd=ROOT)
  if name.endswith('.tres'):
   text=data.decode()
   for part in ['alc_ground_detail.gdshader','alc_ground_fields.png']:
    text=text.replace('res://assets/landmarks/alcatraz_island/ground/'+part,'res://baseline_ground/'+part)
   data=text.encode()
  (baseline/name).write_bytes(data)
 # Diagnostic shader only in ignored QA: same visibility/texture coordinates,
 # fixed primary colours identify pure deep/base/sun interiors for pixel means.
 shader=(QA/'assets/landmarks/alcatraz_island/ground/alc_ground_detail.gdshader').read_text()
 shader=shader.replace('render_mode diffuse_burley, specular_schlick_ggx;','render_mode unshaded;')
 shader=shader.replace('uniform int finish_kind', 'uniform bool mask_off = false;\nuniform int finish_kind')
 shader=shader.replace('vec3 detailed = base;','vec3 detailed = base;\n    vec3 diagnostic = vec3(0.0);')
 shader=shader.replace('float patch = broad * 0.80 + second * 0.20;', '''float patch = broad * 0.80 + second * 0.20;
            if (up_facing > 0.0) diagnostic = vec3(1.0, 0.0, 1.0);
            if (up_facing > 0.98) {
                if (patch < 0.41) diagnostic = vec3(1.0, 0.0, 0.0);
                if (patch > 0.47 && patch < 0.53) diagnostic = vec3(0.0, 1.0, 0.0);
                if (patch > 0.60) diagnostic = vec3(0.0, 0.0, 1.0);
            }''')
 shader=shader.replace('ALBEDO = mix(base, detailed, strength * up_facing);','ALBEDO = mask_off ? vec3(0.0) : diagnostic;')
 (QA/'grass_diagnostic.gdshader').write_text(shader)
 for name in ['review_v11.gd','configure_v11.gd']:shutil.copy2(SRC/name,QA/name)
 (QA/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review_v11.gd" id="1"]\n[node name="GroundGrassReview" type="Node"]\nscript=ExtResource("1")\n')
 print('v1.1 project:',QA)
if __name__=='__main__':main()
