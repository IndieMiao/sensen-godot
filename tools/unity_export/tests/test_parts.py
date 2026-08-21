from pathlib import Path
import parts, naming

ASSET_YAML = """%YAML 1.1
%TAG !u! tag:yousandi.cn,2023:
--- !u!114 &11400000
MonoBehaviour:
  m_Name: ap_fakepart
  guid: 00112233445566778899aabbccddeeff
  attachType: 0
  partName: fakepart
  partType: 0
  mesh: {fileID: -1, guid: 00000000000000000000000000000000, type: 3}
  materials: []
  socketPrefab: {fileID: 0}
  postion: {x: 0, y: 0, z: 0}
  scale: {x: 1, y: 1, z: 1}
  rotation: {x: 0, y: 0, z: 0}
  thumbnail: {fileID: 0}
"""

def _make_unity_root(tmp_path):
    base_parts = tmp_path / "Assets/_Gensen/Characters/BaseCharacter/BaseParts"
    base_parts.mkdir(parents=True)
    (base_parts / "ap_fakepart.asset").write_text(ASSET_YAML, encoding="utf-8")
    return tmp_path

def test_forced_override_bypasses_key_mismatch(tmp_path):
    """forced 直接并入 ov，不依赖任何 key 匹配——即便 overrides 字典里挂着一个错误 key
    的条目（模拟 base_parts 文件名 slug 与 partName 解析出的 part_id 不一致的场景），
    forced 仍然生效。"""
    unity_root = _make_unity_root(tmp_path)
    forced_fbx = tmp_path / "SK_Forced.fbx"
    forced_fbx.touch()
    forced_folder = tmp_path / "tex"
    forced_folder.mkdir()

    report = parts.Report()
    registry = naming.SlugRegistry()
    overrides = {"fakepart00": {"fbx": "should-not-be-used.fbx"}}  # 错误 key，不应生效

    recipe = parts.build_recipe(unity_root, "ap_fakepart", 0, overrides, registry, report,
                                 forced={"fbx": str(forced_fbx), "folder": str(forced_folder)})

    assert recipe is not None
    assert not report.errors
    assert recipe["fbx"] == forced_fbx

def test_forced_none_falls_back_to_overrides_dict(tmp_path):
    """forced 为 None（默认）时，行为与不传一致：仍走 overrides 字典按 part_id 查找。"""
    unity_root = _make_unity_root(tmp_path)
    override_fbx = tmp_path / "SK_FromOverrides.fbx"
    override_fbx.touch()

    report = parts.Report()
    registry = naming.SlugRegistry()
    overrides = {"fakepart": {"fbx": str(override_fbx)}}

    recipe = parts.build_recipe(unity_root, "ap_fakepart", 0, overrides, registry, report)

    assert recipe is not None
    assert recipe["fbx"] == override_fbx

def test_resolve_override_path_absolute(tmp_path):
    abs_path = str(tmp_path / "x.fbx")
    assert parts._resolve_override_path(abs_path, tmp_path / "unity") == Path(abs_path)

def test_resolve_override_path_relative(tmp_path):
    unity_root = tmp_path / "unity"
    assert parts._resolve_override_path("sub/x.fbx", unity_root) == unity_root / "sub/x.fbx"
