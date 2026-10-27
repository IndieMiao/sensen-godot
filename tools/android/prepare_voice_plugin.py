#!/usr/bin/env python3
"""Install tracked voice sources into Godot's ignored Android build template."""
from pathlib import Path
import shutil
from permission_activity import install as install_permission_activity
ROOT = Path(__file__).resolve().parents[2]
build = ROOT / 'android/build'
if not (build / 'build.gradle').exists():
    raise SystemExit('Install the Godot Android build template first.')
target = build / 'src/main/java/com/sensen/voice'
target.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT / 'native/voice/android/GodotVoicePlugin.kt', target / 'GodotVoicePlugin.kt')
p = build / 'build.gradle'
s = p.read_text()
if "https://jitpack.io" not in s:
    s = s.replace('        mavenCentral()\n', '        mavenCentral()\n        maven { url "https://jitpack.io"; content { includeGroup "com.github.davidliu" } }\n', 1)
marker = '    // Sensen party voice: official SDK, pinned for reproducible builds.\n'
if marker not in s:
    s = s.replace('dependencies {\n', 'dependencies {\n' + marker + '    implementation "io.livekit:livekit-android:2.28.2"\n', 1)
p.write_text(s)
p = build / 'src/main/AndroidManifest.xml'
s = p.read_text()
for permission in ['RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS', 'BLUETOOTH_CONNECT']:
    value = 'android.permission.' + permission
    if 'android:name="' + value + '"' not in s:
        s = s.replace('    <application\n', f'    <uses-permission android:name="{value}" />\n\n    <application\n', 1)
if 'org.godotengine.plugin.v2.GodotVoice' not in s:
    s = s.replace('        <!-- Godot v2', '        <meta-data android:name="org.godotengine.plugin.v2.GodotVoice"\n            android:value="com.sensen.voice.GodotVoicePlugin" />\n\n        <!-- Godot v2', 1)
p.write_text(s)
install_permission_activity(build)  # the microphone is asked for there, never through GodotActivity (SGODOT-349)
print('GodotVoice Android sources and SDK prepared')
