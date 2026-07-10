// GDExtension entry point for the Contour kernel (PLAN_ENGINE §3 E2).
//
// The production graduation of native-spike/register_types.cpp: same shape as
// loomkernel's register_types.cpp (native/src/register_types.cpp), renamed to
// the contour identity. Entry symbol `contour_kernel_init` (parallel to
// loomkernel's `loom_kernel_init`) is named by contourkernel.gdext and loaded
// EXPLICITLY via GDExtensionManager — never auto-scanned (see the .gdext note).
#include "contour_kernel.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_contour_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(ContourKernel);
}

void uninitialize_contour_module(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT contour_kernel_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address,
			p_library, r_initialization);
	init_obj.register_initializer(initialize_contour_module);
	init_obj.register_terminator(uninitialize_contour_module);
	init_obj.set_minimum_library_initialization_level(
			MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
