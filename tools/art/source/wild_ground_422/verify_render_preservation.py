"""Independently compare every protected pixel in same-frame overhead pairs."""
from pathlib import Path
import json
import numpy as np
from PIL import Image
from prepare_review import ROOT,SRC,OUT

def main():
    report=json.loads((OUT/'captures/godot-validation.json').read_text())
    assert report['passed']
    templates=json.loads((SRC/'reference/p0_pond_templates.json').read_text())['templates']
    checks=[]
    for shape,t in templates.items():
        records=[next(r for r in report['captures'] if r['name']==shape+suffix) for suffix in ['_overhead_before','_overhead']]
        assert records[0]['same_frame']==records[1]['same_frame']
        assert records[0]['camera']==records[1]['camera']
        for r in records:
            assert abs(r['pitch_degrees']+90)<.01 and abs(r['width_m']-20.8)<.001
            assert r['camera'].endswith('O: (6.0, 30.0, -8.0)]')
        a=np.array(Image.open(OUT/'captures'/f'{shape}_overhead_before.png').convert('RGB')).astype(int)
        b=np.array(Image.open(OUT/'captures'/f'{shape}_overhead.png').convert('RGB')).astype(int)
        h,w=a.shape[:2];metres=records[0]['width_m']/w
        # Exact top-down capture camera: centre (6,-8), KEEP_WIDTH, up=-Z.
        x,z=np.meshgrid(6+(np.arange(w)+.5-w/2)*metres,-8+(np.arange(h)+.5-h/2)*metres)
        points=np.array(t['polygon']);d2=np.full(x.shape,np.inf);inside=np.zeros(x.shape,dtype=bool)
        for start,end in zip(points,np.roll(points,-1,axis=0)):
            v=end-start;u=np.clip(((x-start[0])*v[0]+(z-start[1])*v[1])/np.dot(v,v),0,1)
            d2=np.minimum(d2,(x-start[0]-u*v[0])**2+(z-start[1]-u*v[1])**2)
            if abs(v[1])>1e-12:inside^=((start[1]>z)!=(end[1]>z)) & (x<v[0]*(z-start[1])/v[1]+start[0])
        protected=inside|(d2<=.65**2)
        delta=np.abs(a-b).max(axis=2)
        result={'shape':shape,'same_frame':records[0]['same_frame'],
                'water_and_065m_shore_pixels':int(protected.sum()),
                'max_rgb_255':int(delta[protected].max()),
                'changed_protected_pixels':int(np.count_nonzero(delta[protected])),
                'changed_dry_ground_pixels':int(np.count_nonzero(delta[~protected]))}
        checks.append(result)
        assert result['changed_protected_pixels']==0,result
        assert result['changed_dry_ground_pixels']>10000,result
        print(result,flush=True)
    report['water_pixels']=checks
    report['water_pixels_method']='Independent orthographic pixel-centre projection, analytic polygon plus 0.65m shore buffer; exact RGB byte comparison.'
    (OUT/'captures/godot-validation.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
