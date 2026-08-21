import materials

def test_find_material_files_multi_hit(tmp_path):
    (tmp_path / "M_skin_cloth.mat").touch()
    (tmp_path / "M_skin_cloth_2.mat").touch()
    (tmp_path / "M_skin_shoes.mat").touch()

    hits = materials.find_material_files(tmp_path, "cloth")
    assert [p.name for p in hits] == ["M_skin_cloth.mat", "M_skin_cloth_2.mat"]
    assert materials.find_material_files(tmp_path, "glass") == []

def test_find_material_file_is_first_of_find_material_files(tmp_path):
    (tmp_path / "M_skin_cloth.mat").touch()
    (tmp_path / "M_skin_cloth_2.mat").touch()

    assert materials.find_material_file(tmp_path, "cloth").name == "M_skin_cloth.mat"
    assert materials.find_material_file(tmp_path, "glass") is None
