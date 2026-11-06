from pathlib import Path
import json, hashlib, shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'output/far-backdrop-434';CAP=OUT/'captures';DOC=ROOT/'docs/design/far-backdrop-434'
DOC.mkdir(parents=True,exist_ok=True)
font='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
for name,title,subtitle in [('urban-bay','Urban bay / bridge + high city + hills A','826 triangles / 3 cards / zero texture reads'),('quiet-bay','Quiet bay / medium + low city + hills B','338 triangles / 3 cards / zero texture reads')]:
    im=Image.open(CAP/(name+'.png')).convert('RGB');assert im.size==(360,800)
    d=ImageDraw.Draw(im);d.rectangle((0,0,360,56),fill='#f2f0e8')
    d.text((10,8),'SGODOT-434 / '+name,font=ImageFont.truetype(font,15),fill='#334646')
    d.text((10,32),'360 x 800 | Vulkan Mobile | 432 bay preset',font=ImageFont.truetype(font,11),fill='#334646')
    d.rectangle((0,746,360,800),fill='#f2f0e8')
    for i,line in enumerate([title,subtitle]):d.text((10,754+i*21),line,font=ImageFont.truetype(font,11),fill='#334646')
    im.save(DOC/(name+'-default-review.png'))
def pixels(name):return np.asarray(Image.open(CAP/(name+'.png'))).astype(float)[...,:3]
report={}
for name,control in [('urban-bay','urban-no-cards'),('quiet-bay','quiet-no-cards')]:
    delta=abs(pixels(name)-pixels(control));mask=delta.max(axis=2)>1
    y,x=np.nonzero(mask);assert len(x)>100
    assert y.min()>55 and y.max()<135,'Only horizon cards may change; foreground must remain identical'
    report[name]={'visible_changed_pixels':len(x),'screen_bounds':[int(x.min()),int(y.min()),int(x.max()),int(y.max())]}
for name in ['bridge-cool','heavy-fog']:
    delta=abs(pixels('urban-bay')-pixels(name));n=int((delta.max(axis=2)>2).sum());assert n>100
    report[name]={'changed_pixels_over_2_rgb':n,'max_channel_delta_255':float(delta.max())}
report['passed']=True
(DOC/'visual-validation.json').write_text(json.dumps(report,indent=2)+'\n')
for source,target in [(OUT/'geometry-validation.json','geometry-validation.json'),(OUT/'resource-validation.json','resource-validation.json'),(CAP/'render-validation.json','render-validation.json')]:shutil.copy2(source,DOC/target)
names=['urban-bay-default-review.png','quiet-bay-default-review.png']+[n for n in ['android-urban.png','android-quiet.png'] if (DOC/n).exists()]
manifest={n:{'bytes':(DOC/n).stat().st_size,'sha256':hashlib.sha256((DOC/n).read_bytes()).hexdigest()} for n in names}
(DOC/'media-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(report,indent=2))
