"""Label engine renders, encode exact 30 fps captures, and hash review delivery."""
from pathlib import Path
import hashlib,json,shutil,subprocess
from PIL import Image,ImageDraw,ImageFont
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
OUT=ROOT/'output/cookpot-419';RENDERS=OUT/'renders'
DOC=ROOT/'docs/design/cooking-pot-wait-419-2026-11-05';DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-419_cooking_pot_v1_'
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def font(size):return ImageFont.truetype(FONT,size)
for name,title in [('closed','合盖 · 0.12 s'),('lifted','顶起 · 0.88 s'),('settled','落回后轻抖 · 1.28 s'),('idle','idle · 仅冒热气')]:
    im=Image.open(RENDERS/(PREFIX+name+'.png')).convert('RGB')
    d=ImageDraw.Draw(im);d.text((22,18),'SGODOT-419 / A 炖锅翻滚 / '+title,font=font(22),fill='#344C40')
    d.text((22,680),'黄忠 · Godot Mobile / Vulkan · 原尺寸 · 1.8 s 循环',font=font(17),fill='#344C40')
    im.save(DOC/(PREFIX+name+'.png'))
for name in ['phone_ring','phone_clear']:
    shutil.copy2(RENDERS/(PREFIX+name+'.png'),DOC/(PREFIX+name+'.png'))
phone=Image.open(RENDERS/(PREFIX+'phone_ring.png')).convert('RGB')
zoom=phone.crop((80,150,280,330)).resize((800,720),Image.Resampling.NEAREST)
im=Image.new('RGB',(840,840),'#F7F6EA');im.paste(zoom,(20,60));d=ImageDraw.Draw(im)
d.text((20,16),'黄忠 · 蒸汽 / 火候环原生像素 ×4（未改画面）',font=font(22),fill='#344C40')
d.text((20,794),'5 粒子全部重叠的理论 alpha 上界 0.469 < 0.5',font=font(22),fill='#344C40')
im.save(DOC/(PREFIX+'steam_ring_detail.png'))
for folder,name in [('frames','tumble'),('phone_frames','phone_motion')]:
    assert len(list((RENDERS/folder).glob('*.png')))==108
    target=DOC/(PREFIX+name+'.mp4')
    vf=f"drawtext=fontfile={FONT}:text='HUANG ZHONG / SGODOT-419 / 1.8 s loop':fontsize=12:fontcolor=0x344C40:box=1:boxcolor=white@0.7:x=10:y=h-24"
    subprocess.run(['ffmpeg','-y','-loglevel','error','-framerate','30','-i',str(RENDERS/folder/'%04d.png'),'-vf',vf,'-c:v','libx264','-preset','medium','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(target)],check=True)
validation=json.loads((OUT/'validation.json').read_text())
validation['phone']=json.loads((OUT/'phone-validation.json').read_text())
validation['b1']=json.loads((OUT/'runtime-base.json').read_text())
validation['original_stove_pot_sha256']=hashlib.sha256((ROOT/'assets/props/stove_pot/stove_pot.glb').read_bytes()).hexdigest()
validation['author']='黄忠';validation['virtual_user_id']='5281cd25-6a49-4df8-9802-f3e534956e80'
(DOC/(PREFIX+'validation.json')).write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
manifest=[]
for path in sorted(DOC.glob(PREFIX+'*')):
    record={'file':path.name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    if path.suffix=='.png':record['size']=list(Image.open(path).size)
    if path.suffix=='.mp4':
        probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
        stream=probe['streams'][0];record.update(size=[stream['width'],stream['height']],frames=int(stream['nb_frames']),duration=float(probe['format']['duration']))
        assert record['frames']==108 and abs(record['duration']-3.6)<.01
    manifest.append(record)
(DOC/'media-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(manifest,ensure_ascii=False,indent=2))
