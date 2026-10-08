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

def test_overrides_dict_wins_over_forced_for_same_key(tmp_path):
    """人工定点修正优先于通用注入：当 forced 与 overrides.json（按实际 part_id 命中）都给了
    同一个 key（如 fbx）时，以 overrides.json 为准——例如 base_parts 统统 forced 到
    SK_DtBase.fbx，但 glass0/hairhat0 这类 socket 挂载件的真实网格在别处，靠 overrides.json
    按 part_id 精确纠正。"""
    unity_root = _make_unity_root(tmp_path)
    forced_fbx = tmp_path / "SK_Forced.fbx"
    forced_fbx.touch()
    override_fbx = tmp_path / "SM_Correct.fbx"
    override_fbx.touch()
    forced_folder = tmp_path / "tex"
    forced_folder.mkdir()

    report = parts.Report()
    registry = naming.SlugRegistry()
    overrides = {"fakepart": {"fbx": str(override_fbx)}}  # part_id 与实际解析结果一致

    recipe = parts.build_recipe(unity_root, "ap_fakepart", 0, overrides, registry, report,
                                 forced={"fbx": str(forced_fbx), "folder": str(forced_folder)})

    assert recipe is not None
    assert not report.errors
    assert recipe["fbx"] == override_fbx

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


def test_resolve_override_path_res_passthrough(tmp_path):
    """res:// 开头的 override 原样直通（指向 Godot 仓库内资产：不拼 unity_root、
    不进 _stage 拷贝）。eyes00→T_black 纯黑眼睛依赖此行为。"""
    v = parts._resolve_override_path("res://assets/avatar/common/T_black.png", tmp_path)
    assert v == "res://assets/avatar/common/T_black.png"
    assert isinstance(v, str)

def test_sample_id_names_a_new_part_from_the_same_asset(tmp_path):
    """samples.json 的 "id" 给同一个 Unity 资产另起新部件（SGODOT-229 NPC 专用变体）：原件与变体
    各自登记、互不冲突，overrides 按各自的 id 取。"""
    unity_root = _make_unity_root(tmp_path)
    plain_fbx = tmp_path / "SK_Plain.fbx"
    plain_fbx.touch()
    npc_fbx = tmp_path / "SK_Npc.fbx"
    npc_fbx.touch()
    report = parts.Report()
    registry = naming.SlugRegistry()
    overrides = {"fakepart": {"fbx": str(plain_fbx)}, "fakepart_npc_kai": {"fbx": str(npc_fbx)}}

    plain = parts.build_recipe(unity_root, "ap_fakepart", 0, overrides, registry, report)
    npc = parts.build_recipe(unity_root, "ap_fakepart", 0, overrides, registry, report, part_id="fakepart_npc_kai")

    assert not report.errors
    assert plain["id"] == "fakepart" and plain["fbx"] == plain_fbx
    assert npc["id"] == "fakepart_npc_kai" and npc["fbx"] == npc_fbx
    assert npc["slot"] == plain["slot"] and npc["unity_guid"] == plain["unity_guid"]

def test_sample_id_must_be_a_clean_slug_and_unique(tmp_path):
    unity_root = _make_unity_root(tmp_path)
    (tmp_path / "SK.fbx").touch()
    overrides = {"x": {"fbx": str(tmp_path / "SK.fbx")}}
    report = parts.Report()
    registry = naming.SlugRegistry()
    assert parts.build_recipe(unity_root, "ap_fakepart", 0, {}, registry, report, part_id="Bad Id") is None
    assert report.errors
    report = parts.Report()
    assert parts.build_recipe(unity_root, "ap_fakepart", 0, overrides, registry, report, part_id="x") is not None
    assert parts.build_recipe(unity_root, "ap_fakepart", 0, overrides, registry, report, part_id="x") is None   # 冲突
    assert any("冲突" in e for e in report.errors)
