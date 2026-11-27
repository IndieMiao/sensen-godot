#!/usr/bin/env bash
# 重建 iOS 工程：导出 Xcode 工程（project-only）并注入地图垫底层。
# 注入物：G3Spike.mm（启动引导）+ MapUnderlay.swift（Mapbox 垫底 + UDP 桥）
#        + AppleSignIn.swift（Sign in with Apple 桥 + entitlement，见 inject_apple_sign_in.py）
#        + Mapbox SPM 依赖（mapbox-maps-ios 11.x）。
# 前置：Godot 4.7.2 + iOS 导出模板；Xcode 已登录 Apple ID（免费个人团队即可，
# 首次在 Xcode 打开工程选一次 Team 拿到 TEAM_ID，之后全程命令行）。
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

mkdir -p build/ios
# 编辑器导出结束时不关共享 adb 服务（C-210；工程里有可运行的安卓预设，iOS 导出也会关）。
python3 -I tools/godot_keep_adb_settings.py godot
godot --headless --path . --export-debug "iOS" build/ios/sensen.ipa

cp tools/ios/G3Spike.mm build/ios/sensen/G3Spike.mm
cp tools/ios/MapUnderlay.swift build/ios/sensen/MapUnderlay.swift

python3 - <<'PYEOF'
p = 'build/ios/sensen.xcodeproj/project.pbxproj'
t = open(p).read()
if 'MapUnderlay' in t:
    print('pbxproj 已注入，跳过')
    raise SystemExit

# 1) PBXBuildFile
t = t.replace(
    '\t\t1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */ = {isa = PBXBuildFile; fileRef = 1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */; };',
    '\t\t1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */ = {isa = PBXBuildFile; fileRef = 1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */; };\n'
    '\t\tAA00000000000000000000B2 /* G3Spike.mm in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000B1 /* G3Spike.mm */; };\n'
    '\t\tAA00000000000000000000B4 /* MapUnderlay.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000B3 /* MapUnderlay.swift */; };\n'
    '\t\tAA00000000000000000000C3 /* MapboxMaps in Frameworks */ = {isa = PBXBuildFile; productRef = AA00000000000000000000C2 /* MapboxMaps */; };', 1)
# 2) PBXFileReference
t = t.replace(
    '\t\t1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.cpp; path = dummy.cpp; sourceTree = "<group>"; };',
    '\t\t1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.cpp; path = dummy.cpp; sourceTree = "<group>"; };\n'
    '\t\tAA00000000000000000000B1 /* G3Spike.mm */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; path = G3Spike.mm; sourceTree = "<group>"; };\n'
    '\t\tAA00000000000000000000B3 /* MapUnderlay.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MapUnderlay.swift; sourceTree = "<group>"; };', 1)
# 3) group children
t = t.replace(
    '\t\t\t\t1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */,',
    '\t\t\t\t1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */,\n'
    '\t\t\t\tAA00000000000000000000B1 /* G3Spike.mm */,\n'
    '\t\t\t\tAA00000000000000000000B3 /* MapUnderlay.swift */,', 1)
# 4) Sources phase
t = t.replace(
    '\t\t\t\t1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */,',
    '\t\t\t\t1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */,\n'
    '\t\t\t\tAA00000000000000000000B2 /* G3Spike.mm in Sources */,\n'
    '\t\t\t\tAA00000000000000000000B4 /* MapUnderlay.swift in Sources */,', 1)
# 5) Frameworks phase
t = t.replace(
    '\t\t\t\tDEADBEEF2F582BE20003B888 /* godot in Frameworks */,',
    '\t\t\t\tDEADBEEF2F582BE20003B888 /* godot in Frameworks */,\n'
    '\t\t\t\tAA00000000000000000000C3 /* MapboxMaps in Frameworks */,', 1)
# 6) target 的 packageProductDependencies
# 注意：Godot 新导出的 pbxproj 值带引号（name = "sensen";），被 Xcode 保存过的
# 不带引号——两种锚点都要试（2026-08-31 实际踩过：只匹配无引号版导致漏注入）。
for anchor in ['\t\t\tname = "sensen";\n\t\t\tproductName = "SensenAvatar";',
               '\t\t\tname = sensen;\n\t\t\tproductName = SensenAvatar;']:
    if anchor in t:
        lines = anchor.split('\n')
        t = t.replace(anchor, lines[0] + '\n\t\t\tpackageProductDependencies = (\n'
            '\t\t\t\tAA00000000000000000000C2 /* MapboxMaps */,\n\t\t\t);\n' + lines[1], 1)
        break
# 7) project 的 packageReferences
t = t.replace(
    '\t\t\thasScannedForEncodings = 0;',
    '\t\t\thasScannedForEncodings = 0;\n\t\t\tpackageReferences = (\n'
    '\t\t\t\tAA00000000000000000000C1 /* XCRemoteSwiftPackageReference "mapbox-maps-ios" */,\n\t\t\t);', 1)
# 8) 新 section（插在 objects 收尾前）
t = t.replace(
    '\t};\n\trootObject',
    '''/* Begin XCRemoteSwiftPackageReference section */
\t\tAA00000000000000000000C1 /* XCRemoteSwiftPackageReference "mapbox-maps-ios" */ = {
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/mapbox/mapbox-maps-ios.git";
\t\t\trequirement = {
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = 11.28.0;
\t\t\t};
\t\t};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\tAA00000000000000000000C2 /* MapboxMaps */ = {
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = AA00000000000000000000C1 /* XCRemoteSwiftPackageReference "mapbox-maps-ios" */;
\t\t\tproductName = MapboxMaps;
\t\t};
/* End XCSwiftPackageProductDependency section */
\t};
\trootObject''', 1)
open(p, 'w').write(t)
print('pbxproj 注入完成（spike + swift + SPM）')
PYEOF

python3 tools/ios/inject_apple_sign_in.py --project build/ios/sensen.xcodeproj

cat <<'TIP'
构建装机（TEAM_ID：Xcode 选过一次 Team 后可从 pbxproj grep DEVELOPMENT_TEAM）：
  cd build/ios && xcodebuild -project sensen.xcodeproj -scheme sensen -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath dd-dev -allowProvisioningUpdates \
    DEVELOPMENT_TEAM=<TEAM_ID> CODE_SIGN_STYLE=Automatic build
  xcrun devicectl device install app --device <UDID> dd-dev/Build/Products/Debug-iphoneos/sensen.app
  xcrun devicectl device process launch --device <UDID> com.sensen.mapg3
TIP
