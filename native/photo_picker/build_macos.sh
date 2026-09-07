#!/bin/zsh
# 桌面空实现：给编辑器 / 测试进程一个可载的库（见 src_stub）。用法：native/photo_picker/build_macos.sh [template_debug|template_release]
set -euo pipefail
TARGET=${1:-template_debug}
HERE=$(cd "$(dirname "$0")" && pwd)
CPP="$HERE/../godot-cpp"
JOBS=$(sysctl -n hw.ncpu)
(cd "$CPP" && scons platform=macos arch=arm64 target=$TARGET build_profile="$HERE/build_profile.json" -j"$JOBS")
(cd "$HERE" && scons platform=macos arch=arm64 target=$TARGET build_profile="$HERE/build_profile.json" -j"$JOBS")
ls -la "$HERE"/bin/libsensen_photo_picker.macos.$TARGET.*
