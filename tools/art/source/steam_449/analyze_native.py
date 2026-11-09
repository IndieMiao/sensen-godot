from pathlib import Path
import json,argparse,hashlib
import numpy as np
from PIL import Image
ap=argparse.ArgumentParser();ap.add_argument('captures',type=Path);a=ap.parse_args();P=a.captures;r=json.loads((P/'native-measurements.json').read_text());checks=[];metrics=[]
def check(ok,label,evidence=None):checks.append({'check':label,'passed':bool(ok),'evidence':evidence})
def srgb(c):return np.where(c<=.0031308,c*12.92,1.055*np.maximum(c,0)**(1/2.4)-.055)
for f in r['frames']:
 w,h=map(int,f['layer_size']);raw=(P/'linear'/f"{f['frame']:03d}.bin").read_bytes()
 assert f['layer_is_half_float'] and len(raw)==w*h*8,(f['layer_format'],len(raw),w,h)
 im=np.frombuffer(raw,dtype='<f2').reshape((h,w,4)).astype('float32');al=im[:,:,3];y,x=np.indices(al.shape)
 pos=np.array(f['layer_position']);gx=x+pos[0];gy=y+pos[1]
 # This is a dedicatedSteam-only render layer sharing the native world/camera.
 # Include every pixel, so opaque pot MSAA edges cannot contaminate the result.
 valid=np.ones_like(al,dtype=bool);visible=al>=.01
 if visible.any():
  b=[int(gx[visible].min()),int(gy[visible].min()),int(gx[visible].max()+1),int(gy[visible].max()+1)]
 else:b=[]
 ring=valid&(gy>=170)&(gy<195)
 straight=srgb(np.clip(im[:,:,:3]/np.maximum(al[:,:,None],1e-6),0,1));candidates=straight[valid&(al>.05)]
 core=np.array([255,248,240])/255.;edge=np.array([217,222,227])/255.
 core_d=np.max(np.abs(candidates-core),axis=1) if len(candidates) else np.array([1]);edge_d=np.max(np.abs(candidates-edge),axis=1) if len(candidates) else np.array([1])
 metrics.append({'frame':f['frame'],'bounds_xyxy':b,'peak_alpha':float(al[valid].max()) if valid.any() else 0,'ring_peak_alpha':float(al[ring].max()) if ring.any() else 0,'warm_core_pixels_within_3rgb':int((core_d<3/255).sum()),'cool_edge_pixels_within_3rgb':int((edge_d<3/255).sum()),'nearest_core_srgb':(candidates[core_d.argmin()]*255).round(2).tolist() if len(candidates) else [],'nearest_edge_srgb':(candidates[edge_d.argmin()]*255).round(2).tolist() if len(candidates) else []})
check(r['frame_count']>=60 and 3000<=r['elapsed_wall_ms']<=3200 and not r['error'],'At least3 seconds native capture at20+fps',{'frames':r['frame_count'],'wall_ms':r['elapsed_wall_ms']})
check(all(f['layer_hdr'] for f in r['frames']),'Real host HDR target enabled')
check(all(f['steam_visible'] and f['steam_emitting'] and f['particle_count']==3 for f in r['frames']),'Three emitting particles in real wait overlay')
check(all(np.allclose(f['mouth'],[180,235],atol=.1) for f in r['frames']),'Pot mouth fixed180,235')
check(all(np.allclose(f['layer_position'],[80,110],atol=.1) and f['layer_size']==[200,220] for f in r['frames']),'Native expanded frame80,110/200x220')
check(all(m['bounds_xyxy'] and m['bounds_xyxy'][0]>=130 and m['bounds_xyxy'][1]>=120 and m['bounds_xyxy'][2]<=230 and m['bounds_xyxy'][3]<=195 for m in metrics),'Steam stays within allowed strip and fades beforey120')
check(max(m['ring_peak_alpha'] for m in metrics)<=.5,'Composite alpha<=0.5 over ring',max(m['ring_peak_alpha'] for m in metrics))
check(max(m['peak_alpha'] for m in metrics)<=.605,'Composite upper alpha about0.6',max(m['peak_alpha'] for m in metrics))
check(sum(m['warm_core_pixels_within_3rgb'] for m in metrics)>90,'Warm core matchesFFF8F0 in native target')
check(sum(m['cool_edge_pixels_within_3rgb'] for m in metrics)>90,'Cool edge matchesD9DEE3 in native target')
report={'host_head':r['host_head'],'renderer':r['renderer'],'gpu':r['gpu'],'scope':'native Common wait overlay, no host/camera changes','checks':checks,'passed':all(x['passed'] for x in checks),'frames':metrics}
if r['frames'][0]['particle_count']==1:
 widths=[]
 for f in r['frames']:
  w,h=map(int,f['layer_size']);im=np.fromfile(P/'linear'/f"{f['frame']:03d}.bin",dtype='<f2').reshape(h,w,4);coords=np.argwhere(im[:,:,3]>=.01)
  widths.append({'frame':f['frame'],'wall_ms':f['wall_ms'],'width':int(np.ptp(coords[:,1])+1) if len(coords) else 0})
 births=[i for i in range(1,len(widths)) if widths[i-1]['width']==0 and widths[i]['width']>0]
 initial=[widths[j]['width'] for i in births for j in range(i,min(len(widths),i+6))]
 single={'single_particle_control':True,'host_head':r['host_head'],'frames':widths,'initial_width_px':initial,'grown_max_px':max(x['width'] for x in widths),'passed':bool(initial) and min(initial)>=22 and max(initial)<=26 and 34<=max(x['width'] for x in widths)<=40}
 (P/'single-validation.json').write_text(json.dumps(single,indent=2)+'\n');print('Native single-puff dimensions:',single['initial_width_px'],'max',single['grown_max_px']);raise SystemExit(0 if single['passed'] else 1)
(P/'native-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:print(c)
raise SystemExit(0 if report['passed'] else 1)
