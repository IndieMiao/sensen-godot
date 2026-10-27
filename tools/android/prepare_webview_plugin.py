#!/usr/bin/env python3
"""Install the tracked in-app WebView plugin into Godot's ignored Android build template."""
from pathlib import Path
import shutil
from permission_activity import install as install_permission_activity
ROOT = Path(__file__).resolve().parents[2]
build = ROOT / 'android/build'
if not (build / 'build.gradle').exists():
    raise SystemExit('Install the Godot Android build template first.')
target = build / 'src/main/java/com/sensen/webview'
target.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT / 'native/webview/android/GodotWebViewPlugin.kt', target / 'GodotWebViewPlugin.kt')
p = build / 'src/main/AndroidManifest.xml'
s = p.read_text()
# The page records through the WebView; the runtime grant is requested by the plugin.
for permission in ['INTERNET', 'RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS']:
    value = 'android.permission.' + permission
    if 'android:name="' + value + '"' not in s:
        s = s.replace('    <application\n', f'    <uses-permission android:name="{value}" />\n\n    <application\n', 1)
if 'org.godotengine.plugin.v2.GodotWebView' not in s:
    s = s.replace('        <!-- Godot v2', '        <meta-data android:name="org.godotengine.plugin.v2.GodotWebView"\n            android:value="com.sensen.webview.GodotWebViewPlugin" />\n\n        <!-- Godot v2', 1)
p.write_text(s)
install_permission_activity(build)  # the microphone is asked for there, never through GodotActivity (SGODOT-349)
print('GodotWebView Android sources prepared')
