"""Prove the v1.1 delta only relocates the sign; account for every real instance."""
from pathlib import Path
from collections import Counter
import hashlib
import json
import struct
import subprocess
import sys
import numpy as np

ROOT=Path(__file__).resolve().parents[4]
KIT=ROOT/'assets/rooms/tea_house'
OUT=ROOT/'output/tea-216'
BASE='cf833168cbd0591855b9dcee12f04e8b22fbced2'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import accessor


def baseline(path):return subprocess.check_output(['git','show',BASE+':'+str(path.relative_to(ROOT))],cwd=ROOT)


def signature(raw):
    length=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+length]);blob=raw[28+length:]
    triangles=[]
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            points=np.rint(np.array(accessor(doc,blob,primitive['attributes']['POSITION']))*1e5).astype(np.int64)
            indices=np.array(accessor(doc,blob,primitive['indices'])).reshape(-1,3)
            triangles.extend(tuple(sorted(tuple(v) for v in triangle)) for triangle in points[indices])
    return hashlib.sha256(np.array(sorted(triangles),dtype='<i8').tobytes()).hexdigest()


def main():
    layout=json.loads((KIT/'layout.json').read_text());old=json.loads(baseline(KIT/'layout.json'))
    stats=json.loads((KIT/'asset_stats.json').read_text());assets={a['name']:a for a in stats['assets']}
    checks=[]
    def check(ok,label):
        checks.append({'check':label,'passed':bool(ok)});print('PASS' if ok else 'FAIL',label)
    for spec in layout['assets']:
        path=KIT/spec['file']
        check(signature(path.read_bytes())==signature(baseline(path)),spec['name']+': approved local geometry preserved to 10 micrometres')
        imported=Path(str(path)+'.import')
        check(imported.read_bytes()==baseline(imported),spec['name']+': original import configuration and UID retained')
    check([a for a in layout['assets'] if a['name']!='name_sign']==[a for a in old['assets'] if a['name']!='name_sign'],
          'All non-sign placements and collider definitions unchanged')
    check([a for a in layout['anchors'] if a['name']!='sign_name']==[a for a in old['anchors'] if a['name']!='sign_name'],
          'All seating, NPC, entrance and camera anchors unchanged')
    for key in ['instances','boundaries','bench','preflight','camera','local_lights','review_lighting']:
        check(layout[key]==old[key],key+': approved contract unchanged')
    direct=[a for a in layout['assets'] if not a['review_only']]
    groups=Counter(a['asset'] for a in layout['instances'])
    breakdown=[{'asset':name,'instances':count,'triangles_each':assets[name]['triangles'],
        'triangles':count*assets[name]['triangles'],'surfaces':count*assets[name]['surfaces']} for name,count in sorted(groups.items())]
    primary_triangles=sum(assets[a['name']]['triangles'] for a in direct)
    check(primary_triangles==45424 and len(direct)==21,'Direct assets account for 45424 triangles and 21 surfaces')
    check(sum(a['triangles'] for a in breakdown)==10524 and sum(a['surfaces'] for a in breakdown)==15,
          'Nine stools and three two-part lamps account for 10524 triangles and 15 surfaces')
    check(stats['scene_triangles']==55948 and stats['static_draw_surfaces']==36,'Total remains 55948 triangles / 36 surfaces')
    result={'baseline':BASE,'passed':all(c['passed'] for c in checks),'checks':checks,
        'direct_assets':{'triangles':primary_triangles,'surfaces':len(direct)},'instance_breakdown':breakdown}
    (OUT/'sign-v1.1-preservation.json').write_text(json.dumps(result,indent=2)+'\n')
    if not result['passed']:sys.exit(1)


if __name__=='__main__':main()
