"""Verified native captures, four separate corners, same-scale tea comparison."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'output/church-423';CAP=OUT/'captures';DOC=ROOT/'docs/design/poi-church-423-2026-11-05'
DOC.mkdir(parents=True,exist_ok=True);PREFIX='SGODOT-423_church_v1_'
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def font(s):return ImageFont.truetype(FONT,s)
def main():
 for name,target in [('default_360','default_360x800'),('labyrinth_readability','labyrinth_readability'),('overview','overview'),('topdown','topdown_routes_seats')]:
  im=Image.open(CAP/(name+'.png')).convert('RGB')
  if name not in ['default_360','labyrinth_readability']:
   d=ImageDraw.Draw(im);d.rounded_rectangle((12,12,700,60),10,fill='#FBF5E8');d.text((24,19),'黄忠 · SGODOT-423 · '+('全景' if name=='overview' else '俯视 / 通道与 8 个座位'),font=font(25),fill='#344C40')
  im.save(DOC/(PREFIX+target+'.png'))
 raw=Image.open(CAP/'default_clean.png').convert('RGB')
 for name,rect in [('top_left',(0,0,90,90)),('top_right',(270,0,360,90)),('bottom_left',(0,710,90,800)),('bottom_right',(270,710,360,800))]:
  crop=raw.crop(rect).resize((360,360),Image.Resampling.NEAREST);im=Image.new('RGB',(400,420),'#F5F0E6');im.paste(crop,(20,44))
  ImageDraw.Draw(im).text((20,12),'黄忠 / '+name+' / 4×',font=font(18),fill='#344C40');im.save(DOC/(PREFIX+'corner_'+name+'.png'))
 comp=Image.new('RGB',(780,890),'#F5F0E6');d=ImageDraw.Draw(comp)
 for x,title,name in [(20,'教堂 10.5×10.5 m','default_360'),(400,'茶馆 6.8×6.4 m','tea_same_scale')]:
  comp.paste(Image.open(CAP/(name+'.png')).convert('RGB'),(x,54));d.text((x,15),title,font=font(22),fill='#344C40')
 d.text((20,859),'黄忠 · 同为 360×800 / 43° / 镜头宽 6.72 m / 人高 1.745 m',font=font(18),fill='#344C40')
 comp.save(DOC/(PREFIX+'tea_same_scale.png'))
 original=np.array(raw);control=np.array(Image.open(CAP/'coverage_magenta.png').convert('RGB'))
 changed=np.any(original!=control,axis=2)
 coverage={'method':'Only environment clear colour changed from DDE8E7 to FF00FF; geometry/camera/light fixed','changed_pixels':int(changed.sum()),'total_pixels':int(changed.size),'corner_pixels':{},'edge_pixels_changed':int(changed[0].sum()+changed[-1].sum()+changed[:,0].sum()+changed[:,-1].sum())}
 for name,ys,xs in [('top_left',slice(0,90),slice(0,90)),('top_right',slice(0,90),slice(270,360)),('bottom_left',slice(710,800),slice(0,90)),('bottom_right',slice(710,800),slice(270,360))]:coverage['corner_pixels'][name]=int(changed[ys,xs].sum())
 assert coverage['changed_pixels']==0,coverage
 report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','geometry':json.loads((OUT/'geometry-validation.json').read_text()),'godot':json.loads((CAP/'godot-validation.json').read_text()),'coverage':coverage}
 if (OUT/'bench/result.json').exists():report['scene_bench']=json.loads((OUT/'bench/result.json').read_text())
 report['passed']=report['geometry']['passed'] and report['godot']['passed'] and report.get('scene_bench',{}).get('passed',False)
 (DOC/(PREFIX+'validation.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 assets=report['geometry']['assets'];lines=['| 模块 | 三角面 | 尺寸 X / Y / Z（m） |','| --- | ---: | --- |']
 for a in assets:
  low,high=np.array(a['bounds']);lines.append('| '+a['name']+' | '+str(a['triangles'])+' | '+' / '.join(f'{v:.3f}' for v in high-low)+' |')
 (DOC/'asset-table.md').write_text('\n'.join(lines)+'\n')
 media=[]
 for path in sorted(DOC.glob(PREFIX+'*')):
  row={'file':path.name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
  if path.suffix=='.png':
   row['size']=list(Image.open(path).size);assert max(row['size'])<=1600
  media.append(row)
 (DOC/'media-manifest.json').write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
 print('MEDIA',len(media),'all_validations_passed',report['passed'],'coverage',coverage)
if __name__=='__main__':main()
