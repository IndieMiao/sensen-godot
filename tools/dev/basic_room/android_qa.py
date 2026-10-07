#!/usr/bin/env python3
"""Actual Android inputs and screenshots; run inside tools/android/run_test.sh.

The only direct fixture commands are reset/position/view setup. Movement, release,
pinch and UI checks inject Android MotionEvents, never simulated game movement.
"""
import argparse
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/"output/basic-room-2026-10-06/android"
OUT.mkdir(parents=True,exist_ok=True)
ADB=ROOT/"tools/dev/basic_room/adb.sh"
SERIAL=os.environ.get("JOURNEY_SERIAL","emulator-5588")
PKG=os.environ.get("JOURNEY_PACKAGE","com.sensen.basicroomqa")
assert SERIAL.startswith("emulator-") and PKG=="com.sensen.basicroomqa"
checks=[];sequence=int(time.time()*1000);touches=0

def adb(*args, timeout=30, binary=False, data=None):
    r=subprocess.run([str(ADB),'-s',SERIAL,*map(str,args)],input=data,capture_output=True,timeout=timeout)
    if r.returncode:raise RuntimeError(r.stderr.decode(errors='replace')+r.stdout.decode(errors='replace'))
    return r.stdout if binary else r.stdout.decode(errors='replace').strip()

def state():
    s=json.loads(adb('exec-out','run-as',PKG,'cat','files/room-qa/state.json'))
    pid=int(adb('shell','pidof','-s',PKG))
    assert s['pid']==pid, 'Observer must belong to current process'
    return s

def until(predicate,label,timeout=35):
    deadline=time.monotonic()+timeout;last=None
    while time.monotonic()<deadline:
        try:
            last=state()
            if predicate(last):return last
        except (ValueError,RuntimeError,AssertionError):pass
        time.sleep(.25)
    (OUT/'failure-state.json').write_text(json.dumps(last,indent=2))
    raise AssertionError(label)

def command(**kwargs):
    global sequence
    sequence+=1;kwargs['sequence']=sequence
    payload=json.dumps(kwargs).encode()
    # Pipe data directly; no shell interpolation of JSON.
    adb('shell',f"run-as {PKG} sh -c 'cat > files/room-qa/command.pending'",data=payload)
    adb('shell','run-as',PKG,'mv','files/room-qa/command.pending','files/room-qa/command.json')
    until(lambda s:s.get('command_sequence',-1)>=sequence,'Fixture command acknowledgement',20)

def screenshot(name):
    p=OUT/(name+'.png');p.write_bytes(adb('exec-out','screencap','-p',binary=True))
    (OUT/(name+'.json')).write_text(json.dumps(state(),indent=2))
    return p

def check(name,passed,details=None):
    checks.append({'name':name,'passed':bool(passed),'details':details})
    print(('PASS ' if passed else 'FAIL ')+name+' '+str(details),flush=True)
    if not passed:raise AssertionError(name)

def dimensions():
    text=adb('shell','wm','size')
    matches=re.findall(r'(\d+)x(\d+)',text)
    return tuple(map(int,matches[-1]))

def touch(*args):
    global touches
    touches+=1
    return adb('shell','env','CLASSPATH=/data/local/tmp/basic-room-touch.dex','app_process','/data/local/tmp','RoomTouch',*args)

def drag(dx,dy,hold=700):
    w,h=dimensions();x=w*.30;y=h*.78
    return touch('drag',round(x),round(y),round(x+dx*w/1080),round(y+dy*w/1080),140,hold)

def tap_button(name):
    global touches
    s=state();w,h=dimensions()
    b=next(b for b in s['buttons'] if b['name']==name);x,y,bw,bh=b['rect']
    touches+=1
    adb('shell','input','tap',round((x+bw/2)*w/s['viewport'][0]),round((y+bh/2)*h/s['viewport'][1]))
    time.sleep(.5)

def dismiss_system_tips():
    for attempt in range(3):
        adb('shell','uiautomator','dump','/sdcard/basic-room-ui.xml',timeout=15)
        xml=adb('exec-out','cat','/sdcard/basic-room-ui.xml')
        (OUT/f'system-ui-{attempt}.xml').write_text(xml)
        root=ET.fromstring(xml)
        button=next((n for n in root.iter('node') if n.get('text') in ['Got it','OK',"Don't Show Again"]),None)
        if button is None:return
        nums=list(map(int,re.findall(r'\d+',button.get('bounds',''))))
        adb('shell','input','tap',(nums[0]+nums[2])//2,(nums[1]+nums[3])//2)
        time.sleep(.8)

def restart():
    adb('shell','am','force-stop',PKG)
    adb('shell','run-as',PKG,'rm','-f','files/room-qa/command.json')
    adb('shell','am','start','-n',PKG+'/com.godot.game.GodotAppLauncher')
    return until(lambda s:s['ready'] and s['time']>2,'Fresh cold-start model and avatar',60)

def suite():
    dismiss_system_tips()
    s=until(lambda s:s['ready'] and s['time']>2,'Scene ready after Android education',60)
    check('Android Vulkan Mobile scene loads',s['rendering_method']=='mobile',s['rendering_device'])
    on_path=screenshot('01-room-with-player')
    command(beauty=True)
    off_path=screenshot('01-room-without-player-control')
    # Require the body below the head, catching an emulator that only draws rigid hair.
    from PIL import Image
    import numpy as np
    on=np.asarray(Image.open(on_path).convert('RGB')).astype(np.int16)
    off=np.asarray(Image.open(off_path).convert('RGB')).astype(np.int16)
    px=s['player_screen'][0]*on.shape[1]/s['viewport'][0]
    py=s['player_screen'][1]*on.shape[0]/s['viewport'][1]
    region=np.abs(on-off).sum(axis=2)
    changed=int((region[int(py-on.shape[0]*.060):int(py),int(px-on.shape[1]*.045):int(px+on.shape[1]*.045)]>35).sum())
    check('Skinned body is visible below the head',changed>250,changed)
    command(beauty=False)
    command(reset=True,beauty=False,hud=True)
    before=state();drag(150,0,650)
    after=until(lambda s:math.hypot(s['velocity'][0],s['velocity'][2])<.02 and math.hypot(*s['input'])<.02,'Touch release stops',15)
    check('Android floating joystick moves character',math.dist(before['position'],after['position'])>.35,[before['position'],after['position']])
    check('Touch release returns to idle',after['animation']=='idle')
    screenshot('02-after-walking')
    command(reset=True,position=[-.12,.10,1.9])
    drag(100,-118,900)
    s=until(lambda s:math.hypot(*s['input'])<.02,'Table collision input release')
    check('Real touch cannot cross dining table',s['position'][2]>1.39 and s['position'][2]<1.7,s['position'])
    command(reset=True,position=[2.5,.10,1.5])
    drag(118,100,900)
    s=until(lambda s:math.hypot(*s['input'])<.02,'Boundary input release')
    check('Real touch cannot leave open room edge',s['position'][0]<3.02,s['position'])
    command(reset=True)
    before=state();w,h=dimensions()
    touch('pinch',round(w*.5),round(h*.53),round(w*.25),round(w*.43),700)
    after=until(lambda s:s['zoom']<9,'Pinch updates orthographic camera')
    check('Two-finger pinch changes camera scale',after['zoom']<9,[before['zoom'],after['zoom']])
    check('Two-finger zoom keeps avatar still',math.dist(before['position'],after['position'])<.06,[before['position'],after['position']])
    screenshot('03-pinch-detail')
    tap_button('ViewButton')
    s=until(lambda s:s['beauty'],'View button opens reference view')
    check('View button restores whole-room scale',abs(s['zoom']-10.75)<.01)
    command(beauty=True,hud=False)
    screenshot('04-room-clean')
    command(beauty=False,hud=True,reset=True)
    before=state();pid=before['pid']
    adb('shell','input','keyevent','3');time.sleep(.8)
    adb('shell','am','start','-n',PKG+'/com.godot.game.GodotAppLauncher')
    after=until(lambda s:s['pid']==pid and s['time']>before['time']+.5,'Same-process foreground resume',40)
    check('Foreground retains player position',math.dist(before['position'],after['position'])<.05)
    check('Foreground retains camera scale',abs(before['zoom']-after['zoom'])<.01)
    for size in ['720x1280','780x1688','1080x1920']:
        adb('shell','wm','size',size);time.sleep(.5)
        s=restart();dismiss_system_tips()
        command(reset=True,beauty=False,hud=True)
        s=state();vw,vh=s['viewport']
        check('HUD remains within '+size,all(b['rect'][0]>=0 and b['rect'][0]+b['rect'][2]<=vw+1 and b['rect'][1]>=0 and b['rect'][1]+b['rect'][3]<vh for b in s['buttons']),s['buttons'])
        screenshot('size-'+size)
        before=state();drag(-120,0,320)
        after=until(lambda s:math.hypot(*s['input'])<.02,'Size-change touch release')
        check('Movement after resize '+size,math.dist(before['position'],after['position'])>.25)
    command(reset=True,beauty=False,hud=True)
    samples=[]
    for i in range(24):
        time.sleep(.5);samples.append(state())
    metrics={'renderer':samples[-1]['rendering_method'],'device':samples[-1]['rendering_device'],
             'samples':samples,'fps_median':statistics.median(s['fps'] for s in samples),
             'fps_min':min(s['fps'] for s in samples),'draw_calls_median':statistics.median(s['draw_calls'] for s in samples),
             'video_memory_max_bytes':max(s['video_memory_bytes'] for s in samples),
             'scope':'Android emulator; not physical phone GPU timing'}
    (OUT/'performance.json').write_text(json.dumps(metrics,indent=2))
    check('Idle animation advances',len({round(s['animation_time'],3) for s in samples})>4)
    screenshot('05-final-gameplay')
    return metrics

def record():
    command(reset=True,beauty=True,hud=False)
    device_file='/sdcard/basic-room-review.mp4'
    recording=subprocess.Popen([str(ADB),'-s',SERIAL,'shell','screenrecord','--bit-rate','6000000','--time-limit','32',device_file],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    time.sleep(4)
    command(beauty=False,hud=True,reset=True)
    for dx,dy,duration in [(-150,0,700),(0,-150,650),(150,0,450),(0,150,550)]:
        drag(dx,dy,duration);time.sleep(1.3)
    command(reset=True)
    w,h=dimensions();touch('pinch',round(w*.5),round(h*.52),round(w*.28),round(w*.43),900)
    time.sleep(3)
    command(beauty=True,hud=False,reset=True)
    recording.communicate(timeout=45)
    if recording.returncode:raise RuntimeError('Android screenrecord failed')
    adb('pull',device_file,str(OUT/'android-review-raw.mp4'),timeout=45)
    screenshot('video-cover')
    command(beauty=False,hud=True,reset=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--record-only',action='store_true');args=parser.parse_args()
    try:
        metrics=None if args.record_only else suite()
        record()
        (OUT/'result.json').write_text(json.dumps({'passed':True,'checks':checks,'touch_operations':touches,'metrics_summary':None if metrics is None else {k:v for k,v in metrics.items() if k!='samples'}},indent=2))
    except Exception as error:
        (OUT/'result.json').write_text(json.dumps({'passed':False,'checks':checks,'touch_operations':touches,'error':str(error)},indent=2))
        raise
