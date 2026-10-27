#!/usr/bin/env python3
"""Install the tracked crop-ready notification plugin (SGODOT-350) into Godot's ignored Android build template."""
from pathlib import Path
import shutil
ROOT = Path(__file__).resolve().parents[2]
build = ROOT / 'android/build'
if not (build / 'build.gradle').exists():
    raise SystemExit('Install the Godot Android build template first.')
src = ROOT / 'native/notify/android'
target = build / 'src/main/java/com/sensen/notify'
target.mkdir(parents=True, exist_ok=True)
shutil.copyfile(src / 'GodotNotifyPlugin.kt', target / 'GodotNotifyPlugin.kt')
shutil.copytree(src / 'res', build / 'res', dirs_exist_ok=True)   # the small icon ic_notify, per density
p = build / 'src/main/AndroidManifest.xml'
s = p.read_text()
value = 'android.permission.POST_NOTIFICATIONS'
if 'android:name="' + value + '"' not in s:
    s = s.replace('    <application\n', f'    <uses-permission android:name="{value}" />\n\n    <application\n', 1)
if 'com.sensen.notify.NotifyReceiver' not in s:
    s = s.replace('        <!-- Godot v2', '        <receiver android:name="com.sensen.notify.NotifyReceiver" android:exported="false" />\n\n        <!-- Godot v2', 1)
if 'org.godotengine.plugin.v2.GodotNotify' not in s:
    s = s.replace('        <!-- Godot v2', '        <meta-data android:name="org.godotengine.plugin.v2.GodotNotify"\n            android:value="com.sensen.notify.GodotNotifyPlugin" />\n\n        <!-- Godot v2', 1)
p.write_text(s)
print('GodotNotify Android sources prepared')
