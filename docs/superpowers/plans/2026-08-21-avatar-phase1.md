# Avatar 模块 Godot 一期实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在本仓库落地 avatar 部件 加载/切换/保存 的 Godot 基础框架：数据层、异步加载、双装配策略（直挂/合并）、换装场景、压测场景，以及从 Unity 工程迁移样例资产的自动化转换工具。

**Architecture:** 自包含 `modules/avatar`（数据/目录/加载/装配/存档，零业务依赖）+ 转换工具两阶段管线（Python 解析 Unity YAML → Godot headless 提取网格/生成资源）+ 两个演示场景。装配采用"换装即合并"（bake-on-dress）为默认策略，直挂策略保留作调试对比。

**Tech Stack:** Godot 4.7.2 stable（GDScript，mobile 渲染器）、gdUnit4 v6.2.1（单测）、Python 3 + PyYAML + pytest（转换工具）。

**Spec:** `docs/superpowers/specs/2026-08-21-avatar-godot-design.md`（已批准，本计划所有需求以它为准）

## Global Constraints

- Godot **4.7.2 stable**，本机命令 `godot`；只用 GDScript，渲染方法 `mobile`。
- 部件 ID 是语义 slug（如 `cloth1`），全库唯一；Unity GUID 仅作 `unity_guid` 溯源字段。
- 槽位 14 个，全部来自 `slot_table.tres` 数据，任何代码不得硬编码槽位清单。
- 存档本地 JSON `user://avatar/outfit_<user_id>.json`，格式 `{"version":1,"slots":{...}}`。
- PartCache 默认上限 64MB（可配）。角色 mesh `cast_shadow = OFF`。
- 性能验收基准：中端真机 15 角色 60fps（压测场景提供数据）。
- 一期不做：服务器 API、原生嵌入、PCK 下载（`ContentRepo.ensure_available` 留接缝返回 OK）、贴图 atlas、AIGC 截图、pose 系统。
- Unity 工程只读，路径 `../sensen-unity`（相对本仓库根）。**注意：Unity 的 .meta GUID 已被 Tuanjie 引擎混淆（base64 blob），不可用 .meta 做 hex GUID→路径反查**；转换工具用三级解析：Addressables 表 → 目录/命名约定 → overrides.json 人工兜底。
- 测试统一入口：`tools/run_tests.sh`（内部先 `godot --headless --path . --import` 再跑 gdUnit4）。
- 每个任务收尾必须：跑通该任务全部测试 + `git commit`。

## 文件结构总览（最终状态）

```
project.godot / .gitignore / README.md
addons/gdUnit4/                       # 测试框架（vendored v6.2.1）
modules/avatar/
  data/slot_def.gd  slot_table.gd  slot_table.tres  avatar_config.gd
  catalog/part_catalog.gd            # + AvatarPartMeta
  content/content_repo.gd
  loading/part_loader.gd  part_cache.gd
  assembly/part_def.gd  avatar_rig.gd  rig_activity.gd
           assembler.gd  assembler_direct.gd  assembler_merged.gd
  persistence/outfit_store.gd
  shaders/avatar_toon.gdshader  material_factory.gd
  avatar_service.gd                  # autoload 门面
assets/avatar/                       # 转换工具产出（source/ parts/ thumbs/ base/ parts_manifest.json）
scenes/dressing_room/  scenes/stress_test/
tools/run_tests.sh
tools/pipeline/extract_parts.gd  gen_base_rig.gd
tools/unity_export/  (Python: convert.py unity_yaml.py addressables.py resolve.py
                      materials.py naming.py convention.py manifest.py validate.py
                      samples.json overrides.json requirements.txt tests/)
tests/                               # gdUnit4 测试与 fixtures
docs/mobile_export.md
```

---

### Task 1: Godot 工程骨架 + gdUnit4

**Files:**
- Create: `project.godot`, `.gitignore`, `icon.svg`, `tools/run_tests.sh`, `tests/test_smoke.gd`
- Vendor: `addons/gdUnit4/`（v6.2.1）

**Interfaces:**
- Produces: 可运行的 Godot 工程；测试命令 `tools/run_tests.sh [suite_path]`（默认 `res://tests`，失败时非零退出码）。后续所有任务的测试都经它运行。

- [ ] **Step 1: 写工程文件**

`project.godot`:
```ini
; Engine configuration file.
config_version=5

[application]
config/name="SensenAvatar"
config/features=PackedStringArray("4.7", "GL Compatibility")

[editor_plugins]
enabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg")

[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
```

`.gitignore`:
```
.godot/
*.tmp
tools/unity_export/.venv/
tools/unity_export/__pycache__/
tools/unity_export/**/__pycache__/
tools/unity_export/out/
*.swp
```

`icon.svg`（Godot 默认图标即可）:
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><rect width="128" height="128" fill="#4a8" rx="16"/><text x="64" y="80" font-size="56" text-anchor="middle" fill="#fff">A</text></svg>
```

- [ ] **Step 2: 引入 gdUnit4 v6.2.1**

```bash
git clone --depth 1 --branch v6.2.1 https://github.com/MikeSchulze/gdUnit4 /tmp/gdunit4_checkout
mkdir -p addons && cp -R /tmp/gdunit4_checkout/addons/gdUnit4 addons/gdUnit4
rm -rf /tmp/gdunit4_checkout
```

- [ ] **Step 3: 写测试运行脚本 `tools/run_tests.sh`**

```bash
#!/usr/bin/env bash
# 用法: tools/run_tests.sh [res://tests/子目录]
set -e
cd "$(dirname "$0")/.."
export GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
"$GODOT_BIN" --headless --path . --import > /dev/null 2>&1 || true
exec ./addons/gdUnit4/runtest.sh -a "${1:-res://tests}"
```
`chmod +x tools/run_tests.sh`

- [ ] **Step 4: 写冒烟测试 `tests/test_smoke.gd`**

```gdscript
extends GdUnitTestSuite

func test_project_boots() -> void:
	assert_bool(true).is_true()

func test_renderer_is_mobile() -> void:
	assert_str(str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))).is_equal("mobile")
```

- [ ] **Step 5: 运行测试确认通过**

Run: `tools/run_tests.sh res://tests/test_smoke.gd`
Expected: 2 个用例 PASS，退出码 0。若 gdUnit4 与 4.7 不兼容报错，改用其 master 最新 tag 重新 vendor 并在提交信息注明版本。

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: Godot 4.7 工程骨架 + gdUnit4 v6.2.1 + 测试入口"
```

---

### Task 2: 数据层 — SlotTable + AvatarConfig

**Files:**
- Create: `modules/avatar/data/slot_def.gd`, `modules/avatar/data/slot_table.gd`, `modules/avatar/data/slot_table.tres`, `modules/avatar/data/avatar_config.gd`
- Test: `tests/data/test_slot_table.gd`, `tests/data/test_avatar_config.gd`

**Interfaces:**
- Produces:
  - `AvatarSlotDef`（Resource）: `slot_name: StringName`, `attach_bone: String`, `required: bool`, `default_part: String`
  - `AvatarSlotTable`（Resource）: `slots: Array[AvatarSlotDef]`, `slot(name: StringName) -> AvatarSlotDef`, `slot_names() -> Array[StringName]`, `default_config() -> AvatarConfig`
  - `AvatarConfig`（RefCounted）: `slots: Dictionary`（StringName→String，`""`=空）, `duplicate_config()`, `changed_slots(other) -> Array[StringName]`, `to_json_text() -> String`, `static from_json_text(text) -> AvatarConfig`（非法返回 null）
  - 资源 `res://modules/avatar/data/slot_table.tres`：14 槽位数据

- [ ] **Step 1: 写失败测试**

`tests/data/test_avatar_config.gd`:
```gdscript
extends GdUnitTestSuite

func test_roundtrip_json() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "cloth1"
	cfg.slots[&"glass"] = ""
	var text := cfg.to_json_text()
	var back := AvatarConfig.from_json_text(text)
	assert_object(back).is_not_null()
	assert_str(back.slots[&"cloth"]).is_equal("cloth1")
	assert_str(back.slots[&"glass"]).is_equal("")

func test_from_json_rejects_garbage() -> void:
	assert_object(AvatarConfig.from_json_text("not json")).is_null()
	assert_object(AvatarConfig.from_json_text("[1,2]")).is_null()
	assert_object(AvatarConfig.from_json_text('{"version": 99, "slots": {}}')).is_null()
	assert_object(AvatarConfig.from_json_text('{"version": 1, "slots": {"cloth": 5}}')).is_null()

func test_changed_slots() -> void:
	var a := AvatarConfig.new(); a.slots[&"cloth"] = "cloth1"; a.slots[&"shoes"] = "shoes1"
	var b := AvatarConfig.new(); b.slots[&"cloth"] = "cloth2"; b.slots[&"shoes"] = "shoes1"; b.slots[&"glass"] = "glass1"
	var changed := a.changed_slots(b)
	changed.sort()
	assert_array(changed).contains_exactly([&"cloth", &"glass"])
```

`tests/data/test_slot_table.gd`:
```gdscript
extends GdUnitTestSuite

const TABLE := preload("res://modules/avatar/data/slot_table.tres")

func test_has_14_slots() -> void:
	assert_int(TABLE.slots.size()).is_equal(14)

func test_required_slots_have_defaults() -> void:
	for s in TABLE.slots:
		if s.required:
			assert_str(s.default_part).is_not_empty()

func test_lookup() -> void:
	assert_object(TABLE.slot(&"cloth")).is_not_null()
	assert_object(TABLE.slot(&"nope")).is_null()

func test_default_config_covers_all_slots() -> void:
	var cfg := TABLE.default_config()
	assert_int(cfg.slots.size()).is_equal(14)
	assert_str(cfg.slots[&"body"]).is_equal("body00")
	assert_str(cfg.slots[&"backpack"]).is_equal("")
```

- [ ] **Step 2: 运行确认失败**

Run: `tools/run_tests.sh res://tests/data`
Expected: FAIL/解析错误（类不存在、tres 不存在）。

- [ ] **Step 3: 实现**

`modules/avatar/data/slot_def.gd`:
```gdscript
class_name AvatarSlotDef
extends Resource

@export var slot_name: StringName = &""
@export var attach_bone: String = ""
@export var required: bool = false
@export var default_part: String = ""
```

`modules/avatar/data/avatar_config.gd`:
```gdscript
class_name AvatarConfig
extends RefCounted

const FORMAT_VERSION := 1

## StringName(槽位) -> String(部件id)，"" 表示该槽位为空
var slots: Dictionary = {}

func duplicate_config() -> AvatarConfig:
	var c := AvatarConfig.new()
	c.slots = slots.duplicate()
	return c

func changed_slots(other: AvatarConfig) -> Array[StringName]:
	var out: Array[StringName] = []
	var keys := {}
	for k in slots: keys[k] = true
	for k in other.slots: keys[k] = true
	for k in keys:
		if String(slots.get(k, "")) != String(other.slots.get(k, "")):
			out.append(k)
	return out

func to_json_text() -> String:
	var slot_dict := {}
	for k in slots:
		slot_dict[String(k)] = slots[k]
	return JSON.stringify({"version": FORMAT_VERSION, "slots": slot_dict}, "\t")

static func from_json_text(text: String) -> AvatarConfig:
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return null
	if int(data.get("version", 0)) != FORMAT_VERSION:
		return null
	var raw = data.get("slots")
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var cfg := AvatarConfig.new()
	for k in raw:
		if typeof(raw[k]) != TYPE_STRING:
			return null
		cfg.slots[StringName(k)] = raw[k]
	return cfg
```

`modules/avatar/data/slot_table.gd`:
```gdscript
class_name AvatarSlotTable
extends Resource

@export var slots: Array[AvatarSlotDef] = []

func slot(name: StringName) -> AvatarSlotDef:
	for s in slots:
		if s.slot_name == name:
			return s
	return null

func slot_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in slots:
		out.append(s.slot_name)
	return out

func default_config() -> AvatarConfig:
	var cfg := AvatarConfig.new()
	for s in slots:
		cfg.slots[s.slot_name] = s.default_part
	return cfg
```

`modules/avatar/data/slot_table.tres` —— 14 槽位数据。骨骼名来自 Unity 基础骨架 `SK_DtBase`（62 骨），挂点骨骼按功能指定（Unity 原工程 socket 在 prefab 根上、不随骨骼，属于缺陷，此处直接修正；Task 11 校验骨骼名存在）：

```
[gd_resource type="Resource" script_class="AvatarSlotTable" load_steps=17 format=3]

[ext_resource type="Script" path="res://modules/avatar/data/slot_table.gd" id="1"]
[ext_resource type="Script" path="res://modules/avatar/data/slot_def.gd" id="2"]

[sub_resource type="Resource" id="s01"]
script = ExtResource("2")
slot_name = &"body"
attach_bone = "Root_M"
required = true
default_part = "body00"

[sub_resource type="Resource" id="s02"]
script = ExtResource("2")
slot_name = &"eyes"
attach_bone = "Head_M"
required = true
default_part = "eyes00"

[sub_resource type="Resource" id="s03"]
script = ExtResource("2")
slot_name = &"hairHat"
attach_bone = "Head_M"
required = true
default_part = "hairhat00"

[sub_resource type="Resource" id="s04"]
script = ExtResource("2")
slot_name = &"cloth"
attach_bone = "Spine1_M"
required = true
default_part = "cloth00"

[sub_resource type="Resource" id="s05"]
script = ExtResource("2")
slot_name = &"shoes"
attach_bone = "Root_M"
required = true
default_part = "shoes00"

[sub_resource type="Resource" id="s06"]
script = ExtResource("2")
slot_name = &"shoulderBag"
attach_bone = "Chest_M"
required = false
default_part = ""

[sub_resource type="Resource" id="s07"]
script = ExtResource("2")
slot_name = &"messengerBag"
attach_bone = "Chest_M"
required = false
default_part = ""

[sub_resource type="Resource" id="s08"]
script = ExtResource("2")
slot_name = &"pocketBag"
attach_bone = "RootPart1_M"
required = false
default_part = ""

[sub_resource type="Resource" id="s09"]
script = ExtResource("2")
slot_name = &"backpack"
attach_bone = "Chest_M"
required = false
default_part = ""

[sub_resource type="Resource" id="s10"]
script = ExtResource("2")
slot_name = &"headset"
attach_bone = "Head_M"
required = false
default_part = ""

[sub_resource type="Resource" id="s11"]
script = ExtResource("2")
slot_name = &"handleft"
attach_bone = "Wrist_L"
required = false
default_part = ""

[sub_resource type="Resource" id="s12"]
script = ExtResource("2")
slot_name = &"handright"
attach_bone = "Wrist_R"
required = false
default_part = ""

[sub_resource type="Resource" id="s13"]
script = ExtResource("2")
slot_name = &"mask"
attach_bone = "Head_M"
required = false
default_part = ""

[sub_resource type="Resource" id="s14"]
script = ExtResource("2")
slot_name = &"glass"
attach_bone = "Head_M"
required = false
default_part = ""

[resource]
script = ExtResource("1")
slots = [SubResource("s01"), SubResource("s02"), SubResource("s03"), SubResource("s04"), SubResource("s05"), SubResource("s06"), SubResource("s07"), SubResource("s08"), SubResource("s09"), SubResource("s10"), SubResource("s11"), SubResource("s12"), SubResource("s13"), SubResource("s14")]
```

- [ ] **Step 4: 运行测试确认通过**

Run: `tools/run_tests.sh res://tests/data`
Expected: 全 PASS。

- [ ] **Step 5: Commit**

```bash
git add modules/avatar/data tests/data
git commit -m "feat(avatar): 数据层 SlotTable(14槽位数据驱动) + AvatarConfig 序列化/diff"
```

---

### Task 3: PartCatalog — manifest 解析

**Files:**
- Create: `modules/avatar/catalog/part_catalog.gd`
- Test: `tests/catalog/test_part_catalog.gd`, `tests/fixtures/manifest_valid.json`, `tests/fixtures/manifest_bad.json`

**Interfaces:**
- Consumes: 无（独立于 Task 2）
- Produces:
  - `AvatarPartMeta`（RefCounted，内部类于 part_catalog.gd）: `id: String`, `slot: StringName`, `attach: String`("mesh"|"socket"), `tier: int`, `pack: String`, `res_path: String`, `thumb_path: String`
  - `PartCatalog`（RefCounted）: `static load_from_file(path: String) -> PartCatalog`（非法返回 null）, `part(id: String) -> AvatarPartMeta`, `has_part(id) -> bool`, `parts_for_slot(slot: StringName) -> Array`, `size() -> int`
  - manifest schema 以 spec §4.3 为准

- [ ] **Step 1: 写 fixtures 和失败测试**

`tests/fixtures/manifest_valid.json`:
```json
{
	"version": 1,
	"parts": [
		{ "id": "fx_cloth_a", "slot": "cloth", "attach": "mesh", "tier": 0, "pack": "builtin",
		  "res": "res://tests/fixtures/parts/fx_cloth_a.tres", "thumb": "", "unity_guid": "aa" },
		{ "id": "fx_cloth_b", "slot": "cloth", "attach": "mesh", "tier": 0, "pack": "builtin",
		  "res": "res://tests/fixtures/parts/fx_cloth_b.tres", "thumb": "", "unity_guid": "bb" },
		{ "id": "fx_glass_a", "slot": "glass", "attach": "socket", "tier": 0, "pack": "builtin",
		  "res": "res://tests/fixtures/parts/fx_glass_a.tres", "thumb": "", "unity_guid": "cc" }
	]
}
```

`tests/fixtures/manifest_bad.json`:
```json
{ "version": 1, "parts": [ { "id": "x", "slot": "cloth" } ] }
```

`tests/catalog/test_part_catalog.gd`:
```gdscript
extends GdUnitTestSuite

func test_load_valid() -> void:
	var cat := PartCatalog.load_from_file("res://tests/fixtures/manifest_valid.json")
	assert_object(cat).is_not_null()
	assert_int(cat.size()).is_equal(3)
	assert_bool(cat.has_part("fx_cloth_a")).is_true()
	var meta := cat.part("fx_cloth_a")
	assert_str(String(meta.slot)).is_equal("cloth")
	assert_str(meta.attach).is_equal("mesh")
	assert_int(cat.parts_for_slot(&"cloth").size()).is_equal(2)
	assert_int(cat.parts_for_slot(&"shoes").size()).is_equal(0)

func test_load_missing_file_returns_null() -> void:
	assert_object(PartCatalog.load_from_file("res://tests/fixtures/nope.json")).is_null()

func test_load_bad_schema_returns_null() -> void:
	assert_object(PartCatalog.load_from_file("res://tests/fixtures/manifest_bad.json")).is_null()

func test_duplicate_id_returns_null() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/manifest_valid.json")
	var data = JSON.parse_string(text)
	data.parts.append(data.parts[0])
	var tmp := "user://dup_manifest.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_object(PartCatalog.load_from_file(tmp)).is_null()
```

- [ ] **Step 2: 运行确认失败**

Run: `tools/run_tests.sh res://tests/catalog`
Expected: FAIL（PartCatalog 不存在）。

- [ ] **Step 3: 实现 `modules/avatar/catalog/part_catalog.gd`**

```gdscript
class_name PartCatalog
extends RefCounted

const MANIFEST_VERSION := 1
const REQUIRED_FIELDS := ["id", "slot", "attach", "res"]

class AvatarPartMeta:
	extends RefCounted
	var id: String
	var slot: StringName
	var attach: String
	var tier: int = 0
	var pack: String = "builtin"
	var res_path: String
	var thumb_path: String = ""
	var offset_pos := Vector3.ZERO
	var offset_rot_deg := Vector3.ZERO
	var offset_scale := Vector3.ONE

var _by_id: Dictionary = {}
var _by_slot: Dictionary = {}

static func load_from_file(path: String) -> PartCatalog:
	if not FileAccess.file_exists(path):
		push_warning("PartCatalog: manifest 不存在 %s" % path)
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != MANIFEST_VERSION:
		push_warning("PartCatalog: manifest 版本/格式非法 %s" % path)
		return null
	if typeof(data.get("parts")) != TYPE_ARRAY:
		return null
	var cat := PartCatalog.new()
	for entry in data.parts:
		if typeof(entry) != TYPE_DICTIONARY:
			return null
		for field in REQUIRED_FIELDS:
			if not entry.has(field):
				push_warning("PartCatalog: 缺字段 %s: %s" % [field, str(entry)])
				return null
		var meta := AvatarPartMeta.new()
		meta.id = entry.id
		meta.slot = StringName(entry.slot)
		meta.attach = entry.attach
		meta.tier = int(entry.get("tier", 0))
		meta.pack = str(entry.get("pack", "builtin"))
		meta.res_path = entry.res
		meta.thumb_path = str(entry.get("thumb", ""))
		var off = entry.get("offset")
		if typeof(off) == TYPE_DICTIONARY:
			meta.offset_pos = _vec3(off.get("pos"), Vector3.ZERO)
			meta.offset_rot_deg = _vec3(off.get("rot"), Vector3.ZERO)
			meta.offset_scale = _vec3(off.get("scale"), Vector3.ONE)
		if meta.attach != "mesh" and meta.attach != "socket":
			return null
		if cat._by_id.has(meta.id):
			push_warning("PartCatalog: 重复 id %s" % meta.id)
			return null
		cat._by_id[meta.id] = meta
		if not cat._by_slot.has(meta.slot):
			cat._by_slot[meta.slot] = []
		cat._by_slot[meta.slot].append(meta)
	return cat

static func _vec3(v, fallback: Vector3) -> Vector3:
	if typeof(v) == TYPE_ARRAY and v.size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fallback

func part(id: String) -> AvatarPartMeta:
	return _by_id.get(id)

func has_part(id: String) -> bool:
	return _by_id.has(id)

func parts_for_slot(slot: StringName) -> Array:
	return _by_slot.get(slot, [])

func size() -> int:
	return _by_id.size()

func all_ids() -> Array:
	return _by_id.keys()
```

- [ ] **Step 4: 运行测试确认通过**

Run: `tools/run_tests.sh res://tests/catalog`
Expected: 全 PASS。

- [ ] **Step 5: Commit**

```bash
git add modules/avatar/catalog tests/catalog tests/fixtures
git commit -m "feat(avatar): PartCatalog manifest 解析（元数据与资源本体分离）"
```

---

### Task 4: OutfitStore — 本地 JSON 存档

**Files:**
- Create: `modules/avatar/persistence/outfit_store.gd`
- Test: `tests/persistence/test_outfit_store.gd`

**Interfaces:**
- Consumes: `AvatarConfig`（Task 2：`to_json_text` / `from_json_text`）
- Produces: `LocalOutfitStore`（RefCounted）: `var base_dir: String = "user://avatar"`, `save_outfit(user_id: String, config: AvatarConfig) -> Error`, `load_outfit(user_id: String) -> AvatarConfig`（无档/损坏返回 null；损坏文件改名 `.corrupt` 备份）

- [ ] **Step 1: 写失败测试 `tests/persistence/test_outfit_store.gd`**

```gdscript
extends GdUnitTestSuite

var store: LocalOutfitStore

func before_test() -> void:
	store = LocalOutfitStore.new()
	store.base_dir = "user://test_outfits"

func after_test() -> void:
	var dir := DirAccess.open("user://")
	if dir and dir.dir_exists("test_outfits"):
		for f in DirAccess.get_files_at("user://test_outfits"):
			dir.remove("test_outfits/" + f)
		dir.remove("test_outfits")

func test_save_then_load_roundtrip() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "cloth1"
	assert_int(store.save_outfit("u1", cfg)).is_equal(OK)
	var back := store.load_outfit("u1")
	assert_object(back).is_not_null()
	assert_str(back.slots[&"cloth"]).is_equal("cloth1")

func test_load_missing_returns_null() -> void:
	assert_object(store.load_outfit("ghost")).is_null()

func test_corrupt_file_backed_up_and_null() -> void:
	DirAccess.make_dir_recursive_absolute("user://test_outfits")
	var f := FileAccess.open("user://test_outfits/outfit_u2.json", FileAccess.WRITE)
	f.store_string("{{{ not json")
	f.close()
	assert_object(store.load_outfit("u2")).is_null()
	assert_bool(FileAccess.file_exists("user://test_outfits/outfit_u2.json.corrupt")).is_true()
	assert_bool(FileAccess.file_exists("user://test_outfits/outfit_u2.json")).is_false()

func test_user_id_sanitized() -> void:
	var cfg := AvatarConfig.new()
	assert_int(store.save_outfit("a/../b", cfg)).is_equal(OK)
	assert_bool(FileAccess.file_exists("user://test_outfits/outfit_a_.._b.json")).is_true()
```

- [ ] **Step 2: 运行确认失败**

Run: `tools/run_tests.sh res://tests/persistence`
Expected: FAIL。

- [ ] **Step 3: 实现 `modules/avatar/persistence/outfit_store.gd`**

```gdscript
class_name LocalOutfitStore
extends RefCounted

var base_dir: String = "user://avatar"

func save_outfit(user_id: String, config: AvatarConfig) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(base_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var f := FileAccess.open(_path_for(user_id), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(config.to_json_text())
	f.close()
	return OK

func load_outfit(user_id: String) -> AvatarConfig:
	var path := _path_for(user_id)
	if not FileAccess.file_exists(path):
		return null
	var cfg := AvatarConfig.from_json_text(FileAccess.get_file_as_string(path))
	if cfg == null:
		push_warning("OutfitStore: 存档损坏，备份并回退默认: %s" % path)
		var dir := DirAccess.open(base_dir)
		if dir:
			dir.rename(path.get_file(), path.get_file() + ".corrupt")
	return cfg

func _path_for(user_id: String) -> String:
	var safe := user_id.replace("/", "_").replace("\\", "_").replace(":", "_")
	return base_dir.path_join("outfit_%s.json" % safe)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `tools/run_tests.sh res://tests/persistence`
Expected: 全 PASS。

- [ ] **Step 5: Commit**

```bash
git add modules/avatar/persistence tests/persistence
git commit -m "feat(avatar): 本地 JSON 存档 OutfitStore（损坏备份回退）"
```

---

### Task 5: PartCache（LRU）+ ContentRepo 接缝

**Files:**
- Create: `modules/avatar/loading/part_cache.gd`, `modules/avatar/content/content_repo.gd`
- Test: `tests/loading/test_part_cache.gd`

**Interfaces:**
- Consumes: 无
- Produces:
  - `PartCache`（RefCounted）: `var max_bytes: int = 67108864`, `get_part(id: String) -> Resource`, `put(id: String, res: Resource, bytes: int) -> void`, `clear()`, `total_bytes() -> int`, `static estimate_resource_bytes(res_path: String) -> int`（文件长度启发式，最小 1024）
  - `ContentRepo`（RefCounted）: `ensure_available(part_id: String) -> Error`（一期恒返回 OK；二期替换为 PCK 查包/下载/挂载）

- [ ] **Step 1: 写失败测试 `tests/loading/test_part_cache.gd`**

```gdscript
extends GdUnitTestSuite

func test_put_get_and_touch() -> void:
	var cache := PartCache.new()
	cache.max_bytes = 100
	var r1 := Resource.new()
	cache.put("a", r1, 40)
	assert_object(cache.get_part("a")).is_same(r1)
	assert_int(cache.total_bytes()).is_equal(40)

func test_evicts_lru_when_over_budget() -> void:
	var cache := PartCache.new()
	cache.max_bytes = 100
	cache.put("a", Resource.new(), 40)
	cache.put("b", Resource.new(), 40)
	assert_object(cache.get_part("a")).is_not_null() # touch a，b 变最旧
	cache.put("c", Resource.new(), 40)               # 超预算，踢 b
	assert_object(cache.get_part("b")).is_null()
	assert_object(cache.get_part("a")).is_not_null()
	assert_object(cache.get_part("c")).is_not_null()
	assert_int(cache.total_bytes()).is_equal(80)

func test_oversized_item_still_cached_alone() -> void:
	var cache := PartCache.new()
	cache.max_bytes = 10
	cache.put("big", Resource.new(), 999)
	assert_object(cache.get_part("big")).is_not_null()
	cache.put("b2", Resource.new(), 999)
	assert_object(cache.get_part("big")).is_null()

func test_clear() -> void:
	var cache := PartCache.new()
	cache.put("a", Resource.new(), 10)
	cache.clear()
	assert_object(cache.get_part("a")).is_null()
	assert_int(cache.total_bytes()).is_equal(0)

func test_content_repo_stub_ok() -> void:
	assert_int(ContentRepo.new().ensure_available("anything")).is_equal(OK)
```

- [ ] **Step 2: 运行确认失败**

Run: `tools/run_tests.sh res://tests/loading`
Expected: FAIL。

- [ ] **Step 3: 实现**

`modules/avatar/content/content_repo.gd`:
```gdscript
class_name ContentRepo
extends RefCounted

## 分发接缝：一期所有资源在主包内，恒可用。
## 二期实现：按 manifest.pack 查 PCK → 未下载则下载校验 → load_resource_pack 挂载。
func ensure_available(_part_id: String) -> Error:
	return OK
```

`modules/avatar/loading/part_cache.gd`:
```gdscript
class_name PartCache
extends RefCounted

var max_bytes: int = 64 * 1024 * 1024

var _entries: Dictionary = {}  # id -> {res: Resource, bytes: int, tick: int}
var _total := 0
var _tick := 0

func get_part(id: String) -> Resource:
	var e = _entries.get(id)
	if e == null:
		return null
	_tick += 1
	e.tick = _tick
	return e.res

func put(id: String, res: Resource, bytes: int) -> void:
	if _entries.has(id):
		_total -= _entries[id].bytes
	_tick += 1
	_entries[id] = {"res": res, "bytes": bytes, "tick": _tick}
	_total += bytes
	_evict_over_budget(id)

func _evict_over_budget(keep_id: String) -> void:
	while _total > max_bytes and _entries.size() > 1:
		var oldest_id := ""
		var oldest_tick := _tick + 1
		for k in _entries:
			if k == keep_id:
				continue
			if _entries[k].tick < oldest_tick:
				oldest_tick = _entries[k].tick
				oldest_id = k
		if oldest_id == "":
			break
		_total -= _entries[oldest_id].bytes
		_entries.erase(oldest_id)

func clear() -> void:
	_entries.clear()
	_total = 0

func total_bytes() -> int:
	return _total

static func estimate_resource_bytes(res_path: String) -> int:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return 1024
	var n := int(f.get_length())
	f.close()
	return maxi(n, 1024)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `tools/run_tests.sh res://tests/loading`
Expected: 全 PASS。

- [ ] **Step 5: Commit**

```bash
git add modules/avatar/loading modules/avatar/content tests/loading
git commit -m "feat(avatar): PartCache LRU(按字节预算) + ContentRepo 分发接缝"
```

---

### Task 6: PartLoader — 异步加载器

**Files:**
- Create: `modules/avatar/loading/part_loader.gd`, `tests/fixtures/parts/fx_cloth_a.tres`, `tests/fixtures/parts/fx_cloth_b.tres`, `tests/fixtures/parts/fx_glass_a.tres`
- Test: `tests/loading/test_part_loader.gd`

**Interfaces:**
- Consumes: `PartCatalog.part(id) -> AvatarPartMeta`（`res_path`）、`PartCache`、`ContentRepo.ensure_available`
- Produces: `PartLoader`（Node）:
  - `signal load_finished(request_id: int, part_id: String, resource: Resource)`
  - `signal load_failed(request_id: int, part_id: String, err: int)`
  - `var catalog: PartCatalog`, `var cache: PartCache`, `var content_repo: ContentRepo`
  - `request_part(part_id: String) -> int`（返回递增 request_id；缓存命中也走 deferred 信号，调用方时序一致）
  - `cancel(request_id: int) -> void`（取消后不再发任何信号；底层加载继续并进缓存）
  - 同一资源并发请求合并为一次底层加载

注意：fixture `.tres` 引用 `part_def.gd`（Task 7 产物）。本任务先用**纯 Resource** fixture（不依赖 Task 7）：

`tests/fixtures/parts/fx_cloth_a.tres`（b/glass 同构，改 id 字段注释即可）:
```
[gd_resource type="BoxMesh" format=3]

[resource]
size = Vector3(0.1, 0.1, 0.1)
```

- [ ] **Step 1: 写失败测试 `tests/loading/test_part_loader.gd`**

```gdscript
extends GdUnitTestSuite

var loader: PartLoader
var finished: Array = []
var failed: Array = []

func before_test() -> void:
	loader = PartLoader.new()
	loader.catalog = PartCatalog.load_from_file("res://tests/fixtures/manifest_valid.json")
	loader.cache = PartCache.new()
	add_child(loader)
	finished = []
	failed = []
	loader.load_finished.connect(func(rid, pid, res): finished.append([rid, pid, res]))
	loader.load_failed.connect(func(rid, pid, err): failed.append([rid, pid, err]))

func after_test() -> void:
	loader.queue_free()

func _pump(frames := 300) -> void:
	for i in frames:
		if finished.size() + failed.size() > 0:
			return
		await get_tree().process_frame

func test_load_success() -> void:
	var rid := loader.request_part("fx_cloth_a")
	await _pump()
	assert_int(finished.size()).is_equal(1)
	assert_int(finished[0][0]).is_equal(rid)
	assert_str(finished[0][1]).is_equal("fx_cloth_a")
	assert_object(finished[0][2]).is_not_null()

func test_unknown_part_fails() -> void:
	loader.request_part("nope")
	await _pump()
	assert_int(failed.size()).is_equal(1)
	assert_int(failed[0][2]).is_equal(ERR_DOES_NOT_EXIST)

func test_cache_hit_second_load() -> void:
	loader.request_part("fx_cloth_a")
	await _pump()
	finished.clear()
	loader.request_part("fx_cloth_a")
	await _pump()
	assert_int(finished.size()).is_equal(1)
	assert_object(loader.cache.get_part("fx_cloth_a")).is_not_null()

func test_cancel_suppresses_signal() -> void:
	var rid := loader.request_part("fx_cloth_b")
	loader.cancel(rid)
	for i in 60:
		await get_tree().process_frame
	assert_int(finished.size()).is_equal(0)
	assert_int(failed.size()).is_equal(0)

func test_concurrent_same_part_merged() -> void:
	var r1 := loader.request_part("fx_glass_a")
	var r2 := loader.request_part("fx_glass_a")
	for i in 300:
		if finished.size() >= 2:
			break
		await get_tree().process_frame
	assert_int(finished.size()).is_equal(2)
	assert_bool(r1 != r2).is_true()
```

- [ ] **Step 2: 运行确认失败**

Run: `tools/run_tests.sh res://tests/loading`
Expected: 新增用例 FAIL（PartLoader 不存在）。

- [ ] **Step 3: 实现 `modules/avatar/loading/part_loader.gd`**

```gdscript
class_name PartLoader
extends Node

signal load_finished(request_id: int, part_id: String, resource: Resource)
signal load_failed(request_id: int, part_id: String, err: int)

var catalog: PartCatalog
var cache: PartCache
var content_repo: ContentRepo = ContentRepo.new()

var _next_id := 1
var _by_path: Dictionary = {}   # res_path -> {part_id: String, waiters: Array[int]}
var _cancelled: Dictionary = {} # request_id -> true

func request_part(part_id: String) -> int:
	var rid := _next_id
	_next_id += 1
	var meta = catalog.part(part_id) if catalog else null
	if meta == null:
		call_deferred("_fail", rid, part_id, ERR_DOES_NOT_EXIST)
		return rid
	var avail := content_repo.ensure_available(part_id)
	if avail != OK:
		call_deferred("_fail", rid, part_id, avail)
		return rid
	if cache:
		var hit := cache.get_part(part_id)
		if hit != null:
			call_deferred("_deliver", rid, part_id, hit)
			return rid
	if _by_path.has(meta.res_path):
		_by_path[meta.res_path].waiters.append(rid)
		return rid
	var err := ResourceLoader.load_threaded_request(meta.res_path)
	if err != OK:
		call_deferred("_fail", rid, part_id, err)
		return rid
	_by_path[meta.res_path] = {"part_id": part_id, "waiters": [rid]}
	set_process(true)
	return rid

func cancel(request_id: int) -> void:
	_cancelled[request_id] = true

func _process(_delta: float) -> void:
	if _by_path.is_empty():
		set_process(false)
		return
	for path in _by_path.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var entry = _by_path[path]
		_by_path.erase(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var res := ResourceLoader.load_threaded_get(path)
			if cache:
				cache.put(entry.part_id, res, PartCache.estimate_resource_bytes(path))
			for rid in entry.waiters:
				_deliver(rid, entry.part_id, res)
		else:
			for rid in entry.waiters:
				_fail(rid, entry.part_id, ERR_CANT_ACQUIRE_RESOURCE)

func _deliver(rid: int, part_id: String, res: Resource) -> void:
	if _cancelled.erase(rid):
		return
	load_finished.emit(rid, part_id, res)

func _fail(rid: int, part_id: String, err: int) -> void:
	if _cancelled.erase(rid):
		return
	load_failed.emit(rid, part_id, err)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `tools/run_tests.sh res://tests/loading`
Expected: 全 PASS（含 Task 5 用例）。

- [ ] **Step 5: Commit**

```bash
git add modules/avatar/loading/part_loader.gd tests/loading/test_part_loader.gd tests/fixtures/parts
git commit -m "feat(avatar): PartLoader 线程加载(请求合并/取消/缓存直供)"
```

---

### Task 7: PartDef + AvatarRig 状态机 + AssemblerDirect

**Files:**
- Create: `modules/avatar/assembly/part_def.gd`, `modules/avatar/assembly/assembler.gd`, `modules/avatar/assembly/assembler_direct.gd`, `modules/avatar/assembly/avatar_rig.gd`
- Create: `tests/fixtures/parts/fx_mesh_cloth.tres`, `tests/fixtures/parts/fx_mesh_cloth2.tres`, `tests/fixtures/parts/fx_socket_glass.tres`, `tests/fixtures/parts/fx_socket_glass_scene.tscn`, `tests/fixtures/manifest_rig.json`
- Test: `tests/assembly/test_avatar_rig.gd`

**Interfaces:**
- Consumes: `PartLoader`（信号/`request_part`/`cancel`）、`AvatarSlotTable`、`AvatarConfig`
- Produces:
  - `AvatarPartDef`（Resource）: `id: String`, `slot: StringName`, `attach: String`, `tier: int`, `mesh: Mesh`, `skin: Skin`, `scene: PackedScene`, `offset_pos/offset_rot_deg/offset_scale: Vector3`
  - `AvatarAssembler`（RefCounted）: `rebuild(rig: AvatarRig, parts: Dictionary) -> void`（parts: 槽位→AvatarPartDef，仅含已装部件）；受保护助手 `_sync_sockets(rig, parts)`
  - `AvatarAssemblerDirect`: 每 mesh 部件一个 `MeshInstance3D`（名 `mesh_<slot>`，`cast_shadow=OFF`），socket 部件 `BoneAttachment3D`（名 `socket_<slot>`）挂 `rig.skeleton` 下
  - `AvatarRig`（Node3D）:
    - `signal config_applied(config: AvatarConfig)`, `signal slot_applied(slot: StringName, part_id: String)`, `signal part_load_failed(slot: StringName, part_id: String, err: int)`
    - `@export var slot_table: AvatarSlotTable`；`var skeleton: Skeleton3D`（_ready 自动找子树第一个，也可先手动赋值）；`var assembler: AvatarAssembler`（本任务默认 Direct，Task 8 改默认 Merged）
    - `setup(loader: PartLoader) -> void`；`apply_config(config) -> void`（初次调用=批量：全部到货才 rebuild+显示）；`equip(slot, part_id)`；`unequip(slot)`（required 槽回落 default_part）；`current_config() -> AvatarConfig`
    - 竞态语义：同槽位新请求会 `cancel` 旧请求；失败保持原状并发信号；required 槽初次加载失败自动改请求 default_part

- [ ] **Step 1: 写 fixtures**

`tests/fixtures/parts/fx_mesh_cloth.tres`:
```
[gd_resource type="Resource" script_class="AvatarPartDef" load_steps=3 format=3]

[ext_resource type="Script" path="res://modules/avatar/assembly/part_def.gd" id="1"]

[sub_resource type="BoxMesh" id="m1"]
size = Vector3(0.2, 0.2, 0.2)

[resource]
script = ExtResource("1")
id = "fx_mesh_cloth"
slot = &"cloth"
attach = "mesh"
mesh = SubResource("m1")
```

`tests/fixtures/parts/fx_mesh_cloth2.tres`: 同上，`id = "fx_mesh_cloth2"`，`size = Vector3(0.3, 0.3, 0.3)`。

`tests/fixtures/parts/fx_socket_glass_scene.tscn`:
```
[gd_scene load_steps=2 format=3]

[sub_resource type="BoxMesh" id="m1"]
size = Vector3(0.05, 0.05, 0.05)

[node name="FxGlass" type="MeshInstance3D"]
mesh = SubResource("m1")
```

`tests/fixtures/parts/fx_socket_glass.tres`:
```
[gd_resource type="Resource" script_class="AvatarPartDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://modules/avatar/assembly/part_def.gd" id="1"]
[ext_resource type="PackedScene" path="res://tests/fixtures/parts/fx_socket_glass_scene.tscn" id="2"]

[resource]
script = ExtResource("1")
id = "fx_socket_glass"
slot = &"glass"
attach = "socket"
scene = ExtResource("2")
```
（注意 load_steps=3，两个 ext_resource；执行时以 Godot 实际能加载为准）

`tests/fixtures/manifest_rig.json`:
```json
{
	"version": 1,
	"parts": [
		{ "id": "fx_mesh_cloth",  "slot": "cloth", "attach": "mesh",   "res": "res://tests/fixtures/parts/fx_mesh_cloth.tres" },
		{ "id": "fx_mesh_cloth2", "slot": "cloth", "attach": "mesh",   "res": "res://tests/fixtures/parts/fx_mesh_cloth2.tres" },
		{ "id": "fx_socket_glass","slot": "glass", "attach": "socket", "res": "res://tests/fixtures/parts/fx_socket_glass.tres" },
		{ "id": "fx_broken",      "slot": "mask",  "attach": "mesh",   "res": "res://tests/fixtures/parts/does_not_exist.tres" }
	]
}
```

- [ ] **Step 2: 写失败测试 `tests/assembly/test_avatar_rig.gd`**

```gdscript
extends GdUnitTestSuite

var rig: AvatarRig
var loader: PartLoader

## 测试用槽位表：只留 cloth(required)/glass/mask，避免依赖美术资产
func _mini_slot_table() -> AvatarSlotTable:
	var t := AvatarSlotTable.new()
	for def in [[&"cloth", true, "fx_mesh_cloth"], [&"glass", false, ""], [&"mask", false, ""]]:
		var s := AvatarSlotDef.new()
		s.slot_name = def[0]
		s.attach_bone = "Bone_A"
		s.required = def[1]
		s.default_part = def[2]
		t.slots.append(s)
	return t

func before_test() -> void:
	loader = PartLoader.new()
	loader.catalog = PartCatalog.load_from_file("res://tests/fixtures/manifest_rig.json")
	loader.cache = PartCache.new()
	add_child(loader)
	rig = AvatarRig.new()
	rig.slot_table = _mini_slot_table()
	rig.assembler = AvatarAssemblerDirect.new()  # 本套用例断言 Direct 策略的节点结构，不随默认策略变化
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	skel.add_bone("Bone_A")
	rig.add_child(skel)
	add_child(rig)
	rig.setup(loader)

func after_test() -> void:
	rig.queue_free()
	loader.queue_free()

func _await_signal(sig: Signal, frames := 300) -> Array:
	var hits: Array = []
	var cb := func(a = null, b = null, c = null): hits.append([a, b, c])
	sig.connect(cb)
	for i in frames:
		if hits.size() > 0:
			break
		await get_tree().process_frame
	sig.disconnect(cb)
	return hits

func test_apply_config_atomic_show() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth"
	cfg.slots[&"glass"] = "fx_socket_glass"
	rig.apply_config(cfg)
	assert_bool(rig.visible).is_false()
	var hits := await _await_signal(rig.config_applied)
	assert_int(hits.size()).is_equal(1)
	assert_bool(rig.visible).is_true()
	assert_object(rig.skeleton.get_node_or_null("mesh_cloth")).is_not_null()
	assert_object(rig.skeleton.get_node_or_null("socket_glass")).is_not_null()

func test_equip_switch_and_current_config() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied)
	rig.equip(&"cloth", "fx_mesh_cloth2")
	await _await_signal(rig.slot_applied)
	assert_str(rig.current_config().slots[&"cloth"]).is_equal("fx_mesh_cloth2")
	var mi: MeshInstance3D = rig.skeleton.get_node("mesh_cloth")
	assert_str(String(mi.get_meta("part_id"))).is_equal("fx_mesh_cloth2")

func test_rapid_switch_last_wins() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied)
	rig.equip(&"cloth", "fx_mesh_cloth2")
	rig.equip(&"cloth", "fx_mesh_cloth")
	for i in 120:
		await get_tree().process_frame
	assert_str(rig.current_config().slots[&"cloth"]).is_equal("fx_mesh_cloth")

func test_failed_part_keeps_slot_and_emits() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied)
	var fails := []
	rig.part_load_failed.connect(func(s, p, e): fails.append([s, p, e]))
	rig.equip(&"mask", "fx_broken")
	for i in 300:
		if fails.size() > 0:
			break
		await get_tree().process_frame
	assert_int(fails.size()).is_equal(1)
	assert_str(rig.current_config().slots.get(&"mask", "")).is_equal("")

func test_unequip_required_falls_back_to_default() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth2"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied)
	rig.unequip(&"cloth")
	for i in 120:
		await get_tree().process_frame
	assert_str(rig.current_config().slots[&"cloth"]).is_equal("fx_mesh_cloth")

func test_unequip_optional_clears_socket() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth"
	cfg.slots[&"glass"] = "fx_socket_glass"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied)
	rig.unequip(&"glass")
	for i in 60:
		await get_tree().process_frame
	assert_object(rig.skeleton.get_node_or_null("socket_glass")).is_null()
```

- [ ] **Step 3: 运行确认失败**

Run: `tools/run_tests.sh res://tests/assembly`
Expected: FAIL（类不存在）。

- [ ] **Step 4: 实现**

`modules/avatar/assembly/part_def.gd`:
```gdscript
class_name AvatarPartDef
extends Resource

@export var id: String = ""
@export var slot: StringName = &""
@export var attach: String = "mesh"  # "mesh" | "socket"
@export var tier: int = 0
@export var mesh: Mesh               # attach == "mesh"
@export var skin: Skin               # attach == "mesh"（可为 null：无骨骼的测试网格）
@export var scene: PackedScene       # attach == "socket"
@export var offset_pos: Vector3 = Vector3.ZERO
@export var offset_rot_deg: Vector3 = Vector3.ZERO
@export var offset_scale: Vector3 = Vector3.ONE
```

`modules/avatar/assembly/assembler.gd`:
```gdscript
class_name AvatarAssembler
extends RefCounted

func rebuild(_rig: AvatarRig, _parts: Dictionary) -> void:
	push_error("AvatarAssembler.rebuild 是抽象方法")

## socket 部件装配对两种策略一致：BoneAttachment3D(名 socket_<slot>) 挂 skeleton 下
func _sync_sockets(rig: AvatarRig, parts: Dictionary) -> void:
	var skeleton := rig.skeleton
	var wanted := {}
	for slot in parts:
		var def: AvatarPartDef = parts[slot]
		if def != null and def.attach == "socket" and def.scene != null:
			wanted[slot] = def
	for child in skeleton.get_children():
		if not String(child.name).begins_with("socket_"):
			continue
		var slot := StringName(String(child.name).trim_prefix("socket_"))
		var def: AvatarPartDef = wanted.get(slot)
		if def != null and String(child.get_meta("part_id", "")) == def.id:
			wanted.erase(slot)
		else:
			skeleton.remove_child(child)
			child.queue_free()
	for slot in wanted:
		var def: AvatarPartDef = wanted[slot]
		var attach := BoneAttachment3D.new()
		attach.name = "socket_%s" % slot
		attach.set_meta("part_id", def.id)
		skeleton.add_child(attach)
		var slot_def := rig.slot_table.slot(slot)
		if slot_def and skeleton.find_bone(slot_def.attach_bone) != -1:
			attach.bone_name = slot_def.attach_bone
		var inst := def.scene.instantiate()
		if inst is Node3D:
			inst.position = def.offset_pos
			inst.rotation_degrees = def.offset_rot_deg
			inst.scale = def.offset_scale
		attach.add_child(inst)
```

`modules/avatar/assembly/assembler_direct.gd`:
```gdscript
class_name AvatarAssemblerDirect
extends AvatarAssembler

func rebuild(rig: AvatarRig, parts: Dictionary) -> void:
	_sync_sockets(rig, parts)
	var skeleton := rig.skeleton
	for slot in rig.slot_table.slot_names():
		var node_name := "mesh_%s" % slot
		var existing := skeleton.get_node_or_null(NodePath(node_name))
		var def: AvatarPartDef = parts.get(slot)
		if def == null or def.attach != "mesh" or def.mesh == null:
			if existing:
				skeleton.remove_child(existing)
				existing.queue_free()
			continue
		var mi := existing as MeshInstance3D
		if mi == null:
			mi = MeshInstance3D.new()
			mi.name = node_name
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			skeleton.add_child(mi)
		mi.mesh = def.mesh
		mi.skin = def.skin
		mi.set_meta("part_id", def.id)
```

`modules/avatar/assembly/avatar_rig.gd`:
```gdscript
class_name AvatarRig
extends Node3D

signal config_applied(config: AvatarConfig)
signal slot_applied(slot: StringName, part_id: String)
signal part_load_failed(slot: StringName, part_id: String, err: int)

@export var slot_table: AvatarSlotTable
var skeleton: Skeleton3D
var assembler: AvatarAssembler = AvatarAssemblerDirect.new()
var loader: PartLoader

var _current: Dictionary = {}      # slot -> part_id（已应用）
var _desired: Dictionary = {}      # slot -> part_id（目标）
var _slot_request: Dictionary = {} # slot -> request_id（in-flight）
var _req_slot: Dictionary = {}     # request_id -> slot
var _loaded_defs: Dictionary = {}  # slot -> AvatarPartDef（当前已装）
var _pending_defs: Dictionary = {} # slot -> AvatarPartDef|null（到货待应用）
var _initial_loading := false

func _ready() -> void:
	if skeleton == null:
		skeleton = _find_skeleton(self)

func setup(p_loader: PartLoader) -> void:
	loader = p_loader
	loader.load_finished.connect(_on_load_finished)
	loader.load_failed.connect(_on_load_failed)

func apply_config(config: AvatarConfig) -> void:
	if _current.is_empty():
		_initial_loading = true
		visible = false
	for slot in slot_table.slot_names():
		_set_desired(slot, String(config.slots.get(slot, "")))
	_try_apply()

func equip(slot: StringName, part_id: String) -> void:
	_set_desired(slot, part_id)
	_try_apply()

func unequip(slot: StringName) -> void:
	var sdef := slot_table.slot(slot)
	if sdef and sdef.required:
		equip(slot, sdef.default_part)
	else:
		equip(slot, "")

func current_config() -> AvatarConfig:
	var cfg := AvatarConfig.new()
	for slot in slot_table.slot_names():
		cfg.slots[slot] = String(_current.get(slot, ""))
	return cfg

func _set_desired(slot: StringName, part_id: String) -> void:
	_desired[slot] = part_id
	if _slot_request.has(slot):
		var old_req: int = _slot_request[slot]
		loader.cancel(old_req)
		_req_slot.erase(old_req)
		_slot_request.erase(slot)
	if part_id == "":
		if _current.get(slot, "") != "" or _pending_defs.has(slot):
			_pending_defs[slot] = null
		return
	if String(_current.get(slot, "")) == part_id:
		_pending_defs.erase(slot)
		return
	var rid := loader.request_part(part_id)
	_slot_request[slot] = rid
	_req_slot[rid] = slot

func _on_load_finished(request_id: int, part_id: String, resource: Resource) -> void:
	var slot = _req_slot.get(request_id)
	if slot == null:
		return
	_req_slot.erase(request_id)
	_slot_request.erase(slot)
	var def := resource as AvatarPartDef
	if def == null:
		part_load_failed.emit(slot, part_id, ERR_INVALID_DATA)
		_try_apply()
		return
	_pending_defs[slot] = def
	_try_apply()

func _on_load_failed(request_id: int, part_id: String, err: int) -> void:
	var slot = _req_slot.get(request_id)
	if slot == null:
		return
	_req_slot.erase(request_id)
	_slot_request.erase(slot)
	part_load_failed.emit(slot, part_id, err)
	var sdef := slot_table.slot(slot)
	if sdef and sdef.required and part_id != sdef.default_part and sdef.default_part != "":
		var rid := loader.request_part(sdef.default_part)
		_desired[slot] = sdef.default_part
		_slot_request[slot] = rid
		_req_slot[rid] = slot
		return
	_desired[slot] = String(_current.get(slot, ""))
	_try_apply()

func _try_apply() -> void:
	if _initial_loading and not _slot_request.is_empty():
		return
	if not _pending_defs.is_empty():
		var applied_slots := _pending_defs.keys()
		for slot in _pending_defs:
			var def = _pending_defs[slot]
			if def == null:
				_loaded_defs.erase(slot)
				_current[slot] = ""
			else:
				_loaded_defs[slot] = def
				_current[slot] = def.id
		_pending_defs.clear()
		assembler.rebuild(self, _loaded_defs)
		for slot in applied_slots:
			slot_applied.emit(slot, String(_current.get(slot, "")))
	if _initial_loading and _slot_request.is_empty():
		_initial_loading = false
		visible = true
		config_applied.emit(current_config())

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null
```

- [ ] **Step 5: 运行测试确认通过**

Run: `tools/run_tests.sh res://tests/assembly`
Expected: 全 PASS。同时跑一遍全量 `tools/run_tests.sh` 确认无回归。

- [ ] **Step 6: Commit**

```bash
git add modules/avatar/assembly tests/assembly tests/fixtures
git commit -m "feat(avatar): AvatarRig 槽位状态机(原子显示/竞态取消/失败回落) + 直挂装配"
```

---

### Task 8: AssemblerMerged — 换装即合并

**Files:**
- Create: `modules/avatar/assembly/assembler_merged.gd`
- Modify: `modules/avatar/assembly/avatar_rig.gd`（默认 assembler 改为 Merged：`var assembler: AvatarAssembler = AvatarAssemblerMerged.new()`）
- Test: `tests/assembly/test_assembler_merged.gd`

**Interfaces:**
- Consumes: `AvatarAssembler._sync_sockets`、`AvatarPartDef`（mesh+skin）
- Produces: `AvatarAssemblerMerged.rebuild(rig, parts)`：所有 mesh 部件合并为 skeleton 下单个 `MeshInstance3D`（名 `merged_mesh`，`cast_shadow=OFF`）+ 统一 `Skin`；同材质且同顶点格式的 surface 拼接为一个 surface。测试还依赖内部方法 `_merge(defs: Array, skeleton: Skeleton3D) -> Dictionary`（返回 `{"mesh": ArrayMesh, "skin": Skin}`）。

- [ ] **Step 1: 写失败测试 `tests/assembly/test_assembler_merged.gd`**

```gdscript
extends GdUnitTestSuite

## 构造一个绑定到指定骨骼名的最小蒙皮三角面 mesh + skin
func _make_skinned_def(id: String, slot: StringName, bone_names: Array, mat: Material) -> AvatarPartDef:
	var st_arrays := []
	st_arrays.resize(Mesh.ARRAY_MAX)
	st_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	st_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for v in 3:
		bones.append_array(PackedInt32Array([v % bone_names.size(), 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	st_arrays[Mesh.ARRAY_BONES] = bones
	st_arrays[Mesh.ARRAY_WEIGHTS] = weights
	st_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st_arrays)
	mesh.surface_set_material(0, mat)
	var skin := Skin.new()
	for bn in bone_names:
		skin.add_named_bind(bn, Transform3D.IDENTITY)
	var def := AvatarPartDef.new()
	def.id = id
	def.slot = slot
	def.attach = "mesh"
	def.mesh = mesh
	def.skin = skin
	return def

func _skeleton() -> Skeleton3D:
	var s := Skeleton3D.new()
	s.add_bone("Root_M")
	s.add_bone("Head_M")
	return auto_free(s)

func test_same_material_surfaces_concat_to_one() -> void:
	var mat := StandardMaterial3D.new()
	var a := _make_skinned_def("a", &"cloth", ["Root_M"], mat)
	var b := _make_skinned_def("b", &"shoes", ["Root_M"], mat)
	var merged := AvatarAssemblerMerged.new()._merge([a, b], _skeleton())
	var mesh: ArrayMesh = merged.mesh
	assert_int(mesh.get_surface_count()).is_equal(1)
	var arrays := mesh.surface_get_arrays(0)
	assert_int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(6)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_int(idx.size()).is_equal(6)
	assert_int(idx[3]).is_equal(3)  # 第二段索引被偏移

func test_different_materials_stay_separate() -> void:
	var a := _make_skinned_def("a", &"cloth", ["Root_M"], StandardMaterial3D.new())
	var b := _make_skinned_def("b", &"shoes", ["Root_M"], StandardMaterial3D.new())
	var merged := AvatarAssemblerMerged.new()._merge([a, b], _skeleton())
	assert_int((merged.mesh as ArrayMesh).get_surface_count()).is_equal(2)

func test_bone_indices_remapped_by_name() -> void:
	var mat := StandardMaterial3D.new()
	# a 的 bind0=Root_M；b 的 bind 顺序相反：bind0=Head_M, bind1=Root_M
	var a := _make_skinned_def("a", &"cloth", ["Root_M", "Head_M"], mat)
	var b := _make_skinned_def("b", &"shoes", ["Head_M", "Root_M"], mat)
	var merged := AvatarAssemblerMerged.new()._merge([a, b], _skeleton())
	var skin: Skin = merged.skin
	assert_int(skin.get_bind_count()).is_equal(2)
	var canon := {}
	for i in skin.get_bind_count():
		canon[String(skin.get_bind_name(i))] = i
	var arrays := (merged.mesh as ArrayMesh).surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	# a: 顶点0→bind0(Root_M) 顶点1→bind1(Head_M)；b: 顶点0(全局3)→源bind0=Head_M
	assert_int(bones[0]).is_equal(canon["Root_M"])
	assert_int(bones[4]).is_equal(canon["Head_M"])
	assert_int(bones[3 * 4]).is_equal(canon["Head_M"])

func test_rebuild_creates_single_mesh_instance() -> void:
	var rig := AvatarRig.new()
	var t := AvatarSlotTable.new()
	for n in [&"cloth", &"shoes"]:
		var sd := AvatarSlotDef.new()
		sd.slot_name = n
		sd.attach_bone = "Root_M"
		t.slots.append(sd)
	rig.slot_table = t
	var skel := _skeleton()
	skel.name = "Skeleton3D"
	rig.add_child(skel)
	add_child(auto_free(rig))
	rig.skeleton = skel
	var mat := StandardMaterial3D.new()
	var parts := {
		&"cloth": _make_skinned_def("a", &"cloth", ["Root_M"], mat),
		&"shoes": _make_skinned_def("b", &"shoes", ["Root_M"], mat),
	}
	var asm := AvatarAssemblerMerged.new()
	asm.rebuild(rig, parts)
	var mi: MeshInstance3D = skel.get_node("merged_mesh")
	assert_object(mi).is_not_null()
	assert_int((mi.mesh as ArrayMesh).get_surface_count()).is_equal(1)
	assert_object(mi.skin).is_not_null()
	asm.rebuild(rig, {&"cloth": parts[&"cloth"]})
	assert_int(((skel.get_node("merged_mesh") as MeshInstance3D).mesh as ArrayMesh).get_surface_count()).is_equal(1)

func test_default_assembler_is_merged() -> void:
	assert_bool(AvatarRig.new().assembler is AvatarAssemblerMerged).is_true()
```

- [ ] **Step 2: 运行确认失败**

Run: `tools/run_tests.sh res://tests/assembly`
Expected: 新用例 FAIL。

- [ ] **Step 3: 实现 `modules/avatar/assembly/assembler_merged.gd` 并改 rig 默认值**

```gdscript
class_name AvatarAssemblerMerged
extends AvatarAssembler

func rebuild(rig: AvatarRig, parts: Dictionary) -> void:
	_sync_sockets(rig, parts)
	var skeleton := rig.skeleton
	var mi := skeleton.get_node_or_null("merged_mesh") as MeshInstance3D
	var mesh_defs: Array = []
	for slot in parts:
		var def: AvatarPartDef = parts[slot]
		if def != null and def.attach == "mesh" and def.mesh != null:
			mesh_defs.append(def)
	if mesh_defs.is_empty():
		if mi:
			skeleton.remove_child(mi)
			mi.queue_free()
		return
	var result := _merge(mesh_defs, skeleton)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "merged_mesh"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		skeleton.add_child(mi)
	mi.mesh = result.mesh
	mi.skin = result.skin

## 返回 {"mesh": ArrayMesh, "skin": Skin}
func _merge(defs: Array, skeleton: Skeleton3D) -> Dictionary:
	var canonical := Skin.new()
	var bind_by_bone := {}
	var buckets := {}  # key -> {material: Material, list: Array[surface arrays]}
	var bucket_order: Array = []
	for def in defs:
		var remap := _remap_for(def, canonical, bind_by_bone, skeleton)
		var mesh: Mesh = def.mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			if remap.size() > 0 and arrays[Mesh.ARRAY_BONES] != null:
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				for j in bones.size():
					bones[j] = remap[bones[j]]
				arrays[Mesh.ARRAY_BONES] = bones
			var mat := mesh.surface_get_material(s)
			var key := _bucket_key(mat, arrays)
			if not buckets.has(key):
				buckets[key] = {"material": mat, "list": []}
				bucket_order.append(key)
			buckets[key].list.append(arrays)
	var merged := ArrayMesh.new()
	for key in bucket_order:
		var b = buckets[key]
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _concat_arrays(b.list))
		merged.surface_set_material(merged.get_surface_count() - 1, b.material)
	return {"mesh": merged, "skin": canonical}

func _remap_for(def: AvatarPartDef, canonical: Skin, bind_by_bone: Dictionary, skeleton: Skeleton3D) -> PackedInt32Array:
	var remap := PackedInt32Array()
	if def.skin == null:
		return remap
	remap.resize(def.skin.get_bind_count())
	for i in def.skin.get_bind_count():
		var bone_name := String(def.skin.get_bind_name(i))
		if bone_name.is_empty():
			var bone_idx := def.skin.get_bind_bone(i)
			bone_name = skeleton.get_bone_name(bone_idx) if bone_idx >= 0 and bone_idx < skeleton.get_bone_count() else "bind_%d" % i
		if not bind_by_bone.has(bone_name):
			bind_by_bone[bone_name] = canonical.get_bind_count()
			canonical.add_named_bind(bone_name, def.skin.get_bind_pose(i))
		remap[i] = bind_by_bone[bone_name]
	return remap

func _bucket_key(mat: Material, arrays: Array) -> String:
	var fmt := ""
	for i in arrays.size():
		fmt += "1" if arrays[i] != null else "0"
	var mat_key := "null"
	if mat != null:
		mat_key = mat.resource_path if not mat.resource_path.is_empty() else str(mat.get_instance_id())
	return mat_key + "|" + fmt

func _concat_arrays(list: Array) -> Array:
	if list.size() == 1:
		return list[0]
	var out: Array = list[0].duplicate()
	for i in range(1, list.size()):
		var arrays: Array = list[i]
		var vertex_offset := (out[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for ch in Mesh.ARRAY_MAX:
			if ch == Mesh.ARRAY_INDEX or arrays[ch] == null:
				continue
			var combined = out[ch]
			combined += arrays[ch]
			out[ch] = combined
		if arrays[Mesh.ARRAY_INDEX] != null and out[Mesh.ARRAY_INDEX] != null:
			var out_idx: PackedInt32Array = out[Mesh.ARRAY_INDEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for j in idx.size():
				out_idx.append(idx[j] + vertex_offset)
			out[Mesh.ARRAY_INDEX] = out_idx
	return out
```

`avatar_rig.gd` 修改一行：
```gdscript
var assembler: AvatarAssembler = AvatarAssemblerMerged.new()
```

- [ ] **Step 4: 运行测试确认通过**

Run: `tools/run_tests.sh res://tests/assembly` 然后全量 `tools/run_tests.sh`
Expected: 全 PASS（Task 7 的用例已在 before_test 显式指定 Direct 策略，不受默认策略切换影响）。

- [ ] **Step 5: Commit**

```bash
git add modules/avatar/assembly tests/assembly
git commit -m "feat(avatar): 合并装配策略(骨骼名重映射+同材质拼接)并设为默认"
```

---

### Task 9: Toon Shader + 材质工厂

**Files:**
- Create: `modules/avatar/shaders/avatar_toon.gdshader`, `modules/avatar/shaders/material_factory.gd`
- Test: `tests/shaders/test_material_factory.gd`

**Interfaces:**
- Consumes: 无
- Produces:
  - `res://modules/avatar/shaders/avatar_toon.gdshader`：统一 toon shader，uniform：`albedo_tex`(sampler2D)、`ao_tex`(sampler2D, 默认白)、`ao_strength`(float, 默认0.3)、`shadow_value`(float, 默认0.85)、`shadow_softness`(float, 默认0.1)、`emission_strength`(float, 默认0.0)、`rim_strength`(float, 默认0.0)
  - `AvatarMaterialFactory.create(params: Dictionary) -> ShaderMaterial`：params 键 = `albedo_tex`/`ao_tex`（Texture2D 或 res 路径 String）+ 上述 float 键。这是转换工具（Task 11）生成材质的唯一入口，参数名与 Unity 侧映射：`_Kao→ao_strength`、`_Kshadow→shadow_value`、`_Ke→emission_strength`、`_FresnelHighLight→rim_strength`

- [ ] **Step 1: 写失败测试 `tests/shaders/test_material_factory.gd`**

```gdscript
extends GdUnitTestSuite

func test_shader_loads_and_compiles() -> void:
	var shader: Shader = load("res://modules/avatar/shaders/avatar_toon.gdshader")
	assert_object(shader).is_not_null()
	assert_str(RenderingServer.shader_get_code(shader.get_rid())).is_not_empty()

func test_factory_sets_params() -> void:
	var tex := PlaceholderTexture2D.new()
	var m := AvatarMaterialFactory.create({
		"albedo_tex": tex,
		"ao_strength": 0.5,
		"shadow_value": 0.7,
	})
	assert_object(m).is_not_null()
	assert_object(m.shader).is_not_null()
	assert_object(m.get_shader_parameter("albedo_tex")).is_same(tex)
	assert_float(m.get_shader_parameter("ao_strength")).is_equal_approx(0.5, 0.001)
	assert_float(m.get_shader_parameter("shadow_value")).is_equal_approx(0.7, 0.001)

func test_factory_ignores_unknown_keys() -> void:
	var m := AvatarMaterialFactory.create({"albedo_tex": PlaceholderTexture2D.new(), "bogus_key": 1.0})
	assert_object(m).is_not_null()
```

- [ ] **Step 2: 运行确认失败**

Run: `tools/run_tests.sh res://tests/shaders`
Expected: FAIL。

- [ ] **Step 3: 实现**

`modules/avatar/shaders/avatar_toon.gdshader`:
```glsl
// 统一 avatar toon shader：近似 Unity DonutAvatar（BaseColor × AO × 双段光照 ramp）
// 一期把 56 种 Unity shader 收敛到这一个；特殊效果二期按需扩展。
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.3;
uniform float shadow_value : hint_range(0.0, 1.0) = 0.85; // 暗部亮度（对应 _Kshadow）
uniform float shadow_softness : hint_range(0.001, 1.0) = 0.1;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 alb = texture(albedo_tex, UV);
	float ao = mix(1.0, texture(ao_tex, UV).r, ao_strength);
	ALBEDO = alb.rgb * ao;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = alb.rgb * (emission_strength + rim * rim_strength);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, shadow_softness, ndl);
	float shade = mix(shadow_value, 1.0, lit);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * ATTENUATION * shade;
}
```

`modules/avatar/shaders/material_factory.gd`:
```gdscript
class_name AvatarMaterialFactory
extends RefCounted

const SHADER := preload("res://modules/avatar/shaders/avatar_toon.gdshader")
const TEXTURE_KEYS := ["albedo_tex", "ao_tex"]
const FLOAT_KEYS := ["ao_strength", "shadow_value", "shadow_softness", "emission_strength", "rim_strength"]

static func create(params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	for key in TEXTURE_KEYS:
		if not params.has(key):
			continue
		var v = params[key]
		if v is String:
			v = load(v)
		if v is Texture2D:
			m.set_shader_parameter(key, v)
	for key in FLOAT_KEYS:
		if params.has(key):
			m.set_shader_parameter(key, float(params[key]))
	return m
```

- [ ] **Step 4: 运行测试确认通过**

Run: `tools/run_tests.sh res://tests/shaders`
Expected: 全 PASS。

- [ ] **Step 5: Commit**

```bash
git add modules/avatar/shaders tests/shaders
git commit -m "feat(avatar): 统一 toon shader + 材质工厂(Unity 参数映射)"
```

---

### Task 10: 转换工具 Python 阶段

**Files:**
- Create（均在 `tools/unity_export/`）: `requirements.txt`, `unity_yaml.py`, `addressables.py`, `resolve.py`, `parts.py`, `materials.py`, `naming.py`, `convention.py`, `convert.py`, `samples.json`, `overrides.json`, `tests/test_unity_yaml.py`, `tests/test_naming.py`, `tests/test_convention.py`, `tests/fixtures/`（合成的 Unity YAML 小样本）

**Interfaces:**
- Consumes: 只读 Unity 工程 `../sensen-unity`
- Produces（运行 `convert.py` 后）:
  - `assets/avatar/source/<part_id>/` 与 `assets/avatar/source/base/`：拷贝的 FBX/贴图（写进本 Godot 仓库，供 Godot 导入）
  - `tools/unity_export/out/recipes.json`：Task 11 的输入。schema：
    ```json
    { "version": 1,
      "base": { "fbx": "res://assets/avatar/source/base/SK_DtBase.fbx",
                 "anim_fbx": { "idle": "res://assets/avatar/source/base/dt@idle02.fbx",
                               "walk": "res://assets/avatar/source/base/dt@walk01.fbx",
                               "run":  "res://assets/avatar/source/base/dt@run01.fbx" } },
      "parts": [
        { "id": "cloth1", "slot": "cloth", "attach": "mesh", "tier": 0, "unity_guid": "604181a9...",
          "fbx": "res://assets/avatar/source/cloth1/SK_dt_skin01.fbx", "mesh_name": "cloth",
          "materials": [ { "albedo": "res://assets/avatar/source/cloth1/T_skin01_cloth_D.png",
                            "ao": "res://assets/avatar/source/cloth1/T_skin01_cloth_AO.png",
                            "floats": { "ao_strength": 0.3, "shadow_value": 0.85 } } ],
          "offset": null, "thumb_src": "res://assets/avatar/source/cloth1/thumb.png" },
        { "id": "hairhat20", "slot": "hairHat", "attach": "socket", "tier": 0, "unity_guid": "...",
          "fbx": "res://assets/avatar/source/hairhat20/SM_hairHat20.fbx", "mesh_name": null,
          "materials": [ ... ],
          "offset": { "pos": [0,0,0], "rot": [0,0,0], "scale": [1,1,1] }, "thumb_src": null }
      ] }
    ```
  - `tools/unity_export/out/guid_map.csv`（unity_guid,part_id）与 `out/report.txt`（校验报告；有 ERROR 时退出码非 0）
- 运行方式：
  ```bash
  cd tools/unity_export
  python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
  .venv/bin/python convert.py --unity-root ../../../sensen-unity --godot-root ../.. \
      --samples samples.json --overrides overrides.json --out out
  .venv/bin/python -m pytest tests -q
  ```

**核心设计（源自调研结论，实现时不可偏离）：**
1. Unity .meta 的 GUID 被 Tuanjie 混淆 → hex GUID→路径三级解析：
   a. Addressables 表 `Assets/AddressableAssetsData/AssetGroups/Avatar.asset` 中 `m_GUID`/`m_Address` 对（覆盖全部部件 SO）；
   b. 目录/命名约定（FBX/材质/贴图/缩略图，见 convention.py 规则）；
   c. `overrides.json` 人工兜底：`{ "<part_id 或 hex guid>": { "fbx": "...", "albedo": "...", ... } }`。
   任何字段解析失败 → report 记 ERROR（部件被剔除），绝不猜测性通过。
2. 换 mesh 部件的子网格定位：Unity 约定"套装 FBX 子网格名 = 槽位名"（如 `SK_dt_skin01.fbx` 内 `cloth`）→ recipes 的 `mesh_name` 直接写槽位名；Task 11 在 Godot 内找不到该名节点时报 ERROR。
3. tier 判定：一期由 `samples.json` 显式声明（`"tier": 0|1|2`）；未声明默认 0 并在 report 记 WARN（全量迁移时再做 FBX 动画曲线自动检测）。
4. Unity YAML 解析：删除 `%` 指令行、把 `--- !u!<id> &<fileID>` 规约为 `---` 后 `yaml.safe_load_all`（Tuanjie 自定义 TAG `tag:yousandi.cn,2023:` 因此被绕过）。

`samples.json`（一期样例集；执行时若某项在 Unity 工程中缺失/解析失败，允许换同类型相邻部件并在提交信息注明）:
```json
{
  "base_parts": ["ap_body00", "ap_eyes00", "ap_hairHat00", "ap_cloth00", "ap_shoes00", "ap_glass00"],
  "parts": [
    { "asset": "ap_cloth1",        "tier": 0 },
    { "asset": "ap_cloth1_1",      "tier": 0 },
    { "asset": "ap_shoes1",        "tier": 0 },
    { "asset": "ap_glass1",        "tier": 0 },
    { "asset": "ap_messengerBag1", "tier": 0 },
    { "asset": "ap_cloth87",       "tier": 0 },
    { "asset": "ap_hairHat20",     "tier": 0 },
    { "asset": "ap_hairHat37",     "tier": 1 },
    { "asset": "ap_hairHat101",    "tier": 2 }
  ]
}
```

- [ ] **Step 1: 建 venv 并写 `requirements.txt`**

```
pyyaml>=6.0
pytest>=8.0
```

```bash
cd tools/unity_export && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

- [ ] **Step 2: 写失败测试（pytest，合成 fixtures）**

`tests/fixtures/ap_test.asset`（截取真实结构的合成样本）:
```yaml
%YAML 1.1
%TAG !u! tag:yousandi.cn,2023:
--- !u!114 &11400000
MonoBehaviour:
  m_Name: ap_test
  guid: aabbccdd00112233445566778899aabb
  attachType: 0
  partName: cloth1
  partType: 3
  mesh: {fileID: -555, guid: ffeeddcc00112233445566778899aabb, type: 3}
  materials:
  - {fileID: 2100000, guid: 12345678001122334455667788990011, type: 2}
  socketPrefab: {fileID: 0}
  postion: {x: 0, y: 0, z: 0}
  scale: {x: 1, y: 1, z: 1}
  rotation: {x: 0, y: 0, z: 0}
  thumbnail: {fileID: 0}
```

`tests/test_unity_yaml.py`:
```python
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
```

`tests/test_naming.py`:
```python
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
```

`tests/test_convention.py`:
```python
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
```

Run: `.venv/bin/python -m pytest tests -q` → Expected: FAIL（模块不存在）。

- [ ] **Step 3: 实现各模块**

`unity_yaml.py`:
```python
"""Tuanjie/Unity YAML 宽松解析：去 %TAG 指令、规约文档分隔符后 safe_load_all。"""
import re
from pathlib import Path
import yaml

_DOC_RE = re.compile(r"^--- !u!\d+ &\d+.*$", re.M)

def load_documents(path):
    p = Path(path)
    if not p.is_file():
        return []
    text = p.read_text(encoding="utf-8", errors="replace")
    text = "\n".join(l for l in text.splitlines() if not l.startswith("%"))
    text = _DOC_RE.sub("---", text)
    try:
        return [d for d in yaml.safe_load_all(text) if isinstance(d, dict)]
    except yaml.YAMLError:
        return []

def load_monobehaviour(path):
    for doc in load_documents(path):
        if "MonoBehaviour" in doc:
            return doc["MonoBehaviour"]
    return None
```

`naming.py`:
```python
"""部件 ID(slug) 与槽位映射。槽位顺序 = Unity PartType 枚举顺序，不可改。"""
import re

SLOTS = ["body", "eyes", "hairHat", "cloth", "shoes", "shoulderBag", "messengerBag",
         "pocketBag", "backpack", "headset", "handleft", "handright", "mask", "glass"]

def slot_name(part_type: int) -> str:
    if 0 <= part_type < len(SLOTS):
        return SLOTS[part_type]
    raise ValueError(f"未知 partType: {part_type}")

def slug(part_name: str) -> str:
    s = part_name.strip().lower()
    s = re.sub(r"[\s\-]+", "", s)
    s = re.sub(r"[^a-z0-9_]", "", s)
    if not s:
        raise ValueError(f"无法从 {part_name!r} 生成 slug")
    return s

class SlugRegistry:
    def __init__(self):
        self._seen = set()
    def claim(self, s: str) -> str:
        if s in self._seen:
            raise ValueError(f"部件 ID 冲突: {s}")
        self._seen.add(s)
        return s
```

`addressables.py`:
```python
"""解析 Addressables 组资产中的 m_GUID/m_Address 对（hex GUID → Unity 工程内路径）。"""
import re
from pathlib import Path

_ENTRY_RE = re.compile(r"m_GUID:\s*([0-9a-f]{32})\s*\n\s*m_Address:\s*(.+)")

def load_guid_table(unity_root) -> dict:
    table = {}
    groups_dir = Path(unity_root) / "Assets/AddressableAssetsData/AssetGroups"
    for asset in sorted(groups_dir.glob("*.asset")):
        text = asset.read_text(encoding="utf-8", errors="replace")
        for m in _ENTRY_RE.finditer(text):
            table[m.group(1)] = m.group(2).strip()
    return table
```

`convention.py`:
```python
"""目录/命名约定解析：变体目录、贴图、FBX、缩略图。找不到一律返回 None，让上层记 ERROR。"""
from pathlib import Path
import re

def variant_suffix(part_name: str) -> str:
    m = re.search(r"_(\d+)$", part_name)
    return m.group(1) if m else ""

def variant_dir(pak_dir: Path, part_name: str):
    """skin01/ap_cloth1 → skin01/skin01；ap_cloth1_2 → skin01/skin01_2。
    配件类 pak(glass 等) 无内层目录时返回 pak_dir 本身。"""
    suffix = variant_suffix(part_name)
    inner = pak_dir / (pak_dir.name + (f"_{suffix}" if suffix else ""))
    if inner.is_dir():
        return inner
    return pak_dir if not suffix else None

def find_texture(folder: Path, slot_word: str, kind: str):
    """kind: D | AO | ORM。匹配 T_*_<slot_word>*_<kind>.png（大小写不敏感）。"""
    if folder is None or not folder.is_dir():
        return None
    pat = re.compile(rf"^T_.*{re.escape(slot_word)}.*_{kind}\.png$", re.I)
    hits = sorted(p for p in folder.iterdir() if pat.match(p.name))
    return hits[0] if hits else None

def find_fbx(folder: Path, prefer_prefix: str = "SK_"):
    if folder is None or not folder.is_dir():
        return None
    hits = sorted(folder.glob(f"{prefer_prefix}*.fbx")) or sorted(folder.glob("*.fbx"))
    return hits[0] if hits else None

def find_named_fbx(folder: Path, part_name: str):
    """socket 部件：SM_<partName>.fbx / SK_<partName>.fbx / <partName>*.fbx"""
    if folder is None or not folder.is_dir():
        return None
    for pat in (f"SM_{part_name}.fbx", f"SK_{part_name}.fbx", f"{part_name}*.fbx",
                f"SM_{part_name}*.fbx", f"SK_{part_name}*.fbx"):
        hits = sorted(folder.glob(pat))
        if hits:
            return hits[0]
    return None
```

`materials.py`:
```python
"""从 Unity .mat 提取 float 参数并映射到 toon shader 参数名。贴图靠 convention 定位，不走 .mat 引用。"""
import unity_yaml

FLOAT_MAP = {"_Kao": "ao_strength", "_Kshadow": "shadow_value",
             "_Ke": "emission_strength", "_FresnelHighLight": "rim_strength"}

def extract_floats(mat_path) -> dict:
    docs = unity_yaml.load_documents(mat_path)
    for doc in docs:
        mat = doc.get("Material")
        if not mat:
            continue
        floats = {}
        saved = mat.get("m_SavedProperties", {}) or {}
        for item in saved.get("m_Floats", []) or []:
            if isinstance(item, dict):
                for k, v in item.items():
                    if k in FLOAT_MAP and v is not None:
                        floats[FLOAT_MAP[k]] = float(v)
        return floats
    return {}

def find_material_file(folder, slot_word):
    """M_*<slot_word>*.mat（大小写不敏感），无则 None。"""
    import re
    if folder is None or not folder.is_dir():
        return None
    pat = re.compile(rf"^M_.*{re.escape(slot_word)}.*\.mat$", re.I)
    hits = sorted(p for p in folder.iterdir() if pat.match(p.name))
    return hits[0] if hits else None
```

`resolve.py`:
```python
"""hex GUID → Unity 路径：Addressables 表 → overrides。"""
class GuidResolver:
    def __init__(self, addr_table: dict, overrides: dict):
        self.addr = addr_table
        self.overrides = overrides or {}
    def path_for_guid(self, guid: str):
        ov = self.overrides.get(guid)
        if isinstance(ov, str):
            return ov
        return self.addr.get(guid)
```

`parts.py`（部件记录构建，核心流程）:
```python
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
```

`convert.py`（CLI：组装以上模块；拷贝文件进 `assets/avatar/source/<id>/`，路径改写为 `res://`；写 recipes.json/guid_map.csv/report.txt；基础角色 base_parts 同流程但 `fbx` 固定为 `BaseCharacter/Models/SK_DtBase.fbx`、动画 FBX 固定为 `BaseCharacter/Animations/dt@idle02.fbx`/`dt@walk01.fbx`/`dt@run01.fbx`；report 有 ERROR 时 `sys.exit(1)`）:
```python
import argparse, csv, json, shutil, sys
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

    # 基础部件的 FBX/贴图不在部件目录约定内（Models/ 与 Texture/），进 build_recipe 前注入 override
    for name in samples.get("base_parts", []):
        pid = naming.slug(name.replace("ap_", ""))
        overrides.setdefault(pid, {})
        overrides[pid].setdefault("fbx", str(base_fbx))
        overrides[pid].setdefault("folder", str(base_dir / "Texture"))
        r = parts_mod.build_recipe(unity_root, name, 0, overrides, registry, report)
        if r:
            recipes.append(r)
    for item in samples.get("parts", []):
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
    """拷贝到 assets/avatar/source/<part_id>/，返回 res:// 路径。同名文件幂等覆盖。"""
    src = Path(src)
    if not src.is_file():
        report.error(f"{part_id}: 源文件缺失 {src}")
        return ""
    dst_dir = godot_root / "assets/avatar/source" / part_id
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / src.name
    shutil.copy2(src, dst)
    return "res://" + dst.relative_to(godot_root).as_posix()

if __name__ == "__main__":
    main()
```

`overrides.json` 初始为 `{}`。

- [ ] **Step 4: pytest 通过**

Run: `cd tools/unity_export && .venv/bin/python -m pytest tests -q`
Expected: 全 PASS。

- [ ] **Step 5: 对真实 Unity 工程试跑**

```bash
cd tools/unity_export
.venv/bin/python convert.py --unity-root ../../../sensen-unity --godot-root ../.. --out out
cat out/report.txt
```
Expected: 退出码 0（或按 report 修 `samples.json`/`overrides.json` 直至 0）。`assets/avatar/source/` 出现各部件目录（FBX+PNG），`out/recipes.json` 完整。若某样例部件在工程中不存在，替换为同类型相邻编号部件并在提交信息注明。

- [ ] **Step 6: Commit**

```bash
git add tools/unity_export assets/avatar/source
git commit -m "feat(pipeline): Unity→Godot 转换工具 Python 阶段(三级GUID解析/样例集落地)"
```

---

### Task 11: 转换工具 Godot 阶段 — 部件提取与 manifest 落地

**Files:**
- Create: `tools/pipeline/extract_parts.gd`（`extends SceneTree` 的 headless 脚本）
- Create（运行产出）: `assets/avatar/parts/*.res`（AvatarPartDef，内嵌网格/材质）、`assets/avatar/parts/*_scene.tscn`（socket 场景）、`assets/avatar/thumbs/*.png`、`assets/avatar/parts_manifest.json`
- Test: `tests/pipeline/test_converted_assets.gd`（对产出做加载校验；产出缺失时跳过并警告）

**Interfaces:**
- Consumes: `tools/unity_export/out/recipes.json`（Task 10 schema）、`AvatarPartDef`、`AvatarMaterialFactory`、`PartCatalog`
- Produces: 正式资产库 `assets/avatar/`；`parts_manifest.json`（spec §4.3 schema，`pack` 一律 `"builtin"`）
- 运行方式：
  ```bash
  godot --headless --path . --import
  godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- tools/unity_export/out/recipes.json
  godot --headless --path . --import   # 让新生成的 .res/.png 完成导入
  ```

- [ ] **Step 1: 写 `tools/pipeline/extract_parts.gd`**

```gdscript
## Headless 提取器：recipes.json → AvatarPartDef .res / socket .tscn / thumbs / parts_manifest.json
## 用法: godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- <recipes.json路径>
extends SceneTree

const PARTS_DIR := "res://assets/avatar/parts"
const THUMBS_DIR := "res://assets/avatar/thumbs"
const MANIFEST_PATH := "res://assets/avatar/parts_manifest.json"

var _errors: PackedStringArray = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("缺少参数: recipes.json 路径")
		quit(2)
		return
	var recipes_text := FileAccess.get_file_as_string(args[0])
	var recipes = JSON.parse_string(recipes_text)
	if typeof(recipes) != TYPE_DICTIONARY:
		push_error("recipes.json 解析失败: %s" % args[0])
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PARTS_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(THUMBS_DIR))
	var manifest_parts: Array = []
	for recipe in recipes.parts:
		var entry = _process_part(recipe)
		if entry != null:
			manifest_parts.append(entry)
	var manifest := {"version": 1, "parts": manifest_parts}
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	for e in _errors:
		printerr("ERROR: " + e)
	print("提取完成: %d 部件, %d 错误" % [manifest_parts.size(), _errors.size()])
	quit(1 if _errors.size() > 0 else 0)

func _process_part(recipe: Dictionary):
	var id: String = recipe.id
	var scene_res = load(String(recipe.fbx))
	if scene_res == null or not (scene_res is PackedScene):
		_errors.append("%s: FBX 未导入或加载失败 %s" % [id, recipe.fbx])
		return null
	var inst: Node = (scene_res as PackedScene).instantiate()
	var def := AvatarPartDef.new()
	def.id = id
	def.slot = StringName(String(recipe.slot))
	def.attach = String(recipe.attach)
	def.tier = int(recipe.get("tier", 0))
	var material := _build_material(recipe)
	var res_path := ""
	if def.attach == "mesh":
		var mi := _find_mesh_instance(inst, String(recipe.get("mesh_name", "")))
		if mi == null:
			_errors.append("%s: FBX 内找不到子网格 '%s'" % [id, recipe.get("mesh_name", "")])
			inst.free()
			return null
		var mesh := (mi.mesh as ArrayMesh).duplicate(true) as ArrayMesh
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, material)
		def.mesh = mesh
		def.skin = mi.skin.duplicate(true) if mi.skin else null
		res_path = "%s/%s.res" % [PARTS_DIR, id]
	else:
		var scene_path := "%s/%s_scene.tscn" % [PARTS_DIR, id]
		var root := _build_socket_scene(inst, material, int(recipe.get("tier", 0)))
		if root == null:
			_errors.append("%s: socket FBX 内没有网格" % id)
			inst.free()
			return null
		var packed := PackedScene.new()
		packed.pack(root)
		ResourceSaver.save(packed, scene_path)
		root.free()
		def.scene = load(scene_path)
		var off = recipe.get("offset")
		if typeof(off) == TYPE_DICTIONARY:
			def.offset_pos = _v3(off.pos)
			def.offset_rot_deg = _v3(off.rot)
			def.offset_scale = _v3(off.scale)
		res_path = "%s/%s.res" % [PARTS_DIR, id]
	inst.free()
	var err := ResourceSaver.save(def, res_path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		_errors.append("%s: 保存失败 err=%d" % [id, err])
		return null
	var thumb_path := _write_thumb(id, recipe.get("thumb_src"))
	var entry := {"id": id, "slot": String(recipe.slot), "attach": def.attach, "tier": def.tier,
		"pack": "builtin", "res": res_path, "thumb": thumb_path,
		"unity_guid": String(recipe.get("unity_guid", ""))}
	if typeof(recipe.get("offset")) == TYPE_DICTIONARY:
		entry["offset"] = recipe.offset
	return entry

func _build_material(recipe: Dictionary) -> ShaderMaterial:
	var mats: Array = recipe.get("materials", [])
	var params := {}
	if mats.size() > 0 and typeof(mats[0]) == TYPE_DICTIONARY:
		var m: Dictionary = mats[0]
		if m.get("albedo"):
			params["albedo_tex"] = String(m.albedo)
		if m.get("ao"):
			params["ao_tex"] = String(m.ao)
		var floats = m.get("floats", {})
		if typeof(floats) == TYPE_DICTIONARY:
			for k in floats:
				params[k] = floats[k]
	return AvatarMaterialFactory.create(params)

func _find_mesh_instance(root: Node, mesh_name: String) -> MeshInstance3D:
	var stack: Array = [root]
	var first: MeshInstance3D = null
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			if first == null:
				first = n
			if String(n.name).to_lower() == mesh_name.to_lower():
				return n
		for c in n.get_children():
			stack.append(c)
	return first if mesh_name.is_empty() else null

func _build_socket_scene(fbx_root: Node, material: Material, tier: int) -> Node3D:
	## 收集 FBX 中全部网格烘成静态 MeshInstance3D；tier==1 时保留 AnimationPlayer。
	var root := Node3D.new()
	root.name = "SocketPart"
	var found := false
	var stack: Array = [fbx_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			found = true
			var mi := MeshInstance3D.new()
			mi.name = n.name
			var mesh := (n.mesh as ArrayMesh).duplicate(true) as ArrayMesh
			for s in mesh.get_surface_count():
				mesh.surface_set_material(s, material)
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transform = (n as Node3D).transform
			root.add_child(mi)
			mi.owner = root
		for c in n.get_children():
			stack.append(c)
	if tier == 1:
		var src_player := _find_anim_player(fbx_root)
		if src_player:
			var player := AnimationPlayer.new()
			player.name = "AnimationPlayer"
			var lib := AnimationLibrary.new()
			for anim_name in src_player.get_animation_list():
				lib.add_animation(anim_name, src_player.get_animation(anim_name).duplicate(true))
			player.add_animation_library("", lib)
			root.add_child(player)
			player.owner = root
	return root if found else null

func _find_anim_player(root: Node) -> AnimationPlayer:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _write_thumb(id: String, thumb_src) -> String:
	var dst := "%s/%s.png" % [THUMBS_DIR, id]
	if thumb_src != null and String(thumb_src) != "" and FileAccess.file_exists(String(thumb_src)):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(String(thumb_src)), ProjectSettings.globalize_path(dst))
		return dst
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.6, 0.6, 0.65))
	img.save_png(ProjectSettings.globalize_path(dst))
	return dst

func _v3(a) -> Vector3:
	if typeof(a) == TYPE_ARRAY and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
```

**T2 特效说明**：Unity 粒子系统不做自动迁移（不可转换）。tier=2 的样例部件（如 hairhat101）一期只提取网格，tier 字段照常写入 manifest，供活动度控制与预算统计用；特效二期在 Godot 内重做。

- [ ] **Step 2: 跑管线**

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- tools/unity_export/out/recipes.json
godot --headless --path . --import
```
Expected: `提取完成: N 部件, 0 错误`；`assets/avatar/parts_manifest.json` 存在。若 mesh_name 找不到（Unity 子网格命名不符约定），把实际名字写入 `overrides.json` 的该部件 `mesh_name` 字段，重跑 Task 10 Step 5 + 本步骤。

- [ ] **Step 3: 写校验测试 `tests/pipeline/test_converted_assets.gd`**

```gdscript
extends GdUnitTestSuite

const MANIFEST := "res://assets/avatar/parts_manifest.json"

func test_manifest_loads_and_parts_valid() -> void:
	if not FileAccess.file_exists(MANIFEST):
		push_warning("转换产物缺失，跳过（先跑 Task 10/11 管线）")
		return
	var cat := PartCatalog.load_from_file(MANIFEST)
	assert_object(cat).is_not_null()
	assert_int(cat.size()).is_greater(5)
	for id in cat.all_ids():
		var meta := cat.part(id)
		var res := load(meta.res_path)
		assert_object(res).is_not_null()
		var def := res as AvatarPartDef
		assert_object(def).is_not_null()
		assert_str(def.id).is_equal(id)
		if def.attach == "mesh":
			assert_object(def.mesh).is_not_null()
		else:
			assert_object(def.scene).is_not_null()

func test_mesh_parts_have_toon_material() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var cat := PartCatalog.load_from_file(MANIFEST)
	for id in cat.all_ids():
		var def := load(cat.part(id).res_path) as AvatarPartDef
		if def and def.attach == "mesh" and def.mesh:
			var mat := def.mesh.surface_get_material(0)
			assert_object(mat).is_not_null()
			assert_bool(mat is ShaderMaterial).is_true()
```

- [ ] **Step 4: 运行测试确认通过**

Run: `tools/run_tests.sh res://tests/pipeline`
Expected: 全 PASS。

- [ ] **Step 5: Commit**

```bash
git add tools/pipeline assets/avatar tests/pipeline
git commit -m "feat(pipeline): Godot 提取阶段(部件 .res/socket 场景/缩略图/manifest)"
```

---

### Task 12: 基础骨架场景 + 动画库

**Files:**
- Create: `tools/pipeline/gen_base_rig.gd`
- Create（运行产出）: `assets/avatar/base/base_rig.tscn`, `assets/avatar/base/animations.res`
- Test: `tests/pipeline/test_base_rig.gd`

**Interfaces:**
- Consumes: `assets/avatar/source/base/SK_DtBase.fbx` 与三个动画 FBX（Task 10 staged）、`AvatarRig`
- Produces: `res://assets/avatar/base/base_rig.tscn` —— 根节点 `AvatarRig`（挂 avatar_rig.gd，slot_table 指向 `slot_table.tres`）+ `Skeleton3D`（62 骨，无网格子节点）+ `AnimationPlayer`（库含 `idle`/`walk`/`run`）。这是所有场景实例化角色的唯一入口场景。

- [ ] **Step 1: 写 `tools/pipeline/gen_base_rig.gd`**

```gdscript
## 用法: godot --headless --path . --script res://tools/pipeline/gen_base_rig.gd
extends SceneTree

const BASE_FBX := "res://assets/avatar/source/base/SK_DtBase.fbx"
const ANIM_FBX := {"idle": "res://assets/avatar/source/base/dt@idle02.fbx",
	"walk": "res://assets/avatar/source/base/dt@walk01.fbx",
	"run": "res://assets/avatar/source/base/dt@run01.fbx"}
const OUT_SCENE := "res://assets/avatar/base/base_rig.tscn"
const OUT_LIB := "res://assets/avatar/base/animations.res"

func _initialize() -> void:
	var base_scene := load(BASE_FBX) as PackedScene
	if base_scene == null:
		push_error("基础 FBX 未导入: " + BASE_FBX)
		quit(1)
		return
	var src := base_scene.instantiate()
	var src_skel := _find_first(src, "Skeleton3D") as Skeleton3D
	if src_skel == null:
		push_error("基础 FBX 无 Skeleton3D")
		quit(1)
		return
	# 根：AvatarRig
	var rig := Node3D.new()
	rig.name = "AvatarRig"
	rig.set_script(load("res://modules/avatar/assembly/avatar_rig.gd"))
	rig.set("slot_table", load("res://modules/avatar/data/slot_table.tres"))
	# 骨架：复制骨骼（不带任何网格子节点）
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	for i in src_skel.get_bone_count():
		skel.add_bone(src_skel.get_bone_name(i))
	for i in src_skel.get_bone_count():
		skel.set_bone_parent(i, src_skel.get_bone_parent(i))
		skel.set_bone_rest(i, src_skel.get_bone_rest(i))
		skel.set_bone_pose_position(i, src_skel.get_bone_rest(i).origin)
		skel.set_bone_pose_rotation(i, src_skel.get_bone_rest(i).basis.get_rotation_quaternion())
	rig.add_child(skel)
	skel.owner = rig
	# 动画库
	var lib := AnimationLibrary.new()
	for key in ANIM_FBX:
		var anim_scene := load(ANIM_FBX[key]) as PackedScene
		if anim_scene == null:
			push_error("动画 FBX 未导入: " + ANIM_FBX[key])
			quit(1)
			return
		var anim_inst := anim_scene.instantiate()
		var player := _find_first(anim_inst, "AnimationPlayer") as AnimationPlayer
		if player == null or player.get_animation_list().is_empty():
			push_error("动画 FBX 无动画: " + ANIM_FBX[key])
			anim_inst.free()
			quit(1)
			return
		var anim := player.get_animation(player.get_animation_list()[0]).duplicate(true) as Animation
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(key, anim)
		anim_inst.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/avatar/base"))
	ResourceSaver.save(lib, OUT_LIB)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	rig.add_child(ap)
	ap.owner = rig
	ap.add_animation_library("", load(OUT_LIB))
	var packed := PackedScene.new()
	packed.pack(rig)
	var err := ResourceSaver.save(packed, OUT_SCENE)
	src.free()
	rig.free()
	print("base_rig 生成完成 err=%d 骨骼数=%d" % [err, skel.get_bone_count()])
	quit(0 if err == OK else 1)

func _find_first(root: Node, klass: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(klass):
			return n
		for c in n.get_children():
			stack.append(c)
	return null
```

**已知风险与对策**：导入的动画轨道路径形如 `Skeleton3D:Root_M`，依赖动画 FBX 内骨架节点名与 base_rig 的 `Skeleton3D` 一致；若实际导入名不同（如 `RootNode/Skeleton3D`），在本脚本中对每条轨道调用 `anim.track_set_path(t, NodePath("Skeleton3D:" + 原骨骼名))` 重写路径——执行时用 `anim.get_track_count()`/`track_get_path` 打印确认后处理。

- [ ] **Step 2: 运行生成**

```bash
godot --headless --path . --script res://tools/pipeline/gen_base_rig.gd
godot --headless --path . --import
```
Expected: `base_rig 生成完成 err=0 骨骼数=62`。

- [ ] **Step 3: 写测试 `tests/pipeline/test_base_rig.gd`**

```gdscript
extends GdUnitTestSuite

const RIG_SCENE := "res://assets/avatar/base/base_rig.tscn"

func test_base_rig_structure() -> void:
	if not FileAccess.file_exists(RIG_SCENE):
		push_warning("base_rig 未生成，跳过")
		return
	var rig := (load(RIG_SCENE) as PackedScene).instantiate() as AvatarRig
	add_child(auto_free(rig))
	assert_object(rig.skeleton).is_not_null()
	assert_int(rig.skeleton.get_bone_count()).is_equal(62)
	assert_int(rig.skeleton.find_bone("Head_M")).is_not_equal(-1)
	assert_int(rig.skeleton.find_bone("Wrist_L")).is_not_equal(-1)

func test_animations_present_and_play() -> void:
	if not FileAccess.file_exists(RIG_SCENE):
		return
	var rig := (load(RIG_SCENE) as PackedScene).instantiate()
	add_child(auto_free(rig))
	var ap := rig.get_node("AnimationPlayer") as AnimationPlayer
	for anim_name in ["idle", "walk", "run"]:
		assert_bool(ap.has_animation(anim_name)).is_true()
	ap.play("idle")
	var skel := rig.get_node("Skeleton3D") as Skeleton3D
	var before := skel.get_bone_pose_position(skel.find_bone("Root_M"))
	for i in 30:
		await get_tree().process_frame
	assert_bool(ap.is_playing()).is_true()

func test_slot_table_bones_exist_in_skeleton() -> void:
	if not FileAccess.file_exists(RIG_SCENE):
		return
	var rig := (load(RIG_SCENE) as PackedScene).instantiate() as AvatarRig
	add_child(auto_free(rig))
	var table: AvatarSlotTable = load("res://modules/avatar/data/slot_table.tres")
	for s in table.slots:
		assert_int(rig.skeleton.find_bone(s.attach_bone)).is_not_equal(-1)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `tools/run_tests.sh res://tests/pipeline`
Expected: 全 PASS。若 `test_slot_table_bones_exist_in_skeleton` 失败（骨骼名与实际 62 骨清单不符），按测试输出修正 `slot_table.tres` 的 `attach_bone`（以导入骨架实际名为准），重跑。

- [ ] **Step 5: Commit**

```bash
git add tools/pipeline/gen_base_rig.gd assets/avatar/base tests/pipeline/test_base_rig.gd
git commit -m "feat(pipeline): base_rig 场景生成(62骨骨架+idle/walk/run 动画库)"
```

---

### Task 13: AvatarService 门面 + 换装场景与 UI

**Files:**
- Create: `modules/avatar/avatar_service.gd`（autoload）
- Create: `scenes/dressing_room/dressing_room.tscn`, `scenes/dressing_room/dressing_room.gd`, `scenes/dressing_room/parts_panel.gd`
- Modify: `project.godot`（注册 autoload `Avatar`；`run/main_scene` 设为换装场景）
- Test: `tests/integration/test_dressing_flow.gd`

**Interfaces:**
- Consumes: 全部前序产物（catalog/loader/cache/store/rig/base_rig.tscn/manifest）
- Produces: autoload 单例 `Avatar`（`AvatarService`）:
  - `var catalog: PartCatalog`, `var loader: PartLoader`, `var cache: PartCache`, `var store: LocalOutfitStore`, `var slot_table: AvatarSlotTable`, `var user_id: String = "local"`
  - `create_rig() -> AvatarRig`（实例化 base_rig.tscn 并 `setup(loader)`；调用方负责 add_child）
  - `load_outfit() -> AvatarConfig`（存档→无档回默认 `slot_table.default_config()`）
  - `save_outfit(config: AvatarConfig) -> Error`
  - 方法签名即二期消息桥的映射面（对应 Unity DressingManager）

- [ ] **Step 1: 实现 `modules/avatar/avatar_service.gd` 并注册 autoload**

```gdscript
extends Node
## Autoload 名: Avatar —— avatar 模块唯一门面。
## 二期原生嵌入时，消息桥只与本类交互。

const MANIFEST_PATH := "res://assets/avatar/parts_manifest.json"
const BASE_RIG_SCENE := "res://assets/avatar/base/base_rig.tscn"

var slot_table: AvatarSlotTable = preload("res://modules/avatar/data/slot_table.tres")
var catalog: PartCatalog
var cache := PartCache.new()
var store := LocalOutfitStore.new()
var loader: PartLoader
var user_id := "local"

func _ready() -> void:
	catalog = PartCatalog.load_from_file(MANIFEST_PATH)
	if catalog == null:
		push_error("AvatarService: manifest 加载失败，先运行转换管线")
		catalog = PartCatalog.new()
	loader = PartLoader.new()
	loader.name = "PartLoader"
	loader.catalog = catalog
	loader.cache = cache
	add_child(loader)

func create_rig() -> AvatarRig:
	var rig := (load(BASE_RIG_SCENE) as PackedScene).instantiate() as AvatarRig
	rig.setup(loader)
	return rig

func load_outfit() -> AvatarConfig:
	var cfg := store.load_outfit(user_id)
	return cfg if cfg != null else slot_table.default_config()

func save_outfit(config: AvatarConfig) -> Error:
	return store.save_outfit(user_id, config)
```

`project.godot` 增加：
```ini
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"

[application]
run/main_scene="res://scenes/dressing_room/dressing_room.tscn"
```

- [ ] **Step 2: 建换装场景**

`scenes/dressing_room/dressing_room.tscn` 节点树（在 .tscn 中直接编写）：
```
DressingRoom (Node3D, script=dressing_room.gd)
├── Camera3D            transform: 位于 (0, 1.2, 2.2) 朝向原点
├── DirectionalLight3D  rotation_degrees: (-45, 30, 0)
├── WorldEnvironment    environment: 内嵌 Environment(背景纯色 #2a2a30, ambient 0.6)
├── RigAnchor (Node3D)  # AvatarRig 运行时挂这里；拖动旋转作用于它
└── UI (CanvasLayer)
    └── Panel (右侧, anchors 右缘 40% 宽)
        └── VBox (VBoxContainer, script=parts_panel.gd)
            ├── SlotTabs (HBoxContainer)      # parts_panel.gd 动态填充
            ├── PartsScroll (ScrollContainer, v_expand)
            │   └── PartsGrid (GridContainer, columns=3)
            └── Buttons (HBoxContainer)
                ├── SaveButton (Button, text="保存")
                └── ResetButton (Button, text="重置")
```

`scenes/dressing_room/dressing_room.gd`:
```gdscript
extends Node3D

@onready var anchor: Node3D = $RigAnchor
@onready var parts_panel = $UI/Panel/VBox
var rig: AvatarRig
var _dragging := false

func _ready() -> void:
	rig = Avatar.create_rig()
	anchor.add_child(rig)
	rig.apply_config(Avatar.load_outfit())
	$UI/Panel/VBox/Buttons/SaveButton.pressed.connect(_on_save)
	$UI/Panel/VBox/Buttons/ResetButton.pressed.connect(_on_reset)
	parts_panel.setup(rig)

func _on_save() -> void:
	var err := Avatar.save_outfit(rig.current_config())
	print("保存结果: %d" % err)

func _on_reset() -> void:
	rig.apply_config(Avatar.slot_table.default_config())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		anchor.rotate_y(-event.relative.x * 0.01)
	elif event is InputEventScreenDrag:
		anchor.rotate_y(-event.relative.x * 0.01)
```

`scenes/dressing_room/parts_panel.gd`（挂在 VBox 上）:
```gdscript
extends VBoxContainer
## 槽位标签页 + 部件网格。数据只来自 slot_table 与 PartCatalog（元数据+缩略图）。

var rig: AvatarRig
var current_slot: StringName

@onready var tabs: HBoxContainer = $SlotTabs
@onready var grid: GridContainer = $PartsScroll/PartsGrid

func setup(p_rig: AvatarRig) -> void:
	rig = p_rig
	for slot_def in Avatar.slot_table.slots:
		if Avatar.catalog.parts_for_slot(slot_def.slot_name).is_empty():
			continue
		var b := Button.new()
		b.text = String(slot_def.slot_name)
		b.pressed.connect(_show_slot.bind(slot_def.slot_name))
		tabs.add_child(b)
	if tabs.get_child_count() > 0:
		_show_slot(StringName(tabs.get_child(0).text))

func _show_slot(slot: StringName) -> void:
	current_slot = slot
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var slot_def := Avatar.slot_table.slot(slot)
	if slot_def and not slot_def.required:
		var none_btn := Button.new()
		none_btn.text = "卸下"
		none_btn.custom_minimum_size = Vector2(96, 96)
		none_btn.pressed.connect(func(): rig.unequip(slot))
		grid.add_child(none_btn)
	for meta in Avatar.catalog.parts_for_slot(slot):
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 96)
		b.tooltip_text = meta.id
		var tex: Texture2D = load(meta.thumb_path) if meta.thumb_path != "" and ResourceLoader.exists(meta.thumb_path) else null
		if tex:
			b.icon = tex
			b.expand_icon = true
		else:
			b.text = meta.id
		b.pressed.connect(func(): rig.equip(current_slot, meta.id))
		grid.add_child(b)
```

- [ ] **Step 3: 写集成测试 `tests/integration/test_dressing_flow.gd`**

```gdscript
extends GdUnitTestSuite
## 全链路：默认装 → 换件 → 保存 → 重建 rig → 读档恢复。依赖转换产物，缺失则跳过。

func test_full_dressing_flow() -> void:
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		push_warning("转换产物缺失，跳过集成测试")
		return
	Avatar.store.base_dir = "user://test_integration"
	Avatar.user_id = "it_user"
	var rig := Avatar.create_rig()
	add_child(auto_free(rig))
	rig.apply_config(Avatar.load_outfit())
	var applied := []
	rig.config_applied.connect(func(c): applied.append(c))
	for i in 600:
		if applied.size() > 0:
			break
		await get_tree().process_frame
	assert_int(applied.size()).is_equal(1)
	assert_bool(rig.visible).is_true()
	# 挑一个 cloth 槽的非当前部件换上
	var candidates := Avatar.catalog.parts_for_slot(&"cloth")
	assert_bool(candidates.size() >= 2).is_true()
	var target := ""
	for meta in candidates:
		if meta.id != rig.current_config().slots[&"cloth"]:
			target = meta.id
			break
	rig.equip(&"cloth", target)
	var slots_applied := []
	rig.slot_applied.connect(func(s, p): slots_applied.append([s, p]))
	for i in 600:
		if slots_applied.size() > 0:
			break
		await get_tree().process_frame
	assert_str(rig.current_config().slots[&"cloth"]).is_equal(target)
	# 保存 → 读回
	assert_int(Avatar.save_outfit(rig.current_config())).is_equal(OK)
	var loaded := Avatar.load_outfit()
	assert_str(loaded.slots[&"cloth"]).is_equal(target)
	# 合并策略下骨架下应只有一个 merged_mesh + 若干 socket_*
	var mesh_children := 0
	for c in rig.skeleton.get_children():
		if c is MeshInstance3D:
			mesh_children += 1
	assert_int(mesh_children).is_equal(1)
```

- [ ] **Step 4: 运行验证**

Run: `tools/run_tests.sh res://tests/integration`，然后 `godot --path . --quit-after 300`（有头环境可肉眼看一帧换装场景；headless 环境跳过肉眼步骤）
Expected: 集成测试 PASS；主场景能启动无报错。

- [ ] **Step 5: Commit**

```bash
git add modules/avatar/avatar_service.gd scenes/dressing_room project.godot tests/integration
git commit -m "feat(avatar): AvatarService 门面 + 换装场景/UI + 全链路集成测试"
```

---

### Task 14: 活动度控制 + 压测场景 + 文档

**Files:**
- Create: `modules/avatar/assembly/rig_activity.gd`
- Create: `scenes/stress_test/stress_test.tscn`, `scenes/stress_test/stress_test.gd`
- Create: `README.md`, `docs/mobile_export.md`
- Test: `tests/assembly/test_rig_activity.gd`

**Interfaces:**
- Consumes: `AvatarRig`、`base_rig.tscn`、`PartCatalog`
- Produces:
  - `RigActivity`（Node，挂到 AvatarRig 下）: `@export var reduced_distance := 8.0`, `@export var sleep_distance := 16.0`；每 0.25s 依据「相机距离 + `VisibleOnScreenNotifier3D`」输出 `enum Level {ACTIVE, REDUCED, SLEEP}`；`signal level_changed(level: int)`。作用：ACTIVE=动画播放+T1 socket 动画播放+T2 粒子发射；REDUCED=主动画播放、T1 暂停、T2 停发射；SLEEP=全部暂停。
  - 压测场景：数量滑条(1–20)、direct/merged 切换按钮、HUD（FPS/frame time/draw calls/显存/角色数）

- [ ] **Step 1: 写失败测试 `tests/assembly/test_rig_activity.gd`**

```gdscript
extends GdUnitTestSuite

func test_levels_by_distance() -> void:
	var act := RigActivity.new()
	act.reduced_distance = 8.0
	act.sleep_distance = 16.0
	assert_int(act.level_for(3.0, true)).is_equal(RigActivity.Level.ACTIVE)
	assert_int(act.level_for(10.0, true)).is_equal(RigActivity.Level.REDUCED)
	assert_int(act.level_for(20.0, true)).is_equal(RigActivity.Level.SLEEP)
	assert_int(act.level_for(3.0, false)).is_equal(RigActivity.Level.SLEEP)
	act.free()

func test_apply_level_pauses_players() -> void:
	var rig := AvatarRig.new()
	var t := AvatarSlotTable.new()
	rig.slot_table = t
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	skel.add_bone("Root_M")
	rig.add_child(skel)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	rig.add_child(ap)
	add_child(auto_free(rig))
	rig.skeleton = skel
	var act := RigActivity.new()
	rig.add_child(act)
	act.apply_level(RigActivity.Level.SLEEP)
	assert_bool(ap.playback_active).is_false()
	act.apply_level(RigActivity.Level.ACTIVE)
	assert_bool(ap.playback_active).is_true()
```

- [ ] **Step 2: 运行确认失败**

Run: `tools/run_tests.sh res://tests/assembly`
Expected: 新用例 FAIL。

- [ ] **Step 3: 实现 `modules/avatar/assembly/rig_activity.gd`**

```gdscript
class_name RigActivity
extends Node
## 角色活动度三档控制：按屏幕可见性+相机距离节流动画/粒子。
## 挂在 AvatarRig 下；rig 上所有 AnimationPlayer/GPUParticles3D 的播放权归本节点。

enum Level { ACTIVE, REDUCED, SLEEP }

@export var reduced_distance := 8.0
@export var sleep_distance := 16.0
@export var check_interval := 0.25

signal level_changed(level: int)

var current_level: int = Level.ACTIVE
var _accum := 0.0
var _notifier: VisibleOnScreenNotifier3D

func _ready() -> void:
	var rig := get_parent() as Node3D
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))
	rig.add_child.call_deferred(_notifier)

func _process(delta: float) -> void:
	_accum += delta
	if _accum < check_interval:
		return
	_accum = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rig := get_parent() as Node3D
	var dist := cam.global_position.distance_to(rig.global_position)
	var visible_on_screen := _notifier.is_on_screen() if _notifier and _notifier.is_inside_tree() else true
	var lv := level_for(dist, visible_on_screen)
	if lv != current_level:
		apply_level(lv)

func level_for(distance: float, on_screen: bool) -> int:
	if not on_screen or distance > sleep_distance:
		return Level.SLEEP
	if distance > reduced_distance:
		return Level.REDUCED
	return Level.ACTIVE

func apply_level(level: int) -> void:
	current_level = level
	var rig := get_parent()
	var main_player := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if main_player:
		main_player.playback_active = (level != Level.SLEEP)
	_apply_recursive(rig, level)
	level_changed.emit(level)

func _apply_recursive(node: Node, level: int) -> void:
	for c in node.get_children():
		if c == self:
			continue
		if c is AnimationPlayer and c.get_parent() != get_parent():
			# socket 部件内的 T1 动画：仅 ACTIVE 时播放
			(c as AnimationPlayer).playback_active = (level == Level.ACTIVE)
			if level == Level.ACTIVE and not (c as AnimationPlayer).is_playing():
				var list := (c as AnimationPlayer).get_animation_list()
				if list.size() > 0:
					(c as AnimationPlayer).play(list[0])
		elif c is GPUParticles3D:
			(c as GPUParticles3D).emitting = (level == Level.ACTIVE)
		_apply_recursive(c, level)
```

- [ ] **Step 4: 建压测场景**

`scenes/stress_test/stress_test.tscn` 节点树：
```
StressTest (Node3D, script=stress_test.gd)
├── Camera3D (0, 4, 10) 俯视原点
├── DirectionalLight3D
├── WorldEnvironment（同换装场景 Environment）
├── Floor (MeshInstance3D, PlaneMesh 40x40, StandardMaterial3D 灰)
├── Rigs (Node3D)
└── HUD (CanvasLayer)
    └── VBox (VBoxContainer, 左上)
        ├── StatsLabel (Label)
        ├── CountSlider (HSlider, min=1, max=20, value=10, step=1)
        └── StrategyButton (Button, text="策略: merged")
```

`scenes/stress_test/stress_test.gd`:
```gdscript
extends Node3D

@onready var rigs_root: Node3D = $Rigs
@onready var stats: Label = $HUD/VBox/StatsLabel
@onready var slider: HSlider = $HUD/VBox/CountSlider
@onready var strategy_btn: Button = $HUD/VBox/StrategyButton

var _merged := true
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 20260821  # 固定种子，压测可复现
	slider.value_changed.connect(func(v): _respawn(int(v)))
	strategy_btn.pressed.connect(_toggle_strategy)
	_respawn(int(slider.value))

func _toggle_strategy() -> void:
	_merged = not _merged
	strategy_btn.text = "策略: %s" % ("merged" if _merged else "direct")
	_respawn(rigs_root.get_child_count())

func _respawn(count: int) -> void:
	for c in rigs_root.get_children():
		rigs_root.remove_child(c)
		c.queue_free()
	Avatar.cache.clear()
	var side := int(ceil(sqrt(float(count))))
	for i in count:
		var rig := Avatar.create_rig()
		rig.assembler = AvatarAssemblerMerged.new() if _merged else AvatarAssemblerDirect.new()
		rig.position = Vector3((i % side) * 1.5 - side * 0.75, 0, (i / side) * 1.5)
		rigs_root.add_child(rig)
		rig.add_child(RigActivity.new())
		rig.apply_config(_random_config())
		rig.config_applied.connect(func(_c):
			var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap:
				ap.play("walk" if _rng.randf() > 0.5 else "idle"))

func _random_config() -> AvatarConfig:
	var cfg := Avatar.slot_table.default_config()
	for slot_def in Avatar.slot_table.slots:
		var pool := Avatar.catalog.parts_for_slot(slot_def.slot_name)
		if pool.is_empty():
			continue
		if slot_def.required or _rng.randf() > 0.5:
			cfg.slots[slot_def.slot_name] = pool[_rng.randi_range(0, pool.size() - 1)].id
	return cfg

func _process(_delta: float) -> void:
	stats.text = "角色: %d  策略: %s\nFPS: %d  帧时: %.2fms\nDrawCalls: %d\n显存: %.1fMB" % [
		rigs_root.get_child_count(),
		"merged" if _merged else "direct",
		Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
	]
```

- [ ] **Step 5: 运行测试 + 桌面冒烟**

Run: `tools/run_tests.sh` 全量；有头环境 `godot --path . res://scenes/stress_test/stress_test.tscn` 观察 HUD 数字、切换策略对比 draw calls。
Expected: 全 PASS；merged 策略 draw calls 显著低于 direct。

- [ ] **Step 6: 写 `README.md` 与 `docs/mobile_export.md`**

`README.md` 内容要点（简短）：项目定位、目录结构、跑测试（`tools/run_tests.sh`）、跑转换管线（Task 10/11/12 的三条命令）、两个场景怎么开、压测数据怎么读。
`docs/mobile_export.md` 内容要点：安装 4.7.2 export templates；Android preset（ETC2/ASTC、arm64-v8a、调试签名即可）；iOS preset（team id 占位、ASTC）；真机验收步骤 = 打开压测场景→15 角色 merged→记录 FPS/帧时/显存 到表格（策略×角色数×机型）；已知一期不含 PCK 下载。

- [ ] **Step 7: Commit**

```bash
git add modules/avatar/assembly/rig_activity.gd scenes/stress_test tests/assembly/test_rig_activity.gd README.md docs/mobile_export.md
git commit -m "feat(avatar): 活动度三档控制 + 压测场景(策略对比HUD) + 文档"
```

---

## 一期验收对照（全部任务完成后核对）

| spec 验收项 | 对应 |
|---|---|
| 转换工具跑通样例集，报告干净 | Task 10 Step 5 + Task 11 Step 2 |
| 换装：列表→切换（异步无闪烁）→保存→重启恢复 | Task 13 集成测试 + 手动走查 |
| 压测：15 角色 merged 帧率数据（真机 iOS/Android） | Task 14 + docs/mobile_export.md 人工步骤 |
| 单测全绿 | `tools/run_tests.sh` |

## 风险与对策备忘

1. **gdUnit4 与 4.7 兼容**：Task 1 若失败改用 master 最新 tag。
2. **FBX 导入差异**（ufbx 对 Tuanjie 导出 FBX 的兼容、子网格命名、动画轨道路径）：Task 11/12 都有显式报错点与 overrides 兜底；极端情况下把问题 FBX 用 Blender 转 glTF 再入库（工具链改动仅限 convert.py 的 `_stage`）。
3. **合并后蒙皮姿态错误**（bind pose 不一致）：Task 8 的骨骼名重映射用"首见 bind pose"；若样例出现部件间 bind pose 不一致导致变形，改为统一取 base body 部件的 bind pose 并在测试中补断言。
4. **性能未达标**：压测 HUD 提供 direct/merged 对比与 draw call 数据，归因方向依次为：surface 数（材质收敛）、阴影/灯光设置、动画开销（活动度阈值）。
