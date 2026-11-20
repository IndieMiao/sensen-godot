"""Reproducible static archive plus full streamed member-hash verification."""
from pathlib import Path
import json,hashlib,gzip,tarfile,time
R=Path(__file__).resolve().parents[1];O=R/'generated';receipt=json.loads((R/'evidence/full-author-validation.json').read_text());m=json.loads((O/'manifest.json').read_text())
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
assert digest(O/'manifest.json')==receipt['author_manifest_sha256']
expected={**m['files'],'manifest.json':receipt['author_manifest_sha256'],'client-manifest.json':receipt['client_manifest_sha256']}
archive=R/(m['dataset_version']+'-static.tar.gz');assert not archive.exists(),'do not overwrite frozen archive';start=time.monotonic()
with archive.open('xb') as raw:
 with gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0,compresslevel=6) as gz:
  with tarfile.open(fileobj=gz,mode='w|',format=tarfile.PAX_FORMAT) as tar:
   for rel in sorted(expected):
    p=O/rel;info=tarfile.TarInfo('static/'+rel);info.size=p.stat().st_size;info.mode=0o644;info.mtime=0;info.uid=info.gid=0
    with p.open('rb') as stream:tar.addfile(info,stream)
seen=set()
with tarfile.open(archive,'r|gz') as tar:
 for info in tar:
  assert info.isfile() and info.name.startswith('static/');rel=info.name[7:];assert rel in expected and rel not in seen
  stream=tar.extractfile(info);h=hashlib.sha256()
  for b in iter(lambda:stream.read(1024*1024),b''):h.update(b)
  assert h.hexdigest()==expected[rel],rel;seen.add(rel)
assert seen==set(expected)
result={'dataset_version':m['dataset_version'],'static_root':str(O),'archive':str(archive),'archive_bytes':archive.stat().st_size,'archive_sha256':digest(archive),'author_manifest_sha256':receipt['author_manifest_sha256'],'client_manifest_sha256':receipt['client_manifest_sha256'],'parcel_count':m['parcel_count'],'file_count':len(expected),'all_archive_member_hashes_verified':True,'seconds':time.monotonic()-start,'reviewed':False,'review_boundary':'author artifact only; reviewer approval must cite these pins; no deployment or phone/UI claims'}
(R/'delivery-hashes.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result),flush=True)
