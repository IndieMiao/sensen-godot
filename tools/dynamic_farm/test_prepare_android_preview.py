from pathlib import Path
import unittest,json
from prepare_android_preview import preview_project,verify_preview,parse_settings,preview_preset,USER_DIR,verify_data_config,DATASET,ICON_PATH,ICON_SVG,PACKAGE,ICON_MONO_PATH,ICON_MONO_SVG

PROJECT='''config_version=5
[application]
config/name="Gensen"
run/main_scene="res://scenes/city_select/city_select.tscn"
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
AppRouter="*res://modules/ui/app_router.gd"
Net="*res://modules/net/net_service.gd"
Voice="*res://modules/net/voice_session.gd"
[sensen]
network/base_url="https://production.invalid/v1"
network/mobile_base_url="https://production.invalid/preview/v1"
'''
ENTRY='res://scenes/dynamic_farm/dynamic_farm_map.tscn'

class PreviewGateChecks(unittest.TestCase):
    def test_offline_flag_preexists_and_autoloads_preserved(self):
        text,record=preview_project(PROJECT,ENTRY);settings=parse_settings(text)
        self.assertEqual(settings['sensen']['network/online_qa'],'true')
        self.assertEqual(settings['autoload'],parse_settings(PROJECT)['autoload'])
        self.assertEqual(record['user_dir'],USER_DIR)
        self.assertNotIn('production.invalid',text)
        self.assertNotIn('network/online_qa',PROJECT)
    def test_main_scene_only_cannot_pass(self):
        candidate=PROJECT.replace('res://scenes/city_select/city_select.tscn',ENTRY)
        self.assertRaisesRegex(ValueError,'offline gate',verify_preview,candidate,ENTRY,parse_settings(PROJECT)['autoload'])
    def test_false_or_string_true_rejected(self):
        text,_=preview_project(PROJECT,ENTRY)
        for wrong in ('false','"true"'):
            self.assertRaisesRegex(ValueError,'literal true',verify_preview,text.replace('network/online_qa=true','network/online_qa='+wrong),ENTRY,parse_settings(PROJECT)['autoload'])
    def test_missing_router_and_shared_userdata_rejected(self):
        self.assertRaisesRegex(ValueError,'missing required autoload',preview_project,PROJECT.replace('AppRouter="*res://modules/ui/app_router.gd"\n',''),ENTRY)
        text,_=preview_project(PROJECT,ENTRY);self.assertRaisesRegex(ValueError,'shared user data',verify_preview,text.replace(USER_DIR,'gensen'),ENTRY,parse_settings(PROJECT)['autoload'])
    def test_duplicate_override_rejected(self):
        text,_=preview_project(PROJECT,ENTRY)
        self.assertRaisesRegex(ValueError,'duplicate setting',parse_settings,text+'network/online_qa=false\n')
    def test_invalid_entry_rejected(self):
        self.assertRaises(ValueError,preview_project,PROJECT,'res://scenes/p0/p0_boot.tscn')
    def test_3d_host_is_not_main(self):
        self.assertRaisesRegex(ValueError,'3D host',preview_project,PROJECT,'res://scenes/dynamic_farm/dynamic_farm_host.tscn')
    def test_readonly_data_config_pins(self):
        origin='https://synthetic-only.trycloudflare.com';pin='a'*64
        config={'base_url':origin,'dataset_version':DATASET,'manifest_sha256':pin,'building_source':'mapbox'}
        self.assertEqual(verify_data_config(json.dumps(config),origin,pin),config)
        for key,value in [('base_url','https://other.trycloudflare.com'),('dataset_version','sf-parcel-20261117-v3'),('manifest_sha256','b'*64),('building_source','unexpected'),('manifest_path','manifest.json')]:
            with self.subTest(key=key):
                bad={**config,key:value};self.assertRaises(ValueError,verify_data_config,json.dumps(bad),origin,pin)
        duplicate=json.dumps(config)[:-1]+',"base_url":"https://other.trycloudflare.com"}'
        self.assertRaisesRegex(ValueError,'duplicate',verify_data_config,duplicate,origin,pin)
    def test_autoload_binding_rejects_wrong_paths_and_non_singleton(self):
        cases=[
            ('Net="*res://modules/net/net_service.gd"','Net="*res://modules/net/other_net.gd"'),
            ('Net="*res://modules/net/net_service.gd"','Net="res://modules/net/net_service.gd"'),
            ('Avatar="*res://modules/avatar/avatar_service.gd"','Avatar="*res://modules/avatar/other.gd"'),
            ('AppRouter="*res://modules/ui/app_router.gd"','AppRouter="*res://modules/ui/other.gd"'),
        ]
        for old,new in cases:
            with self.subTest(declaration=new):
                candidate=PROJECT.replace(old,new)
                self.assertRaisesRegex(ValueError,'autoload binding',preview_project,candidate,ENTRY)
    def test_autoload_binding_accepts_original_and_preserves_other_symbols(self):
        original=PROJECT.replace('[sensen]','Helper="*res://modules/isolated_helper.gd"\n[sensen]')
        text,facts=preview_project(original,ENTRY)
        self.assertEqual(parse_settings(text)['autoload'],parse_settings(original)['autoload'])
        self.assertIn('Helper',facts['autoload_symbols'])
    def test_distinct_icon_gate_and_launcher_references(self):
        text,_=preview_project(PROJECT,ENTRY)
        self.assertEqual(parse_settings(text)['application']['config/icon'],'"res://'+ICON_PATH+'"')
        bad=text.replace('res://'+ICON_PATH,'res://icon.svg')
        self.assertRaisesRegex(ValueError,'distinct QA icon',verify_preview,bad,ENTRY,parse_settings(PROJECT)['autoload'])
        self.assertNotIn('<text',ICON_SVG)
        self.assertIn('<path',ICON_SVG)
        self.assertNotIn('<text',ICON_MONO_SVG)
        self.assertNotIn(PACKAGE,['com.sensen.p0demo','com.sensen.geofarmdemo','com.sensen.journeypreview'])
        preset='[preset.2]\nname="Android P0"\n[preset.2.options]\npackage/unique_name="com.sensen.p0demo"\n'
        settings=parse_settings(preview_preset(preset,2026111901))['preset.0.options']
        self.assertEqual(settings['launcher_icons/main_192x192'],'"res://'+ICON_PATH+'"')
        self.assertEqual(settings['launcher_icons/adaptive_foreground_432x432'],'"res://'+ICON_PATH+'"')
        self.assertEqual(settings['launcher_icons/adaptive_monochrome_432x432'],'"res://'+ICON_MONO_PATH+'"')
    def test_dynamic_json_included_without_truncating_full_resources(self):
        original='[preset.2]\nname="Android P0"\ninclude_filter="mapbox_token.txt,assets/p0/*.json"\nexport_filter="selected_resources"\nscript_export_mode=2\n[preset.2.options]\npackage/unique_name="com.sensen.p0demo"\n'
        settings=parse_settings(preview_preset(original,2026111901))['preset.0']
        include=json.loads(settings['include_filter']).split(',')
        self.assertTrue(set(['mapbox_token.txt','assets/p0/*.json','assets/dynamic_farm/*.json','modules/dynamic_farm/map/config.json']).issubset(include))
        self.assertEqual(settings['export_filter'],'"all_resources"')
        self.assertEqual(settings['script_export_mode'],'0')
    def test_unique_isolated_export_preset(self):
        original='''[preset.2]
name="Android P0"
platform="Android"
custom_features="p0"
[preset.2.options]
package/unique_name="com.sensen.p0demo"
version/code=1
[preset.3]
name="Production other"
'''
        result=preview_preset(original,2026111901);settings=parse_settings(result)
        self.assertEqual(set(settings),{'preset.0','preset.0.options'})
        self.assertEqual(settings['preset.0.options']['package/unique_name'],'"com.sensen.dynamicfarmqa"')
        self.assertNotIn('com.sensen.p0demo',result)

if __name__=='__main__':unittest.main(verbosity=2)
