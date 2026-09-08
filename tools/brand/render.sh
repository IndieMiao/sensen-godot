#!/usr/bin/env bash
# 重新生成品牌开屏 / 启动图标 PNG（源：assets/brand/logo_mark.svg）。
# 换品牌素材（SSLAUNCH B1）后跑这个，然后提交 assets/brand/generated/。
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
# 先 import：新脚本的 class_name 要进全局类缓存，脚本里才认得 Brand
"$GODOT_BIN" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT_BIN" --headless --path . --script tools/brand/render_brand_assets.gd
# 再 import：新生成的 PNG 要有 .import 才进导出链资源表
"$GODOT_BIN" --headless --path . --import > /dev/null 2>&1 || true
