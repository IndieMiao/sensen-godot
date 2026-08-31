#!/usr/bin/env bash
# 重建 iOS G3 验证工程：导出 Xcode 工程（project-only）并注入 G3Spike.mm。
# 前置：Godot 4.7.2 + iOS 导出模板；签名走 Xcode 内登录的 Apple ID（免费个人团队即可，
# 首次需在 Xcode 打开工程选一次 Team，之后全程命令行）。
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

mkdir -p build/ios
godot --headless --path . --export-debug "iOS" build/ios/sensen.ipa

cp tools/ios/G3Spike.mm build/ios/sensen/G3Spike.mm
python3 - <<'PYEOF'
p = 'build/ios/sensen.xcodeproj/project.pbxproj'
t = open(p).read()
if 'G3Spike' in t:
    print('pbxproj 已含 G3Spike，跳过')
else:
    t = t.replace(
        '\t\t1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */ = {isa = PBXBuildFile; fileRef = 1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */; };',
        '\t\t1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */ = {isa = PBXBuildFile; fileRef = 1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */; };\n\t\tAA00000000000000000000B2 /* G3Spike.mm in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000B1 /* G3Spike.mm */; };', 1)
    t = t.replace(
        '\t\t1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.cpp; path = dummy.cpp; sourceTree = "<group>"; };',
        '\t\t1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.cpp; path = dummy.cpp; sourceTree = "<group>"; };\n\t\tAA00000000000000000000B1 /* G3Spike.mm */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; path = G3Spike.mm; sourceTree = "<group>"; };', 1)
    t = t.replace(
        '\t\t\t\t1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */,',
        '\t\t\t\t1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */,\n\t\t\t\tAA00000000000000000000B1 /* G3Spike.mm */,', 1)
    t = t.replace(
        '\t\t\t\t1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */,',
        '\t\t\t\t1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */,\n\t\t\t\tAA00000000000000000000B2 /* G3Spike.mm in Sources */,', 1)
    open(p, 'w').write(t)
    print('pbxproj 已注入 G3Spike')
PYEOF

cat <<'TIP'
构建装机（TEAM_ID 用 Xcode 选过一次 Team 后：
  grep -o "DEVELOPMENT_TEAM = [A-Z0-9]*" build/ios/sensen.xcodeproj/project.pbxproj）：
  cd build/ios && xcodebuild -project sensen.xcodeproj -scheme sensen -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath dd-dev -allowProvisioningUpdates \
    DEVELOPMENT_TEAM=<TEAM_ID> CODE_SIGN_STYLE=Automatic build
  xcrun devicectl device install app --device <UDID> dd-dev/Build/Products/Debug-iphoneos/sensen.app
  xcrun devicectl device process launch --device <UDID> com.sensen.mapg3
TIP
