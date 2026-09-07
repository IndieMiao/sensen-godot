#!/bin/zsh
# 构建 iOS 版 Photo Picker GDExtension：godot-cpp（按本机 Godot 4.7.2 的 API dump）+ 本扩展，
# 再用 libtool 合成一个 .a（Godot 导出的 Xcode 工程只链 .gdextension 里列的那一个库）。
# 用法：native/photo_picker/build_ios.sh [template_debug|template_release]
set -euo pipefail
TARGET=${1:-template_debug}
HERE=$(cd "$(dirname "$0")" && pwd)
CPP="$HERE/../godot-cpp"
if [ ! -d "$CPP" ]; then
  echo "缺 native/godot-cpp：git clone --depth 1 -b 4.5 https://github.com/godotengine/godot-cpp.git $CPP"; exit 1
fi
# 绑定按本机 Godot 生成：换 Godot 版本后重新 dump 一次。
TMP=$(mktemp -d); (cd "$TMP" && godot --headless --dump-extension-api --dump-gdextension-interface >/dev/null 2>&1)
cp "$TMP/extension_api.json" "$CPP/gdextension/extension_api.json"; cp "$TMP/gdextension_interface.h" "$CPP/gdextension/gdextension_interface.h"; rm -rf "$TMP"
touch "$CPP/.gdignore"
JOBS=$(sysctl -n hw.ncpu)
(cd "$CPP" && scons platform=ios arch=arm64 target=$TARGET ios_min_version=14.0 build_profile="$HERE/build_profile.json" -j"$JOBS")
(cd "$HERE" && scons platform=ios arch=arm64 target=$TARGET ios_min_version=14.0 build_profile="$HERE/build_profile.json" -j"$JOBS")
OUT="$HERE/bin/libsensen_photo_picker.ios.$TARGET.arm64.a"
libtool -static -o "$OUT" "$HERE/bin/libsensen_photo_picker_objs.ios.$TARGET.arm64.a" "$CPP/bin/libgodot-cpp.ios.$TARGET.arm64.a"
echo "built $OUT ($(du -h "$OUT" | cut -f1))"
