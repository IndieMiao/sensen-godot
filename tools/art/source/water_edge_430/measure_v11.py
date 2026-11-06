"""Measure actual Mobile-rendered alpha contours, not parameter values alone."""
from pathlib import Path
import json,numpy as np
from PIL import Image
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/water-edge-430-v11';P=OUT/'measure'
def alpha(name):
 c=np.asarray(Image.open(P/(name+'.png')).convert('RGB'),dtype=float)[:,:,0]/255
 return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
def edge_y(a):
 mask=a>.02
 return np.where(mask,np.arange(a.shape[0])[:,None],-1).max(0)
a=alpha('straight_00');b=alpha('straight_minimum');columns=np.arange(95,805);ea=edge_y(a)[columns];eb=edge_y(b)[columns]
width=.64+(ea+.5-300)/375-.509090909
move=(ea-eb)/375
contact=a[251,columns]
ring_a=alpha('pile_ring_00');ring_b=alpha('pile_ring_minimum')
# Sample radial contours; pixel centre mapping matches the orthographic viewport.
angles=np.linspace(0,2*np.pi,128,endpoint=False);rs=np.linspace(.11,.36,501)
def ring_edges(arr):
 edges=[]
 for theta in angles:
  x=np.rint(450+np.cos(theta)*rs*900-.5).astype(int);y=np.rint(300+np.sin(theta)*rs*900-.5).astype(int)
  valid=(x>=0)&(x<900)&(y>=0)&(y<600);inside=np.zeros_like(valid);inside[valid]=arr[y[valid],x[valid]]>.02
  edges.append(rs[np.flatnonzero(inside)[-1]])
 return np.array(edges)
ring_move=ring_edges(ring_a)-ring_edges(ring_b)
inner=alpha('inner_00');contact_inner=[]
# d=.51 follows coast water contact; no endpoints or raster outer boundary.
for t in np.linspace(.03,.97,95):
 theta=t*np.pi/2;x=-1+.49*np.sin(theta);z=1-.49*np.cos(theta)
 px=round(450+(x+.5)*500-.5);py=round(300+(z-.5)*500-.5);contact_inner.append(inner[py,px])
changes=[]
for kind in ['straight','inner','pile_ring']:
 samples=[alpha(kind+'_%02d'%i) for i in range(12)]
 changes.append({'kind':kind,'changed_pixels_each_half_second':[int((abs(x-y)>.02).sum()) for x,y in zip(samples,samples[1:])],'loop_max_alpha_delta':float(abs(samples[0]-samples[-1]).max())})
report={'passed':True,'method':'Mobile render, diagnostic white albedo over black; RGB decoded to linear alpha. Width contour alpha>0.02; source shader alpha unchanged.','default_straight_water_width_m':{'minimum':float(width.min()),'mean':float(width.mean()),'maximum':float(width.max())},'shore_contact_alpha':{'minimum':float(contact.min()),'maximum':float(contact.max())},'inner_contact_minimum_alpha':float(min(contact_inner)),'straight_push_peak_to_peak_m':{'minimum':float(move.min()),'mean':float(move.mean()),'maximum':float(move.max())},'pile_push_peak_to_peak_m':{'minimum':float(ring_move.min()),'mean':float(ring_move.mean()),'maximum':float(ring_move.max())},'two_hz_motion':changes,'two_hz_note':'10 of 11 adjacent pairs must move; 2.5s and 3.0s are symmetric around the 2.75s turn','width_phase_note':'Default t=0 is expanded. The outer edge then retreats by 0.10m while the shore contact stays opaque; the sheet and inner boundary do not move.'}
assert .29<=width.min() and width.max()<=.5
assert contact.min()>.68 and min(contact_inner)>.68
assert abs(move.mean()-.1)<.005 and abs(ring_move.mean()-.1)<.012
# The two samples at 2.5/3.0 seconds are symmetric about the 2.75s turning point.
assert all(sum(n>100 for n in c['changed_pixels_each_half_second'])>=10 for c in changes)
assert all(c['loop_max_alpha_delta']<1e-6 for c in changes)
(OUT/'edge-motion-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
