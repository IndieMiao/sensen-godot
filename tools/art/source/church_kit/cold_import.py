"""Two clean-cache imports with mobile formats enabled; never import the live tree.

Runs Godot under the shared render lock, verifies kit imports against committed
source, and reports the pre-existing dependency import update separately.
"""
from pathlib import Path
import hashlib,json,os,shutil,subprocess

ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'output/church-kit-427-v11'
P=OUT/'cold-project'
REL=Path('assets/rooms/_shared/church_kit')
DEP=Path('assets/rooms/poi_church')
ACTOR='5281cd25-6a49-4df8-9802-f3e534956e80'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def snapshot(path):
 return {str(p.relative_to(path)):digest(p) for p in sorted(path.rglob('*'))
         if p.is_file() and '.godot' not in p.relative_to(path).parts}
def changed(a,b):return sorted(k for k in set(a)|set(b) if a.get(k)!=b.get(k))

source_before=snapshot(ROOT/REL)
live_before=snapshot(ROOT/DEP)
if P.exists():shutil.rmtree(P)
shutil.copytree(ROOT/REL,P/REL)
(P/DEP).mkdir(parents=True)
for name in ['room_albedo_ao.png','room_albedo_ao.png.import']:
 shutil.copy2(ROOT/DEP/name,P/DEP/name)
(P/'project.godot').write_text('''config_version=5
[application]
config/name="ChurchKit427ColdImport"
config/features=PackedStringArray("4.7", "Mobile")
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
result={'author':'黄忠','virtual_user_id':ACTOR,'mobile_import_enabled':True,'passes':[]}
env=dict(os.environ,ANDROID_ADB_SERVER_PORT='5097')
for attempt in [1,2]:
 if (P/'.godot').exists():shutil.rmtree(P/'.godot')
 before=snapshot(P)
 log=OUT/f'cold-import-{attempt}.log'
 with log.open('w') as f:
  run=subprocess.run(['flock',str(Path.home()/'gs66-render.lock'),'godot','--headless','--path',str(P),'--editor','--import'],stdout=f,stderr=subprocess.STDOUT,env=env)
 after=snapshot(P)
 text=log.read_text()
 assert run.returncode==0 and 'ERROR:' not in text,(attempt,text[-4000:])
 kit_delta=changed(source_before,snapshot(P/REL))
 assert not kit_delta,kit_delta
 delta=changed(before,after)
 if attempt==1:
  assert delta in [[],[str(DEP/'room_albedo_ao.png.import')]],delta
 else:assert not delta,delta
 result['passes'].append({'cold_cache':True,'exit_code':run.returncode,'kit_source_diff':kit_delta,'all_fixture_file_changes':delta})
result['palette_imports']={}
for name in ['classic','meadow']:
 cfg=(P/REL/f'glass_palette_{name}.png.import').read_text()
 assert 'compress/mode=0' in cfg and '"vram_texture": false' in cfg and 'imported_formats' not in cfg
 result['palette_imports'][name]={'compression':'lossless','vram_texture':False,'gpu_format_list_required':False,'sha256':digest(P/REL/f'glass_palette_{name}.png.import')}
dep=(P/DEP/'room_albedo_ao.png.import').read_text()
assert 's3tc_bptc' in dep and 'etc2_astc' in dep
assert source_before==snapshot(ROOT/REL) and live_before==snapshot(ROOT/DEP)
result['shared_dependency']={'path':'res://'+str(DEP/'room_albedo_ao.png'),'source_bytes':(ROOT/DEP/'room_albedo_ao.png').stat().st_size,'fixture_formats':['s3tc_bptc','etc2_astc'],'live_directory_unchanged':True,'note':'Existing poi_church atlas import lacks etc2_astc in base branch. First cold pass writes it only in isolated dependency copy; not submitted because live poi_church is out of scope.'}
result['passed']=True
(OUT/'cold-import-validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False,indent=2))
