"""Patch only COLOR_0 bytes in four accepted GLBs; no re-exported geometry."""
from pathlib import Path
import ast,json,hashlib,struct,subprocess,sys,colorsys
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent;KIT=ROOT/'assets/landmarks/alcatraz_island'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
BASE='fc19d492eabbbe96105726c5a627c30d98b4e445';HOST='bf0c31b1c871011008b455434d167224d14de59c'
NAMES=['alc_lighthouse','alc_lighthouse_far','alc_watertower','alc_watertower_far']
def oldfile(rel):return subprocess.check_output(['git','show',BASE+':'+rel],cwd=ROOT)
def linear(h):return [v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in [i/255 for i in bytes.fromhex(h)]]
build_path=ROOT/'tools/art/source/alcatraz_far_424/build.py';old_build=oldfile(str(build_path.relative_to(ROOT))).decode()
old_palette=next(ast.literal_eval(n.value) for n in ast.parse(old_build).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='PAL' for t in n.targets))
NEW={'white':'EFE7D4','white_light':'F6ECD9','white_shadow':'D7CAB1','stone':'CBB48F','window':'86B0B3','window_dark':'608F99','lantern':'F0D69C','roof':'A4A08F','rust':'AC7955','rust_light':'C1946D','rust_dark':'7F5B44','hoop':'6D5746'}
palette={**old_palette,**NEW};rows={}
for name in NAMES:
 path=KIT/(name+'.glb');raw=oldfile(str(path.relative_to(ROOT)));n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);binary=bytearray(raw[28+n:]);changed=0;roles={}
 for mesh in doc['meshes']:
  for p in mesh['primitives']:
   a=doc['accessors'][p['attributes']['COLOR_0']];v=doc['bufferViews'][a['bufferView']];count={'VEC3':3,'VEC4':4}[a['type']];kind={5126:'f',5123:'H',5121:'B'}[a['componentType']];div={5126:1,5123:65535,5121:255}[a['componentType']];stride=v.get('byteStride',struct.calcsize('<'+kind*count));start=v.get('byteOffset',0)+a.get('byteOffset',0)
   for i in range(a['count']):
    off=start+i*stride;value=struct.unpack_from('<'+kind*count,binary,off);colour=[x/div for x in value[:3]]
    role=min(old_palette,key=lambda k:sum((colour[j]-linear(old_palette[k])[j])**2 for j in range(3)))
    assert max(abs(colour[j]-linear(old_palette[role])[j]) for j in range(3))<2/div if div!=1 else max(abs(colour[j]-linear(old_palette[role])[j]) for j in range(3))<1e-6
    roles[role]=roles.get(role,0)+1
    if role not in NEW:continue
    dest=linear(NEW[role]);dest=[round(x*div) for x in dest] if div!=1 else dest
    struct.pack_into('<'+kind*3,binary,off,*dest);changed+=1
 path.write_bytes(raw[:28+n]+binary)
 rows[name]={'before_sha256':hashlib.sha256(raw).hexdigest(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'vertices_recoloured':changed,'roles':roles}
# Keep the full original generator reproducible; only its named colour table changes.
a=old_build.index('PAL=');b=old_build.index('\nPARTS=',a)
build_path.write_text(old_build[:a]+'PAL='+repr(palette)+old_build[b:])
manifest=json.loads((KIT/'alc_far_manifest.json').read_text());manifest['revision']='v1.2_tower_palette';manifest['palette_srgb']=palette
for name,row in rows.items():manifest['assets'][name]['sha256']=row['sha256']
manifest['tower_palette_reference']={'host':HOST,'palette':'tools/art/source/alcatraz_island/palette.json','change':'Tower COLOR_0 only; shared roof/glass/stone roles, warm-white lighthouse and desaturated rust tank'}
(KIT/'alc_far_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
colours={}
for k,h in NEW.items():
 def measure(s):
  c=[i/255 for i in bytes.fromhex(s)];return {'hex':'#'+s,'srgb_weighted_value':sum(c[i]*[.2126,.7152,.0722][i] for i in range(3)),'hsv_saturation':colorsys.rgb_to_hsv(*c)[1]}
 colours[k]={'before':measure(old_palette[k]),'after':measure(h)}
report={'task':'SGODOT-424','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','base':BASE,'host_ref':HOST,'old_palette':old_palette,'new_palette':palette,'changes':colours,'assets':rows,'reference_palette':'reference/island-palette-bf0c31b1.json'}
(SRC/'colour-map.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('RECOLOURED',json.dumps({n:r['vertices_recoloured'] for n,r in rows.items()}))
