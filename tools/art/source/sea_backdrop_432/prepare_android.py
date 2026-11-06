"""Stage an isolated emulator project; never export the game or edit its presets."""
import shutil, sys
import prepare

if '--lake-revision' in sys.argv:
    prepare.OUT = prepare.ROOT / 'output/sea-backdrop-432-v11'
    prepare.QA = prepare.OUT / 'project'
qa = prepare.OUT / 'android-project'
shutil.copytree(prepare.QA, qa, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('.godot'))
(qa / 'export_presets.cfg').write_text('''[preset.0]
name="Android Sea Backdrop QA"
platform="Android"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter=""
[preset.0.options]
gradle_build/use_gradle_build=false
architectures/arm64-v8a=false
architectures/x86_64=true
version/code=43202
version/name="432-sea-backdrop-v1.1"
package/unique_name="com.sensen.seabackdrop432qa"
package/name="Sea Backdrop Art QA"
package/signed=true
''')
print(qa)
