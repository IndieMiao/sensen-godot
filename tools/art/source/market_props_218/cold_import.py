"""Fresh isolated Godot cache; confirm the delivered kit's import metadata is stable."""
from pathlib import Path
import argparse,json,hashlib,shutil,subprocess,os
ROOT=Path(__file__).resolve().parents[4];REL=Path('assets/rooms/market_plaza')
p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args();out=a.out.resolve();proj=out/'cold-project'
assert not proj.exists(),'Choose a new cold-project path, preserve previous evidence.'
shutil.copytree(ROOT/REL,proj/REL)
(proj/'project.godot').write_text('''config_version=5
[application]
config/name="Market218ColdImport"
config/features=PackedStringArray("4.7", "Mobile")
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
def snapshot(root):return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file() and '.godot' not in p.relative_to(root).parts}
before=snapshot(proj);source=snapshot(ROOT/REL);status=subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=ROOT)
with (out/'cold-import.log').open('w') as f:r=subprocess.run(['flock',str(Path.home()/'gs66-render.lock'),'godot','--headless','--path',str(proj),'--editor','--import'],stdout=f,stderr=subprocess.STDOUT)
after=snapshot(proj);changed=[k for k in set(before)|set(after) if before.get(k)!=after.get(k)]
errors=[s for s in (out/'cold-import.log').read_text().splitlines() if 'ERROR:' in s]
report={'exit_code':r.returncode,'changed_fixture_files':changed,'engine_errors':errors,'source_unchanged':source==snapshot(ROOT/REL),'tracked_status_unchanged':status==subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=ROOT),'fresh_cache':True,'etc2_astc_enabled':True,'private_adb_port':os.environ.get('ANDROID_ADB_SERVER_PORT'),'files_checked':len(before)}
report['passed']=r.returncode==0 and not changed and not errors and report['source_unchanged'] and report['tracked_status_unchanged']
(out/'cold-import-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));raise SystemExit(0 if report['passed'] else 1)
