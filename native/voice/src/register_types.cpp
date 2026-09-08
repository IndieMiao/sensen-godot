#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "sensen_voice.h"

using namespace godot;

static SensenVoice *voice_singleton = nullptr;

void initialize_sensen_voice(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(SensenVoice);
	voice_singleton = memnew(SensenVoice);
	Engine::get_singleton()->register_singleton("SensenVoice", voice_singleton);
}

void uninitialize_sensen_voice(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Engine::get_singleton()->unregister_singleton("SensenVoice");
	memdelete(voice_singleton);
	voice_singleton = nullptr;
}

extern "C" {
GDExtensionBool GDE_EXPORT sensen_voice_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_sensen_voice);
	init_obj.register_terminator(uninitialize_sensen_voice);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
