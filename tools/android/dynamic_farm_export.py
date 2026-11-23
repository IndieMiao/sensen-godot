"""Settings for the staged, read-only parcel preview (never edit the live project)."""
import re

PACKAGE = 'com.sensen.dynamicfarm.cardigan'
MAP_SCENE = 'res://scenes/dynamic_farm/dynamic_farm_map.tscn'
RAW_FILES = ('modules/dynamic_farm/map/config.json', 'assets/dynamic_farm/499-art-inventory.json',
             'assets/dynamic_farm/499-art-recipe.json', 'assets/dynamic_farm/499-edge-decor-v2.json',
             'assets/avatar/parts_manifest.json', 'assets/avatar/demo_denylist.json', 'assets/avatar/npc_only.json')


def replace_one(text, pattern, replacement):
    text, count = re.subn(pattern, replacement, text, flags=re.M)
    if count != 1:
        raise ValueError('unexpected dynamic farm source settings: ' + pattern)
    return text


def staged_project(text):
    # Net reads online_qa before the map scene starts. Retain the real autoloads.
    if re.search(r'^(?:network/online_qa|config/(?:use_custom_user_dir|custom_user_dir_name))=', text, re.M):
        raise ValueError('unexpected pre-existing QA overrides')
    text = replace_one(text, r'^run/main_scene="[^"]+"$', f'run/main_scene="{MAP_SCENE}"')
    text = replace_one(text, r'^\[application\]$', '[application]\nconfig/use_custom_user_dir=true\n'
                       'config/custom_user_dir_name="DynamicFarmCardigan"')
    text = replace_one(text, r'^\[sensen\]$', '[sensen]\nnetwork/online_qa=true')
    for key in ('base_url', 'mobile_base_url'):
        text = replace_one(text, rf'^network/{key}="[^"]+"$', f'network/{key}="http://127.0.0.1:9"')
    return text


def staged_preset(header, options):
    if 'export_filter="all_resources"' not in header.splitlines():
        raise ValueError('dynamic inventory needs all imported resources')

    def add_files(match):
        items = match[1].split(',')
        if 'mapbox_token.txt' not in items:
            raise ValueError('missing mapbox_token.txt in Android include_filter')
        return 'include_filter="' + ','.join(dict.fromkeys([*items, *RAW_FILES])) + '"'

    header = replace_one(header, r'^include_filter="([^"\n]*)"$', add_files)
    options = replace_one(options, r'^package/unique_name="[^"\n]+"$', f'package/unique_name="{PACKAGE}"')
    options = replace_one(options, r'^package/name="[^"\n]*"$', 'package/name="Dynamic Farm Preview"')
    return header, options
