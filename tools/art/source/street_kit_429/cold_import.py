"""Cold-import the delivered kit and unmodified pinned #830 dependency.
Every Godot call takes the shared GPU lock. Only the isolated cache is removed.
"""
from pathlib import Path
import os,json,hashlib,shutil,subprocess
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'output/street-kit-429'
P=OUT/'cold-project';REL=Path('assets/landmarks/_shared/street_kit');GROUND=Path('assets/landmarks/_shared/ground_detail')
def snapshot(root):
 return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file() and '.godot' not in p.relative_to(root).parts}
before_source=snapshot(ROOT/REL)
status_before=subprocess.check_output(['git','status','--porcelain=v1','-z'],cwd=ROOT)
if P.exists():shutil.rmtree(P)
shutil.copytree(ROOT/REL,P/REL);shutil.copytree(OUT/'project'/GROUND,P/GROUND)
(P/'project.godot').write_text('''config_version=5
[application]
config/name="StreetKit429ColdImport"
config/features=PackedStringArray("4.7", "Mobile")
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
before=snapshot(P);log=OUT/'cold-import.log'
with log.open('w') as f:
 run=subprocess.run(['flock',str(Path.home()/'gs66-render.lock'),'godot','--headless','--path',str(P),'--editor','--import'],stdout=f,stderr=subprocess.STDOUT,env=dict(os.environ,ANDROID_ADB_SERVER_PORT='5097'))
after=snapshot(P);changes=sorted(k for k in set(before)|set(after) if before.get(k)!=after.get(k))
assert run.returncode==0 and 'ERROR:' not in log.read_text(),log.read_text()[-3000:]
assert not changes,changes
assert before_source==snapshot(ROOT/REL),'Source kit drift'
assert status_before==subprocess.check_output(['git','status','--porcelain=v1','-z'],cwd=ROOT),'Workspace status drift'
for path in (P/GROUND).glob('*.png.import'):
 text=path.read_text();assert 'etc2_astc' in text or 'compress/mode=0' in text,path
result={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','passed':True,'fresh_cache':True,'exit_code':run.returncode,'etc2_astc_enabled':True,'source_kit_unchanged':True,'workspace_status_unchanged':True,'fixture_file_changes':changes,'fixture_files_checked':len(before),'street_kit_textures':0,'ground_dependency_images_have_mobile_formats':True,'ground_commit':'54b76f78f78eff3f992365c934586e170bd15fb1'}
(OUT/'cold-import-validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False))
