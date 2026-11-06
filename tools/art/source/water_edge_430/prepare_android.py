from pathlib import Path
import shutil,prepare
qa=prepare.OUT/'android-project'
shutil.copytree(prepare.QA,qa,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.godot'))
for name in ['review.gd','verify.gd']:shutil.copy2(prepare.SRC/name,qa/name)
(qa/'export_presets.cfg').write_text('''[preset.0]
name="Android Water Edge QA"
platform="Android"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter=""
[preset.0.options]
gradle_build/use_gradle_build=false
architectures/arm64-v8a=false
architectures/x86_64=true
version/code=43002
version/name="430-water-edge-v11"
package/unique_name="com.sensen.wateredge430qa"
package/name="Water Edge Art QA"
package/signed=true
''')
print(qa)
