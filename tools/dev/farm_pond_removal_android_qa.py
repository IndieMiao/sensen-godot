#!/usr/bin/env python3
"""Real inputs and HTTP settlement on the dedicated pond-retirement QA account."""
import json
import os
from pathlib import Path
import subprocess
import time
import re
import xml.etree.ElementTree as ET

SERIAL = os.environ['JOURNEY_SERIAL']
PACKAGE = os.environ['JOURNEY_PACKAGE']
assert SERIAL == 'emulator-5580' and PACKAGE == 'com.sensen.farmpondremovalqa'
OUT = Path('output/farm-pond-removal-2026-09-25/android')
OUT.mkdir(parents=True,exist_ok=True)


def adb(*args):
    return subprocess.check_output([os.environ.get('ADB','adb'),'-s',SERIAL,*args],timeout=30)


def state():
    return json.loads(adb('exec-out','run-as',PACKAGE,'cat','files/farm-pond-proof/state.json'))


def until(predicate, timeout=60):
    end = time.monotonic()+timeout
    while time.monotonic()<end:
        try:
            s=state()
            if predicate(s): return s
        except (ValueError,subprocess.SubprocessError): pass
        time.sleep(.2)
    raise AssertionError('QA state did not reach the requested condition')


def ui_tree():
    raw=adb('exec-out','uiautomator','dump','/dev/tty').decode()
    xml=raw[raw.find('<?xml'):raw.rfind('</hierarchy>')+12]
    (OUT/'native-ui.xml').write_text(xml)
    return list(ET.fromstring(xml).iter('node'))


def dismiss_tips():
    for attempt in range(4):
        target=next((n for n in ui_tree() if n.get('package')=='com.android.systemui' and n.get('text')=='Got it' and n.get('clickable')=='true'),None)
        if target is None:return
        x,y,x2,y2=map(int,re.findall(r'\d+',target.get('bounds')))
        adb('shell','input','tap',str((x+x2)//2),str((y+y2)//2))
        time.sleep(.5)
    raise AssertionError('OS tips still cover the app')


def tap(point):
    nodes=[n for n in ui_tree() if n.get('package')==PACKAGE]
    surfaces=[n for n in nodes if 'SurfaceView' in n.get('class','') or 'RenderView' in n.get('class','')]
    if not surfaces:surfaces=[n for n in nodes if n.get('resource-id')=='android:id/content']
    assert surfaces, 'Need the live Android app surface bounds'
    x,y,_,_=map(int,re.findall(r'\d+',surfaces[0].get('bounds')))
    # Tablet letterboxing offsets the Godot surface within the display.
    adb('shell','input','tap',str(round(point[0]+x)),str(round(point[1]+y)))


def shot(name):
    s=state()
    (OUT/(name+'.json')).write_text(json.dumps(s,indent=2))
    (OUT/(name+'.png')).write_bytes(adb('exec-out','screencap','-p'))
    return s


pid=int(adb('shell','pidof','-s',PACKAGE).strip())
try:
    s=until(lambda s:s['process_id']==pid and s['joined'])
    dismiss_tips()
    time.sleep(2)
    s=shot('reclaimed-ground')
    assert not s['farm_pond_mesh'] and not s['fishing_action']
    assert s['walkable'] and s['cultivable'] and not s['work_mode']
    before=s['position']
    tap(s['target'])
    until(lambda s:s['position']!=before)
    until(lambda s:not s['moving'])
    shot('walked-into-former-pond')
    x,y,w,h=state()['mode_button']
    tap([x+w/2,y+h/2])
    until(lambda s:s['work_mode'])
    tap(state()['target'])
    s=until(lambda s:'8,33' in s['cells'] and s['version']>0)
    assert s['cells']['8,33']['state'] in ['tilled','sown','growing']
    shot('server-confirmed-farming')
    (OUT/'validation.json').write_text(json.dumps({'passed':True,'inputs':3,'walked_into_former_pond':True,
        'server_confirmed_cell':s['cells']['8,33'],'server_version':s['version'],'farm_fishing_removed':True,
        'isolated_account':True,'serial':SERIAL},indent=2))
    print('FARM_POND_REMOVAL_ANDROID_PASSED',s['version'],flush=True)
finally:
    (OUT/'logcat.txt').write_bytes(adb('logcat','-d','--pid',str(pid)))
