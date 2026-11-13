"""Static generic v2 asset, budget, UID and non-target preservation checks."""
from pathlib import Path
import hashlib, json, struct, subprocess, re
ROOT=Path(__file__).resolve().parents[4];BASE='76a363edf';ASSETS=ROOT/'assets/rooms/market_plaza'
def old(rel):return subprocess.check_output(['git','show',BASE+':'+rel],cwd=ROOT)
def glb(path):
    raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+n]);p=[p for m in d['meshes'] for p in m['primitives']]
    assert len(d['nodes'])==1 and len(d['meshes'])==1 and len(p)==1
    assert not d.get('images') and 'COLOR_0' in p[0]['attributes']
    mat=d['materials'][p[0]['material']]['pbrMetallicRoughness']
    assert mat['metallicFactor']==0 and mat['roughnessFactor']>=.85
    a=d['accessors'][p[0]['attributes']['POSITION']]
    assert a['max'][1]<=6.501
    assert a['max'][0]-a['min'][0]<=4.001
    return {'triangles':sum(d['accessors'][p['indices']]['count']//3 for p in p),
            'surfaces':len(p),'min':a['min'],'max':a['max'],'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
def main():
    layout_path='assets/rooms/market_plaza/layout.json'
    before=json.loads(old(layout_path));after=json.loads((ROOT/layout_path).read_text())
    # Only reference strings may be rotated to avoid same-colour corner houses,
    # after the director confirms that file-table adjustment. All else is exact.
    mappings=[]
    for a,b in zip(before['assets'],after['assets']):
        if a.get('group')=='FarFacades' and a['variants']['generic']!=b['variants']['generic']:
            mappings.append({'placement':a['name'],'before':a['variants']['generic'],'after':b['variants']['generic']})
            a['variants']['generic']=b['variants']['generic']
    assert before==after,'Non-reference layout field changed'
    stats=json.loads((ASSETS/'shell_asset_stats.json').read_text())['assets']
    rows=[]
    for i in range(4):
        file=f'facade_generic_{i}.glb';p=ASSETS/file;g=glb(p)
        assert g['triangles']==stats[f'facade_generic_{i}']['triangles']
        uid=re.search(r'uid="uid://([a-y0-8]+)"',(ASSETS/(file+'.import')).read_text())
        assert uid and (ASSETS/(file+'.import')).read_bytes()==old('assets/rooms/market_plaza/'+file+'.import')
        placed=[a for a in after['assets'] if a.get('variants',{}).get('generic')==file]
        caps=[]
        for a in placed:
            sf=a['variants']['san_francisco'];n=stats[sf[:-4]]['triangles'];assert g['triangles']<=n
            caps.append({'placement':a['name'],'sf_file':sf,'sf_triangles':n})
        g.update(file=file,uid=uid.group(1),positions=caps);rows.append(g)
    allowed={f'assets/rooms/market_plaza/facade_generic_{i}.glb' for i in range(4)}|{'assets/rooms/market_plaza/shell_asset_stats.json',layout_path}
    preserved={}
    for rel in subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'--','assets/rooms/market_plaza','scenes/market_plaza'],cwd=ROOT,text=True).splitlines():
        if rel in allowed:continue
        raw=(ROOT/rel).read_bytes();assert raw==old(rel),rel;preserved[rel]=hashlib.sha256(raw).hexdigest()
    report={'art_base':BASE,'layout_field_check':'all fields identical except listed generic file references',
            'layout_reference_changes':mappings,'layout_sha256':hashlib.sha256((ROOT/layout_path).read_bytes()).hexdigest(),
            'generic':rows,'preserved_files':preserved,
            'placed_triangles':sum(g['triangles']*len(g['positions']) for g in rows)}
    out=ROOT/'docs/design/market-generic-v2-218-2026-11-13';out.mkdir(parents=True,exist_ok=True)
    (out/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS',report['placed_triangles'],'placed triangles;',len(preserved),'preserved files; layout verified')
if __name__=='__main__':main()
