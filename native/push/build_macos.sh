#!/bin/zsh
# 桌面空实现：让编辑器与测试进程有库可载（macOS 上没有推送通道）。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TARGET=${1:-template_debug}
(cd "$HERE/../godot-cpp" && scons platform=macos arch=arm64 target=$TARGET build_profile="$HERE/build_profile.json" -j"$(sysctl -n hw.ncpu)")
(cd "$HERE" && scons platform=macos arch=arm64 target=$TARGET build_profile="$HERE/build_profile.json" -j"$(sysctl -n hw.ncpu)")
