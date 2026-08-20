"""从 Unity .mat 提取 float 参数并映射到 toon shader 参数名。贴图靠 convention 定位，不走 .mat 引用。"""
import unity_yaml

FLOAT_MAP = {"_Kao": "ao_strength", "_Kshadow": "shadow_value",
             "_Ke": "emission_strength", "_FresnelHighLight": "rim_strength"}

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

def find_material_file(folder, slot_word):
    """M_*<slot_word>*.mat（大小写不敏感），无则 None。"""
    import re
    if folder is None or not folder.is_dir():
        return None
    pat = re.compile(rf"^M_.*{re.escape(slot_word)}.*\.mat$", re.I)
    hits = sorted(p for p in folder.iterdir() if pat.match(p.name))
    return hits[0] if hits else None
