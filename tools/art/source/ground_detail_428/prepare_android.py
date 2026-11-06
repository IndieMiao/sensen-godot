"""Isolated static-material smoke APK, not a production game build."""
from pathlib import Path
import shutil
import prepare

def main():
 qa=prepare.OUT/'android-project'
 shutil.copytree(prepare.QA,qa,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.godot'))
 (qa/'export_presets.cfg').write_text('''[preset.0]
name="Android Ground Kit QA"
platform="Android"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
[preset.0.options]
gradle_build/use_gradle_build=false
architectures/arm64-v8a=false
architectures/x86_64=true
version/code=42801
version/name="428-ground-v1"
package/unique_name="com.sensen.groundkit428qa"
package/name="Ground Kit Art QA"
package/signed=true
''')
 print(qa)
if __name__=='__main__':main()
