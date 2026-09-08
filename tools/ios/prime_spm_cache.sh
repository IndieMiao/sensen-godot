#!/bin/zsh
# SPM 的**二进制产物**（binaryTarget 的 .xcframework.zip）走 URLSession 下载，只认系统网络设置里的
# 代理，不认环境变量里的 HTTPS_PROXY；git 仓库那部分走 git，认。于是在需要代理的网络下会出现
# 一个很难看懂的现象：xcodebuild 停在 "Resolve Package Graph"，CPU 0%，几十分钟不动——
# 仓库都克隆好了，卡在下 zip（2026-09-08 实测 LiveKit 的 WebRTC 与 uniffi 两个包）。
#
# 这个脚本用 curl（认环境代理）把 zip 下好，按 SPM 的缓存命名规则放进共享缓存目录：
# 键名 = URL 里所有非字母数字换成 _。命中缓存后 xcodebuild 不再自己下。
#
# 用法：tools/ios/prime_spm_cache.sh   （在 setup_ios_g3.sh 之后、xcodebuild 之前跑）
# 已经缓存且校验通过的会跳过，重复跑没有副作用。
set -euo pipefail
CACHE="$HOME/Library/Caches/org.swift.swiftpm/artifacts"
CHECKOUTS=${SPM_CHECKOUTS:-build/ios/derived-cli/SourcePackages/checkouts}
mkdir -p "$CACHE"

prime() {
  local url=$1 sum=$2
  local key=$(printf '%s' "$url" | sed 's/[^A-Za-z0-9]/_/g')
  local dest="$CACHE/$key"
  if [ -f "$dest" ] && [ "$(shasum -a 256 "$dest" | cut -d' ' -f1)" = "$sum" ]; then
    echo "已缓存 ${url##*/}"
    return
  fi
  echo "下载 $url"
  curl -fsSL --retry 3 -o "$dest.part" "$url"
  local got=$(shasum -a 256 "$dest.part" | cut -d' ' -f1)
  if [ "$got" != "$sum" ]; then
    echo "校验不符（期望 $sum，实得 $got）：不放进缓存" >&2
    rm -f "$dest.part"
    return 1
  fi
  mv "$dest.part" "$dest"
  echo "就位 ${url##*/}（$(du -h "$dest" | cut -f1)）"
}

# 首选：从已克隆的 Package.swift 里读 url/checksum，将来加依赖不用改这个脚本。
found=0
if [ -d "$CHECKOUTS" ]; then
  while IFS='|' read -r url sum; do
    [ -z "$url" ] && continue
    found=1
    prime "$url" "$sum" || true
  done < <(grep -rhA2 'url: *"https://[^"]*\.zip"' "$CHECKOUTS"/*/Package.swift 2>/dev/null \
    | tr -d ' ' | tr '\n' ' ' \
    | grep -o 'url:"[^"]*"checksum:"[^"]*"' \
    | sed 's/url:"\([^"]*\)"checksum:"\([^"]*\)"/\1|\2/')
fi

# 兜底：还没 resolve 过（没有 checkouts）时，用已知的两个 LiveKit 产物。
# 版本跟着 client-sdk-swift 走，升级 SDK 后若这里对不上，先跑一次让它 resolve 出 checkouts 再重跑。
if [ "$found" -eq 0 ]; then
  echo "没找到 checkouts，用内置清单"
  prime "https://github.com/livekit/webrtc-xcframework/releases/download/144.7559.11/LiveKitWebRTC.xcframework.zip" \
        "07c5caf718058af3c528dcabd257298c40e5a8527e4fb9f47c48336ba5899853"
  prime "https://github.com/livekit/livekit-uniffi-xcframework/releases/download/0.0.6/RustLiveKitUniFFI.xcframework.zip" \
        "0d3f2ce159a224c728f8b131068d53bbf9b13d968cda0edc68a6a2290f2651ed"
fi
