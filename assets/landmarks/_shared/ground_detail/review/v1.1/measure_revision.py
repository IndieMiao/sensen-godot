"""Measure native viewport pixels, preserve masks, and annotate requested review images."""
from pathlib import Path
import json,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from scipy.ndimage import binary_erosion
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'tools/art/source/ground_detail_428').is_dir())
DOC=Path(__file__).resolve().parent;CAP=ROOT/'output/ground-detail-428-v11/captures'
C={'deep':(255,0,0),'ordinary':(0,255,0),'sand':(255,255,0),'wet':(0,255,255)}
coef=np.array([.2126,.7152,.0722])
def a(name):return np.asarray(Image.open(CAP/(name+'.png')).convert('RGB'))
def bright(rgb):return rgb@coef/255

def main():
 records=[]
 for name in ['default','sand_close']:
  rgb=a(name);before=a(name+'-before');classes=a(name+'-classes');light=bright(a(name+'-lighting'))
  masks={k:binary_erosion(np.max(abs(classes.astype(int)-c),axis=2)<3) for k,c in C.items()}
  reference=np.median(light[np.logical_or.reduce(list(masks.values()))]);masks={k:m&(abs(light-reference)<.008) for k,m in masks.items()}
  samples={k:{'pixels':int(m.sum()),'mean_Yprime':float(bright(rgb)[m].mean()),'before_mean_Yprime':float(bright(before)[m].mean()),'mean_rgb':rgb[m].mean(axis=0).tolist()} for k,m in masks.items() if m.any()}
  contrast=100*(1-samples['wet']['mean_Yprime']/samples['sand']['mean_Yprime']);assert contrast>=15
  rec={'view':name,'dry_wet_contrast_percent':contrast,'before_contrast_percent_same_samples':100*(1-samples['wet']['before_mean_Yprime']/samples['sand']['before_mean_Yprime']),'samples':samples}
  if 'deep' in samples:
   rec['grass_contrast_percent']=100*(1-samples['deep']['mean_Yprime']/samples['ordinary']['mean_Yprime']);assert rec['grass_contrast_percent']>=15
  maskimg=np.zeros_like(rgb);outline=rgb.copy()
  for k,m in masks.items():maskimg[m]=C[k];outline[m&~binary_erosion(m)]=C[k]
  Image.fromarray(maskimg).save(DOC/(name+'-sample-mask.png'));Image.fromarray(outline).save(DOC/(name+'-sampling.png'))
  records.append(rec)
 for n in ['default','default-before','wood_close','wood_close-before','sand_close']:shutil.copy2(CAP/(n+'.png'),DOC/(n+'.png'))
 # Original flat-colour control identifies complete grass/paving/dry-sand interiors.
 flat=a('vertex-original');diff=abs(a('default').astype(int)-a('default-before').astype(int));unchanged={}
 for key,x,y in [('grass',180,75),('paving',180,230),('dry_sand',180,540)]:
  m=binary_erosion(np.all(flat==flat[y,x],axis=-1));d=diff[m];assert m.sum()>100 and d.max()==0
  unchanged[key]={'pixels':int(m.sum()),'max_rgb_difference_255':int(d.max())}
 default=records[0];contrast=default['dry_wet_contrast_percent']
 font=lambda n:ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',n)
 # Exact requested 360x800: a labelled 46px footer overlays review only, raw preserved.
 im=Image.open(DOC/'default.png').convert('RGB');d=ImageDraw.Draw(im);d.rectangle((0,754,360,800),fill='#edf0e8')
 d.text((8,758),f'428 v1.1 | dry / wet sand: {contrast:.2f}%',font=font(16),fill='#26342b')
 d.text((8,780),'Native 360 x 800 | original warm light',font=font(14),fill='#26342b');im.save(DOC/'default-review.png')
 wood=Image.open(DOC/'wood_close.png').convert('RGB');sheet=Image.new('RGB',(1000,850),'#edf0e8');sheet.paste(wood,(0,0));d=ImageDraw.Draw(sheet)
 d.text((16,764),'Wood: 0.18 m wide / 1.8 m long / half-board stagger / 1 texture read',font=font(21),fill='#26342b')
 d.text((16,800),f'Dry / wet sand contrast: {contrast:.2f}% (measured in matching default view)',font=font(21),fill='#26342b');sheet.save(DOC/'wood-close-review.png')
 report={'passed':True,'revision':'1.1','metric':"Y'=(.2126R+.7152G+.0722B)/255, rendered output sRGB mean; contrast=(dry-wet)/dry",'sampling':'eroded class interiors; same warm-light control +/-0.008; all selected pixels, excluding tide band','views':records,'unchanged_region_controls':unchanged}
 (DOC/'brightness-validation.json').write_text(json.dumps(report,indent=2)+'\n')
 r=json.loads((CAP/'render-validation.json').read_text());assert r['passed'];shutil.copy2(CAP/'render-validation.json',DOC/'render-validation.json')
 print(json.dumps({'contrast':contrast,'sand_close':records[1]['dry_wet_contrast_percent'],'unchanged':unchanged},indent=2))
if __name__=='__main__':main()
