"""Import delivered settings in a completely new cache and compare every asset byte."""
from pathlib import Path
import hashlib,json,shutil,subprocess
import prepare

def hashes(path):
 return {str(p.relative_to(path)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(path.rglob('*')) if p.is_file()}
def main():
 root=prepare.ROOT;out=prepare.OUT;cold=out/'cold-project'
 assert not cold.exists(), 'Use a fresh cold-project path; preserve earlier evidence.'
 shutil.copytree(prepare.QA,cold,ignore=shutil.ignore_patterns('.godot'))
 assets=cold/prepare.REL
 before=hashes(assets)
 cmd=['flock','/home/deck/gs66-render.lock','/home/deck/.local/bin/godot','--headless','--path',str(cold)]
 with (out/'cold-import.log').open('w') as log:
  subprocess.run(cmd+['--editor','--import'],check=True,stdout=log,stderr=subprocess.STDOUT)
 after=hashes(assets);assert before==after,'Cold import dirtied delivered resources'
 assert hashes(root/prepare.REL)==after,'Committed source / isolated import mismatch'
 with (out/'resource-check.log').open('w') as log:
  subprocess.run(cmd+['--script','res://verify_resources.gd'],check=True,stdout=log,stderr=subprocess.STDOUT)
 report={'passed':True,'godot':'4.7.2','fresh_cache':True,'resource_file_count':len(before),'before_sha256':before,'after_sha256':after,'source_matches_cold_import':True,'changed_asset_files':[],
 'scene_imports':0,'root_script_note':'No scene imports; nodes/root_script=null is not a texture-import option. No GLBs/models are delivered.'}
 doc=root/'docs/design/ground-detail-428';(doc/'cold-import-validation.json').write_text(json.dumps(report,indent=2)+'\n')
 shutil.copy2(out/'resource-validation.json',doc/'resource-validation.json')
 print('GROUND_KIT_COLD_IMPORT_PASS',len(before),'unchanged files',flush=True)
if __name__=='__main__':main()
