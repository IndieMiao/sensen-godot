// C3 Photo Picker（iOS）：PHPickerViewController 薄桥接。不要相册权限、不进 Godot 视口，
// 选完在原生层缩到 max_side 并转 JPEG 落到临时目录，只把路径交回 GDScript。
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class SensenPhotoPicker : public Object {
	GDCLASS(SensenPhotoPicker, Object)

	static SensenPhotoPicker *singleton;
	bool picking = false;

protected:
	static void _bind_methods();

public:
	static SensenPhotoPicker *get_singleton();
	SensenPhotoPicker();
	~SensenPhotoPicker();

	/// 系统有 PHPicker（iOS 14+）且当前没有在选。
	bool is_available() const;
	bool is_picking() const;
	/// 弹系统选图器；结果通过 `picked(paths, error)` 信号回来（取消 = 空数组、空 error）。
	/// 返回 false 表示没弹出来（不可用 / 正在选）。
	bool pick_images(int max_count, int max_side, float jpeg_quality);
	/// 原生层完成后在主线程调用。
	void _deliver(const PackedStringArray &paths, const String &error);
};

} // namespace godot
