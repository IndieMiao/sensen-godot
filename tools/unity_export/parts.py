"""ap_*.asset → PartRecipe。所有失败走 report，不猜测。"""
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

def build_recipe(unity_root: Path, asset_name: str, tier: int,
                 overrides: dict, registry: naming.SlugRegistry, report: Report):
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
    ov = overrides.get(part_id, {}) if overrides else {}
    pak_dir = ap_path.parent
    folder = Path(ov["folder"]) if "folder" in ov else convention.variant_dir(pak_dir, part_name)
    recipe = {"id": part_id, "slot": slot, "attach": attach, "tier": tier,
              "unity_guid": str(mb.get("guid", "")), "materials": [], "offset": None,
              "thumb_src": None, "fbx": None, "mesh_name": None, "src_files": []}
    slot_word = _slot_word(part_name, slot)
    if attach == "mesh":
        fbx = Path(ov["fbx"]) if "fbx" in ov else convention.find_fbx(folder)
        if fbx is None:
            report.error(f"{part_id}: 找不到 FBX（目录 {folder}）")
            return None
        recipe["fbx"] = fbx
        recipe["mesh_name"] = ov.get("mesh_name", slot)
    else:
        fbx = Path(ov["fbx"]) if "fbx" in ov else convention.find_named_fbx(folder, part_name) or convention.find_fbx(folder, "SM_")
        if fbx is None:
            report.error(f"{part_id}: 找不到 socket FBX（目录 {folder}）")
            return None
        recipe["fbx"] = fbx
        pos, rot, scale = mb.get("postion", {}), mb.get("rotation", {}), mb.get("scale", {})
        recipe["offset"] = {"pos": _v(pos), "rot": _v(rot), "scale": _v(scale, 1.0)}
    albedo = Path(ov["albedo"]) if "albedo" in ov else convention.find_texture(folder, slot_word, "D")
    ao = Path(ov["ao"]) if "ao" in ov else convention.find_texture(folder, slot_word, "AO")
    if albedo is None:
        report.warn(f"{part_id}: 找不到 albedo 贴图，材质将无贴图")
    mat_file = materials.find_material_file(folder, slot_word)
    floats = materials.extract_floats(mat_file) if mat_file else {}
    recipe["materials"].append({"albedo": albedo, "ao": ao, "floats": floats})
    return recipe

def _slot_word(part_name: str, slot: str) -> str:
    import re
    m = re.match(r"([a-zA-Z]+)", part_name)
    return m.group(1) if m else slot

def _v(d, default=0.0):
    if not isinstance(d, dict):
        return [default] * 3
    return [float(d.get("x", default)), float(d.get("y", default)), float(d.get("z", default))]
