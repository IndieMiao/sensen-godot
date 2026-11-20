"""Separate review source/evidence archive; never part of the served static tree."""
from pathlib import Path
import json,hashlib,shutil,zipfile
R=Path(__file__).resolve().parents[1];root=R/'review-final';assert not root.exists(),'do not overwrite a frozen review';root.mkdir();delivery=json.loads((R/'delivery-hashes.json').read_text());files={}
def copy(src,rel):
 dst=root/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst);files[rel]=hashlib.sha256(dst.read_bytes()).hexdigest()
for name in ['SCHEMA-r4.md','STATIC-LAYOUT-r4.md','REPRODUCE-r4.md','REVIEW-FIXES-r2.md','REVIEW-FIXES-r3.md','499-r4-data-review.md']:copy(R/name,name)
for p in sorted((R/'tools').iterdir()):
 if p.suffix in ['.py','.mjs']:copy(p,'author-tools/'+p.name)
for p in sorted((R/'generated/reports').glob('*.json')):copy(p,'static-reports/'+p.name)
for name in ['manifest.json','client-manifest.json','generation-report.json']:copy(R/'generated'/name,'static-pins/'+name)
for p in sorted((R/'evidence').iterdir()):
 if p.is_file() and p.name not in ['package-runtime.json','archive_review.py.log'] and p.suffix in ['.json','.log']:copy(p,'evidence/'+p.name)
copy(R/'audit/r3-exclusions-baseline.json','source-audit/r3-exclusions-baseline.json')
for snapshot in ['author-review-r1','author-review-r2','author-review-r3']:
 for p in sorted((R/snapshot/'source-snapshot/tools').glob('*.py')):
  if p.name in ['generator.py','audit_source_geometry.py']:copy(p,snapshot+'/source-snapshot/tools/'+p.name)
 for p in [R/snapshot/'manifest.json']:
  if p.exists():copy(p,snapshot+'/manifest.json')
manifest={'schema':1,'scope':'r4 author source/audit review only; not served or mounted in static','dataset_version':delivery['dataset_version'],'static_archive_sha256':delivery['archive_sha256'],'static_author_manifest_sha256':delivery['author_manifest_sha256'],'static_client_manifest_sha256':delivery['client_manifest_sha256'],'files':dict(sorted(files.items()))}
(root/'manifest.json').write_text(json.dumps(manifest,separators=(',',':'))+'\n');manifest_sha=hashlib.sha256((root/'manifest.json').read_bytes()).hexdigest();archive=R/'sf-dynamic-farm-20261118-r4-review.zip';assert not archive.exists()
with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for rel in sorted([*files,'manifest.json']):
  info=zipfile.ZipInfo('review/'+rel,(2026,11,18,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;z.writestr(info,(root/rel).read_bytes())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 for rel,sha in {**files,'manifest.json':manifest_sha}.items():assert hashlib.sha256(z.read('review/'+rel)).hexdigest()==sha
h=hashlib.sha256()
with archive.open('rb') as f:
 for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
delivery.update(review_root=str(root),review_archive=str(archive),review_archive_sha256=h.hexdigest(),review_archive_bytes=archive.stat().st_size,review_manifest_sha256=manifest_sha,review_files=len(files),review_archive_members_hash_verified=True)
(R/'delivery-hashes.json').write_text(json.dumps(delivery,indent=2)+'\n');print(json.dumps(delivery),flush=True)
