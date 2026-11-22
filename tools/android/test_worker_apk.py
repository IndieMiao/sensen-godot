import hashlib
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from check_export_inputs import check_template
from worker_apk import inspect, inspect_zip, worker_preset

ROOT = Path(__file__).resolve().parents[2]
PRESETS = (ROOT / 'export_presets.cfg').read_text()
FILES = ('AndroidManifest.xml', 'classes.dex', 'assets/project.binary', 'assets/mapbox_token.txt',
         'lib/arm64-v8a/libgodot_android.so', 'lib/arm64-v8a/libmapbox-maps.so',
         'lib/arm64-v8a/libmapbox-common.so', 'lib/arm64-v8a/liblkjingle_peerconnection_so.so')


class WorkerAPK(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.apk = self.tmp / 'fixture.apk'
        self.cfg, self.identity = worker_preset(PRESETS)

    def fixture(self, files=FILES):
        with zipfile.ZipFile(self.apk, 'w') as z:
            for name in files:
                z.writestr(name, b'fixture')

    def test_generated_preset_is_unsigned_only_and_keeps_identity(self):
        self.assertEqual(self.cfg.count('[preset.0]'), 1)
        self.assertNotIn('[preset.1', self.cfg)
        self.assertIn('package/signed=false\n', self.cfg)
        self.assertIn('runnable=false\n', self.cfg)
        self.assertNotIn('package/signed=true', self.cfg)
        self.assertEqual(worker_preset(self.cfg), (self.cfg, self.identity))
        self.assertEqual(self.identity['package'], 'com.sensen.journeypreview')

    def test_reject_ambiguous_or_non_apk_or_credentialed_preset(self):
        for bad in [PRESETS + PRESETS, PRESETS.replace('package/signed=true', ''),
                    PRESETS.replace('gradle_build/export_format=0', 'gradle_build/export_format=1'),
                    PRESETS.replace('custom_template/release=""', 'custom_template/release="another.apk"'),
                    PRESETS.replace('package/signed=true', 'package/signed=true\nkeystore/release=""')]:
            with self.subTest(), self.assertRaises(ValueError):
                worker_preset(bad)

    def test_reject_v1_signature_and_signing_material_and_incomplete_game(self):
        for names in [FILES + ('META-INF/SIGNER.SF',), FILES + ('assets/temp.jks',), FILES[:-1]]:
            self.fixture(names)
            with self.assertRaises(ValueError):
                inspect_zip(self.apk, True)

    def test_signing_material_rejected_without_opening_any_apk_entry(self):
        for name in ('export_credentials.cfg', '.godot/EXPORT_CREDENTIALS.CFG', 'assets/sample.jks',
                     'sample.keystore', 'sample.p12', 'sample.pk8'):
            self.fixture(FILES + (name,))  # ordinary placeholder bytes, never a key
            for unsigned in (True, False):
                with self.subTest(name=name, unsigned=unsigned), \
                     patch.object(zipfile.ZipFile, 'open', side_effect=AssertionError('entry opened')) as opened:
                    with self.assertRaisesRegex(ValueError, 'signing material'):
                        inspect_zip(self.apk, unsigned)
                    opened.assert_not_called()

    def test_template_setup_rejects_credentials_before_extraction(self):
        # Run the real setup entrypoint in a disposable project, not the checkout.
        tools = self.tmp / 'project/tools/android'
        tools.mkdir(parents=True)
        for script in ('setup_android_build.sh', 'check_export_inputs.py'):
            shutil.copyfile(ROOT / 'tools/android' / script, tools / script)
        for name in ('export_credentials.cfg', '.godot/EXPORT_CREDENTIALS.CFG', 'nested/sample.keystore'):
            with self.subTest(name=name):
                with zipfile.ZipFile(self.tmp / 'android_source.zip', 'w') as z:
                    z.writestr('first-marker', b'unit-test-only')
                    z.writestr(name, b'unit-test-only')
                result = subprocess.run(['bash', tools / 'setup_android_build.sh'], capture_output=True,
                                        env=dict(os.environ, GODOT_TEMPLATES_DIR=str(self.tmp)))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b'signing material', result.stderr)
                self.assertFalse((self.tmp / 'project/android').exists())

    def test_template_name_check_never_opens_members(self):
        for name, forbidden in [('src/main/AndroidManifest.xml', False), ('nested/export_credentials.cfg', True)]:
            self.fixture(('first-marker', name))
            with self.subTest(name=name), patch.object(zipfile.ZipFile, 'open') as opened:
                if forbidden:
                    with self.assertRaisesRegex(ValueError, 'signing material'):
                        check_template(self.apk)
                else:
                    check_template(self.apk)
                opened.assert_not_called()

    def test_tracked_inputs_use_same_name_guard_but_public_runtime_file_must_be_untracked(self):
        for name, allowed in [('assets/input.json', True), ('export_credentials.cfg', False),
                              ('.godot/export_credentials.cfg', False), ('assets/mapbox_token.txt', False)]:
            with self.subTest(name=name):
                result = subprocess.run(['python3', ROOT / 'tools/android/check_export_inputs.py', 'tracked'],
                                        input=b'first-marker\0' + name.encode() + b'\0', capture_output=True)
                self.assertEqual(result.returncode == 0, allowed)

    def test_worker_rejects_relative_output(self):
        result = subprocess.run(['bash', ROOT / 'tools/android/build_worker_apk.sh', 'relative-output'],
                                cwd=self.tmp, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'absolute path', result.stderr)
        self.assertFalse((self.tmp / 'relative-output').exists())

    def test_reject_signing_block_even_without_jar_entries(self):
        self.fixture()
        with zipfile.ZipFile(self.apk) as z:
            offset = z.start_dir
        data = self.apk.read_bytes()
        eocd = data.rindex(b'PK\x05\x06')
        block = struct.pack('<QQ', 24, 24) + b'APK Sig Block 42'
        self.apk.write_bytes(data[:offset] + block + data[offset:eocd+16] +
                             struct.pack('<I', offset + len(block)) + data[eocd+20:])
        with self.assertRaisesRegex(ValueError, 'APK Signing Block'):
            inspect_zip(self.apk, True)

    def test_unapproved_service_signer_rejected(self):
        self.fixture()
        manifest = "package: name='{package}' versionCode='{version_code}' versionName='{version_name}'".format(**self.identity)
        with patch('worker_apk.checked_output', side_effect=['', manifest, 'Signer #1 certificate SHA-256 digest: ' + 'a'*64]), \
             self.assertRaisesRegex(ValueError, 'unexpected APK signer'):
            inspect(self.apk, self.identity, self.tmp, 'b'*64)

    def test_actual_sdk_manifest_digest_and_unsigned_rejection_by_apksigner(self):
        sdk = Path(os.environ.get('ANDROID_HOME', '.'))
        bt = Path(os.environ.get('ANDROID_BUILD_TOOLS', sdk / 'build-tools/36.1.0'))
        jar = sdk / 'platforms/android-36/android.jar'
        if not (jar.is_file() and (bt / 'aapt').is_file()):
            self.skipTest('SDK build-tools and platform required for binary manifest fixture')
        manifest = self.tmp / 'AndroidManifest.xml'
        manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
                            'package="{package}" android:versionCode="{version_code}" android:versionName="{version_name}">'
                            '<uses-sdk android:minSdkVersion="24"/><application/></manifest>'.format(**self.identity))
        subprocess.run([bt / 'aapt', 'package', '-M', manifest, '-I', jar, '-F', self.apk], check=True)
        with zipfile.ZipFile(self.apk, 'a') as z:
            for name in FILES[1:]:
                z.writestr(name, b'fixture')
        aligned = self.tmp / 'aligned.apk'
        subprocess.run([bt / 'zipalign', '-P', '16', '4', self.apk, aligned], check=True)
        result = inspect(aligned, self.identity, bt)
        self.assertEqual(result['sha256'], hashlib.sha256(aligned.read_bytes()).hexdigest())
        with self.assertRaisesRegex(ValueError, 'identity differ'):
            inspect(aligned, dict(self.identity, version_code='1'), bt)
        subprocess.run([bt / 'apksigner', 'version'], check=True, stdout=subprocess.DEVNULL)
        with self.assertRaisesRegex(ValueError, 'apksigner failed'):
            inspect(aligned, self.identity, bt, 'a'*64)


if __name__ == '__main__':
    unittest.main()
