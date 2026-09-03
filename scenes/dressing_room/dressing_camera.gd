class_name DressingCamera
extends Camera3D
## 换装房间相机：窄视角平透视 + **固定参考盒**取景，
## 保证全身完整落在抽屉之上的可用区内，且角色在画面中的比例恒定。
##
## 为什么不按实际包围盒取景（2026-09-02 改）：
## 原来每次 slot_applied 都用 merged_aabb(rig) 重算距离，于是
##   - 换一顶高发型（当时实测 hairhat0 1.721m → hairhat101 1.971m，差 14%）相机就后退，
##     角色在屏幕上忽大忽小；
##   - 拖拽转身时包围盒宽度随朝向变化，画面还会左右"呼吸"。
## 产品口径是"角色在画面中的比例不变"，所以改成对着一个与装扮无关的固定参考盒取景。

const FOV_DEG := 35.0    # 现状 75° 默认值透视过强（头大脚小）

## 取景参考盒：脚底贴地（y=0），按**身体**尺度定，不含高发型的余量。
## 实测身高（2026-09-02 部件池换代后重测）：默认 1.721m，最高的 hairhat20 1.952m。
##
## 这里刻意取 1.80 而不是最高值——把最高发型也塞进参考盒的话，短发角色要连带
## 缩小 15%，头顶会空出一大块死区（试过，很难看）。改成按身体取景：超出的发型
## 向上溢出到顶栏那条带子里。顶栏是透明的、只在左右两端有控件，中间正好留给头发，
## 既不裁切也不浪费画面。真正的底线是"别出画"，由
## test_dressing_room_layout 的 _assert_body_within_usable_area 守。
const REF_HEIGHT := 1.80
const REF_WIDTH := 1.30
## 允许高发型向上溢出参考盒的最大量（米）。溢出部分落在顶栏那条透明带子里，
## 再多就会顶出画面。新增更高的发型/帽子时 test_dressing_camera 会在这里报红。
const HEAD_OVERFLOW := 0.25
## 参考盒是固定的，不再需要给动态包围盒留兜底余量（原值 1.12）。
const PADDING := 1.02
## 抬高机位：占可用区高度的比例。正值把相机沿局部 Y 上移，角色相应下移，
## 视线从原来的腰腹高度抬到胸口附近，头部透视更正、不再是仰视。
## 注意 position.y 与 v_offset 是同一个自由度（v_offset 平移的是相机本身），
## 所以"抬机位"只能通过这个偏置表达，改 position.y 会被 v_offset 抵消掉。
const EYE_LIFT := 0.04

## 分区取景：切到某个分类时推近到对应部位，让用户看清在选什么。
##
## 与"比例不变"的关系：每个分区都是 reference_box() 的**固定**子盒，同样与所装
## 部件无关。所以"换发型不改变大小"在每一档里依然成立——变的只有档位本身，
## 而档位只由用户主动切分类（或点角色）触发，属于预期内的镜头移动。
enum Region { FULL, HEAD, TORSO, FEET }

const FOCUS_TWEEN_S := 0.35

## 当前取景分区；改完要调 reframe() 才生效。
var focus_region: int = Region.FULL

var drawer_height: float = 312.0
var safe_margin_top: float = 16.0
var safe_margin_bottom: float = 16.0

var _tween: Tween

func _ready() -> void:
	fov = FOV_DEG
	rotation = Vector3.ZERO

## 分类 → 取景分区。头部两类共用一档：眼镜单独收更紧会好看些，但要多一个
## 需要跟着部件尺寸维护的常量，先合并。
static func region_for_slot(slot: StringName) -> int:
	match slot:
		&"hairHat", &"glass":
			return Region.HEAD
		&"cloth", &"messengerBag":
			return Region.TORSO
		&"shoes":
			return Region.FEET
		_:
			return Region.FULL

## 分区取景盒。
##
## HEAD 的上界取 1.85 而不是覆盖最高发型的 2.05：推近之后画面尺度被放大了近三倍，
## 把最高发型的余量整个留在盒子里，普通发型的头顶就会空出一大块（试过，很明显）。
## 与 FULL 同一套思路——按常见尺寸取景，最高的那几顶向上溢出到顶栏那条透明带子里。
static func region_box(region: int) -> AABB:
	match region:
		Region.HEAD:
			return _span(1.12, 1.85, 0.62)
		# 竖屏视口很窄（宽/高 ≈ 0.46），"矮而宽"的盒子会被宽度约束反推出很远的距离，
		# 纵向就多框进一大截无关的身体。TORSO / FEET 都刻意做窄，让高度成为约束项。
		#
		# ⚠️ 这不只是好不好看的问题：UIMetrics.frame_distance 取 max(高约束, 宽约束)，
		# 而 frame_v_offset 是**按被摄体正好填满 ratio** 推的。一旦宽度成为约束项，
		# 被摄体实际填不满 ratio，v_offset 就会把它推偏（表现为整体上移）。
		# 调这几个盒子时保持"高瘦"，否则得先把 frame_v_offset 一起改对。
		Region.TORSO:
			return _span(0.62, 1.38, 0.74)
		Region.FEET:
			return _span(0.0, 0.62, 0.42)
		_:
			return _span(0.0, REF_HEIGHT, REF_WIDTH)

static func _span(y0: float, y1: float, w: float) -> AABB:
	return AABB(Vector3(-w * 0.5, y0, -w * 0.5), Vector3(w, maxf(y1 - y0, 0.001), w))

## 合并 root 子树内所有可见 GeometryInstance3D（真实渲染几何：网格/粒子/文字等）的
## 全局包围盒。用 GeometryInstance3D 而非 VisualInstance3D 是为了排除
## VisibleOnScreenNotifier3D / VisibleOnScreenEnabler3D 这类只继承 VisualInstance3D、
## 但不产生任何渲染像素的节点——RigActivity 会挂一个硬编码剔除框的 Notifier3D 到 rig 下
## （modules/avatar/assembly/rig_activity.gd），若不过滤会把取景撑大到它的 AABB。
## 子树为空或全不可见时返回 size 为 0 的退化 AABB，调用方据此跳过取景。
static func merged_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var found := false
	for node in _visuals(root):
		var box := node.get_global_transform() * node.get_aabb()
		if found:
			out = out.merge(box)
		else:
			out = box
			found = true
	return out

static func _visuals(node: Node) -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	var vi := node as GeometryInstance3D
	if vi and vi.is_visible_in_tree():
		result.append(vi)
	for c in node.get_children():
		result.append_array(_visuals(c))
	return result

## 与装扮无关的取景参考盒。脚底贴地，水平以角色原点为中心。
static func reference_box() -> AABB:
	return region_box(Region.FULL)

## 重新取景。viewport_size 由调用方传入而非内部取，便于 headless 测试。
##
## subject_root 只用来判断"有没有东西可拍"——取景尺寸一律用 region_box(focus_region)，
## 不读它的实际包围盒，换装因此不会改变角色在画面中的大小。
## animate=true 用于用户主动切分区（补间推拉）；布局变化走 false 直接落位。
func reframe(subject_root: Node3D, viewport_size: Vector2, animate := false) -> void:
	if merged_aabb(subject_root).size.y <= 0.0:
		return
	var ratios := UIMetrics.free_ratios(
		viewport_size.y, safe_margin_top, safe_margin_bottom, drawer_height)
	if ratios.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# 机位上抬要在可用区上下各让出 EYE_LIFT，否则角色下移后脚会顶进抽屉。
	var lift := ratios.x * EYE_LIFT
	var usable := ratios.x - 2.0 * lift
	if usable <= 0.0:
		return
	var subject := region_box(focus_region)
	var dist := UIMetrics.frame_distance(
		subject, viewport_size.x / viewport_size.y, usable, FOV_DEG, PADDING)
	if dist <= 0.0:
		return
	var center := subject.position + subject.size * 0.5
	var target_position := Vector3(center.x, center.y, center.z + dist)
	var target_v_offset := UIMetrics.frame_v_offset(subject, usable, ratios.y + lift, PADDING)
	fov = FOV_DEG
	rotation = Vector3.ZERO
	if _tween and _tween.is_valid():
		_tween.kill()
	if not animate or not is_inside_tree():
		position = target_position
		v_offset = target_v_offset
		return
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position", target_position, FOCUS_TWEEN_S)
	_tween.tween_property(self, "v_offset", target_v_offset, FOCUS_TWEEN_S)
