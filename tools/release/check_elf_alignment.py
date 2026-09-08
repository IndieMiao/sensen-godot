#!/usr/bin/env python3
"""扫 APK / AAB 里的 arm64 .so，检查 LOAD 段的对齐够不够 16 KB。

为什么要自己写：Google 的 check_elf_alignment.sh 依赖 NDK 的 llvm-readelf，
本机不一定有；而 ELF 程序头就那么几个字段，直接读比装一套工具链省事。
判据：每个 PT_LOAD 段的 p_align >= 16384。Google Play 从 2025-11 起要求
target Android 15+ 的应用满足这一条，达不到就上不去。

用法：tools/release/check_elf_alignment.py build/sensen-android-debug.apk
退出码 0 = 全部达标，1 = 有未对齐的。
"""
import struct
import sys
import zipfile

REQUIRED = 16384
PT_LOAD = 1


def load_alignments(data: bytes) -> list[int]:
    """返回所有 PT_LOAD 段的 p_align；不是 64 位小端 ELF 就返回空。"""
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        return []
    e_phoff = struct.unpack_from("<Q", data, 0x20)[0]
    e_phentsize = struct.unpack_from("<H", data, 0x36)[0]
    e_phnum = struct.unpack_from("<H", data, 0x38)[0]
    out = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from("<I", data, off)[0]
        if p_type == PT_LOAD:
            out.append(struct.unpack_from("<Q", data, off + 0x30)[0])
    return out


def main(path: str) -> int:
    bad = []
    checked = 0
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if not name.endswith(".so") or "/arm64-v8a/" not in name:
                continue
            aligns = load_alignments(z.read(name))
            if not aligns:
                print(f"?? {name}: 不是 64 位小端 ELF，跳过")
                continue
            checked += 1
            worst = min(aligns)
            ok = worst >= REQUIRED
            print(f"{'OK' if ok else '!!'} {name}: 最小 LOAD 对齐 {worst} ({worst // 1024} KB)")
            if not ok:
                bad.append(name)
    print(f"\n检查 {checked} 个 so，{len(bad)} 个未达 16 KB。")
    if bad:
        print("未达标：" + ", ".join(bad))
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
