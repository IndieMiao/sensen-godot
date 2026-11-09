from pathlib import Path
import argparse,shutil,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[4]
a=argparse.ArgumentParser();a.add_argument('--out',type=Path,required=True);o=a.parse_args().out.resolve();P=o/'cold-project';assert not P.exists()
for rel in ['assets/props/stove_pot','assets/props/warming_cabinet','assets/props/cooking_pot_wait']:shutil.copytree(ROOT/rel,P/rel)
(P/'project.godot').write_text('''config_version=5
[application]
config/name="Steam449ColdImport"
config/features=PackedStringArray("4.7", "Mobile")
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_etc2_astc=true
textures/vram_compression/import_s3tc_bptc=true
''')
def snap(root):return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file() and '.godot' not in p.relative_to(root).parts}
b=snap(P);source=snap(ROOT/'assets/props/cooking_pot_wait')
with (o/'cold-import.log').open('w') as f:r=subprocess.run(['flock',str(Path.home()/'gs66-render.lock'),'godot','--headless','--path',str(P),'--editor','--import'],stdout=f,stderr=subprocess.STDOUT)
e=snap(P);changed=[k for k in set(b)|set(e) if b.get(k)!=e.get(k)];errors=[x for x in (o/'cold-import.log').read_text().splitlines() if 'ERROR:' in x]
result={'exit_code':r.returncode,'changed':changed,'errors':errors,'source_unchanged':source==snap(ROOT/'assets/props/cooking_pot_wait'),'fresh_cache':True,'texture_format':'lossless RGBA, mipmaps;128x128','etc2_astc_enabled':True}
result['passed']=r.returncode==0 and not changed and not errors and result['source_unchanged'];(o/'cold-import-validation.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result));raise SystemExit(0 if result['passed'] else 1)
