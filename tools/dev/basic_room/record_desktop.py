#!/usr/bin/env python3
"""Record the live desktop Godot renderer. This is a presentation, not an input test."""
import json
import os
from pathlib import Path
import statistics
import subprocess
import time

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/"output/basic-room-2026-10-06"
STATE=Path(os.environ.get('XDG_DATA_HOME',str(Path.home()/'.local/share')))/"SensenBasicRoomQA/room-qa"
STATE.mkdir(parents=True,exist_ok=True)
(STATE/'command.json').unlink(missing_ok=True)
sequence=int(time.time()*1000)

def read():
    return json.loads((STATE/'state.json').read_text())

def command(**kwargs):
    global sequence
    sequence+=1;kwargs['sequence']=sequence
    p=STATE/'command.pending';p.write_text(json.dumps(kwargs));p.replace(STATE/'command.json')
    deadline=time.monotonic()+10
    while time.monotonic()<deadline:
        try:
            if read().get('command_sequence',-1)>=sequence:return
        except (OSError,ValueError):pass
        time.sleep(.05)
    raise RuntimeError('Desktop review command was not acknowledged')

log=(OUT/'desktop-review.log').open('w')
app=subprocess.Popen(['godot','--path',str(OUT/'qa-project'),'--resolution','700x700','--position','0,0','--borderless'],stdout=log,stderr=subprocess.STDOUT)
recorder=None
try:
    deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        try:
            s=read()
            if s['pid']==app.pid and s['ready'] and s['time']>2:break
        except (OSError,ValueError):pass
        time.sleep(.1)
    else:raise RuntimeError('Desktop scene did not become ready')
    command(reset=True,beauty=True,hud=False,capture=str(OUT/'desktop-video-cover.png'))
    time.sleep(.4)
    recorder=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','x11grab','-draw_mouse','0',
        '-framerate','30','-video_size','700x700','-i',os.environ.get('DISPLAY',':0')+'+0,0','-t','28',
        '-c:v','libx264','-preset','veryfast','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',
        '-metadata','comment=Live desktop Godot Mobile/Vulkan capture; not Android phone performance.',str(OUT/'desktop-review.mp4')])
    samples=[]
    def wait(seconds):
        end=time.monotonic()+seconds
        while time.monotonic()<end:
            samples.append(read());time.sleep(.25)
    wait(3)
    command(beauty=False,hud=True,reset=True)
    wait(2)
    for vector in [[-.65,0],[0,-.65],[.65,0],[0,.65]]:
        command(input=vector,duration=1.0)
        wait(1.9)
    command(reset=True,zoom=7.8,focus=[.4,1.0,.6])
    wait(4)
    command(beauty=True,hud=False,reset=True)
    while recorder.poll() is None:wait(.5)
    assert recorder.returncode==0
    result={'samples':samples,'fps_median':statistics.median(s['fps'] for s in samples),
        'fps_min':min(s['fps'] for s in samples),'draw_calls_median':statistics.median(s['draw_calls'] for s in samples),
        'device':samples[-1]['rendering_device'],'scope':'Live desktop Vulkan, not physical mobile hardware'}
    (OUT/'desktop-performance.json').write_text(json.dumps(result,indent=2))
    print(json.dumps({k:v for k,v in result.items() if k!='samples'}))
finally:
    if recorder and recorder.poll() is None:recorder.terminate();recorder.wait(timeout=5)
    app.terminate();app.wait(timeout=10)
    log.close()
