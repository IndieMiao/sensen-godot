"""Package the revised independent layer; preserve v1 as historical evidence."""
from pathlib import Path
import hashlib,json,shutil,subprocess
from PIL import Image,ImageDraw,ImageFont
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
OUT=ROOT/'output/cookpot-419';RENDERS=OUT/'renders'
DOC=ROOT/'docs/design/cooking-pot-wait-419-2026-11-05/v1.1';DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-419_cooking_pot_v1.1_'
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def font(size):return ImageFont.truetype(FONT,size)
for name,title in [('closed','合盖 · 0.12 s'),('lifted','顶起 · 0.88 s'),('settled','落回后轻抖 · 1.28 s'),('idle','idle · 仅冒热气')]:
    im=Image.open(RENDERS/(PREFIX+name+'.png')).convert('RGB')
    d=ImageDraw.Draw(im);d.text((22,18),'SGODOT-419 / A v1.1 / '+title,font=font(22),fill='#344C40')
    d.text((22,680),'黄忠 · Mobile / Vulkan · 盖沿抬升 ≤ 1.8 cm',font=font(17),fill='#344C40')
    im.save(DOC/(PREFIX+name+'.png'))
for name in ['overlay_ring','layer_rgba']:
    shutil.copy2(RENDERS/(PREFIX+name+'.png'),DOC/(PREFIX+name+'.png'))
phone=Image.open(RENDERS/(PREFIX+'overlay_ring.png')).convert('RGB')
zoom=phone.crop((80,150,280,330)).resize((800,720),Image.Resampling.NEAREST)
im=Image.new('RGB',(840,840),'#F5F2E9');im.paste(zoom,(20,60));d=ImageDraw.Draw(im)
d.text((20,16),'黄忠 · 原生 200×180 叠层 / 圆环占位 ×4',font=font(22),fill='#344C40')
d.text((20,794),'蒸汽 alpha 上界 0.469；锅口 (180,235)，环半径 60 px',font=font(20),fill='#344C40')
im.save(DOC/(PREFIX+'overlay_detail.png'))
for folder,name,frames in [('studio_v11_frames','tumble',108),('overlay_frames','overlay_motion',90)]:
    assert len(list((RENDERS/folder).glob('*.png')))==frames
    target=DOC/(PREFIX+name+'.mp4')
    vf=f"drawtext=fontfile={FONT}:text='HUANG ZHONG / SGODOT-419 v1.1':fontsize=12:fontcolor=0x344C40:box=1:boxcolor=white@0.7:x=10:y=h-24"
    subprocess.run(['ffmpeg','-y','-loglevel','error','-framerate','30','-i',str(RENDERS/folder/'%04d.png'),'-vf',vf,'-c:v','libx264','-preset','medium','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(target)],check=True)
validation=json.loads((OUT/'validation.json').read_text())
validation['overlay']=json.loads((OUT/'overlay-validation.json').read_text())
validation['author']='黄忠';validation['virtual_user_id']='5281cd25-6a49-4df8-9802-f3e534956e80'
asset=ROOT/'assets/props/cooking_pot_wait'
protected=['assets/props/stove_pot/stove_pot.glb']+['assets/props/cooking_pot_wait/'+p.name for p in asset.iterdir() if p.suffix in ['.res','.tres'] or p.name=='resource_uids.json']
unchanged={}
for rel in protected:
    before=subprocess.check_output(['git','show','76dd3cb4:'+rel],cwd=ROOT)
    now=(ROOT/rel).read_bytes();assert before==now,rel
    unchanged[rel]=hashlib.sha256(now).hexdigest()
validation['unchanged_from_v1_sha256']=unchanged
rgba=Image.open(DOC/(PREFIX+'layer_rgba.png')).convert('RGBA')
assert rgba.size==(200,180) and rgba.getpixel((0,0))[3]==0 and rgba.getpixel((199,179))[3]==0
validation['native_layer_rgba']={'size':[200,180],'corner_alpha':0}
(DOC/(PREFIX+'validation.json')).write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
manifest=[]
for path in sorted(DOC.glob(PREFIX+'*')):
    record={'file':path.name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    if path.suffix=='.png':record['size']=list(Image.open(path).size)
    if path.suffix=='.mp4':
        probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
        stream=probe['streams'][0];record.update(size=[stream['width'],stream['height']],frames=int(stream['nb_frames']),duration=float(probe['format']['duration']))
        expected=90 if 'overlay' in path.name else 108
        assert record['frames']==expected and abs(record['duration']-expected/30)<.01
    manifest.append(record)
(DOC/'media-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('Packaged',len(manifest),'verified v1.1 review files')
