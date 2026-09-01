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

def find_material_files(folder, slot_word):
    """M_*<slot_word>*.mat（大小写不敏感），返回全部命中（已排序），无则 []。"""
    import re
    if folder is None or not folder.is_dir():
        return []
    pat = re.compile(rf"^M_.*{re.escape(slot_word)}.*\.mat$", re.I)
    return sorted(p for p in folder.iterdir() if pat.match(p.name))

def find_material_file(folder, slot_word):
    """M_*<slot_word>*.mat（大小写不敏感），无则 None。find_material_files 的首个命中。"""
    hits = find_material_files(folder, slot_word)
    return hits[0] if hits else None
