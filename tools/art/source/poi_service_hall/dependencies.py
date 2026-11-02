"""Pinned, unmodified draft dependencies for the SGODOT-321 blockout only."""
from pathlib import Path
import hashlib
import io
import json
import struct
import subprocess
import tarfile
import numpy as np

ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent
OUT=ROOT/'output/poi-service-hall-321'
DEPS=OUT/'dependencies'
HALL='assets/rooms/_shared/shell_hall'
SHELL_COMMIT='3aa234665681f8fe9e9acc63784c3ef65bf93ff4'
KIT_COMMIT='104446a2a995c8a0269d12d27308b3d547b29f6e'


def write_json(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')


def glb_measure(path):
    raw=path.read_bytes()
    assert raw[:4]==b'glTF'
    length=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+length]);blob=raw[28+length:]
    def accessor(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
        dtype={5121:'u1',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]
        cols={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        width=np.dtype(dtype).itemsize
        return np.ndarray((a['count'],cols),dtype=dtype,buffer=blob,
            offset=v.get('byteOffset',0)+a.get('byteOffset',0),
            strides=(v.get('byteStride',cols*width),width)).copy()
    points=[];triangles=0;surfaces=0
    for node in doc['nodes']:
        if 'mesh' not in node:continue
        assert np.allclose(node.get('translation',[0,0,0]),[0,0,0],atol=1e-6)
        assert np.allclose(node.get('scale',[1,1,1]),[1,1,1],atol=1e-6)
        assert np.allclose(node.get('rotation',[0,0,0,1]),[0,0,0,1],atol=1e-6)
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            vertices=accessor(primitive['attributes']['POSITION'])
            points.append(vertices);surfaces+=1
            triangles+=len(accessor(primitive['indices']))//3 if 'indices' in primitive else len(vertices)//3
    points=np.concatenate(points)
    assert np.isfinite(points).all()
    return {'bounds':[points.min(0).astype(float).tolist(),points.max(0).astype(float).tolist()],
            'dimensions_m':np.ptp(points,axis=0).astype(float).tolist(),
            'triangles':triangles,'surfaces':surfaces,'sha256':hashlib.sha256(raw).hexdigest(),
            'mesh_names':[mesh['name'] for mesh in doc['meshes']]}


def stage():
    DEPS.mkdir(parents=True,exist_ok=True)
    sources=[]
    for commit,paths,pr in [(SHELL_COMMIT,[HALL,'scenes/shell_hall'],594),
                            (KIT_COMMIT,[HALL,'tools/art/source/hallkit_324/hallkit_324.blend'],563)]:
        archive=subprocess.check_output(['git','archive',commit,*paths],cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            records=[]
            for member in tar.getmembers():
                if not member.isfile():continue
                data=tar.extractfile(member).read()
                records.append({'path':member.name,'sha256':hashlib.sha256(data).hexdigest()})
            tar.extractall(DEPS,filter='data')
        sources.append({'pr':pr,'commit':commit,'files':records})
    inventory={}
    for path in sorted((DEPS/HALL).glob('*.glb')):
        inventory[path.stem]=glb_measure(path)
    kit=json.loads((DEPS/HALL/'asset_stats.json').read_text())
    for item in kit['assets']:
        if item['name'] in inventory:inventory[item['name']]['seat_anchors']=item.get('anchors',{})
    plant=ROOT/'assets/rooms/_shared/plants/peace_lily.glb'
    inventory['peace_lily']=glb_measure(plant)
    write_json(SRC/'measured_dependencies.json',inventory)
    manifest={'task':'SGODOT-321','phase':'layout blockout, not detailed art',
              'author':'Huangzhong','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
              'dependencies':sources,'rule':'Original shell and hallkit files copied only into ignored output; never changed by this branch'}
    write_json(SRC/'dependency_manifest.json',manifest)
    print(json.dumps({k:inventory[k] for k in ['sofa_three_seat','armchair','round_side_table','peace_lily']},indent=2))


if __name__=='__main__':stage()
