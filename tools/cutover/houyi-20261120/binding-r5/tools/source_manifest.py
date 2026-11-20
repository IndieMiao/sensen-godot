"""Validate a frozen download inventory before accepting any source rows."""
from pathlib import Path
import json,hashlib,re

def verify_source_pages(source,expected_manifest_sha256=None):
 source=Path(source);mp=source/'parcel-download-manifest.json';manifest_blob=mp.read_bytes()
 if expected_manifest_sha256 is not None and hashlib.sha256(manifest_blob).hexdigest()!=expected_manifest_sha256:raise ValueError('download manifest pin mismatch')
 manifest=json.loads(manifest_blob)
 if not isinstance(manifest,list) or not manifest:raise ValueError('empty source download manifest')
 names=[]
 for entry in manifest:
  name=entry.get('file')
  if not isinstance(name,str) or not re.fullmatch(r'parcels-[0-9]+\.json',name):raise ValueError('unsafe page name')
  if name in names:raise ValueError('duplicate source page')
  names.append(name)
 actual={p.name for p in source.glob('parcels-*.json')}
 if actual!=set(names):raise ValueError('source page inventory mismatch')
 verified=[]
 for entry in manifest:
  path=source/entry['file']
  if not path.is_file() or path.is_symlink():raise ValueError('unsafe/missing source page')
  blob=path.read_bytes();rows=json.loads(blob)
  if not isinstance(rows,list) or type(entry.get('rows'))!=int or entry['rows']!=len(rows):raise ValueError('source page row count mismatch')
  if type(entry.get('bytes'))!=int or entry['bytes']!=len(blob):raise ValueError('source page bytes mismatch')
  sha=hashlib.sha256(blob).hexdigest()
  if not isinstance(entry.get('sha256'),str) or sha!=entry['sha256']:raise ValueError('source page hash mismatch')
  verified.append({'file':entry['file'],'sha256':sha,'bytes':len(blob),'count':len(rows)})
 return {'download_manifest_sha256':hashlib.sha256(mp.read_bytes()).hexdigest(),'pages':verified,'page_set_verified':True,'bytes_rows_hashes_verified':True,'source_records':sum(x['count'] for x in verified)}
