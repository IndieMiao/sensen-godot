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
import gradle_dist_seed as seeding
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
        PROJECT, TARGET if variant == 'dynamic-farm-internal' else None, variant == 'dynamic-farm-release')
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
        self.assertIs(internal['sensen/network/online_qa'], True)  # Net never boots; only the map's guest_play signs in.
        self.assertIs(isolated['sensen/network/online_qa'], True)
        self.assertNotIn('sensen/network/online_qa', release)
        for key in ('sensen/dynamic_farm/reselect', 'sensen/dynamic_farm/account_restore', 'sensen/dynamic_farm/own_farm',
                    'sensen/dynamic_farm/guest_play'):
            self.assertIs(internal[key], True)
            self.assertNotIn(key, isolated)
            self.assertNotIn(key, release)
        self.assertNotIn('sensen/dynamic_farm/fake_claims', internal)
        # The device stand-in save (C-34; the market and carpenter use it too, C-59) never ships in any package.
        for settings in (internal, isolated, release):
            self.assertNotIn('sensen/dynamic_farm/local_farm_save', settings)
        self.assertEqual(internal['application/config/custom_user_dir_name'], 'DynamicFarmInternal')
        for setting in ('dynamic_farm/reselect=false', 'dynamic_farm/fake_claims=true', 'dynamic_farm/local_farm_save=true',
                        'dynamic_farm/reselect.mobile=true',
                        'network/base_url.android="https://farm.sensenjoy.cn/v1"', 'network/online_qa.mobile=false'):
            source = PROJECT.replace('[sensen]', '[sensen]\n' + setting)
            for target, release in ((None, False), (TARGET, False), (None, True)):
                with self.subTest(setting=setting, target=target), self.assertRaisesRegex(ValueError, 'pre-existing'):
                    farm.staged_project(source, target, release)

    def test_release_project_is_fixed_to_production_with_own_farm_and_invite_sign_in(self):
        release = exported_settings('dynamic-farm-release')
        self.assertEqual(farm.RELEASE_TARGET, 'https://farm.sensenjoy.cn/dynamicfarm/v1')
        for key in ('sensen/network/base_url', 'sensen/network/mobile_base_url'):
            self.assertEqual(release[key], farm.RELEASE_TARGET)
        # Net never boots, so nothing signs in anonymously; the map reloads only a saved invite sign-in.
        self.assertIs(release['sensen/network/online_qa'], True)
        for key in ('sensen/dynamic_farm/own_farm', 'sensen/dynamic_farm/account_restore', 'sensen/account/invite_only'):
            self.assertIs(release[key], True)
        # Install-and-play (C-100) stays out until the owner decides to open it.
        for key in ('sensen/dynamic_farm/reselect', 'sensen/dynamic_farm/fake_claims', 'sensen/dynamic_farm/local_farm_save',
                    'sensen/dynamic_farm/guest_play'):
            self.assertNotIn(key, release)
        # The 0.4.1 preview's user directory, which this package replaces in place.
        self.assertEqual(release['application/config/custom_user_dir_name'],
                         exported_settings('dynamic-farm')['application/config/custom_user_dir_name'])
        for variant in ('dynamic-farm', 'dynamic-farm-internal', 'android'):
            settings = exported_settings(variant)
            self.assertNotIn('sensen/account/invite_only', settings)
            self.assertNotIn(farm.RELEASE_TARGET, settings.values())
        # No target can be chosen for it, approved or not.
        for target in (TARGET, farm.RELEASE_TARGET, 'https://farm.sensenjoy.cn/preview/p0/v1'):
            with self.subTest(target=target), self.assertRaises(ValueError):
                farm.staged_project(PROJECT, target, True)
        with self.assertRaisesRegex(ValueError, 'pre-existing'):
            farm.staged_project(PROJECT.replace('[sensen]', '[sensen]\naccount/invite_only=true'))

    def test_release_preset_upgrades_the_preview_package_with_the_same_version(self):
        preset, identity = worker_preset(PRESETS, 'dynamic-farm-release')
        self.assertEqual(identity, dict(self.identity, package=farm.PACKAGE))
        self.assertEqual(identity['package'], 'com.sensen.dynamicfarm.cardigan')
        self.assertEqual(worker_preset(preset, 'dynamic-farm-release'), (preset, identity))
        self.assertIn('package/name="Dynamic Farm"', preset)
        self.assertIn('package/signed=false', preset)
        self.assertIn('runnable=false', preset)
        # Only the package name and the display name differ from the preview's preset.
        preview, _ = worker_preset(PRESETS, 'dynamic-farm')
        self.assertEqual(preset.replace('package/name="Dynamic Farm"', 'package/name="Dynamic Farm Preview"'), preview)
        for path in farm.RAW_FILES:
            self.assertIn(path, preset)

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
        for variant, files in [('android', FILES), ('dynamic-farm', FARM_FILES), ('dynamic-farm-internal', FARM_FILES),
                               ('dynamic-farm-release', FARM_FILES)]:
            self.fixture(files, exported_settings(variant))
            with self.subTest(variant=variant):
                config = inspect_zip(self.apk, True, variant)
                self.assertEqual(config['variant'], variant)
                internal, release = variant == 'dynamic-farm-internal', variant == 'dynamic-farm-release'
                self.assertEqual(config['reselect'], internal)
                self.assertEqual(config['guest_play'], internal)
                self.assertEqual((config['account_restore'], config['own_farm']), (internal or release,) * 2)
                self.assertEqual(config['invite_only'], release)
                self.assertEqual(config['journey_mobile_base_url'] == TARGET, internal)
                self.assertEqual(config['journey_mobile_base_url'] == farm.RELEASE_TARGET, release)
        internal = exported_settings('dynamic-farm-internal')
        release = exported_settings('dynamic-farm-release')
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
               ('dynamic-farm-internal', dict(internal, **{'sensen/dynamic_farm/own_farm': False})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/dynamic_farm/guest_play': False})),
               ('dynamic-farm', dict(exported_settings('dynamic-farm'), **{'sensen/dynamic_farm/guest_play': True})),
               ('android', dict(exported_settings('android'), **{'sensen/dynamic_farm/guest_play': True})),
               ('dynamic-farm', dict(exported_settings('dynamic-farm'), **{'sensen/dynamic_farm/own_farm': True})),
               ('android', dict(exported_settings('android'), **{'sensen/dynamic_farm/own_farm': True})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/dynamic_farm/fake_claims': True})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/dynamic_farm/local_farm_save': True})),
               ('dynamic-farm', dict(exported_settings('dynamic-farm'), **{'sensen/dynamic_farm/local_farm_save': True})),
               ('android', dict(exported_settings('android'), **{'sensen/dynamic_farm/local_farm_save': True})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/dynamic_farm/reselect.mobile': False})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/network/online_qa.mobile': False})),
               ('dynamic-farm', dict(exported_settings('dynamic-farm'),
                                     **{'sensen/network/mobile_base_url.android': 'https://farm.sensenjoy.cn/v1'})),
               ('android', dict(exported_settings('android'), **{'sensen/network/base_url.mobile': TARGET})),
               (True, exported_settings('dynamic-farm')), ('android-internal', internal),
               ('dynamic-farm-release', internal), ('dynamic-farm-release', exported_settings('dynamic-farm')),
               ('dynamic-farm-release', exported_settings('android')), ('dynamic-farm', release),
               ('dynamic-farm-internal', release), ('android', release),
               ('dynamic-farm-release', dict(release, **{'sensen/dynamic_farm/reselect': False})),
               ('dynamic-farm-release', dict(release, **{'sensen/dynamic_farm/reselect': True})),
               ('dynamic-farm-release', dict(release, **{'sensen/dynamic_farm/guest_play': True})),
               ('dynamic-farm-release', dict(release, **{'sensen/dynamic_farm/guest_play': False})),
               ('dynamic-farm-release', dict(release, **{'sensen/account/invite_only': False})),
               ('dynamic-farm-release', dict(release, **{'sensen/dynamic_farm/own_farm': False})),
               ('dynamic-farm-release', dict(release, **{'sensen/dynamic_farm/account_restore': False})),
               ('dynamic-farm-release', dict(release, **{'sensen/network/online_qa': False})),
               ('dynamic-farm-release', dict(release, **{'sensen/dynamic_farm/fake_claims': True})),
               ('dynamic-farm-release', dict(release, **{'sensen/dynamic_farm/local_farm_save': True})),
               ('dynamic-farm-release', dict(release, **{'sensen/account/other': True})),
               ('dynamic-farm-release', dict(release, **{'sensen/network/base_url': TARGET})),
               ('dynamic-farm-release', dict(release, **{'sensen/network/mobile_base_url': 'https://farm.sensenjoy.cn/v1'})),
               ('dynamic-farm-release', dict(release, **{'sensen/network/mobile_base_url': farm.RELEASE_TARGET + '/'})),
               ('dynamic-farm-release', dict(release, **{'sensen/network/mobile_base_url':
                                                          'https://farm.sensenjoy.cn/preview/p0/v1'})),
               ('dynamic-farm-release', dict(release, **{'sensen/network/mobile_base_url.android': TARGET})),
               ('dynamic-farm-release', dict(release, **{'sensen/account/invite_only.mobile': False})),
               ('dynamic-farm-internal', dict(internal, **{'sensen/account/invite_only': True})),
               ('dynamic-farm', dict(exported_settings('dynamic-farm'), **{'sensen/account/invite_only': True})),
               ('android', dict(exported_settings('android'), **{'sensen/account/invite_only': True})),
               ('android', dict(exported_settings('android'), **{'sensen/network/mobile_base_url': farm.RELEASE_TARGET}))]
        for variant, settings in bad:
            self.fixture(FILES if variant == 'android' else FARM_FILES, settings)
            with self.subTest(variant=variant, settings=settings), self.assertRaises(ValueError):
                inspect_zip(self.apk, True, variant)

    def test_release_readback_requires_the_preview_user_directory(self):
        # It installs over 0.4.1 in place: another user directory would leave the local data and sign-in behind.
        release = exported_settings('dynamic-farm-release')
        self.assertEqual(farm.PREVIEW_USER_DIR, 'DynamicFarmCardigan')
        self.assertEqual(exported_settings('dynamic-farm')['application/config/custom_user_dir_name'],
                         farm.PREVIEW_USER_DIR)
        self.fixture(FARM_FILES, release)
        self.assertEqual(inspect_zip(self.apk, True, 'dynamic-farm-release')['variant'], 'dynamic-farm-release')
        name, enabled = 'application/config/custom_user_dir_name', 'application/config/use_custom_user_dir'
        without = {key: value for key, value in release.items() if key != name}
        unenabled = {key: value for key, value in release.items() if key != enabled}
        for settings in (dict(release, **{name: 'DynamicFarmInternal'}), dict(release, **{name: 'DynamicFarm'}),
                         dict(release, **{name: 'dynamicfarmcardigan'}), dict(release, **{name: ''}),
                         dict(release, **{name: farm.PREVIEW_USER_DIR + ' '}), dict(release, **{enabled: False}),
                         without, unenabled):
            self.fixture(FARM_FILES, settings)
            with self.subTest(settings={k: settings.get(k) for k in (name, enabled)}), \
                    self.assertRaisesRegex(ValueError, 'preview user directory'):
                inspect_zip(self.apk, True, 'dynamic-farm-release')
        # The preview and internal readbacks are unchanged: they do not check the user directory.
        for variant in ('dynamic-farm', 'dynamic-farm-internal'):
            self.fixture(FARM_FILES, dict(exported_settings(variant), **{name: 'Elsewhere'}))
            with self.subTest(variant=variant):
                self.assertEqual(inspect_zip(self.apk, True, variant)['variant'], variant)

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

    def test_build_script_release_takes_no_target(self):
        env = {k: v for k, v in os.environ.items() if k not in ('ANDROID_HOME', 'ANDROID_ADB_SERVER_PORT')}
        script = ROOT / 'tools/android/build_worker_apk.sh'
        out = self.tmp / 'candidate'
        for args, message in [([TARGET, out], b'usage'), ([farm.RELEASE_TARGET, out], b'usage'), ([], b'usage'),
                              ([out], b'shared Android SDK required')]:  # Valid: passes to the next check.
            with self.subTest(args=args):
                result = subprocess.run(['bash', script, '--dynamic-farm-release', *args],
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


TEMPLATE_WRAPPER = ('#Wed Jan 17 12:08:26 PST 2024\ndistributionBase=GRADLE_USER_HOME\ndistributionPath=wrapper/dists\n'
                    'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.11.1-bin.zip\n'
                    'zipStoreBase=GRADLE_USER_HOME\nzipStorePath=wrapper/dists\n')
WRAPPER_DIR = 'gradle-8.11.1-bin/bpt9gzteqjrbo1mjrsomdt32c'
OFFICIAL_GRADLE_SHA256 = dict(seeding.OFFICIAL_SHA256)  # Before any test patches the table.


class GradleDistSeed(unittest.TestCase):
    """C-64: the disposable Gradle home reuses only a verified wrapper distribution zip."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.props = self.tmp / 'gradle-wrapper.properties'
        self.home = self.tmp / 'home/.gradle'
        self.home.mkdir(parents=True)
        self.state = self.tmp / 'gradle-seed.json'
        self.seed = self.tmp / 'seed'
        self.payload = b'fixture distribution bytes'
        # A fixture zip cannot match the official digest; pin the fixture's own digest via the
        # official table entry instead, so the real table is exercised separately below.
        patcher = patch.dict(seeding.OFFICIAL_SHA256,
                             {'gradle-8.11.1-bin.zip': hashlib.sha256(self.payload).hexdigest()})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.props.write_text(TEMPLATE_WRAPPER)

    def put_seed(self, data):
        (self.seed / WRAPPER_DIR).mkdir(parents=True, exist_ok=True)
        (self.seed / WRAPPER_DIR / 'gradle-8.11.1-bin.zip').write_bytes(data)

    def run_cli(self, *args, env=None):
        return subprocess.run(['python3', '-B', ROOT / 'tools/android/gradle_dist_seed.py', *args],
                              capture_output=True, env=env)

    def gradle_home_files(self):
        return sorted(str(path.relative_to(self.home)) for path in self.home.rglob('*'))

    def test_official_digest_and_wrapper_layout_of_the_template(self):
        self.assertEqual(OFFICIAL_GRADLE_SHA256['gradle-8.11.1-bin.zip'],
                         'f397b287023acdba1e9f6fc5ea72d22dd63669d59ed4a289a29b1a76eee151c6')
        self.assertEqual(seeding.url_hash('https://services.gradle.org/distributions/gradle-8.11.1-bin.zip'),
                         'bpt9gzteqjrbo1mjrsomdt32c')
        name, relative, _ = seeding.plan(TEMPLATE_WRAPPER)
        self.assertEqual((name, str(relative)), ('gradle-8.11.1-bin.zip', WRAPPER_DIR))

    def test_no_seed_directory_leaves_the_build_unchanged(self):
        self.assertFalse(seeding.seed(self.props, self.home, self.state, self.seed))
        self.assertEqual(self.gradle_home_files(), [])
        self.assertFalse(self.state.exists())
        self.assertIsNone(seeding.check(self.state))
        # Through the CLI and the default path under $HOME: silent, nothing written.
        env = {'PATH': os.environ['PATH'], 'HOME': str(self.tmp / 'empty-home')}
        result = self.run_cli('seed', self.props, self.home, self.state, env=env)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b'', b''))
        result = self.run_cli('check', self.state, env=env)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b'', b''))
        self.assertEqual(self.gradle_home_files(), [])

    def test_verified_seed_is_copied_where_the_wrapper_looks(self):
        self.put_seed(self.payload)
        with patch('sys.stderr') as err:
            self.assertTrue(seeding.seed(self.props, self.home, self.state, self.seed))
        self.assertIn('sha256 verified', ''.join(call.args[0] for call in err.write.call_args_list))
        target = self.home / 'wrapper/dists' / WRAPPER_DIR / 'gradle-8.11.1-bin.zip'
        self.assertEqual(target.read_bytes(), self.payload)
        self.assertEqual(self.gradle_home_files(), ['wrapper', 'wrapper/dists', 'wrapper/dists/gradle-8.11.1-bin',
                                                    'wrapper/dists/' + WRAPPER_DIR, 'wrapper/dists/' + WRAPPER_DIR +
                                                    '/gradle-8.11.1-bin.zip'])
        with patch('sys.stderr'):
            self.assertFalse(seeding.check(self.state))  # The wrapper has not unpacked it yet.
            target.with_name(target.name + '.ok').touch()  # Wrapper marks the unpacked seed.
            self.assertTrue(seeding.check(self.state))
            target.unlink()
            target.write_bytes(self.payload)  # A downloaded replacement is a new file.
            self.assertFalse(seeding.check(self.state))

    def test_seed_path_override_through_the_environment(self):
        self.put_seed(self.payload)
        env = {'PATH': os.environ['PATH'], 'HOME': str(self.tmp / 'empty-home'),
               seeding.SEED_ENV: str(self.seed)}
        self.assertEqual(seeding.seed_dir(env), self.seed)
        self.assertEqual(seeding.seed_dir({'HOME': '/h'}), Path('/h/.local/share/sensen-godot/gradle-wrapper-dists'))
        self.assertEqual(seeding.seed_dir({'HOME': '/h', seeding.SEED_ENV: ''}),
                         Path('/h/.local/share/sensen-godot/gradle-wrapper-dists'))
        # The CLI uses the real official digest: the fixture is rejected, proving the override was read.
        result = self.run_cli('seed', self.props, self.home, self.state, env=env)
        self.assertEqual(result.returncode, 0)
        self.assertIn(b'sha256 mismatch', result.stderr)

    def test_wrong_digest_is_not_used_and_falls_back_to_download(self):
        self.put_seed(self.payload + b'tampered')
        with patch('sys.stderr') as err:
            self.assertFalse(seeding.seed(self.props, self.home, self.state, self.seed))
        message = ''.join(call.args[0] for call in err.write.call_args_list)
        self.assertIn('sha256 mismatch', message)
        self.assertIn('will download', message)
        self.assertFalse(self.state.exists())
        self.assertEqual(self.gradle_home_files(), ['wrapper', 'wrapper/dists', 'wrapper/dists/gradle-8.11.1-bin',
                                                    'wrapper/dists/' + WRAPPER_DIR])  # Empty: wrapper downloads.

    def test_unverifiable_or_incomplete_seed_falls_back_to_download(self):
        self.seed.mkdir()
        cases = [(TEMPLATE_WRAPPER, 'no gradle-8.11.1-bin.zip in seed'),  # Seed holds another version only.
                 (TEMPLATE_WRAPPER.replace('8.11.1', '8.12'), 'no official sha256'),
                 # A digest pinned in the template is not trusted in place of the built-in official one.
                 (TEMPLATE_WRAPPER.replace('8.11.1', '8.12') + 'distributionSha256Sum=' + 'b' * 64 + '\n',
                  'no official sha256'),
                 (TEMPLATE_WRAPPER + 'distributionSha256Sum=' + 'a' * 64 + '\n', 'differs from the official'),
                 (TEMPLATE_WRAPPER.replace('distributionPath=wrapper/dists', 'distributionPath=x'), 'non-default'),
                 (TEMPLATE_WRAPPER.replace('https', 'http'), 'no https distributionUrl')]
        for text, reason in cases:
            self.props.write_text(text)
            with self.subTest(reason=reason), patch('sys.stderr') as err:
                self.assertFalse(seeding.seed(self.props, self.home, self.state, self.seed))
                message = ''.join(call.args[0] for call in err.write.call_args_list)
                self.assertIn(reason, message)
                self.assertIn('will download', message)
                self.assertFalse(self.state.exists())
                self.assertEqual([path for path in self.home.rglob('*') if path.is_file()], [])

    def test_install_failure_after_verification_falls_back_to_download(self):
        self.put_seed(self.payload)
        state = self.tmp / 'absent-directory/gradle-seed.json'  # The state file cannot be written.
        with patch('sys.stderr') as err:
            self.assertFalse(seeding.seed(self.props, self.home, state, self.seed))
        message = ''.join(call.args[0] for call in err.write.call_args_list)
        self.assertIn('cannot install', message)
        self.assertIn('will download', message)
        self.assertEqual([path for path in self.home.rglob('*') if path.is_file()], [])

    def test_build_script_seeds_after_template_setup_and_checks_after_export(self):
        script = (ROOT / 'tools/android/build_worker_apk.sh').read_text()
        order = [script.index(marker) for marker in (
            'setup_android_build.sh"', '"${seed_tool[@]}" seed "$p/android/build/gradle/wrapper/gradle-wrapper.properties" '
            '"$home/.gradle"', 'run_editor --export-release', '"${seed_tool[@]}" check')]
        self.assertEqual(order, sorted(order))
        self.assertIn('"GRADLE_USER_HOME=$home/.gradle"', script)


if __name__ == '__main__':
    unittest.main()
