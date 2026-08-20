"""解析 Addressables 组资产中的 m_GUID/m_Address 对（hex GUID → Unity 工程内路径）。"""
import re
from pathlib import Path

_ENTRY_RE = re.compile(r"m_GUID:\s*([0-9a-f]{32})\s*\n\s*m_Address:\s*(.+)")

def load_guid_table(unity_root) -> dict:
    table = {}
    groups_dir = Path(unity_root) / "Assets/AddressableAssetsData/AssetGroups"
    for asset in sorted(groups_dir.glob("*.asset")):
        text = asset.read_text(encoding="utf-8", errors="replace")
        for m in _ENTRY_RE.finditer(text):
            table[m.group(1)] = m.group(2).strip()
    return table
