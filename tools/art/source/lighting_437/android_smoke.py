"""Three real taps switch presets and return to noon; verify the installed APK."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / os.environ.get('LIGHTING_REVIEW_OUT', 'output/lighting-437') / 'android'
OUT.mkdir(exist_ok=True)
PKG = 'com.sensen.lighting437qa'
ADB = [os.environ['ADB'], '-s', os.environ['JOURNEY_SERIAL']]


def call(*args):
    return subprocess.check_output(ADB + list(map(str, args)), stderr=subprocess.DEVNULL)


def wait(preset):
    end = time.monotonic() + 120
    while time.monotonic() < end:
        try:
            state = json.loads(call('shell', 'run-as', PKG, 'cat', 'files/lighting_state.json'))
            if (str(state['pid']) == call('shell', 'pidof', PKG).decode().strip()
                    and state['kit'] == '437-v12' and state['preset'] == preset):
                return state
        except (ValueError, subprocess.CalledProcessError):
            pass
        time.sleep(1)
    raise AssertionError('No fresh lighting state for ' + preset)


records = []
try:
    for index, preset in enumerate(['warm_noon', 'cool_morning', 'golden_dusk', 'warm_noon']):
        state = wait(preset)
        assert state['renderer'] == 'mobile'
        time.sleep(2)
        (OUT / (preset + '.png')).write_bytes(call('exec-out', 'screencap', '-p'))
        (OUT / (preset + '-viewport.png')).write_bytes(call(
            'exec-out', 'run-as', PKG, 'cat', 'files/lighting_' + preset + '.png'))
        records.append(state)
        if index < 3:
            call('shell', 'input', 'tap', *state['button_next'])
    path = call('shell', 'pm', 'path', PKG).decode().strip().removeprefix('package:')
    call('pull', path, OUT / 'installed.apk')
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    apk = OUT.parent / 'lighting-qa.apk'
    assert digest(apk) == digest(OUT / 'installed.apk')
    assert len({state['draws'] for state in records}) == 1
    for field in ['background', 'sea_far_color', 'bridge_color']:
        assert len({state[field] for state in records[:3]}) == 3, field
        assert records[0][field] == records[-1][field], field
    (OUT / 'smoke.json').write_text(json.dumps({
        'passed': True, 'states': records, 'apk_sha256': digest(apk),
        'installed_apk_readback_equal': True,
        'scope': 'API37 SwiftShader / Mobile; 3 real taps; not physical GPU timing.'
    }, indent=2) + '\n')
    print('LIGHTING_ANDROID_PASS', flush=True)
finally:
    call('shell', 'wm', 'size', '720x1280')
    call('shell', 'wm', 'density', 'reset')
