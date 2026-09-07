// 桌面（macOS 编辑器 / 测试）用的空实现：同一个类名与信号，is_available() 恒 false，
// 让 .gdextension 在桌面也有库可载，不然每次启动刷三行「No GDExtension library found」。
// 桌面真正选图走 DisplayServer 的原生文件框（PhotoPicker._pick_dialog）。
#include "sensen_photo_picker.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

SensenPhotoPicker *SensenPhotoPicker::singleton = nullptr;

SensenPhotoPicker *SensenPhotoPicker::get_singleton() { return singleton; }
SensenPhotoPicker::SensenPhotoPicker() { singleton = this; }
SensenPhotoPicker::~SensenPhotoPicker() { if (singleton == this) singleton = nullptr; }

void SensenPhotoPicker::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &SensenPhotoPicker::is_available);
	ClassDB::bind_method(D_METHOD("is_picking"), &SensenPhotoPicker::is_picking);
	ClassDB::bind_method(D_METHOD("pick_images", "max_count", "max_side", "jpeg_quality"), &SensenPhotoPicker::pick_images, DEFVAL(9), DEFVAL(2048), DEFVAL(0.85f));
	ADD_SIGNAL(MethodInfo("picked", PropertyInfo(Variant::PACKED_STRING_ARRAY, "paths"), PropertyInfo(Variant::STRING, "error")));
}

bool SensenPhotoPicker::is_available() const { return false; }
bool SensenPhotoPicker::is_picking() const { return picking; }
bool SensenPhotoPicker::pick_images(int, int, float) { return false; }
void SensenPhotoPicker::_deliver(const PackedStringArray &paths, const String &error) {
	picking = false;
	emit_signal("picked", paths, error);
}
