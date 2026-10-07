#!/usr/bin/env python3
"""Run actual desktop Godot checks, optionally capture a real-time route video."""
from pathlib import Path
import argparse
import json
import os
import subprocess
import time
import math

ROOT=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser()
parser.add_argument('slug')
parser.add_argument('--record',action='store_true')
parser.add_argument('--project')
parser.add_argument('--output')
args=parser.parse_args()
project=ROOT/(args.project or f'output/scene-bench/{args.slug}/project')
out=ROOT/(args.output or f'output/scene-bench/{args.slug}/evidence')
out.mkdir(parents=True,exist_ok=True)
if not os.environ.get('DISPLAY'):raise SystemExit('A real display is required. Set DISPLAY and the current XAUTHORITY.')
base=['godot','--path',str(project),'--resolution','960x720','--position','0,0','--borderless','--',
      '--slug',args.slug,'--output',str(out)]
with (out/'test.log').open('w') as log:
    result=subprocess.run([*base,'--test'],stdout=log,stderr=subprocess.STDOUT,timeout=130)
report=json.loads((out/'result.json').read_text()) if (out/'result.json').exists() else {}
print(json.dumps({'slug':args.slug,'passed':report.get('passed',False),'checks':len(report.get('checks',[]))}),flush=True)
if result.returncode or not report.get('passed'):raise SystemExit(result.returncode or 1)
if not args.record:raise SystemExit(0)
go=out/'record-go'
if go.exists():go.unlink()
log=(out/'record.log').open('w')
app=subprocess.Popen([*base,'--record-route'],stdout=log,stderr=subprocess.STDOUT)
recorder=None
try:
    deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        if app.poll() is not None:raise RuntimeError('Godot exited before recorder handshake')
        try:
            state=json.loads((out/'state.json').read_text())
            if state['pid']==app.pid and state['phase']=='record-ready':break
        except (OSError,ValueError):pass
        time.sleep(.05)
    else:raise RuntimeError('Recorder readiness timeout')
    recorder=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','x11grab','-draw_mouse','0',
        '-framerate','30','-video_size','960x720','-i',os.environ['DISPLAY']+'+0,0','-t','15',
        '-c:v','libx264','-preset','veryfast','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',
        '-metadata','comment=Real-time desktop Godot Mobile/Vulkan fixture route; not physical-phone performance',str(out/'walkthrough.mp4')])
    time.sleep(.25)
    go.write_text(str(app.pid))
    assert recorder.wait(timeout=25)==0
    assert app.wait(timeout=30)==0
    route=json.loads((out/'record-result.json').read_text());assert route['passed']
    probe=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_name,width,height','-of','json',str(out/'walkthrough.mp4')],capture_output=True,text=True,check=True)
    video=json.loads(probe.stdout);assert 14.8<=float(video['format']['duration'])<=15.2
    frame_checks=[]
    for i,t in enumerate((.5,7.5,14.0)):
        subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(t),'-i',str(out/'walkthrough.mp4'),'-frames:v','1',str(out/f'video-{i}.png')],check=True)
        decoded=subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-ss',str(t),'-i',str(out/'walkthrough.mp4'),
            '-frames:v','1','-vf','scale=64:48','-pix_fmt','gray','-f','rawvideo','pipe:1'],capture_output=True,check=True).stdout
        assert len(decoded)==64*48
        mean=sum(decoded)/len(decoded)
        std=math.sqrt(sum((x-mean)**2 for x in decoded)/len(decoded))
        visible=mean>8 and std>8
        frame_checks.append({'time_seconds':t,'luma_mean':mean,'luma_std':std,'nonblack_nonuniform':visible})
    video['frame_checks']=frame_checks
    video['image_content_valid']=all(x['nonblack_nonuniform'] for x in frame_checks)
    (out/'video-metadata.json').write_text(json.dumps(video,indent=2)+'\n')
    if not video['image_content_valid']:
        raise RuntimeError('Recording contains black/blank sample frames; encoding/route success is insufficient. Inspect video-*.png; do not deliver this clip.')
    print('REAL_TIME_ROUTE_VIDEO_VERIFIED',args.slug,flush=True)
finally:
    if recorder and recorder.poll() is None:recorder.terminate();recorder.wait(timeout=5)
    if app.poll() is None:app.terminate();app.wait(timeout=10)
    log.close()
