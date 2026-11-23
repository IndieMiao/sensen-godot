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
import dynamic_farm_export as farm
from worker_apk import inspect, inspect_zip, worker_preset

ROOT = Path(__file__).resolve().parents[2]
PRESETS = (ROOT / 'export_presets.cfg').read_text()
PROJECT = (ROOT / 'project.godot').read_text()
FILES = ('AndroidManifest.xml', 'classes.dex', 'assets/project.binary', 'assets/mapbox_token.txt',
         'lib/arm64-v8a/libgodot_android.so', 'lib/arm64-v8a/libmapbox-maps.so',
         'lib/arm64-v8a/libmapbox-common.so', 'lib/arm64-v8a/liblkjingle_peerconnection_so.so')
TARGET = farm.APPROVED_TARGETS[0]
SCENES = tuple('assets/scenes/dynamic_farm/' + name + '.tscn.remap'
               for name in ('dynamic_farm_map', 'dynamic_farm_host', 'dynamic_farm'))
FARM_FILES = FILES + SCENES + tuple('assets/' + path for path in farm.RAW_FILES)


def encode_settings(settings):
    # Godot's ECFG layout: pascal key, then the encoded Variant (bool / string) with its length.
    def variant(value):
        if isinstance(value, bool):
            return struct.pack('<II', 1, value)
        data = value.encode()
        return struct.pack('<II', 4, len(data)) + data + b'\0' * (-len(data) % 4)
    out = b'ECFG' + struct.pack('<I', len(settings))
    for key, value in settings.items():
        encoded = variant(value)
        out += struct.pack('<I', len(key.encode())) + key.encode() + struct.pack('<I', len(encoded)) + encoded
    return out


def exported_settings(variant):
    # What an export of the staged project carries, from the same staging code the build script runs.
    from configparser import ConfigParser
    text = PROJECT if variant == 'android' else farm.staged_project(
        PROJECT, TARGET if variant == 'dynamic-farm-internal' else None)
    config = ConfigParser(interpolation=None)
    config.optionxform = str
    config.read_string(text[text.index('[application]'):])
    return {f'{section}/{key}': value == 'true' if value in ('true', 'false') else value.strip('"')
            for section in ('application', 'sensen') for key, value in config[section].items()}


class WorkerAPK(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.apk = self.tmp / 'fixture.apk'
        self.cfg, self.identity = worker_preset(PRESETS)

    def fixture(self, files=FILES, settings=None):
        with zipfile.ZipFile(self.apk, 'w') as z:
            for name in files:
                z.writestr(name, encode_settings(settings or exported_settings('android'))
                           if name == 'assets/project.binary' else b'fixture')

    def test_generated_preset_is_unsigned_only_and_keeps_identity(self):
        self.assertEqual(self.cfg.count('[preset.0]'), 1)
        self.assertNotIn('[preset.1', self.cfg)
        self.assertIn('package/signed=false\n', self.cfg)
        self.assertIn('runnable=false\n', self.cfg)
        self.assertNotIn('package/signed=true', self.cfg)
        self.assertEqual(worker_preset(self.cfg), (self.cfg, self.identity))
        self.assertEqual(self.identity['package'], 'com.sensen.journeypreview')

    def test_dynamic_variant_is_standalone_and_idempotent(self):
        preset, identity = worker_preset(PRESETS, 'dynamic-farm')
        self.assertEqual(identity, dict(self.identity, package=farm.PACKAGE))
        self.assertEqual(worker_preset(preset, 'dynamic-farm'), (preset, identity))
        self.assertIn('package/signed=false', preset)
        self.assertIn('runnable=false', preset)
        for path in farm.RAW_FILES:
            self.assertIn(path, preset)
        with self.assertRaises(ValueError):
            worker_preset(PRESETS.replace('mapbox_token.txt', 'absent.txt'), 'dynamic-farm')

    def test_dynamic_project_prevents_journey_boot(self):
        from configparser import ConfigParser
        project = (ROOT / 'project.godot').read_text()
        staged = farm.staged_project(project)
        config = ConfigParser(interpolation=None)
        config.read_string(staged[staged.index('[application]'):])
        self.assertEqual(config['application']['run/main_scene'], '"' + farm.MAP_SCENE + '"')
        self.assertTrue(config['application'].getboolean('config/use_custom_user_dir'))
        self.assertTrue(config['sensen'].getboolean('network/online_qa'))
        self.assertEqual(config['sensen']['network/mobile_base_url'], '"http://127.0.0.1:9"')
        self.assertIn('net', config['autoload'])
        with self.assertRaises(ValueError):
            farm.staged_project(project.replace('[sensen]', '[sensen]\nnetwork/online_qa=false'))

    def test_dynamic_readback_rejects_missing_map_or_scenery_payload(self):
        for missing in ('modules/dynamic_farm/map/config.json', 'assets/dynamic_farm/499-art-recipe.json', None):
            self.fixture(tuple(name for name in FARM_FILES if name != 'assets/' + str(missing)),
                         exported_settings('dynamic-farm'))
            if missing:
                with self.assertRaises(ValueError):
                    inspect_zip(self.apk, True, 'dynamic-farm')
            else:
                inspect_zip(self.apk, True, 'dynamic-farm')

    def test_internal_target_is_the_approved_test_service_only(self):
        self.assertEqual(farm.internal_target(TARGET), 'https://aliyun-sh-plane.taildf0ff5.ts.net:8443/v1')
        for bad in ['https://farm.sensenjoy.cn/v1', 'https://farm.sensenjoy.cn/preview/journey/v1',  # production
                    'https://sub.sensenjoy.cn/v1', 'http://192.168.124.53:3150/v1',  # other / devserver P0
                    'http://127.0.0.1:3110/v1', farm.DISABLED, '', TARGET + '/', TARGET + ' ', ' ' + TARGET,
                    TARGET.replace('https', 'http'), TARGET.replace(':8443', ''), TARGET.replace(':8443', ':443'),
                    TARGET.replace('/v1', '/v2'), TARGET.replace('https://', 'https://user@'),
                    TARGET.replace('.ts.net', '.ts.net.example.com'), TARGET.upper(), TARGET + '?x=1', TARGET + '#v']:
            with self.subTest(url=bad), self.assertRaisesRegex(ValueError, 'unapproved'):
                farm.internal_target(bad)
            with self.subTest(url=bad), self.assertRaisesRegex(ValueError, 'unapproved'):
                farm.staged_project(PROJECT, bad)

    def test_internal_settings_only_in_the_explicit_internal_project(self):
        internal, isolated = exported_settings('dynamic-farm-internal'), exported_settings('dynamic-farm')
        release = exported_settings('android')
        for key in ('sensen/network/base_url', 'sensen/network/mobile_base_url'):
            self.assertEqual(internal[key], TARGET)
            self.assertEqual(isolated[key], farm.DISABLED)
            self.assertNotIn(release[key], (TARGET, farm.DISABLED))
        self.assertIs(internal['sensen/network/online_qa'], True)  # Net never boots or signs in anonymously.
        self.assertIs(isolated['sensen/network/online_qa'], True)
        self.assertNotIn('sensen/network/online_qa', release)
        for key in ('sensen/dynamic_farm/reselect', 'sensen/dynamic_farm/account_restore'):
            self.assertIs(internal[key], True)
            self.assertNotIn(key, isolated)
            self.assertNotIn(key, release)
        self.assertNotIn('sensen/dynamic_farm/fake_claims', internal)
        self.assertEqual(internal['application/config/custom_user_dir_name'], 'DynamicFarmInternal')
        for setting in ('dynamic_farm/reselect=false', 'dynamic_farm/fake_claims=true', 'dynamic_farm/reselect.mobile=true',
                        'network/base_url.android="https://farm.sensenjoy.cn/v1"', 'network/online_qa.mobile=false'):
            source = PROJECT.replace('[sensen]', '[sensen]\n' + setting)
            for target in (None, TARGET):
                with self.subTest(setting=setting, target=target), self.assertRaisesRegex(ValueError, 'pre-existing'):
                    farm.staged_project(source, target)

    def test_internal_preset_is_a_separate_unsigned_package_with_the_same_version(self):
        preset, identity = worker_preset(PRESETS, 'dynamic-farm-internal')
        self.assertEqual(identity, dict(self.identity, package=farm.INTERNAL_PACKAGE))
        self.assertEqual(worker_preset(preset, 'dynamic-farm-internal'), (preset, identity))
        self.assertIn('package/name="Dynamic Farm Internal"', preset)
        self.assertIn('package/signed=false', preset)
        self.assertIn('runnable=false', preset)
        self.assertNotEqual(farm.INTERNAL_PACKAGE, farm.PACKAGE)
        for variant in (True, 'android-internal'):  # A bool is an old caller's signature.
            with self.subTest(variant=variant), self.assertRaisesRegex(ValueError, 'unknown package variant'):
                worker_preset(PRESETS, variant)

    def test_readback_checks_each_variants_exported_configuration(self):
        for variant, files in [('android', FILES), ('dynamic-farm', FARM_FILES), ('dynamic-farm-internal', FARM_FILES)]:
            self.fixture(files, exported_settings(variant))
            with self.subTest(variant=variant):
                config = inspect_zip(self.apk, True, variant)
                self.assertEqual(config['variant'], variant)
                internal = variant == 'dynamic-farm-internal'
                self.assertEqual((config['reselect'], config['account_restore']), (internal, internal))
                self.assertEqual(config['journey_mobile_base_url'] == TARGET, internal)
        internal = exported_settings('dynamic-farm-internal')
        bad = [('dynamic-farm', internal), ('android', internal),
               ('dynamic-farm-internal', exported_settings('dynamic-farm')),
               ('dynamic-farm-internal', exported_settings('android')),
               ('android', dict(exported_settings('android'), **{'sensen/dynamic_farm/reselect': True})),
               ('android', dict(exported_settings('android'), **{'sensen/network/mobile_base_url': TARGET})),
               ('android', dict(exported_settings('android'), **{'sensen/network/online_qa': True})),
               ('dynamic-farm', dict(exported_settings('dynamic-farm'), **{'sensen/dynamic_farm/reselect': False})),
               ('dynamic-farm', dict(exported_settings('dynamic-farm'), **{'sensen/network/base_url': TARGET})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/network/base_url': 'https://farm.sensenjoy.cn/v1'})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/network/online_qa': False})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/dynamic_farm/account_restore': False})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/dynamic_farm/fake_claims': True})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/dynamic_farm/reselect.mobile': False})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/network/online_qa.mobile': False})),
               ('dynamic-farm', dict(exported_settings('dynamic-farm'),
                                     **{'sensen/network/mobile_base_url.android': 'https://farm.sensenjoy.cn/v1'})),
               ('android', dict(exported_settings('android'), **{'sensen/network/base_url.mobile': TARGET})),
               (True, exported_settings('dynamic-farm')), ('android-internal', internal)]
        for variant, settings in bad:
            self.fixture(FILES if variant == 'android' else FARM_FILES, settings)
            with self.subTest(variant=variant, settings=settings), self.assertRaises(ValueError):
                inspect_zip(self.apk, True, variant)

    def test_project_binary_reader_rejects_malformed_input(self):
        good = encode_settings({'sensen/network/online_qa': True, 'sensen/network/base_url': TARGET})
        self.assertEqual(farm.project_settings(good), {'sensen/network/online_qa': True, 'sensen/network/base_url': TARGET})
        twice = encode_settings({'a': True})[8:]
        long_string = b'ECFG' + struct.pack('<IIsII', 1, 1, b'k', 12, 4) + struct.pack('<I', 9) + b'abcd'
        for blob in [b'', b'fixture', good[:-1], good + b'\0', b'ECFG' + struct.pack('<I', 2) + twice + twice,
                     long_string]:
            with self.subTest(blob=blob), self.assertRaises(ValueError):
                farm.project_settings(blob)

    def test_build_script_refuses_an_unapproved_target_before_staging(self):
        env = {k: v for k, v in os.environ.items() if k not in ('ANDROID_HOME', 'ANDROID_ADB_SERVER_PORT')}
        script = ROOT / 'tools/android/build_worker_apk.sh'
        out = self.tmp / 'candidate'
        for args, message in [(['https://farm.sensenjoy.cn/v1', out], b'unapproved'),
                              (['http://192.168.124.53:3150/v1', out], b'unapproved'),
                              ([TARGET + '/', out], b'unapproved'), ([out], b'usage'), ([], b'usage'),
                              ([TARGET, out], b'shared Android SDK required')]:  # Approved: passes to the next check.
            with self.subTest(args=args):
                result = subprocess.run(['bash', script, '--dynamic-farm-internal', *args],
                                        cwd=self.tmp, capture_output=True, env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertFalse(out.exists())

    def test_cli_generates_the_internal_preset(self):
        out = self.tmp / 'internal.cfg'
        subprocess.run(['python3', '-B', ROOT / 'tools/android/worker_apk.py', '--variant', 'dynamic-farm-internal',
                        '--presets', ROOT / 'export_presets.cfg', 'generate', out], check=True)
        self.assertEqual(worker_preset(out.read_text(), 'dynamic-farm-internal')[1]['package'], farm.INTERNAL_PACKAGE)

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
                z.writestr(name, encode_settings(exported_settings('android'))
                           if name == 'assets/project.binary' else b'fixture')
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
