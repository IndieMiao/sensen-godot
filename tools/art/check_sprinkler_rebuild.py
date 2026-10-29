"""Rebuild sprinkler and compare exact GLB bytes; writes isolated QA evidence."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]
file=ROOT/'assets/farm/art/sprinkler.glb'
before=hashlib.sha256(file.read_bytes()).hexdigest()
run=subprocess.run(['blender','--background','--factory-startup','--threads','2','--python',str(ROOT/'tools/art/build_sprinkler.py')],cwd=ROOT,capture_output=True,text=True,check=True)
(ROOT/'output/sprinkler-244/rebuild.log').write_text(run.stdout+run.stderr)
assert 'SPRINKLER_EXPORTED' in run.stdout
after=hashlib.sha256(file.read_bytes()).hexdigest()
assert before==after,(before,after)
(ROOT/'output/sprinkler-244/reproducibility.json').write_text(json.dumps({'before':before,'after':after,'byte_identical':True},indent=2)+'\n')
print('REBUILD_BYTE_IDENTICAL',after)
