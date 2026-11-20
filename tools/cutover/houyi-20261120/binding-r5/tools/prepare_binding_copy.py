from pathlib import Path
import shutil,json,hashlib
R=Path(__file__).resolve().parents[1];old=R.parent
assert not (R/'generated').exists()
shutil.copyfile(old/'delivery-hashes.json',R/'binding-input.json')
shutil.copytree(old/'generated',R/'generated')
for p in (old/'audit').iterdir():
 if p.is_file():shutil.copyfile(p,R/'audit'/p.name)
for p in (old/'evidence').iterdir():
 if p.is_file() and p.name in ['farm-runtime.json','source-audit-runtime.json','mvt-runtime.json','reconcile-runtime.json','reconcile-r3-runtime.json','sample-validation-strengthened.json','hole-parent-tests-r3.json','single-source-fragments-test.json','source-manifest-verification.json']:shutil.copyfile(p,R/'evidence'/p.name)
for name in ['author-review-r1','author-review-r2','author-review-r3']:
 shutil.copytree(old/name,R/name)
assert hashlib.sha256((R/'generated/manifest.json').read_bytes()).hexdigest()==json.loads((R/'binding-input.json').read_text())['author_manifest_sha256']
print('FROZEN_INPUT_COPIED')
