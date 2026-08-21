import argparse, csv, json, os, shutil, stat, sys
from pathlib import Path
import addressables, naming, parts as parts_mod

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--unity-root", required=True)
    ap.add_argument("--godot-root", required=True)
    ap.add_argument("--samples", default="samples.json")
    ap.add_argument("--overrides", default="overrides.json")
    ap.add_argument("--out", default="out")
    args = ap.parse_args()

    unity_root = Path(args.unity_root).resolve()
    godot_root = Path(args.godot_root).resolve()
    out_dir = Path(args.out); out_dir.mkdir(parents=True, exist_ok=True)
    samples = json.loads(Path(args.samples).read_text(encoding="utf-8"))
    overrides = json.loads(Path(args.overrides).read_text(encoding="utf-8")) if Path(args.overrides).is_file() else {}

    report = parts_mod.Report()
    registry = naming.SlugRegistry()
    _ = addressables.load_guid_table(unity_root)  # 一期保留备用（overrides/约定已覆盖样例）；全量迁移时启用
    recipes, guid_rows = [], []

    base_dir = unity_root / "Assets/_Gensen/Characters/BaseCharacter"
    base_fbx = base_dir / "Models/SK_DtBase.fbx"
    base = {"fbx": _stage(base_fbx, godot_root, "base", report),
            "anim_fbx": {k: _stage(base_dir / f"Animations/{v}", godot_root, "base", report)
                         for k, v in {"idle": "dt@idle02.fbx", "walk": "dt@walk01.fbx", "run": "dt@run01.fbx"}.items()}}

    # 基础部件的 FBX/贴图不在部件目录约定内（Models/ 与 Texture/）：用 build_recipe 的 forced
    # 参数强制注入（不依赖 overrides 字典的 key——base_parts 的文件名 slug 与资产内 partName
    # 解析出的 part_id 并不总是一致，例如 ap_cloth00.asset 的 partName 其实是 "cloth0"）。
    base_forced = {"fbx": str(base_fbx), "folder": str(base_dir / "Texture")}
    for name in samples.get("base_parts", []):
        r = parts_mod.build_recipe(unity_root, name, 0, overrides, registry, report, forced=base_forced)
        if r:
            recipes.append(r)
    for item in samples.get("parts", []):
        if "tier" not in item:
            report.warn(f"{item['asset']}: tier 未声明，默认 0")
        r = parts_mod.build_recipe(unity_root, item["asset"], int(item.get("tier", 0)), overrides, registry, report)
        if r:
            recipes.append(r)

    for r in recipes:
        sid = r["id"]
        r["fbx"] = _stage(Path(r["fbx"]), godot_root, sid, report)
        for m in r["materials"]:
            m["albedo"] = _stage(m["albedo"], godot_root, sid, report) if m["albedo"] else None
            m["ao"] = _stage(m["ao"], godot_root, sid, report) if m["ao"] else None
        guid_rows.append((r["unity_guid"], sid))

    (out_dir / "recipes.json").write_text(
        json.dumps({"version": 1, "base": base, "parts": recipes}, indent=2, default=str), encoding="utf-8")
    with (out_dir / "guid_map.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f); w.writerow(["unity_guid", "part_id"]); w.writerows(guid_rows)
    rpt = ["ERROR: " + e for e in report.errors] + ["WARN: " + w for w in report.warnings]
    (out_dir / "report.txt").write_text("\n".join(rpt) or "clean", encoding="utf-8")
    print("\n".join(rpt) or "clean")
    if report.errors:
        sys.exit(1)

def _stage(src, godot_root: Path, part_id: str, report) -> str:
    """拷贝到 assets/avatar/source/<part_id>/，返回 res:// 路径。同名文件真正幂等覆盖：用
    copyfile（不像 copy2 那样拷贝源文件的元数据/系统标志——Unity 源文件本身可能带只读/
    uchg 等不可变标志，copy2 会把它们连带复制到目标文件上，导致下一次运行覆盖同名文件时
    PermissionError）。覆盖前若目标已存在且不可写，先清掉不可变标志/加上写权限。"""
    src = Path(src)
    if not src.is_file():
        report.error(f"{part_id}: 源文件缺失 {src}")
        return ""
    dst_dir = godot_root / "assets/avatar/source" / part_id
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / src.name
    if dst.exists():
        try:
            os.chflags(dst, 0)  # 清 uchg 等标志（macOS；非 macOS 平台没有 chflags）
        except (AttributeError, OSError):
            pass
        try:
            dst.chmod(dst.stat().st_mode | stat.S_IWUSR)
        except OSError:
            pass
    shutil.copyfile(src, dst)
    return "res://" + dst.relative_to(godot_root).as_posix()

if __name__ == "__main__":
    main()
