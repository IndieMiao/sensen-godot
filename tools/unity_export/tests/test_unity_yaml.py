from pathlib import Path
import unity_yaml

FIX = Path(__file__).parent / "fixtures"

def test_load_monobehaviour_strips_tuanjie_tags():
    mb = unity_yaml.load_monobehaviour(FIX / "ap_test.asset")
    assert mb["partName"] == "cloth1"
    assert mb["partType"] == 3
    assert mb["mesh"]["guid"] == "ffeeddcc00112233445566778899aabb"
    assert mb["socketPrefab"]["fileID"] == 0

def test_load_missing_returns_none():
    assert unity_yaml.load_monobehaviour(FIX / "nope.asset") is None
