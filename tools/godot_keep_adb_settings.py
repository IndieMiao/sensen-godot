#!/usr/bin/env python3
"""Keep a Godot editor run from stopping the shared adb server (C-210) or restarting it with other keys (C-213).

Godot's editor setting export/android/shutdown_adb_on_exit defaults to true. Any editor-mode run
(--import, --export-*, --editor) of a project with a runnable Android preset ends with
`<android_sdk_path>/platform-tools/adb kill-server`; android_sdk_path defaults to $ANDROID_HOME and
adb honours $ANDROID_ADB_SERVER_PORT, so on the Cardigan workers it stops the shared server on 5137
(mac-mini: the owner's tablet and every session's emulator). The hosts set the key to false in the
account's settings, but a run under a private HOME (or private XDG_CONFIG_HOME on Linux) reads other
settings: fresh ones, where the default applies. Script-mode runs (--script, running a scene) open no
editor settings and never call adb. The key does not stop the editor from polling `adb devices` while a
runnable Android preset exists (the game project's own presets are runnable), which starts a server under
the run's HOME if the shared one is down. adb reads its keys from $HOME/.android only (it ignores
ANDROID_USER_HOME), so such a server would offer fresh keys and the devices would be unauthorized
(SEN-C-186#16); a private HOME's adbkey and adbkey.pub therefore link to the account's (C-213).

Run this right before an editor-mode run, with the same environment and Godot binary:

    python3 tools/godot_keep_adb_settings.py [GODOT]      # default: $GODOT_BIN, else godot on PATH

It finds the settings file that Godot will read (as Godot's EditorPaths do) and:
  * private settings (not the account's own location): sets the key to false, creating the file if
    needed (from the newest earlier same-major version's settings when there are some, as Godot
    itself would migrate them);
  * the account's own settings, or a self-contained Godot's settings: never written; a note on
    stderr if the key is not false there.
When $HOME/.android is not $SENSEN_ADB_KEY_DIR (default: the account's ~/.android) it also makes
$HOME/.android/adbkey and adbkey.pub symlinks to the files there, replacing private ones; the key directory
itself is never written. SENSEN_ADB_KEY_DIR=none turns this off; a note on stderr if it has no keys.
Exit status 0 unless Godot or its settings cannot be read, in which case nothing is written.
"""
import os
import platform
import pwd
import re
import shutil
import subprocess
import sys
from pathlib import Path

KEY = 'export/android/shutdown_adb_on_exit'
ADB_KEYS = ('adbkey', 'adbkey.pub')
MINIMAL = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'


def resolve_godot(name):
    found = shutil.which(name)
    if not found:
        raise SystemExit(f'godot_keep_adb_settings: Godot not found: {name}')
    return Path(os.path.realpath(found))


def godot_version(binary):
    out = subprocess.run([str(binary), '--version'], capture_output=True, text=True, timeout=60).stdout.strip()
    m = re.match(r'(\d+)\.(\d+)', out)
    if not m:
        raise SystemExit(f'godot_keep_adb_settings: unexpected Godot version: {out!r}')
    return int(m[1]), int(m[2])


def settings_dir(binary, env, system):
    """(directory, kind): kind is 'self_contained' or 'user'. Mirrors Godot 4.7's EditorPaths/OS."""
    exe = binary.parent
    if system == 'Darwin' and exe.name == 'MacOS' and exe.parent.name == 'Contents':
        exe = exe.parent.parent.parent  # beside the .app
    if (exe / '._sc_').exists() or (exe / '_sc_').exists():
        return exe / 'editor_data', 'self_contained'
    home = env.get('HOME', '')
    if system == 'Darwin':  # Godot reads $HOME/Library/Application Support even with XDG_* set
        return Path(home) / 'Library/Application Support/Godot', 'user'
    config = env.get('XDG_CONFIG_HOME', '')
    if not config.startswith('/'):
        config = str(Path(home) / '.config')
    return Path(config) / 'godot', 'user'


def account_settings_dir(account_home, system):
    if system == 'Darwin':
        return Path(account_home) / 'Library/Application Support/Godot'
    return Path(account_home) / '.config/godot'


def same_path(a, b):
    return os.path.realpath(a) == os.path.realpath(b)


def key_of(line):
    return line.split('=', 1)[0].strip()


def is_false(lines):
    values = [line.split('=', 1)[1].strip() for line in lines if '=' in line and key_of(line) == KEY]
    return values == ['false']


def ensure(binary, env, account_home, system, log=sys.stderr):
    """Returns 'written', 'ok' or 'not_private' (the latter with a note on log when the key is not false)."""
    major, minor = godot_version(binary)
    directory, kind = settings_dir(binary, env, system)
    target = directory / f'editor_settings-{major}.{minor}.tres'
    private = kind == 'user' and not same_path(directory, account_settings_dir(account_home, system))
    source = target
    if not target.is_file():
        earlier = sorted((int(m[1]), p) for p in directory.glob(f'editor_settings-{major}.*.tres')
                         if (m := re.fullmatch(rf'editor_settings-{major}\.(\d+)\.tres', p.name)) and int(m[1]) < minor)
        source = earlier[-1][1] if earlier else None
    lines = source.read_text().splitlines() if source else MINIMAL.splitlines()
    if source is target and is_false(lines):
        return 'ok'
    if not private:
        whose = 'a self-contained Godot' if kind != 'user' else "the account's own settings"
        port = env.get('ANDROID_ADB_SERVER_PORT') or '5037'
        print(f'godot_keep_adb_settings: note: {KEY} is not false in {target} ({whose}, not changed here); '
              f'an editor run stops the adb server on port {port}', file=log)
        return 'not_private'
    if '[resource]' not in lines:
        raise SystemExit(f'godot_keep_adb_settings: no [resource] section in {source}')
    lines = [line for line in lines if key_of(line) != KEY]
    at = lines.index('[resource]') + 1
    lines[at:at] = [f'{KEY} = false']
    directory.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + '.tmp')
    tmp.write_text('\n'.join(lines) + '\n')
    os.replace(tmp, target)
    print(f'godot_keep_adb_settings: {KEY} = false in {target}', file=log)
    return 'written'


def link_adb_keys(env, account_home, log=sys.stderr):
    """Returns 'linked', 'ok', 'not_private', 'off' or 'no_keys' (the latter with a note on log)."""
    source = env.get('SENSEN_ADB_KEY_DIR') or str(Path(account_home) / '.android')
    if source == 'none':
        return 'off'
    directory = Path(env.get('HOME') or account_home) / '.android'  # adb falls back to the passwd entry too
    if same_path(directory, source):
        return 'not_private'
    source = Path(os.path.realpath(source))
    if not all((source / name).is_file() for name in ADB_KEYS):
        print(f'godot_keep_adb_settings: note: no adbkey and adbkey.pub in {source}; an adb server started '
              f'under HOME={directory.parent} uses keys of its own', file=log)
        return 'no_keys'
    if all(os.path.islink(directory / name) and os.readlink(directory / name) == str(source / name) for name in ADB_KEYS):
        return 'ok'
    directory.mkdir(mode=0o750, parents=True, exist_ok=True)
    for name in ADB_KEYS:
        tmp = directory / f'{name}.tmp'
        tmp.unlink(missing_ok=True)
        tmp.symlink_to(source / name)
        os.replace(tmp, directory / name)
    print(f'godot_keep_adb_settings: {directory}/adbkey and adbkey.pub link to {source}', file=log)
    return 'linked'


def main(argv):
    if len(argv) > 2 or (len(argv) == 2 and argv[1].startswith('-')):
        raise SystemExit('usage: godot_keep_adb_settings.py [GODOT]')
    name = argv[1] if len(argv) == 2 else (os.environ.get('GODOT_BIN') or 'godot')
    account_home = pwd.getpwuid(os.getuid()).pw_dir
    ensure(resolve_godot(name), os.environ, account_home, platform.system())
    link_adb_keys(os.environ, account_home)


if __name__ == '__main__':
    main(sys.argv)
