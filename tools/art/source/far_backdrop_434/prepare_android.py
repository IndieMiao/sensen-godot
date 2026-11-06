"""Stage an isolated emulator project; never export the game or edit its presets."""
import shutil
import prepare

qa = prepare.OUT / 'android-project'
shutil.copytree(prepare.QA, qa, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('.godot'))
(qa / 'export_presets.cfg').write_text('''[preset.0]
name="Android Far Backdrop QA"
platform="Android"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter=""
[preset.0.options]
gradle_build/use_gradle_build=false
architectures/arm64-v8a=false
architectures/x86_64=true
version/code=43401
version/name="434-far-backdrop-v1"
package/unique_name="com.sensen.farbackdrop434qa"
package/name="Far Backdrop Art QA"
package/signed=true
''')
print(qa)
