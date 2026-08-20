"""部件 ID(slug) 与槽位映射。槽位顺序 = Unity PartType 枚举顺序，不可改。"""
import re

SLOTS = ["body", "eyes", "hairHat", "cloth", "shoes", "shoulderBag", "messengerBag",
         "pocketBag", "backpack", "headset", "handleft", "handright", "mask", "glass"]

def slot_name(part_type: int) -> str:
    if 0 <= part_type < len(SLOTS):
        return SLOTS[part_type]
    raise ValueError(f"未知 partType: {part_type}")

def slug(part_name: str) -> str:
    s = part_name.strip().lower()
    s = re.sub(r"[\s\-]+", "", s)
    s = re.sub(r"[^a-z0-9_]", "", s)
    if not s:
        raise ValueError(f"无法从 {part_name!r} 生成 slug")
    return s

class SlugRegistry:
    def __init__(self):
        self._seen = set()
    def claim(self, s: str) -> str:
        if s in self._seen:
            raise ValueError(f"部件 ID 冲突: {s}")
        self._seen.add(s)
        return s
