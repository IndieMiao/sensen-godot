"""Reuse the verified viewport recorder when desktop X11 capture returns black."""
from pathlib import Path
import hashlib
import json
import math
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[4]
PROJECT=ROOT/'output/tea-216/project'
OUT=ROOT/'output/tea-216/bench'
RECORDER=ROOT/'tools/art/source/coffee_shop/record_r1.gd'
shutil.copy2(RECORDER,PROJECT/'record_tea.gd')
(OUT/'record-go').unlink(missing_ok=True)
layout_path=PROJECT/'assets/rooms/tea_house/layout.json'
original_layout=layout_path.read_text();view=json.loads(original_layout)
direction=[a-b for a,b in zip(view['camera']['position'],view['camera']['target'])]
view['camera']['target']=[0,1.85,.30]
view['camera']['position']=[a+b for a,b in zip(view['camera']['target'],direction)]
view['camera']['size']=12.8
layout_path.write_text(json.dumps(view,indent=2)+'\n')
with (OUT/'record-viewport.log').open('w') as log:
    process=subprocess.Popen(['godot','--disable-vsync','--max-fps','60','--path',str(PROJECT),
        '--resolution','960x720','--position','0,0','--borderless','--script','res://record_tea.gd','--',
        '--slug','tea_house','--output',str(OUT),'--record-route'],stdout=log,stderr=subprocess.STDOUT)
    print('TEA_VIEWPORT_RECORDER_PID',process.pid,flush=True)
    try:assert process.wait(timeout=75)==0
    finally:
        if process.poll() is None:process.terminate();process.wait(timeout=10)
        layout_path.write_text(original_layout)
result=json.loads((OUT/'record-result.json').read_text());assert result['passed']
frames=json.loads((OUT/'viewport-frames.json').read_text())['frames']
assert len(frames)>100 and frames[-1]['seconds']>14.8
sequence=['ffconcat version 1.0']
if frames[0]['seconds']>.001:
    sequence += ["file '"+frames[0]['file']+"'",f'duration {frames[0]["seconds"]:.6f}']
for index,frame in enumerate(frames):
    end=frames[index+1]['seconds'] if index+1<len(frames) else 15.0
    sequence += ["file '"+frame['file']+"'",f'duration {max(.001,end-frame["seconds"]):.6f}']
sequence += ["file '"+frames[-1]['file']+"'"]
(OUT/'viewport.ffconcat').write_text('\n'.join(sequence)+'\n')
subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','concat','-safe','0','-i',str(OUT/'viewport.ffconcat'),
    '-vf','fps=30','-t','15','-c:v','libx264','-preset','veryfast','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',
    '-metadata','comment=Huangzhong SGODOT-216; real-time Godot viewport, original wall-clock intervals, no acceleration',str(OUT/'walkthrough.mp4')],check=True)
checks=[]
for index,seconds in enumerate([.5,7.5,14.]):
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(seconds),'-i',str(OUT/'walkthrough.mp4'),
                    '-frames:v','1',str(OUT/f'video-{index}.png')],check=True)
    raw=subprocess.check_output(['ffmpeg','-hide_banner','-loglevel','error','-ss',str(seconds),'-i',str(OUT/'walkthrough.mp4'),
        '-frames:v','1','-vf','scale=64:48','-pix_fmt','gray','-f','rawvideo','pipe:1'])
    assert len(raw)==3072
    mean=sum(raw)/len(raw);std=math.sqrt(sum((value-mean)**2 for value in raw)/len(raw))
    checks.append({'time_seconds':seconds,'luma_mean':mean,'luma_std':std,'nonblack_nonuniform':mean>8 and std>8})
metadata=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_name,width,height',
                                            '-of','json',str(OUT/'walkthrough.mp4')],text=True))
metadata.update({'frame_checks':checks,'image_content_valid':all(c['nonblack_nonuniform'] for c in checks),
    'capture':'Existing rendered viewport recorder; original monotonic wall-clock frame intervals','accelerated':False,
    'captured_frames':len(frames),'camera':'Overview 43 degrees, 12.8m width; default art camera remains 6.72m',
    'recorder_source':str(RECORDER.relative_to(ROOT)),
    'recorder_sha256':hashlib.sha256(RECORDER.read_bytes()).hexdigest(),
    'max_capture_interval_seconds':max(b['seconds']-a['seconds'] for a,b in zip(frames,frames[1:]))})
assert 14.8<=float(metadata['format']['duration'])<=15.2 and metadata['image_content_valid']
(OUT/'video-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(json.dumps(metadata,indent=2))
