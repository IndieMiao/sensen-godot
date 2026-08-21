"""ap_*.asset → PartRecipe。所有失败走 report，不猜测。"""
import re
from dataclasses import dataclass, field
from pathlib import Path
import unity_yaml, naming, convention, materials

@dataclass
class Report:
    errors: list = field(default_factory=list)
    warnings: list = field(default_factory=list)
    def error(self, msg): self.errors.append(msg)
    def warn(self, msg): self.warnings.append(msg)

def find_ap_asset(unity_root: Path, asset_name: str):
    roots = [unity_root / "Assets/_Gensen/Characters/AvatarPaks",
             unity_root / "Assets/_Gensen/Characters/BaseCharacter/BaseParts"]
    for root in roots:
        hits = sorted(root.rglob(f"{asset_name}.asset"))
        if hits:
            return hits[0]
    return None

def _resolve_override_path(val, unity_root: Path) -> Path:
    """overrides.json 里的路径可以是绝对路径，也可以是相对 unity_root 的相对路径（便于换机器/仓库位置）。"""
    p = Path(val)
    return p if p.is_absolute() else Path(unity_root) / p

def build_recipe(unity_root: Path, asset_name: str, tier: int,
                 overrides: dict, registry: naming.SlugRegistry, report: Report,
                 forced: dict = None):
    """forced：调用方强制注入的 per-part override（优先级最高），不依赖 part_id 匹配任何 key——
    直接并入 overrides.json 里该 part_id 的条目之上。用于 base_parts 这类"文件名 slug 与
    partName 解析出的 part_id 不一致"的场景（不能靠 overrides 字典的 key 命中）。"""
    ap_path = find_ap_asset(unity_root, asset_name)
    if ap_path is None:
        report.error(f"{asset_name}: 找不到 ap 资产")
        return None
    mb = unity_yaml.load_monobehaviour(ap_path)
    if mb is None:
        report.error(f"{asset_name}: YAML 解析失败")
        return None
    part_name = str(mb.get("partName", ""))
    try:
        part_id = registry.claim(naming.slug(part_name))
        slot = naming.slot_name(int(mb.get("partType", -1)))
    except ValueError as e:
        report.error(f"{asset_name}: {e}")
        return None
    attach = "mesh" if int(mb.get("attachType", 0)) == 0 else "socket"
    ov = {**(overrides.get(part_id, {}) if overrides else {}), **(forced or {})}
    pak_dir = ap_path.parent
    folder = _resolve_override_path(ov["folder"], unity_root) if "folder" in ov else convention.variant_dir(pak_dir, part_name)
    recipe = {"id": part_id, "slot": slot, "attach": attach, "tier": tier,
              "unity_guid": str(mb.get("guid", "")), "materials": [], "offset": None,
              "thumb_src": None, "fbx": None, "mesh_name": None, "src_files": []}
    slot_word = _slot_word(part_name, slot)
    if attach == "mesh":
        fbx = _resolve_override_path(ov["fbx"], unity_root) if "fbx" in ov else convention.find_fbx(folder)
        if fbx is None:
            report.error(f"{part_id}: 找不到 FBX（目录 {folder}）")
            return None
        recipe["fbx"] = fbx
        recipe["mesh_name"] = ov.get("mesh_name", slot)
        recipe["materials"] = _mesh_materials(folder, slot_word, ov, unity_root, part_id, report)
    else:
        fbx = _resolve_override_path(ov["fbx"], unity_root) if "fbx" in ov else convention.find_named_fbx(folder, part_name) or convention.find_fbx(folder, "SM_")
        if fbx is None:
            report.error(f"{part_id}: 找不到 socket FBX（目录 {folder}）")
            return None
        recipe["fbx"] = fbx
        pos, rot, scale = mb.get("postion", {}), mb.get("rotation", {}), mb.get("scale", {})
        recipe["offset"] = {"pos": _v(pos), "rot": _v(rot), "scale": _v(scale, 1.0)}
        albedo = _resolve_override_path(ov["albedo"], unity_root) if "albedo" in ov else convention.find_texture(folder, slot_word, "D")
        ao = _resolve_override_path(ov["ao"], unity_root) if "ao" in ov else convention.find_texture(folder, slot_word, "AO")
        if albedo is None:
            report.warn(f"{part_id}: 找不到 albedo 贴图，材质将无贴图")
        mat_file = materials.find_material_file(folder, slot_word)
        floats = materials.extract_floats(mat_file) if mat_file else {}
        recipe["materials"].append({"albedo": albedo, "ao": ao, "floats": floats})
    return recipe

def _mesh_materials(folder, slot_word: str, ov: dict, unity_root: Path, part_id: str, report: Report):
    """mesh 部件的材质列表：每个命中的 .mat 一条 entry（floats 各取各的），贴图先按该 .mat
    文件名里除 slot_word/pak 前缀外的额外 token 精确匹配，找不到则回退共享的 slot_word 贴图并记
    WARN（不 ERROR）。若 folder 内一个匹配的 .mat 都没有（如基础部件 Texture/ 目录本就没有
    .mat），退回旧行为：单条 entry，floats 为空。若调用方在 overrides 里显式指定了 albedo/ao，
    视为对这个部件贴图的整体覆盖，同样只产出单条 entry，不做多 .mat 展开。"""
    if "albedo" in ov or "ao" in ov:
        albedo = _resolve_override_path(ov["albedo"], unity_root) if "albedo" in ov else convention.find_texture(folder, slot_word, "D")
        ao = _resolve_override_path(ov["ao"], unity_root) if "ao" in ov else convention.find_texture(folder, slot_word, "AO")
        if albedo is None:
            report.warn(f"{part_id}: 找不到 albedo 贴图，材质将无贴图")
        return [{"albedo": albedo, "ao": ao, "floats": {}}]

    mat_files = materials.find_material_files(folder, slot_word)
    if not mat_files:
        albedo = convention.find_texture(folder, slot_word, "D")
        ao = convention.find_texture(folder, slot_word, "AO")
        if albedo is None:
            report.warn(f"{part_id}: 找不到 albedo 贴图，材质将无贴图")
        return [{"albedo": albedo, "ao": ao, "floats": {}}]

    entries = []
    for mat_file in mat_files:
        floats = materials.extract_floats(mat_file)
        albedo = _precise_texture(folder, mat_file, slot_word, "D")
        if albedo is None:
            fallback = convention.find_texture(folder, slot_word, "D")
            if fallback is None:
                report.warn(f"{part_id}: {mat_file.name} 找不到 albedo 贴图，材质将无贴图")
            else:
                report.warn(f"{part_id}: {mat_file.name} 未找到精确贴图，回退共享 {slot_word} 贴图")
            albedo = fallback
        ao = _precise_texture(folder, mat_file, slot_word, "AO")
        if ao is None:
            ao = convention.find_texture(folder, slot_word, "AO")
        entries.append({"albedo": albedo, "ao": ao, "floats": floats})
    return entries

_KIND_TOKENS = {"d", "ao", "orm"}

def _tokens(stem: str, prefix: str, slot_word: str) -> set:
    """把 .mat/.png 的文件名 stem 拆成小写 token 集合，去掉前缀字母(M_/T_)、槽位词本身
    (slot_word) 与贴图种类词(D/AO/ORM)，剩下的即"这一份文件专属"的区分 token（如变体号 1/2、
    共享的 pak 名 skin88 等）。用于在同一 slot_word 下有多个 .mat/贴图时按 token 集合精确配对。"""
    s = re.sub(rf"^{re.escape(prefix)}_?", "", stem, flags=re.I)
    toks = [t.lower() for t in re.split(r"[^a-zA-Z0-9]+", s) if t]
    return {t for t in toks if t != slot_word.lower() and t not in _KIND_TOKENS}

def _precise_texture(folder: Path, mat_file: Path, slot_word: str, kind: str):
    if folder is None or not folder.is_dir():
        return None
    mat_tokens = _tokens(mat_file.stem, "M", slot_word)
    pat = re.compile(rf"^T_.*{re.escape(slot_word)}.*_{kind}\.png$", re.I)
    candidates = sorted(p for p in folder.iterdir() if pat.match(p.name))
    for cand in candidates:
        if _tokens(cand.stem, "T", slot_word) == mat_tokens:
            return cand
    return None

def _slot_word(part_name: str, slot: str) -> str:
    m = re.match(r"([a-zA-Z]+)", part_name)
    return m.group(1) if m else slot

def _v(d, default=0.0):
    if not isinstance(d, dict):
        return [default] * 3
    return [float(d.get("x", default)), float(d.get("y", default)), float(d.get("z", default))]
