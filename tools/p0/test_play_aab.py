#!/usr/bin/env python3
"""Focused release-tool regressions. Synthetic archives/ELF and stubbed Java output; no Godot, ADB, keys or uploads."""
from contextlib import redirect_stderr
import hashlib
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import check_play_aab as checks
import play_aab as build

def elf(aligns=(16384, 16384), mismatch=False):
    data = bytearray(64 + 56 * len(aligns))
    data[:7] = b'\x7fELF\x02\x01\x01'
    struct.pack_into('<HH', data, 16, 3, 183)
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, len(aligns))
    for i, alignment in enumerate(aligns):
        struct.pack_into('<IIQQQQQQ', data, 64 + 56 * i, 1, 5, 0, 1 if mismatch else 0, 0, 0, 4096, alignment)
    return bytes(data)

def android_manifest(extra='', app_extra='', missing_plugin=None):
    permissions = ''.join(f'<uses-permission android:name="{p}"/>' for p in sorted(checks.ALLOWED_PERMISSIONS))
    plugins = ''.join(f'<meta-data android:name="{p}" android:value="test"/>' for p in sorted(checks.PLUGINS) if p != missing_plugin)
    return f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="app.gensen.maps"
android:versionCode="2026111501" android:versionName="0.3.11"><uses-sdk android:minSdkVersion="29" android:targetSdkVersion="36"/>
{permissions}{extra}<application {app_extra}>{plugins}</application></manifest>'''

def preset():
    return '''[preset.0]
name="Android P0"
[preset.0.options]
version/code=7
version/name="old"
[preset.4]
name="Android Play"
custom_features="p0,store"
[preset.4.options]
gradle_build/export_format=1
gradle_build/use_gradle_build=true
gradle_build/compress_native_libraries=false
package/unique_name="app.gensen.maps"
package/signed=true
architectures/arm64-v8a=true
architectures/armeabi-v7a=false
architectures/x86=false
architectures/x86_64=false
version/code=1
version/name="0.1.0"
[preset.5]
name="Unrelated"
version/code=99
'''

class PlayBundleChecks(unittest.TestCase):
    def test_every_load_segment_requires_16k(self):
        self.assertEqual(checks.elf_load_alignment(elf()), [16384, 16384])
        for data in [elf((16384, 4096)), elf((24576,)), elf(mismatch=True), elf()[:90], b'not ELF']:
            with self.subTest(size=len(data)), self.assertRaises(checks.CheckError):
                checks.elf_load_alignment(data)

    def test_no_load_segments_is_not_a_pass(self):
        data = bytearray(elf())
        struct.pack_into('<I', data, 64, 4)
        struct.pack_into('<I', data, 120, 4)
        with self.assertRaises(checks.CheckError):
            checks.elf_load_alignment(data)

    def test_permission_changes_are_not_silently_accepted(self):
        self.assertTrue(checks.manifest_facts(android_manifest(), 2026111501, '0.3.11')['permissions_ok'])
        for permission in [checks.AD_ID, 'android.permission.CAMERA', 'android.permission.ACCESS_FINE_LOCATION', 'android.permission.READ_PHONE_STATE']:
            with self.subTest(permission=permission), self.assertRaises(checks.CheckError):
                checks.manifest_facts(android_manifest(f'<uses-permission-sdk-23 android:name="{permission}"/>'), 2026111501, '0.3.11')

    def test_debug_cleartext_and_plugin_loss_are_rejected(self):
        for xml in [android_manifest(app_extra='android:debuggable="true"'),
                    android_manifest(app_extra='android:networkSecurityConfig="@xml/dev"'),
                    android_manifest(missing_plugin='org.godotengine.plugin.v2.GodotGoogleSignIn'),
                    android_manifest().replace('</application>', '<service android:name="io.livekit.android.room.track.screencapture.ScreenCaptureService"/></application>')]:
            with self.assertRaises(checks.CheckError):
                checks.manifest_facts(xml, 2026111501, '0.3.11')

    def test_package_version_and_target_are_read_from_artifact(self):
        for xml in [android_manifest().replace('package="app.gensen.maps"', 'package="com.sensen.p0demo"'),
                    android_manifest().replace('2026111501', '2026111401'),
                    android_manifest().replace('targetSdkVersion="36"', 'targetSdkVersion="34"')]:
            with self.assertRaises(checks.CheckError):
                checks.manifest_facts(xml, 2026111501, '0.3.11')

    def test_elf_pass_does_not_replace_aab_zip_alignment_setting(self):
        good = {'optimizations': {'uncompressNativeLibraries': {'enabled': True, 'alignment': 'PAGE_ALIGNMENT_16K'}}}
        self.assertTrue(checks.bundle_config_facts(good)['bundle_16kb_ok'])
        for cfg in [{}, {'optimizations': {'uncompressNativeLibraries': {'enabled': True, 'alignment': 'PAGE_ALIGNMENT_4K'}}}]:
            with self.assertRaises(checks.CheckError):
                checks.bundle_config_facts(cfg)

    def test_unsigned_and_wrong_upload_certificate_rejected(self):
        with patch.object(checks, 'capture', return_value='jar is unsigned.'):
            with self.assertRaises(checks.CheckError):
                checks.signing_facts(Path('fake.aab'), Path('/jdk'), checks.UPLOAD_CERT)
        pem = '-----BEGIN CERTIFICATE-----\nZmFrZS11bml0LXRlc3QtY2VydA==\n-----END CERTIFICATE-----'
        with patch.object(checks, 'capture', side_effect=['jar verified.', pem]):
            with self.assertRaises(checks.CheckError):
                checks.signing_facts(Path('fake.aab'), Path('/jdk'), checks.UPLOAD_CERT)
        with patch.object(checks, 'capture', return_value='jar verified. This jar contains unsigned entries.'):
            with self.assertRaises(checks.CheckError):
                checks.signing_facts(Path('fake.aab'), Path('/jdk'), checks.UPLOAD_CERT)

    def archive(self, path, prefix='assetPackInstallTime/assets/', extra=None):
        files = {n: elf() for n in checks.NATIVE}
        files.update({prefix + 'mapbox_token.txt': b'synthetic-map-token',
                      prefix + 'assets/p0/demo_server.json': json.dumps({'url': 'https://example.invalid/v1', 'key': 'synthetic-private-key', 'version': 2026111501, 'name': '0.3.11'}).encode(),
                      prefix + 'assets/p0/legal/licenses.json': json.dumps({'groups': [{'rows': [{'text': 'res://assets/p0/legal/license.txt'}]}]}).encode(),
                      prefix + 'assets/p0/legal/license.txt': b'license'})
        if extra:
            files.update(extra)
        with zipfile.ZipFile(path, 'w') as z:
            for name, data in files.items():
                z.writestr(name, data)

    def test_install_time_or_base_resources_and_baked_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            aab = Path(tmp) / 'fake.aab'
            for prefix in checks.ASSET_ROOTS:
                self.archive(aab, prefix)
                r = checks.check_archive(aab, 'https://example.invalid/v1', 'synthetic-private-key', 2026111501, '0.3.11')
                self.assertTrue(r['elf_16kb_ok'])
                self.assertFalse(r['account_legal_versions_present'])  # r1's absence is reported, not invented.
                self.assertNotIn('synthetic-private-key', json.dumps(r))
                with self.assertRaises(checks.CheckError) as error:
                    checks.check_archive(aab, 'https://example.invalid/v1', 'wrong-private-key', 2026111501, '0.3.11')
                self.assertNotIn('wrong-private-key', str(error.exception))

    def test_duplicate_resource_qa_entry_and_wrong_abi_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            aab = Path(tmp) / 'fake.aab'
            for extra in [{'base/assets/assets/p0/demo_server.json': b'{}'}, {'assetPackInstallTime/assets/tools/qa/qa_entry.gdc': b'qa'},
                          {'base/lib/x86_64/bad.so': elf()}]:
                self.archive(aab, extra=extra)
                with self.assertRaises(checks.CheckError):
                    checks.check_archive(aab, 'https://example.invalid/v1', 'synthetic-private-key', 2026111501, '0.3.11')

    def test_arm64_path_cannot_hide_wrong_machine_header(self):
        with tempfile.TemporaryDirectory() as tmp:
            aab = Path(tmp) / 'fake.aab'
            wrong_machine = bytearray(elf())
            struct.pack_into('<H', wrong_machine, 18, 62)  # x86_64, despite the arm64 path.
            self.archive(aab, extra={checks.NATIVE[0]: bytes(wrong_machine)})
            with self.assertRaises(checks.CheckError):
                checks.check_archive(aab, 'https://example.invalid/v1', 'synthetic-private-key', 2026111501, '0.3.11')

class PlayBuildSafety(unittest.TestCase):
    def test_version_reservations_survive_failed_attempts(self):
        build.check_next_code([], 2026111501)
        for history, code in [([], 2026111401), ([{'version_code': 2026111502, 'status': 'failed'}], 2026111502),
                              ([{'version_code': 2026111502, 'status': 'reserved'}], 2026111501), ({}, 2026111503)]:
            with self.assertRaises(checks.CheckError):
                build.check_next_code(history, code)
        for code in ['2026111500', '2026023101', '1', '2026111501suffix']:
            with self.assertRaises(checks.CheckError):
                build.version_code(code)

    def test_unsafe_endpoints_refused_without_echo(self):
        for server in ['http://example.invalid/v1', 'https://user:SECRET@example.invalid/v1', 'https://example.invalid/v1?key=SECRET']:
            with self.assertRaises(checks.CheckError) as error:
                build.validated_server(server)
            self.assertNotIn('SECRET', str(error.exception))

    def test_only_play_preset_changes(self):
        original = preset()
        modified = build.configured_presets(original, 2026111501, '0.3.11')
        self.assertIn('version/code=7\nversion/name="old"', modified)
        self.assertIn('name="Unrelated"\nversion/code=99', modified)
        self.assertIn('version/code=2026111501\nversion/name="0.3.11"', modified)
        with self.assertRaises(checks.CheckError):
            build.configured_presets(original.replace('p0,store', 'p0,accounts_ui_qa'), 2026111501, '0.3.11')

    def test_original_export_inputs_restored_on_failure_and_interrupt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'assets/p0').mkdir(parents=True)
            config = root / 'export_presets.cfg'; baked = root / 'assets/p0/demo_server.json'
            config.write_text(preset()); original = config.read_bytes()
            for existing in (False, True):
                if existing:
                    baked.write_bytes(b'{"original":"do-not-remove"}\n'); baked.chmod(0o640)
                for failure in (RuntimeError, KeyboardInterrupt):
                    with self.assertRaises(failure):
                        with build.temporary_export_files(root, 'https://example.invalid/v1', 'synthetic-key', 2026111501, '0.3.11'):
                            self.assertEqual(json.loads(baked.read_text())['version'], 2026111501)
                            raise failure()
                    self.assertEqual(config.read_bytes(), original)
                    if existing:
                        self.assertEqual(baked.read_bytes(), b'{"original":"do-not-remove"}\n')
                        self.assertEqual(baked.stat().st_mode & 0o777, 0o640)
                    else:
                        self.assertFalse(baked.exists())

    def test_download_copy_does_not_replace_or_publish_partial_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source = root / 'source'; target = root / 'download.aab'
            source.write_bytes(b'valid-artifact'); digest = checks.sha256(source)
            with self.assertRaises(checks.CheckError):
                build.copy_verified(source, target, '0' * 64)
            self.assertFalse(target.exists())
            build.copy_verified(source, target, digest)
            with self.assertRaises(FileExistsError):
                build.copy_verified(source, target, digest)
            self.assertEqual(target.read_bytes(), b'valid-artifact')
            self.assertEqual(sorted(p.name for p in root.iterdir()), ['download.aab', 'source'])

    def test_export_log_redacts_private_values_even_on_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / 'export.log'
            with self.assertRaises(checks.CheckError):
                build.run_logged([sys.executable, '-c', 'print("fake-password fake-api-key"); raise SystemExit(2)'], log,
                                 dict(__import__('os').environ), ['fake-password', 'fake-api-key'])
            self.assertNotIn('fake-password', log.read_text())
            self.assertNotIn('fake-api-key', log.read_text())
            self.assertEqual(log.read_text().strip(), '[REDACTED] [REDACTED]')

    def test_upload_flag_is_not_an_upload_path_and_errors_do_not_echo_secrets(self):
        err = io.StringIO()
        with redirect_stderr(err), self.assertRaises(SystemExit) as result:
            build.parser().parse_args(['--server', 'https://example.invalid/v1', '--code', '2026111501', '--name', '0.3.11', '--upload', 'SECRET'])
        self.assertEqual(result.exception.code, 2)
        self.assertNotIn('SECRET', err.getvalue())

if __name__ == '__main__':
    unittest.main()
