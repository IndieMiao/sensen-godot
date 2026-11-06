"""Measure original rendered pixels, excluding occlusion, edges and shadows.

Pure colour masks are separate QA renders of identical geometry/coordinates.
The neutral-albedo render selects matching sun illumination; beauty pixels are
never recoloured. The same masks are then evaluated in before and after frames.
"""
from pathlib import Path
import json, shutil, hashlib, subprocess, io
import numpy as np
from scipy.ndimage import binary_erosion,binary_dilation
from PIL import Image,ImageDraw,ImageFont
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
OUT=ROOT/'output/alcatraz-ground-424-v11';CAP=OUT/'captures'
DOC=ROOT/'docs/design/alcatraz-ground-424/v1.1'
W=np.array([.2126,.7152,.0722])
FONT='/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc'
def read(path):return np.array(Image.open(path).convert('RGB'))/255
def font(n):return ImageFont.truetype(FONT,n)
def main():
 DOC.mkdir(parents=True,exist_ok=True)
 report={'revision':'1.1','before_commit':'91c563b16b651c1013d0290e70d611884376ab0f',
  'metric':'mean Yprime = (0.2126 R + 0.7152 G + 0.0722 B)/255 on rendered sRGB pixels; contrast=(ordinary-deep)/ordinary',
  'selection':'Pure deep/base shader regions, eroded 1px. Neutral grass control restricts samples to within 0.008 Yprime of the ordinary region 80th percentile; excludes shadows/occluding objects. Before uses identical pixel masks.',
  'views':{},'preserved':{}}
 for name,title in [('opening','开场'),('mid_hill','半山'),('summit','山顶'),('grass_detail','草坡近景')]:
  before=read(CAP/f'{name}-before.png');after=read(CAP/f'{name}-after.png');classes=read(CAP/f'{name}-classes.png');illum=read(CAP/f'{name}-lighting-control.png')@W
  masks={}
  for label,i in [('deep',0),('ordinary',1),('sun',2)]:
   masks[label]=binary_erosion((classes[:,:,i]>.99)&(classes[:,:,(i+1)%3]<.01)&(classes[:,:,(i+2)%3]<.01),iterations=1)
  assert masks['ordinary'].sum()>=30,(name,'ordinary visible')
  level=float(np.quantile(illum[masks['ordinary']],.8))
  for label in masks:masks[label]&=abs(illum-level)<.008
  assert masks['deep'].sum()>=30 and masks['ordinary'].sum()>=30,(name,'sunlit sample count')
  result={'size':[before.shape[1],before.shape[0]],'illumination_reference_Yprime':level,'regions':{}}
  for label,mask in masks.items():
   pixels=int(mask.sum())
   if pixels==0:continue
   ys,xs=np.where(mask)
   region={'pixels':pixels,'bbox_xyxy':[int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)],
    'before_mean_Yprime':float((before@W)[mask].mean()),'after_mean_Yprime':float((after@W)[mask].mean()),
    'control_mean_Yprime':float(illum[mask].mean()),'after_mean_RGB255':(after[mask].mean(0)*255).round(3).tolist()}
   result['regions'][label]=region
  for suffix in ['before','after']:
   a=result['regions']['ordinary'][suffix+'_mean_Yprime'];b=result['regions']['deep'][suffix+'_mean_Yprime']
   result[suffix+'_contrast_percent']=(a-b)/a*100
  assert result['after_contrast_percent']>=15,(name,result)
  # Difference from a matching black target shader also detects grass visible
  # only in MSAA subsamples behind thin railings. One extra pixel covers AA edges.
  occlusion=read(CAP/f'{name}-occlusion-control.png')
  primary=np.abs(classes-occlusion).max(2)>.5/255
  grass_area=binary_dilation(primary,iterations=1)
  delta=np.abs(after-before).max(2)*255
  result['outside_grass_max_RGB255']=float(delta[~grass_area].max())
  result['outside_grass_changed_pixels']=int((delta[~grass_area]>.5).sum())
  assert result['outside_grass_max_RGB255']<.01,(name,'non-grass pixels changed')
  if name=='opening':
   result['bridge_city_max_RGB255']=float(delta[45:160,:150].max())
   assert result['bridge_city_max_RGB255']==0
  report['views'][name]=result
  # Keep actual sample masks so every measured pixel is independently inspectable.
  mask_rgb=np.zeros_like(after,dtype=np.uint8)
  for label,color in [('deep',[255,80,100]),('ordinary',[255,255,255]),('sun',[255,225,70])]:mask_rgb[masks[label]]=color
  Image.fromarray(mask_rgb).save(DOC/f'{name}-sample-mask.png')
  if name!='grass_detail':
   canvas=Image.new('RGB',(756,966),'#f3f1e8');draw=ImageDraw.Draw(canvas)
   for x,suffix,text in [(12,'before','v1 已审版'),(384,'after','v1.1 草坡增强')]:
    im=Image.open(CAP/f'{name}-{suffix}.png').convert('RGB');assert im.size==(360,800)
    canvas.paste(im,(x,56));draw.text((x,16),title+' / '+text,font=font(20),fill='#354138')
    shutil.copy2(CAP/f'{name}-{suffix}.png',DOC/f'{name}-{suffix}-360x800.png')
   draw.text((12,866),'原光照 / 同机位 / 排除阴影；精确采样区域另附图。',font=font(18),fill='#354138')
   draw.text((12,898),f"平均亮度差：{result['before_contrast_percent']:.1f}% → {result['after_contrast_percent']:.1f}%（要求 ≥15%）",font=font(22),fill='#354138')
   draw.text((12,934),f"新版 Y′ 深草 {result['regions']['deep']['after_mean_Yprime']:.3f} / 普通草 {result['regions']['ordinary']['after_mean_Yprime']:.3f}",font=font(17),fill='#354138')
   canvas.save(DOC/f'{name}-comparison.png')
   # Separate evidence image keeps the primary comparison unobscured.
   sampling=canvas.copy();sample_draw=ImageDraw.Draw(sampling)
   for x in [12,384]:
    for label,color in [('deep','#ec5768'),('ordinary','#ffffff')]:
     edge=binary_dilation(masks[label])&~masks[label]
     yy,xx=np.where(edge)
     for px,py in zip(xx,yy):sample_draw.point((x+int(px),56+int(py)),fill=color)
   sampling.save(DOC/f'{name}-sampling.png')
  else:shutil.copy2(CAP/f'{name}-after.png',DOC/'grass-closeup.png')
  print(name,'contrast %.2f%%'%result['after_contrast_percent'],'samples',int(masks['deep'].sum()),int(masks['ordinary'].sum()),'outside',result['outside_grass_max_RGB255'])
 asset=ROOT/'assets/landmarks/alcatraz_island/ground'
 for name in ['alc_ground_surfaces.png','alc_ground_surfaces.png.import','alc_dock_detail.tres','alc_ground_fields.png.import','alc_ground_detail.gdshader.uid']:
  old=subprocess.check_output(['git','show',report['before_commit']+':'+str((asset/name).relative_to(ROOT))],cwd=ROOT)
  current=(asset/name).read_bytes();assert old==current,name
  report['preserved'][name]=hashlib.sha256(current).hexdigest()
 old=Image.open(io.BytesIO(subprocess.check_output(['git','show',report['before_commit']+':'+str((asset/'alc_ground_fields.png').relative_to(ROOT))],cwd=ROOT)))
 current=np.array(Image.open(asset/'alc_ground_fields.png'));assert np.array_equal(np.array(old)[:,:,1:],current[:,:,1:])
 report['preserved']['fields_GB_exact']=True
 old_shader=subprocess.check_output(['git','show',report['before_commit']+':'+str((asset/'alc_ground_detail.gdshader').relative_to(ROOT))],cwd=ROOT).decode()
 current_shader=(asset/'alc_ground_detail.gdshader').read_text()
 assert old_shader[old_shader.index('        } else if (path)'):]==current_shader[current_shader.index('        } else if (path)'):]
 report['preserved']['paving_dock_and_final_shading_code_exact']=True
 report['passed']=True
 (DOC/'brightness-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 shutil.copy2(CAP/'render-validation.json',DOC/'render-validation.json')
if __name__=='__main__':main()
