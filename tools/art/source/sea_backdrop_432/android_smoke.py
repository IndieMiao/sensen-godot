"""Run through tools/android/run_test.sh; four real preset / foam button taps."""
from pathlib import Path
import os, subprocess, time, json, hashlib

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / os.environ.get('SEA_REVIEW_OUTPUT', 'output/sea-backdrop-432') / 'android'
OUT.mkdir(exist_ok=True)
PKG = 'com.sensen.seabackdrop432qa'
ADB = [os.environ['ADB'], '-s', os.environ['JOURNEY_SERIAL']]

def call(*args):
    return subprocess.check_output(ADB + list(map(str, args)), stderr=subprocess.DEVNULL)

def wait(preset, foam):
    end = time.monotonic() + 120
    while time.monotonic() < end:
        try:
            state = json.loads(call('shell', 'run-as', PKG, 'cat', 'files/sea_state.json'))
            assert str(state['pid']) == call('shell', 'pidof', PKG).decode().strip()
            if state['preset'] == preset and state['foam'] == foam and state['kit'] == '432-v1.1':
                return state
        except (ValueError, AssertionError, subprocess.CalledProcessError):
            pass
        time.sleep(1)
    raise AssertionError('No fresh sea backdrop state')

records = []
try:
    steps = [('bay', True, 'bay', 'button_preset'),
             ('lake', True, 'lake', 'button_foam'),
             ('lake', False, 'lake-control', 'button_foam'),
             ('lake', True, 'lake-restored', 'button_preset'),
             ('bay', True, 'bay-restored', None)]
    for preset, foam, name, button in steps:
        state = wait(preset, foam)
        assert state['renderer'] == 'mobile'
        time.sleep(2)
        (OUT / (name + '.png')).write_bytes(call('exec-out', 'screencap', '-p'))
        (OUT / (name + '-viewport.png')).write_bytes(call(
            'exec-out', 'run-as', PKG, 'cat', f'files/sea_{preset}_{str(foam).lower()}.png'))
        records.append(state)
        if button:
            call('shell', 'input', 'tap', *state[button])
    path = call('shell', 'pm', 'path', PKG).decode().strip().removeprefix('package:')
    call('pull', path, OUT / 'installed.apk')
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    apk = OUT.parent / 'sea-backdrop-qa.apk'
    assert digest(apk) == digest(OUT / 'installed.apk')
    assert records[0]['draws'] == records[1]['draws'] == records[4]['draws']
    assert records[1]['draws'] > records[2]['draws']
    (OUT / 'smoke.json').write_text(json.dumps({
        'passed': True, 'states': records, 'apk_sha256': digest(apk),
        'installed_apk_readback_equal': True,
        'scope': 'API37 SwiftShader emulator / Mobile / 4 real taps; not physical GPU performance'
    }, indent=2) + '\n')
    print('SEA_BACKDROP_ANDROID_PASS', flush=True)
finally:
    call('shell', 'wm', 'size', '720x1280')
    call('shell', 'wm', 'density', 'reset')
