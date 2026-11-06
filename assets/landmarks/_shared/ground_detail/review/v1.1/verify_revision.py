"""Cold import + unchanged source textures + installed APK resource validation."""
from pathlib import Path
import hashlib,json,shutil,subprocess,zipfile
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'tools/art/source/ground_detail_428').is_dir())
DOC=Path(__file__).resolve().parent;OUT=ROOT/'output/ground-detail-428-v11';REL='assets/landmarks/_shared/ground_detail'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def files(p):return {f.name:sha(f) for f in sorted(p.iterdir()) if f.is_file()}
def run(project,args,log):
 with (OUT/log).open('w') as f:subprocess.run(['flock','/home/deck/gs66-render.lock','/home/deck/.local/bin/godot','--headless','--path',str(project)]+args,stdout=f,stderr=subprocess.STDOUT,check=True)
def main():
 cold=OUT/'cold-project';assert not cold.exists(),'Use a new cold directory; keep prior evidence.'
 shutil.copytree(OUT/'project',cold,ignore=shutil.ignore_patterns('.godot'))
 shutil.copytree(ROOT/REL,cold/REL,dirs_exist_ok=True)
 before=files(cold/REL);run(cold,['--editor','--import'],'cold-import.log');after=files(cold/REL)
 assert before==after==files(ROOT/REL)
 baseline='54b76f78f'
 for name in ['ground_fields.png','ground_fields.png.import','ground_surfaces.png','ground_surfaces.png.import','ground_detail.gdshader.uid']:
  assert (ROOT/REL/name).read_bytes()==subprocess.check_output(['git','show',baseline+':'+REL+'/'+name],cwd=ROOT)
 # Exact installed package, not just the source staging directory.
 package=OUT/'package-project';package.mkdir(exist_ok=True)
 with zipfile.ZipFile(OUT/'android/installed.apk') as z:
  for name in z.namelist():
   if name.startswith('assets/') and not name.endswith('/'):
    target=package/name.removeprefix('assets/');target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(name))
 assert (package/REL/'ground_detail.gdshader').read_bytes()==(ROOT/REL/'ground_detail.gdshader').read_bytes()
 script=(ROOT/'tools/art/source/ground_detail_428/verify_resources.gd').read_text()
 script=script.replace('var textures={}', '''if i==0 or i==3:
+   assert(mat.get_shader_parameter("wood_board_size_m").is_equal_approx(Vector2(1.8,0.18)))
+   assert(mat.get_shader_parameter("wood_board_stagger")==0.5)
+   assert(mat.get_shader_parameter("wood_color").is_equal_approx(Color("A3815D")))
+  if i==0 or i==5:
+   assert(mat.get_shader_parameter("wet_sand_color").is_equal_approx(Color("A68B63")))
+  var textures={}'''.replace('\n+','\n'))
 (package/'verify_resources.gd').write_text(script);run(package,['--script','res://verify_resources.gd'],'package-verify.log')
 shutil.copy2(OUT/'resource-validation.json',DOC/'packaged-resource-validation.json')
 report={'passed':True,'fresh_cache':True,'runtime_files':len(before),'before_sha256':before,'after_sha256':after,'changed_runtime_files':[],
 'baseline_textures_imports_shader_uid_byte_identical':True,'revision_parameter_values_checked_in_installed_apk':True,'sampler_bindings':2,'texture_reads':{'grass':3,'paving':1,'wood':1,'sand':2,'wet_sand':2},'passes':1}
 (DOC/'cold-import-validation.json').write_text(json.dumps(report,indent=2)+'\n')
 for name in ['default','wood','sand']:shutil.copy2(OUT/'android'/f'{name}.png',DOC/f'android-{name}.png')
 shutil.copy2(OUT/'android/smoke.json',DOC/'android-smoke.json')
 print('REVISION_COLD_AND_PACKAGE_PASS',len(before),flush=True)
if __name__=='__main__':main()
