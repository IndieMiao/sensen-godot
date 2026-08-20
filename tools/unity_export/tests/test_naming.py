import naming, pytest

def test_slug():
    assert naming.slug("cloth1") == "cloth1"
    assert naming.slug("hairHat20") == "hairhat20"
    assert naming.slug("Glass 3_2") == "glass3_2"

def test_slot_from_part_type():
    assert naming.slot_name(3) == "cloth"
    assert naming.slot_name(13) == "glass"
    with pytest.raises(ValueError):
        naming.slot_name(99)

def test_unique_registry():
    reg = naming.SlugRegistry()
    assert reg.claim("cloth1") == "cloth1"
    with pytest.raises(ValueError):
        reg.claim("cloth1")
