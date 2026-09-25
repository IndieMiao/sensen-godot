#!/usr/bin/env python3
"""Actual phone inputs from a fresh read-only Godot control tree. No farm actions."""
import json
import os
from pathlib import Path
import statistics
import subprocess
import time

SERIAL = os.environ['JOURNEY_SERIAL']
PACKAGE = os.environ['JOURNEY_PACKAGE']
assert SERIAL == '10AFAF162200319' and PACKAGE == 'com.sensen.journeypreview'
OUT = Path('output/pond-pitch-2026-09-25/phone/runtime')
OUT.mkdir(parents=True, exist_ok=True)
operations = 0
results = []


def adb(*args):
    return subprocess.check_output(['adb', '-s', SERIAL, *args], timeout=40)


def state():
    return json.loads(adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/pond-device-proof/state.json'))


def until(predicate, label, timeout=60):
    end = time.monotonic() + timeout
    last = {}
    while time.monotonic() < end:
        try:
            last = state()
            if predicate(last):
                return last
        except (ValueError, subprocess.SubprocessError):
            pass
        time.sleep(.15)
    (OUT/'failure-state.json').write_text(json.dumps(last, indent=2))
    raise AssertionError(label)


def point(x, y):
    global operations
    adb('shell', 'input', 'tap', str(round(x)), str(round(y)))
    operations += 1
    time.sleep(.3)


def tap(selector):
    match = lambda c: not c['disabled'] and c['bounds'][2] > 4 and c['bounds'][3] > 4 and (selector(c) if callable(selector) else c['name'] == selector)
    s = until(lambda s: any(match(c) for c in s['controls']), str(selector))
    c = next(c for c in s['controls'] if match(c))
    x,y,w,h = c['bounds']
    point(x+w/2, y+h/2)


def shot(name):
    s = state()
    (OUT/(name+'.json')).write_text(json.dumps(s, indent=2))
    (OUT/(name+'.png')).write_bytes(adb('exec-out', 'screencap', '-p'))
    print('PHONE_ART', name, s['fps'], flush=True)
    return s


def area(s):
    controls = {c['name']:c for c in s['controls']}
    left,top,w,h = controls['PondBack']['bounds']
    right = sum(controls['PondBag']['bounds'][::2])
    bottom = controls['PondFish']['bounds'][1]
    return left,top+h+25,right-left,bottom-top-h-50


def pinch(factor):
    global operations
    s = state()
    x,y,w,h = area(s)
    cx,cy,half = x+w*.5,y+h*.56,w*.12
    coords = [cx-half,cy,cx+half,cy,cx-half*factor,cy,cx+half*factor,cy]
    adb('shell','env','CLASSPATH=/data/local/tmp/pond-art-touch.dex','app_process','/data/local/tmp','JourneyTouch',*[str(round(v)) for v in coords],'550')
    operations += 1
    time.sleep(.9)


try:
    current_pid = int(adb('shell','pidof','-s',PACKAGE).strip())
    until(lambda s:s.get('process_id') == current_pid and s['logged_in'] and s['has_farm'] and s['scene'].endswith('/city_select/city_select.tscn'), 'fresh process existing account login')
    shot('city')
    choice = json.loads(Path('output/pond-pitch-2026-09-25/phone/private/before/region_choice.json').read_text())
    names = ['Los Angeles','洛杉矶'] if choice['region_id'] == 'los_angeles' else ['Shanghai','上海']
    tap(lambda c:c['text'] in names)
    first = until(lambda s:len(s.get('map',{}).get('ponds',[])) == 6, 'six city ponds', 90)
    assert first['map_plugin'] and first['webview_plugin']
    shot('map')
    for shape in ['gourd','crescent','meander']:
        entry = next(p for p in first['map']['ponds'] if p['template_id'] == shape)
        tap('MapFilter_pond')
        tap('MapLandmarkList')
        tap('MapPlace_'+entry['id'])
        selected = until(lambda s:s.get('map',{}).get('selected',{}).get('id') == entry['id'], 'pond selected')
        pose = selected['map']['pose']
        tap(lambda c:c['text'] in ['Enter pond','进入鱼塘'])
        s = until(lambda s:s.get('pond',{}).get('id') == entry['id'] and s['pond']['joined'] and s['pond']['geometry_ready'], 'pond joined', 90)
        assert s['method'] == 'mobile' and s['driver'] == 'vulkan'
        shot(shape+'-entry')
        before = s['pond']['position']
        target = next(t for t in s['pond']['targets'] if t['walkable'] and 60<t['screen'][0]<1020 and 300<t['screen'][1]<2000 and sum((a-b)**2 for a,b in zip(t['world'],before))>.25)
        point(*target['screen'])
        until(lambda s:s['pond']['position'] != before, 'walk changes position')
        until(lambda s:s['pond']['clip'] == 'idle', 'walking completes')
        shot(shape+'-walked')
        tap('PondOverview')
        s = until(lambda s:s['pond']['overview'], 'overview')
        time.sleep(4)
        samples = []
        for i in range(24):
            samples.append(state()['fps'])
            time.sleep(.25)
        s = shot(shape+'-overview')
        player = s['pond']['position']
        camera = s['pond']['camera']
        x,y,w,h = area(s)
        adb('shell','input','swipe',str(round(x+w*.72)),str(round(y+h*.5)),str(round(x+w*.32)),str(round(y+h*.59)),'550')
        operations += 1
        time.sleep(1)
        s = shot(shape+'-pan')
        assert s['pond']['camera'] != camera and s['pond']['position'] == player
        zoom = s['pond']['zoom']
        pinch(1.35)
        s = shot(shape+'-zoom-in')
        assert s['pond']['zoom'] > zoom * 1.05
        zoom = s['pond']['zoom']
        pinch(.78)
        s = shot(shape+'-zoom-out')
        assert s['pond']['zoom'] < zoom * .95 and s['pond']['position'] == player
        # Reset the overview using the real game button, leaving player state intact.
        tap('PondOverview')
        tap('PondOverview')
        if shape == 'gourd':
            pid = adb('shell','pidof','-s',PACKAGE).strip()
            adb('shell','input','keyevent','3')
            operations += 1
            time.sleep(2)
            adb('shell','am','start','-W','-n',PACKAGE+'/com.godot.game.GodotAppLauncher')
            operations += 1
            until(lambda s:s.get('pond',{}).get('joined') and s['pond']['geometry_ready'], 'foreground pond recovery')
            assert adb('shell','pidof','-s',PACKAGE).strip() == pid
            time.sleep(2)
            shot('gourd-foreground')
            video = '/sdcard/Download/pond-art-phone.mp4'
            adb('shell','screenrecord','--bit-rate','8000000','--time-limit','12',video)
            adb('pull',video,str(OUT/'water-motion-phone.mp4'))
            adb('shell','rm',video)
        tap('PondBag')
        shot(shape+'-bag')
        adb('shell','input','keyevent','4')
        operations += 1
        time.sleep(.5)
        tap('PondBack')
        back = until(lambda s:'map' in s, 'return to map')
        assert all(abs(a-b)<.0001 for a,b in zip(pose,back['map']['pose']))
        results.append({'shape':shape,'walk':True,'pan':True,'pinch':True,'map_return':True,'fps_samples':samples,'fps_median':statistics.median(samples),'fps_min':min(samples)})
        print('PHONE_POND_PASSED', shape, results[-1]['fps_median'], flush=True)
    shot('map-returned')
    (OUT/'validation.json').write_text(json.dumps({'passed':True,'operations':operations,'results':results,'read_only_gameplay':True,'casts_or_economy_commands':False,'foreground_same_process':True},indent=2))
except Exception:
    shot('failure')
    raise
