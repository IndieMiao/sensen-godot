from pathlib import Path
import convention

def test_variant_folder(tmp_path):
    pak = tmp_path / "skin01"
    (pak / "skin01").mkdir(parents=True)
    (pak / "skin01_2").mkdir()
    (pak / "skin01" / "SK_dt_skin01.fbx").touch()
    (pak / "skin01_2" / "T_skin01_2_cloth_D.png").touch()
    assert convention.variant_dir(pak, "cloth1") == pak / "skin01"
    assert convention.variant_dir(pak, "cloth1_2") == pak / "skin01_2"

def test_find_texture(tmp_path):
    d = tmp_path
    (d / "T_skin01_cloth_D.png").touch()
    (d / "T_skin01_cloth_AO.png").touch()
    assert convention.find_texture(d, "cloth", "D").name == "T_skin01_cloth_D.png"
    assert convention.find_texture(d, "cloth", "AO").name == "T_skin01_cloth_AO.png"
    assert convention.find_texture(d, "shoes", "D") is None
