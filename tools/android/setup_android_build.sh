#!/usr/bin/env bash
# 安装 Android gradle 构建模板并套上 G1 PoC 的 Mapbox 插件覆盖层。
# android/ 目录整体不入库（约 700MB 模板产物），fresh checkout 后跑本脚本重建。
# 前置：已装 Godot 4.7.2 官方导出模板；Android SDK / JDK 已在 Godot 编辑器设置里配置。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Godot 的数据目录：macOS 在 Application Support，Linux 走 XDG（~/.local/share/godot）。GODOT_TEMPLATES_DIR 可覆盖。
if [ "$(uname -s)" = "Darwin" ]; then
    GODOT_DATA="$HOME/Library/Application Support/Godot"
else
    GODOT_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/godot"
fi
TEMPLATE_DIR="${GODOT_TEMPLATES_DIR:-$GODOT_DATA/export_templates/4.7.2.stable}"
TEMPLATE_ZIP="$TEMPLATE_DIR/android_source.zip"
BUILD_DIR="$REPO_ROOT/android/build"
OVERLAY="$REPO_ROOT/tools/android/overlay"

if [ ! -f "$TEMPLATE_ZIP" ]; then
    echo "找不到 $TEMPLATE_ZIP（先在 Godot 里安装 4.7.2 导出模板）" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"
touch "$REPO_ROOT/android/.gdignore" # 防止 Godot 导入模板内的 res 资源
unzip -oq "$TEMPLATE_ZIP" -d "$BUILD_DIR"
# 注意：版本文件在 build 目录的父级（export_plugin.cpp 用 get_base_dir()）
printf '4.7.2.stable\n' > "$REPO_ROOT/android/.build_version"

# PoC 覆盖层：Mapbox 依赖 + 插件源码 + manifest 注册（整文件替换，钉在 4.7.2 模板上）
cp "$OVERLAY/build.gradle" "$BUILD_DIR/build.gradle"
cp "$OVERLAY/AndroidManifest.xml" "$BUILD_DIR/src/main/AndroidManifest.xml"
mkdir -p "$BUILD_DIR/src/main/java/com/sensen/map"
cp "$OVERLAY/GodotMapPlugin.kt" "$BUILD_DIR/src/main/java/com/sensen/map/GodotMapPlugin.kt"
mkdir -p "$BUILD_DIR/src/test/java/com/sensen/map"
cp "$OVERLAY/GodotMapPluginTest.kt" "$BUILD_DIR/src/test/java/com/sensen/map/GodotMapPluginTest.kt"

echo "android/build 已就绪（模板 4.7.2 + GodotMap 插件覆盖层）"
echo "别忘了在仓库根放 mapbox_token.txt（pk token，勿提交）"
