"""Run through tools/android/run_test.sh; four real composition / bridge-colour button taps."""
from pathlib import Path
import os, subprocess, time, json, hashlib

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'output/far-backdrop-434/android'
OUT.mkdir(exist_ok=True)
PKG = 'com.sensen.farbackdrop434qa'
ADB = [os.environ['ADB'], '-s', os.environ['JOURNEY_SERIAL']]

def call(*args):
    return subprocess.check_output(ADB + list(map(str, args)), stderr=subprocess.DEVNULL)

def wait(combo, cool):
    end = time.monotonic() + 120
    while time.monotonic() < end:
        try:
            state = json.loads(call('shell', 'run-as', PKG, 'cat', 'files/far_state.json'))
            assert str(state['pid']) == call('shell', 'pidof', PKG).decode().strip()
            if state['combo'] == combo and state['cool'] == cool and state['kit'] == '434-v1':
                return state
        except (ValueError, AssertionError, subprocess.CalledProcessError):
            pass
        time.sleep(1)
    raise AssertionError('No fresh far backdrop state')

records = []
try:
    steps = [(0, False, 'urban', 'button_combo'),
             (1, False, 'quiet', 'button_combo'),
             (0, False, 'urban-restored', 'button_color'),
             (0, True, 'bridge-cool', 'button_color'),
             (0, False, 'bridge-restored', None)]
    for combo, cool, name, button in steps:
        state = wait(combo, cool)
        assert state['renderer'] == 'mobile'
        time.sleep(2)
        (OUT / (name + '.png')).write_bytes(call('exec-out', 'screencap', '-p'))
        (OUT / (name + '-viewport.png')).write_bytes(call(
            'exec-out', 'run-as', PKG, 'cat', f'files/far_{combo}_{str(cool).lower()}.png'))
        records.append(state)
        if button:
            call('shell', 'input', 'tap', *state[button])
    path = call('shell', 'pm', 'path', PKG).decode().strip().removeprefix('package:')
    call('pull', path, OUT / 'installed.apk')
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    apk = OUT.parent / 'far-backdrop-qa.apk'
    assert digest(apk) == digest(OUT / 'installed.apk')
    assert records[0]['draws'] == records[1]['draws'] == records[4]['draws']
    (OUT / 'smoke.json').write_text(json.dumps({
        'passed': True, 'states': records, 'apk_sha256': digest(apk),
        'installed_apk_readback_equal': True,
        'scope': 'API37 SwiftShader emulator / Mobile / 4 real taps; not physical GPU performance'
    }, indent=2) + '\n')
    print('FAR_BACKDROP_ANDROID_PASS', flush=True)
finally:
    call('shell', 'wm', 'size', '720x1280')
    call('shell', 'wm', 'density', 'reset')
