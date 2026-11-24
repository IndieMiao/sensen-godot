import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'tools/p0/godot_keep_adb.sh'
KEY = 'export/android/shutdown_adb_on_exit'
SETTINGS = ('[gd_resource type="EditorSettings" format=3]\n\n[sub_resource type="InputEventKey" id="1"]\nkeycode = 65\n\n'
            '[resource]\nexport/android/android_sdk_path = "/opt/android-sdk"\n' + KEY + ' = true\n'
            'export/android/debug_keystore = "/keys/debug.keystore"\n')


class GodotKeepAdbTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(subprocess.run, ['rm', '-rf', str(self.tmp)])
        self.home = self.tmp / 'home'
        godot = self.tmp / 'bin/godot'
        godot.parent.mkdir()
        godot.write_text('#!/bin/sh\necho 4.7.2.stable.official.test\n')
        godot.chmod(0o755)
        self.godot = godot
        if platform.system() == 'Darwin':
            self.config = self.data = self.home / 'Library/Application Support/Godot'
        else:
            self.config, self.data = self.home / '.config/godot', self.home / '.local/share/godot'
        (self.data / 'export_templates/4.7.2.stable').mkdir(parents=True)
        self.config.mkdir(parents=True, exist_ok=True)

    def run_helper(self, java_home=None, check=True):
        out = self.tmp / 'copy'
        out.mkdir()
        env = {k: v for k, v in os.environ.items() if not k.startswith('XDG_') and k != 'JAVA_HOME'}
        env['HOME'] = str(self.home)
        if java_home:
            env['JAVA_HOME'] = java_home
        result = subprocess.run(['bash', '-c', 'set -euo pipefail; source "$0"; p0_godot_keep_adb "$1" "$2"; echo "$P0_GODOT"',
                                 str(HELPER), str(self.godot), str(out)],
                                env=env, check=check, capture_output=True, text=True)
        self.result = result
        return out, Path(result.stdout.strip())

    def test_copy_keeps_the_accounts_settings_but_never_shuts_adb_down(self):
        (self.config / 'editor_settings-4.7.tres').write_text(SETTINGS)
        out, godot = self.run_helper()
        self.assertEqual(godot, out / 'godot')
        self.assertEqual(subprocess.run([str(godot), '--version'], capture_output=True, text=True).stdout,
                         '4.7.2.stable.official.test\n')
        self.assertTrue((out / '._sc_').exists())
        text = (out / 'editor_data/editor_settings-4.7.tres').read_text()
        self.assertEqual(re.findall(f'^{KEY} = .*$', text, re.M), [f'{KEY} = false'])
        self.assertEqual(text.replace(f'{KEY} = false\n', ''), SETTINGS.replace(f'{KEY} = true\n', ''))
        # The key sits in [resource], not in a sub_resource.
        self.assertLess(text.index('[resource]'), text.index(KEY))
        self.assertEqual((out / 'editor_data/export_templates').resolve(), (self.data / 'export_templates').resolve())
        self.assertEqual((out / 'editor_data/keystores').resolve(), (self.data / 'keystores').resolve())
        # The account's own settings are left alone.
        self.assertEqual((self.config / 'editor_settings-4.7.tres').read_text(), SETTINGS)

    def test_without_this_versions_settings_the_newest_earlier_ones_are_copied(self):
        (self.config / 'editor_settings-4.5.tres').write_text(SETTINGS.replace('/opt/android-sdk', '/old/sdk'))
        (self.config / 'editor_settings-4.6.tres').write_text(SETTINGS)
        (self.config / 'editor_settings-4.10.tres').write_text(SETTINGS.replace('/opt/android-sdk', '/newer/sdk'))
        (self.config / 'editor_settings-3.tres').write_text(SETTINGS.replace('/opt/android-sdk', '/godot3/sdk'))
        out, _ = self.run_helper()
        text = (out / 'editor_data/editor_settings-4.7.tres').read_text()
        self.assertEqual(text.replace(f'{KEY} = false\n', ''), SETTINGS.replace(f'{KEY} = true\n', ''))
        self.assertIn('editor_settings-4.6.tres', self.result.stderr)
        self.assertFalse((self.config / 'editor_settings-4.7.tres').exists())

    def test_without_any_settings_it_stops_and_says_why(self):
        (self.config / 'editor_settings-4.8.tres').write_text(SETTINGS)
        out, _ = self.run_helper(check=False)
        self.assertNotEqual(self.result.returncode, 0)
        self.assertIn('no editor settings for Godot 4.7', self.result.stderr)
        self.assertIn('Android SDK and JDK', self.result.stderr)
        self.assertFalse((out / 'editor_data/editor_settings-4.7.tres').exists())

    def test_an_unwritable_data_directory_without_keystores_is_skipped_with_a_note(self):
        (self.config / 'editor_settings-4.7.tres').write_text(SETTINGS)
        self.data.chmod(0o555)
        self.addCleanup(self.data.chmod, 0o755)
        out, _ = self.run_helper()
        self.assertFalse((self.data / 'keystores').exists())
        self.assertFalse(os.path.lexists(out / 'editor_data/keystores'))
        self.assertIn('keystores', self.result.stderr)
        self.assertEqual((out / 'editor_data/export_templates').resolve(), (self.data / 'export_templates').resolve())
        self.assertIn(f'{KEY} = false', (out / 'editor_data/editor_settings-4.7.tres').read_text())

    def test_an_empty_jdk_setting_takes_the_callers_java_home_but_a_set_one_is_kept(self):
        settings = self.config / 'editor_settings-4.7.tres'
        settings.write_text(SETTINGS + 'export/android/java_sdk_path = ""\n')
        out, _ = self.run_helper('/jdk home')
        text = (out / 'editor_data/editor_settings-4.7.tres').read_text()
        self.assertEqual(re.findall('^export/android/java_sdk_path = .*$', text, re.M),
                         ['export/android/java_sdk_path = "/jdk home"'])
        subprocess.run(['rm', '-rf', str(out)], check=True)
        settings.write_text(SETTINGS + 'export/android/java_sdk_path = "/own/jdk"\n')
        out, _ = self.run_helper('/jdk home')
        text = (out / 'editor_data/editor_settings-4.7.tres').read_text()
        self.assertEqual(re.findall('^export/android/java_sdk_path = .*$', text, re.M),
                         ['export/android/java_sdk_path = "/own/jdk"'])

    def test_p0_scripts_run_godot_only_through_the_copy(self):
        for name in ('build_demo_apk.sh', 'android_p0.sh'):
            text = (ROOT / 'tools/p0' / name).read_text()
            self.assertIn('p0_godot_keep_adb ', text, name)
            runs = re.findall(r'^\s*(\S+) --headless', text, re.M)
            self.assertEqual(set(runs), {'"$P0_GODOT"'}, name)
        # play_aab.py (build_play_aab.sh) swaps its Godot for the copy before any run.
        text = (ROOT / 'tools/p0/play_aab.py').read_text()
        self.assertEqual(len(re.findall(r'^\s*godot = godot_keep_adb\(godot, ', text, re.M)), 1)
        runs = re.findall(r"run_logged\(\[(\w+), '--headless'", text)
        self.assertEqual(set(runs), {'godot'})
        self.assertLess(text.index('godot = godot_keep_adb('), text.index("run_logged([godot, '--headless'"))

    def test_play_build_gets_the_copy_with_its_jdk(self):
        sys.path.insert(0, str(ROOT / 'tools/p0'))
        self.addCleanup(sys.path.remove, str(ROOT / 'tools/p0'))
        import play_aab
        (self.config / 'editor_settings-4.7.tres').write_text(SETTINGS + 'export/android/java_sdk_path = ""\n')
        env = {k: v for k, v in os.environ.items() if not k.startswith('XDG_')}
        env['HOME'] = str(self.home)
        out = self.tmp / 'copy'
        out.mkdir()
        with patch.dict(os.environ, env, clear=True):
            godot = play_aab.godot_keep_adb(str(self.godot), out, Path('/jdk home'))
        self.assertEqual(Path(godot), out / 'godot')
        text = (out / 'editor_data/editor_settings-4.7.tres').read_text()
        self.assertIn(f'{KEY} = false', text)
        self.assertIn('export/android/java_sdk_path = "/jdk home"', text)
        # Without settings the build stops with the helper's reason (on stderr), not a traceback.
        (self.config / 'editor_settings-4.7.tres').unlink()
        other = self.tmp / 'other'
        other.mkdir()
        with patch.dict(os.environ, env, clear=True), self.assertRaises(play_aab.CheckError):
            play_aab.godot_keep_adb(str(self.godot), other, Path('/jdk'))


if __name__ == '__main__':
    unittest.main()
