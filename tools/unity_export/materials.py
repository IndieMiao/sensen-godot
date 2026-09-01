"""从 Unity .mat 提取 float 参数并映射到 toon shader 参数名。贴图靠 convention 定位，不走 .mat 引用。"""
import unity_yaml

# 映射按 Unity DonutAvatar.shadergraph 的真实语义（URP Lit 表面输出）对齐。
# 2026-09-01 修正：_Ksmooth 是 Smoothness 而非 ramp 宽度，此前完全没映射，
# 于是 Godot 侧高光被写死掐掉；_Kshadow 是 graph 内部 Lerp 系数、不对应任何
# Godot 表面输入，硬映射成"暗部亮度"是画面变平的主因之一，故不再映射。
FLOAT_MAP = {"_Kao": "ao_strength", "_Ksmooth": "smoothness",
             "_Kd": "diffuse_strength", "_Ke": "emission_strength",
             "_FresnelHighLight": "rim_strength"}

def extract_floats(mat_path) -> dict:
    docs = unity_yaml.load_documents(mat_path)
    for doc in docs:
        mat = doc.get("Material")
        if not mat:
            continue
        floats = {}
        saved = mat.get("m_SavedProperties", {}) or {}
        for item in saved.get("m_Floats", []) or []:
            if isinstance(item, dict):
                for k, v in item.items():
                    if k in FLOAT_MAP and v is not None:
                        floats[FLOAT_MAP[k]] = float(v)
        return floats
    return {}

# 美术侧命名漂移：材质文件名里的槽位词与 partType 解析出的 slot_word 常常不一致。
# 实测样本：hairHat 的材质叫 M_hair20 / M_skin88_hair；eyes 的叫 M_baseboy_eye；
# messengerBag 的叫 M_skin47_messagebag（美术把 messenger 写成了 message）。
# 按"最具体优先"依次尝试，第一个有命中的别名即停——避免 hair 这种宽别名
# 抢在 hairHat 之前误命中同目录下别的部件材质。
SLOT_WORD_ALIASES = {
    "hairHat": ("hairHat", "hairhat", "hair"),
    "eyes": ("eyes", "eye"),
    "messengerBag": ("messengerBag", "messengerbag", "messagebag"),
}

def find_material_files(folder, slot_word):
    """M_*<slot_word>*.mat（大小写不敏感），返回全部命中（已排序），无则 []。
    slot_word 找不到时按 SLOT_WORD_ALIASES 依次退让。"""
    import re
    if folder is None or not folder.is_dir():
        return []
    names = sorted(folder.iterdir())
    for word in SLOT_WORD_ALIASES.get(slot_word, (slot_word,)):
        pat = re.compile(rf"^M_.*{re.escape(word)}.*\.mat$", re.I)
        hits = [p for p in names if pat.match(p.name)]
        if hits:
            return hits
    return []

def find_material_file(folder, slot_word):
    """M_*<slot_word>*.mat（大小写不敏感），无则 None。find_material_files 的首个命中。"""
    hits = find_material_files(folder, slot_word)
    return hits[0] if hits else None
