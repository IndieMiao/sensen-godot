"""Validate v9's material-only geometry and the declared collaborator changes."""
from pathlib import Path
import json,hashlib,struct,subprocess
ROOT=Path(__file__).resolve().parents[4];FOLDER=ROOT/'assets/landmarks/alcatraz_island'
BASE='b81605af5b9aaa2e9bdcd3af81a0b2f385ce7bc3';TREE='4d8cdab5af1fd89a972af2ecd9c990eb1371f5cf'
def original(path):return subprocess.check_output(['git','show',BASE+':'+str(path.relative_to(ROOT))],cwd=ROOT)
def glb(data):
    n=struct.unpack_from('<I',data,12)[0];return json.loads(data[20:20+n]),data[28+n:]
def accessor(j,b,index):
    a=j['accessors'][index];v=j['bufferViews'][a['bufferView']];start=v.get('byteOffset',0)+a.get('byteOffset',0)
    width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]*{5126:4,5125:4,5123:2,5121:1}[a['componentType']]
    stride=v.get('byteStride',width)
    return b''.join(b[start+i*stride:start+i*stride+width] for i in range(a['count']))
report={'baseline':BASE,'owned_glbs_unchanged':{},'tower_colour_only':{},'tree_import_gate':{},'tree_roots':[]}
for name in ['alc_ground_dock','alc_ground_terraces','alc_ground_summit','dock','alc_museum','ruins']:
    p=FOLDER/(name+'.glb');data=p.read_bytes();assert data==original(p),name
    report['owned_glbs_unchanged'][name]=hashlib.sha256(data).hexdigest()
for name in ['alc_lighthouse','alc_lighthouse_far','alc_watertower','alc_watertower_far']:
    p=FOLDER/(name+'.glb');a,ab=glb(original(p));b,bb=glb(p.read_bytes());assert a==b,name
    colours={q['attributes']['COLOR_0'] for m in a['meshes'] for q in m['primitives']}
    for i in range(len(a['accessors'])):
        if i not in colours:assert accessor(a,ab,i)==accessor(b,bb,i),(name,i)
        else:
            x=accessor(a,ab,i);y=accessor(b,bb,i);assert x!=y,name
            channel_bytes={5121:1,5123:2,5126:4}[a['accessors'][i]['componentType']]
            assert all(x[k:k+channel_bytes]==y[k:k+channel_bytes] for k in range(3*channel_bytes,len(x),4*channel_bytes)),name
    imported=FOLDER/(name+'.glb.import');assert imported.read_bytes()==original(imported),name
    report['tower_colour_only'][name]={'json_and_geometry_uv_normals_indices_equal':True,'alpha_equal':True,'rgb_changed':True,'import_and_uid_equal':True}
old=json.loads(original(FOLDER/'layout.json'));new=json.loads((FOLDER/'layout.json').read_text())
for key in ['navigation','spawn','exit','camera','anchors','boundaries','walk_bounds','route','walk_goals']:
    assert old[key]==new[key],key
report['layout_geometry_camera_navigation_unchanged']=True
prior={p['name']:p for p in old['placements'] if p['asset'].startswith('alc_tree_')}
counts={}
for p in new['placements']:
    if not p['asset'].startswith('alc_tree_'):continue
    q=prior[p['source_name']]
    for key in ['position','yaw','scale','zone','collision']:assert p[key]==q[key],(p['name'],key)
    counts[p['asset']]=counts.get(p['asset'],0)+1;report['tree_roots'].append(p['source_name'])
assert counts=={'alc_tree_a':8,'alc_tree_b':6,'alc_tree_c':4,'alc_tree_d':8},counts
report['tree_counts']=counts
for name in ['alc_tree_c','alc_tree_c_far','alc_tree_d','alc_tree_d_far']:
    p=FOLDER/(name+'.glb.import');data=p.read_bytes();assert b'nodes/root_script=null' in data,name
    assert data==subprocess.check_output(['git','show',TREE+':'+str(p.relative_to(ROOT))],cwd=ROOT),name
    report['tree_import_gate'][name]='matches Godot-generated 4d8cdab5'
for name in ['sea_backdrop.gdshader','far_card.gdshader']:
    assert (FOLDER/name).read_bytes()==original(FOLDER/name),name
report['sea_and_backdrop_shaders_unchanged']=True
materials=FOLDER/'ground'
for p in materials.iterdir():
    if not p.is_file():continue
    assert p.read_bytes()==subprocess.check_output(['git','show','25923b8e9a9e18bb8cb6e856dc89bf86e73fe771:'+str(p.relative_to(ROOT))],cwd=ROOT),p.name
for name in ['alc_dock_detail.tres','alc_ground_surfaces.png','alc_ground_surfaces.png.import']:
    p=materials/name
    assert p.read_bytes()==subprocess.check_output(['git','show','91c563b16b651c1013d0290e70d611884376ab0f:'+str(p.relative_to(ROOT))],cwd=ROOT),name
shader=(materials/'alc_ground_detail.gdshader').read_text()
previous=subprocess.check_output(['git','show','91c563b16b651c1013d0290e70d611884376ab0f:assets/landmarks/alcatraz_island/ground/alc_ground_detail.gdshader'],cwd=ROOT,text=True)
assert shader[shader.index('} else if (path)'):]==previous[previous.index('} else if (path)'):]
report['ground_material_head']='25923b8e9a9e18bb8cb6e856dc89bf86e73fe771'
report['paving_and_dock_finish_v1_preserved']=True

report['passed']=True
out=ROOT/'docs/design/alcatraz-blockout-424-2026-11-05/v9/preservation.json';out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('PRESERVATION pass: 6 GLBs exact; 4 towers RGB only; 26 tree roots/TRS; 4 fixed imports; navigation/camera/sea intact')
