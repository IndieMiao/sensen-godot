"""回归：Unity/Tuanjie 的 fileID anchor 可以是负数。

2026-09-01 真机 lookdev 排查发现，25 个部件里 24 个没有材质参数，根因是
unity_yaml._DOC_RE 只匹配 `&\\d+`，漏掉负号。于是 `--- !u!114 &-4807...` 这行
不被规约成 `---`，PyYAML 撞上未知标签 !u!114 直接抛 YAMLError，
load_documents 返回空列表 —— **整个文件都丢**，连后面带 m_Floats 的
Material 文档一起丢。表现是画面全用 shader 默认值、完全没有材质区分。
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import materials  # noqa: E402
import unity_yaml  # noqa: E402

FIXTURE = pathlib.Path(__file__).parent / "fixtures" / "M_neg_anchor_cloth.mat"


def test_negative_anchor_document_is_parsed():
    docs = unity_yaml.load_documents(FIXTURE)
    assert docs, "负数 anchor 让整个文件解析失败"
    assert any("Material" in d for d in docs), "Material 文档丢了"


def test_floats_extracted_from_file_with_negative_anchor():
    floats = materials.extract_floats(FIXTURE)
    # 按 URP Lit 真实语义映射：_Ksmooth→smoothness、_Kd→diffuse_strength
    assert floats["smoothness"] == 0.1
    assert floats["ao_strength"] == 0.3
    assert floats["diffuse_strength"] == 1.0
    assert floats["emission_strength"] == 0.3
    # _Kshadow 是 graph 内部 Lerp 系数，不对应任何 Godot 表面输入，不该被映射
    assert "shadow_value" not in floats


def test_monobehaviour_still_readable_alongside_negative_anchor():
    mb = unity_yaml.load_monobehaviour(FIXTURE)
    assert mb is not None
