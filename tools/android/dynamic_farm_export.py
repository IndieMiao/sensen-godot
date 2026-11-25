"""Settings for the staged parcel preview builds (never edit the live project).

`dynamic-farm` is the isolated preview: Journey endpoints are disabled. `dynamic-farm-internal` is the
internal test package (C-39): Journey points only at an approved isolated test service, and the map's
internal-only settings (C-32; install-and-play guest sign-in, C-100) are on. `dynamic-farm-release` is the invite-only release package (C-98): the
preview's package, Journey fixed to the US West dynamic farm production service,
one's own farm and the saved sign-in on, reselect off. None carries an account or credential.

Nothing a player sees carries "sensen" (C-142, the owner's C-101#91): the package names, display names, the
launcher icon (farm-dev's P0 icon, tools/app_icon/android, owner's C-142#7) and the delivered APK file names.
The domains, the `[sensen]` setting section and code identifiers are internal and stay.
"""
import re
import struct
import sys

# The owner's package name (C-142#7, Q-171). It replaced com.sensen.dynamicfarm.cardigan, so 0.4.x installs are not
# upgraded in place: testers uninstall the old package once. The internal package keeps its own name so it can sit
# next to the release package on one phone.
PACKAGE = 'com.gensen.mapfarm'
INTERNAL_PACKAGE = 'com.gensen.mapfarm.internal'
PACKAGES = {'dynamic-farm': PACKAGE, 'dynamic-farm-internal': INTERNAL_PACKAGE, 'dynamic-farm-release': PACKAGE}
NAMES = {'dynamic-farm': 'Dynamic Farm Preview', 'dynamic-farm-internal': 'Dynamic Farm Internal',
         'dynamic-farm-release': 'Dynamic Farm'}
# Delivered file names: <prefix>-<version name>-<version code>-<commit 8>-<unsigned|signed>.apk (C-142).
FILE_PREFIXES = {'dynamic-farm': 'mapfarm-preview', 'dynamic-farm-internal': 'mapfarm-internal',
                 'dynamic-farm-release': 'mapfarm'}
# farm-dev's P0 launcher icon (bcefa351, 0.3.4), the same files as the Android P0 / Play presets.
LAUNCHER_ICONS = {key: f'res://tools/app_icon/android/{key}.png' for key in (
    'main_192x192', 'adaptive_foreground_432x432', 'adaptive_background_432x432', 'adaptive_monochrome_432x432')}
MAP_SCENE = 'res://scenes/dynamic_farm/dynamic_farm_map.tscn'
RAW_FILES = ('modules/dynamic_farm/map/config.json', 'assets/dynamic_farm/499-art-inventory.json',
             'assets/dynamic_farm/499-art-recipe.json', 'assets/dynamic_farm/499-edge-decor-v2.json',
             'assets/avatar/parts_manifest.json', 'assets/avatar/demo_denylist.json', 'assets/avatar/npc_only.json',
             # Settings › Licenses (C-128): the main farm's credits and the texts they open.
             'assets/p0/legal/licenses.json', 'assets/p0/legal/mapbox-maps-android-LICENSE.md',
             'assets/p0/legal/odbl-1.0.txt', 'assets/p0/legal/cc-by-4.0.txt', 'assets/p0/legal/unicode-license-v3.txt')
DISABLED = 'http://127.0.0.1:9'
# The isolated Journey test service confirmed in C-38#46 (tailnet only). Anything else is refused:
# production, devserver, P0 and every other address.
APPROVED_TARGETS = ('https://aliyun-sh-plane.taildf0ff5.ts.net:8443/v1',)
# The dynamic farm production service in US West (C-96 materials, C-97 entry). The release package uses
# exactly this address; it is not a build argument.
RELEASE_TARGET = 'https://farm.sensenjoy.cn/dynamicfarm/v1'
# Read by the map (C-32; own_farm: C-34 Q-72; guest_play: C-100); only the internal package may set all of them.
# guest_play signs in anonymously when no account was restored (install-and-play); the server decides whether a
# guest may claim and farm (PARCEL_GUEST_WRITES). The release package does not carry it until the owner opens it.
GUEST_PLAY = 'dynamic_farm/guest_play'
INTERNAL_SETTINGS = ('dynamic_farm/reselect', 'dynamic_farm/account_restore', 'dynamic_farm/own_farm', GUEST_PLAY)
# The release package: one's own farm and the saved sign-in, never reselect; the account panel only signs in
# with an invite account (C-98, server ACCOUNT_SIGNUP=closed). Only the release package may set invite_only.
INVITE_ONLY = 'account/invite_only'
RELEASE_SETTINGS = ('dynamic_farm/account_restore', 'dynamic_farm/own_farm', INVITE_ONLY)
URL_KEYS = ('network/base_url', 'network/mobile_base_url')
# The 0.4.1 preview's user directory, kept by the release package (C-116). Since the package name changed (C-142)
# nothing is upgraded in place any more, but the name is internal (never shown) and stays as it is.
PREVIEW_USER_DIR = 'DynamicFarmCardigan'
USER_DIR_KEYS = ('application/config/use_custom_user_dir', 'application/config/custom_user_dir_name')
VARIANTS = ('android', *PACKAGES)
# A feature-tag override (e.g. `network/base_url.mobile=`) would win at run time over the staged value.
OVERRIDDEN = re.compile(r'^(?:sensen/)?network/(?:online_qa|base_url|mobile_base_url)\.')


def replace_one(text, pattern, replacement):
    text, count = re.subn(pattern, replacement, text, flags=re.M)
    if count != 1:
        raise ValueError('unexpected dynamic farm source settings: ' + pattern)
    return text


def internal_target(url):
    # Exact match only: no normalisation, so a lookalike host, port, path or userinfo cannot pass.
    if url not in APPROVED_TARGETS:
        raise ValueError('unapproved internal Journey target')
    return url


def staged_project(text, target=None, release=False):
    # Net reads online_qa before the map scene starts, so it never boots or signs in anonymously.
    # Retain the real autoloads.
    if re.search(r'^(?:network/online_qa|config/(?:use_custom_user_dir|custom_user_dir_name)|dynamic_farm/\w+|'
                 r'account/invite_only)[=.]', text, re.M) or any(OVERRIDDEN.match(line) for line in text.splitlines()):
        raise ValueError('unexpected pre-existing QA overrides')
    url, user_dir, extra, variant = DISABLED, PREVIEW_USER_DIR, '', 'dynamic-farm'
    if release:
        # Same package and user directory as the preview; no target can be chosen.
        if target is not None:
            raise ValueError('the release package has a fixed target')
        url, extra = RELEASE_TARGET, ''.join(f'\n{key}=true' for key in RELEASE_SETTINGS)
        variant = 'dynamic-farm-release'
    elif target is not None:
        url, user_dir = internal_target(target), 'DynamicFarmInternal'
        extra = ''.join(f'\n{key}=true' for key in INTERNAL_SETTINGS)
        variant = 'dynamic-farm-internal'
    # The project's own name (SensenAvatar) would otherwise travel in project.binary (C-142).
    text = replace_one(text, r'^config/name="[^"\n]*"$', f'config/name="{NAMES[variant]}"')
    text = replace_one(text, r'^run/main_scene="[^"]+"$', f'run/main_scene="{MAP_SCENE}"')
    text = replace_one(text, r'^\[application\]$', '[application]\nconfig/use_custom_user_dir=true\n'
                       f'config/custom_user_dir_name="{user_dir}"')
    text = replace_one(text, r'^\[sensen\]$', '[sensen]\nnetwork/online_qa=true' + extra)
    for key in URL_KEYS:
        text = replace_one(text, rf'^{key}="[^"]+"$', f'{key}="{url}"')
    return text


def staged_preset(header, options, variant):
    if 'export_filter="all_resources"' not in header.splitlines():
        raise ValueError('dynamic inventory needs all imported resources')

    def add_files(match):
        items = match[1].split(',')
        if 'mapbox_token.txt' not in items:
            raise ValueError('missing mapbox_token.txt in Android include_filter')
        return 'include_filter="' + ','.join(dict.fromkeys([*items, *RAW_FILES])) + '"'

    if variant not in PACKAGES:
        raise ValueError('unknown package variant')
    package, name = PACKAGES[variant], NAMES[variant]
    header = replace_one(header, r'^include_filter="([^"\n]*)"$', add_files)
    options = replace_one(options, r'^package/unique_name="[^"\n]+"$', f'package/unique_name="{package}"')
    options = replace_one(options, r'^package/name="[^"\n]*"$', f'package/name="{name}"')
    for key, path in LAUNCHER_ICONS.items():
        options = replace_one(options, rf'^launcher_icons/{key}="[^"\n]*"$', f'launcher_icons/{key}="{path}"')
    return header, options


def apk_filename(variant, version_name, version_code, commit, signed=False):
    """The delivered file name of a dynamic farm APK; never carries "sensen" (C-142)."""
    if variant not in FILE_PREFIXES:
        raise ValueError('unknown package variant')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', str(version_name)) or not re.fullmatch(r'[0-9]+', str(version_code)):
        raise ValueError('unexpected version')
    if not re.fullmatch(r'[0-9a-f]{8,40}', commit):
        raise ValueError('expected a commit SHA')
    state = 'signed' if signed else 'unsigned'
    return f'{FILE_PREFIXES[variant]}-{version_name}-{version_code}-{commit[:8]}-{state}.apk'


def project_settings(blob):
    """Read Godot's exported `project.binary` (ECFG). Bool, int and string values; others are None."""
    def take(size):
        nonlocal at
        if at + size > len(blob):
            raise ValueError('truncated project.binary')
        at += size
        return blob[at - size:at]

    at = 0
    if take(4) != b'ECFG':
        raise ValueError('not an exported project.binary')
    settings = {}
    for _ in range(struct.unpack('<I', take(4))[0]):
        key = take(struct.unpack('<I', take(4))[0]).decode()
        value = take(struct.unpack('<I', take(4))[0])
        kind, flags = struct.unpack('<HH', value[:4]) if len(value) >= 4 else (None, 0)
        if key in settings:
            raise ValueError('duplicate project setting')
        if kind == 1 and len(value) == 8:
            settings[key] = struct.unpack('<I', value[4:])[0] != 0
        elif kind == 2 and len(value) in (8, 12):
            settings[key] = struct.unpack('<q' if flags & 1 else '<i', value[4:])[0]
        elif kind == 4 and len(value) >= 8:
            size = struct.unpack('<I', value[4:8])[0]
            if len(value) != 8 + size + -size % 4:
                raise ValueError('malformed project.binary string')
            settings[key] = value[8:8 + size].decode()
        else:
            settings[key] = None
    if at != len(blob):
        raise ValueError('trailing data in project.binary')
    return settings


def exported_config(settings, variant):
    """Check the exported Journey settings for a variant and return them for the build record."""
    if variant not in VARIANTS:
        raise ValueError('unknown package variant')
    if any(OVERRIDDEN.match(key) for key in settings):
        raise ValueError('feature-tag override of a Journey setting in export')
    s = {key[len('sensen/'):]: value for key, value in settings.items() if key.startswith('sensen/')}
    unknown = ({key for key in s if key.startswith('dynamic_farm/')} - set(INTERNAL_SETTINGS) |
               {key for key in s if key.startswith('account/')} - {INVITE_ONLY})
    urls = [s.get(key) for key in URL_KEYS]
    config = dict(variant=variant, online_qa=s.get('network/online_qa', False), journey_base_url=urls[0],
                  journey_mobile_base_url=urls[1], invite_only=s.get(INVITE_ONLY, False),
                  **{key.split('/')[1]: s.get(key, False) for key in INTERNAL_SETTINGS})
    if unknown:
        raise ValueError('unexpected dynamic farm setting in export')
    if variant == 'dynamic-farm-release':
        if config['online_qa'] is not True or any(s.get(key) is not True for key in RELEASE_SETTINGS):
            raise ValueError('release package must keep Net from signing in anonymously and enable its settings')
        if 'dynamic_farm/reselect' in s:
            raise ValueError('reselect in the release package')
        if GUEST_PLAY in s:
            raise ValueError('install-and-play in the release package')
        if urls != [RELEASE_TARGET, RELEASE_TARGET]:
            raise ValueError('release package must point only at the production service')
        if [settings.get(key) for key in USER_DIR_KEYS] != [True, PREVIEW_USER_DIR]:
            raise ValueError('release package must keep the preview user directory')
        return config
    if INVITE_ONLY in s:
        raise ValueError('invite-only sign-in outside the release package')
    if RELEASE_TARGET in urls:
        raise ValueError('production dynamic farm service outside the release package')
    internal = variant == 'dynamic-farm-internal'
    if internal:
        if config['online_qa'] is not True or any(s.get(key) is not True for key in INTERNAL_SETTINGS):
            raise ValueError('internal package must keep Net isolated and enable its internal settings')
        if urls[0] != urls[1] or urls[0] not in APPROVED_TARGETS:
            raise ValueError('internal package must point only at the approved target')
        return config
    if any(key in s for key in INTERNAL_SETTINGS):
        raise ValueError('internal-only settings in a non-internal package')
    if any(url in APPROVED_TARGETS for url in urls):
        raise ValueError('internal target in a non-internal package')
    if variant == 'dynamic-farm' and (config['online_qa'] is not True or urls != [DISABLED, DISABLED]):
        raise ValueError('isolated preview must keep Journey disabled')
    if variant == 'android' and config['online_qa'] is not False:
        raise ValueError('release-configuration package must not be isolated for QA')
    return config


if __name__ == '__main__':
    # Early check for build_worker_apk.sh, before any staging or tool start.
    try:
        if len(sys.argv) != 3 or sys.argv[1] != 'check-target':
            raise ValueError('usage: dynamic_farm_export.py check-target URL')
        internal_target(sys.argv[2])
    except ValueError as exc:
        raise SystemExit(str(exc))
