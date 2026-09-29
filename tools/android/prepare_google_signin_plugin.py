#!/usr/bin/env python3
"""Install the tracked Sign in with Google plugin into Godot's ignored Android build template (idempotent)."""
from pathlib import Path
import shutil
ROOT = Path(__file__).resolve().parents[2]
build = ROOT / 'android/build'
if not (build / 'build.gradle').exists():
    raise SystemExit('Install the Godot Android build template first.')
target = build / 'src/main/java/com/sensen/googleauth'
target.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT / 'native/googleauth/android/GodotGoogleSignInPlugin.kt', target / 'GodotGoogleSignInPlugin.kt')
gradle = build / 'build.gradle'
g = gradle.read_text()
deps = ['androidx.credentials:credentials:1.3.0', 'androidx.credentials:credentials-play-services-auth:1.3.0',
        'com.google.android.libraries.identity.googleid:googleid:1.1.1', 'com.google.android.gms:play-services-base:18.5.0']
missing = [d for d in deps if d not in g]
if missing:
    block = '    // Sign in with Google (Credential Manager), GodotGoogleSignInPlugin.\n' + ''.join(f'    implementation "{d}"\n' for d in missing)
    g = g.replace('dependencies {\n', 'dependencies {\n' + block, 1)
    gradle.write_text(g)
p = build / 'src/main/AndroidManifest.xml'
s = p.read_text()
if 'org.godotengine.plugin.v2.GodotGoogleSignIn' not in s:
    s = s.replace('        <!-- Godot v2', '        <meta-data android:name="org.godotengine.plugin.v2.GodotGoogleSignIn"\n            android:value="com.sensen.googleauth.GodotGoogleSignInPlugin" />\n\n        <!-- Godot v2', 1)
    p.write_text(s)
print('GodotGoogleSignIn Android sources prepared')
