#!/bin/zsh
# 构建 iOS 版语音 GDExtension（godot-cpp + 本扩展 → 合成一个 .a）。
# 用法：native/voice/build_ios.sh [template_debug|template_release]
#
# 本库只是薄壳：真正的 LiveKit 在 Swift 侧（tools/ios/SensenVoice.swift），由
# tools/ios/setup_ios_g3.sh 注入 Xcode 工程并挂上 client-sdk-swift 的 SPM 依赖。
# 没注入时 is_available() = false，语音房自动进只读模式。
set -euo pipefail
TARGET=${1:-template_debug}
HERE=$(cd "$(dirname "$0")" && pwd)
CPP="$HERE/../godot-cpp"
if [ ! -d "$CPP" ]; then
  echo "缺 native/godot-cpp：git clone --depth 1 -b 4.5 https://github.com/godotengine/godot-cpp.git $CPP"; exit 1
fi
JOBS=$(sysctl -n hw.ncpu)
(cd "$CPP" && scons platform=ios arch=arm64 target=$TARGET ios_min_version=14.0 build_profile="$HERE/build_profile.json" -j"$JOBS")
(cd "$HERE" && scons platform=ios arch=arm64 target=$TARGET ios_min_version=14.0 build_profile="$HERE/build_profile.json" -j"$JOBS")
OUT="$HERE/bin/libsensen_voice.ios.$TARGET.arm64.a"
libtool -static -o "$OUT" "$HERE/bin/libsensen_voice_objs.ios.$TARGET.arm64.a" "$CPP/bin/libgodot-cpp.ios.$TARGET.arm64.a"
echo "built $OUT ($(du -h "$OUT" | cut -f1))"
