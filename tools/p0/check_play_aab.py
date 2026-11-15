#!/usr/bin/env python3
"""Read back a Play AAB. Built-in Python + JDK + locally installed bundletool; no network or credentials in reports."""
import base64
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import xml.etree.ElementTree as ET
import zipfile

PACKAGE = 'app.gensen.maps'
UPLOAD_CERT = '0a734126e2754b12c4e10bbe5c7837f45c2b935e3819b50a55b81217489f0492'
ANDROID = '{http://schemas.android.com/apk/res/android}'
ALLOWED_PERMISSIONS = {
    'android.permission.INTERNET', 'android.permission.VIBRATE', 'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.RECORD_AUDIO', 'android.permission.MODIFY_AUDIO_SETTINGS', 'android.permission.BLUETOOTH_CONNECT',
    'android.permission.POST_NOTIFICATIONS', 'android.permission.ACCESS_WIFI_STATE', 'android.permission.BLUETOOTH',
    PACKAGE + '.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
}
REQUIRED_PERMISSIONS = {'android.permission.INTERNET', 'android.permission.RECORD_AUDIO', 'android.permission.POST_NOTIFICATIONS'}
AD_ID = 'com.google.android.gms.permission.AD_ID'
NATIVE = ['base/lib/arm64-v8a/libgodot_android.so', 'base/lib/arm64-v8a/libmapbox-maps.so',
          'base/lib/arm64-v8a/libmapbox-common.so', 'base/lib/arm64-v8a/liblkjingle_peerconnection_so.so']
PLUGINS = {'org.godotengine.plugin.v2.' + n for n in ('GodotMap', 'GodotVoice', 'GodotWebView', 'GodotNotify', 'GodotGoogleSignIn')}
ASSET_ROOTS = ('base/assets/', 'assetPackInstallTime/assets/')

class CheckError(RuntimeError):
    pass

def require(condition, message):
    if not condition:
        raise CheckError(message)

def sha256(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def elf_load_alignment(data):
    """All PT_LOAD segments, not merely the largest alignment; reject malformed/truncated ELF too."""
    require(len(data) >= 52 and data[:4] == b'\x7fELF' and data[4] in (1, 2) and data[5] in (1, 2), 'invalid ELF header')
    endian = '<' if data[5] == 1 else '>'
    is64 = data[4] == 2
    try:
        offset = struct.unpack_from(endian + ('Q' if is64 else 'I'), data, 32 if is64 else 28)[0]
        size, count = struct.unpack_from(endian + 'HH', data, 54 if is64 else 42)
        require(size >= (56 if is64 else 32) and count > 0 and offset + size * count <= len(data), 'invalid ELF program headers')
        aligns = []
        for i in range(count):
            p = offset + i * size
            if struct.unpack_from(endian + 'I', data, p)[0] != 1:
                continue
            if is64:
                file_offset, address, _, file_size, _, alignment = struct.unpack_from(endian + 'QQQQQQ', data, p + 8)
            else:
                file_offset, address, _, file_size, _, _, alignment = struct.unpack_from(endian + 'IIIIIII', data, p + 4)
            require(file_offset + file_size <= len(data), 'ELF load segment exceeds file')
            require(alignment >= 16384 and alignment & (alignment - 1) == 0, 'ELF PT_LOAD alignment is below 16 KB or invalid')
            require((address - file_offset) % 16384 == 0, 'ELF PT_LOAD offset/address are not 16 KB congruent')
            aligns.append(alignment)
        require(bool(aligns), 'ELF has no PT_LOAD segment')
        return aligns
    except struct.error as e:
        raise CheckError('truncated ELF structure') from e

def manifest_facts(xml, code, name):
    try:
        root = ET.fromstring(xml)
        app = root.find('application')
        sdk = root.find('uses-sdk')
        require(root.tag == 'manifest' and app is not None and sdk is not None, 'missing Android manifest structure')
        require(root.get('package') == PACKAGE, 'unexpected package name')
        require(root.get(ANDROID + 'versionCode') == str(code) and root.get(ANDROID + 'versionName') == name, 'manifest version mismatch')
        require(app.get(ANDROID + 'debuggable', 'false') == 'false', 'debuggable Play bundle')
        require(ANDROID + 'networkSecurityConfig' not in app.attrib, 'development network security override')
        require(int(sdk.get(ANDROID + 'targetSdkVersion', '0')) >= 35, 'target SDK below Play baseline')
        permissions = {n.get(ANDROID + 'name') for n in root if n.tag.startswith('uses-permission')}
        require(AD_ID not in permissions, 'advertising ID permission present')
        unknown = permissions - ALLOWED_PERMISSIONS
        require(not unknown, 'unexpected permissions: ' + ', '.join(sorted(str(x) for x in unknown)))
        require(REQUIRED_PERMISSIONS <= permissions, 'required game permissions missing')
        names = {n.get(ANDROID + 'name', '') for n in app.iter()}
        require(not any('ScreenCaptureService' in n for n in names), 'screen-capture service present')
        require(PLUGINS <= names, 'required native plugin registration missing')
        return {'package': PACKAGE, 'version_code': code, 'version_name': name, 'permissions_ok': True,
                'permissions': sorted(permissions), 'ad_id_absent': True, 'debuggable': False,
                'target_sdk': int(sdk.get(ANDROID + 'targetSdkVersion')), 'native_plugins_ok': True}
    except (ET.ParseError, ValueError) as e:
        raise CheckError('invalid Android manifest') from e

def bundle_config_facts(config):
    libraries = config.get('optimizations', {}).get('uncompressNativeLibraries', {})
    require(libraries.get('enabled') is True and libraries.get('alignment') == 'PAGE_ALIGNMENT_16K',
            'AAB must request uncompressed native libraries with PAGE_ALIGNMENT_16K')
    return {'bundle_16kb_ok': True, 'native_page_alignment': 'PAGE_ALIGNMENT_16K'}

def capture(argv, timeout=120):
    result = subprocess.run(argv, capture_output=True, timeout=timeout)
    # Never echo tool output: manifest metadata and verifier diagnostics may contain private input.
    require(result.returncode == 0, Path(argv[0]).name + ' verification command failed')
    return result.stdout.decode('utf-8', errors='replace')

def signing_facts(aab, java_home, expected_cert):
    result = capture([str(java_home / 'bin/jarsigner'), '-J-Duser.language=en', '-verify', str(aab)])
    require('jar verified.' in result and 'jar is unsigned' not in result.lower() and 'unsigned entries' not in result.lower(),
            'AAB JAR signature is missing, invalid, or does not cover every entry')
    pem = capture([str(java_home / 'bin/keytool'), '-J-Duser.language=en', '-printcert', '-rfc', '-jarfile', str(aab)])
    certificates = re.findall(r'-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----', pem, re.S)
    require(bool(certificates), 'AAB signer certificate missing')
    digests = {hashlib.sha256(base64.b64decode(c)).hexdigest() for c in certificates}
    require(digests == {expected_cert}, 'AAB is not signed by the expected Play upload certificate')
    return {'signature_ok': True, 'signer_sha256': expected_cert}

def asset_entry(entries, relative, required=True):
    found = [prefix + relative for prefix in ASSET_ROOTS if prefix + relative in entries]
    require(len(found) <= 1 and (found or not required), 'required asset missing or duplicated across modules: ' + relative)
    return found[0] if found else None

def check_archive(aab, server, key, code, name):
    with zipfile.ZipFile(aab) as z:
        infos = z.infolist()
        entries = {i.filename for i in infos}
        require(len(entries) == len(infos), 'duplicate ZIP entries')
        require(z.testzip() is None, 'ZIP CRC failure')
        require(set(NATIVE) <= entries, 'required native library missing')
        asset_entry(entries, 'mapbox_token.txt')
        require(not any('/tools/qa/' in n or '/accounts_rehearsal/' in n or 'qa_entry' in n for n in entries), 'QA entry resource in Play bundle')
        config = json.loads(z.read(asset_entry(entries, 'assets/p0/demo_server.json')))
        require(config.get('url') == server and config.get('key') == key and config.get('version') == code and config.get('name') == name,
                'baked endpoint/key/version mismatch')
        version_entry = asset_entry(entries, 'assets/p0/legal/versions.json', required=False)
        versions = json.loads(z.read(version_entry)) if version_entry else None
        if versions is not None:
            require(set(versions) == {'terms', 'privacy'} and all(isinstance(x, str) and x for x in versions.values()), 'invalid account legal versions')
        licenses = json.loads(z.read(asset_entry(entries, 'assets/p0/legal/licenses.json')))
        for group in licenses.get('groups', []):
            for row in group.get('rows', []):
                text = row.get('text', '')
                if isinstance(text, str) and text.startswith('res://'):
                    asset_entry(entries, text[6:])
        libraries = []
        for info in sorted(infos, key=lambda i: i.filename):
            if not info.filename.endswith('.so'):
                continue
            require(info.filename.startswith('base/lib/arm64-v8a/'), 'unexpected native ABI/module')
            require(info.file_size <= 512 * 1024 * 1024, 'native library too large to inspect')
            native = z.read(info)
            require(len(native) >= 20 and native[4:6] == b'\x02\x01' and struct.unpack_from('<H', native, 18)[0] == 183,
                    'native library is not little-endian AArch64 ELF64')
            aligns = elf_load_alignment(native)
            libraries.append({'path': info.filename, 'load_segments': len(aligns), 'min_alignment': min(aligns)})
        require(bool(libraries), 'no native libraries inspected')
    return {'zip_crc_ok': True, 'native_ok': True, 'elf_16kb_ok': True, 'libraries': libraries,
            'server': server, 'key_matches': True, 'key_present': bool(key), 'version_baked': code,
            'legal_ok': True, 'legal_versions': versions, 'account_legal_versions_present': version_entry is not None}

def verify(aab, *, server, key, code, name, bundletool, java_home, expected_cert=UPLOAD_CERT):
    aab, bundletool, java_home = Path(aab), Path(bundletool), Path(java_home)
    require(aab.is_file() and bundletool.is_file(), 'AAB or bundletool is missing')
    java = str(java_home / 'bin/java')
    capture([java, '-jar', str(bundletool), 'validate', '--bundle', str(aab)])
    xml = capture([java, '-jar', str(bundletool), 'dump', 'manifest', '--bundle', str(aab), '--module', 'base'])
    cfg = json.loads(capture([java, '-jar', str(bundletool), 'dump', 'config', '--bundle', str(aab)]))
    with zipfile.ZipFile(aab) as z:
        modules = {n.split('/')[0] for n in z.namelist() if re.fullmatch(r'[^/]+/manifest/AndroidManifest.xml', n)}
    require(modules in ({'base'}, {'base', 'assetPackInstallTime'}), 'unreviewed AAB module; its manifest needs an explicit audit')
    if 'assetPackInstallTime' in modules:
        pack_xml = capture([java, '-jar', str(bundletool), 'dump', 'manifest', '--bundle', str(aab), '--module', 'assetPackInstallTime'])
        pack = ET.fromstring(pack_xml)
        require(pack.find('.//{http://schemas.android.com/apk/distribution}install-time') is not None,
                'game asset pack must be delivered at install time')
    return {'aab': str(aab), 'bytes': aab.stat().st_size, 'sha256': sha256(aab), 'bundletool_validate_ok': True,
            'checker_sha256': sha256(Path(__file__)), 'bundletool_sha256': sha256(bundletool),
            'modules': sorted(modules),
            **manifest_facts(xml, code, name), **bundle_config_facts(cfg),
            **signing_facts(aab, java_home, expected_cert), **check_archive(aab, server, key, code, name),
            'upload_performed': False}
