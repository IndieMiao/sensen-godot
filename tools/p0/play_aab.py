#!/usr/bin/env python3
"""Local Play build/verification. No upload client, service-account access, deployment or device installation."""
import argparse
from contextlib import contextmanager
from datetime import datetime
import fnmatch
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
import zipfile

from check_play_aab import CheckError, UPLOAD_CERT, verify, sha256, production_clean_source

ROOT = Path(__file__).resolve().parents[2]
KEEP_ADB = ROOT / 'tools/p0/godot_keep_adb.sh'
FIRST_PLAY_CODE = 2026111401
PRESET = 'Android Play'

def require(ok, message):
    if not ok:
        raise CheckError(message)

def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write('\n')

def replace_json(path, data):
    temporary = path.with_name(path.name + '.tmp')
    write_json(temporary, data)
    os.replace(temporary, path)

def version_code(value):
    require(re.fullmatch(r'20\d{8}', value or '') is not None, '--code must be YYYYMMDDNN')
    try:
        datetime.strptime(value[:8], '%Y%m%d')
    except ValueError as e:
        raise CheckError('invalid date in versionCode') from e
    require(value[-2:] != '00', 'versionCode NN=00 is reserved for dry runs')
    require(int(value) <= 2100000000, 'versionCode exceeds Play limit')
    return int(value)

def validated_server(value):
    url = urlsplit(value)
    require(url.scheme == 'https' and bool(url.hostname) and url.username is None and url.password is None
            and not url.query and not url.fragment and url.path.rstrip('/').endswith('/v1'),
            '--server must be an HTTPS /v1 endpoint without credentials, query or fragment')
    return value.rstrip('/')

def play_segment(text):
    blocks = re.split(r'(?m)(?=^\[preset\.\d+\]$)', text)
    found = [block for block in blocks if re.search(r'^name="Android Play"$', block, re.M)]
    require(len(found) == 1, 'exactly one Android Play preset is required')
    return found[0]

def configured_presets(text, code, name):
    segment = play_segment(text)
    for required in ['custom_features="p0,store"', 'gradle_build/export_format=1', 'gradle_build/use_gradle_build=true',
                     'gradle_build/compress_native_libraries=false', 'package/unique_name="app.gensen.maps"',
                     'package/signed=true', 'architectures/arm64-v8a=true']:
        require(required in segment.splitlines(), 'Android Play preset is missing: ' + required)
    for abi in ('armeabi-v7a', 'x86', 'x86_64'):
        require('architectures/' + abi + '=false' in segment.splitlines(), 'Play preset must use the reviewed arm64 ABI')
    changed, n = re.subn(r'^version/code=\d+$', 'version/code=' + str(code), segment, flags=re.M)
    require(n == 1, 'Play version/code missing or duplicated')
    changed, n = re.subn(r'^version/name="[^"\n]*"$', 'version/name="' + name + '"', changed, flags=re.M)
    require(n == 1, 'Play version/name missing or duplicated')
    return text.replace(segment, changed, 1)

@contextmanager
def temporary_export_files(root, server, key, code, name):
    """Restore exact original bytes and modes, including a pre-existing demo_server.json, on every exit."""
    paths = [root / 'export_presets.cfg', root / 'assets/p0/demo_server.json']
    originals = {}
    for path in paths:
        require(not path.is_symlink(), 'refusing to modify symlinked export input')
        originals[path] = (path.read_bytes(), stat.S_IMODE(path.stat().st_mode)) if path.exists() else None
    try:
        paths[0].write_text(configured_presets(originals[paths[0]][0].decode(), code, name))
        fd = os.open(paths[1], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as f:
            json.dump({'url': server, 'key': key, 'version': code, 'name': name}, f)
        paths[1].chmod(0o600)
        yield
    finally:
        for path, original in originals.items():
            if original is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(original[0])
                path.chmod(original[1])

def native_inputs(root):
    build = root / 'android/build'
    require((root / 'mapbox_token.txt').is_file() and (root / 'mapbox_token.txt').stat().st_size > 0, 'mapbox_token.txt missing')
    require((build / 'build.gradle').is_file(), 'run tools/android/setup_android_build.sh before export')
    pairs = [('tools/android/overlay/GodotMapPlugin.kt', 'map/GodotMapPlugin.kt'),
             ('native/voice/android/GodotVoicePlugin.kt', 'voice/GodotVoicePlugin.kt'),
             ('native/webview/android/GodotWebViewPlugin.kt', 'webview/GodotWebViewPlugin.kt'),
             ('native/permission/android/PermissionActivity.kt', 'permission/PermissionActivity.kt'),
             ('native/googleauth/android/GodotGoogleSignInPlugin.kt', 'googleauth/GodotGoogleSignInPlugin.kt'),
             ('native/notify/android/GodotNotifyPlugin.kt', 'notify/GodotNotifyPlugin.kt')]
    for source, dest in pairs:
        copied = build / 'src/main/java/com/sensen' / dest
        require(copied.is_file() and copied.read_bytes() == (root / source).read_bytes(),
                'stale/missing Android plugin: ' + dest + '; refresh the template and four prepare_*_plugin.py scripts')
    for icon in (root / 'native/notify/android/res').glob('*/ic_notify.png'):
        copied = build / 'res' / icon.relative_to(root / 'native/notify/android/res')
        require(copied.is_file() and copied.read_bytes() == icon.read_bytes(), 'stale/missing notification icon')
    gradle = (build / 'build.gradle').read_text()
    for dependency in re.findall(r'com\.mapbox[^\s"\x27]+', (root / 'tools/android/overlay/build.gradle').read_text()):
        require(dependency in gradle, 'stale Mapbox dependency; refresh Android template')
    require('io.livekit:livekit-android' in gradle and 'androidx.credentials:credentials' in gradle, 'voice/Google Gradle dependencies missing')
    manifest = (build / 'src/main/AndroidManifest.xml').read_text()
    for name in ('GodotMap', 'GodotVoice', 'GodotWebView', 'GodotNotify', 'GodotGoogleSignIn'):
        require('org.godotengine.plugin.v2.' + name in manifest, 'native manifest registration missing: ' + name)
    require('PermissionActivity' in manifest and 'NotifyReceiver' in manifest, 'native permission/notification component missing')
    require('networkSecurityConfig' not in manifest, 'development cleartext network override present')

def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()

def source_identity():
    require(not git('status', '--porcelain', '--untracked-files=no'), 'commit or isolate tracked changes before a Play build')
    segment = play_segment((ROOT / 'export_presets.cfg').read_text())
    excludes = re.search(r'^exclude_filter="([^"]*)"$', segment, re.M)
    require(excludes is not None, 'Play exclude_filter missing')
    patterns = [p.strip() for p in excludes.group(1).split(',') if p.strip()]
    untracked = git('ls-files', '--others', '--exclude-standard').splitlines()
    unexpected = [p for p in untracked if not p.endswith('.uid') and not any(fnmatch.fnmatch(p, pattern) for pattern in patterns)]
    require(not unexpected, 'untracked export inputs present; isolate them before building')
    production_clean_source(ROOT)
    return git('rev-parse', 'HEAD')

def no_phone_and_free_adb(port):
    command = ['system_profiler', 'SPUSBDataType', '-json'] if sys.platform == 'darwin' else ['lsusb']
    result = subprocess.run(command, capture_output=True, timeout=30)
    require(result.returncode == 0, 'USB preflight failed; do not start Godot')
    require(re.search(rb'vivo|V2509|android', result.stdout, re.I) is None, 'USB Android phone detected; do not start Godot')
    for family, address in [(socket.AF_INET, '127.0.0.1'), (socket.AF_INET6, '::1')]:
        sock = socket.socket(family)
        try:
            sock.bind((address, port))
        except OSError as e:
            raise CheckError('private ADB port unavailable; do not stop another process') from e
        finally:
            sock.close()

def godot_keep_adb(godot, directory, java_home):
    """A copy of Godot whose own editor settings keep the adb server up after the export (godot_keep_adb.sh)."""
    r = subprocess.run(['bash', '-c', 'set -euo pipefail; source "$0"; p0_godot_keep_adb "$1" "$2"; printf %s "$P0_GODOT"',
                        str(KEEP_ADB), godot, str(directory)], env=dict(os.environ, JAVA_HOME=str(java_home)),
                       stdout=subprocess.PIPE, text=True)
    require(r.returncode == 0 and bool(r.stdout), 'Godot copy unavailable; see the message above')
    return r.stdout

def run_logged(argv, log, env, secrets_to_hide):
    """Only own recorded process group is stopped on interruption; no name-based process kills."""
    process = None
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('x', encoding='utf-8') as out:
        log.chmod(0o600)
        try:
            process = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, errors='replace', start_new_session=True)
            with (log.parent / 'processes.jsonl').open('a') as records:
                records.write(json.dumps({'stage': log.stem, 'pid': process.pid, 'process_group': process.pid}) + '\n')
            for line in process.stdout:
                for secret in secrets_to_hide:
                    if secret:
                        line = line.replace(secret, '[REDACTED]')
                out.write(line)
            require(process.wait() == 0, log.stem + ' failed; see its redacted log')
        finally:
            if process is not None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                finally:
                    if process.stdout is not None:
                        process.stdout.close()

def upload_password():
    password = os.environ.get('GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD', '')
    if not password:
        require(sys.platform == 'darwin', 'set GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD on non-macOS build hosts')
        r = subprocess.run(['security', 'find-generic-password', '-s', 'sensen.android.play-upload-keystore',
                            '-w', str(Path.home() / 'Library/Keychains/login.keychain-db')], capture_output=True)
        require(r.returncode == 0, 'Play upload password unavailable in login keychain')
        password = r.stdout.decode().rstrip('\n')
    require(bool(password), 'empty upload keystore password')
    return password

def read_access_key(path):
    key = os.environ.get('P0_KEY')
    if key is None:
        require(path.is_file(), 'set P0_KEY or provide --key-file for the baked game endpoint')
        key = path.read_text().strip()
    require(bool(key) and '\n' not in key and '\r' not in key, 'empty or invalid game access key')
    return key

def copy_verified(source, destination, expected_sha):
    """A partial/interrupted copy never appears under the uploadable .aab filename."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.' + destination.name + '-', suffix='.part', dir=destination.parent)
    temporary = Path(name)
    try:
        with source.open('rb') as src, os.fdopen(fd, 'wb') as dst:
            shutil.copyfileobj(src, dst)
        require(sha256(temporary) == expected_sha, 'Downloads copy checksum mismatch')
        os.link(temporary, destination)  # Exclusive and atomic, on the destination filesystem.
    finally:
        temporary.unlink(missing_ok=True)

def check_next_code(history, code):
    require(isinstance(history, list) and all(isinstance(x, dict) and type(x.get('version_code')) is int for x in history), 'invalid local version ledger')
    require(code > max([FIRST_PLAY_CODE] + [x['version_code'] for x in history]), 'versionCode must increase beyond r1 and all locally reserved Play builds')

class SafeParser(argparse.ArgumentParser):
    def error(self, _message):
        self.print_usage(sys.stderr)
        self.exit(2, 'Invalid arguments; use --help. Passwords and access keys belong in environment/file inputs.\n')

def parser():
    p = SafeParser(description=__doc__, epilog='Before export: reserve the build window; refresh Android template/plugins. Play uploads remain manual.')
    p.add_argument('--server', required=True)
    p.add_argument('--code', required=True, help='YYYYMMDDNN; a new build must exceed r1 and all locally reserved codes')
    p.add_argument('--name', required=True, help='versionName, e.g. 0.3.11')
    p.add_argument('--revision', default='r2')
    p.add_argument('--bundletool', type=Path, default=os.environ.get('BUNDLETOOL_JAR'), help='locally installed bundletool JAR')
    p.add_argument('--java-home', type=Path, default=os.environ.get('JAVA_HOME', '/Applications/Android Studio.app/Contents/jbr/Contents/Home' if sys.platform == 'darwin' else ''))
    p.add_argument('--key-file', type=Path, default=ROOT / 'output/p0-deploy/key')
    p.add_argument('--keystore', type=Path, default=Path.home() / '.config/sensen/gensen-play-upload.keystore')
    p.add_argument('--expected-signer', default=UPLOAD_CERT, help='public SHA-256 of the approved upload certificate')
    p.add_argument('--download-dir', type=Path, default=Path.home() / 'Downloads')
    p.add_argument('--adb-port', type=int, default=5071)
    p.add_argument('--check-only', type=Path, help='verify this existing AAB without export, signing-key access, copying or code reservation')
    p.add_argument('--report', type=Path, help='verification JSON destination (must not exist)')
    return p

def main(argv=None):
    a = parser().parse_args(argv)
    code = version_code(a.code)
    server = validated_server(a.server)
    require(re.fullmatch(r'\d+\.\d+\.\d+', a.name) is not None, '--name must be x.y.z')
    require(re.fullmatch(r'r[2-9]\d*|r1\d+', a.revision) is not None, '--revision starts at r2; original r1 is preserved')
    cert = a.expected_signer.replace(':', '').lower()
    require(re.fullmatch('[a-f0-9]{64}', cert) is not None, 'invalid expected public signer fingerprint')
    require(a.bundletool is not None and a.bundletool.is_file(), 'set BUNDLETOOL_JAR or --bundletool; no automatic download')
    require((a.java_home / 'bin/java').is_file(), 'JDK unavailable; set --java-home or JAVA_HOME')
    key = read_access_key(a.key_file)
    if a.check_only:
        report = verify(a.check_only.resolve(), server=server, key=key, code=code, name=a.name,
                        bundletool=a.bundletool.resolve(), java_home=a.java_home.resolve(), expected_cert=cert)
        report.update(mode='existing-aab-check', source_commit=None, build_performed=False)
        destination = a.report or ROOT / 'output/p0-play' / ('check-' + report['sha256'][:12] + '.json')
        write_json(destination, report)
        print(json.dumps({'verified': True, 'sha256': report['sha256'], 'bytes': report['bytes'], 'report': str(destination), 'upload_performed': False}))
        return
    require(code > FIRST_PLAY_CODE, 'r2 versionCode must exceed 2026111401')
    require(1024 <= a.adb_port <= 65535 and a.adb_port != 5037, 'use a private ADB port, never 5037')
    require(not os.environ.get('P0_DEV_CLEARTEXT'), 'development cleartext override is forbidden for Play')
    source = source_identity()
    native_inputs(ROOT)
    require(a.keystore.is_file() and stat.S_IMODE(a.keystore.stat().st_mode) & 0o077 == 0, 'upload keystore missing or not private (0600)')
    godot = shutil.which(os.environ.get('GODOT_BIN', 'godot'))
    require(godot is not None, 'Godot unavailable; set GODOT_BIN')
    sdk = Path(os.environ.get('ANDROID_HOME', os.environ.get('ANDROID_SDK_ROOT', str(Path.home() / ('Library/Android/sdk' if sys.platform == 'darwin' else 'Android/Sdk')))))
    adb = sdk / 'platform-tools/adb'
    require(adb.is_file(), 'Android SDK adb unavailable')
    no_phone_and_free_adb(a.adb_port)
    work = ROOT / 'output/p0-play'
    work.mkdir(parents=True, exist_ok=True)
    (ROOT / 'output/.gdignore').touch(exist_ok=True)
    lock = work / '.build-lock'
    try:
        lock.mkdir(mode=0o700)
    except FileExistsError as e:
        raise CheckError('another Play build or stale .build-lock exists; verify its recorded PID before removing') from e
    started_godot = False
    copy_dir = None
    try:
        write_json(lock / 'owner.json', {'pid': os.getpid(), 'source_commit': source})
        copy_dir = Path(tempfile.mkdtemp(prefix='p0play_godot.'))
        godot = godot_keep_adb(godot, copy_dir, a.java_home.resolve())
        ledger = work / 'versions.json'
        history = json.loads(ledger.read_text()) if ledger.exists() else []
        check_next_code(history, code)
        filename = f'gensen-{a.name}-play-{a.revision}.aab'
        folder = work / f'{a.name}-{a.revision}-{code}'
        require(not folder.exists(), 'build output already exists')
        download = a.download_dir / filename
        require(not download.exists(), 'Downloads destination already exists; use a new revision, never overwrite r1 or a prior build')
        folder.mkdir(mode=0o700)
        out = folder / filename
        report_path = a.report or folder / 'build.json'
        require(not report_path.exists(), 'report destination already exists')
        password = upload_password()
        map_token = (ROOT / 'mapbox_token.txt').read_text().strip()
        env = dict(os.environ)
        env.update(ANDROID_HOME=str(sdk), JAVA_HOME=str(a.java_home), ADB_SERVER_SOCKET=f'tcp:localhost:{a.adb_port}',
                   ANDROID_ADB_SERVER_PORT=str(a.adb_port), ADB_LOCAL_TRANSPORT_MAX_PORT='5553',
                   GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(a.keystore.resolve()), GODOT_ANDROID_KEYSTORE_RELEASE_USER='upload',
                   GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=password,
                   GRADLE_OPTS=env.get('GRADLE_OPTS', '') + ' -Dorg.gradle.daemon=false')
        record = {'version_code': code, 'version_name': a.name, 'revision': a.revision, 'source_commit': source, 'status': 'reserved'}
        history.append(record)
        replace_json(ledger, history)  # Reserved even if export fails: every new attempt uses a higher code.
        try:
            with temporary_export_files(ROOT, server, key, code, a.name):
                started_godot = True
                run_logged([godot, '--headless', '--path', str(ROOT), '--import'], folder / 'import.log', env, [password, key, map_token])
                run_logged([godot, '--headless', '--path', str(ROOT), '--export-release', PRESET, str(out)], folder / 'export.log', env, [password, key, map_token])
            env.pop('GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD', None)
            report = verify(out, server=server, key=key, code=code, name=a.name,
                            bundletool=a.bundletool.resolve(), java_home=a.java_home.resolve(), expected_cert=cert)
            report.update(mode='local-play-build', source_commit=source, source_dirty=False, revision=a.revision,
                          build_performed=True, submission_prerequisites='accounts/q320 deployed + terms live + TERMS_LIVE merged; verify separately')
            write_json(report_path, report)
            copy_verified(out, download, report['sha256'])
            record.update(status='verified', sha256=report['sha256'])
            replace_json(ledger, history)
            print(json.dumps({'aab': str(download), 'bytes': report['bytes'], 'sha256': report['sha256'], 'version_code': code,
                              'report': str(report_path), 'upload_performed': False}))
        except BaseException:
            record['status'] = 'failed'
            replace_json(ledger, history)
            raise
    finally:
        try:
            if started_godot:
                subprocess.run([str(adb), '-P', str(a.adb_port), 'kill-server'], capture_output=True, timeout=10)
        finally:
            if copy_dir is not None:
                shutil.rmtree(copy_dir, ignore_errors=True)
            shutil.rmtree(lock)

if __name__ == '__main__':
    def interrupted(_signal, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    try:
        main()
    except (CheckError, OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as e:
        # Known check messages never contain private values. Other exception bodies may contain file contents.
        print(str(e) if isinstance(e, CheckError) else 'Play build/verification failed; inspect the local evidence.', file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print('Play build interrupted; temporary export inputs restored.', file=sys.stderr)
        sys.exit(130)
