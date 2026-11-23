"""Settings for the staged parcel preview builds (never edit the live project).

`dynamic-farm` is the isolated preview: Journey endpoints are disabled. `dynamic-farm-internal` is the
internal test package (C-39): Journey points only at an approved isolated test service, and the map's
internal-only settings (C-32) are on. Neither carries an account or credential.
"""
import re
import struct
import sys

PACKAGE = 'com.sensen.dynamicfarm.cardigan'
INTERNAL_PACKAGE = 'com.sensen.dynamicfarm.internal'
PACKAGES = {'dynamic-farm': PACKAGE, 'dynamic-farm-internal': INTERNAL_PACKAGE}
MAP_SCENE = 'res://scenes/dynamic_farm/dynamic_farm_map.tscn'
RAW_FILES = ('modules/dynamic_farm/map/config.json', 'assets/dynamic_farm/499-art-inventory.json',
             'assets/dynamic_farm/499-art-recipe.json', 'assets/dynamic_farm/499-edge-decor-v2.json',
             'assets/avatar/parts_manifest.json', 'assets/avatar/demo_denylist.json', 'assets/avatar/npc_only.json')
DISABLED = 'http://127.0.0.1:9'
# The isolated Journey test service confirmed in C-38#46 (tailnet only). Anything else is refused:
# production, devserver, P0 and every other address.
APPROVED_TARGETS = ('https://aliyun-sh-plane.taildf0ff5.ts.net:8443/v1',)
# Read by the map (C-32); only the internal package may set them.
INTERNAL_SETTINGS = ('dynamic_farm/reselect', 'dynamic_farm/account_restore')
URL_KEYS = ('network/base_url', 'network/mobile_base_url')
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


def staged_project(text, target=None):
    # Net reads online_qa before the map scene starts, so it never boots or signs in anonymously.
    # Retain the real autoloads.
    if re.search(r'^(?:network/online_qa|config/(?:use_custom_user_dir|custom_user_dir_name)|dynamic_farm/\w+)[=.]',
                 text, re.M) or any(OVERRIDDEN.match(line) for line in text.splitlines()):
        raise ValueError('unexpected pre-existing QA overrides')
    url, user_dir, extra = DISABLED, 'DynamicFarmCardigan', ''
    if target is not None:
        url, user_dir = internal_target(target), 'DynamicFarmInternal'
        extra = ''.join(f'\n{key}=true' for key in INTERNAL_SETTINGS)
    text = replace_one(text, r'^run/main_scene="[^"]+"$', f'run/main_scene="{MAP_SCENE}"')
    text = replace_one(text, r'^\[application\]$', '[application]\nconfig/use_custom_user_dir=true\n'
                       f'config/custom_user_dir_name="{user_dir}"')
    text = replace_one(text, r'^\[sensen\]$', '[sensen]\nnetwork/online_qa=true' + extra)
    for key in URL_KEYS:
        text = replace_one(text, rf'^{key}="[^"]+"$', f'{key}="{url}"')
    return text


def staged_preset(header, options, internal=False):
    if 'export_filter="all_resources"' not in header.splitlines():
        raise ValueError('dynamic inventory needs all imported resources')

    def add_files(match):
        items = match[1].split(',')
        if 'mapbox_token.txt' not in items:
            raise ValueError('missing mapbox_token.txt in Android include_filter')
        return 'include_filter="' + ','.join(dict.fromkeys([*items, *RAW_FILES])) + '"'

    package, name = (INTERNAL_PACKAGE, 'Dynamic Farm Internal') if internal else (PACKAGE, 'Dynamic Farm Preview')
    header = replace_one(header, r'^include_filter="([^"\n]*)"$', add_files)
    options = replace_one(options, r'^package/unique_name="[^"\n]+"$', f'package/unique_name="{package}"')
    options = replace_one(options, r'^package/name="[^"\n]*"$', f'package/name="{name}"')
    return header, options


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
    unknown = {key for key in s if key.startswith('dynamic_farm/')} - set(INTERNAL_SETTINGS)
    urls = [s.get(key) for key in URL_KEYS]
    config = dict(variant=variant, online_qa=s.get('network/online_qa', False), journey_base_url=urls[0],
                  journey_mobile_base_url=urls[1], **{key.split('/')[1]: s.get(key, False) for key in INTERNAL_SETTINGS})
    if unknown:
        raise ValueError('unexpected dynamic farm setting in export')
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
