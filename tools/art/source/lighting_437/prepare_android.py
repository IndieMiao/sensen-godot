"""Export only the isolated lighting review, never the game."""
import shutil
import prepare

qa = prepare.OUT / 'android-project'
shutil.copytree(prepare.QA, qa, dirs_exist_ok=True, ignore=shutil.ignore_patterns('.godot'))
(qa / 'export_presets.cfg').write_text('''[preset.0]
name="Android Lighting QA"
platform="Android"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter=""
[preset.0.options]
gradle_build/use_gradle_build=false
architectures/arm64-v8a=false
architectures/x86_64=true
version/code=43701
version/name="437-lighting-v1"
package/unique_name="com.sensen.lighting437qa"
package/name="Lighting Art QA"
package/signed=true
''')
print(qa)
