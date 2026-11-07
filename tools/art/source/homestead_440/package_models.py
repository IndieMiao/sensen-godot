"""Verify the imported meshes actually packed in the read-back Android APK."""
import hashlib,re,zipfile
from pathlib import Path

def verify(apk,qa,root):
 records=[]
 with zipfile.ZipFile(apk) as bundle:
  for name in ['master_farmhouse_a','master_farmhouse_b']:
   rel='assets/farm/art/'+name+'.glb'
   assert (qa/rel).read_bytes()==(root/rel).read_bytes()
   source=(qa/(rel+'.import')).read_text()
   packed=bundle.read('assets/'+rel+'.import').decode().rstrip('\0')
   # Export intentionally removes editor-only deps/params from .import.
   for key in ['uid','path','type']:
    value=lambda s:re.search(r'^'+key+r'=(.*)$',s,re.M)[1]
    assert value(source)==value(packed),(name,key)
   imported=re.search(r'^path="res://([^"]+)"',source,re.M)[1]
   data=bundle.read('assets/'+imported)
   assert data==(qa/imported).read_bytes(),name
   records.append({'asset':name,'imported_path':imported,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'source_glb_sha256':hashlib.sha256((root/rel).read_bytes()).hexdigest(),'packed_uid_and_remap_match':True})
 return records
if __name__=='__main__':
 import json
 root=Path(__file__).resolve().parents[4];out=root/'output/homestead-440'
 p=out/'android/smoke.json';d=json.loads(p.read_text());d['packaged_imported_models_match']=verify(out/'android/installed.apk',out/'android-project',root)
 p.write_text(json.dumps(d,indent=2)+'\n');print('Packaged models verified:',len(d['packaged_imported_models_match']))
