"""目录/命名约定解析：变体目录、贴图、FBX、缩略图。找不到一律返回 None，让上层记 ERROR。"""
from pathlib import Path
import re

def variant_suffix(part_name: str) -> str:
    m = re.search(r"_(\d+)$", part_name)
    return m.group(1) if m else ""

def variant_dir(pak_dir: Path, part_name: str):
    """skin01/ap_cloth1 → skin01/skin01；ap_cloth1_2 → skin01/skin01_2。
    配件类 pak(glass 等) 无内层目录时返回 pak_dir 本身。"""
    suffix = variant_suffix(part_name)
    inner = pak_dir / (pak_dir.name + (f"_{suffix}" if suffix else ""))
    if inner.is_dir():
        return inner
    return pak_dir if not suffix else None

def find_texture(folder: Path, slot_word: str, kind: str):
    """kind: D | AO | ORM。匹配 T_*_<slot_word>*_<kind>.png（大小写不敏感）。"""
    if folder is None or not folder.is_dir():
        return None
    pat = re.compile(rf"^T_.*{re.escape(slot_word)}.*_{kind}\.png$", re.I)
    hits = sorted(p for p in folder.iterdir() if pat.match(p.name))
    return hits[0] if hits else None

def find_fbx(folder: Path, prefer_prefix: str = "SK_"):
    if folder is None or not folder.is_dir():
        return None
    hits = sorted(folder.glob(f"{prefer_prefix}*.fbx")) or sorted(folder.glob("*.fbx"))
    return hits[0] if hits else None

def find_named_fbx(folder: Path, part_name: str):
    """socket 部件：SM_<partName>.fbx / SK_<partName>.fbx / <partName>*.fbx"""
    if folder is None or not folder.is_dir():
        return None
    for pat in (f"SM_{part_name}.fbx", f"SK_{part_name}.fbx", f"{part_name}*.fbx",
                f"SM_{part_name}*.fbx", f"SK_{part_name}*.fbx"):
        hits = sorted(folder.glob(pat))
        if hits:
            return hits[0]
    return None
