import os
from pathlib import Path
import platform
import re
import subprocess
import tempfile
import unittest

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

    def run_helper(self):
        out = self.tmp / 'copy'
        out.mkdir()
        env = {k: v for k, v in os.environ.items() if not k.startswith('XDG_')}
        env['HOME'] = str(self.home)
        result = subprocess.run(['bash', '-c', 'set -euo pipefail; source "$0"; p0_godot_keep_adb "$1" "$2"; echo "$P0_GODOT"',
                                 str(HELPER), str(self.godot), str(out)],
                                env=env, check=True, capture_output=True, text=True)
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

    def test_without_account_settings_only_the_adb_setting_is_written(self):
        out, _ = self.run_helper()
        self.assertEqual((out / 'editor_data/editor_settings-4.7.tres').read_text(),
                         f'[gd_resource type="EditorSettings" format=3]\n\n[resource]\n{KEY} = false\n')

    def test_p0_scripts_run_godot_only_through_the_copy(self):
        for name in ('build_demo_apk.sh', 'android_p0.sh'):
            text = (ROOT / 'tools/p0' / name).read_text()
            self.assertIn('p0_godot_keep_adb ', text, name)
            runs = re.findall(r'^\s*(\S+) --headless', text, re.M)
            self.assertEqual(set(runs), {'"$P0_GODOT"'}, name)


if __name__ == '__main__':
    unittest.main()
