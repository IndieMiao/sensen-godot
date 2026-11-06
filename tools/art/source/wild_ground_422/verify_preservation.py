"""Audit protected source bytes and independently measure ground-mask clearance."""
from pathlib import Path
import hashlib,json,subprocess
import numpy as np
from PIL import Image
from prepare_review import BASE,ROOT,PROJECT,SRC

def sha(data):return hashlib.sha256(data).hexdigest()
def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT)
def main():
    protected=['modules/ponds','modules/fishing','assets/ponds','assets/farm/art/water']
    changed=git('diff','--name-only','93befb18','--',*protected).decode().splitlines()
    assert all(p.startswith('assets/ponds/ground/') for p in changed),changed
    files=git('ls-tree','-r','--name-only',BASE,'--',*protected).decode().splitlines()
    matches=[]
    for f in files:
        if f=='modules/ponds/pond_scenery.gd' or f.endswith('.import'):continue
        expected=git('show',BASE+':'+f)
        actual=(PROJECT/f).read_bytes()
        assert actual==expected,f
        matches.append({'path':f,'sha256':sha(actual)})
    original=git('show',BASE+':modules/ponds/pond_ground.gdshader').decode()
    sample=(SRC/'pond_ground.sample.gdshader').read_text()
    fragment=original[original.index('    vec2 p ='):original.rindex('}')]
    assert fragment in sample
    for line in original.splitlines():
        if line.startswith('uniform '):assert line in sample
    templates=json.loads((SRC/'reference/p0_pond_templates.json').read_text())['templates']
    mask=np.asarray(Image.open(ROOT/'assets/ponds/ground/dry_ground_mask.png'))
    h,w=mask.shape[:2]
    x,z=np.meshgrid(-4+(np.arange(w)+.5)*20/w,-20+(np.arange(h)+.5)*24/h)
    cases=[]
    for channel,(shape,t) in enumerate(templates.items()):
        points=np.asarray(t['polygon']);d2=np.full(x.shape,np.inf);inside=np.zeros(x.shape,dtype=bool)
        # Segment distance and ray crossings, independent of raster/EDT bake.
        for a,b in zip(points,np.roll(points,-1,axis=0)):
            v=b-a;u=np.clip(((x-a[0])*v[0]+(z-a[1])*v[1])/np.dot(v,v),0,1)
            d2=np.minimum(d2,(x-a[0]-u*v[0])**2+(z-a[1]-u*v[1])**2)
            if abs(v[1])>1e-12:inside^=((a[1]>z)!=(b[1]>z)) & (x<(b[0]-a[0])*(z-a[1])/v[1]+a[0])
        protected=inside|(d2<=.75**2)
        values=mask[:,:,channel]
        violations=int(np.count_nonzero(values[protected]))
        assert violations==0,(shape,violations)
        cases.append({'shape':shape,'all_water_and_075m_shore_texels':int(protected.sum()),'nonzero_permission_texels':violations})
    report={'passed':True,'runtime_commit':BASE,'art_base':'93befb18','production_protected_paths_unchanged':True,
        'original_ground_fragment_verbatim':True,'original_texture_uniforms_retained':True,
        'preview_source_hashes':matches,'dry_mask_checks':cases,
        'limits':'0.75m analytic clearance check allows raster/filter margin below the nominal 0.8m bake. Same-frame rendered comparisons are in godot-validation.json.'}
    (ROOT/'docs/design/wild-ground-422/preservation-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PRESERVATION PASS',len(matches),'source files;',cases)
if __name__=='__main__':main()
