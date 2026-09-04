extends GdUnitTestSuite
## canonical / checksum 的跨语言契约测试。
##
## 加载的 golden corpus 与 packages/blueprint-core/test/canonical.test.ts 是**同一份数据**
## （从 packages/blueprint-core/golden/corpus.json 拷来，见 tools/sync_blueprint_golden.sh），
## 且那份数据由一份独立的 Python 实现生成——不是把任一端的输出抄回来。任一端改了公式，
## 这里立刻炸。

const CORPUS := "res://tests/fixtures/blueprint_golden_corpus.json"

func _corpus() -> Dictionary:
	var text := FileAccess.get_file_as_string(CORPUS)
	assert_bool(text.is_empty()).is_false()
	return JSON.parse_string(text) as Dictionary

func test_golden_canonical_and_checksum_match_byte_for_byte() -> void:
	var entries: Array = _corpus().entries
	assert_int(entries.size()).is_greater_equal(3)
	for e in entries:
		var bp := FarmBlueprint.from_dict(e.blueprint)
		assert_object(bp).is_not_null()
		assert_str(bp.canonical()).is_equal(str(e.canonical))
		assert_str(bp.compute_checksum()).is_equal(str(e.checksum))

func test_golden_rejects_are_refused_by_the_loader() -> void:
	# 拒绝样本里既有类型/范围错误，也有结构错误；Godot 侧统一表现为 from_dict 返回 null。
	for r in _corpus().rejects:
		var bp := FarmBlueprint.from_dict(r.blueprint)
		assert_object(bp).is_null()

## r1 的公式不覆盖这四项，手改任意一项 checksum 都照样通过（2026-09-04 决策①收紧）。
## 在已解析的对象上改字段而不是改 JSON：改 grid 会让 mask 行列数对不上，被 _field_error
## 先一步拒掉，就测不到 canonical 本身覆盖没覆盖 grid 了（TS 侧同样做法）。
func test_checksum_now_covers_grid_cell_mm_play_area_and_reserved_bed() -> void:
	var raw: Dictionary = _corpus().entries[0].blueprint
	var base := FarmBlueprint.from_dict(raw).compute_checksum()
	var mutations: Array[Callable] = [
		func(b: FarmBlueprint): b.grid = Vector2i(2, 8),
		func(b: FarmBlueprint): b.cell_mm = 2000,
		func(b: FarmBlueprint): b.play_area_mm = 8000,
		func(b: FarmBlueprint): b.anchors.reserved_bed.cells[0] = Vector2i(2, 0),
	]
	for mutate in mutations:
		var bp := FarmBlueprint.from_dict(raw)
		assert_object(bp).is_not_null()
		mutate.call(bp)
		assert_str(bp.compute_checksum()).is_not_equal(base)

## 改显示名不该让已有存档失效。
func test_renaming_does_not_change_checksum() -> void:
	var raw: Dictionary = _corpus().entries[0].blueprint
	var base := FarmBlueprint.from_dict(raw)
	var d: Dictionary = raw.duplicate(true)
	d.name = "Renamed"
	assert_str(FarmBlueprint.from_dict(d).compute_checksum()).is_equal(base.compute_checksum())
