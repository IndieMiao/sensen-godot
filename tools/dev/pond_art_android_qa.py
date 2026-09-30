#!/usr/bin/env python3
"""Run inside tools/android/run_test.sh; only the supplied art package/device.

Captures runtime frames and a screenrecord. No game server, account or catches.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

SERIAL = os.environ['JOURNEY_SERIAL']
PACKAGE = os.environ['JOURNEY_PACKAGE']
assert PACKAGE in {'com.sensen.pondart.rapidharbor', 'com.sensen.pondart.calmcloud'}, 'Use the isolated pond art app'
OUT = Path(sys.argv[1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)


def adb(*args, data=None, check=True):
    return subprocess.run([os.environ.get('ADB', 'adb'), '-s', SERIAL, *args], input=data, capture_output=True, check=check).stdout


def read(name):
    return adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/' + name, check=False)


def wait_json(name, predicate, seconds=90):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            value = json.loads(read(name))
            if predicate(value):
                return value
        except (ValueError, TypeError, KeyError):
            pass
        time.sleep(.5)
    raise TimeoutError(name)


def capture(shape, shot, motion=False):
    request = uuid.uuid4().hex
    payload = {'shape': shape, 'shot': shot, 'motion': motion, 'time': 12, 'request_id': request}
    adb('shell', 'run-as', PACKAGE, 'sh', '-c', '"cat > files/art-command.json"', data=json.dumps(payload).encode())
    stem = shape + '-' + shot
    report = wait_json('pond-art/' + stem + '.json', lambda r: r['request_id'] == request)
    assert report['network_booted'] is False
    assert report['rendering_method'] == 'mobile'
    assert report['shadow_size'] == 2048 and report['shadow_filter'] == 2
    saved_stem = stem + '-motion' if motion else stem
    (OUT / (saved_stem + '.json')).write_text(json.dumps(report, indent=2))
    (OUT / (saved_stem + '.png')).write_bytes(read('pond-art/' + stem + '.png'))
    print('CAPTURE', stem, report['size'], report['rendering_driver'], flush=True)
    return report


def dismiss_system_tips():
    # Fresh AVDs show OS onboarding over an otherwise correct Godot render.
    # Derive each acknowledgement from the current accessibility tree.
    for attempt in range(4):
        raw = adb('exec-out', 'uiautomator', 'dump', '/dev/tty').decode()
        xml = raw[raw.find('<?xml'):raw.rfind('</hierarchy>') + len('</hierarchy>')]
        (OUT / f'system-ui-{attempt}.xml').write_text(xml)
        tree = ET.fromstring(xml)
        buttons = [n for n in tree.iter('node')
                   if n.get('package', '').startswith('com.android.')
                   and n.get('text') == 'Got it' and n.get('clickable') == 'true']
        if not buttons:
            return
        b = list(map(int, re.findall(r'\d+', buttons[0].get('bounds'))))
        adb('shell', 'input', 'tap', str((b[0]+b[2])//2), str((b[1]+b[3])//2))
        time.sleep(.5)
    raise AssertionError('System onboarding still covers the art viewer')


original_size = adb('shell', 'wm', 'size').decode()
try:
    wait_json('pond-art/gourd-hero.json', lambda r: not r['network_booted'])
    if '--record-only' not in sys.argv:
        for shape, shot in [('gourd','hero'), ('gourd','reference'), ('gourd','detail'), ('gourd','bank'), ('gourd','tree'), ('crescent','hero'), ('meander','hero')]:
            capture(shape, shot)
        adb('shell', 'wm', 'size', '390x844')
        capture('gourd', 'portrait')
        adb('shell', 'wm', 'size', 'reset')
    motion = capture('gourd', 'reference', True)
    dismiss_system_tips()
    performance = wait_json('pond-art/performance.json', lambda r: r['request_id'] == motion['request_id'])
    (OUT / 'performance.json').write_text(json.dumps(performance, indent=2))
    print('PERFORMANCE', [s['fps'] for s in performance['samples']], flush=True)
    # Rotation / size changes can trigger Android education after the first
    # check. Inspect again immediately before recording, using fresh UI bounds.
    dismiss_system_tips()
    video = '/sdcard/Download/gensen-pond-art.mp4'
    (OUT / 'before-record.png').write_bytes(adb('exec-out', 'screencap', '-p'))
    adb('shell', 'screenrecord', '--size', '1280x800', '--bit-rate', '8000000', '--time-limit', '12', video)
    adb('pull', video, str(OUT / 'water-motion-android.mp4'))
    (OUT / 'screencap.png').write_bytes(adb('exec-out', 'screencap', '-p'))
    adb('shell', 'rm', video)
finally:
    if 'Override size:' in original_size:
        adb('shell', 'wm', 'size', original_size.split('Override size:')[1].strip())
    else:
        adb('shell', 'wm', 'size', 'reset')
    (OUT / 'logcat.txt').write_bytes(adb('logcat', '-d', '-s', 'godot'))
