"""Install the shared PermissionActivity (native/permission/android) into Godot's ignored Android build template.

The WebView and voice plugins ask for the microphone through it, never through GodotActivity (SGODOT-349).
Both prepare scripts call install(); it is idempotent."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
ACTIVITY = 'com.sensen.permission.PermissionActivity'


def install(build: Path) -> None:
    target = build / 'src/main/java/com/sensen/permission'
    target.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'native/permission/android/PermissionActivity.kt', target / 'PermissionActivity.kt')
    p = build / 'src/main/AndroidManifest.xml'
    s = p.read_text()
    if ACTIVITY not in s:
        entry = (f'        <activity android:name="{ACTIVITY}"\n'
                 '            android:exported="false"\n'
                 '            android:excludeFromRecents="true"\n'
                 '            android:configChanges="orientation|screenSize|screenLayout|keyboardHidden|uiMode|smallestScreenSize"\n'
                 '            android:theme="@android:style/Theme.Translucent.NoTitleBar" />\n\n')
        if '        <!-- Godot v2' not in s:
            raise SystemExit('AndroidManifest.xml: no Godot v2 plugin marker to place PermissionActivity before.')
        s = s.replace('        <!-- Godot v2', entry + '        <!-- Godot v2', 1)
        p.write_text(s)
