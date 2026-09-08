#!/bin/zsh
# 构建 iOS 版推送 GDExtension（godot-cpp + 本扩展 → 合成一个 .a）。
# 用法：native/push/build_ios.sh [template_debug|template_release]
#
# 注意：真机拿到 token 还需要 provisioning profile 带 Push Notifications 能力与
# aps-environment 授权（SSLAUNCH A9）。没有的话 register_for_remote 会走 token_failed，
# 报「no valid aps-environment entitlement」——这是预期，不是插件坏了。
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
OUT="$HERE/bin/libsensen_push.ios.$TARGET.arm64.a"
libtool -static -o "$OUT" "$HERE/bin/libsensen_push_objs.ios.$TARGET.arm64.a" "$CPP/bin/libgodot-cpp.ios.$TARGET.arm64.a"
echo "built $OUT ($(du -h "$OUT" | cut -f1))"
