#!/usr/bin/env python3
"""Generate the worker's unsigned APK preset or read back a worker/service APK."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

from check_export_inputs import check_names
import dynamic_farm_export as farm


def require(condition, message):
    if not condition:
        raise ValueError(message)


def worker_preset(text, variant='android'):
    # Godot config values aren't INI strings (e.g. PackedStringArray, dictionaries).
    # Preserve their encoding; take only the named non-store preset and its options.
    matches = [b for b in re.split(r'(?m)(?=^\[preset\.\d+\]$)', text)
               if 'name="Android"' in b.splitlines()]
    require(len(matches) == 1, 'expected one Android preset')
    header, options = re.split(r'(?m)^\[preset\.\d+\.options\]$', matches[0])
    require('platform="Android"' in header.splitlines() and
            {'gradle_build/use_gradle_build=true', 'gradle_build/export_format=0',
             'gradle_build/gradle_build_directory=""', 'gradle_build/android_source_template=""',
             'custom_template/release=""'} <= set(options.splitlines()),
            'expected a Gradle APK preset')
    require(not re.search(r'(?mi)^keystore/', options), 'unexpected signing configuration in preset')

    def value(pattern):
        values = re.findall(pattern, options, re.M)
        require(len(values) == 1, 'missing or ambiguous APK identity')
        return values[0]

    if variant != 'android':
        header, options = farm.staged_preset(header, options, variant == 'dynamic-farm-internal')
    identity = dict(package=value(r'^package/unique_name="([a-zA-Z0-9_.]+)"$'),
                    version_code=value(r'^version/code=(\d+)$'), version_name=value(r'^version/name="([^"\n]+)"$'))
    options, count = re.subn(r'^package/signed=(?:true|false)$', 'package/signed=false', options, flags=re.M)
    require(count == 1, 'missing or ambiguous package/signed')
    header = re.sub(r'^\[preset\.\d+\]', '[preset.0]', header)
    header, count = re.subn(r'^runnable=(?:true|false)$', 'runnable=false', header, flags=re.M)
    require(count == 1, 'missing or ambiguous runnable flag')
    header = re.sub(r'^export_path=.*$', 'export_path=""', header, flags=re.M)
    return header + '[preset.0.options]' + options, identity


def checked_output(args):
    p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    require(p.returncode == 0, f'{Path(args[0]).name} failed')
    return p.stdout


def inspect_zip(apk, unsigned, variant='android'):
    with apk.open('rb') as f, zipfile.ZipFile(f) as z:
        names = z.namelist()
        check_names(names)  # Must precede any member I/O, including CRC verification.
        require(len(names) == len(set(names)), 'duplicate ZIP entries')
        required = {'AndroidManifest.xml', 'classes.dex', 'assets/project.binary', 'assets/mapbox_token.txt',
                    'lib/arm64-v8a/libgodot_android.so', 'lib/arm64-v8a/libmapbox-maps.so',
                    'lib/arm64-v8a/libmapbox-common.so', 'lib/arm64-v8a/liblkjingle_peerconnection_so.so'}
        if variant != 'android':
            required.update('assets/' + path for path in farm.RAW_FILES)
            for scene in ('dynamic_farm_map', 'dynamic_farm_host', 'dynamic_farm'):
                path = f'assets/scenes/dynamic_farm/{scene}.tscn'
                require(path in names or path + '.remap' in names, 'missing dynamic farm scene: ' + scene)
        require(required <= set(names), 'missing Android, Godot or plugin payload')
        if unsigned:
            require(not any(re.match(r'^META-INF/(?:[^/]+\.(?:SF|RSA|DSA|EC)|SIG-[^/]+)$', n, re.I)
                            for n in names), 'JAR signature metadata present')
            f.seek(z.start_dir - 16)
            require(f.read(16) != b'APK Sig Block 42', 'APK Signing Block present')
        require(z.testzip() is None, 'corrupt ZIP entry')
        return farm.exported_config(farm.project_settings(z.read('assets/project.binary')), variant)


def inspect(apk, identity, build_tools, signer=None, variant='android'):
    config = inspect_zip(apk, signer is None, variant)
    checked_output([build_tools / 'zipalign', '-c', '-P', '16', '4', apk])
    badging = checked_output([build_tools / 'aapt', 'dump', 'badging', apk])
    found = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
    require(found and found.groups() == (identity['package'], identity['version_code'], identity['version_name']),
            'manifest and export preset identity differ')
    if signer is not None:
        require(re.fullmatch(r'[0-9a-fA-F]{64}', signer), 'expected approved signer SHA-256')
        certs = checked_output([build_tools / 'apksigner', 'verify', '--verbose', '--print-certs', apk])
        digests = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})$', certs, re.M)
        require([d.lower() for d in digests] == [signer.lower()], 'unexpected APK signer')
    h = hashlib.sha256()
    with apk.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return dict(identity, bytes=apk.stat().st_size, sha256=h.hexdigest(), signer_sha256=signer, config=config)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--presets', type=Path, required=True, help='preset file from the source revision')
    parser.add_argument('--variant', choices=['android', *farm.PACKAGES], default='android')
    cmd = parser.add_subparsers(dest='cmd', required=True)
    cmd.add_parser('generate').add_argument('destination', type=Path)
    cmd.add_parser('check-unsigned').add_argument('apk', type=Path)
    check = cmd.add_parser('verify')
    check.add_argument('apk', type=Path)
    check.add_argument('--build-tools', type=Path, required=True)
    check.add_argument('--signer-sha256', help='only for the C-500 result; must come from the approved identity')
    a = parser.parse_args()
    preset, identity = worker_preset(a.presets.read_text(), a.variant)
    if a.cmd == 'generate':
        with a.destination.open('x') as f:
            f.write(preset)
    elif a.cmd == 'check-unsigned':
        inspect_zip(a.apk, True, a.variant)
    else:
        print(json.dumps(inspect(a.apk, identity, a.build_tools, a.signer_sha256, a.variant), sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        raise SystemExit(str(exc))
