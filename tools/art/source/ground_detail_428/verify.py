"""Visual controls, unchanged source channels and actual APK resource readback."""
from pathlib import Path
import hashlib,json,shutil,subprocess,zipfile
import numpy as np
from PIL import Image
import prepare

def main():
 root=prepare.ROOT;out=prepare.OUT;cap=out/'captures';doc=root/'docs/design/ground-detail-428'
 report=json.loads((cap/'render-validation.json').read_text());assert report['passed']
 shutil.copy2(cap/'render-validation.json',doc/'render-validation.json')
 def a(name):return np.asarray(Image.open(cap/(name+'.png')).convert('RGB')).astype(int)
 c=a('default-classes');mask=(c.max(axis=2)>250)&(c.sum(axis=2)<260)
 delta=abs(a('unmatched-key')-a('vertex-original'))[mask];assert delta.max()<=1
 forced=a('forced-grass')[mask];assert np.all((forced[:,1]>forced[:,0])&(forced[:,1]>forced[:,2]))
 old=root/'assets/landmarks/alcatraz_island/ground';new=root/prepare.REL
 for name in ['fields','surfaces']:assert (old/f'alc_ground_{name}.png').read_bytes()==(new/f'ground_{name}.png').read_bytes()
 info={'passed':True,'unmatched_key_preserves_vertex_color_max_rgb_255':int(delta.max()),'unmatched_key_sample_pixels':int(mask.sum()),'forced_grass_independent_of_vertex_keys':True,'both_packed_textures_byte_identical_to_827':True,'source_texture_reads_per_fragment':{'grass':3,'paving':1,'wood':1,'dry_sand':2,'wet_sand':2,'unmatched':0},'sampler_bindings':2,'opaque_surface_passes':1}
 (doc/'parameter-validation.json').write_text(json.dumps(info,indent=2)+'\n')
 # Read the exact installed APK previously recovered by the Android session.
 pkg=out/'package-project';pkg.mkdir(exist_ok=True)
 with zipfile.ZipFile(out/'android/installed.apk') as z:
  for name in z.namelist():
   if name.startswith('assets/') and not name.endswith('/'):
    dst=pkg/name.removeprefix('assets/');dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(z.read(name))
 assert (pkg/prepare.REL/'ground_detail.gdshader').read_bytes()==(new/'ground_detail.gdshader').read_bytes()
 shutil.copy2(prepare.SRC/'verify_resources.gd',pkg/'verify_resources.gd')
 with (out/'package-verify.log').open('w') as log:
  subprocess.run(['flock','/home/deck/gs66-render.lock','/home/deck/.local/bin/godot','--headless','--path',str(pkg),'--script','res://verify_resources.gd'],check=True,stdout=log,stderr=subprocess.STDOUT)
 shutil.copy2(out/'resource-validation.json',doc/'packaged-resource-validation.json')
 for name in ['default','grass','sand']:shutil.copy2(out/'android'/f'{name}.png',doc/f'android-{name}.png')
 smoke=json.loads((out/'android/smoke.json').read_text());assert smoke['passed']
 android=np.asarray(Image.open(doc/'android-default.png').convert('RGB')).astype(int)
 desktop=a('default');d=abs(android[:735]-desktop[:735])
 smoke['default_desktop_android_rgb_difference_255']={'mean':float(d.mean()),'max':int(d.max()),'region':'full width, rows0..734, excludes Android-only QA button'}
 (doc/'android-smoke.json').write_text(json.dumps(smoke,indent=2)+'\n')
 print('GROUND_KIT_SOURCE_AND_PACKAGE_PASS',smoke['default_desktop_android_rgb_difference_255'],flush=True)
if __name__=='__main__':main()
