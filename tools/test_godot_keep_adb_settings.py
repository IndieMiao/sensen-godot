"""python3 -m unittest tools/test_godot_keep_adb_settings.py (C-210, C-213).

The last case runs the real Godot (skipped without one on PATH) against a stub adb: an editor import under a
private HOME stops "the" adb server without the helper and leaves it alone with it.
"""
import importlib.util
import io
import os
import platform
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('godot_keep_adb_settings', ROOT / 'tools/godot_keep_adb_settings.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
KEY = helper.KEY
SETTINGS = ('[gd_resource type="EditorSettings" format=3]\n\n[sub_resource type="InputEventKey" id="1"]\nkeycode = 65\n\n'
            '[resource]\nexport/android/android_sdk_path = "/opt/android-sdk"\n{line}'
            'export/android/debug_keystore = "/keys/debug.keystore"\n')


class EnsureTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.godot = self.tmp / 'bin/godot'
        self.godot.parent.mkdir()
        self.godot.write_text('#!/bin/sh\necho 4.7.2.stable.official.test\n')
        self.godot.chmod(0o755)
        self.account = self.tmp / 'account'
        self.private = self.tmp / 'private'

    def ensure(self, home, system='Linux', **env):
        log = io.StringIO()
        result = helper.ensure(self.godot, {'HOME': str(home), **env}, str(self.account), system, log)
        return result, log.getvalue()

    def settings(self, home, system='Linux'):
        if system == 'Darwin':
            return home / 'Library/Application Support/Godot/editor_settings-4.7.tres'
        return home / '.config/godot/editor_settings-4.7.tres'

    def test_fresh_private_home_gets_minimal_settings(self):
        for system in ('Linux', 'Darwin'):
            with self.subTest(system=system):
                home = self.private / system
                self.assertEqual(self.ensure(home, system)[0], 'written')
                text = self.settings(home, system).read_text()
                self.assertEqual(text, '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' + KEY + ' = false\n')
                self.assertEqual(self.ensure(home, system)[0], 'ok')

    def test_private_true_or_missing_key_is_set_false_keeping_the_rest(self):
        for line in (KEY + ' = true\n', ''):
            with self.subTest(line=line):
                f = self.settings(self.private)
                f.parent.mkdir(parents=True, exist_ok=True)
                f.write_text(SETTINGS.format(line=line))
                self.assertEqual(self.ensure(self.private)[0], 'written')
                lines = f.read_text().splitlines()
                self.assertEqual(lines[lines.index('[resource]') + 1], KEY + ' = false')
                self.assertEqual(sum(KEY in l for l in lines), 1)
                self.assertIn('keycode = 65', lines)
                self.assertIn('export/android/debug_keystore = "/keys/debug.keystore"', lines)

    def test_already_false_is_left_untouched(self):
        f = self.settings(self.private)
        f.parent.mkdir(parents=True)
        f.write_text(SETTINGS.format(line=KEY + ' = false\n'))
        before = f.stat().st_mtime_ns
        self.assertEqual(self.ensure(self.private), ('ok', ''))
        self.assertEqual(f.stat().st_mtime_ns, before)

    def test_private_xdg_config_on_linux(self):
        result, _ = self.ensure(self.account, XDG_CONFIG_HOME=str(self.private / 'cfg'))
        self.assertEqual(result, 'written')
        self.assertTrue((self.private / 'cfg/godot/editor_settings-4.7.tres').is_file())
        self.assertFalse((self.account / '.config').exists())

    def test_xdg_is_ignored_on_macos(self):
        result, _ = self.ensure(self.private, 'Darwin', XDG_CONFIG_HOME=str(self.tmp / 'cfg'))
        self.assertEqual(result, 'written')
        self.assertTrue(self.settings(self.private, 'Darwin').is_file())
        self.assertFalse((self.tmp / 'cfg').exists())

    def test_migrates_from_newest_earlier_version(self):
        d = self.settings(self.private).parent
        d.mkdir(parents=True)
        (d / 'editor_settings-4.5.tres').write_text(SETTINGS.format(line='').replace('/opt/android-sdk', '/sdk45'))
        (d / 'editor_settings-4.6.tres').write_text(SETTINGS.format(line=KEY + ' = true\n').replace('/opt/android-sdk', '/sdk46'))
        self.assertEqual(self.ensure(self.private)[0], 'written')
        text = self.settings(self.private).read_text()
        self.assertIn('/sdk46', text)
        self.assertIn(KEY + ' = false', text)
        self.assertNotIn(KEY + ' = true', text)
        self.assertIn(KEY + ' = true', (d / 'editor_settings-4.6.tres').read_text())

    def test_account_settings_are_never_written(self):
        for system in ('Linux', 'Darwin'):
            for line in (KEY + ' = true\n', None):
                with self.subTest(system=system, line=line):
                    f = self.settings(self.account, system)
                    if line is not None:
                        f.parent.mkdir(parents=True, exist_ok=True)
                        f.write_text(SETTINGS.format(line=line))
                    before = f.read_text() if f.exists() else None
                    result, log = self.ensure(self.account, system, ANDROID_ADB_SERVER_PORT='5137')
                    self.assertEqual(result, 'not_private')
                    self.assertIn('port 5137', log)
                    self.assertEqual(f.read_text() if f.exists() else None, before)
                    if f.exists():
                        f.unlink()

    def test_account_settings_already_false(self):
        f = self.settings(self.account)
        f.parent.mkdir(parents=True)
        f.write_text(SETTINGS.format(line=KEY + ' = false\n'))
        self.assertEqual(self.ensure(self.account), ('ok', ''))

    def test_self_contained_godot_is_not_written(self):
        (self.godot.parent / '._sc_').touch()
        result, log = self.ensure(self.private)
        self.assertEqual(result, 'not_private')
        self.assertIn('self-contained', log)
        self.assertFalse((self.godot.parent / 'editor_data').exists())
        self.assertFalse(self.private.exists())

    def test_settings_without_resource_section_fail_without_writing(self):
        f = self.settings(self.private)
        f.parent.mkdir(parents=True)
        f.write_text('[gd_resource type="EditorSettings" format=3]\n')
        with self.assertRaises(SystemExit):
            self.ensure(self.private)
        self.assertEqual(f.read_text(), '[gd_resource type="EditorSettings" format=3]\n')


class LinkAdbKeysTest(unittest.TestCase):
    """A private HOME's adb keys link to the account's, so a server adb starts there is authorized (C-213)."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.account = self.tmp / 'account'
        self.keys = self.account / '.android'
        self.keys.mkdir(parents=True)
        (self.keys / 'adbkey').write_text('PRIVATE\n')
        (self.keys / 'adbkey.pub').write_text('PUBLIC user@host\n')
        (self.keys / 'emu-update-last-check.ini').write_text('x\n')
        self.private = self.tmp / 'private'

    def link(self, home, **env):
        log = io.StringIO()
        return helper.link_adb_keys({'HOME': str(home), **env}, str(self.account), log), log.getvalue()

    def snapshot(self, directory):
        return {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in sorted(directory.iterdir())}

    def assert_linked(self, home, source):
        for name in ('adbkey', 'adbkey.pub'):
            link = home / '.android' / name
            self.assertTrue(link.is_symlink(), name)
            self.assertEqual(os.readlink(link), os.path.realpath(source / name))
            self.assertEqual(link.read_bytes(), (source / name).read_bytes())

    def test_private_home_links_the_account_keys(self):
        before = self.snapshot(self.keys)
        result, log = self.link(self.private)
        self.assertEqual(result, 'linked')
        self.assertIn('link to', log)
        self.assert_linked(self.private, self.keys)
        self.assertEqual(sorted(p.name for p in (self.private / '.android').iterdir()), ['adbkey', 'adbkey.pub'])
        self.assertEqual(self.link(self.private), ('ok', ''))
        self.assertEqual(self.snapshot(self.keys), before)

    def test_private_keys_adb_generated_are_replaced(self):
        d = self.private / '.android'
        d.mkdir(parents=True)
        (d / 'adbkey').write_text('OTHER\n')
        (d / 'adbkey.pub').symlink_to(self.tmp / 'elsewhere.pub')
        (d / 'adb_usb.ini').write_text('kept\n')
        self.assertEqual(self.link(self.private)[0], 'linked')
        self.assert_linked(self.private, self.keys)
        self.assertEqual((d / 'adb_usb.ini').read_text(), 'kept\n')
        self.assertFalse(any(p.name.endswith('.tmp') for p in d.iterdir()))

    def test_account_home_is_left_alone(self):
        before = self.snapshot(self.keys)
        self.assertEqual(self.link(self.account), ('not_private', ''))
        self.assertEqual(self.link(''), ('not_private', ''))  # adb falls back to the account's home
        self.assertEqual(self.snapshot(self.keys), before)
        self.assertFalse((self.keys / 'adbkey').is_symlink())

    def test_key_directory_is_configurable(self):
        other = self.tmp / 'other-keys'
        other.mkdir()
        (other / 'adbkey').write_text('K\n')
        (other / 'adbkey.pub').write_text('K.pub\n')
        self.assertEqual(self.link(self.private, SENSEN_ADB_KEY_DIR=str(other))[0], 'linked')
        self.assert_linked(self.private, other)
        self.assertEqual(self.link(self.tmp / 'off', SENSEN_ADB_KEY_DIR='none'), ('off', ''))
        self.assertFalse((self.tmp / 'off').exists())

    def test_missing_account_keys_leave_the_private_home_alone(self):
        (self.keys / 'adbkey.pub').unlink()
        result, log = self.link(self.private)
        self.assertEqual(result, 'no_keys')
        self.assertIn('no adbkey and adbkey.pub', log)
        self.assertFalse(self.private.exists())


@unittest.skipUnless(shutil.which('godot'), 'no godot on PATH')
class RealGodotImportTest(unittest.TestCase):
    """An editor import of a project with a runnable Android preset, under a fresh private HOME."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        adb = self.tmp / 'sdk/platform-tools/adb'
        adb.parent.mkdir(parents=True)
        self.calls = self.tmp / 'adb.log'
        adb.write_text(f'#!/bin/sh\necho "port=$ANDROID_ADB_SERVER_PORT $*" >> "{self.calls}"\n')
        adb.chmod(0o755)
        project = self.tmp / 'project'
        project.mkdir()
        (project / 'project.godot').write_text('config_version=5\n\n[application]\nconfig/name="adb_probe"\n')
        (project / 'export_presets.cfg').write_text(
            '[preset.0]\n\nname="Android"\nplatform="Android"\nrunnable=true\nexport_filter="all_resources"\n\n'
            '[preset.0.options]\n\npackage/unique_name="com.example.adbprobe"\n')
        self.project = project

    def import_once(self, home, keep_adb):
        env = {k: v for k, v in os.environ.items() if not k.startswith(('XDG_', 'ANDROID_', 'GODOT'))}
        env.update(HOME=str(home), ANDROID_HOME=str(self.tmp / 'sdk'), ANDROID_ADB_SERVER_PORT='5199')
        if platform.system() != 'Darwin':
            env.update(XDG_CONFIG_HOME=str(home / '.config'), XDG_DATA_HOME=str(home / '.local/share'),
                       XDG_CACHE_HOME=str(home / '.cache'))
        if keep_adb:
            subprocess.run(['python3', '-I', str(ROOT / 'tools/godot_keep_adb_settings.py'), 'godot'], env=env, check=True)
        subprocess.run(['godot', '--headless', '--path', str(self.project), '--import'], env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
        calls = self.calls.read_text() if self.calls.exists() else ''
        self.calls.unlink(missing_ok=True)
        return calls

    def test_import(self):
        self.assertIn('port=5199 kill-server', self.import_once(self.tmp / 'home-default', keep_adb=False))
        self.assertNotIn('kill-server', self.import_once(self.tmp / 'home-kept', keep_adb=True))


if __name__ == '__main__':
    unittest.main()
